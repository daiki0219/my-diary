# my-diary 現在の実装状況

> この文書は、my-diaryの現在の実装状況を示す。
> 仕様そのものは [`my-diary_spec_v2.0.md`](../../my-diary_spec_v2.0.md) を正とする。
> 各Phase完了後に、実装・migration・テスト結果に基づいて更新する。
> 計画や希望だけで「実装済み」に変更しない。

## 1. 文書の目的

この文書は、正式仕様の各項目と現在のrepositoryに存在する実装根拠を対応付け、次のPhaseを判断できる状態に保つための管理文書である。仕様の追加・変更はこの文書では行わない。

- 正式仕様: [`my-diary_spec_v2.0.md`](../../my-diary_spec_v2.0.md)
- 初期MVPの履歴資料: [`docs/specs/archive/my-diary_MVP_spec_v1.0.md`](../specs/archive/my-diary_MVP_spec_v1.0.md)
- DB設計資料: [`docs/database/core-schema-rls-design.md`](../database/core-schema-rls-design.md)
- 調査基準日: 2026-08-09
- 調査時branch: `main`
- 調査基準HEAD: `15960c342d32ac12287e11ed8c6d897bbdf34ffe`
- 調査基準HEADのmessage: `feat: generate notifications`

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

この文書では、機能を58個の管理項目へ分けて集計する。

| 状態 | 件数 |
| --- | ---: |
| 実装済み | 29 |
| 一部実装済み | 4 |
| 未実装 | 8 |
| MVP後 | 17 |
| 確認不能 | 0 |
| 合計 | 58 |

現在は、メールアドレスとパスワードによる認証、non-active accountのapplication session gate、プロフィールの表示・編集、日記の作成・詳細・編集・soft delete、6種類の気分、自由タグの入力・保存・投稿上のリンク表示・タグ一覧・タグ詳細・部分一致検索、3段階の公開範囲、フォロー中・最新投稿の2種類のタイムライン、private Storage画像の新規投稿upload・認証付き表示・既存投稿での追加・削除・並び替え、3種類のリアクション、コメントの投稿・1階層返信・親子表示・soft delete、フォロー・解除・一覧、ユーザー名検索、閲覧可能な投稿のtitle・body部分一致検索まで実装されている。

DB側では、`accounts`、`profiles`、`posts`、`follows`、`reactions`、`comments`、`tags`、`post_tags`、`post_images`、`notifications`の10 tableと、公開範囲・active状態を守るRLS、権限を限定した関数、RLS自動有効化の安全網がmigration管理されている。Phase C1aでは、Auth sessionを保持する`suspended` / `deactivated` viewerも通常データを取得できないよう、posts owner例外、profiles、SECURITY DEFINER profile検索、Storage orphan経路をactive必須へ変更した。Phase C1bでは通常authenticated clientでviewer本人の`accounts.status`だけを確認し、`active`以外、account row欠損、status query失敗を通常利用へ通さず、login・即時session付きsign-up・callback・protected request・画像request・Server Action requestでsessionを終了する。Phase C2aでは1階層comment返信のDB基盤をrepository / local / remoteへ追加し、invalid parentをgeneric errorへ集約した。Phase C2bでは既存comment経路を再利用して返信Server Action、親子表示、inline form、削除済み・取得不能な親のneutral placeholder、返信soft deleteをApplication / UIへ接続した。Phase C2c-1ではfollow / reaction / comment / replyを保持する通知DB / RLS基盤を追加し、Phase C2c-2では4種類のsource INSERTへ同一transactionの通知生成triggerを接続した。Phase C2c-3ではRLS下の通知一覧、未読件数、個別・すべて既読、Server側で再評価するtarget遷移、削除済みcomment等のneutral表示をApplication / UIへ接続した。自由タグ、投稿検索、private投稿画像とatomic mutationは既存設計を維持する。pgTAPは19ファイル、plan合計923 assertionで、通知生成、ACL、active境界、現在のpost可視性、既読列更新、invalid replyのgeneric errorとatomic rollbackを含むDB認可を対象としている。

MVP完了条件との差分には、場所入力UI、タイムラインのページネーション、カレンダー、設定がある。パスワードリセットとOAuth、avatarも未完成である。non-active accountのDB / RLS境界とapplication session gateはPhase C1a / C1bで完了し、1階層コメント返信はPhase C2a / C2bでDBからApplication / UIまで完了した。通知はDB / RLS基盤、follow / reaction / comment / reply生成、一覧・未読/既読・target遷移までPhase C2c-1〜C2c-3で完了した。投稿画像の新規作成・表示・編集要件はPhase B3a〜B3dで完了した。MVP後のカテゴリー、推し活、コミュニティ、ぬい活、イベント、アルバム、おすすめ、AI、プレミアムは未着手であり、現時点のMVP欠陥としては扱わない。

### 2.1 MVP残差と実装優先順位

正式仕様上のMVP分類と、公開前の実装優先順位は別に管理する。

- 公開前に重要: timeline pagination / infinite scroll、timezone settings、calendar
- 強く推奨: password reset、`location_name`のUI接続、timeline本文省略、follow / profile / user検索等の固定件数改善
- MVP対象だが後順位: Google login、Apple login、avatar、timezone以外のsettings、profile / follow list等のpagination
- MVP後またはmaintenanceへ延期可能: 長期orphan cleanup、soft-deleted画像のphysical delete、保持期間後のphysical delete、正式仕様のPhase 2以降の機能

この優先順位は正式仕様のMVP対象をMVP後へ変更するものではない。投稿画像の主要利用者要件は実装済みだが、物理削除と長期orphan回収は運用・保持方針を伴う後続maintenanceとして残る。

## 3. 技術・リポジトリ状態

| 項目 | 現在の状態 | 根拠 |
| --- | --- | --- |
| framework | Next.js 16.2.11、App Router | `package.json`、`src/app/**` |
| language | TypeScript 5、React 19.2.4 | `package.json`、`tsconfig.json` |
| styling | Tailwind CSS 4、mobile-firstのutility class | `package.json`、`src/app/globals.css`、各component |
| backend | Supabase Auth、Postgres、RLS、Supabase SSR | `@supabase/ssr`、`@supabase/supabase-js`、migration |
| 認証方式 | email/password、SSR cookie session、認証callback、request-scoped account status gate | `src/app/auth/actions.ts`、`src/app/auth/callback/route.ts`、`src/lib/supabase/account-session.ts`、`src/proxy.ts` |
| migration | repository / local / remoteは19件。latestは`20260809000300_generate_notifications.sql` | `supabase/migrations/*.sql`、local / linked remote migration list |
| DB table | repository / localは10 table | `accounts`、`profiles`、`posts`、`follows`、`reactions`、`comments`、`tags`、`post_tags`、`post_images`、`notifications` |
| pgTAP | 19ファイル、plan合計923。C2c-2のfresh reset後は`923 / 923 PASS` | `supabase/tests/database/*.sql` |
| その他の自動テスト | repository内では未確認 | unit、component、E2Eのtest fileは存在しない |
| npm検証 | `lint`、`typecheck`、`build` | `package.json` |
| 調査基準commit | `15960c342d32ac12287e11ed8c6d897bbdf34ffe` | `feat: generate notifications`。Phase C2c-2までを含む |

Server Componentがpageとデータ取得を担当し、入力フォーム、フォロー、リアクション、削除などの操作UIをClient Componentへ分けている。投稿作成・更新はServer Actionからatomic RPCを呼び、SECURITY DEFINER関数内で`auth.uid()`、active状態、所有権、未削除を最終検証する。SELECTとその他の一般mutationはRLSを最終認可としている。タグrouteには共通の`loading.tsx`があり、送信操作のpending表示は各Client Componentの`useFormStatus`で実装されている。

## 4. 機能別実装状況

### 4.1 認証

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| email/password会員登録 | 実装済み | `/sign-up`、`signUp` Server Action、email確認callback。`my_diary_on_auth_user_created`が`accounts`と`profiles`を作成 | なし |
| ログイン・ログアウト・session・未認証遷移 | 実装済み | `/login`、`login`、`logout`、SSR cookie更新、各protected pageの`getClaims()`と`/login` redirect | 公開投稿の匿名閲覧は採用せず、認証画面へ誘導する方式 |
| パスワードリセット | 未実装 | 対応route、action、UIなし | reset request、callback、password更新を実装する |
| Googleログイン | 未実装 | OAuth actionとUIなし | provider設定と通常OAuth導線が必要 |
| Appleログイン | 未実装 | OAuth actionとUIなし | provider設定と通常OAuth導線が必要 |
| suspended account制御 | 実装済み | Phase C1aでDB / RLSをfail-closed化し、Phase C1bでlogin・即時session付きsign-up・callback・protected request・画像request・Server Action requestへ共通status gateを追加。本人accounts statusだけを取得し、`active`以外・row欠損・query失敗はfail-closedでcurrent sessionを終了し、固定codeのgeneric messageへ誘導する | ローカル統合回帰と実ブラウザ主要シナリオを確認済み。320〜390pxはBrowser viewport overrideが反映されず未確認 |

主な関連コードは`src/app/auth/actions.ts`、`src/app/auth/callback/route.ts`、`src/lib/supabase/server.ts`、`src/lib/supabase/proxy.ts`である。主な関連テストは`0001_core_rls.test.sql`、`0004_user_search_and_follows.test.sql`、`0006_user_profile_posts_rls.test.sql`、`0007_follow_lists_rls.test.sql`である。

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
| 場所名 | 一部実装済み | `posts.location_name`と100文字CHECKは存在。Phase B2a RPCには含めず、作成時NULL・更新時既存値維持 | form、Server Actionの入力・保存、表示がない |
| カテゴリー・推し・ぬい・イベント・アルバム関連 | MVP後 | 正式仕様でPhase 3以降 | MVP完了条件には含めない |

投稿の関連コードは`src/app/(protected)/posts/actions.ts`、`src/lib/post-data.ts`、`src/lib/tag-data.ts`、`src/lib/post-image-data.ts`、`src/components/posts/**`である。`0001_core_rls.test.sql`、`0005_post_edit_rls.test.sql`、`0006_user_profile_posts_rls.test.sql`、`0009_tags_rls.test.sql`、`0010_post_tag_mutation_rpc.test.sql`、`0013_post_images_storage_rls.test.sql`、`0014_post_image_upload_mutation.test.sql`、`0015_post_image_edit_mutation.test.sql`が主要なDB回帰を担う。

### 4.4 タイムライン

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| timeline共通表示・feed分離 | 実装済み | `/home?feed=following`と`/home?feed=latest`をリンク型navigationで切り替え、選択中リンクへ`aria-current="page"`を付与。投稿者、日時、気分、title、body、タグ、画像、reaction、comment件数、詳細導線を共通利用 | body省略、継続取得がない |
| フォロー中timeline | 実装済み | queryなし・空・未知・複数値を含む既定feed。`follows`からfollow先を取得し、自分＋follow先のauthorへ絞ったうえでRLSがprivate、suspended、soft delete等を最終除外 | 最大50件固定。大量follow時の`.in(...)`は実データで評価が必要 |
| 最新投稿timeline | 実装済み | `feed=latest`で`visibility = public`を明示し、RLS上閲覧可能な全active投稿者のpublic投稿を新着順に表示 | 最大50件固定 |
| pagination / infinite scroll | 未実装 | homeは50件固定、profile投稿とfollow一覧は20件固定で案内文のみ | cursor等による安定した継続取得が必要 |

RLSは権限のない投稿、soft-deleted投稿、suspended投稿者の投稿をDB取得結果から除外する。`getTimelinePosts`は`created_at DESC, id DESC`、最大50件を共通条件とし、タグはposts queryのnested select、作者プロフィール、reaction、comment件数はbatch取得として投稿単位のN+1を避けている。タグrelationの取得・shape検証に失敗した場合はタグ0件へ丸めず投稿取得エラーとする。各feedには固有の説明文と空状態がある。

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
| カレンダー | 未実装 | route、component、日付別queryなし | timezone、同日複数投稿、気分表示を設計する |
| 通知 | 実装済み | DB / RLS、4 type生成、`/notifications`、20件複合cursor、actor / comment batch取得、未読badge、個別・すべて既読、Server側再評価による遷移、利用不能targetのneutral表示を実装 | 大量通知での実データ性能は継続評価する |
| 設定 | 未実装 | `/settings`相当のrouteなし | timezone等の設定UIを定義する |
| レスポンシブ | 一部実装済み | mobile-first class、`min-w-0`、`break-words`、`overflow-wrap:anywhere`、幅制限を主要画面に使用。投稿画像galleryを320 / 360 / 375 / 390 / 1280pxで確認済み | repository内にviewport別の自動回帰テストはない |
| アクセシビリティ | 一部実装済み | label、role、aria-live、focus-visible、semantic heading/link/buttonを主要UIに使用 | 網羅的なkeyboard、contrast、screen readerの自動検証はない |
| error handling・loading | 一部実装済み | not-found UI、role alert、empty state、Server Action error、送信中disabledを実装 | route-level `loading.tsx`、error boundary、再試行UIは未整備 |
| ログ・監視 | 一部実装済み | `/api/health/supabase`は秘密情報を返さず接続状態を返す | 集約ログ、監視、管理操作logはない |
| 振り返り | MVP後 | profileに総投稿数の基盤はあるが、正式仕様ではPhase 2 | 今月、連続投稿日数、去年の今日、timezone集計なし |
| 通報・管理者機能 | MVP後 | `accounts.role/status`は基盤として存在 | reports table、管理画面、停止/解除操作、管理履歴なし |

## 5. DB・セキュリティ実装状況

### 5.1 tableと主要制約

| 対象 | 状態 | column | 主な制約・index・権限 |
| --- | --- | --- | --- |
| `accounts` | 実装済み | `user_id`、`role`、`status`、`timezone`、`created_at`、`updated_at` | Auth userへのcascade FK、role/status/timezone CHECK、本人SELECT、active時のtimezone更新 |
| `profiles` | 一部実装済み | `user_id`、`username`、`bio`、`avatar_path`、`created_at`、`updated_at` | Auth userへのcascade FK、文字数CHECK、`lower(username)` index、本人更新。avatar利用UIとsuspended対象のSELECT制限は未完成 |
| `posts` | 一部実装済み | `id`、`user_id`、`title`、`body`、`mood`、`location_name`、`visibility`、`created_at`、`updated_at`、`deleted_at` | Auth userへのcascade FK、入力値CHECK、partial index、可視性RLS。authenticatedの直接INSERT/UPDATEを閉じ、atomic post/tag RPCだけを一般作成・更新経路とする |
| `follows` | 実装済み | `follower_id`、`following_id`、`created_at` | 両userへのcascade FK、複合PK、self-follow CHECK、active関係だけのSELECT、following/follower安定順index |
| `reactions` | 実装済み | `id`、`post_id`、`user_id`、`reaction_type`、`created_at`、`updated_at` | post/accountへのcascade FK、3種類CHECK、投稿×ユーザーUNIQUE、post/type index、可視post連動RLS |
| `comments` | 一部実装済み | `id`、`post_id`、`user_id`、`body`、`parent_comment_id`、`created_at`、`updated_at`、`deleted_at` | post/accountへのcascade FK、body/deleted_at CHECK、通常comment・返信のpartial index、可視post連動RLS、soft-delete RPC。返信関係はDB triggerで1階層・same-post・parent存在・未削除・active authorを保証 |
| `tags` | 実装済み | `id`、`name`、`normalized_name`、`created_at` | NFKC canonical name、30 codepoint上限、文字種制約、UNIQUE、可視post連動SELECT。master mutationはatomic RPC内部だけで、入力・投稿表示・一覧・詳細・検索UIを実装済み |
| `post_tags` | 一部実装済み | `post_id`、`tag_id`、`created_at` | 複合PK、cascade FK、逆引きindex、可視post連動SELECT RLS。RPC内の最大5個検証、post row lock、差分更新を実装 |
| `post_images` | 実装済み | `id`、`post_id`、`storage_path`、`sort_order`、`created_at` | post物理削除へのcascade FK、`sort_order` 0〜9 CHECK、投稿×順序のdeferrable UNIQUE、path UNIQUE、可視post連動SELECT RLS。authenticatedの直接mutationはなく、作成・編集RPCがStorage object確認後にmetadataをatomic確定・更新。同一origin routeがRLS下でpathを解決して配信し、clientへはidと順序だけを渡す |
| `notifications` | 実装済み | `id`、`recipient_user_id`、`actor_user_id`、`notification_type`、`target_post_id`、`target_comment_id`、`is_read`、`created_at` | account / post / commentへのcascade FK、4 typeとtarget shape・自己通知拒否CHECK、recipient安定順index、active recipient / actorと現在のposts RLSを再評価するrecipient専用SELECT / UPDATE RLS、authenticatedは`UPDATE(is_read)`のみ。DB trigger生成とRLS下の一覧・既読UIを実装 |

Postgres enumは使用せず、`role`、`status`、`mood`、`visibility`、`reaction_type`をtextとCHECK制約で管理している。主要FKはuser削除またはpost削除に対するcascadeを設定している。物理DELETEは一般ユーザーへ付与せず、postとcommentは専用RPCでsoft deleteする。

### 5.2 RLS、function、trigger、ACL

- 10個のpublic tableすべてでRLSを明示的に有効化している。
- public tableのpolicyは合計21件で、accounts 2、profiles 2、posts 3、follows 3、reactions 4、comments 2、tags 1、post_tags 1、post_images 1、notifications 2である。加えて`storage.objects`にpost画像用policyが8件（SELECT 4、INSERT 2、DELETE 2）ある。
- `posts` SELECTは本人、active viewer、active author、follow関係、visibility、`deleted_at`をDB側で評価する。
- reactionsとcommentsは、参照先postを現在のviewerが閲覧できる場合だけSELECT・mutationできる。
- post_tagsは可視postだけをSELECTでき、tagsは可視なpost_tagsが存在する場合だけSELECTできる。tags → post_tags → postsの一方向評価とし、private・権限外followers・soft-delete済みpostだけに紐づくtag名を隠す。
- post_imagesは可視postだけをSELECTできる。`storage.objects`は対応metadataが見える場合、または通常upload / cleanup中の本人所有orphanだけをSELECTできる。INSERT / DELETEはStorage operation context、本人owner、3 UUID segment path、active状態または未参照状態を検査し、UPDATE / upsertは許可しない。標準Storage tableのowner、ACL、owner_idは変更していない。
- `my_diary_is_account_active`と`my_diary_can_view_post`をprivate schemaへ置き、再帰的RLSを避けている。
- `my_diary_validate_comment_parent`は一般roleから直接実行できないprivate trigger functionで、返信INSERT時にparent rowをlockし、1階層・same-post・未削除・active authorを検証する。ownerは`postgres`、`SECURITY DEFINER`、空search pathである。
- `my_diary_normalize_tag_name`をprivate schemaへ置き、NFKC、前後空白、先頭`#`、連続空白、ASCII caseを決定的にcanonical化する。一般application roleにはEXECUTEを付与しない。
- `my_diary_soft_delete_post`、`my_diary_soft_delete_comment`は本人とactive状態を再検証する。
- `my_diary_create_post_with_tags`と`my_diary_update_post_with_tags`は投稿本体とtag relationを同一transactionで処理し、後者はpost row lockと差分更新を使用する。
- `my_diary_search_profiles`はauthenticated identity、NFKC、入力長、literal wildcard、active対象、20件上限を関数内で検証する。
- `my_diary_search_tags`は`SECURITY INVOKER`で既存tags RLSを通し、authenticated identity、NFKC canonical query、literal wildcard、cursor、21件取得を検証する。21件目はUIの次ページ判定だけに使用する。
- `my_diary_search_posts`は`SECURITY INVOKER`で既存posts RLSを通し、authenticated identity、NFKC、1〜50 codepoint、literal wildcard、title / body OR、`created_at DESC, id DESC`のcursor、最大21件を検証する。UIは20件を表示し、RPCのIDだけを通常SELECTで再取得して現在のRLSを再評価する。
- `SECURITY DEFINER`関数はownerを`postgres`へ固定し、空の`search_path`または`pg_catalog`固定を使用する。
- table・column・functionの権限は既定権限をREVOKEして必要なauthenticated権限だけをGRANTする。
- `rls_auto_enable()`はevent trigger `ensure_rls`からpublic schemaの新規table、partitioned table、CTAS、SELECT INTOへRLSを有効化する。policyやFORCE RLSは作成しない。
- `rls_auto_enable()`のEXECUTEは`PUBLIC`、`anon`、`authenticated`、`service_role`、`authenticator`からREVOKEされ、`postgres`だけに残る。

通常triggerは、5 tableの`updated_at`更新、Auth user作成時のaccount/profile作成、follow / reaction / comment / replyのnotification生成に使用する。別にevent trigger `ensure_rls`が存在する。

### 5.3 未作成の主要table

`notifications`はDB / RLS、4 type生成、一覧・既読UIまで作成済みである。`post_images`はDB・private Storage・新規投稿時のupload / preview / atomic metadata確定 / 失敗cleanup、一覧・詳細への認証付き配信と表示、既存投稿での追加・削除・並び替え、保持identity、atomic更新、DB commit後の旧object cleanupまで作成済みである。長期orphan回収、soft delete画像と保持期間後の物理削除は未実装である。`tags`と`post_tags`はDB読み取り・mutation基盤、利用者向け入力・投稿リンク、タグ一覧・詳細・検索まで作成済みである。Phase 2の`reports`、Phase 3以降のcategories、favorites、communities、plushies、events、albumsと各紐付けtableは未作成である。

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

| route | 種別 | 役割 |
| --- | --- | --- |
| `/` | page | landing、新規登録・ログイン導線 |
| `/login` | page | email/passwordログイン |
| `/sign-up` | page | email/password会員登録 |
| `/auth/callback` | route handler | email確認codeをsessionへ交換 |
| `/home` | page | 認証済みviewer向けのフォロー中・最新投稿timeline（`feed=following` / `feed=latest`） |
| `/notifications` | page | RLS上見える通知を20件ずつ表示し、未読 / 既読、個別・すべて既読、target遷移を提供 |
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
| `/users/[userId]` | dynamic page | 他ユーザーのプロフィールと閲覧可能投稿 |
| `/users/[userId]/following` | dynamic page | 他ユーザーのfollowing一覧 |
| `/users/[userId]/followers` | dynamic page | 他ユーザーのfollowers一覧 |
| `/search` | page | users / tags / posts category切替、NFKC canonical query、ユーザー・タグ・投稿title/body部分一致検索、タグ・投稿cursor pagination |
| `/api/health/supabase` | route handler | Supabase Auth healthの安全な状態応答 |

`not-found.tsx`はpost詳細、profile系、tag詳細に存在する。タグrouteには共通`loading.tsx`がある。専用のprotected layoutと`error.tsx`は存在しない。未認証時のpage-level redirectは各pageに残し、non-active accountのstatus確認・session終了はrequestごとに再評価されるProxyと共通helperへ集約している。

## 8. migration一覧

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
| `20260809000100` | `20260809000100_add_comment_replies.sql` | nullable parent relation、1階層・same-post・未削除・active parentを検証するlocking trigger、返信取得index、既存RLSを維持した最小INSERT列権限 |
| `20260809000200` | `20260809000200_create_notifications.sql` | notifications、4 type / target shape / 自己通知CHECK、account・post・commentへのcascade FK、recipient安定順index、active recipient / actorとposts RLSを再評価するSELECT / UPDATE policy、SELECT＋`UPDATE(is_read)`の最小ACL |

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
| 合計 | 923 | 19ファイル |

### 9.2 実行結果の区別

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
- repository内にunit、component、browser E2Eの自動test fileは確認できない。

## 10. 既知の制限・技術的負債

1. `rls_auto_enable()`はRLS有効化失敗をlogへ記録して元DDLを成功させるfail-openである。policyも自動作成しないため、各migrationで明示的なRLSとpolicyが引き続き必須である。
2. event triggerとfunction ACLは一般的なschema diffだけでは完全に検出できないため、migrationのpreflight/postconditionとpgTAPを維持する必要がある。
3. Supabase Authはnon-active accountの正しいcredential自体を受理し得る。Phase C1bはAuth確立直後と次のapplication requestでstatusを確認してcurrent sessionを終了する。最終認可はPhase C1aのDB / RLSであり、application gateだけへ依存しない。
4. timelineは最大50件、他者投稿とfollow一覧は最新20件、comment一覧は古い順100件で打ち切り、継続取得を実装していない。
5. timelineはフォロー中と最新投稿に分離済みだが、一覧本文を省略しない。フォロー中feedのauthor filterは`.in(...)`を使用するため、大量follow時のURL長・query性能を実データで評価する必要がある。
6. avatar_pathとlocation_nameはDB基盤だけで、UIから利用できない。
7. comment返信と通知はDBからApplication / UIまで実装済みである。通知は現在RLS上見える行だけを一覧・件数・既読更新の対象とするため、不可視だったpost targetが将来再び可視になると過去通知が未読で再表示される場合がある。通報tableは未作成である。
8. unit、component、E2E、accessibility、viewport別responsiveの自動回帰がない。
9. profile件数、timeline補助data、comment件数は複数queryを使う。投稿単位のN+1は避けているが、規模拡大時はRPC、view、集計方式を再評価する必要がある。
10. root-level `loading.tsx`と`error.tsx`はなく、未認証redirectと一般error handlingはpageごとに一部重複している。non-active status gateはProxyと共通helperへ集約済みで、protected layoutはClient navigation、Server Action、画像Route Handlerを単独では覆えないため追加していない。
11. 自由タグは入力・投稿リンク・一覧・詳細・検索まで実装済みである。入力順を保存するcolumnはなく、投稿上はcode point順、タグ一覧・検索はDBの`normalized_name`順で表示する。検索の部分一致は現時点で専用indexを追加せず、RLS適用後のscan性能は大規模データで再評価が必要である。最大5個はauthenticatedのRPC経路で保証し、特権roleの直接SQLを禁止するconstraint triggerは置いていない。認証済みブラウザ回帰は完了したが、同一`created_at`の実データ、suspended author、瞬間的loading、実キーボードによるTab / Enterは未確認である。
12. 投稿検索はNFKC化したtitle / bodyへの部分一致で、専用indexを追加していない。大規模データでRLS適用後のscan性能を再評価する必要がある。cursorはPostgRESTのtimestamp文字列をDateへ変換せず保持する。suspended author / viewerはpgTAPで確認し、通常UIによるブラウザ再現は未実施である。自動ブラウザのTab / Enter key injectionも再現できず、実キーボード確認が残る。

## 11. 次Phase候補

### C1 DB / RLS・application完了状態

- local DB / RLS: 実装・検証済み。repository / localは19 migration、全pgTAP `923 / 923 PASS`。
- remote DB: C1a migration適用済み。local / remote履歴16件一致、再dry-run up to date、remote catalog / ACLと3 schemaのlinked diff確認済み。
- application: C1b session gateをローカル実装・統合検証し、主要実ブラウザシナリオも確認済み。remote DB変更はない。320〜390px、信頼できるTab / Enter、実Auth callback、実画像bytesのnon-active browser表示は未実施。

### C2 comment replyの実装状態

- repository / local DB: `20260809000100_add_comment_replies.sql`を追加・適用し、17 migration。返信は1階層、same-post、存在する未削除・active parentだけをDB triggerで許可する。
- remote DB: C2a migration適用済みでlocal / remoteとも17 migration。再dry-run、remote catalog、linked schema diffを確認済み。migration repair、resetは未実施。
- application: 既存top-level comment経路とsoft-delete RPCを再利用し、返信Server Action、1階層親子表示、inline form、削除済み・取得不能な親のneutral placeholder、返信削除を実装済み。reply通知生成と通知UIも実装済み。

### C2c notificationの実装状態

- repository / local DB: `20260809000200_create_notifications.sql`と`20260809000300_generate_notifications.sql`を追加・fresh適用し、19 migration。4 type、自己通知拒否、target FK / shape、recipient / actor active境界、現在のpost可視性、recipient専用既読更新に加え、follow / reaction / comment / replyのevent単位生成とsource transactionとのatomicityをDBで保証する。
- remote DB: C2c-2まで19 migration適用済み。C2c-3ではremote schema・data・fixtureを変更していない。
- application: 通知生成責任はDB triggerへ限定したまま、`/notifications`、20件cursor pagination、actor profile / target commentのbatch hydrate、4 type文言、未読 / 既読、個別・すべて既読、home badge、Server側で再評価するtarget遷移、利用不能targetのneutral表示を実装済み。

### C1完了後の主な候補

1. timelineへcursor pagination / infinite scrollを追加し、本文省略を改善する。
2. timezone settingsを先に整備し、その後calendarを実装する。
3. password resetを追加し、Google / Apple OAuthはprovider設定を含む別Phaseで扱う。
4. `location_name`のform・Server Action・表示を既存atomic投稿更新へ接続する。

Phase B3dの投稿画像追加・削除・並び替えは完了済みであり、次Phase候補ではない。長期orphan回収、soft delete画像と保持期間後の物理削除は後続maintenanceとして別に扱う。

## 12. 更新履歴

| 日付 | HEAD | 内容 |
| --- | --- | --- |
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
