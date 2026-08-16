# my-diary 現在の実装状況

> この文書は、my-diaryの現在の実装状況を示す。
> 仕様そのものは [`my-diary_spec_v2.2.md`](../../my-diary_spec_v2.2.md) を正とする。
> 各Phase完了後に、実装・migration・テスト結果に基づいて更新する。
> 計画や希望だけで「実装済み」に変更しない。

## 1. 文書の目的

この文書は、正式仕様の各項目と現在のrepositoryに存在する実装根拠を対応付け、次のPhaseを判断できる状態に保つための管理文書である。仕様の追加・変更はこの文書では行わない。

- 正式仕様: [`my-diary_spec_v2.2.md`](../../my-diary_spec_v2.2.md)
- 初期MVPの履歴資料: [`docs/specs/archive/my-diary_MVP_spec_v1.0.md`](../specs/archive/my-diary_MVP_spec_v1.0.md)
- DB設計資料: [`docs/database/core-schema-rls-design.md`](../database/core-schema-rls-design.md)
- 調査基準日: 2026-08-16
- 調査時branch: `main`
- 調査基準HEAD: `52efbd45e1369fef8a9e61549ce43d11d127a0a5`
- 調査基準HEADのmessage: `fix: harden report moderation conflicts`

### 更新ルール

1. 実際のroute、component、Server Action、migration、RLS、テストを確認してから状態を変更する。
2. 仕様、型、TODO、計画だけを根拠に「実装済み」としない。
3. UIだけがある場合、DB認可やRLSを含む要件は「実装済み」としない。
4. migrationだけがある場合、利用者向けUIを含む機能は「実装済み」としない。
5. 過去の成功結果と、更新時に再実行した検証結果を分けて記録する。
6. 各Phase完了後に、調査時HEAD、状態集計、関連migration、関連テスト、更新履歴を更新する。

### 状態の意味

| 状態 | 判定基準 |
| --- | --- |
| 実装済み | 主要要件について、現在のrepositoryでコードと必要なDB・テスト根拠を確認できる |
| 一部実装済み | 基盤または主要操作の一部はあるが、正式仕様の要件を満たし切っていない |
| 未実装 | MVP対象だが、利用可能な実装を確認できない |
| MVP後 | 正式仕様でMVP公開後のPhaseに分類されている |
| 確認不能 | repository内の情報だけでは判定できない |

## 2. 全体サマリー

この文書では、機能を60個の管理項目へ分けて集計する。従来の58項目に、交換日記の「DB / Storage foundation」と「Application / UI」を分離した2項目を追加した。

| 状態 | 件数 |
| --- | ---: |
| 実装済み | 34 |
| 一部実装済み | 7 |
| 未実装 | 2 |
| MVP後 | 17 |
| 確認不能 | 0 |
| 合計 | 60 |

現在は、メールアドレスとパスワードによる認証とパスワード再設定、non-active accountのapplication session gate、プロフィールの表示・編集、日記の作成・詳細・編集・soft delete、6種類の気分、任意の場所名、自由タグの入力・保存・投稿上のリンク表示・タグ一覧・タグ詳細・部分一致検索、3段階の公開範囲、フォロー中・最新投稿の2種類のタイムライン、private Storage画像の新規投稿upload・認証付き表示・既存投稿での追加・削除・並び替え、3種類のリアクション、コメントの投稿・1階層返信・親子表示・soft delete、フォロー・解除・一覧、ユーザー名検索、閲覧可能な投稿のtitle・body部分一致検索まで実装されている。

DB側では、従来のコア10 public tableに加え、交換日記・通知設定・通報の12 public table、2 private table、private Storage bucket `exchange-entry-images`がmigration管理されている。公開範囲、active / suspended / deactivated、participant-only、通報対象だけの運営閲覧、evidence保持をRLS・ACL・RPC・trigger・Storage policyで制御する。Exchangeの通常利用者向けApplication / UIはE3aで`/exchange`、`/exchange/[diaryId]`、oldest / latest pagination、削除済みplaceholder、通知3 type parser / target遷移、home導線を実装し、E3bでinvitationのcreate / accept / reject / cancel、user別のblock / unblockを既存RPCへ接続した。E3cではentryの作成・本人編集・本人soft delete、diary title変更・archive、確認UI、入力検証、stale / crafted-inputのgeneric failureを既存RPCへ接続した。E3dではprivate Exchange画像のsame-origin Route Handler、live metadata hydrate、0〜10枚galleryを実装した。Phase E3e-0bではnever-confirmed Exchange画像orphanを24時間grace後にtrusted active-admin maintenanceだけが回収できるDB / Storage境界を追加した。Phase E3e-1ではentry新規作成へ0〜10枚のprivate画像upload、preview・選択順保持、magic-byte validation、caller-generated entry UUIDとstrict 4 UUID path、successor RPCへの完全移行、outcome別cleanupを接続した。Phase E3e-2ではexisting画像の保持・削除・並び替え、new画像追加、existing / new混在順序、全画像削除を一つのordered stateとfinal complete manifestでedit successorへ接続し、new画像だけをupload / cleanup対象にした。Phase E3f-1ではactive adminであっても自分がtargetまたはreporterのreportをrow / snapshot / exact evidence / status / purgeの全境界から除外するsuccessor migrationをrepository / localへ実装し、linked開発DBへ通常適用した。repository / local / remoteは32 migrationで一致する。E3f-1時点のlocal fresh apply後に32 pgTAP・`1,755 / 1,755 PASS`を確認した。

MVP完了条件との差分では、パスワードリセットと場所名が完了し、OAuthとavatarは未完成である。home timelineの20件forward cursor paginationと本文省略はPhase C3aで完了した。timezone DB integrity、viewer timezone helper、`/settings`の表示・変更はPhase C3bで完了し、Phase C3c-1ではstrict month/date validation、DST対応のlocal month境界、本人Calendar posts query、日単位summaryと選択日data shapeを実装した。Phase C3c-2では`/calendar`、月grid、前後月・今月遷移、日別marker、日付選択、選択日投稿一覧、responsive / accessibilityを実装した。non-active accountのDB / RLS境界とapplication session gateはPhase C1a / C1bで完了し、1階層コメント返信はPhase C2a / C2bでDBからApplication / UIまで完了した。通知はDB / RLS基盤、follow / reaction / comment / reply生成、一覧・未読/既読・target遷移までPhase C2c-1〜C2c-3で完了した。投稿画像の新規作成・表示・編集要件はPhase B3a〜B3dで完了した。MVP後のカテゴリー、推し活、コミュニティ、ぬい活、イベント、アルバム、おすすめ、AI、プレミアムは未着手であり、現時点のMVP欠陥としては扱わない。

Phase E2a〜E2gで、交換日記のstate・招待、entry / tag / private画像、通知設定・mute、通報snapshot、deactivated時archive、invite-block privacy、画像evidence retention / cleanup・trusted maintenance基盤を実装した。Phase E2h-1aの最終read-only security auditでは当時の調査範囲でDB / Storage BLOCKERは0件だったが、E3f-0でactive adminが自分をtargetまたはreporterとするreportを閲覧・自己moderationできるDB BLOCKERを確認した。E3f-1はこのconflict-of-interest境界をrepository / local / remoteで修正し、linked catalogとschema diffを確認した。Phase E3aでは通知parser / target navigationとparticipant-onlyのread / list / detail Applicationを完了し、Phase E3bでは6 invitation operation、mutual-follow時のinvite UX、invitation専用block preference、generic errorによるprivacy oracle対策を完了した。Phase E3cではdiary / entry mutation UIを既存のoperation RPCへ接続した。Phase E3dではprivate Exchange画像Routeと表示を完了し、raw Storage path非露出、live metadata / Storage RLS再評価、neutral 404、archived / follow解除後の閲覧、soft delete後不可視、evidence / retention経路分離を確認した。Phase E3e-0bではstrict 4 UUID pathとowner一致を満たすnever-confirmed orphanだけを24時間後に列挙・削除可能とし、live metadata、confirmed cleanup candidate、report snapshot evidenceを除外し、Storage row lockでsuccessor RPCとのraceを直列化した。Phase E3e-1ではcreateを、Phase E3e-2ではeditを画像統合successorへ接続し、existing identity、follow解除後のparticipant semantics、archive / account status競合のfail-closed、raw path非露出、removed existingの7日retentionを維持した。残るApplication BLOCKERはreport submission、admin moderation、moderator evidence Route、maintenance実行経路の4カテゴリで、公開前には4件の運用・統合確認が残る。`my_diary_create_user_report`がExchange relationを要求しないglobal scopeである問題はE3f-3対象として未解消である。

Phase C4b-2では、作成・編集formへ任意の場所名を追加し、trim・空欄からNULL・最大100 Unicode codepointsをClientとServer Actionで検証する。画像upload前のClient validationとDB successor RPCの最終境界を併用し、既存tag / image manifest・Storage cleanup順序を維持する。投稿詳細、home、自己・他者投稿一覧、タグ詳細、投稿検索結果は必要なposts SELECTへだけ`location_name`を追加し、共通metadata componentで表示する。Calendar、通知、location検索、package、DB、migrationは変更していない。このセッションの認証付きbrowser fixtureは、通常sign-upがローカルAuthのemail rate limitへ達し、利用可能な別browser sessionもなかったため未実施である。`lint`、`typecheck`、`build`、`git diff --check`は成功した。

正式仕様Ver.2.2でも初回公開対象として維持された交換日記は、DB / Storage foundation、E3aのread / list / detail / notification compatibility、E3bのinvitation create / accept / reject / cancel / block / unblock、E3cのdiary / entry mutation、E3dのprivate画像Route / 表示、E3e-1の新規entry画像upload / create接続、E3e-2のexisting画像edit / final complete manifest接続、E3f-1のreport moderation conflict-of-interest hardeningまで実装・remote適用済みである。report submission / admin moderation / evidence / maintenanceのApplication経路は未完了である。

### 2.1 MVP残差と実装優先順位

正式仕様上のProduct phaseと、Ver.2.2のWeb Initial Release Gateは別に管理する。

- 公開前に重要: 残るExchange通報、moderation / maintenance経路、remote AuthのSite URL / Redirect URLsと実メール配信を完了する
- 強く推奨: follow / profile / user検索等の固定件数改善
- MVP対象だが後順位: Google login、Apple login、avatar、timezone以外のsettings、profile / follow list等のpagination
- MVP後またはmaintenanceへ延期可能: 通常post画像の長期orphan cleanup・soft-delete後physical delete、正式仕様のPhase 2以降の機能

Google / Apple OAuth、avatar、一部pagination・settingsの未完成だけではWeb初回公開を停止しないというVer.2.2の分類を反映する。この優先順位は正式仕様のProduct roadmapから各項目を削除するものではない。投稿画像の主要利用者要件は実装済みだが、物理削除と長期orphan回収は運用・保持方針を伴う後続maintenanceとして残る。

## 3. 技術・リポジトリ状態

| 項目 | 現在の状態 | 根拠 |
| --- | --- | --- |
| framework | Next.js 16.2.11、App Router | `package.json`、`src/app/**` |
| language | TypeScript 5、React 19.2.4 | `package.json`、`tsconfig.json` |
| styling | Tailwind CSS 4、mobile-firstのutility class | `package.json`、`src/app/globals.css`、各component |
| backend | Supabase Auth、Postgres、RLS、Supabase SSR | `@supabase/ssr`、`@supabase/supabase-js`、migration |
| 認証方式 | email/password、SSR cookie session、認証callback、request-scoped account status gate | `src/app/auth/actions.ts`、`src/app/auth/callback/route.ts`、`src/lib/supabase/account-session.ts`、`src/proxy.ts` |
| migration | repository / local / remoteは32件で一致。latestは`20260816000200_harden_report_moderation_conflict_of_interest.sql` | `supabase/migrations/*.sql`、local / linked migration list・remote catalog・linked schema diff |
| DB table | public 22 table、private 2 table | 既存コア10件、Exchange / report 12件、pair lock / cleanup candidate 2件 |
| pgTAP | 32ファイル、plan合計1,755。最新確認済みlocal全回帰`1,755 / 1,755 PASS` | `supabase/tests/database/*.sql`。E3f-1 local fresh apply後に確認 |
| local Supabase | Windows TCP除外範囲と競合したtracked 5432x portsを5542xへ移動。API `55421`、DB `55422`、Studio `55423`等のconfig / Docker mapping一致とclean start / local reset成功を確認。remote設定には影響なし | `supabase/config.toml`、local Supabase / Docker確認 |
| その他の自動テスト | repository内では未確認 | unit、component、E2Eのtest fileは存在しない |
| npm検証 | `lint`、`typecheck`、`build` | `package.json` |
| 調査基準commit | `52efbd45e1369fef8a9e61549ce43d11d127a0a5` | Phase E3f-1のremote確定と通常pushまでを含む |

Server Componentがpageとデータ取得を担当し、入力フォーム、フォロー、リアクション、削除などの操作UIをClient Componentへ分けている。投稿作成・更新はServer Actionからatomic RPCを呼び、SECURITY DEFINER関数内で`auth.uid()`、active状態、所有権、未削除を最終検証する。SELECTとその他の一般mutationはRLSを最終認可としている。タグrouteには共通の`loading.tsx`があり、送信操作のpending表示は各Client Componentの`useFormStatus`で実装されている。

## 4. 機能別実装状況

### 4.1 認証

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| email/password会員登録 | 実装済み | `/sign-up`、`signUp` Server Action、email確認callback。`my_diary_on_auth_user_created`が`accounts`と`profiles`を作成 | なし |
| ログイン・ログアウト・session・未認証遷移 | 実装済み | `/login`、`login`、`logout`、SSR cookie更新、各protected pageの`getClaims()`と`/login` redirect | 公開投稿の匿名閲覧は採用せず、認証画面へ誘導する方式 |
| パスワードリセット | 実装済み | `/forgot-password`、account enumerationを避けるgeneric案内、Supabase SSR / PKCE callback、SDK `redirectType=recovery`とJWT `amr=recovery`の二重確認、recovery専用`/reset-password`、`updateUser()`、local sign-out、新passwordでの再loginを実装 | remote SupabaseのSite URL / Redirect URLs・SMTP、期限切れlink、実ブラウザ初回redirectと実キーボードは公開前確認 |
| Googleログイン | 未実装 | OAuth actionとUIなし | provider設定と通常OAuth導線が必要 |
| Appleログイン | 未実装 | OAuth actionとUIなし | provider設定と通常OAuth導線が必要 |
| suspended account制御 | 実装済み | Phase C1aでDB / RLSをfail-closed化し、Phase C1bでlogin・即時session付きsign-up・callback・protected request・画像request・Server Action requestへ共通status gateを追加。本人accounts statusだけを取得し、`active`以外・row欠損・query失敗はfail-closedでcurrent sessionを終了し、固定codeのgeneric messageへ誘導する | ローカル統合回帰と実ブラウザ主要シナリオを確認済み。320〜390pxはBrowser viewport overrideが反映されず未確認 |

主な関連コードは`src/app/auth/actions.ts`、`src/app/auth/callback/route.ts`、`src/app/(auth)/forgot-password/page.tsx`、`src/app/(auth)/reset-password/page.tsx`、`src/components/auth/password-reset-request-form.tsx`、`src/components/auth/password-update-form.tsx`、`src/lib/auth-validation.ts`、`src/lib/supabase/server.ts`、`src/lib/supabase/account-session.ts`、`src/lib/supabase/proxy.ts`である。主な関連テストは`0001_core_rls.test.sql`、`0004_user_search_and_follows.test.sql`、`0006_user_profile_posts_rls.test.sql`、`0007_follow_lists_rls.test.sql`である。

### 4.2 プロフィール

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| 自分のプロフィール表示・編集 | 実装済み | `/profile`、`/profile/edit`。username、bio、投稿数、フォロー数、フォロワー数と編集導線を表示 | なし |
| 他ユーザープロフィール | 実装済み | `/users/[userId]`。UUID検証、本人UUIDの`/profile`正規化、follow操作、閲覧可能な最新20投稿を表示 | 続きを読むページングは別項目 |
| follow/follower件数と一覧導線 | 実装済み | 自分・他者それぞれのfollowing/followers route、安定順、最新20件、follow操作 | 続きを読むページングは未実装 |
| avatar | 一部実装済み | `profiles.avatar_path`と長さ制約、更新権限は存在 | upload、Storage policy、表示・編集UIはなく、現在はユーザー名の頭文字を表示 |
| suspendedプロフィールの扱い | 実装済み | C1aのprofiles RLSとprofile検索RPCはactive viewer / active targetだけを許可し、直接取得もDBで拒否。C1bのrequest gateはnon-active sessionをプロフィール取得前に終了してloginへ誘導する | なし |
| 興味タグ・推し一覧 | MVP後 | 正式仕様のPhase 3、Phase 4以降 | 対応table・route・UIなし |

関連コードは`src/lib/profile-data.ts`、`src/lib/follow-data.ts`、`src/components/profile/**`である。関連migrationはコアschemaと`20260801000100_secure_follow_lists.sql`、関連テストは`0001`、`0004`、`0006`、`0007`である。

### 4.3 日記投稿、画像、気分、タグ、場所、公開範囲

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| 作成・詳細・編集・soft delete | 実装済み | `/posts/new`、`/posts/[postId]`、`/posts/[postId]/edit`、`/profile/posts`。作成・編集はatomic post/tag RPC、削除はsoft-delete RPCを使用 | なし |
| title・body・入力検証 | 実装済み | titleは任意120文字、bodyは1〜10,000文字。ClientとServer Action、DB CHECKで検証 | なし |
| 気分 | 実装済み | 6種類と未設定を作成・編集・一覧・詳細で扱う。DB CHECKあり | なし |
| 公開範囲 | 実装済み | `private`、`followers`、`public`。作成・編集可能で、RLSが閲覧を制御 | 未認証public閲覧は対象外の運用 |
| 画像 | 実装済み | privateな`post-images` bucketへJPEG / PNG / WebPを1枚6 MiB・最大10枚で逐次uploadし、`userId/postId/imageId` path、preview、atomic post/tag/image作成・更新RPCを実装。編集は既存identityを維持した追加・削除・並び替え、DB失敗時new cleanup、DB commit後old cleanupに対応。表示はraw path非露出の同一origin routeとRLS再評価を使い、0 / 1 / 複数 / 最大10枚の共通galleryを詳細・timeline・profile・tag・検索へ統合 | 長期orphan回収、soft delete画像と保持期間後の物理削除は後続maintenance。magic-byte / virus scanは未実装 |
| 自由タグ | 実装済み | `tags`、`post_tags`、NFKC canonical name、文字数・文字種制約、重複防止、可視post連動SELECT RLS、atomic作成・差分更新RPC、一般アプリ経路の最大5個保証を実装。作成・編集のチップ入力、投稿詳細・following・latest・自他プロフィール投稿一覧のUUIDリンク、`/tags`、`/tags/[tagId]`、部分一致検索、forward cursor paginationまで接続済み。直接mutation権限なし | なし |
| 場所名 | 実装済み | C4b-1で`posts.location_name`、100文字CHECK、NULL解除、正規化、active owner・未削除・row lock・tag/image rollbackを保証する画像統合successor RPCを追加。C4b-2で作成・編集form、Client / Server Actionの100 codepoint検証、successor RPC切替、詳細・home・自他プロフィール投稿・タグ詳細・投稿検索結果の共通metadata表示まで接続 | 認証付きbrowser回帰と5幅responsive・実キーボード操作はローカルAuth rate limitのため今回未確認 |
| カテゴリー・推し・ぬい・イベント・アルバム関連 | MVP後 | 正式仕様でPhase 3以降 | MVP完了条件には含めない |

投稿の関連コードは`src/app/(protected)/posts/actions.ts`、`src/lib/post-data.ts`、`src/lib/tag-data.ts`、`src/lib/post-image-data.ts`、`src/components/posts/**`である。`0001_core_rls.test.sql`、`0005_post_edit_rls.test.sql`、`0006_user_profile_posts_rls.test.sql`、`0009_tags_rls.test.sql`、`0010_post_tag_mutation_rpc.test.sql`、`0013_post_images_storage_rls.test.sql`、`0014_post_image_upload_mutation.test.sql`、`0015_post_image_edit_mutation.test.sql`、`0021_location_name_atomic_mutation.test.sql`が主要なDB回帰を担う。

### 4.4 タイムライン

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| timeline共通表示・feed分離 | 実装済み | `/home?feed=following`と`/home?feed=latest`をリンク型navigationで切り替え、選択中リンクへ`aria-current="page"`を付与。投稿者、日時、気分、title、タグ、画像、reaction、comment件数、詳細導線を共通利用。home本文は280 codepointsまで表示し、281以上だけellipsisと「続きを読む」を出す。投稿詳細とhome以外の共通card利用画面は全文を維持する | なし |
| フォロー中timeline | 実装済み | queryなし・空・未知・複数値を含む既定feed。`follows`から現在のfollow先を毎回取得し、自分＋follow先のauthorへ絞ったうえでRLSがprivate、suspended、soft delete等を最終除外。20件単位のforward cursorで継続取得する | 大量follow時の`.in(...)`は実データで評価が必要 |
| 最新投稿timeline | 実装済み | `feed=latest`で`visibility = public`を明示し、現在のRLS上閲覧可能な全active投稿者のpublic投稿を20件単位のforward cursorで継続取得する | なし |
| pagination / infinite scroll | 実装済み | `created_at DESC, id DESC`と一致する複合cursor条件で21件取得し、表示・hydrateは先頭20件、21件目はnext有無の判定に使う。cursorはversion・feed・timestamp・UUIDを持つstrictなopaque base64urlでfeedへbindし、通常Link遷移、reload、back / forward、URL直接アクセスに対応する | infinite scrollは採用せず通常paginationとした |

RLSは権限のない投稿、soft-deleted投稿、suspended投稿者の投稿をDB取得結果から除外する。`getTimelinePosts`は`created_at DESC, id DESC`の20件forward cursorを共通条件とし、現在のfollow・visibility・RLSを各pageで再評価する。タグはposts queryのnested select、作者プロフィール、reaction、comment件数は表示対象20件だけをbatch取得として投稿単位のN+1を避けている。タグrelationの取得・shape検証に失敗した場合はタグ0件へ丸めず投稿取得エラーとする。不正cursor、feed不一致、取得失敗はraw値や内部errorを出さないgeneric errorへ集約し、cursor付き0件pageは先頭へ戻る導線を表示する。各feedには固有の説明文と空状態がある。

### 4.5 リアクション

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| 3種類・追加・解除・変更・件数 | 実装済み | `empathy`、`support`、`relatable`。1投稿1ユーザー1件のUNIQUE、toggle Server Action、種類別・合計件数を表示 | 自分の投稿へのreactionは現在許可されている |
| reaction通知 | 実装済み | reaction INSERTと同一transactionで通知を生成し、RLS下の一覧からpostへ遷移する。解除・種類変更では追加通知しない | なし |

関連migrationは`20260726000100_create_reactions.sql`、関連テストは`0002_reactions_rls.test.sql`とvisibility変更を扱う`0005_post_edit_rls.test.sql`である。

### 4.6 コメント

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| 投稿・表示・本人soft delete・件数 | 実装済み | 投稿詳細で最大100件を古い順に表示。1〜1,000文字、閲覧可能投稿だけに作成可能。本人専用RPCでsoft delete | 投稿者による他者comment削除方針は未決定 |
| 返信 | 実装済み | nullable `parent_comment_id`、同一post・top-level・未削除・active parentを検証するDB trigger、安定取得indexをlocal / remoteへ実装。既存comment作成・soft-delete経路を再利用した返信Server Action、古い順の1階層親子表示、inline form、削除済み・取得不能な親のneutral placeholderを実装 | comment一覧は古い順100件固定 |
| 通知 | 実装済み | comment / reply INSERTと同一transactionで通知を生成し、target commentをRLS下でbatch確認する。利用不能targetは本文やUUIDを出さずneutral表示し、既読化できる | なし |
| コメント通報 | MVP後 | 正式仕様のPhase 2で通報を整備 | `reports` tableとUIなし |
| コメント編集 | MVP後 | 正式仕様でMVP対象外でもよい | update UI・policyなし |

関連migrationは`20260726000200_create_comments.sql`から`20260726000400_fix_post_visibility_helper.sql`と`20260809000100_add_comment_replies.sql`、関連テストは`0003_comments_rls.test.sql`と`0017_comment_replies_rls.test.sql`である。

### 4.7 フォロー

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| follow・解除・自己/重複拒否 | 実装済み | Server ActionとRLS、複合PK、CHECKで実装。active targetだけfollow可能 | なし |
| following / followers一覧 | 実装済み | 自分・他者の4 route、最新順、20件、一覧内follow操作、suspended関係の除外 | paginationは未実装 |
| follow通知 | 実装済み | follow INSERTと同一transactionで通知を生成し、actor profileをRLS下で取得して遷移する。解除では追加通知せず、再followは新規eventとして扱う | なし |
| 非公開account・承認制 | MVP後 | MVP対象外 | 将来拡張時にdata modelとRLSを再設計する |

関連migrationはコアschema、`20260726000500_secure_user_search_and_follows.sql`、`20260801000100_secure_follow_lists.sql`、関連テストは`0004`と`0007`である。

### 4.8 検索

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| ユーザー名検索 | 実装済み | `/search?category=users`とhardened RPC。NFKC、1〜50 codepoint、前後空白除去、case-insensitive部分一致、`\\`・`%`・`_`をliteral扱い、activeユーザー、最大20件 | paginationなし |
| タグ検索 | 実装済み | `/search?category=tags`。入力をtag規則でNFKC canonical化し、`\\`・`%`・`_`をliteral扱い、RLS上閲覧可能なタグだけを`normalized_name`順に20件ずつ表示 | 大量データ時の部分一致性能は別途評価が必要 |
| 投稿title・body検索 | 実装済み | `/search?category=posts`、NFKC・1〜50 codepoint・literal wildcardのhardened RPC、既存posts RLS、title / body OR、20件cursor pagination、ID再取得と共通hydrate・`TimelinePostCard`を使用 | 専用indexは追加せず、大量データ時の部分一致性能は別途評価が必要 |
| 検索category切替・paging | 一部実装済み | users / tags / postsをリンク型navigationで切り替え、canonical queryを維持してcursorを破棄する。タグと投稿はquery紐付きのopaque forward cursorを使用 | ユーザー検索のpaginationは未実装 |

関連コードは`src/app/(protected)/search/page.tsx`、`src/components/search/**`、`src/lib/search-query.ts`、`src/lib/search-cursor.ts`、`src/lib/user-search-data.ts`、`src/lib/tag-search-data.ts`、`src/lib/post-search-data.ts`である。関連migrationとテストは`20260726000500_secure_user_search_and_follows.sql`、`20260804000100_extend_user_and_tag_search.sql`、`20260806000100_add_post_search.sql`、`0004_user_search_and_follows.test.sql`、`0011_user_and_tag_search.test.sql`、`0012_post_search.test.sql`である。

### 4.9 その他のMVP・Phase 2機能

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| カレンダー | 実装済み | strict month/date parser、viewer timezone基準の現在月・今日・前後月、DST対応UTC half-open range、claims由来本人IDと既存posts RLSを使う本人月別query、日別件数・最新mood、`/calendar`のsemantic table月grid、前後月・今月遷移、marker、日付選択、選択日全投稿一覧を実装 | 実キーボードによるTab / Shift+Tab / Enter操作は手動確認へ持ち越し |
| 通常SNS通知 | 実装済み | DB / RLS、follow / reaction / comment / replyの4 typeに加えExchange 3 typeをparser対応し、`/notifications`、20件複合cursor、actor / target batch取得、未読badge、個別・すべて既読、Server側再評価による遷移、利用不能targetのneutral表示を実装 | なし |
| 設定 | 実装済み | `/settings`で現在のtimezone、runtime標準IANA option、保存中・成功・generic errorを表示し、Server Actionからclaims由来の本人IDと既存RLSで更新する | timezone以外の設定は後順位 |
| レスポンシブ | 一部実装済み | mobile-first class、`min-w-0`、`break-words`、`overflow-wrap:anywhere`、幅制限を主要画面に使用。投稿画像gallery、Calendar、Exchange一覧・招待・profile section・detail・confirmation・generic errorに加え、E3dの0 / 1 / 3 / 10枚galleryを320 / 360 / 375 / 390 / 1280pxで確認済み。長文・改行・連続半角文字列・長いlocationを含むactive / archived画面でも横overflowなし | repository内にviewport別の自動回帰テストはない |
| アクセシビリティ | 一部実装済み | label、role、aria-live、focus-visible、semantic heading/link/buttonを主要UIに使用。Calendarはcaption、column header、日付ごとのaccessible name、今日・選択日の状態を提供。Exchange confirmationはfocus移動・Escape close後のfocus復帰、pending live region、error `role=alert`、success `role=status`を実装し、E3d galleryはordered list、「交換日記の画像」label、順序を示すaltを提供する | 網羅的なkeyboard、contrast、screen readerの自動検証はなく、実screen readerによるE3d label / alt読み上げも未確認 |
| error handling・loading | 一部実装済み | not-found UI、role alert、empty state、Server Action error、送信中disabledを実装 | route-level `loading.tsx`、error boundary、再試行UIは未整備 |
| ログ・監視 | 一部実装済み | `/api/health/supabase`は秘密情報を返さず接続状態を返す | 集約ログ、監視、管理操作logはない |
| 振り返り | MVP後 | profileに総投稿数の基盤はあるが、正式仕様ではPhase 2 | 今月、連続投稿日数、去年の今日、timezone集計なし |
| 通常投稿・コメントの包括的な通報・管理 | MVP後 | `accounts.role/status`と、Exchange限定通報に将来拡張可能な`reports`基盤は存在 | 通常post / commentへの通報拡張、full admin dashboard、停止/解除操作、管理履歴はPhase 2以降 |

### 4.10 交換日記（Phase 1）

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| DB / Storage foundation | 実装済み | E2a〜E2gでstate / participant / invitation / block、operation RPC、entry / tag / redaction、private画像、通知3 type・全体preference・diary mute、report / snapshot、deactivation archive、retention / cleanup / trusted maintenanceをmigration管理。E3e-0bでnever-confirmed画像orphanの24時間grace・strict owner-path・reference除外・Storage-first lockを追加。E3f-0でactive-admin target / reporterのCOI欠落を発見し、E3f-1でreport / snapshot / exact evidence / status / purgeをrepository / local / remoteでhardeningした。remote catalogとlinked schema diffを確認し、最終security reviewは全severity 0件 | Application / UIと運用経路、`my_diary_create_user_report`のExchange scope hardeningは本項目に含めない |
| Application / UI | 一部実装済み | E3aのread / list / detail / notification compatibility、E3bのinvitation 6操作とblock / unblock、E3cのentry / diary mutation、E3dのcookie認証付き画像Route / galleryに加え、E3e-1でcreate、E3e-2でeditへ0〜10枚JPEG / PNG / WebP、6 MiB、magic-byte validation、preview、existing / new共通ordered state、追加・削除・並び替え、final complete manifest、strict 4 UUID path、private authenticated upload・`upsert:false`、画像統合successor RPCを接続した。cleanupは成功確認済みcurrent-attempt new pathだけとし、unknown outcomeではDELETEせず通常retryも停止する。removed existingはApplicationから物理DELETEせずcleanup candidate・7日retentionへ委譲し、raw pathをUIへ露出しない | report、moderation、maintenanceは未実装 |

## 5. DB・セキュリティ実装状況

### 5.1 tableと主要制約

| 対象 | 状態 | column | 主な制約・index・権限 |
| --- | --- | --- | --- |
| `accounts` | 実装済み | `user_id`、`role`、`status`、`timezone`、`created_at`、`updated_at` | Auth userへのcascade FK、role/status/timezone CHECK、IANA timezone validator trigger、本人SELECT、active時のtimezone更新 |
| `profiles` | 一部実装済み | `user_id`、`username`、`bio`、`avatar_path`、`created_at`、`updated_at` | Auth userへのcascade FK、文字数CHECK、`lower(username)` index、本人更新。suspended対象のSELECTはfail-closed済み。avatar upload / Storage / 表示・編集UIは未実装 |
| `posts` | 一部実装済み | `id`、`user_id`、`title`、`body`、`mood`、`location_name`、`visibility`、`created_at`、`updated_at`、`deleted_at` | Auth userへのcascade FK、入力値CHECK、partial index、可視性RLS。authenticatedの直接INSERT/UPDATEを閉じ、既存post/tag/image RPCとlocation対応successor RPCだけを一般作成・更新経路とする |
| `follows` | 実装済み | `follower_id`、`following_id`、`created_at` | 両userへのcascade FK、複合PK、self-follow CHECK、active関係だけのSELECT、following/follower安定順index |
| `reactions` | 実装済み | `id`、`post_id`、`user_id`、`reaction_type`、`created_at`、`updated_at` | post/accountへのcascade FK、3種類CHECK、投稿×ユーザーUNIQUE、post/type index、可視post連動RLS |
| `comments` | 一部実装済み | `id`、`post_id`、`user_id`、`body`、`parent_comment_id`、`created_at`、`updated_at`、`deleted_at` | post/accountへのcascade FK、body/deleted_at CHECK、通常comment・返信のpartial index、可視post連動RLS、soft-delete RPC。返信関係はDB triggerで1階層・same-post・parent存在・未削除・active authorを保証 |
| `tags` | 実装済み | `id`、`name`、`normalized_name`、`created_at` | NFKC canonical name、30 codepoint上限、文字種制約、UNIQUE、可視post連動SELECT。master mutationはatomic RPC内部だけで、入力・投稿表示・一覧・詳細・検索UIを実装済み |
| `post_tags` | 一部実装済み | `post_id`、`tag_id`、`created_at` | 複合PK、cascade FK、逆引きindex、可視post連動SELECT RLS。RPC内の最大5個検証、post row lock、差分更新を実装 |
| `post_images` | 実装済み | `id`、`post_id`、`storage_path`、`sort_order`、`created_at` | post物理削除へのcascade FK、`sort_order` 0〜9 CHECK、投稿×順序のdeferrable UNIQUE、path UNIQUE、可視post連動SELECT RLS。authenticatedの直接mutationはなく、作成・編集RPCがStorage object確認後にmetadataをatomic確定・更新。同一origin routeがRLS下でpathを解決して配信し、clientへはidと順序だけを渡す |
| `notifications` | 実装済み | `id`、`recipient_user_id`、`actor_user_id`、`notification_type`、`target_post_id`、`target_comment_id`、`is_read`、`created_at` | account / post / commentへのcascade FK、4 typeとtarget shape・自己通知拒否CHECK、recipient安定順index、active recipient / actorと現在のposts RLSを再評価するrecipient専用SELECT / UPDATE RLS、authenticatedは`UPDATE(is_read)`のみ。DB trigger生成とRLS下の一覧・既読UIを実装 |

Postgres enumは使用せず、`role`、`status`、`mood`、`visibility`、`reaction_type`をtextとCHECK制約で管理している。主要FKはuser削除またはpost削除に対するcascadeを設定している。物理DELETEは一般ユーザーへ付与せず、postとcommentは専用RPCでsoft deleteする。

### 5.2 Exchange / report schema inventory

Public tableは次の12件である。

| 分類 | table |
| --- | --- |
| state / invitation | `exchange_diaries`、`exchange_diary_participants`、`exchange_invitations`、`exchange_invitation_blocks` |
| entry / image | `exchange_entries`、`exchange_entry_tags`、`exchange_entry_images` |
| notification setting | `exchange_notification_preferences`、`exchange_diary_mutes` |
| report / snapshot | `reports`、`report_exchange_entry_snapshots`、`report_snapshot_images` |

Private tableは`my_diary_private.my_diary_exchange_pair_locks`と`my_diary_private.exchange_entry_image_cleanup_candidates`の2件、private Storage bucketは`exchange-entry-images`である。対となるparticipantを固定するpair lock、通常removed画像の7日cleanup candidate、terminal report evidenceの実transition後30日保持を支える。

### 5.3 RLS、function、trigger、ACL

- 22個のpublic tableすべてでRLSを明示的に有効化し、authenticatedの一般table権限はSELECT中心の最小ACLとしている。
- public tableのeffective policyは33件、`storage.objects`のproject policyは19件（post画像8、Exchange画像11）である。Exchange画像の11件には4件のRESTRICTIVE guardを含み、UPDATE / move / upsertは許可しない。
- `posts` SELECTは本人、active viewer、active author、follow関係、visibility、`deleted_at`をDB側で評価する。
- reactionsとcommentsは、参照先postを現在のviewerが閲覧できる場合だけSELECT・mutationできる。
- post_tagsは可視postだけをSELECTでき、tagsは可視なpost_tagsが存在する場合だけSELECTできる。tags → post_tags → postsの一方向評価とし、private・権限外followers・soft-delete済みpostだけに紐づくtag名を隠す。
- post_imagesは可視postだけをSELECTできる。`storage.objects`は対応metadataが見える場合、または通常upload / cleanup中の本人所有orphanだけをSELECTできる。INSERT / DELETEはStorage operation context、本人owner、3 UUID segment path、active状態または未参照状態を検査し、UPDATE / upsertは許可しない。標準Storage tableのowner、ACL、owner_idは変更していない。
- Exchangeの12 public tableはowner=`postgres`、RLS明示有効、authenticatedはSELECTのみ、anonは権限なしで、一般userの直接mutation grantはない。主要mutationは`auth.uid()`、active状態、participant / owner、対象IDと状態遷移を再検証するRPCに限定する。
- Exchange画像はowner / diary / entry / imageの4 UUID pathを検証し、通常readはactive participant、通報evidence readは対象reportのreporterでもreported userでもないactive adminによるexact snapshot pathだけに限定する。一般userによるconfirmed / candidate画像のDELETEは許可しない。
- Phase E3e-0bのnever-confirmed orphan cleanupは、strict 4 UUID path、Storage ownerとpath ownerの一致、24時間grace、live `exchange_entry_images` metadataなし、confirmed cleanup candidateなし、`report_snapshot_images` evidence参照なしをすべて満たす場合だけ、active adminかつ`storage.object.delete_many` contextへ許可する。Storage rowを最初にlockしてから参照を再検証し、create / update successor RPCとのconfirm raceを直列化する。既存のconfirmed画像7日retention、terminal evidence 30日retention、Exchange画像Storage policy 11件（RESTRICTIVE guard 4件）は変更していない。
- E3dのparticipant向け画像Routeはlive `exchange_entry_images`を唯一の入口とし、同じauthenticated clientでmetadata RLSとStorage RLSを再評価する。report snapshot、evidence、cleanup candidate、retention queueは参照せず、removed・soft-deleted・snapshot-only・evidence-only画像を通常Routeへ戻さない。
- E2h-1aではreport targetへの漏洩なしと判定していたが、E3f-0でactive admin本人がtargetまたはreporterの場合のreport / snapshot / evidence閲覧とstatus / purge自己操作をBLOCKERとして確認した。E3f-1はreport 3表RLS、exact-evidence Storage helper、status RPC、purge RPCに同じNULL-safe COI guardを追加し、unrelated active adminのmoderation、reporter NULL、admin whole-diary禁止、期限前purge拒否を維持した。repository / local / remoteへ適用済みである。
- `my_diary_is_account_active`と`my_diary_can_view_post`をprivate schemaへ置き、再帰的RLSを避けている。
- `my_diary_validate_comment_parent`は一般roleから直接実行できないprivate trigger functionで、返信INSERT時にparent rowをlockし、1階層・same-post・未削除・active authorを検証する。ownerは`postgres`、`SECURITY DEFINER`、空search pathである。
- `my_diary_validate_account_timezone`は`pg_timezone_names`の完全一致を使うprivate trigger functionで、`accounts` INSERTとtimezone UPDATEを検証する。`posix/*`重複treeとIntl非対応の`Factory`を除外し、ownerは`postgres`、`SECURITY INVOKER`、空search path、一般roleの直接EXECUTEなしである。
- `my_diary_normalize_tag_name`をprivate schemaへ置き、NFKC、前後空白、先頭`#`、連続空白、ASCII caseを決定的にcanonical化する。一般application roleにはEXECUTEを付与しない。
- `my_diary_soft_delete_post`、`my_diary_soft_delete_comment`は本人とactive状態を再検証する。
- `my_diary_create_post_with_tags`と`my_diary_update_post_with_tags`は投稿本体とtag relationを同一transactionで処理し、後者はpost row lockと差分更新を使用する。
- `my_diary_create_post_with_images_and_location`と`my_diary_update_post_with_images_and_location`は、既存画像統合RPCの認証・active account・所有権・row lock・tag/image validationを同じtransaction内で再利用し、正規化済み`location_name`までatomicに確定する。既存Application用RPCはsignatureとsemanticsを維持する。
- `my_diary_search_profiles`はauthenticated identity、NFKC、入力長、literal wildcard、active対象、20件上限を関数内で検証する。
- `my_diary_search_tags`は`SECURITY INVOKER`で既存tags RLSを通し、authenticated identity、NFKC canonical query、literal wildcard、cursor、21件取得を検証する。21件目はUIの次ページ判定だけに使用する。
- `my_diary_search_posts`は`SECURITY INVOKER`で既存posts RLSを通し、authenticated identity、NFKC、1〜50 codepoint、literal wildcard、title / body OR、`created_at DESC, id DESC`のcursor、最大21件を検証する。UIは20件を表示し、RPCのIDだけを通常SELECTで再取得して現在のRLSを再評価する。
- `SECURITY DEFINER`関数はownerを`postgres`へ固定し、空の`search_path`または`pg_catalog`固定を使用する。
- table・column・functionの権限は既定権限をREVOKEして必要なauthenticated権限だけをGRANTする。
- `rls_auto_enable()`はevent trigger `ensure_rls`からpublic schemaの新規table、partitioned table、CTAS、SELECT INTOへRLSを有効化する。policyやFORCE RLSは作成しない。
- `rls_auto_enable()`のEXECUTEは`PUBLIC`、`anon`、`authenticated`、`service_role`、`authenticator`からREVOKEされ、`postgres`だけに残る。

通常triggerは、`updated_at`更新、Auth user作成時のaccount/profile作成、通知生成、entry redaction、report retention deadline、deactivation archive等に使用する。別にevent trigger `ensure_rls`が存在する。

### 5.4 未作成の主要table

`notifications`は通常4 typeに加えExchange 3 typeのDB生成・preference / muteと、E3aのApplication parser・neutral target・一覧 / 詳細遷移まで作成済みである。`reports`、`report_exchange_entry_snapshots`、`report_snapshot_images`はExchange Phase 1の限定通報・証拠保持基盤として作成済みである。通常post / comment通報への拡張はPhase 2以降である。Phase 3以降のcategories、favorites、communities、plushies、events、albumsと各紐付けtableは未作成である。

## 6. MVP後の機能

| 項目 | 状態 | 現在の基盤・補足 |
| --- | --- | --- |
| 正式カテゴリー・興味タグ | MVP後 | `posts`に`category_id`はなく、カテゴリーtableもない。MVPの自由タグは入力・投稿リンク・一覧・詳細・検索まで実装済み |
| 推しプロフィール・推し日記・推しページ・推し検索 | MVP後 | 対応table、route、componentなし |
| 推しコミュニティ | MVP後 | 対応table、membership、thread、message、通報基盤なし |
| ぬいプロフィール・ぬい活日記 | MVP後 | 対応table、route、componentなし |
| イベント | MVP後 | 対応table、route、componentなし |
| アルバム | MVP後 | 対応table、route、componentなし |
| おすすめ | MVP後 | 興味data、ranking query、routeなし |
| 専用入力フォーム | MVP後 | 通常の日記formだけが存在 |
| AI | MVP後 | AI SDK、API、外部送信処理なし |
| プレミアム | MVP後 | 課金provider、plan、entitlementなし |

カテゴリー、推し活、コミュニティ、ぬい活、イベント、アルバム、おすすめ、専用入力フォーム、AI、プレミアムはこの文書の状態集計で10件の「MVP後」として扱う。コードが存在しないことは現MVPの欠陥には数えない。

## 7. 実装済みroute一覧

`src/app`配下のpage / route handlerは現在31件である。

| route | 種別 | 役割 |
| --- | --- | --- |
| `/` | page | landing、新規登録・ログイン導線 |
| `/login` | page | email/passwordログイン |
| `/sign-up` | page | email/password会員登録 |
| `/forgot-password` | page | account存在を露出しないパスワード再設定メール申請 |
| `/reset-password` | page | SDK marker・JWT AMR・account状態を再検証したrecovery session専用のpassword更新 |
| `/auth/callback` | route handler | email確認またはpassword recoveryのPKCE codeをsessionへ交換し、固定same-origin pathへ遷移 |
| `/home` | page | 認証済みviewer向けのフォロー中・最新投稿timeline。20件forward cursor pagination、feed bind、不正cursorのgeneric error、home本文280 codepoints省略に対応（`feed=following` / `feed=latest`） |
| `/calendar` | page | viewer timezone基準の本人月別Calendar。前後月・今月遷移、日別件数・最新mood marker、今日・選択日、選択日投稿一覧を表示（`month=YYYY-MM&date=YYYY-MM-DD`） |
| `/notifications` | page | RLS上見える通知を20件ずつ表示し、未読 / 既読、個別・すべて既読、target遷移を提供 |
| `/exchange` | page | participant本人の交換中・pending招待・終了済み交換日記を表示し、view別empty stateとpagination、新規交換日記へのfollowing / search導線、receivedのaccept / reject、sentのcancelを提供 |
| `/exchange/[diaryId]` | dynamic page | participant-onlyの交換日記詳細、oldest / latest entry pagination、削除済みplaceholder、mood・場所・非リンクtag・画像件数を表示。active時のtitle変更・archive、本人entryの編集・soft delete、archive後の本人entry削除を提供 |
| `/exchange-entry-images/[imageId]` | route handler | cookie認証、live Exchange画像metadata / participant RLS、authoritative 4 UUID path、Storage RLS、MIME / magic byte / sizeを再評価し、private画像をno-storeで配信。全deny / errorはempty 404 |
| `/exchange/[diaryId]/entries/new` | dynamic page | active participant向けentry作成。title・本文・mood・場所・最大5 tagに加え、0〜10枚のprivate画像選択・preview・削除・選択順保持・uploadを提供し、画像統合successor RPCへ接続 |
| `/exchange/[diaryId]/entries/[entryId]/edit` | dynamic page | active diary内の本人・未削除entryだけをdiary / entry組で再検証し、existing / new画像の保持・削除・並び替えとfinal complete manifestを画像統合update successorへ接続 |
| `/settings` | page | viewer本人の現在timezoneを表示し、runtime標準IANA optionから選択してServer Actionで保存 |
| `/tags` | page | RLS上閲覧可能なタグをcanonical名順に50件ずつ表示 |
| `/tags/[tagId]` | dynamic page | UUIDで識別したタグと、RLS上閲覧可能な投稿を20件ずつ表示 |
| `/posts/new` | page | 日記作成 |
| `/post-images/[imageId]` | route handler | cookie認証とpost_images / Storage RLSを通し、private画像をno-storeで配信 |
| `/posts/[postId]` | dynamic page | 閲覧可能な日記詳細、reaction、comment |
| `/posts/[postId]/edit` | dynamic page | 本人の日記編集 |
| `/profile` | page | 自分のプロフィール |
| `/profile/edit` | page | username、bio編集 |
| `/profile/posts` | page | 自分の未削除投稿一覧 |
| `/profile/following` | page | 自分のfollowing一覧 |
| `/profile/followers` | page | 自分のfollowers一覧 |
| `/users/[userId]` | dynamic page | 他ユーザーのプロフィールと閲覧可能投稿に加え、Exchange sectionでmutual-follow時のinvite、pending導線、invitation専用block / unblockを提供 |
| `/users/[userId]/following` | dynamic page | 他ユーザーのfollowing一覧 |
| `/users/[userId]/followers` | dynamic page | 他ユーザーのfollowers一覧 |
| `/search` | page | users / tags / posts category切替、NFKC canonical query、ユーザー・タグ・投稿title/body部分一致検索、タグ・投稿cursor pagination |
| `/api/health/supabase` | route handler | Supabase Auth healthの安全な状態応答 |

`not-found.tsx`はpost詳細、profile系、tag詳細、Exchange詳細に存在する。タグrouteとExchange routeには`loading.tsx`がある。専用のprotected layoutと`error.tsx`は存在しない。未認証時のpage-level redirectは各pageに残し、non-active accountのstatus確認・session終了はrequestごとに再評価されるProxyと共通helperへ集約している。

Exchange invitation operationとdiary / entry mutationはServer Actionから既存RPCへ接続済みで、private画像の取得・表示もsame-origin Routeへ接続済みである。E3e-1で新規entryの画像upload / create、E3e-2でexisting / new画像のeditをsuccessor RPCへ接続した。report submission、admin moderation、moderator evidence、trusted maintenanceのApplication経路はまだ存在しない。計画中のrouteは上の実装済み一覧に含めない。

## 8. migration一覧

repository / local / remoteは32件で一致し、latestは`20260816000200_harden_report_moderation_conflict_of_interest.sql`である。

| timestamp | ファイル名 | 主な目的 |
| --- | --- | --- |
| `20260725000100` | `20260725000100_create_core_schema.sql` | private schema、accounts、profiles、posts、follows、制約、index、Auth/updated_at trigger、active判定、post soft delete、RLS、policy、grant |
| `20260726000100` | `20260726000100_create_reactions.sql` | reactions table、3種類CHECK、UNIQUE、index、updated_at trigger、RLSと4 policy |
| `20260726000200` | `20260726000200_create_comments.sql` | comments table、body/deleted_at制約、partial index、updated_at trigger、RLSと初期policy |
| `20260726000300` | `20260726000300_add_comment_soft_delete.sql` | post可視性helper、post SELECT policy置換、comment直接UPDATE取消、comment soft-delete RPC |
| `20260726000400` | `20260726000400_fix_post_visibility_helper.sql` | 可視性helperを行値引数へ変更してRLS再帰を回避し、comment soft-delete RPCを追従 |
| `20260726000500` | `20260726000500_secure_user_search_and_follows.sql` | active targetだけのfollow INSERT、hardened username検索RPC |
| `20260801000100` | `20260801000100_secure_follow_lists.sql` | active viewer・両端userだけのfollow SELECT、following/follower安定順index |
| `20260801000200` | `20260801000200_manage_rls_auto_enable.sql` | 既存RLS自動有効化関数とevent triggerをpreflight付きでmigration管理し、EXECUTE ACLをhardening |
| `20260802000100` | `20260802000100_create_tags.sql` | tag normalizer、tags・post_tags、canonical制約、index、可視post連動SELECT RLS、read-only ACL |
| `20260802000200` | `20260802000200_create_atomic_post_tag_mutation.sql` | atomic post/tag作成・更新RPC、最大5個検証、row lock、差分更新、posts直接INSERT/UPDATE grant取消、RPC ACL |
| `20260804000100` | `20260804000100_extend_user_and_tag_search.sql` | ユーザー検索のNFKC化、タグ検索query normalizer、RLSを通すタグ検索RPC、literal wildcard、cursor、ACLとcatalog検証 |
| `20260806000100` | `20260806000100_add_post_search.sql` | RLSを通す投稿title/body検索RPC、NFKC、literal wildcard、`created_at DESC, id DESC` cursor、ACLとcatalog検証 |
| `20260808000100` | `20260808000100_create_post_images_storage.sql` | private post画像bucket、post_images、最大10枚・順序・path制約、posts RLS委任、Storage SELECT allowとRESTRICTIVE guard、最小ACL |
| `20260808000200` | `20260808000200_integrate_post_image_uploads.sql` | JPEG / PNG / WebP・6 MiB制限、operation-aware upload / orphan cleanup policy、strict owner path、Storage object row lock、atomic post/tag/image作成RPC、最小ACL |
| `20260808000300` | `20260808000300_integrate_post_image_edits.sql` | final JSONB image manifest、post row lock、保持画像identity、追加path検証、metadata削除・順序更新をatomicに行う編集RPC、削除旧path返却、最小ACL |
| `20260808000400` | `20260808000400_fail_close_non_active_accounts.sql` | suspended / deactivated accountのprofile、post、search、Storage orphan経路を既存機能横断でfail-closed化 |
| `20260809000100` | `20260809000100_add_comment_replies.sql` | nullable parent relation、1階層・same-post・未削除・active parentを検証するlocking trigger、返信取得index、既存RLSを維持した最小INSERT列権限 |
| `20260809000200` | `20260809000200_create_notifications.sql` | notifications、4 type / target shape / 自己通知CHECK、account・post・commentへのcascade FK、recipient安定順index、active recipient / actorとposts RLSを再評価するSELECT / UPDATE policy、SELECT＋`UPDATE(is_read)`の最小ACL |
| `20260809000300` | `20260809000300_generate_notifications.sql` | follow / reaction / comment / replyの同一transaction通知生成trigger、trigger専用functionと最小ACL |
| `20260809000400` | `20260809000400_validate_account_timezones.sql` | PostgreSQL timezone catalogに基づくaccounts INSERT / timezone UPDATE validator、runtime非互換値除外、trigger専用ACL |
| `20260810000100` | `20260810000100_add_location_name_atomic_mutation.sql` | 既存画像統合RPC互換性を維持したlocation_name対応作成・編集successor RPC、正規化、100 codepoint境界、atomic rollback、最小ACL |
| `20260811000100` | `20260811000100_create_exchange_diary_state_foundation.sql` | diary / participant / invitation / blockのstate、RLS、ACL基盤 |
| `20260811000200` | `20260811000200_add_exchange_diary_operation_rpcs.sql` | invitation create / accept / reject / cancel、title変更、archive等のatomic operation RPC |
| `20260811000300` | `20260811000300_create_exchange_entries.sql` | Exchange entry / entry tag、CRUD、redaction、participant-only取得 |
| `20260811000400` | `20260811000400_integrate_exchange_entry_images.sql` | private Exchange画像bucket、metadata、upload / read / edit / cleanup境界 |
| `20260811000500` | `20260811000500_add_exchange_diary_notifications.sql` | Exchange 3通知type、全体new-entry preference、diary mute |
| `20260811000600` | `20260811000600_create_reports_and_exchange_snapshots.sql` | reports、entry text / image snapshot、対象entry限定のactive-admin moderation境界 |
| `20260811000700` | `20260811000700_archive_exchange_diaries_on_deactivation.sql` | participant deactivation時のactive diary atomic archiveと`participant_deactivated` cause |
| `20260811000800` | `20260811000800_harden_exchange_invitation_block_privacy.sql` | block時pending reject、24時間cooldown、privacy oracle、lock順の強化 |
| `20260811000900` | `20260811000900_harden_exchange_image_evidence_retention.sql` | 通常removed画像7日保持、terminal evidence 30日保持、trusted maintenance、exact-evidence Storage境界 |
| `20260816000100` | `20260816000100_harden_unconfirmed_exchange_image_orphan_cleanup.sql` | never-confirmed Exchange画像orphanの24時間grace、strict owner-path、live / confirmed candidate / evidence除外、Storage-first lock、active-admin maintenance境界 |
| `20260816000200` | `20260816000200_harden_report_moderation_conflict_of_interest.sql` | target / reporter本人のactive adminをreport row・snapshot・exact evidence・status・purgeからNULL-safeに除外し、unrelated active adminのmoderationを維持 |

Phase B2b-3aでは既存10 migrationを変更せず、`20260804000100_extend_user_and_tag_search.sql`を1件追加した。ローカルresetで11件すべてをfresh適用した後、この1件だけをリンク済みのリモート開発DBへ通常適用した。local / remote履歴は11件で一致し、適用後の再dry-runはup to date、pg-deltaによる`public,my_diary_private`のlinked schema diffは空だった。migration transaction内のpostconditionと空のcatalog diffを組み合わせ、両検索RPCとprivate helperのsignature、引数名、return shape、owner、volatility、security属性、固定search path、ACL、および既存tags RLS・policy・table ACLの維持を確認した。適用後のcatalog cache生成では一時CA証明書を参照できない補助warningが発生したが、migration適用は終了コード0で完了し、remote履歴と再dry-runで成功を確認したため再適用していない。リモートfixture・ユーザーデータ操作・Service Roleは使用せず、Git stage・commit・pushも実施していない。

Phase B2b-3bでは既存11 migrationを変更せず、`20260806000100_add_post_search.sql`を1件追加した。ローカルresetで12件をfresh適用し、新規pgTAP `52 / 52`、全pgTAP `528 / 528`、`public,my_diary_private`のlocal schema diff 0件、local catalog一致を確認した。Phase終了時点では新規migrationはリモート未適用で、remote dry-run・remote catalog・linked schema diffも未実施だったが、後続Phaseで適用された。B3d時点ではlocal / remote履歴15件、C1a適用後の現在は16件で一致している。

Phase B3aでは既存12 migrationを変更せず、`20260808000100_create_post_images_storage.sql`を1件追加した。ローカルresetで13件をfresh適用し、新規pgTAP `75 / 75`、全pgTAP `603 / 603`、`public,storage,my_diary_private`のlocal schema diff 0件を確認した。新規migrationだけをリンク済みのリモート開発DBへ通常適用し、local / remote履歴13件一致、再dry-run up to date、remote catalogのbucket・table・constraint・RLS・ACL・Storage policy一致、linked schema diff 0件を確認した。適用後のpg-delta catalog cache生成warningはmigration SQL成功後の後処理warningと切り分け、repairや再適用は行っていない。

Phase B3bでは既存13 migrationを変更せず、`20260808000200_integrate_post_image_uploads.sql`を1件追加した。ローカルresetで14件をfresh適用し、新規pgTAP `47 / 47`、画像関連 `122 / 122`、全pgTAP 14ファイル・`650 / 650`を確認した。通常のローカル認証ユーザーとpublishable clientによるStorage upload、orphan remove、参照済みremove拒否、atomic metadata確定も実APIで確認した。新規migrationだけをリンク済みのリモート開発DBへ通常適用し、local / remote履歴14件一致、再dry-run up to date、remote catalogのbucket・Storage policy・RPC属性 / ACL・既存RLS / RPC・標準Storage owner一致、`public,storage,my_diary_private`のlinked schema diff 0件を確認した。migration SQL成功後のpg-delta catalog cache生成warningは履歴・catalog・再dry-run・schema diffと切り分け、repairや再適用は行っていない。安全な既存remote認証情報がないためremote実upload / RPC mutationは未実施であり、remote fixture・ユーザーデータ・Storage objectの作成や変更、Service Role、Auth Admin APIは使用していない。

## 9. テスト状況

### 9.1 pgTAP定義

| ファイル | plan | 主な対象 |
| --- | ---: | --- |
| `0001_core_rls.test.sql` | 45 | Auth trigger、core function ACL、post visibility、follow、profile/account権限、post soft delete |
| `0002_reactions_rls.test.sql` | 45 | reactions schema、ACL、4 policy、3種類、追加・変更・削除、visibility、suspended、follow変化 |
| `0003_comments_rls.test.sql` | 63 | comments schema、ACL、可視性helper、soft-delete RPC、閲覧境界、suspended、soft delete |
| `0004_user_search_and_follows.test.sql` | 30 | search RPC、入力境界、case-insensitive/literal検索、active対象、20件、follow安全性 |
| `0005_post_edit_rls.test.sql` | 20 | editable column、所有者、suspended、soft delete、文字数、mood/visibility、可視性変更 |
| `0006_user_profile_posts_rls.test.sql` | 13 | 他者profile投稿のpublic/followers/private境界、soft delete、author/viewer suspended、順序 |
| `0007_follow_lists_rls.test.sql` | 22 | follow SELECT policy、安定順index、suspended両端、追加・削除回帰 |
| `0008_rls_auto_enable.test.sql` | 29 | function/event trigger定義、ACL、CREATE TABLE/CTAS/SELECT INTO、非対象schema、非遡及 |
| `0009_tags_rls.test.sql` | 71 | normalizer、schema、制約、ACL、public/followers/private/soft delete/suspended、visibility変更、RLS非再帰、cascade |
| `0010_post_tag_mutation_rpc.test.sql` | 68 | RPC catalog/ACL、direct grant閉鎖、作成・更新、tag validation、最大5個、NULL/空配列、差分更新、rollback |
| `0011_user_and_tag_search.test.sql` | 70 | user NFKC・literal検索、tag query canonical化、RPC catalog/ACL、RLS可視境界、cursor、20+1件、visibility・follow・soft delete変化 |
| `0012_post_search.test.sql` | 52 | 投稿検索RPC catalog/ACL、NFKC・literal検索、title/body OR、RLS可視境界、follow・visibility・soft delete・suspended、21件・cursor順序 |
| `0013_post_images_storage_rls.test.sql` | 75 | private bucket、post_images schema/FK/constraint/index/RLS/ACL、最大10枚、順序・path境界、visibility・follow・soft delete・suspended、Storage SELECT/guard/mutation拒否 |
| `0014_post_image_upload_mutation.test.sql` | 47 | successor RPC catalog/ACL、Storage operation・owner・strict path、0 / 10 / 11枚、順序、post/tag/image atomic確定、suspended、rollback |
| `0015_post_image_edit_mutation.test.sql` | 36 | 編集RPC catalog/ACL、0 / 10 / 11枚、保持・追加・削除・並び替え、foreign/missing/duplicate拒否、identity維持、atomic rollback |
| `0016_non_active_account_fail_closed.test.sql` | 79 | C1a catalog/ACL、active回帰、suspended/deactivated viewer、non-active target、accounts status最小経路、Storage orphan境界 |
| `0017_comment_replies_rls.test.sql` | 45 | parent column・index・trigger function/ACL、top-level/reply、grandchild・cross-post・deleted parent・spoof拒否、不可視parentのgeneric error、visibility・soft/physical delete回帰 |
| `0018_notifications_rls.test.sql` | 65 | notifications schema / CHECK / cascade FK / index、RLS / ACL、recipient・actor active境界、現在のpost可視性再評価、既読列更新、自己通知拒否、physical delete cascade |
| `0019_notification_generation.test.sql` | 48 | 3 trigger functionの属性 / ACL、follow / reaction / comment / reply生成、自己通知防止、解除・更新・再追加、invalid reply generic error、特権fixture境界、atomic rollback |
| `0020_account_timezone_validation.test.sql` | 31 | timezone validator function / trigger / ACL、IANA値、無効・空・内部timezone拒否、本人・他人・non-active、role / status境界 |
| `0021_location_name_atomic_mutation.test.sql` | 48 | successor RPC catalog / ACL、NULL・空・trim・100/101境界、active/non-active・所有権・soft delete、tag/image併用とrollback、既存RPC互換性 |
| `0022_exchange_diary_state_foundation.test.sql` | 83 | diary / participant / invitation / block state、RLS、ACL、suspended / archived境界 |
| `0023_exchange_diary_operation_rpcs.test.sql` | 95 | invitation・開始・拒否・cancel・archive・title operation RPCと競合境界 |
| `0024_exchange_entries.test.sql` | 93 | entry / tag、validation、participant-only、redaction、archived mutation境界 |
| `0025_exchange_entry_images.test.sql` | 86 | Exchange画像metadata / Storage、path、upload / read / edit / delete境界 |
| `0026_exchange_diary_notifications.test.sql` | 88 | Exchange 3通知type、生成、全体preference、diary mute |
| `0027_reports_and_exchange_snapshots.test.sql` | 96 | reports / snapshots、reporter / target privacy、対象entry限定admin閲覧 |
| `0028_archive_exchange_diaries_on_deactivation.test.sql` | 37 | deactivation時archive、cause、復帰禁止、active相手のarchive read |
| `0029_harden_exchange_invitation_block_privacy.test.sql` | 36 | block時reject、explicit rejectとのobservable / cooldown一致、lock順 |
| `0030_exchange_image_evidence_retention.test.sql` | 57 | 7日cleanup candidate、30日evidence retention、trusted maintenance、multiple reference保護 |
| `0031_unconfirmed_exchange_image_orphan_cleanup.test.sql` | 45 | 24時間境界、strict owner-path、live / candidate / evidence除外、active-admin ACL、Storage DELETEと保護対象残存 |
| `0032_report_moderation_conflict_of_interest.test.sql` | 37 | target-admin / reporter-admin COI、NULL reporter、ordinary / non-active denial、exact evidence、status / purge、whole-diary回帰 |
| 合計 | 1,755 | 32ファイル |

### 9.2 実行結果の区別

- 最新確認済みlocal結果は32ファイル・`1,755 / 1,755 PASS`である。内訳はpre-Exchange `0001`〜`0021`が21ファイル・1,002 assertions、Exchange `0022`〜`0032`が11ファイル・753 assertionsである。Phase E3f-1ではlocal `auth.users` / `reports` / `storage.objects`が0件であることと5542xのproject限定環境を確認後、32 migrationをfresh適用し、新規`37 / 37`、関連`0025 / 0027 / 0030 / 0031`の`284 / 284`、全32ファイルを再実行した。

- Phase E3f-1 remote確定 PASS。active adminであっても自分がreported userまたはreporterのreportについて、report row、text / image snapshot、exact Storage evidence、status更新、期限後purgeを拒否する。unrelated active admin、reporter NULL、既存status transition、terminal実遷移+30日、confirmed removed画像7日、never-confirmed orphan 24時間、multiple reference、participant画像Route、admin whole-diary禁止を維持した。repository / local / remoteは32 migrationで一致し、再dry-runはup to date、remote catalogはmigration意図と一致、`public,my_diary_private,storage`のlinked schema diffは空だった。適用後の既知pg-delta CA warningは履歴・再dry-run・catalog・diffでSQL成功と切り分け、repair・再適用はしていない。`lint`、`typecheck`、`build`、`git diff --check`はPASSし、最終read-only security reviewはBLOCKER / HIGH / MEDIUM / LOWすべて0件。Application source、report submission、admin UI、moderator evidence Route、maintenance経路、`my_diary_create_user_report`のglobal scopeは変更していない。

- Phase E3e-2 COMPLETE。Exchange entry editへexisting画像の保持・削除・並び替え、new画像追加・削除、existing / new混在順序、全画像削除、0〜10件のfinal complete manifestを接続し、`my_diary_update_exchange_entry_with_images`へ切り替えた。existing IDを維持し、new画像だけをstrict 4 UUID pathへ`upsert:false`でuploadする。partial upload failureと明確なRPC rollbackではcurrent-attempt new objectだけをbest-effort cleanupし、unknown outcomeではStorage DELETEせず通常retryを停止する。成功後のremoved existingはApplicationから物理DELETEせず、relation解除、cleanup candidate、通常participantから即不可視、7日retention、evidence条件、trusted maintenanceの既存lifecycleへ委譲する。raw Storage path非露出、editで新規entry通知を増やさない境界、E3e-1 create画像機能を維持した。実装Phaseの対象pgTAPは`502 / 502 PASS`、全pgTAPはproject限定volume cleanup・clean rebuild後に今回`1,718 / 1,718 PASS`。`lint`、`typecheck`、`build`はE3e-2実装Phaseの最終PASS結果、`git diff --check`もPASS。最終security reviewはBLOCKER / HIGH / MEDIUM / LOWすべて0件。1280pxは実測済みだが、Browser viewport capabilityが指定幅を反映せず320 / 360 / 375 / 390pxは未実施である。follow解除の最終Browser操作、archive / status / deactivated / suspended race、soft-delete stale edit、強制partial upload failure、real transport / network unknown outcome、実keyboard、実screen readerも未実施で、DB pgTAPとcode reviewの代替確認と区別する。

- Phase E3e-1 COMPLETE。Exchange entry createにJPEG / PNG / WebPを0〜10枚、1枚6 MiB、0 byte拒否、magic-byte validation、preview・選択画像削除・選択順保持を追加した。caller-generated entry UUIDとimage UUIDからowner / diary / entry / imageのstrict 4 UUID pathを生成し、authenticated private Storageへ`upsert:false`でuploadする。createは0枚も含め`my_diary_create_exchange_entry_with_images`のみへ完全移行し、editはlegacy updateを維持した。partial upload failureは成功応答確認済みpathだけ、明確なRPC rollbackでは今回のnew objectだけをbest-effort cleanupする。network / transport・不正な戻り値・revalidation失敗のunknown outcomeではStorage DELETEせず、通常retryも停止してreload / 一覧確認を促す。E3e-0bの24h trusted orphan cleanupと連携し、follow解除後create、archive / status raceのfail-closed、raw path非露出を維持する。対象pgTAPは実装Phaseで`406 / 406 PASS`、全pgTAPは今回clean rebuild後に`1,718 / 1,718 PASS`。`lint`、`typecheck`、`build`はE3e-1実装Phaseの最終PASS結果、`git diff --check`は今回PASS。最終security reviewはBLOCKER / HIGH / P1すべて0件。existing画像追加・削除・並び替え、final complete manifest、edit successor Application接続はE3e-2として未実装・未着手である。

- Phase E3e-0b COMPLETE。never-confirmed Exchange画像orphan cleanupを、Storage `created_at`基準の24時間grace、strict 4 UUID path / owner-path一致、live metadata・confirmed cleanup candidate・report snapshot evidenceの除外、trusted active-admin maintenanceだけのruntime gateでhardeningした。最終認可はStorage rowを先にlockしてから参照を再検証し、前Phaseの2-session確認ではconfirm-firstが`object=1 / entry=1 / metadata=1 / cleanup delete=0`、cleanup-firstが`object=0 / entry=0 / metadata=0 / successor fail-closed`で、両方の実Lock待機を確認した。repository / local / remote migrationは`31 / 31 / 31`、適用後dry-runはup to date、remote catalogでは新規listing function 1 overload、postgres owner、SECURITY DEFINER、固定search path、authenticated session内のactive-admin再検証、PUBLIC / anon / service_role / authenticatorへの実行権限なし、既存Storage policy 11件・RESTRICTIVE guard 4件、7日 / 30日retentionを確認し、`public,my_diary_private,storage`のlinked schema diffは空だった。remote fixture、Storage upload / DELETE、Auth user mutation、Service Role、Auth Admin APIは使用していない。適用直後のpg-delta catalog cacheには既知のCAファイルwarningが出たが、migration履歴・再dry-run・catalog dump・空のlinked diffでSQL適用成功と切り分け、repairや再適用は行っていない。E3e-1は未着手である。

- Phase E3dではDB schema・RLS・migration・pgTAP定義・packageを変更せず、cookie認証付き`/exchange-entry-images/[imageId]`、live metadataのbounded hydrate、private no-store応答、neutral empty 404、raw Storage path非露出、既存galleryの狭いvariantを実装した。通常authenticated fixtureでparticipant A / Bは200、第三者C・未認証・malformed / nonexistent UUIDは404、follow解除後とarchive後のA / Bは200、soft delete後はA / Bとも404を確認した。0 / 1 / 3 / 10枚、active / archived、reload・back / forward・direct image URL・diary再訪、320 / 360 / 375 / 390 / 1280px、長文・改行・連続半角文字列・長いlocation、通常post画像Route / label / altを確認し、横overflowはなかった。E3d browser回帰後にsourceは変更しておらず、最終status更新Phaseではbrowserを再実行していない。実screen reader、suspended / deactivated sessionのRoute実HTTP、意図的なimage failure fallback再現は未実施である。

- Phase E3cではDB schema・RLS・migration・pgTAP定義・packageを変更せず、entry作成・本人編集・本人soft delete、diary title変更・archiveを既存RPCへ接続した。Server Actionはclaims由来actorと通常authenticated clientを使い、update / deleteではrouting用`diaryId`と対象entryの所属一致も中立に検証し、RPCを所有権・participant・active状態の最終認可に維持する。local通常sign-up UIでA / B / 第三者Cを作成し、通常UIだけでmutual follow、2冊の交換日記、25 entriesを作成した。本文10,000 / 10,001、title 120 / 121、場所100 / 101、tag 5 / 6、絵文字・改行、任意値の設定 / NULL解除、同一author連続作成、follow解除後継続、oldest / latest `20 / 4` pagination、本人だけの編集・削除、title fallback、two-tab stale edit / title / archive / delete、第三者・malformed・diary / entry mismatchの共通404を確認した。作成二重送信後もentry 1件・通知1件で、全25 entryに対する`exchange_entry`通知は25件、title / edit / archive / deleteの追加通知は0件だった。soft delete 7件は本文等が全てredactされ、tag / image linkは0件、archive後も本人削除とreadを維持した。320 / 360 / 375 / 390 / 1280pxのactive・archived・deleted・validation・generic error・新規 / 編集form・confirmationはすべて横overflow 0で、確認UIの初期focus、Escape / cancel後のfocus復帰、pending live region、error / status、重複しないentry操作名、fresh tabのconsole warning / error 0件を確認した。自動Tab / Shift+Tab注入はactive elementを動かさず、実screen reader announcementと瞬間的pending目視は手動確認へ残す。private画像fixtureは通常UIから作成できないため、legacy update RPCの維持と`0025` / `0030` pgTAPでmetadata / evidence境界を確認した。fixtureは許可済みlocal `supabase db reset`で全削除し、30 migration・全pgTAP`1,673 / 1,673 PASS`、`lint`、`typecheck`、`build`を再確認した。remote DB / Storage、Service Role、Auth Admin API、stage・commit・pushは未使用・未実施である。

- Phase E3bではDB schema・RLS・migration・pgTAP定義・packageを変更せず、invitation create / accept / reject / cancel、invitation専用block / unblock、`/exchange?view=invitations`、`/users/[userId]` Exchange section、mutual-follow invite UXを既存RPCへ接続した。Applicationはclaims由来actorだけを使い、party authorization、active / mutual-follow再確認、pending最大1件、cooldown、block、pair lock、concurrencyをDBへ委任し、RPC errorをgeneric messageへ変換する。local通常認証fixtureでcreate二重送信はpending 1件・通知1件、accept後detail遷移とdiary 1冊、two-tabのaccept / reject / cancel先行処理後のstale操作はneutral failure、block時incoming pendingはrejectedへ収束、unblock再操作、block / unblockによる追加通知0件、Exchange通知parserを確認した。320 / 360 / 375 / 390 / 1280pxの`/exchange`、招待一覧、profile section、detail、confirmation、pending、generic errorはすべて`scrollWidth <= clientWidth`で、50文字連続半角usernameと改行dataでも横overflowはなかった。confirmation open時focus、Escape close後focus復帰、pending中disabled / live region、error `role=alert`、success `role=status`を確認し、console warning / error、React / hydration warningは0件だった。自動Tab / Shift+Tab / Enter injectionはactive elementを動かさず、実キー操作とscreen reader announcementは手動確認へ残す。真の同時multi-session raceは未実施で、DB pair lock / conditional updateと既存pgTAPを根拠とする。

- Phase E3aではDB schema・RLS・migration・pgTAP定義・packageを変更せず、Exchange 3通知type parser / target navigation、`/exchange`、`/exchange/[diaryId]`、read-only list / detail、oldest / latest pagination、削除済みplaceholder、home導線を実装した。通常authenticated clientと既存RLSを使ったlocal fixtureでA/B participant、第三者C、active / archived / pending、22 entries、削除済みentry、mood / location / 5 tags / 画像件数、通常通知とのmixed表示を確認した。follow解除後もA/Bの既存diaryは継続し、Cは一覧0件・既知UUIDも共通404だった。320 / 360 / 375 / 390 / 1280pxの対象6画面は横overflow 0、semantic heading / nav / list / article / time、status、loading `aria-busy` / `role=status`、error `role=alert`、focus-visible、通知操作のcontextual accessible nameを確認した。自動browserのTab / Shift+Tab / Enter key injectionはactive elementを動かさず、実キー操作は未確認としてcode reviewと区別する。console warning / error、React / hydration warningは0件だった。

- Phase C4aではDB schema・RLS・migration・pgTAP定義・packageを変更せず、Supabase SSR / PKCEのpassword recoveryをApplication / UIへ接続した。`resetPasswordForEmail()`の利用者向け結果は登録済み・未登録emailで同じgeneric案内とし、callbackは固定same-origin pathだけを使う。インストール済みAuth SDKがPKCE verifierへ保存するrecovery marker由来のruntime `redirectType`を安全なshape guardで読み、JWT `amr=recovery`とactive / non-active account rowの両方を再検証する。recovery sessionはProxyで`/reset-password`以外へ通さず、更新Server Actionも同じcontextを再検証し、`updateUser()`成功後にlocal sign-outして新passwordによる通常loginを要求する。通常UIとlocal Auth / mail captureで登録済み・未登録の同一案内、新規recovery email、callback判定、password入力境界、更新、旧password拒否、新password login、protected route、logout、直接アクセス・code欠損・malformed callback・使用済みlinkのgeneric拒否を確認した。自動Browserではcallback直後の同一redirect chainだけcookie未反映のinvalid表示となり、次の通常requestでは有効なformとなった。Supabase SSRの標準cookie保存実装と次requestの成立、独自1-hopでも同じ挙動だったことからautomation制約として記録し、そのためのproduction workaroundは追加していない。320 / 360 / 375 / 390 / 1280pxは横scrollなし、semantic label・ARIA・focus-visible実装とconsole warning / error 0件を確認した。実キーボード、瞬間的pending目視、期限切れlink、remote Auth / SMTPは未確認である。最終`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`は成功した。DB変更がないためpgTAPは再実行せず、既存`954 / 954 PASS`は過去結果として区別する。local Auth fixtureは通常UIに削除経路がないため残している。Service Role、Auth Admin API、remote DB / Auth、stage、commit、pushは使用・変更・実施していない。

- Phase C3bでは既存19 migrationを変更せず、`20260809000400_validate_account_timezones.sql`と`0020_account_timezone_validation.test.sql`を各1件追加した。変更前はactiveなauthenticated本人が`Invalid/Timezone`を直接UPDATEできることをロールバック付きfixtureで再現した。新triggerは`pg_timezone_names`完全一致を使い、`posix/*`とIntl非対応の`Factory`を除外する。functionは追加権限が不要な`SECURITY INVOKER`、owner=`postgres`、空search path、trigger専用ACLとした。Applicationは`Intl.supportedValuesOf('timeZone')`＋`UTC`、runtime validation、viewer timezone helper、`/settings`、claims由来本人ID・通常Supabase client・既存RLSを使うServer Action、home導線、pending・成功・generic errorを実装した。DB validatorが受理する597 timezoneはNode Intlで全件利用でき、Application option 419件も全件DB受理可能で、不一致は両方向0件だった。認証済みローカルBrowser回帰で初期`Asia/Tokyo`、419候補、`America/New_York`・`Europe/London`・`Asia/Tokyo`の保存、保存直後表示、reload・再訪保持、home導線、320 / 360 / 375 / 390 / 1280pxの横scrollなし、label・説明関連付け・focus-visible・status、console warning / error 0件を確認した。保存直後だけselectが旧defaultへ戻る問題を検出し、selectを保存済みtimezoneでremountする最小修正を行った。通常authenticated clientの`Invalid/Timezone`直接UPDATEは`23514`で拒否され保存値は不変だった。Browser DOM tampering、瞬間的pending目視、信頼できるTab / Shift+Tab / Arrow移動は未実施で、helper・pgTAP・direct UPDATEと、`useFormStatus`・disabled / `aria-disabled`・semantic実装確認で補完した。reset後fixtureは0件で、新規`31 / 31`、全20ファイル`954 / 954 PASS`、timezone helper 14 assertion、`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`が成功した。remote migration履歴はread-onlyで19件を確認し、C3b migration未適用、remote mutation・Auth・Storage、Service Role、Auth Admin API、package変更、calendar、stage、commit、pushは未実施である。

- Phase C2c-3ではDB schema・RLS・migration・pgTAP定義を変更せず、RLS下の通知data layer、20件複合cursor pagination、actor profile / target commentのbatch hydrate、4 type文言、未読 / 既読、個別・すべて既読、home badge、通知IDだけをClient入力とするServer Action、Server側で現在のnotification / profile / commentを再評価するtarget遷移、利用不能targetのneutral表示を実装した。全19 pgTAP `923 / 923`、`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`が成功した。認証済みローカルブラウザ回帰では通常sign-up / loginと既存mutationだけを使い、follow / reaction / comment / reply、個別既読とreload保持、通知openの既読化・正しいtarget遷移、すべて既読、未読badge、利用不能comment / replyのneutral表示、stale click、post可視性の再評価、不正cursor 6種のfail-closed、22件を`20 / 2`で表示するpaginationを確認した。通知内に本文・`deleted_at`・raw UUID・DB errorは露出せず、320 / 360 / 375 / 390 / 1280pxで横スクロールはなく、browser consoleのerror / warning、React warning、hydration errorは0件だった。検証中の専用server stderrでfixture account切替時に`refresh_token_not_found`が2回あったが、後続loginと通知操作は成功し、C2c-3固有の不具合とは確認できなかったため修正していない。fixtureはローカルresetで清掃し、全pgTAP `923 / 923`を再確認した。実キーボードのTab / Shift+Tab / Enter / Spaceと、低速環境での個別既読・すべて既読のpending表示目視は未実施の手動確認として残す。remote DB / Storageのschema・migration・既存dataは変更せず、Service Role・Auth Admin・直接notifications INSERTは使用していない。

- Phase C2c-2では既存18 migrationと既存pgTAPを変更せず、`20260809000300_generate_notifications.sql`と`0019_notification_generation.test.sql`を各1件追加した。follow / reaction / commentsのAFTER INSERT triggerから、trigger専用の`SECURITY DEFINER` functionでrecipient / actor / targetをsource rowとDBのcurrent dataから決定する。Application roleの直接EXECUTEとnotifications INSERTは開けず、実DB role=`authenticated`、`auth.uid()`とsource actor一致、actor / recipient active、非自己通知の境界を満たす場合だけ生成する。reaction UPDATE / DELETE、follow DELETEでは生成せず、再INSERTは新規eventとして追加する。replyはvalid parentだけをfail-closedな`INSERT ... SELECT`で通知し、invalid parentでは独自errorを出さず既存validatorの`23514 / invalid parent comment`を維持する。最終local resetで19 migrationをfresh適用し、新規`48 / 48`、関連既存`0017` 45件・`0018` 65件、全19ファイル`923 / 923 PASS`を確認した。linked remote historyはC2c-1まで18件で、C2c-2 migrationは未適用である。既存test、Server Action、notifications RLS / policy / table ACL、package、UIは変更していない。remote migration適用、Service Role、Auth Admin API、stage、commit、pushは未実施である。

- Phase C2c-1では既存17 migrationを変更せず、`20260809000200_create_notifications.sql`を1件追加した。ローカルへincremental適用後、新規pgTAP `65 / 65`を確認し、local DB resetで18件をfresh適用して全pgTAP 18ファイル・`875 / 875 PASS`を確認した。reset前には引き継ぎどおり既存active fixtureが`0016`へ混入する1件失敗を再現し、今回のnotifications回帰と区別した。C2c-1で陳腐化した`0017`のnotifications不在assertionだけを削除し、reply認可期待値と既知fixture期待値は変更していない。repository / localは18 migration、remoteは17 migrationのままで、remote migration適用・linked schema diff・remote fixture・Service Role・Auth Admin APIは未実施である。通知生成、Application / UI、packageは変更していない。UI変更がないためbrowser / responsive検証は対象外である。

- Phase C2aでは既存16 migrationを変更せず、`20260809000100_add_comment_replies.sql`を1件追加し、resetなしの`migration up --local`で17件目としてローカル適用した。追加security reviewで、当初のinvalid parent別SQLSTATE / messageが不可視parentの推測経路になることを再現し、remote初回適用前にgenericな`23514 / invalid parent comment`へ修正した。新規pgTAP `46 / 46`、全pgTAP 17ファイル・`811 / 811`、`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`が成功した。最終migration 1件だけをリンク済みのリモート開発DBへ通常適用し、local / remote履歴17件一致、再dry-run up to date、remote catalog定義一致、`public,my_diary_private,storage`のlinked schema diff 0件を確認した。適用後のcatalog cache生成では一時CAファイルwarningが発生したが、migration履歴・再dry-run・catalog・schema diffでSQL本体の成功と切り分け、再適用やrepairは行っていない。remote fixture、Service Role、Auth Admin API、resetは使用していない。UI変更がないためブラウザ・responsive検証は対象外である。

- Phase C1bではDB schema・RLS・migration・pgTAP定義を変更せず、通常authenticated clientで本人`accounts.status`だけを取得する共通helperと、login・即時session付きsign-up・callback・Proxyへのapplication session gateを実装した。ローカル公開Auth clientとSSR cookieによる統合回帰でactive userの`/home`、`/profile`、`/posts/new`、`/tags`を通常表示し、suspended後の主要GETをloginへ307、画像requestをsession削除Cookie付き404へfail-closed化した。実ブラウザではactive / suspended / deactivated login、stale refresh、back / forward、5つのprotected URL同時再読込、logout、active復帰、generic errorとlabel / alertを確認した。stale Server Actionへ通常303を返すとNext.js clientが応答を解釈できずpendingのままになる問題を検出し、`next-action` requestにはcookie削除と`x-action-redirect`を返すよう修正して、login退避、mutation 0件、追加console errorなしを再確認した。suspended / deactivatedの正しいcredentialはAuthで受理されてもhelperが`non-active`としてsessionを終了し、active復帰後の再loginは成功した。account row欠損とstatus query errorはmock境界でそれぞれ`account-missing` / `query-error`へ分類した。最初の全pgTAPはactiveなローカルfixtureがprofile SELECT期待へ1行混入して`764 / 765`となったが、fixtureを削除せず明示許可されたstatus変更でdeactivatedへ戻した後、16ファイル`765 / 765 PASS`を確認した。`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`も成功した。Browserのviewport overrideは実画面へ反映されず、1280px以外のresponsive、信頼できるTab / Enter injection、実callback、実画像bytesのnon-active browser表示は未実施である。

- Phase C1aでは既存15 migrationを変更せず、`20260808000400_fail_close_non_active_accounts.sql`を1件追加した。ローカルDB resetで16件をfresh適用し、新規pgTAP `79 / 79`、全pgTAP 16ファイル・`765 / 765`、`npm run lint`、`npm run typecheck`、`npm run build`が成功した。既存のsuspended owner期待値は`0001`、`0004`、`0009`、`0011`、`0012`、`0013`で新しいfail-closed仕様へ更新した。JWT claimを保持するnon-active viewerとしてDB accessが閉じることを検証した。C1a migrationだけをリンク済みのリモート開発DBへ通常適用し、local / remote履歴16件一致、再dry-run up to date、remote catalogのfunction属性・ACL、accounts最小status read、profiles / posts / Storageのactive境界、既存RLS・RPC回帰、`public,storage,my_diary_private`のlinked schema diff 0件を確認した。SQL成功後のcatalog cache生成で一時CAファイルwarningが発生したが、repairや再適用は行っていない。remote実ユーザーテストは安全な既存認証情報がないため未実施で、Service Role、Auth Admin API、remote fixture・ユーザーデータ・Storage objectは使用していない。application sign-out / callback / protected route gateはC1b対象で未実装である。

- Phase B3dでは既存14 migrationを変更せず、`20260808000300_integrate_post_image_edits.sql`を1件追加した。新規pgTAP `36 / 36`、全pgTAP 15ファイル・`686 / 686`がローカルで成功した。通常sign-upとpublishable clientだけのStorage統合で、mixed追加・削除・並び替え、保持identity、既知DB失敗時new cleanup、DB成功後old cleanup、session失効時private orphanと再ログイン後cleanup、重複retry拒否を確認した。ブラウザでは画像なし、既存2枚、mixed編集、10枚、11枚拒否、MIME・0-byte・6 MiB超過、保存中disabled、詳細・プロフィール反映、320 / 360 / 375 / 390 / 1280pxの横scrollなしを確認した。soft deleteはmetadata / objectを保持する既存方針を変えず、postと画像routeの取得を拒否する。B3d migration 1件だけをリモート開発DBへ通常適用し、local / remote履歴15件一致、再dry-run up to date、remote catalogの新RPC属性 / ACL、deferrable UNIQUE、`post_images` ACL、既存Storage policy・既存RPC・soft delete・標準Storage ownerの維持、`public,storage,my_diary_private`のlinked schema diff 0件を確認した。SQL成功後のcatalog cache生成で一時CAファイルwarningが発生したが、repairや再適用は行っていない。安全な既存remote認証情報がないためremote実update / Storage lifecycleは未実施で、Service Role、Auth Admin API、remote fixture・ユーザーデータ・Storage objectの作成や変更は行っていない。

- Phase B3cではmigration・pgTAP定義を変更せず、cookie認証付き同一origin画像route、private no-store応答、metadata batch hydration、raw path非露出、共通galleryを実装した。ローカルDB resetで14 migrationをfresh適用し、全pgTAP 14ファイル・`650 / 650`、`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`が成功した。通常sign-upとauthenticated clientだけで3 user、public / followers / private、0 / 1 / 2 / 3 / 10枚、検索pagination用投稿を作成し、詳細・following・latest・自他プロフィール・タグ・検索、20 / 1件pagination、320 / 360 / 375 / 390 / 1280px、altと非interactive galleryを確認した。follow解除、`public → followers`、`followers → private`、soft delete、未認証、不正 / 不存在UUIDは同じ画像URLの次回取得で空body 404となり、成功・失敗応答ともprivate no-store境界を確認した。suspended author / viewerは一般ユーザーAPIで作成せず既存pgTAPの確認に留めた。fixtureは最後のlocal resetで削除し、auth user、accounts、posts、post_images、tags、post_tags、post-images Storage objectがすべて0件であることを確認した。Service Role、Auth Admin API、remote DB / Storage、stage、commit、pushは使用していない。

- Phase B3bではローカルDB resetで14 migrationをfresh適用し、新規pgTAP `47 / 47`、画像関連 `122 / 122`、全pgTAP 14ファイル・`650 / 650`が成功した。通常の認証ユーザーとpublishable clientだけを使う実Storage API検証で、通常upload、途中失敗cleanup、DB失敗cleanup、orphan remove、参照済みremove拒否、upsert拒否、MIME・0-byte・6 MiB超過拒否、10枚順序を確認した。新規投稿の画像なし経路とレスポンシブ5幅も確認した。リモート開発DBへのmigration適用、remote catalog、再dry-run、linked schema diffも成功した。安全な既存remote認証情報がないためremote実upload / RPC mutationは未実施で、Service Role、Auth Admin API、remote fixture・ユーザーデータ・Storage objectの作成や変更は行っていない。

- Phase B3aではローカルDB resetで13 migrationをfresh適用し、新規pgTAP `75 / 75`、全pgTAP 13ファイル・`603 / 603`が成功した。private bucket、最大10枚、順序・path制約、ACL、post_images → postsとstorage.objects → post_images → postsのRLS連鎖、follow・visibility・soft delete・suspended、pathのみ・orphan・別bucket、Storage mutation拒否を確認した。意図的に広いPERMISSIVE SELECT policyを追加したテストでもRESTRICTIVE guardがprivate画像を拒否した。`public,storage,my_diary_private`のlocal schema diffは空で、`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`も成功した。UI変更がないためブラウザ・responsive検証は対象外とした。
- Phase B2b-3bではローカルDB resetで12 migrationをfresh適用し、新規pgTAP `52 / 52`、全pgTAP 12ファイル・`528 / 528`が成功した。local catalogで投稿検索RPCのexact signature、引数名、return shape、`STABLE`、`SECURITY INVOKER`、owner、固定search path、authenticated専用ACL、overload 1を確認し、posts RLS・SELECT policy・table ACL・既存indexの維持も確認した。`public,my_diary_private`のlocal schema diffは空だった。`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`も成功した。
- Phase B2b-3bの認証済みブラウザ検証では、通常sign-upとauthenticated経路だけで3 userと33 postの一時fixtureを作成した。users / tags / posts切替、canonical redirect、title / body / OR、NFKC、ASCII case、literal wildcard、空・50 / 51 codepoint・control文字、17種の不正parameterのfail-closed表示を確認した。不正入力2画面の前後で`pg_stat_statements`上の投稿検索RPC呼出回数が増えず、DB query前に拒否されたことも確認した。
- 投稿検索のRLSは、本人のpublic / followers / private、follower、non-follower、follow解除・再follow、`public → followers → private → public`、soft deleteを次回検索で確認した。paginationは23件を`20 / 3`件で表示し、重複・欠落なし、戻る・進む・再読み込み・cursor URL直接アクセスを確認した。1ページ目後のfollow解除では保存済み2ページ目が0件となり、別の権限外投稿を補完しなかった。実cursorのtimestampは`+00:00`表現・小数6桁で、元文字列のbase64url JSON round-tripを維持した。
- 320 / 360 / 375 / 390 / 1280pxで3カテゴリnavigation、検索form、投稿一覧、pagination、長いtitle・body・改行・連続半角文字列、長いusername、30 codepoint tagを確認し、横scrollはなかった。label関連、`aria-current`、`aria-invalid`、`aria-describedby`、`role="alert"`、`ul / li / article`、focus表示用style、button送信を確認し、console error / warning、React warning、hydration errorはなかった。自動ブラウザのTab / Enter key injectionはfocus・submitを再現できず未実施、suspended境界は通常利用者UIがないためpgTAPのみとした。
- 直前作業までの確認済み結果として、全pgTAP `267 / 267`、最新追加分`29 / 29`、`npm run lint`、`npm run typecheck`、`npm run build`成功が作業依頼に記録されている。
- Phase A1では`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`を再実行し、すべて成功した。migrationは8件のまま、`supabase/migrations`、`package.json`、`package-lock.json`に差分がないことも確認した。
- Phase A1では全pgTAP `267 / 267`が成功した。今回の文書記録更新では、直前の全件成功を根拠としてpgTAPを再実行していない。
- Phase B1ではVectorを除外したローカルstackでDB resetにより9 migrationをfresh適用し、新規pgTAP `71 / 71`、全pgTAP `338 / 338`が成功した。PostgreSQL 17.6の標準NFKCとNode/TypeScript相当の正規化も既知ケースで一致した。リモート適用後のpg-delta catalog cache生成ではCLIの証明書参照警告が発生したが、remote migration履歴9件の一致、PostgreSQL catalog由来のschema dump、再dry-runで適用対象0件、linked schema diff 0件を確認した。
- Phase B2aではローカルDB resetで10 migrationをfresh適用し、新規pgTAP `68 / 68`、全pgTAP `406 / 406`が成功した。補助2-session検証では同一canonical tagの同時作成がmaster 1行・relation 2行で完了し、同一postの同時更新はrow lock待機後に一方の完全なpost/tag集合へ収束した。リモート開発DBへ適用後、再dry-run、linked schema diff、remote catalog一致まで確認済みである。
- Phase B2b-1ではmigration・pgTAP定義を変更せず、ローカルDB reset後に全pgTAP `406 / 406`を2回実行して成功した。TypeScript normalizer・validationの20境界assertion、authenticated clientによるnested selectの実shape、public / followers / private / soft delete境界、作成・更新RPC、変更しないrelationの`created_at`維持を補助検証した。`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`も成功した。
- Phase B2b-1の認証済みブラウザ検証では、タグ作成、編集初期表示、追加・削除・全解除、validation後の保持、投稿詳細、following、latest、自分・他者投稿一覧、非リンク表示、Backspace非削除、戻る・進む・再読み込みを確認した。320 / 360 / 375 / 390 / 1280pxで横スクロールはなく、5タグと30文字連続英数字が収まり、削除buttonは40px、console error / warning、React warning、hydration errorはなかった。OS IME変換中Enterと瞬間的なpending表示は自動ブラウザでは再現せず、composition防御とpending disabledのコード確認に留めた。
- Phase B2b-2ではmigration・pgTAP定義を変更せず、タグ一覧・詳細cursor、UUID canonical化、同時刻postのID tie-break、`PostTag{id,name}` relation shape、UUID hrefについてinline assertion 27件が成功した。認証済みブラウザ検証後には、localhostのローカルDBだけをresetして10 migrationをfresh適用し、全pgTAP 10ファイル・`406 / 406`を再実行して成功した。`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`も成功した。
- Phase B2b-2の認証済みブラウザ検証では、通常のsign-upとauthenticated経路だけで7 userの一時fixtureを作成した。`/tags`は初期108 tagを`50 / 50 / 8`件、共通tagの詳細は21 postを`20 / 1`件で表示し、最終ページ、cursor付き再読み込み、戻る・進む、不正cursorのfail-closed表示を確認した。小文字UUID、大文字UUIDからのcanonical redirect、有効cursorの保持、形式不正・不存在・権限外UUIDの共通404も確認した。同一`created_at`の実ブラウザfixtureは特権SQLを使わず未実施とし、ID tie-breakは既存inline assertionとコード確認に留めた。
- Phase B2b-3aではローカルDB resetで11 migrationをfresh適用し、新規pgTAP `70 / 70`、全pgTAP 11ファイル・`476 / 476`が成功した。TypeScript query/cursorのinline assertion、`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`も成功した。
- Phase B2b-3aの認証済みブラウザ検証では、通常のsign-upとauthenticated経路だけで3 userと一時投稿・タグを作成した。users / tags切替、canonical redirect、NFKC、日本語・絵文字・空白、`\\`・`%`・`_`・`*`・`/`・`?`のliteral検索、20 / 2件のタグcursor pagination、reload・戻る・進む、不正・過長・query不一致・schema不一致cursorのfail-closed表示を確認した。non-follower・follower・follow解除、private・followers・public、soft deleteの初期可視境界と動的なfollow解除・soft delete反映を確認した。公開範囲3方向の全編集遷移は既存編集routeがブラウザfixtureで404となり未実施とし、DB側pgTAPの保証に留めた。
- Phase B2b-3aでは320 / 360 / 375 / 390 / 1280pxで検索結果・error・空状態・長いtagを確認し、横scrollはなかった。semantic nav、`aria-current`、label、`aria-invalid`、alert、`ul / li`、UUID linkを確認した。自動ブラウザではEnter送信とTab移動を再現できず、button送信とfocus-visible実装の確認に留めた。検証中のconsole error / warning、React warning、hydration errorはなかった。fixtureはローカルDB resetで削除し、通常ログアウト後に`/search`から`/login`へのredirectを確認した。
- authenticated PostgREST clientの実responseで、`matching_tags:post_tags!inner(tag_id)`が親postを対象tagで絞り、表示用`post_tags(tags(id,name))`が各postの全tagを返すことを確認した。relation shape error、対象外post、不可視postのpayload混入はなく、shape validatorは不正relationをfail closedで扱い、post単位のN+1を使わず一括hydrateする。
- visibility境界は、本人がpublic・followers・privateを閲覧でき、followerはpublic・followersだけ、non-followerはpublicだけを閲覧できた。follow解除直後、`public → followers`、`followers → private`、`private → public`の編集後、soft delete後も、次回navigationまたはreloadでタグ一覧・詳細がRLSどおり更新された。suspended authorは通常利用者経路で作成せず、DB側pgTAPの保証だけとした。
- TagListはfollowing、latest、投稿詳細、自分の投稿一覧、他ユーザー投稿一覧で`#タグ名`、UUID href、不正なinteractive要素の入れ子がないことを確認した。日本語、絵文字、空白、30 codepoint連続英数字、`/`・`%`・`?`、5タグでもhrefにtag名は入らず、クリックでタグ詳細へ遷移して戻る操作も正常だった。
- タグ詳細上のreactionは追加・種類変更・解除後に選択状態と件数が更新され、commentは追加後とタグ詳細へ戻った際に件数が更新された。comment削除後、タグ詳細へ再navigationすると削除が反映されたが、投稿詳細上では削除直後だけ古いcommentが残り、navigationまたはreloadで解消した。これは既存のcomment削除UIのrefresh不足で、B2b-2のタグroute固有不具合ではないため今回は変更していない。タグ編集は追加・解除・維持が反映され、最後の可視relationを解除したtagの既知UUIDは404になった。
- 320 / 360 / 375 / 390 / 1280pxで`/tags`、タグ詳細、homeのTagList、pagination、共通404を確認し、意図しない横scrollやカード崩れはなかった。focus-visible、heading、`ul / li`、aria-label、errorの`role=alert`、404のh1、loading実装の`role=status`と`aria-busy`、tag linkのaccessible nameが可視文字列と一致することを確認した。自動ブラウザのkeyboard dispatchではTab移動とEnter activationを再現できず、実キーボード操作は未確認である。loadingは遷移が速く瞬間表示を分離捕捉できず、markupと実装確認に留めた。
- 対象操作後のbrowser console error / warning、React warning、hydration error、予期しないnetwork / PostgREST failureは0件だった。user切替中の開発server logには失効済みrefresh token由来のAuth errorが2件あったが、tag routeのquery errorではなく、画面操作とDB結果に影響しなかった。検証fixtureはローカルDB resetで削除し、reset後の`/tags`空状態を確認した。B2b-2固有の不具合は検出されず、アプリコードの追加修正は行っていない。
- 認証済みブラウザ検証では、following / latestの表示行列、URL直接アクセス、不正・空・複数feed値、リンク切り替え、再読み込み、戻る・進む、`aria-current`、空状態、動的反映を確認した。320 / 360 / 375 / 390 / 1280pxで横スクロールがなく、長文・改行・連続半角文字列の表示も正常であり、console error / warning、React warning、hydration errorはなかった。ユーザーによる最終手動確認も問題なかった。
- Phase C3aの認証済みブラウザ検証では、following `20 / 5`件、latest `20 / 7`件のforward cursor pagination、重複なし、reload・back / forward・cursor URL直接アクセス、feed切替時のcursor破棄を確認した。不正base64url・JSON・version・feed・UUID・timestamp・過不足fieldと実cursorのfeed不一致はgeneric errorとなりraw値を表示しなかった。follow解除後のsaved following cursorは現在のfollow関係を再評価して0件導線となり、visibility変更後のsaved latest cursorも現在不可視のpostを除外した。本文280 / 281 codepoints、絵文字、改行、連続半角文字列、ellipsis、「続きを読む」、投稿詳細全文、home以外の代表画面で全文維持を確認した。320 / 360 / 375 / 390 / 1280pxのfollowing初期・次page、latest初期、不正cursor、cursor付き0件状態で横scrollはなく、console error / warning、React warning、hydration errorは0件だった。同一`created_at`の実データtie-breakと実キーボードのTab / Shift+Tab / Enterは自動ブラウザで再現できず、query order・semantic link/button・focus-visibleの実装確認に留めた。
- repository内にunit、component、browser E2Eの自動test fileは確認できない。

## 10. 既知の制限・技術的負債

1. `rls_auto_enable()`はRLS有効化失敗をlogへ記録して元DDLを成功させるfail-openである。policyも自動作成しないため、各migrationで明示的なRLSとpolicyが引き続き必須である。
2. event triggerとfunction ACLは一般的なschema diffだけでは完全に検出できないため、migrationのpreflight/postconditionとpgTAPを維持する必要がある。
3. Supabase Authはnon-active accountの正しいcredential自体を受理し得る。Phase C1bはAuth確立直後と次のapplication requestでstatusを確認してcurrent sessionを終了する。最終認可はPhase C1aのDB / RLSであり、application gateだけへ依存しない。
4. home timelineは20件forward cursor paginationを実装済みだが、他者投稿とfollow一覧は最新20件、comment一覧は古い順100件で打ち切り、継続取得を実装していない。
5. home timeline本文は280 codepointsで省略済みである。フォロー中feedのauthor filterは`.in(...)`を使用するため、大量follow時のURL長・query性能を実データで評価する必要がある。
6. avatar_pathはDB基盤だけで、UIから利用できない。
7. comment返信と通常SNS通知はDBからApplication / UIまで実装済みである。通知は現在RLS上見える行だけを一覧・件数・既読更新の対象とするため、不可視だったpost targetが将来再び可視になると過去通知が未読で再表示される場合がある。Exchange 3通知typeもE3aでparser / target navigationへ対応済みである。
8. unit、component、E2E、accessibility、viewport別responsiveの自動回帰がない。
9. profile件数、timeline補助data、comment件数は複数queryを使う。投稿単位のN+1は避けているが、規模拡大時はRPC、view、集計方式を再評価する必要がある。
10. root-level `loading.tsx`と`error.tsx`はなく、未認証redirectと一般error handlingはpageごとに一部重複している。non-active status gateはProxyと共通helperへ集約済みで、protected layoutはClient navigation、Server Action、画像Route Handlerを単独では覆えないため追加していない。
11. 自由タグは入力・投稿リンク・一覧・詳細・検索まで実装済みである。入力順を保存するcolumnはなく、投稿上はcode point順、タグ一覧・検索はDBの`normalized_name`順で表示する。検索の部分一致は現時点で専用indexを追加せず、RLS適用後のscan性能は大規模データで再評価が必要である。最大5個はauthenticatedのRPC経路で保証し、特権roleの直接SQLを禁止するconstraint triggerは置いていない。認証済みブラウザ回帰は完了したが、同一`created_at`の実データ、suspended author、瞬間的loading、実キーボードによるTab / Enterは未確認である。
12. 投稿検索はNFKC化したtitle / bodyへの部分一致で、専用indexを追加していない。大規模データでRLS適用後のscan性能を再評価する必要がある。cursorはPostgRESTのtimestamp文字列をDateへ変換せず保持する。suspended author / viewerはpgTAPで確認し、通常UIによるブラウザ再現は未実施である。自動ブラウザのTab / Enter key injectionも再現できず、実キーボード確認が残る。
13. password recoveryの自動Browser検証ではcallbackの同一redirect chain直後だけcookieが見えずinvalid表示となり、次の通常requestでは有効なformとなった。SDKのcallback交換・recovery marker・JWT AMR・account gateは成立し、次requestへcookieが反映されるためautomation制約と判断しているが、公開前に通常の実ブラウザで初回表示を手動確認する。remote SupabaseのSite URL / Redirect URLs・SMTP、期限切れlink、実キーボード操作も未確認である。
14. `0015_post_image_edit_mutation.test.sql`は`begin;`後に明示的な`rollback;` / `commit;`を置いておらず、他の29 pgTAP fileとfixture isolationの形式が一致しない。テストセッション終了時のrollbackに依存するため、後続maintenanceで明示的な終了を追加する。
15. E3e-1では全upload成功後の明確なRPC failureの実再現、実network切断によるunknown outcome、session失効、suspended、uploader / counterpart deactivated競合、全UI状態×5幅の完全matrix、実キーボード、実screen reader、JPEG / WebPの完全decoder妥当性は未実施である。DB / RLS境界、code review、pgTAP、実browser結果による代替確認と区別する。
16. E3e-2では1280pxを実測したが、Browser viewport capabilityが指定幅を反映せず320 / 360 / 375 / 390pxは未実施である。follow解除の最終Browser操作、archive / status / deactivated / suspendedの実Browser race、soft-delete stale edit、partial upload failureの強制再現、real transport / network unknown outcome、実キーボード、実screen readerも未実施であり、DB pgTAP、code review、実装済みsemantic / mobile-first UIの確認と区別する。
17. `my_diary_create_user_report`はExchange participant relationを要求しないglobal user-report RPCのままであり、E3f-3のDB BLOCKERとして残る。E3f-1はこのRPCのscope、authenticated EXECUTE、submission semanticsを変更していない。

## 11. Exchange完了状態と次Phase

### 11.1 E2a〜E2hの判定

- E2a〜E2g DB / Storage foundation: 実装・migration適用・検証済み。
- E2h-1a final read-only security audit: DB / Storage BLOCKER 0件。
- E2h-1aではreport targetへの漏洩なしと判定したが、後続E3f-0でtarget / reporter本人がactive adminの場合のCOI例外をBLOCKERとして確認した。E3f-1はrepository / local / remoteのDB・Storage最終境界で修正済みである。
- この判定はDB / Storage foundationに対するものであり、Exchange Application / UIの完成を意味しない。

### 11.2 E3 Application BLOCKER（残り4カテゴリ）

E3aでExchange 3通知typeのparser / target navigationとinvitation / list / detailのsecurity-safe read hydration、E3bでinvitation 6操作、E3cでdiary / entry mutation、E3dでprivate画像Route / 表示、E3e-1で新規entryの画像upload / create接続、E3e-2でexisting / new画像editとfinal complete manifest接続を解消した。E3e-0bでnever-confirmed画像orphanのDB / Storage cleanup境界を完了したが、maintenanceのApplication実行経路はまだ接続していない。残るBLOCKERは次のとおりである。

E3f-1ではtarget-admin / reporter-adminのDB / Storage COI境界をrepository / local / remoteで確定した。また、`my_diary_create_user_report`のglobal scopeはE3f-3対象として残る。

E3fの現在位置は次のとおりである。

- E3f-0 report調査: `COMPLETE`
- E3f-1 report moderation conflict-of-interest hardening: `COMPLETE`
- E3f-2 Exchange entry report UI: `未着手`
- E3f-3 Exchange user-report scope hardening: `未着手`
- E3f-4 Exchange counterpart report UI: `未着手`

E3f-3の`my_diary_create_user_report`がExchange participant relationを要求しないglobal scope問題は未解決であり、Ver.2.2の作成によって解決済みにはならない。

1. report submission UI。
2. 最小限のadmin report queue / snapshot / status更新経路。
3. moderator exact-evidence Route Handler。
4. maintenance RPCの安全な実行経路。

E3e-2はexisting画像追加・削除・並び替えとedit successor Application接続まで完了した。E3f-1はDB hardeningだけを対象とし、残る4 Applicationカテゴリへ着手していない。

### 11.3 PRE-PUBLICATION（4件）

1. maintenance cadence / runbook / retry / failure monitoring。
2. controlled remote actual Storage API smoke。
3. reports row / reason / detailsの長期retention policy決定。
4. E3完成後のbrowser security integration回帰。

これらはE3開始を止めるDB blockerではないが、初回公開前に完了または方針確定が必要である。

Ver.2.2でWeb Initial Release、Design Completion、Legal / Privacy Verification、Production Readiness、Operations Handoffの各Gateと補助checklist / runbookを追加した。文書の骨格を作成しただけであり、各Gateは未確認・未完了である。

### 11.4 POST-PUBLICATION / MAINTENANCE

- full admin dashboard。
- cleanup candidate backlog / completion監視。
- 追加remote concurrency smoke。
- verifier scriptのfixture cleanup・failure時restore hardening。
- statistical timing regression。
- full safety / legal hold workflow。
- account完全削除lifecycle。
- SNS全体のユーザーブロック機能。
- shared tag masterのcreated_atを含むmetadata最小化の追加検討。

### 11.5 Ver.2.2で追加されたGate・roadmapの状態

| 項目 | 現在の状態 | 補足 |
| --- | --- | --- |
| Web Initial Release Gate | 未確認 | Web release checklistは未完了 |
| Design Completion Gate | 一部実装済み / 未完了 | 主要UIに既存対応はあるが横断release review未完了 |
| Legal / Privacy Verification Gate | 未確認 | 法的結論、Terms、Privacy Policy、問い合わせ手段は完成扱いにしない |
| Production Readiness Gate | 未確認 | remote Auth、実メール、production E2E等が残る |
| Operations Handoff Gate | 未確認 | maintenance Application実行経路と運用判断が残る |
| general account deletion | 未実装 | Web公開後roadmap。Exchange既存semanticsとは別 |
| SNS全体のglobal user block | 未実装 | Exchange invitation blockとは別 |
| 将来iOS Application | 未着手 | roadmapとexternal verification gateのみ |

これらのGate・roadmapは上記60個の既存機能集計へ自動加算していない。仕様追加と実装・外部確認の完了を区別する。

## 12. 更新履歴

| 日付 | HEAD | 内容 |
| --- | --- | --- |
| 2026-08-16 | documentation commit前。基準HEAD `52efbd45e1369fef8a9e61549ce43d11d127a0a5` | 正式仕様をVer.2.2へ更新し、Web Initial Release、Design Completion、Legal / Privacy Verification、Production Readiness、Operations Handoff、将来iOS方針の各Gateと補助checklist / runbookを追加。E3f-0 / E3f-1 COMPLETE、E3f-2 / E3f-3 / E3f-4未着手、32 migration、最新確認済み全pgTAP`1,755 / 1,755 PASS`を維持し、仕様追加を実装・法務・production・iOS完了扱いしていない。Application、DB、migration、pgTAP、package、remote DB / Storage / Authは変更せず、stage / commit / push前 |
| 2026-08-16 | commit前。基準HEAD `38ef7aabc5863f4c1e00aed54a66d0a1aed43df7` | Phase E3f-1 remote確定 PASS。targetまたはreporter本人であるactive adminをreports / text snapshot / image snapshot / exact Storage evidence / status update / expired evidence purgeからNULL-safeに除外し、unrelated active adminとreporter NULLのmoderationを維持するsuccessor migrationを追加。既存`0027`のtarget-admin期待を最小更新し、専用`0032`は`37 / 37`、関連`0025 / 0027 / 0030 / 0031`は`284 / 284`、local 32 migration fresh apply後の全32 pgTAPは`1,755 / 1,755 PASS`。linked `my-diary-dev`へ新migration 1件だけを通常適用し、repository / local / remote `32 / 32 / 32`、再dry-run up to date、remote catalog一致、3 schemaのlinked diff空を確認。既知pg-delta CA warningは独立証拠でSQL成功と切り分け、repair・再適用なし。lint・typecheck・build・diff check PASS、security reviewは全severity 0件。migration以外のremote DB mutation、Storage / Auth mutation、Service Role、Auth Admin APIなし。Application source・package・report create RPC・global user-report scopeは変更せず、commit / push前 |
| 2026-08-16 | commit前。基準HEAD `c308a914a1f91fab35f552eb054aecd7bfc9fcdc` | Phase E3e-2 COMPLETE。Exchange entry editへexisting画像保持・削除・並び替え、new画像追加・削除、existing / new混在順序、全画像削除、0〜10件のfinal complete manifestを接続し、画像統合update successorへ切り替えた。existing identityを維持し、newだけをstrict 4 UUID pathへ`upsert:false`でupload / best-effort cleanupする。unknown outcomeではDELETEと通常retryを止め、success後のremoved existingはApplicationから物理DELETEせずcleanup candidate・7日retention・evidence・trusted maintenanceへ委譲。raw path非露出、edit通知追加なし、create画像回帰なしを確認した。実装Phaseの対象pgTAP`502 / 502`、確定Phaseではlocal physical fixture 18件をproject限定data-volume cleanupし、31 migration fresh適用後に全pgTAP`1,718 / 1,718 PASS`。lint・typecheck・build・diff check PASS、securityはBLOCKER / HIGH / MEDIUM / LOW 0件。1280pxは実測、320 / 360 / 375 / 390px、follow解除最終操作、archive / status / soft-delete race、強制partial / network failure、実keyboard、実screen readerは未実施として代替確認と区別。DB / migration / pgTAP定義 / package / 通常post画像 / remote Supabaseは変更していない |
| 2026-08-16 | commit前。基準HEAD `9462b03789f5cbcb4f1d97e4fc0fd2901b3cd0ad` | Phase E3e-1 COMPLETE。Exchange entry createへ0〜10枚のJPEG / PNG / WebP、1枚6 MiB、magic-byte validation、preview・選択削除・選択順保持、caller-generated entry / image UUIDのstrict 4 UUID path、private authenticated upload・`upsert:false`、0枚を含むsuccessor RPC完全移行を実装。partial uploadは成功確認済みpathだけ、明確なrollbackは今回new objectだけをcleanupし、unknown outcomeではDELETEせず通常retryを停止。follow解除後create、archive競合fail-closed、raw path非露出、success後double-submit防止を維持。対象pgTAP`406 / 406`、全pgTAPは今回local physical fixture 15件をproject限定data-volume cleanupし、31 migration fresh適用後に`1,718 / 1,718 PASS`。lint・typecheck・buildは実装Phaseの最終PASS、diff checkは今回PASS、security finalはBLOCKER / HIGH / P1 0件。local検証開始時のremote Auth endpointへ2 sign-up試行の可能性はCodex read-only調査で直接確認できなかったが、後にユーザーが`my-diary-dev` DashboardのAuthentication > Usersを手動確認し、既存本人user 1件のみで追加userなしを確認。remote Auth cleanupは不要とし、remote Auth mutationは行っていない。E3e-2のexisting画像editとfinal manifestは未実装・未着手 |
| 2026-08-16 | commit前。基準HEAD `58b3460067432561aa1ac2ebd516e446c3b9bb12` | Phase E3e-0b COMPLETE。never-confirmed Exchange画像orphanを24時間grace後にtrusted active-admin maintenanceだけが回収できるようhardeningし、strict 4 UUID / owner-path、live metadata・confirmed candidate・全report snapshot evidence除外、Storage-first row lockとsuccessor race protectionを追加した。前Phaseのlocal結果は新規pgTAP`45 / 45`、関連既存`268 / 268`、全31ファイル`1,718 / 1,718 PASS`、2-session confirm-first / cleanup-first実Lock待機で、今回のremote適用Phaseでは再実行していない。リンク先`my-diary-dev`へ新migration 1件だけを通常適用し、repository / local / remote`31 / 31 / 31`、再dry-run up to date、remote catalogのfunction signature / owner / SECURITY DEFINER / volatility / search_path / ACL / overload、active-admin境界、既存11 Storage policy、confirmed 7日・evidence 30日retention、`public,my_diary_private,storage` linked diff 0件を確認した。適用後の既知pg-delta CA warningは履歴・dry-run・catalog・diffで切り分け、repair・再適用なし。remote fixture・Storage / Auth mutation、Service Role、Auth Admin APIは未使用。E3e-1は未着手 |
| 2026-08-15 | commit前。基準HEAD `ff5f1f20c135b70e537d93fdd4f63a91f8c9f3fe` | Phase E3dとしてcookie認証付きprivate Exchange画像Route、live metadata / entry / author participant / 4 UUID path / Storage RLSの再評価、MIME / magic byte / 0 byte / 6 MiB検証、raw path非露出、neutral empty 404、bounded image reference hydrate、0〜10枚のaccessible / responsive galleryを実装。通常authenticated fixtureでA / B 200、C・未認証・malformed / nonexistent 404、follow解除後・archive後200、soft delete後404を確認し、0 / 1 / 3 / 10枚、5幅、通常post画像回帰を完了。local Supabase portsをWindows TCP除外範囲外の5542xへ移し、config / Docker mapping一致を確認後、project限定data-volume cleanupとclean rebuildで旧physical image 71件を0件化、fixture 0件、30 migration fresh適用、関連`273 / 273`・全pgTAP`1,673 / 1,673 PASS`を確認した。実screen reader、suspended / deactivated sessionのRoute実HTTP、image failure fallbackの実browser再現は未実施。DB・migration・pgTAP定義・package・remote DB / Storage / Authは変更せず、Service Role・Auth Admin APIは未使用 |
| 2026-08-15 | commit前。基準HEAD `69d39b153640d6291f2fba4fb953552c928f98da` | Phase E3cとしてentry作成・本人編集・本人soft delete、diary title変更・archive、作成 / 編集route、Unicode codepoint検証、確認UI、double-submit抑止、pending / error / status、diary / entry所属一致確認を既存RPCへ接続。local通常UIでA / B / C、follow、2 diary、25 entriesを作成し、境界値、任意値解除、同一author連続、follow解除後継続、pagination、本人 / 第三者、two-tab stale、archive後read / delete、共通404、5幅overflow 0、confirmation focus / Escape / cancel、固有accessible name、fresh console 0件を確認した。検証中にCRLF正規化による10,000 codepoint誤拒否と削除成功announcement不足を検出して最小修正。entry 25件に対する通知25件、削除7件の全redact、削除済みtag / image link 0件をlocal DBで確認。許可済みlocal reset後fixture全0件・30 migration、全pgTAP`1,673 / 1,673 PASS`、lint・typecheck・build成功。private画像実fixture、実Tab / Shift+Tab、screen reader、瞬間的pending目視は未確認として区別。DB・migration・pgTAP定義・package・remote DB / Storageは変更せず、Service Role・Auth Admin API・stage・commit・pushは未使用・未実施 |
| 2026-08-15 | commit前。基準HEAD `4c5459dab6cd295535fbcb0779401cee9e34521f` | Phase E3bとしてinvitation create / accept / reject / cancel、`/users/[userId]`のmutual-follow invite UXとinvitation専用block / unblockを既存RPCへ接続。generic error / privacy oracle対策、two-tab stale、二重送信、block時rejected収束、追加通知0件、Exchange通知parser、5幅の一覧・profile・detail・confirmation・pending・error、focus / Escape / ARIA、console 0件をlocal通常認証fixtureで確認した。長いusernameのconfirmation overflowとblock→unblock後のstale confirmationを最小修正し、成功statusも保持。実Tab / Shift+Tab / Enter、screen reader、真の同時multi-session raceは未実施として区別。local reset後fixture 0件、repository / local / remote 30 migration一致、全pgTAP`1,673 / 1,673 PASS`。DB・migration・pgTAP定義・package変更なし |
| 2026-08-13 | commit前。基準HEAD `c5c4df10eb99d10d7a7d819717756b4cc9c63b88` | Phase E3aとしてExchange 3通知type parser / target navigation、read-onlyの`/exchange`・`/exchange/[diaryId]`、active / pending / archived一覧、oldest / latest pagination、削除済みplaceholder、mood / location / 非リンクtag / 画像件数、home導線を実装。local通常認証・RLS経路でA/B/C security、follow解除後の継続、共通404、mixed通知、5幅30画面のoverflow 0、semantic DOM、内部値・Storage path非露出、console 0件を確認。自動browserの実キー送出は未確認として区別。DB・migration・pgTAP定義・packageは変更せず、最新全pgTAPは`1,673 / 1,673 PASS` |
| 2026-08-11 | documentation commit前。基準HEAD `5b7d79cd322f5688560306ce967794a10e59b54f` | Phase E2a〜E2gのExchange DB / Storage foundation完了とE2h final read-only auditを同期。DB / Storage BLOCKER 0件、repository / local / remote 30 migration、30 pgTAP・最新確認済み`1,673 / 1,673 PASS`、E3 Application BLOCKER 7件、PRE-PUBLICATION 4件を現在値として整理し、DB / Storage完了とApplication / UI未実装を分離して記録 |
| 2026-08-10 | commit前。基準HEAD `8a889aa44e4c6875f30b35486162bf243f51987b` | Phase C4b-2として作成・編集formへ任意の場所名を追加し、Unicode codepoint基準のClient / Server validation、trim / NULL解除、location対応successor RPCへの切替、必要なposts取得shape、詳細・home・自他プロフィール投稿・タグ詳細・投稿検索結果の共通metadata表示を実装。既存tag / image manifest、upload / DB結果別cleanup、保持画像identity、pending / disabled、RLS / active-account gateを維持した。認証付きbrowser fixtureと5幅responsive・実キーボードは通常sign-upのローカルAuth rate limitと別browser不在により未実施。lint、typecheck、build、diff checkは成功。DB・migration・package・remote DBは変更せず、pgTAPはDB変更なしのため未再実行。Service Role・Auth Admin API・stage・commit・pushは未使用・未実施 |
| 2026-08-10 | 基準HEAD `cbfc1669874631fb11d5734041669cf50143619b` | Phase C4b-1として既存Application用画像統合RPCを維持し、location_name対応の作成・編集successor RPC、DB正規化、NULL解除、100 codepoint境界、active owner・未削除・row lock・tag/image rollback、最小EXECUTE ACLを追加。local resetで21 migrationをfresh適用し、新規pgTAP`48 / 48`、全pgTAP`1,002 / 1,002`を確認。新migration 1件をlinked開発DBへ通常適用し、repository / local / remote 21件一致、再dry-run up to date、remote catalog、3 schemaのlinked diff 0件を確認した。pg-delta CA warningはSQL成功後のcatalog cache補助warningと切り分け、repair・再適用なし。UI・Application・package・既存migration・remote fixture / Storageは変更せず、Service RoleとAuth Admin APIは未使用 |
| 2026-08-09 | commit前。基準HEAD `f23b617f4407245ded6c3c1d147d38a056046f06` | Phase C4aとしてSupabase SSR / PKCEのpassword reset request、account enumerationを避けるgeneric案内、既存callbackのSDK recovery marker＋JWT AMR二重確認、recovery session専用gate、共有password validation、password更新後local sign-outと新password loginを実装。通常UIとlocal Auth / mail captureで登録済み・未登録の同一案内、新規recovery、入力境界、更新、旧password拒否、新password login、protected route、logout、直接・malformed・使用済みlink、5幅responsive、ARIA、console 0件を確認。callback直後の同一redirect chainだけcookie反映が遅れ、次requestは正常だったためautomation制約として記録し、production workaroundは追加していない。実キーボード、瞬間的pending、期限切れlink、remote Auth / SMTPは未確認。lint、typecheck、build、diff checkは成功。DB・migration・pgTAP定義・package・remote DB / Authは変更せず、既存954件は未再実行の過去結果。local fixtureは残存し、Service Role・Auth Admin API・stage・commit・pushは未使用・未実施 |
| 2026-08-09 | commit前。基準HEAD `0327547e70550d3f544ab69ff65db55daec1be21` | Phase C3c-2として`/calendar`、semantic table月grid、前後月・今月遷移、日別件数・最新mood marker、今日・選択日、選択日全投稿一覧、home導線、投稿mutation後の再検証を実装。date-only queryもDB取得前にfail-closed化した。通常UIで同日3件・3公開範囲・mood未設定、月/年跨ぎ、URL reload・back / forward、不正・重複parameter、詳細遷移、timezone変更による日付境界再計算、320 / 360 / 375 / 390 / 1280px、semantic DOM、focus-visible、console warning / error 0件を確認し、fixture投稿をsoft delete、timezoneを復元、logoutした。実キーボードのTab / Shift+Tab / Enterは自動注入が安定せず未確認。419 runtime timezoneのCalendar assertion、lint、typecheck、build、diff checkが成功。DB・migration・pgTAP定義・package・remote DB、Service Role、Auth Admin API、stage・commit・pushは変更・使用・実施していない |
| 2026-08-09 | commit前。基準HEAD `f70bd4929ec7aedbe88e6b83cf50f864b8df05e3` | Phase C3c-1としてstrict month/date parser、viewer timezone基準の現在月・今日・前後月、Intlによるlocal month開始ごとの独立UTC変換、本人Calendar posts query、local date、日別post count・最新mood、選択日全投稿data shapeを実装。Tokyo / New York / Londonの境界、同一instantの日付差、同日複数投稿の`created_at DESC, id DESC`、query条件と419 runtime timezoneの3月・8月境界をNode assertionで確認した。既存viewer helperのclaims由来本人ID、通常authenticated client、本人filter、未削除、half-open range、既存posts RLSを維持し、Service Role・SECURITY DEFINERは追加していない。lint、typecheck、build、diff checkが成功。UI・browserは対象外。DB・migration・pgTAP定義・package・remote DBは変更せず、stage・commit・pushは未実施 |
| 2026-08-09 | commit前。基準HEAD `95a007477ebf3a021592f196476a482cd3748344` | Phase C3bとして`accounts.timezone`のDB validator trigger、pgTAP 31件、runtime標準IANA option・validation、viewer timezone helper、`/settings`、本人claimsと既存RLSを使うServer Action、home導線、pending・成功・generic error UIを実装。DB受理597件とNode Intl、Application option 419件とDB validatorの双方向不一致0件を確認。認証済みローカルBrowser回帰で保存直後のselectだけが旧値へ戻る問題を検出し、保存済みtimezoneでselectをremountする最小修正後、複数timezone保存・reload / 再訪保持・5幅responsive・accessibility・consoleを確認した。通常authenticated direct invalid UPDATEは拒否され、fixtureはlocal resetで清掃した。新規31件・全954件のpgTAP、helper 14件、lint、typecheck、build、diff checkを再確認。remote migration、Service Role、Auth Admin API、package変更、calendar、stage、commit、pushは未実施 |
| 2026-08-09 | commit前。基準HEAD `dbd0b837f92bf657088f2a25006fd180f7b9bbbb` | Phase C3aとしてfollowing / latestへ`created_at DESC, id DESC`の20件forward cursor pagination、21件目next判定、表示20件だけの補助hydrateを実装。version・feed・timestamp・UUIDをstrict検証するopaque base64url cursorをfeedへbindし、feed切替で破棄、不正cursorはgeneric error、現在のfollow・visibility・RLSをpageごとに再評価する。homeだけ本文を280 codepointsで省略し、281以上へellipsisと「続きを読む」を表示して投稿詳細・home以外は全文を維持した。認証済みローカルブラウザでfollowing `20 / 5`、latest `20 / 7`、reload・back / forward・直接URL、malformed / feed mismatch、follow解除・visibility変更後のsaved cursor、本文境界、5幅responsive、semantic / accessible name、console warning / error 0を確認。同一timestamp実fixtureと実キーボード操作は手動確認へ持ち越した。C3a fixtureはローカル限定resetで削除し、19 migration fresh適用、fixture全件0、全pgTAP `923 / 923 PASS`、lint、typecheck、build、diff checkを確認。DB / migration / pgTAP定義 / package / remote DB / Storageは変更せず、Service Role・Auth Admin・stage・commit・pushは未使用・未実施 |
| 2026-08-09 | commit前。基準HEAD `15960c342d32ac12287e11ed8c6d897bbdf34ffe` | Phase C2c-3として`/notifications`、20件複合cursor、RLS下のactor / comment batch hydrate、4 type文言、未読 / 既読、個別・すべて既読、home badge、Server側再評価によるtarget遷移、利用不能targetのneutral表示を実装。DB / migration / pgTAP定義 / packageは変更せず、全pgTAP923件とnpm・diff検証が成功。認証済みローカルブラウザで通知4種、個別・open・すべて既読、未読badge、neutral / stale target、post可視性再評価、不正cursor、22件の`20 / 2` pagination、5幅の横スクロールなし、console error / warning・React / hydration warning 0を確認。fixture清掃後に全pgTAP `923 / 923 PASS`。実キーボードと低速環境でのpending表示目視は手動確認へ持ち越し。remote schema / migration / Storageは変更せず、Service Role・Auth Admin・直接notifications INSERTは未使用 |
| 2026-08-09 | commit前。基準HEAD `bac2b1326a3e87beaa009a32bed5e36ac6eb84f9` | Phase C2c-2としてfollow / reaction / comment / replyの通知生成をAFTER INSERT triggerで実装。source rowとDB current dataからrecipient / actor / targetを決定し、authenticated role＋`auth.uid()`一致、active両端、自己通知除外を防御的に検証するtrigger専用SECURITY DEFINER functionを追加した。reaction UPDATE / DELETEとfollow DELETEは通知せず、再INSERTは新規eventとして追加する。reply notificationはparent authorだけへ送り、新reply自身をtargetとし、invalid parentは独自errorなしで既存generic `23514`を維持する。ローカルresetで19 migrationをfresh適用し、新規48件・全923件がPASS。remoteはC2c-1まで18 migrationでC2c-2未適用。UI・package・既存test・Server Action・notifications RLS / ACLは変更せず、stage・commit・pushも未実施 |
| 2026-08-09 | commit前。基準HEAD `7e5cf7669fd82db2b0b91a1868e240ae68ed7ad6` | Phase C2c-1としてnotifications DB / RLS基盤を実装。generic targetを採用せずpost / comment明示列、4 type shape、自己通知拒否、account / post / commentへのcascade FK、recipient安定順index、active recipient / actorと現在のposts RLSを再評価するrecipient専用SELECT / UPDATE policy、SELECT＋`UPDATE(is_read)`の最小ACLを追加した。ローカルincremental適用後に新規pgTAP`65 / 65`、resetで18 migrationをfresh適用し全`875 / 875`を確認。reset前には既知active fixtureによる`0016`の1件失敗を再現して今回回帰と区別した。remote migration、通知生成、UI、package、Service Role、Auth Admin API、stage、commit、pushは未実施 |
| 2026-08-09 | commit前。基準HEAD `2951462d1e2fc3a7a230ab7a0882c813c579cd72` | Phase C2bとして既存comment作成・soft-delete経路を再利用し、返信Server Action、`parent_comment_id`取得、安定順の1階層親子表示、inline reply form、削除済み・取得不能な親のneutral placeholder、返信削除後refreshを実装。認証claims由来の`user_id`、RLSとC2a validatorの最終認可、invalid parentのgeneric UI errorを維持した。C2a pgTAPは`46 / 46 PASS`、全pgTAPは既存active local fixtureが`0016`の期待へ混入した1件だけ失敗して`810 / 811`。lint、typecheck、production build、diff checkを実施し、認証済みローカルブラウザで返信作成・refresh保持・削除、本文境界、pending、stale parent、neutral placeholderを確認。1280pxは横scrollなし、320 / 360 / 375 / 390pxはBrowser viewport overrideが反映されず未実施。DB・migration・package・通知は変更せず、Service Role、Auth Admin API、stage、commit、pushは未使用・未実施 |
| 2026-08-09 | commit前。基準HEAD `3d6d5b3c968ed9564829055076555f2fc89a3b14` | Phase C2aとしてcommentsへnullable `parent_comment_id`、1階層・same-post・parent存在・未削除・active authorをDBで保証するlocking trigger、安定取得index、最小INSERT列権限を追加。追加security reviewで不可視別post parentと不存在parentのエラー差を再現し、全invalid parentをgenericな`23514 / invalid parent comment`へ統一した。既存top-level direct INSERT、RLS、soft-delete RPCを維持し、自己参照FKは物理削除時のcascade消失・top-level化・Auth削除阻害を避けるため採用しなかった。local / remote 17 migration一致、再dry-run、remote catalog、linked schema diff、新規pgTAP46件・全811件、lint、typecheck、build、diff checkが成功。UI・通知・package、remote fixture、Service Role、Auth Admin API、reset、repairは未実施・未使用 |
| 2026-08-08 | commit前。基準HEAD `98b047c439385ee1963d77eaa4ab37e45126e702` | Phase C1bとして本人accounts status最小readを使うrequest-scoped session gateを実装。login・即時session付きsign-up・callback・protected request・画像request・Server Action requestで`active`以外、row欠損、query errorをfail-closed化し、local scope sign-out、固定message code、画像404、redirect loop回避を追加。ローカル公開Auth clientとSSR cookieでactive / suspended / deactivated / stale request / direct URL / image / stale POST / active復帰を統合確認し、実ブラウザでも主要login・stale session・protected URL・logout・generic errorを確認した。stale Server Actionの通常303がNext.js clientでpendingになる問題を検出し、`next-action`へ`x-action-redirect`を返す最小修正後、login退避・mutation 0件・追加console errorなしを再確認した。全pgTAP 765件、lint、typecheck、build、diff checkが成功。320〜390px、信頼できるTab / Enter、実callback、実画像bytesのnon-active browser表示は未実施。migration・package・remote DB / Storage、Service Role、Auth Admin API、stage・commit・pushは変更・使用なし |
| 2026-08-08 | commit前。基準HEAD `16a93b3aaebe00082a782828a6300d2f86ed88ca` | Phase C1aとしてnon-active accountのDB / RLSをfail-closed化し、本人accounts status readだけをC1b用に維持。ローカル16 migration fresh適用、新規pgTAP 79件・全765件、npm検証を完了。C1a migration 1件だけをリモート開発DBへ通常適用し、履歴16件一致、再dry-run up to date、remote catalog / ACL / RLS回帰、3 schemaのlinked diff 0件を確認。catalog cacheの一時CA warningはSQL成功後の補助warningと切り分け、repair・再適用なし。remote fixture・ユーザーデータ・Storage object、Service Role、Auth Admin APIは使用していない。C1b application session gateは未実装 |
| 2026-08-08 | `d0ef062d9090af8574d4215c21a67f7a5230a431` | Phase B3dとして既存投稿の画像追加・削除・並び替え、atomic post / tag / image更新RPC、保持identity、DB結果別Storage cleanup、mixed preview UIを実装して`feat: add post image editing`として完了。ローカル15 migration、新規pgTAP 36件・全686件、実Storage API、ブラウザ、5幅responsive、npm検証を完了。B3d migrationだけをリモート開発DBへ通常適用し、履歴15件一致、remote catalog / ACL / Storage境界、再dry-run、3 schemaのlinked diff 0件を確認。remote実update / Storage lifecycleは安全な既存認証情報がないため未実施。Service Role、Auth Admin API、remote fixtureは使用していない |
| 2026-08-08 | commit前。基準HEAD `d202e8db4cea5c8e2d7d3c3b3b4c6f29a1412f5d` | Phase B3cとしてsigned URLを採用せず、cookie認証付き`/post-images/[imageId]`、post_images / Storage RLSの取得ごとの再評価、private no-store、raw path非露出、bounded metadata batch、共通galleryを詳細・timeline・profile・tag・検索へ統合。follow解除、visibility変更、soft delete、未認証、不正 / 不存在UUID、5幅responsive、0 / 1 / 2 / 3 / 10枚、pagination、consoleを通常認証fixtureで確認。ローカル14 migration fresh適用、全pgTAP 650件、npm検証を完了し、fixture残数0を確認。migration・pgTAP定義・packageは変更せず、remote操作、Service Role、Auth Admin API、stage・commit・pushは未実施 |
| 2026-08-08 | commit前。基準HEAD `7ea2b85c4db023d4195316acd898c5a6b0493d8f` | Phase B3bとしてJPEG / PNG / WebP・1枚6 MiB・最大10枚の新規投稿画像upload、選択順preview・削除、strict UUID path、operation-aware Storage RLS、atomic post/tag/image RPC、途中失敗とDB失敗cleanupを実装。Storage object row lockで確定直前の並行cleanupを直列化。ローカル14 migration fresh適用、新規pgTAP 47件・全650件、実Storage API、画像なし投稿、5幅responsive、npm検証を完了。B3b migrationだけをリモート開発DBへ通常適用し、履歴14件一致、remote catalog、再dry-run、linked schema diffを確認。remote実upload / RPC mutationは未実施。Service Role、Auth Admin API、remote fixture・ユーザーデータ・Storage objectの作成や変更は行っていない |
| 2026-08-08 | commit前。基準HEAD `2a7107ca3a95d05d8792aae89b17b20d80ea0d9e` | Phase B3aとしてprivate post画像bucket、post_images、最大10枚・順序・path制約、既存posts RLSへ委任するmetadata SELECT、Storage SELECT allowとRESTRICTIVE guard、最小ACLを実装。ローカル13 migration fresh適用、新規pgTAP 75件・全603件、local schema diff、npm検証を完了。B3a migration 1件をリモート開発DBへ通常適用し、履歴13件一致、remote catalog、再dry-run、linked schema diffを確認。適用後のpg-delta catalog cache warningはSQL成功後の後処理warningと切り分けた。UI変更なし。Git stage・commit・pushは未実施 |
| 2026-08-06 | commit前。基準HEAD `be79d85eee60ba08ca8bdc698ee66b77756c4c46` | Phase B2b-3bとして投稿title / body検索、既存posts RLSへ委任する`SECURITY INVOKER` RPC、NFKC・literal wildcard、20件cursor pagination、ID再取得と共通hydrate・`TimelinePostCard`再利用を実装。ローカル12 migration fresh適用、新規pgTAP 52件・全528件、local catalog/schema diff、npm検証、認証済みブラウザ・5幅responsive検証を完了。新migrationはremote未適用。remote操作、Git stage・commit・pushは未実施 |
| 2026-08-06 | commit前。基準HEAD `1b73043e6262aa410c4f7d593fb36ae9c612ee52` | Phase B2b-3aの`20260804000100`だけをリモート開発DBへ通常適用。local / remote履歴11件一致、再dry-runはup to date、remote catalog属性・ACL・tags RLS前提の一致、`public,my_diary_private`のlinked schema diffが空であることを確認。適用後のcatalog cache生成warningはSQL成功と切り分け、リモートfixture・ユーザーデータ操作、Git stage・commit・pushは未実施 |
| 2026-08-04 | commit前。基準HEAD `1b73043e6262aa410c4f7d593fb36ae9c612ee52` | Phase B2b-3aとしてusers / tags検索UI基盤、ユーザー検索NFKC対応、RLSを通すタグ部分一致検索、20件forward cursor pagination、厳格なquery/cursor検証を実装。新migration・pgTAPを各1件追加し、ローカルreset後に全pgTAP 476件、npm検証、認証済みブラウザ・レスポンシブ検証を完了。リモートDB操作、既存migration/test変更、Git stage・commit・pushは未実施 |
| 2026-08-03 | commit前。基準HEAD `37b055ea9b18c19ec04fb040e3851ff579534938` | Phase B2b-2としてRLS上閲覧可能なタグ一覧・タグ詳細、UUID canonical route、50件・20件のforward cursor pagination、投稿タグのUUIDリンク、home導線、404・空状態・loadingを実装。通常のauthenticated経路だけで認証済みブラウザ、PostgREST実response、RLS、responsiveを検証し、fixtureをローカルDB resetで清掃後に全pgTAP 406件とnpm検証を完了。DB・migration・pgTAP定義は変更なし |
| 2026-08-02 | commit前。基準HEAD `756a32e341c9a84de2e3106c82f534335445087d` | Phase B2b-1としてタグのチップ入力、Server Action validationと実配列送信、nested select、投稿詳細・timeline・自他投稿一覧の非リンク表示を実装。全pgTAP 406件とnpm検証、認証済みブラウザ・レスポンシブ検証を完了。タグ一覧・詳細・検索は未実装として維持 |
| 2026-08-02 | 作業開始時 `9bdd08682cfa963bb9e4da531849f195c8772531` | Phase B2aとしてatomic post/tag作成・更新RPC、最大5個保証、posts直接mutation閉鎖、Server Action移行、pgTAPを追加。UI・route・検索は未実装として維持 |
| 2026-08-02 | `9bdd08682cfa963bb9e4da531849f195c8772531` | Phase B1として自由タグDB読み取り基盤、NFKC canonical制約、可視post連動SELECT RLS、pgTAPを追加。mutation・最大5個保証・UI・route・検索は未実装として維持 |
| 2026-08-02 | `072c73ef460869105051134c3addd1901df3a11b` | Phase A1としてフォロー中・最新投稿timelineとリンク型feed分離を実装。最大50件固定、pagination・無限scroll・長文省略は未実装として維持 |
| 2026-08-02 | `4c7ff37de13b035decb791f91f05adb4038c88b3` | Ver.2.0、repository、8 migration、8 pgTAPに基づき初回作成 |
