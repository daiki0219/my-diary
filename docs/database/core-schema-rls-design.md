# コアデータモデル・RLS設計案

## 対象と前提

この設計案は、最初のデータベース単位として `accounts`、`profiles`、
`posts`、`follows` を対象とした。投稿画像、リアクション、コメント、通知、
通報、Storageは初回単位に含めない。自由タグの後続Phase B1設計は本書の
「自由タグPhase B1追加設計」に追記する。

全体公開投稿を含めて閲覧はログイン必須とする。`anon` には4テーブルの
権限を付与せず、`authenticated` に対してもRLSと列権限の両方で制御する。

今回作成したSQLはmigrationとして管理し、リンク済みのリモート開発Supabaseへ適用済みである。

## データモデル

### accounts

- `user_id`: `auth.users.id` を参照する主キー
- `role`: `user` / `admin`
- `status`: `active` / `suspended` / `deactivated`
- `timezone`: IANAタイムゾーン名を保存する想定。初期値は `Asia/Tokyo`
- `created_at` / `updated_at`: `TIMESTAMPTZ`

一般ユーザーに許可する更新列は `timezone` だけである。`role` と `status`
はRLSだけに頼らず、PostgreSQLの列権限でも更新を拒否する。管理者による
状態変更は管理機能の設計時に、監査ログと一緒に別途追加する。

### profiles

- `user_id`: `auth.users.id` を参照する主キー
- `username`: 表示名。1〜50文字
- `bio`: 任意。最大500文字
- `avatar_path`: 任意。将来の非公開Storage内のオブジェクトパス
- `created_at` / `updated_at`: `TIMESTAMPTZ`

MVPではプロフィール自体に機密情報を置かず、ログイン済みユーザー全員が
閲覧できる。更新は本人だけに許可する。`username` は表示名として扱うため
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

## CHECK制約を採用する理由

`role`、`status`、`mood`、`visibility` はPostgreSQL enumではなく、`text` と
名前付きCHECK制約を使用する。MVPでは候補値が変わる可能性があり、CHECKは
制約の差し替えをトランザクション内で行いやすく、値削除・名称変更に伴う
enum固有の移行制約を避けられるためである。アプリ側では同じ値を
TypeScriptの文字列unionとして生成・管理する予定とする。

## RLSポリシー

### posts SELECT

`deleted_at is null` を前提に、次のいずれかだけを許可する。

1. `posts.user_id = auth.uid()`（投稿者本人）
2. 閲覧者と投稿者の両方が `active` で `visibility = 'public'`
3. 閲覧者と投稿者の両方が `active` で `visibility = 'followers'` かつ、
   `follows` に `(auth.uid(), posts.user_id)` が存在する

`anon` にはテーブル権限もポリシーも付与しないため、公開投稿もログイン必須。
フォロー解除で `follows` 行がなくなると、次のSELECTから即時に閲覧不可になる。
投稿者が `suspended` の場合、投稿者本人だけは自分の未削除投稿を閲覧できるが、
他ユーザーからはpublic投稿を含めて非表示になる。

### posts INSERT / UPDATE / ソフトデリート

- INSERT: `user_id = auth.uid()` かつ `deleted_at is null`
- UPDATE: 削除前の本人投稿だけ。更新後も `user_id = auth.uid()`
- ソフトデリート: 本人だけが `my_diary_soft_delete_post` 関数で
  `deleted_at` を設定
- DELETE: 一般ユーザーには権限もRLSポリシーも付与しない

列権限により、一般ユーザーは `id`、`user_id`、作成・更新日時を直接変更
できない。`updated_at` はトリガーで更新する。

### profiles

- SELECT: ログイン済みユーザー
- UPDATE: 本人だけ
- INSERT / DELETE: 一般ユーザーには許可しない

### follows

- SELECT: 閲覧者、`follower_id`、`following_id`の3者がすべてactiveの場合のみ
- INSERT / DELETE: `follower_id = auth.uid()` の行だけ
- UPDATE: 許可しない

停止中のユーザーを含む既存関係は削除せずSELECT結果から除外する。両者が
activeへ戻り、関係行が残っている場合は一覧と件数へ再表示される。

### accounts

- SELECT: 本人の行だけ
- UPDATE: 本人の `timezone` 列だけ
- INSERT / DELETE: 一般ユーザーには許可しない

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
- suspended投稿者の投稿を本人以外から非表示
- suspendedユーザーの投稿作成・更新・ソフトデリート拒否
- 自己フォロー、重複、他人名義のフォロー操作
- `accounts.role` / `accounts.status` の更新拒否
- 他ユーザーのaccountsを閲覧できないこと
- ログイン済みユーザーによるprofiles閲覧
- 本人だけのプロフィール更新
- 本人だけのタイムゾーン更新
- Authユーザー作成時のaccounts / profiles自動作成
- プロジェクト固有Authトリガーと一般名トリガーの共存
- SECURITY DEFINER関数の所有者、`search_path`、EXECUTE権限
- tag normalizerのNFKC・space・先頭`#`・ASCII case canonical化とACL
- tags/post_tagsの列、制約、cascade FK、index、RLS、SELECT専用grant
- private / followers / public / deleted / suspended / visibility変更時のtag名境界
- tags → post_tags → postsの評価でRLS再帰が起きないこと
- Phase B1では1投稿6個のlinkが可能で、最大5個保証を未導入のまま維持すること

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
- `timezone` のIANA名をDBでも厳密検証するか、アプリ入力候補で保証するか
- ソフトデリート後の保持期間とPhase 2での物理削除手順
- Phase 2で実装する管理者のrole/status変更経路と監査ログ
- 将来のプロフィール公開範囲とブロック機能
