# コアデータモデル・RLS設計案

> [!IMPORTANT]
> この文書はコアDB設計と各Phaseの設計根拠を残す履歴・設計資料です。
> 現在の正式仕様は[`my-diary_spec_v2.2.md`](../../my-diary_spec_v2.2.md)、現在の実装状態は[`current-implementation-status.md`](../project/current-implementation-status.md)を参照してください。
> 本文中のmigration件数や「未作成」等の記述は、明示した当該Phase時点の記録であり、repositoryの現在値とは限りません。

## 対象と前提

この設計案は、最初のデータベース単位として `accounts`、`profiles`、
`posts`、`follows` から開始した。その後、リアクション、コメント、自由タグ、
投稿画像とStorageを後続migrationで追加し、投稿画像はPhase B3a〜B3dまで完了した。
Phase C2cで通知DB / RLS基盤、通知生成、通知UIを追加し、Phase C3bでtimezone設定とDB validation境界を追加した。この段階では通報は未作成であった。自由タグの後続Phase B1設計は本書の
「自由タグPhase B1追加設計」と「自由タグPhase B2a atomic mutation設計」に記録する。

全体公開投稿を含めて閲覧はログイン必須とする。`anon` にはpublic application tableの
権限を付与せず、`authenticated` に対してもRLSと列権限の両方で制御する。

初回schemaからPhase C4b-1までの21件は、当該Phase時点でリンク済みのリモート開発Supabaseへ適用済みである。
latestは`20260810000100_add_location_name_atomic_mutation.sql`で、repository / local / remoteの
migration履歴は一致している。

### 投稿画像基盤の現在状態

- Phase B3a: private `post-images` bucket、`post_images`、RLS、Storage SELECT、最大10枚のDB保証
- Phase B3b: JPEG / PNG / WebP、1枚6 MiB、Storage INSERT、未参照orphan DELETE、`my_diary_create_post_with_images`によるatomic create
- Phase B3c: same-origin authenticated delivery、post_images RLSとStorage SELECT RLSの取得ごとの再評価、private no-store、raw `storage_path`のserver内限定
- Phase B3d: `my_diary_update_post_with_images`、最終manifest、post rowの`FOR UPDATE`、保持image identity、`sort_order`更新、post / tag / imageのatomic edit、DB commit後のold object cleanup

長期orphanの定期回収、soft delete画像のphysical delete、保持期間後のphysical deleteは
未実装であり、後続のmaintenance / 保持方針として扱う。

## データモデル

### accounts

- `user_id`: `auth.users.id` を参照する主キー
- `role`: `user` / `admin`
- `status`: `active` / `suspended` / `deactivated`
- `timezone`: IANAタイムゾーン名。初期値は `Asia/Tokyo`
- `created_at` / `updated_at`: `TIMESTAMPTZ`

一般ユーザーに許可する更新列は `timezone` だけである。`role` と `status`
はRLSだけに頼らず、PostgreSQLの列権限でも更新を拒否する。管理者による
状態変更は管理機能の設計時に、監査ログと一緒に別途追加する。
Phase C3b以降はDB triggerがPostgreSQLのtimezone catalogへ完全一致する値だけを許可し、
Applicationを迂回するauthenticated direct UPDATEでも無効値を保存できない。

### profiles

- `user_id`: `auth.users.id` を参照する主キー
- `username`: 表示名。1〜50文字
- `bio`: 任意。最大500文字
- `avatar_path`: 任意。将来の非公開Storage内のオブジェクトパス
- `created_at` / `updated_at`: `TIMESTAMPTZ`

MVPではプロフィール自体に機密情報を置かないが、Phase C1a以降は閲覧者と対象者の
双方がactiveの場合だけ閲覧できる。更新はactiveな本人だけに許可する。`username` は表示名として扱うため
重複を許可する。ログインIDとして使う場合は、別の一意なhandle列が必要になる。

### posts

- `id`: UUID主キー
- `user_id`: 投稿者の `auth.users.id`
- `title`: 任意。1〜120文字
- `body`: 必須。1〜10,000文字
- `mood`: 任意
- `location_name`: 任意。1〜100文字
- `visibility`: `private` / `followers` / `public`
- `created_at` / `updated_at` / `deleted_at`: `TIMESTAMPTZ`

気分の保存値と表示は次の対応とする。

| 保存値 | 表示 |
| --- | --- |
| `happy` | 😊 楽しい |
| `sad` | 😢 悲しい |
| `tired` | 😴 疲れた |
| `irritated` | 😡 イライラ |
| `calm` | 😌 穏やか |
| `neutral` | 😐 普通 |

`deleted_at` が設定された投稿は、投稿者本人を含む通常のSELECTから除外する。
一般ユーザーの削除は `deleted_at` を設定するソフトデリートだけとする。
一般ユーザーにはテーブルのDELETE権限を付与せず、DELETEポリシーも作成しない。
また、`deleted_at` の直接UPDATE権限は与えず、所有者とアカウント状態を検証する
`my_diary_soft_delete_post` 関数だけを削除経路とする。
保持期間後の物理削除は、Phase 2の管理・監査設計と一緒に決定する。

### follows

- `follower_id`: フォローする側
- `following_id`: フォローされる側
- `created_at`: `TIMESTAMPTZ`

複合主キーで重複を禁止し、CHECK制約で自己フォローを禁止する。
作成・削除は `follower_id = auth.uid()` の場合だけ許可する。MVPは承認制
ではない。将来承認制を導入する場合は、状態列をこのテーブルへ足すより、
フォローリクエストを別テーブルに分ける案を優先して再検討する。

### notifications（Phase C2c-1）

- `id`: UUID主キー
- `recipient_user_id`: 通知受信者。`accounts.user_id`へCASCADE FK
- `actor_user_id`: 通知を生じさせたuser。`accounts.user_id`へCASCADE FK
- `notification_type`: `follow` / `reaction` / `comment` / `reply`
- `target_post_id`: post target。`posts.id`へCASCADE FK
- `target_comment_id`: comment / reply target。`comments.id`へCASCADE FK
- `is_read`: 既読状態。必須、初期値`false`
- `created_at`: `TIMESTAMPTZ`

genericな`target_type / target_id`は採用しない。MVPの4種類について明示FKを維持し、
DB CHECKでfollowはtargetなし、reactionはpostだけ、comment / replyはpostとcommentの
両方を必須とする。`actor_user_id <> recipient_user_id`もCHECKで保証し、Applicationだけに
自己通知除外を依存させない。commentがtop-levelかreplyか、recipientが正当なownerかという
生成時の意味的整合はC2c-2のtransaction内通知生成経路で保証する。

通常のpost / comment削除はsoft deleteなのでnotification rowを保持する。account、post、commentが
物理削除された場合はCASCADEでnotificationも削除し、dangling UUIDを残さない。reaction rowや
follow relationにはFKせず、reaction解除・種類変更、follow解除・再followの通知semanticsはC2c-2へ持ち越す。

## CHECK制約を採用する理由

`role`、`status`、`mood`、`visibility` はPostgreSQL enumではなく、`text` と
名前付きCHECK制約を使用する。MVPでは候補値が変わる可能性があり、CHECKは
制約の差し替えをトランザクション内で行いやすく、値削除・名称変更に伴う
enum固有の移行制約を避けられるためである。アプリ側では同じ値を
TypeScriptの文字列unionとして生成・管理する予定とする。

## RLSポリシー

### posts SELECT

`deleted_at is null` と閲覧者がactiveであることを前提に、次のいずれかだけを許可する。

1. `posts.user_id = auth.uid()`（activeな投稿者本人）
2. 投稿者も `active` で `visibility = 'public'`
3. 投稿者も `active` で `visibility = 'followers'` かつ、
   `follows` に `(auth.uid(), posts.user_id)` が存在する

`anon` にはテーブル権限もポリシーも付与しないため、公開投稿もログイン必須。
フォロー解除で `follows` 行がなくなると、次のSELECTから即時に閲覧不可になる。
投稿者または閲覧者が`suspended` / `deactivated`の場合、本人所有を含む通常投稿は
すべて非表示になる。statusをactiveへ戻すと、未削除データは通常RLSで再表示される。

### posts作成 / 更新 / ソフトデリート

- 作成: `my_diary_create_post_with_tags` RPCがactiveな`auth.uid()`をownerとして
  postとtag relationを同一transactionで作成する
- 更新: `my_diary_update_post_with_tags` RPCが本人所有・未削除のpostをrow lockし、
  post本体と任意のtag集合を同一transactionで更新する
- ソフトデリート: 本人だけが `my_diary_soft_delete_post` 関数で
  `deleted_at` を設定
- DELETE: 一般ユーザーには権限もRLSポリシーも付与しない

Phase B2a以降、`authenticated`にはpostsの直接INSERT / UPDATE列権限を
付与しない。既存INSERT / UPDATE policyは防御層として維持するが、一般アプリの
作成・更新経路は上記2 RPCだけである。`updated_at` はトリガーで更新する。

### profiles

- SELECT: 閲覧者と対象者がともにactive
- UPDATE: activeな本人だけ
- INSERT / DELETE: 一般ユーザーには許可しない

### Phase C1a DB / RLS fail-closed境界

`20260808000400_fail_close_non_active_accounts.sql`は、non-activeをstatus値の列挙ではなく
`my_diary_is_account_active(...) = false`として扱い、将来statusが増えてもfail-openしない。
posts visibility helperのowner例外、profiles SELECT、SECURITY DEFINER profile検索、
post-images Storageのowned-orphan SELECT / DELETEをactive必須へ変更する。post_tags、tags、
post_images、reactions、comments、tag / post検索は既存のposts RLS委任により閉じる。

non-active本人の`accounts` row SELECTは、C1bが`status`を読んでsign-out / redirectを判断する
最小経路として維持する。他人のaccountsは読めず、non-active本人のtimezone UPDATEも既存の
active条件で拒否する。Phase C1bはこの最小readを通常authenticated clientから使用し、
DB / RLSを最終認可として維持したままapplication session lifecycleをfail-closed化する。

C1a migrationはリンク済みのリモート開発DBへ通常適用済みである。local / remote履歴は
16件で一致し、再dry-runはup to date、remote catalogで変更対象functionのexact signature・
owner・security・volatility・空search path・authenticated専用ACL、accountsの最小status read、
profiles / posts / Storageのactive境界、既存RLS・RPC回帰を確認した。
`public,storage,my_diary_private`のlinked schema diffは空だった。SQL成功後のcatalog cache生成で
一時CAファイルwarningが発生したが、履歴・catalog・再dry-run・schema diffで適用成功と切り分け、
repairや再適用は行っていない。remote fixture、ユーザーデータ、Storage objectは操作せず、
Service RoleとAuth Admin APIも使用していない。

### Phase C1b application session gate

Phase C1bはDB schema、RLS、migrationを変更しない。server側の共通helperは`getClaims()`で
現在のviewer identityを確認した後、そのauthenticated Supabase clientで本人accounts rowの
`status`だけを取得する。clientからuser IDやstatusを受け取らず、shared cacheも使用しない。
`status = 'active'`だけを通常利用へ通し、それ以外の文字列は将来statusを含めてnon-activeとして
扱う。accounts row欠損とquery errorもactiveへ丸めず、それぞれ整合異常・確認失敗として
fail-closedにする。

Auth確立直後はpassword login、即時sessionを返すsign-up、`/auth/callback`で同じhelperを使う。
既存sessionはNext.js Proxyでprotected requestごとに再評価する。Proxyはcookie更新可能な既存の
Supabase SSR境界であるため、non-active検出時はSupabase Authのlocal scope sign-outでcurrent
sessionを終了し、通常pageは固定error code付きloginへ誘導する。画像requestはresource存在や
内部statusを区別しないprivate no-store 404を返す。`next-action` headerを持つServer Action
requestは、通常303ではなくNext.js clientが解釈できる`x-action-redirect` responseでloginへ
退避する。それ以外のnon-GET requestは303を使用する。
login自体で同じerror codeを再評価した場合は、cookieを削除したrequestをそのまま通して
redirect loopを避ける。固定codeだけをUI messageへ変換し、query由来の任意文字列やDB status値を
表示しない。

protected layout単独はClient navigationで再評価されない場合があり、Server Actionと画像Route
Handlerも単独では覆えないため採用しない。Proxyのstatus queryはauthenticated viewerの
protected/auth entry requestに限定し、root、callback確立前、health、static assetでは実行しない。
raceでProxy判定後にstatusが変わった場合も、C1aのRLS / RPC active検証が最終的に通常データの
SELECT / mutationを拒否する。

### Phase C2a comment reply DB基盤

`comments.parent_comment_id uuid nullable`を追加し、`NULL`をtop-level、非`NULL`をreplyとする。
既存行はcolumn追加後もすべてtop-levelであり、データ書き換えは行わない。通常Applicationの
comment作成は既存どおりauthenticatedの直接INSERTを使い、`parent_comment_id`のINSERT列権限だけを
追加する。既存の本人・active viewer・可視postを検証するINSERT RLS policyは変更しない。

`my_diary_private.my_diary_validate_comment_parent()`をcommentsのAFTER INSERT / UPDATE triggerから
呼び出し、parentの存在、same-post、parentがtop-level、未soft-delete、active authorをDBで検証する。
AFTER triggerとすることで既存INSERT RLSが本人・active viewer・可視postを先に拒否し、
不可視post自体へのINSERTではSECURITY DEFINERのparent lookupへ到達させない。可視postへ不可視commentの
UUIDを指定するprobeも含め、parent不存在、cross-post、reply、soft-delete、non-active authorはすべて
SQLSTATE `23514`、message `invalid parent comment`の同じvalidation failureとし、parentの存在・状態・postを
callerへ露出しない。
trigger functionはparent rowを`FOR UPDATE`でlockする。reply INSERTが先ならcommit後にparent soft deleteが
進み、soft deleteが先ならINSERT側は更新後の`deleted_at`を見て拒否するため、検証とsoft deleteの競合を
直列化できる。既存replyのparentを後からsoft deleteする操作は許可し、reply rowと関係値は保持する。

parent relationには自己参照FKを置かない。`ON DELETE CASCADE`はparent作者の物理削除で他ユーザーreplyを
失い、`SET NULL`はreplyをtop-levelへ変え、`RESTRICT` / `NO ACTION`はAuth user削除を阻害し得るためである。
triggerがINSERTと関係更新時の存在・階層を保証する。post物理削除では既存`comments.post_id` FKにより
parentとreplyをともにcascadeし、parent作者だけの物理削除では他ユーザーreplyを非NULLのreplyとして
保持する。parent UUIDは履歴関係として残るが、物理削除後はparent rowを参照できない。

取得用に未削除行の`(post_id, parent_comment_id, created_at, id)` partial indexを追加する。
trigger functionは`SECURITY DEFINER`、owner=`postgres`、`VOLATILE`、`search_path = ''`とし、
`PUBLIC`、`anon`、`authenticated`、`service_role`、`authenticator`からEXECUTEを剥奪してtrigger専用とする。
このためparent commentsとaccounts statusはpostgres権限でRLSを迂回して検証するが、取得値は返さず、
invalid条件は前記のgeneric failureへ集約する。
返信UI・親子取得・通知はC2aでは実装しない。C2a migrationはリンク済みのリモート開発DBへ
初回適用済みで、local / remote履歴17件一致、再dry-runはup to date、remote schema dumpの定義一致、
`public,my_diary_private,storage`のlinked schema diffが空であることを確認した。

### Phase C2c-1 notification DB / RLS基盤

`notifications`はRLSを明示的に有効化し、authenticatedのrecipient本人だけがSELECTできる。
recipient本人とactorの双方が現在activeであることを既存
`my_diary_private.my_diary_is_account_active(uuid)`で確認する。post targetを持つ通知は、
`exists (select 1 from public.posts ...)`を通じて既存posts SELECT RLSへ委任し、follow解除、
visibility変更、post soft delete、post author / viewerのactive状態を次のSELECTから再評価する。
notification policyからpostsへ、posts policyから既存visibility helperへ進む一方向の評価であり、
notificationsへ戻る参照はないためRLS recursionを増やさない。

authenticatedにはtable SELECTと`UPDATE(is_read)`だけを付与する。UPDATE policyもSELECTと同じ
recipient / active / post可視境界を使い、recipient、actor、type、target、created_at等は列権限で
更新を拒否する。anon、一般authenticatedのINSERT / DELETE、INSERT policy、生成RPC、triggerは
作成しない。C2c-1ではSECURITY DEFINER関数を追加していない。通知生成はC2c-2、一覧・未読badge・
すべて既読・遷移UIはC2c-3へ持ち越す。

repository / localは18 migrationで、`20260809000200_create_notifications.sql`をlocal DBへ
incremental適用した後、local resetで18件をfresh適用した。新規pgTAPは`65 / 65`、全pgTAPは
18ファイル`875 / 875 PASS`である。remoteはC2aまでの17 migrationのままで、C2c-1では
remote migration適用、remote schema / fixture変更、Service Role、Auth Admin APIを使用していない。

### Phase C2c-2 notification生成

`20260809000300_generate_notifications.sql`はfollows、reactions、commentsのAFTER INSERTへ
triggerを追加し、follow、reaction、top-level comment、replyをsource mutationと同じtransactionで
notificationsへ生成する。reaction UPDATE / DELETEとfollow DELETEにはtriggerを置かないため、種類変更・
解除では追加通知せず過去通知を維持し、解除後の再INSERTは新しいeventとして別通知を生成する。
commentはpost owner、replyはparent comment authorだけをrecipientとし、replyのtarget_comment_idは
parentではなく新しいreply自身を指す。actorとrecipientが同じ場合はsource mutationを成功させ、通知だけを
生成しない。username、本文、reaction type等のsnapshotとevent間UNIQUE制約は追加しない。

3つのgenerator functionは`my_diary_private`に分離し、`VOLATILE`、`SECURITY DEFINER`、
owner=`postgres`、`search_path=''`、完全修飾objectを使用する。`PUBLIC`、`anon`、`authenticated`、
`service_role`、`authenticator`からEXECUTEを剥奪し、trigger以外の呼出経路を閉じる。trigger入口は
実DB roleが`authenticated`かつ`auth.uid()`がsource actorと一致する場合だけfunctionを呼び、function内でも
identity一致とactor / recipient activeを再検証する。これにより通常Application以外のmigration、fixture、
特権SQLがJWT claimを残していても通知へ変換されない。recipient、actor、targetをClient入力として新たに
受け取らず、authenticatedへのnotifications INSERT grantや公開生成RPCも追加しない。

comment generatorはreply parentの存在、same-post、top-level、未削除、active authorを
`INSERT ... SELECT`の条件として扱い、不正条件で独自errorを出さない。既存C2a validatorがその後に
`FOR UPDATE` lockとgeneric `23514 / invalid parent comment`でsource INSERTを拒否し、先にgeneratorが
実行された場合でも同一transaction rollbackでnotificationは残らない。このため同一timing trigger名の
alphabetical orderに情報非露出保証を依存せず、replyとparent soft deleteの既存直列化も維持する。

local resetで19 migrationをfresh適用し、新規pgTAP `48 / 48`、既存reply `45 / 45`、既存notifications
RLS `65 / 65`、全19ファイル`923 / 923 PASS`を確認した。repository / localは19 migration、linked
remoteはC2c-1まで18 migrationで、C2c-2 migrationは未適用である。remote schema / fixture変更、
Service Role、Auth Admin API、Application / UI変更は行っていない。

### follows

- SELECT: 閲覧者、`follower_id`、`following_id`の3者がすべてactiveの場合のみ
- INSERT / DELETE: `follower_id = auth.uid()` の行だけ
- UPDATE: 許可しない

停止中のユーザーを含む既存関係は削除せずSELECT結果から除外する。両者が
activeへ戻り、関係行が残っている場合は一覧と件数へ再表示される。

### post_images（Phase B3a）

- `id`: UUID主キー
- `post_id`: `posts.id`への外部キー。親postの物理削除時はCASCADE
- `storage_path`: private `post-images` bucket内のobject path。全行で一意
- `sort_order`: 0〜9。`post_id`との組み合わせで一意
- `created_at`: `TIMESTAMPTZ`

`sort_order`の有限な10 slotと`UNIQUE(post_id, sort_order)`を組み合わせ、
件数を数えるtriggerを使わず、同時INSERTでも1投稿最大10枚をDBで保証する。
順序UNIQUEは`DEFERRABLE INITIALLY IMMEDIATE`とし、通常は即時検査しつつ、
後続の並び替えRPCだけがtransaction終端まで遅延してrow identityを保ったswapを
行えるようにする。このUNIQUE indexは投稿単位の安定した並び順取得にも使う。`storage_path`の
UNIQUE indexはpath衝突を防ぎ、Storage policyから対応metadataを検索する。
Phase B3bのpathは`{auth.uid()}/{postId}/{imageId}`の3 UUID segmentとし、元の
ファイル名や拡張子を含めない。JPEG / PNG / WebPだけを許可し、1枚6 MiB以下、
1投稿最大10枚とする。作成時の配列順を`sort_order` 0〜9へ保存する。

`post_images`のSELECT policyは対応する`posts`行が既存posts RLS経由で見えるか
だけを評価する。private / followers / public、follow解除、visibility変更、
soft delete、suspended accountの条件を重複実装しない。authenticatedには
SELECTだけを付与し、INSERT / UPDATE / DELETEのtable権限とpolicyは付与しない。
metadata mutationはuploadとの整合を保つ限定RPC
`my_diary_create_post_with_images`と`my_diary_update_post_with_images`だけで行う。

### 投稿画像Storage（Phase B3a / B3b）

`post-images` bucketはprivateとし、public URLを前提にしない。Phase B3bでbucketへ
JPEG / PNG / WebPと6 MiBの上限を設定した。`storage.objects`のSELECT policyは
bucketを`post-images`に限定し、`objects.name = post_images.storage_path`の
対応metadataがviewerから見える場合だけ許可する。このため認可評価は
`storage.objects → post_images → posts`の一方向となり、pathを知るだけでは
取得できない。authenticatedとanonには別途RESTRICTIVE SELECT guardを設け、
将来別bucket用のPERMISSIVE policyが増えてもOR合成で`post-images`の認可を
迂回できないようにする。

Supabase標準の`storage.buckets` / `storage.objects`のowner、ACL、owner列は
変更しない。B3bのINSERTはStorage APIのupload operation、activeな本人、owner_id、
strict pathをPERMISSIVE / RESTRICTIVE双方で検証する。Phase C1a以降、owned-orphanの
SELECTとDELETEもactiveな本人だけに限定する。DELETEはStorage APIの
delete-many operationかつ同じowner / pathの未参照orphanだけに限定する。UPDATE
policyは作成せず、upsert・overwrite・moveを拒否する。参照判定はprivateな
`SECURITY DEFINER` helperで全post_imagesを確認するため、private・soft delete済み
metadataもorphanとして誤認しない。

新規作成はbrowserから逐次uploadした後、`my_diary_create_post_with_images`が
Storage objectのowner・MIME・sizeを検証して行を`FOR UPDATE`でlockし、post・tag・
post_imagesを同一transactionで確定する。明示的なupload / validation / RPC失敗では
本人のorphanだけを補償削除する。Server Actionの`getClaims()`がRPC開始前に失敗した
場合も、browserへ補償削除を要求し、同じauthenticated clientから今回uploadしたpath
だけを削除する。削除は既存のowner・strict path・未参照orphan境界を通し、権限を
広げない。通信断でRPC結果が不明な場合はcommit済みobjectを誤削除しないため削除せず、
自分の日記一覧で確定結果を確認する。browser側のsessionも失効している場合、browser
終了、cleanup失敗による長期orphanの定期回収は後続Phaseとする。postのsoft deleteでは
metadataとobjectを残してposts RLS連鎖で即時に隠す。

Phase B3cの配信はsigned URLを使わず、extensionlessな同一origin
`/post-images/[imageId]` Route Handlerを採用する。Route Handlerはcookie session由来の
通常authenticated clientで`post_images`をSELECTし、同じclientでStorage downloadを
実行する。これによりpost_imagesとStorageの両RLSをrequestごとに再評価し、follow解除、
visibility変更、soft delete、suspended状態を次回取得へ反映する。invalid UUID、不存在、
RLS拒否、Storage拒否はresource存在を区別しない空bodyの404へfail-closedする。

responseは`Cache-Control: private, no-store, max-age=0`、`X-Content-Type-Options: nosniff`、
`Cross-Origin-Resource-Policy: same-origin`とし、JPEG / PNG / WebPおよび1〜6 MiBを配信時にも
再検証する。clientへ渡すmetadataは画像IDと順序だけで、raw `storage_path`はRoute Handler内に
閉じる。Next.js image optimizerは認証header転送とviewer別cache境界を保証しないため、
表示は同一origin URLを`Image unoptimized`で直接取得し、shared optimizer cacheを通さない。

### accounts

- SELECT: statusがnon-activeでも本人の行だけ。C1bのstatus判定経路として維持する
- UPDATE: activeな本人の `timezone` 列だけ
- INSERT / DELETE: 一般ユーザーには許可しない

### Phase C3b timezone validation境界

`20260809000400_validate_account_timezones.sql`は、
`my_diary_private.my_diary_validate_account_timezone()`を
`accounts`の`BEFORE INSERT OR UPDATE OF timezone` triggerから呼び出す。
保存値は`pg_catalog.pg_timezone_names.name`への完全一致を必須とする。
PostgreSQL内部の重複treeである`posix/*`、将来存在した場合の`right/*`、
現在のNode Intlが扱えない特殊値`Factory`は拒否する。

ローカルPostgreSQL 17.6では`pg_timezone_names` 1196件のうち`posix/*`が598件で、
残る598件をNode 24.12.0の`Intl.DateTimeFormat`へ照合すると非対応は`Factory`だけだった。
`Asia/Tokyo`、`America/New_York`、`Europe/London`、`UTC`と、runtimeが扱える既存aliasを維持できる。
Applicationの新規選択肢は`Intl.supportedValuesOf('timeZone')`に`UTC`を加えた安定sortとし、
保存済みのruntime-valid aliasがcanonical option集合にない場合だけ現在値を追加する。
Server Actionはこのserver-generated集合へ完全一致する入力だけを受理し、DB triggerを最終整合性境界とする。

validatorはcatalog SELECTに追加権限が不要なため`SECURITY INVOKER`とし、owner=`postgres`、
`search_path=''`、完全修飾objectを使用する。`PUBLIC`、`anon`、`authenticated`、
`service_role`、`authenticator`の直接EXECUTEはREVOKEし、trigger以外の呼出経路を閉じる。
既存accounts RLSと`UPDATE(timezone)`列権限は変更せず、active本人だけ更新可能、
他人・suspended・deactivated・role・status更新不可の境界を維持する。

## プロジェクト固有名と既存オブジェクトの保護

`accounts`、`profiles`、`posts`、`follows` は仕様上のテーブル名を維持する。
それ以外のスキーマ、制約、インデックス、関数、トリガー、RLSポリシーには
`my_diary` 接頭辞を付ける。Supabaseで一般的に使われる
`handle_new_auth_user` や `on_auth_user_created` を上書きしないためである。

Auth連携には `public.my_diary_handle_new_auth_user` と
`my_diary_on_auth_user_created` を使用し、一般名の関数やトリガーには
DROP、REPLACE、権限変更を行わない。この初回マイグレーションが管理する
オブジェクトにもDROPやCREATE OR REPLACEを使わず、同名オブジェクトが存在した
場合はトランザクション全体を失敗させる。

初回マイグレーションでは、テーブルにも `IF NOT EXISTS` を使用しない。
既存テーブルの列、制約、所有者、RLSが想定と異なる状態で後続処理だけを進める
より、名前衝突を即座に検出してロールバックする方が安全だからである。
適用済み環境の変更は、このファイルの再実行ではなく後続マイグレーションで行う。

## 権限の初期化

新規作成する4テーブル、`my_diary_private` スキーマ、プロジェクト関数は、
最初に `PUBLIC`、`anon`、`authenticated` から権限を明示的にREVOKEし、
その後 `authenticated` へ必要最小限だけ再付与する。環境ごとのデフォルト権限に
依存せず、RLSと列権限を二重の境界にするためである。

REVOKEの対象はこのマイグレーションが新規作成するオブジェクトだけであり、
`auth`、`storage`、`extensions` などSupabase標準スキーマや標準関数の権限は
変更しない。

## セキュリティ関数

### `my_diary_handle_new_auth_user`

`auth.users` 作成時に同じUUIDの `accounts` と `profiles` を生成し、1対1の
ライフサイクルを保証するトリガー関数。`auth` スキーマから `public`
スキーマへ書き込むため `SECURITY DEFINER` が必要である。
初回適用時点ですでに存在する `auth.users` は、トリガー作成前の
`INSERT ... SELECT ... ON CONFLICT DO NOTHING` で安全に補完する。

危険を抑えるため、引数を受け取らずトリガーの `new.id` だけを使い、
`search_path = ''` と完全修飾名を使用し、`public` の実行権限を剥奪する。
ユーザー由来メタデータから `role` や `status` を設定しない。
所有者は明示的に `postgres` とし、`PUBLIC`、`anon`、`authenticated` の
いずれにもEXECUTEを付与しない。トリガーからの実行だけを許可する。

### `my_diary_private.my_diary_is_account_active`

指定ユーザーの `accounts.status` が `active` かだけを返し、suspended投稿者の
投稿を他ユーザーから隠すために使用する。accountsのRLSを迂回して投稿者状態を
確認する必要があるため `SECURITY DEFINER` とする。

状態列そのものは返さずbooleanだけを返し、`search_path = ''` と完全修飾名を
使用する。また、PostgRESTの公開対象ではない `my_diary_private` スキーマに
配置し、`PUBLIC` と `anon` の実行権限を剥奪する。所有者は `postgres` とし、
`authenticated` にはRLS評価に必要なスキーマUSAGEと関数EXECUTEだけを付与する。

### `my_diary_soft_delete_post`

通常のUPDATEでは、更新後にSELECTポリシー上見えなくなる行を安全に扱えないため、
投稿IDを受け取り、投稿者本人・未削除・activeアカウントを確認して
`deleted_at` を設定する限定RPC関数とする。この狭い操作だけRLSを迂回する必要が
あるため `SECURITY DEFINER` を使用する。

任意SQLや他ユーザーIDは受け取らず、`auth.uid()` と完全修飾名だけを使用する。
`search_path = ''` を固定し、所有者を `postgres` にする。`PUBLIC` と `anon`
の実行権限を剥奪して
`authenticated` だけにEXECUTEを付与する。処理結果は成功・不成功のbooleanで、
投稿内容は返さない。

### `my_diary_set_updated_at`

更新時刻を統一する通常のトリガー関数。追加権限が不要なので
`SECURITY DEFINER` は使用しない。`search_path = ''` は固定する。

## RLS自動有効化の安全網

`20260801000200_manage_rls_auto_enable.sql` は、Dashboard等で作成されて
migration管理外だった `public.rls_auto_enable()` とevent trigger
`ensure_rls` を、既存remoteの定義を検証したうえでmigration管理へ取り込む。
これらは既存の一般名を維持する必要があるため、プロジェクト固有名の原則に
対するbaseline化済みの例外として扱い、renameや無条件再作成は行わない。

`ensure_rls` は `ddl_command_end` で動作し、`public` schemaに対する
`CREATE TABLE`、`CREATE TABLE AS`、`SELECT INTO`のうち、tableまたは
partitioned tableを作成するDDLだけを対象とする。対象relationには
`ENABLE ROW LEVEL SECURITY`だけを実行し、policyの自動作成や
`FORCE ROW LEVEL SECURITY`は行わない。既存tableや、作成後に`public`へ
移されたtableには遡及しない。このため、各migrationでtable作成直後にRLSを
明示的に有効化し、必要なpolicyを定義する既存方針は引き続き必須である。

関数は既存定義どおりownerを`postgres`、`SECURITY DEFINER`、
`search_path=pg_catalog`とする。既定の関数権限により生じる不要な呼び出し経路を
閉じるため、`PUBLIC`、`anon`、`authenticated`、`service_role`、
`authenticator`からEXECUTEをREVOKEし、ownerである`postgres`だけが
EXECUTE可能な状態を維持する。event trigger経由の自動有効化は、このACL
hardening後も動作することをpgTAPで検証する。

既知の制約として、RLS有効化中の例外はLOGへ記録して元のDDLを成功させる
fail-open挙動を維持している。自動有効化に失敗した場合でもtable作成自体は
ロールバックされないため、将来Phaseでfail-closed化を別途検討する。
関数とevent triggerにはbaselineとの差を増やさないためDB commentを追加しない。

## 自由タグPhase B1追加設計

`20260802000100_create_tags.sql`は、自由タグのDB読み取り基盤だけを追加する。
ローカルresetとpgTAPで検証後、リモート開発DBへ適用した。適用後のpg-delta
catalog cache生成ではCLIの証明書参照警告が発生したが、remote migration履歴、
PostgreSQL catalog由来のschema dump、再dry-run、linked schema diffで適用状態と
定義の一致を確認した。
投稿作成・編集へ接続するmutation RPC、1投稿最大5個のDB保証、入力・表示UI、
タグroute、検索はPhase B1に含めない。

### tag nameのcanonical化

`my_diary_private.my_diary_normalize_tag_name(text)`はPostgreSQL標準の
`normalize(..., NFKC)`を使用し、次の順にcanonical nameを返す。

1. Unicode NFKC正規化
2. 前後の半角space除去
3. 1個以上の先頭`#`除去
4. `#`除去後の前後space除去
5. 連続する半角spaceを1個へ集約
6. ASCII `A`〜`Z`だけを小文字化

関数は`IMMUTABLE`、`STRICT`、`PARALLEL SAFE`、`SECURITY INVOKER`、
`search_path = ''`、owner=`postgres`とする。table CHECKからのみ利用するため、
`PUBLIC`、`anon`、`authenticated`、`service_role`、`authenticator`には
EXECUTEを付与しない。同じ処理はTypeScriptで`String.prototype.normalize('NFKC')`
とASCII限定の置換処理により再現できることを既知入力で確認する。

### tags

- `id`: UUID主キー
- `name`: canonical表示名
- `normalized_name`: canonical検索・重複判定名
- `created_at`: `TIMESTAMPTZ`

Phase B1では`name = normalized_name = canonical value`を必須とし、
`normalized_name`へUNIQUE制約を置く。長さは`char_length`で1〜30 Unicode
codepointとする。comma、保存値内の`#`、改行・tabを含むC0/C1制御文字を
拒否する。PostgreSQLの`text`が保持できないNULは入力段階で拒否される。

### post_tags

- `post_id`: `posts.id`へのcascade FK
- `tag_id`: `tags.id`へのcascade FK
- `created_at`: `TIMESTAMPTZ`

`(post_id, tag_id)`を複合主キーとして同一投稿内の重複を禁止する。
tagからpostを逆引きするため`(tag_id, post_id)` indexを置く。Phase B1では
最大5個をtriggerやCHECKで保証せず、後続のatomic mutation RPCと同じ
transactionで保証する。

### tags・post_tagsのRLSとACL

両tableは作成migration内でRLSを明示的に有効化し、`anon`には権限を与えない。
`authenticated`にはSELECTだけをGRANTし、INSERT、UPDATE、DELETEは付与しない。
Phase B1にはmutation policyも作成しない。

`post_tags`のSELECT policyは、同じ`post_id`の`public.posts`行が既存posts RLSで
閲覧可能な場合だけ関係行を返す。`tags`のSELECT policyは、現在のviewerへ
見える`post_tags`が1件以上存在する場合だけtag行を返す。評価方向を
`tags` → `post_tags` → `posts`へ固定し、tagsへ戻るpolicy参照を作らないため、
RLS再帰を発生させない。

この構成により、private投稿、権限のないfollowers投稿、soft-delete済み投稿、
suspended投稿者の投稿だけに紐づくtag名は取得できない。follow解除やvisibility
変更も、既存posts RLSの次回評価から即時に反映される。

### Phase B1 migrationの安全条件

migrationは同名table・関数との衝突、private schema・posts・Supabase roleの
存在をpreflightで確認する。作成後はfunction属性とACL、table owner・列、
制約、cascade FK、reverse index、RLS、policy数、authenticated/anon権限を
postconditionで検証し、不一致ならtransaction全体をrollbackする。

## 自由タグPhase B2a atomic mutation設計

`20260802000200_create_atomic_post_tag_mutation.sql`は、投稿作成・更新と自由タグの
関連付けを1回のPostgREST RPC transactionへまとめる。公開signatureは次の2つで、
overloadとdefault引数は作らない。`location_name`は引数に含めず、作成時は既定の
`NULL`、更新時は既存値を維持する。

```sql
public.my_diary_create_post_with_tags(
  p_title text,
  p_body text,
  p_mood text,
  p_visibility text,
  p_tags text[]
) returns uuid

public.my_diary_update_post_with_tags(
  p_post_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_visibility text,
  p_tags text[]
) returns uuid
```

両関数は`VOLATILE`、`SECURITY DEFINER`、owner=`postgres`、
`search_path = ''`とし、関数内のobjectを完全修飾する。`PUBLIC`、`anon`、
`service_role`、`authenticator`にはEXECUTEを付与せず、`authenticated`だけに
付与する。RLSを迂回する関数であるため、`auth.uid()`の存在、accountのactive状態、
本人所有、未削除を関数内で再検証する。更新対象が存在しない、他人所有、
soft-delete済みのどれかは、同じ認可エラーとして扱う。

### 投稿・タグ入力

投稿値はRPC内で前後の空白を正規化し、既存posts CHECKと同じ上限を
明示的に検証する。titleは`NULL`または1〜120 codepoint、bodyはtrim後
1〜10,000 codepoint、moodは既存6種類または`NULL`、visibilityは既存3種類である。
Server ActionとClient formのvalidationは早いUX feedback用として維持し、DB関数と
CHECKを最終境界とする。

tag配列は1次元、raw最大20要素、配列内`NULL`なしとする。各要素は既存の
`my_diary_private.my_diary_normalize_tag_name(text)`でcanonical化し、空、30 codepoint
超過、comma、canonical値内の`#`、制御文字を拒否する。同じ正規化処理をRPCへ
複製しない。最大5個はcanonical化後に重複排除したdistinct数で数えるため、rawが
6〜20要素でもdistinctが5以下なら受理する。処理順はcanonical名の昇順へ固定し、
tag順序自体は保存しない。

作成では`p_tags IS NULL`と空配列をどちらも「タグなし」とする。更新では次のように
区別する。

- `p_tags IS NULL`: relationをSELECT・DELETE・INSERTせず、現在のtag集合を維持
- 空配列: すべてのrelationを解除
- 非空配列: canonical化後の希望集合へ差分更新

### transaction・lock・差分更新

作成RPCはpost INSERT、tag master解決、post_tags INSERT、uuid返却を同一transactionで
実行する。更新RPCは本人所有かつ未削除のpostを`FOR UPDATE`でlockしてからpost本体と
relationを処理する。同じpostへの更新とsoft deleteはpost row lockで直列化され、
lockはtransaction終了まで保持される。

tag masterはcanonical名の昇順で`INSERT ... ON CONFLICT (normalized_name) DO NOTHING`
を実行し、その後の別statementでIDを取得する。同じ新規tagを作るtransactionが
競合しても不要な`DO UPDATE`を行わず、UNIQUE violationを一般利用者へ露出させない。

更新時は、現在あって希望集合にないrelationだけをDELETEし、希望集合にあって
現在ないrelationだけをINSERTする。共通するrelationは変更せず、既存の
`post_tags.created_at`を維持する。処理途中の例外はpost、tag master、relationを含む
RPC statement全体をrollbackする。relationを外した後も未使用tag masterは自動削除
しない。

`authenticated`のposts直接INSERT / UPDATE列grantを取り消すことで、この2 RPCを
一般アプリの唯一の作成・更新経路とする。RPC内の最大5個検証と更新時row lockにより
一般アプリ経路では最大数をDB側で保証するが、`postgres`等の特権roleによる直接SQL
まで構造的に禁止するconstraint triggerやcounterはPhase B2aでは追加しない。

### Phase B2a migrationの安全条件

migrationは同名RPC/overload、必要table・normalizer・Supabase role、移行前posts列grantを
preflightで確認する。作成後はexact signature、引数名、return型、言語、volatility、
owner、SECURITY DEFINER、固定search_path、comment、ACL、posts/tag table権限を
postconditionで検証し、不一致ならtransaction全体をrollbackする。

## 検索Phase B2b-3a設計

`20260804000100_extend_user_and_tag_search.sql`は、既存ユーザー検索のNFKC対応と、
閲覧可能な自由タグの部分一致検索RPCを追加する。既存table、RLS policy、indexは
変更しない。このmigrationはローカルresetとpgTAPで検証した後、リンク済みの
リモート開発DBへ適用済みである。local / remote migration履歴は11件で一致し、
適用後の再dry-runはup to date、`public,my_diary_private`のlinked schema diffは空である。

### ユーザー検索

`public.my_diary_search_profiles(text)`はsignature、return列、並び順、20件上限、
`SECURITY DEFINER`、owner=`postgres`、`search_path = ''`、authenticated専用ACLを
維持する。Phase C1a以降はviewer自身がactiveでなければ`42501`で拒否し、targetも
active accountだけに限定する。入力と`profiles.username`をNFKC化してから前後空白を除き、
ASCII小文字化した部分一致を行い、`\\`、`%`、`_`はescapeしてliteralとして扱う。

### タグ検索queryとRPC

`my_diary_private.my_diary_normalize_tag_search_query(raw_query text)`は、tag name
normalizerと同じNFKC、前後ASCII space、先頭`#`、連続space、ASCII caseの規則を
検索queryへ適用する。`raw_query`は正規化前のprivate helper入力であり、公開RPCの
`search_query`とは別の引数名である。
`IMMUTABLE`、`STRICT`、`PARALLEL SAFE`、`SECURITY INVOKER`、owner=`postgres`、
`search_path = ''`とし、一般application roleへEXECUTEを付与しない。

公開RPCは次のexact signatureとする。

```sql
public.my_diary_search_tags(
  search_query text,
  after_normalized_name text
) returns table (
  id uuid,
  name text,
  normalized_name text
)
```

RPCは`STABLE`、`SECURITY INVOKER`、owner=`postgres`、`search_path = ''`とし、
`authenticated`だけにEXECUTEを付与する。`auth.uid()`がない呼び出しを拒否し、静的SQLで
`public.tags`を検索するため、既存tags SELECT RLSが最終的な可視性を決める。
`normalized_name ASC`、cursorより大きい値、最大21件を返し、applicationは20件を表示して
21件目を次ページ有無の判定だけに使う。queryとcursorは同じcanonical規則で検証し、
`\\`、`%`、`_`は部分一致条件でliteralとして扱う。

UI cursorはcategory、canonical query、最後の`normalized_name`だけをbase64url JSONへ
格納する。余分・不足field、別category、query不一致、非canonical encoding、過長値を
DB query前に拒否する。category切替時はcanonical queryを維持し、cursorは破棄する。

### Phase B2b-3a migrationの安全条件

preflightでは既存ユーザー検索RPCのexact catalog、return shape、ACL、必要schema・table・
Supabase role、tags RLSとpolicyを確認する。postconditionでは両RPCの引数名とreturn型、
両RPCとhelperのoverload数、signature、言語、volatility、parallel属性、owner、security属性、
固定search_path、ACL、tags RLSを再検証し、不一致ならtransaction全体をrollbackする。

### Phase B2b-3aのリモート適用結果

リモート開発DBへは`20260804000100_extend_user_and_tag_search.sql`だけを通常適用した。
適用後のpg-delta catalog比較とmigration postconditionにより、ユーザー検索RPCの
`search_query`、private helperの`raw_query`、公開タグ検索RPCの`search_query`と
`after_normalized_name`、return shape、owner、volatility、security属性、固定search_path、
ACLを確認した。`public.tags`はRLS有効、FORCE RLS無効、既存SELECT policy 1件、
`authenticated`のtable権限はSELECTのみ、`anon`はSELECT不可の状態を維持している。

適用後のcatalog cache生成では、一時CA証明書を参照できないpg-deltaの補助warningが
発生した。migration SQLは終了コード0で完了し、remote履歴に`20260804000100`が記録され、
再dry-runがup to date、linked schema diffが空であることを確認したため、migrationの
再適用やrepairは行っていない。リモートfixtureとユーザーデータ操作は行わず、
Service Roleも使用していない。

## 投稿検索Phase B2b-3b設計

`20260806000100_add_post_search.sql`は、viewerが閲覧できる投稿だけをtitle・bodyから
検索する公開RPCを追加する。既存posts table、RLS policy、ACL、indexは変更せず、
ローカルreset、pgTAP、catalog、schema diff、認証済みブラウザで検証した。
Phase B2b-3b終了時点ではリモート未適用だったが、後続Phaseで適用済みである。
現在はremoteがC2aまでの17件、repository / localがC2c-1までの18件である。

公開RPCのexact signatureは次のとおりで、overloadとdefault引数は作らない。

```sql
public.my_diary_search_posts(
  search_query text,
  before_created_at timestamptz,
  before_id uuid
) returns table (
  id uuid,
  created_at timestamptz
)
```

RPCは`plpgsql`、`STABLE`、`SECURITY INVOKER`、owner=`postgres`、
`search_path = ''`とし、`authenticated`だけにEXECUTEを付与する。`auth.uid()`が
存在しない呼び出しを拒否し、静的SQLで`public.posts`を検索するため、本人、
public、followers、private、soft delete、author / viewerのactive状態は既存posts
SELECT RLSが最終的に決定する。RPC内へvisibilityやfollow条件を複製しない。

`search_query`はNULL、NFKC後の制御文字、trim後の空文字、51 codepoint以上を拒否する。
query、title、bodyをNFKC化してcase-insensitiveに比較し、`\\`、`%`、`_`をescapeして
literalとして扱う。titleまたはbodyのいずれかへ部分一致すれば1投稿を返す静的な
OR条件であり、利用者入力をPostgRESTの`.or()`や`.ilike()`へ連結しない。

並び順は`created_at DESC, id DESC`、cursorは`before_created_at`と`before_id`の
両方NULLまたは両方非NULLだけを許可し、境界より古い行を最大21件返す。applicationは
先頭20件だけを表示し、21件目の存在を次ページ判定に使う。次cursorはRPC結果の
20件目から作成し、category、canonical query、元の`created_at`文字列、lowercase UUIDを
base64url JSONへ格納する。PostgRESTが返したtimestampを`Date`や`toISOString()`へ
変換せず、小数秒精度とoffset表現をそのまま次RPCの`before_created_at`へ渡す。

RPCは表示候補のIDとtimestampだけを返す。applicationはそのIDだけを通常のposts SELECTで
一括再取得し、再取得時点のRLSを再評価する。再取得できないID、RPCとtimestampが一致しない
IDは表示から除外し、権限変更やsoft deleteの競合時に古いpayloadを表示しない。取得できた
投稿はRPC順へ復元し、既存`attachPostTags`、`hydrateTimelinePosts`、`TimelinePostCard`を
再利用する。権限変更で20件未満になっても、RPCの表示候補外から補完しない。

Phase B2b-3bでは投稿検索専用indexを追加していない。NFKC化したtitle / bodyの先頭・末尾
wildcard部分一致は既存btree indexを直接利用できないため、RLS適用後のscan性能を大規模
データで再評価し、必要性が実測で確認された後に別migrationとして検討する。

新規pgTAP `0012_post_search.test.sql`は52 assertionで、exact catalog・ACL、認証identity、
入力境界、NFKC、case、literal wildcard、title / body OR、public / followers / private、
follow解除・再follow、visibility変更、soft delete、suspended author / viewer、21件上限、
`created_at DESC, id DESC`、cursor重複・欠落・境界を検証する。ローカルでは新規
`52 / 52`、全12ファイル`528 / 528`がPASSし、`public,my_diary_private`のlocal schema diffは
空、catalogはRPC属性・authenticated専用ACL・overload 1と既存posts RLS / policy / ACL /
indexの維持を示した。

## 投稿画像upload Phase B3b設計

`20260808000200_integrate_post_image_uploads.sql`は既存13 migrationを変更せず、
bucket制限、Storage mutation policy、private参照helper、successor作成RPCを追加する。
Storage policyは`storage.allow_only_operation` / `allow_any_operation`を使い、通常の
uploadとdelete-many以外のraw metadata mutationを拒否する。これによりData APIから
実体のない`storage.objects`行だけを偽造してRPCを通す経路を閉じる。

successor RPCは`auth.uid()`とactive状態を関数内で確定し、client由来のuser IDを
受け取らない。post / tag validationは従来作成RPCと同じ境界を維持し、画像は0〜10件、
重複なし、本人・同一post IDのstrict pathだけを受け付ける。対応objectのowner_id、
MIME、1〜6 MiBを確認し、対象行をtransaction終了までlockして並行orphan cleanupを
直列化した後、post、tag master / relation、post_imagesをatomicに保存する。RPCは
`SECURITY DEFINER`、owner=`postgres`、`search_path=''`、authenticated専用EXECUTEとする。

新規pgTAP `0014_post_image_upload_mutation.test.sql`は47 assertionで、RPC catalog / ACL、
bucket上限、policy構成、raw mutation拒否、owner / path / active境界、0 / 10 / 11枚、
配列順、object存在、post / tag validation、atomic rollbackを検証する。ローカルでは
画像関連`122 / 122`、全14ファイル`650 / 650`がPASSした。通常の認証ユーザーと
publishable clientによる実Storage APIでもupload、orphan remove、参照済みremove拒否、
途中・DB失敗cleanup、upsert、MIME / size境界、10枚順序を確認した。

新規migrationだけをリンク済みのリモート開発DBへ通常適用し、local / remote履歴14件一致、
再dry-run up to date、remote catalogのprivate bucket・MIME / size・Storage policy・RPC属性 / ACL、
既存RLS / RPC / 標準Storage ownerの維持、`public,storage,my_diary_private`のlinked schema diff
0件を確認した。migration SQL本体は成功し、その後のpg-delta catalog cache生成で一時CA
参照warningが発生したが、履歴・catalog・再dry-run・linked schema diffで切り分け、repairや
再適用は行っていない。安全な既存remote認証情報がないためremote実upload / RPC mutationは
未実施であり、remote fixture・ユーザーデータ・Storage objectの作成や変更、Service Role、
Auth Admin APIは使用していない。

## 投稿画像配信・表示 Phase B3c設計

Phase B3cは既存14 migration、policy、pgTAP定義を変更しない。既存の
`post_images → posts`と`storage.objects → post_images → posts`のRLS連鎖だけで
metadata取得とbytes取得を二段階に認可できるため、表示専用RPCや
`SECURITY DEFINER` helperは追加しない。

投稿一覧のmetadataは、表示対象post IDを50件ずつのbounded batchへ分け、各batchを
exact count付きrange paginationで取得する。ローカルのPostgREST `max_rows = 1000`や
URL長の影響で結果が黙って欠落しないようにし、取得後はUUID、要求post ID、
`sort_order` 0〜9、画像ID・順序の重複、投稿ごとの最大10枚をapplicationでも検証して
順序を確定する。queryまたはshapeが不正な場合は公開URLや別経路で補完せず、
投稿取得自体を失敗させる。`storage_path`はこのbatch queryでSELECTしない。

詳細、following / latest、自己・他者プロフィール、タグ詳細、投稿検索は共通の
post data hydrationを利用し、各pageにつきmetadata queryを投稿単位のN+1にしない。
画像bytesごとの同一origin requestは取得時認可のsecurity boundaryであり、metadata
hydrationとは分ける。共通galleryは0枚では何も描画せず、1枚は4:3、2枚は2列、
3〜10枚はmobile 2列・`sm`以上3列で`sort_order`を維持する。画像は非interactiveで、
位置情報だけのaltを付け、取得失敗時は同じaspectの一般的なplaceholderへ置き換える。

## 投稿画像編集 Phase B3d設計

`my_diary_update_post_with_images`はpost・tagと最終画像manifestを同一transactionで
更新する。manifestは最大10件のJSONB配列で、各要素を保持する`existingId`または
追加する`newPath`のどちらか1つに限定する。RPCは本人所有かつ未削除のpost行を
`FOR UPDATE`でlockし、保持IDの所属・重複、新規pathの本人namespace・post ID・
Storage object owner / MIME / size・未参照性をDB側で検証する。一般authenticatedへ
`post_images`の直接mutation権限やStorage UPDATE policyは追加しない。

保持画像は`id`、`storage_path`、`created_at`を維持し、deferrableな
`my_diary_post_images_post_sort_key`をtransaction内だけdeferして`sort_order`を更新する。
最終manifestから外れたmetadataはDB transaction内で削除し、その旧pathだけをRPC結果で
Server Actionへ返す。新規uploadはDB確定前のorphanとして扱い、既知のDB失敗時だけ補償削除する。
DB成功後に旧objectをStorage APIで削除し、cleanup失敗時も投稿更新は保存済みとして扱う。
この場合、旧objectはmetadataのないprivate orphanとなり、画像routeからは取得できない。

RPC結果不明時はcommit済みの新規objectを壊さないよう補償削除せず、フォームを停止して
投稿状態の確認を求める。soft deleteでは`post_images` metadataとStorage objectを保持し、
既存RLS連鎖で次回取得を404へfail-closedする。session失効、browser終了、cleanup通信失敗で
残る長期orphanの定期回収と、保持期間後の物理削除は後続Phaseとする。

`20260808000300_integrate_post_image_edits.sql`だけをリンク済みのリモート開発DBへ通常適用した。
local / remote履歴は15件で一致し、再dry-runはup to date、remote catalogでRPCのexact signature・
owner・volatility・`SECURITY DEFINER`・空search path・authenticated専用ACL、deferrable UNIQUE、
`post_images`のread-only ACL、既存8件のStorage policyと標準Storage ownerの維持を確認した。
`public,storage,my_diary_private`のlinked schema diffは空だった。SQL成功後のcatalog cache生成で
一時CAファイルwarningが発生したが、履歴・catalog・再dry-run・schema diffで適用成功と切り分け、
repairや再適用は行っていない。安全な既存remote認証情報がないため、remote実updateとStorage
lifecycle操作は未実施である。Service Role、Auth Admin API、remote fixtureは使用していない。

## 場所名 Phase C4b-1 atomic mutation設計

`20260810000100_add_location_name_atomic_mutation.sql`は既存の
`posts.location_name`列と1〜100文字CHECKを変更せず、現在のApplicationが使用する
`my_diary_create_post_with_images` / `my_diary_update_post_with_images`も維持する。
C4b-2でApplicationを接続するため、次の別名successor RPCを追加した。

```sql
public.my_diary_create_post_with_images_and_location(
  p_post_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
  p_visibility text,
  p_tags text[],
  p_image_paths text[]
) returns uuid

public.my_diary_update_post_with_images_and_location(
  p_post_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
  p_visibility text,
  p_tags text[],
  p_image_manifest jsonb
) returns jsonb
```

場所名はDB mutation境界で前後のspaceを除去し、空または空白のみを`NULL`へ
正規化する。PostgreSQLの`char_length`で100 codepointまでを許可し、101以上は
`22023`で拒否する。既存CHECKにないcontrol文字制約は追加せず、既存DB semanticsを
維持した最小変更とする。編集の`NULL`は明示的な場所名解除であり、値の維持ではない。
C4b-2の編集formは現在値または解除用`NULL`を送る。

successor RPCは`SECURITY DEFINER`、owner=`postgres`、`search_path=''`、
authenticated専用EXECUTEである。client由来user IDを受け取らず、`auth.uid()`と
active accountを確認する。既存画像統合RPCを同じRPC statement / transaction内で
呼ぶため、本人所有・未削除・更新row lock、tag差分、画像manifest、Storage object lockを
再利用する。location更新までcommitされず、location・tag・imageのいずれかのvalidation
failureではpost本体を含むstatement全体がrollbackする。既存posts RLS 3件、updated_at
trigger、authenticatedのposts直接INSERT / UPDATE閉鎖、tag/image RPCとStorage境界は変更しない。

local DBをresetして21 migrationをfresh適用し、新規pgTAP `48 / 48`、全pgTAP
`1,002 / 1,002`を確認した。linked開発DBへ21件目だけを通常適用し、適用後の
migration履歴21件一致、再dry-run up to date、remote catalog属性・ACL、
`public,my_diary_private,storage`のlinked schema diff 0件を確認した。適用直後の
pg-delta catalog cacheでは一時CA証明書の補助warningが発生したが、SQL終了コード、
migration履歴、再dry-run、remote catalog、linked schema diffで適用成功と切り分け、
再適用とmigration repairは行っていない。remote fixture、ユーザーデータ、Storage object、
Service Role、Auth Admin APIは使用していない。

## インデックス

- `my_diary_posts_user_created_at_idx`: ユーザープロフィール、本人の日記、
  フォロー中タイムラインを新しい順に取得するため
- `my_diary_posts_public_created_at_idx`: 最新の全体公開投稿を新しい順に
  取得するため
- `follows` の主キー: 閲覧者が投稿者をフォロー中かを確認するRLSの
  `(follower_id, following_id)` 検索に使用
- `my_diary_follows_following_follower_idx`: フォロワー一覧とフォロワー数の
  逆向き検索用
- `my_diary_follows_follower_created_following_idx`: フォロー中一覧を
  `created_at DESC, following_id DESC`で最大件数取得するため
- `my_diary_follows_following_created_follower_idx`: フォロワー一覧を
  `created_at DESC, follower_id DESC`で最大件数取得するため
- `my_diary_profiles_username_lower_idx`: 大文字小文字を無視したユーザー名検索の
  準備
- `my_diary_tags_normalized_name_key`: canonical tag nameの重複防止と検索準備
- `my_diary_post_tags_tag_post_idx`: tagから可視post relationを逆引きするため
- `my_diary_notifications_recipient_created_id_idx`: recipientの通知一覧を
  `created_at DESC, id DESC`の安定順で取得するため

投稿検索Phase B2b-3bでは新しいindexを追加しない。

通知の未読partial indexはC2c-3の実queryが未確定であるためC2c-1では追加しない。

部分インデックスでは `deleted_at is null` を条件にし、通常の取得対象だけを
小さく保つ。

## 初回マイグレーションの衝突検出と依存順

初回スキーマは1ファイルのトランザクションで、依存順を次のように固定する。

1. 拡張と非公開関数用スキーマ
2. 親となる `auth.users` を参照するテーブル
3. インデックス
4. 関数とトリガー
5. 権限
6. RLSポリシー

`pgcrypto` はSupabase標準でも利用される拡張なので `IF NOT EXISTS` とするが、
このプロジェクトが作成するスキーマ、テーブル、インデックス、関数、トリガー、
ポリシーには `IF NOT EXISTS`、`CREATE OR REPLACE`、事前DROPを使用しない。
名前衝突や部分的な既存定義があれば、その場で失敗してトランザクション全体を
ロールバックする。

Supabaseのマイグレーション履歴で一度だけ適用するのが原則であり、既存定義を
修正する用途で同じファイルを再実行しない。適用後の変更は必ず新しい
マイグレーションとして追加する。

## リモート適用前の既存オブジェクト確認

初回適用前に、リモート開発DBへ次のオブジェクトが存在しないことを確認する。
確認だけを行い、既存オブジェクトを自動削除しない。

- `public.accounts`、`public.profiles`、`public.posts`、`public.follows`
- `my_diary_private` スキーマ
- `my_diary_` 接頭辞の制約とインデックス
- `public.my_diary_set_updated_at`
- `public.my_diary_handle_new_auth_user`
- `my_diary_private.my_diary_is_account_active`
- `public.my_diary_soft_delete_post`
- `my_diary_` 接頭辞のテーブルトリガーとRLSポリシー
- `auth.users.my_diary_on_auth_user_created`

加えて `auth.users` の全トリガー一覧を確認し、一般名の
`on_auth_user_created` など既存Auth連携が維持されることを適用前後で比較する。

## テスト方針

pgTAPテストはトランザクション内にA・B・Cの認証ユーザーと投稿を作成し、
JWT claimとDB roleを切り替えてRLSを検証し、最後にロールバックする。
最低限、次を確認する。

- private / followers / public / deleted投稿の閲覧境界
- 匿名ユーザーはpublic投稿も閲覧できないこと
- フォロー解除直後のアクセス喪失
- 投稿の本人名義作成、本人だけの更新・ソフトデリート
- 一般ユーザーによる物理DELETEの拒否
- suspended / deactivated viewerは本人所有を含む通常投稿・profile・tag・image・reaction・commentを取得不可
- suspended / deactivated targetのprofile・投稿・関連tag・imageをactive viewerから非表示
- suspended / deactivatedユーザーの投稿作成・更新・ソフトデリート拒否
- 自己フォロー、重複、他人名義のフォロー操作
- `accounts.role` / `accounts.status` の更新拒否
- 他ユーザーのaccountsを閲覧できないこと
- active viewerによるactive profiles閲覧とnon-active targetの拒否
- activeな本人だけのプロフィール更新
- non-active本人のaccounts status SELECT維持と、activeな本人だけのタイムゾーン更新
- Authユーザー作成時のaccounts / profiles自動作成
- プロジェクト固有Authトリガーと一般名トリガーの共存
- SECURITY DEFINER関数の所有者、`search_path`、EXECUTE権限
- tag normalizerのNFKC・space・先頭`#`・ASCII case canonical化とACL
- tags/post_tagsの列、制約、cascade FK、index、RLS、SELECT専用grant
- private / followers / public / deleted / suspended / visibility変更時のtag名境界
- tags → post_tags → postsの評価でRLS再帰が起きないこと
- 特権roleの直接SQLでは1投稿6個のlinkが可能という構造上の境界を維持しつつ、
  Phase B2aのauthenticated RPC経路ではcanonical distinct最大5個を拒否すること
- atomic RPCのexact signature、属性、ACL、posts直接grant取消、入力境界
- tagのNULL / 空配列 / 非空配列、差分更新、unchanged relationの`created_at`
- relation段階の強制例外でpost・tag master・relationが一括rollbackすること
- 補助2-session検証で同一tag UNIQUE競合と同一post row lockを実際に待機させること
- 投稿検索RPCのexact signature・ACL・SECURITY INVOKER、NFKC・literal wildcard、
  title / body OR、既存posts RLSへの委任、21件・複合cursor境界
- 投稿画像RPCのexact signature・ACL・active owner、0 / 10 / 11枚、strict path、
  Storage object owner・MIME・size、呼出順のsort_order、post / tag / image rollback
- Storage mutationのoperation context、owner_id、本人UUID namespace、UPDATE拒否、
  active ownerだけの未参照orphan SELECT / cleanup、参照済み・soft-delete済みmetadataの削除拒否
- notificationsの4 type / target shape、自己通知拒否、account / post / commentへのcascade FK
- anonと一般authenticatedのINSERT / DELETE拒否、recipient本人だけのSELECTと`is_read`更新
- non-active recipient / actorのfail-closed、現在のpost visibility・follow・soft deleteの再評価
- target commentのsoft deleteではpostが見える限りnotificationを維持し、target physical deleteではcascadeすること
- follow / reaction / top-level comment / replyの正しいrecipient、actor、targetと自己通知防止
- reaction種類変更・解除では追加通知せず、reaction再追加・refollowでは新しいevent通知を生成すること
- replyはparent authorだけへ通知し、新reply自身をtargetとしてpost ownerへ重複通知しないこと
- invalid replyのgeneric errorと0 notification、特権fixtureの非通知化、source mutationとのatomic rollback
- notification generatorのowner、SECURITY DEFINER、空search path、trigger専用ACLとauthenticated直接INSERT拒否
- account timezone validatorのowner、SECURITY INVOKER、空search path、trigger専用ACL、INSERT / UPDATE event
- authenticated direct UPDATEで有効timezoneだけを保存でき、無効・空・内部timezoneを拒否すること
- 本人timezone更新成功、他人・suspended・deactivated更新拒否、role / status列権限維持

## リモート適用後のAuth確認

リモート開発DBへ適用した後は、既存データを使わず、確認専用の新規ユーザーを
通常のSupabase Auth登録経路から1件作成する。登録が成功し、同じUUIDの
accountsとprofilesが各1行だけ作成され、role=`user`、status=`active` である
ことを確認する。

続けて、適用前に記録した `auth.users` の既存トリガーが残っていること、
`my_diary_on_auth_user_created` が1個だけ存在すること、AuthログとDBログに
トリガー由来のエラーがないことを確認する。確認ユーザーの削除は
`ON DELETE CASCADE` の影響を理解したうえで、別途許可された作業として行う。

## 未確定事項

- body、bio等の文字数上限の最終値
- ソフトデリート後の保持期間とPhase 2での物理削除手順
- Phase 2で実装する管理者のrole/status変更経路と監査ログ
- 将来のプロフィール公開範囲とブロック機能
