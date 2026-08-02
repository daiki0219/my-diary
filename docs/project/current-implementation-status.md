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
- 調査基準日: 2026-08-02
- 調査時branch: `main`
- 調査時HEAD: `072c73ef460869105051134c3addd1901df3a11b`
- 調査時HEADのmessage: `feat: split home timeline feeds`

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
| 実装済み | 17 |
| 一部実装済み | 8 |
| 未実装 | 16 |
| MVP後 | 17 |
| 確認不能 | 0 |
| 合計 | 58 |

現在は、メールアドレスとパスワードによる認証、プロフィールの表示・編集、日記の作成・詳細・編集・soft delete、6種類の気分、3段階の公開範囲、フォロー中・最新投稿の2種類のタイムライン、3種類のリアクション、コメントの投稿・表示・soft delete、フォロー・解除・一覧、ユーザー名検索まで実装されている。

DB側では、`accounts`、`profiles`、`posts`、`follows`、`reactions`、`comments`の6 tableと、公開範囲・active状態を守るRLS、権限を限定した`SECURITY DEFINER`関数、RLS自動有効化の安全網がmigration管理されている。pgTAPは8ファイル、plan合計267 assertionで、認証後の権限境界、soft delete、visibility変更、suspended状態、follow一覧、RLS自動有効化とACLを対象としている。

MVP完了条件との差分は、画像、自由タグ、場所入力UI、タイムラインのページネーション、コメント返信、通知、タグ・投稿検索、カレンダー、設定である。パスワードリセットとOAuth、avatarも未完成である。MVP後のカテゴリー、推し活、コミュニティ、ぬい活、イベント、アルバム、おすすめ、AI、プレミアムは未着手であり、現時点のMVP欠陥としては扱わない。

## 3. 技術・リポジトリ状態

| 項目 | 現在の状態 | 根拠 |
| --- | --- | --- |
| framework | Next.js 16.2.11、App Router | `package.json`、`src/app/**` |
| language | TypeScript 5、React 19.2.4 | `package.json`、`tsconfig.json` |
| styling | Tailwind CSS 4、mobile-firstのutility class | `package.json`、`src/app/globals.css`、各component |
| backend | Supabase Auth、Postgres、RLS、Supabase SSR | `@supabase/ssr`、`@supabase/supabase-js`、migration |
| 認証方式 | email/password、SSR cookie session、認証callback | `src/app/auth/actions.ts`、`src/app/auth/callback/route.ts`、`src/proxy.ts` |
| migration | 8ファイル | `supabase/migrations/*.sql` |
| DB table | 6 table | `accounts`、`profiles`、`posts`、`follows`、`reactions`、`comments` |
| pgTAP | 8ファイル、plan合計267 | `supabase/tests/database/*.sql` |
| その他の自動テスト | repository内では未確認 | unit、component、E2Eのtest fileは存在しない |
| npm検証 | `lint`、`typecheck`、`build` | `package.json` |
| 最新commit | `072c73ef460869105051134c3addd1901df3a11b` | `feat: split home timeline feeds` |

Server Componentがpageとデータ取得を担当し、入力フォーム、フォロー、リアクション、削除などの操作UIをClient Componentへ分けている。mutationはServer Actionで認証済みユーザーIDを取得し、RLSを最終認可としている。専用の`loading.tsx`はなく、送信操作のpending表示は各Client Componentの`useFormStatus`で実装されている。

## 4. 機能別実装状況

### 4.1 認証

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| email/password会員登録 | 実装済み | `/sign-up`、`signUp` Server Action、email確認callback。`my_diary_on_auth_user_created`が`accounts`と`profiles`を作成 | なし |
| ログイン・ログアウト・session・未認証遷移 | 実装済み | `/login`、`login`、`logout`、SSR cookie更新、各protected pageの`getClaims()`と`/login` redirect | 公開投稿の匿名閲覧は採用せず、認証画面へ誘導する方式 |
| パスワードリセット | 未実装 | 対応route、action、UIなし | reset request、callback、password更新を実装する |
| Googleログイン | 未実装 | OAuth actionとUIなし | provider設定と通常OAuth導線が必要 |
| Appleログイン | 未実装 | OAuth actionとUIなし | provider設定と通常OAuth導線が必要 |
| suspended account制御 | 一部実装済み | RLSとServer Actionはactive状態をmutation条件に使用し、他者投稿・follow関係も制限 | Auth login自体は`accounts.status`を検査せず、suspendedユーザーもsessionを取得できる。直接の他ユーザープロフィール表示もactive対象だけには限定されていない |

主な関連コードは`src/app/auth/actions.ts`、`src/app/auth/callback/route.ts`、`src/lib/supabase/server.ts`、`src/lib/supabase/proxy.ts`である。主な関連テストは`0001_core_rls.test.sql`、`0004_user_search_and_follows.test.sql`、`0006_user_profile_posts_rls.test.sql`、`0007_follow_lists_rls.test.sql`である。

### 4.2 プロフィール

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| 自分のプロフィール表示・編集 | 実装済み | `/profile`、`/profile/edit`。username、bio、投稿数、フォロー数、フォロワー数と編集導線を表示 | なし |
| 他ユーザープロフィール | 実装済み | `/users/[userId]`。UUID検証、本人UUIDの`/profile`正規化、follow操作、閲覧可能な最新20投稿を表示 | 続きを読むページングは別項目 |
| follow/follower件数と一覧導線 | 実装済み | 自分・他者それぞれのfollowing/followers route、安定順、最新20件、follow操作 | 続きを読むページングは未実装 |
| avatar | 一部実装済み | `profiles.avatar_path`と長さ制約、更新権限は存在 | upload、Storage policy、表示・編集UIはなく、現在はユーザー名の頭文字を表示 |
| suspendedプロフィールの扱い | 一部実装済み | search、post、follow一覧はsuspended関係を除外する | `profiles` SELECTは全authenticatedに許可され、`/users/[userId]`は対象accountのactive確認をしていない |
| 興味タグ・推し一覧 | MVP後 | 正式仕様のPhase 3、Phase 4以降 | 対応table・route・UIなし |

関連コードは`src/lib/profile-data.ts`、`src/lib/follow-data.ts`、`src/components/profile/**`である。関連migrationはコアschemaと`20260801000100_secure_follow_lists.sql`、関連テストは`0001`、`0004`、`0006`、`0007`である。

### 4.3 日記投稿、画像、気分、タグ、場所、公開範囲

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| 作成・詳細・編集・soft delete | 実装済み | `/posts/new`、`/posts/[postId]`、`/posts/[postId]/edit`、`/profile/posts`。本人IDをsessionから取得し、soft-delete RPCを使用 | なし |
| title・body・入力検証 | 実装済み | titleは任意120文字、bodyは1〜10,000文字。ClientとServer Action、DB CHECKで検証 | なし |
| 気分 | 実装済み | 6種類と未設定を作成・編集・一覧・詳細で扱う。DB CHECKあり | なし |
| 公開範囲 | 実装済み | `private`、`followers`、`public`。作成・編集可能で、RLSが閲覧を制御 | 未認証public閲覧は対象外の運用 |
| 画像 | 未実装 | `post_images` table、Storage、upload、preview、並び順、画像表示なし | 最大10枚、形式・容量検証、非公開画像の認可が必要 |
| 自由タグ | 未実装 | `tags`、`post_tags` table、入力・表示・検索routeなし | MVP検索とタグ画面を含めて実装する |
| 場所名 | 一部実装済み | `posts.location_name`、100文字CHECK、authenticatedのinsert/update権限は存在 | form、Server Actionの入力・保存、表示がない |
| カテゴリー・推し・ぬい・イベント・アルバム関連 | MVP後 | 正式仕様でPhase 3以降 | MVP完了条件には含めない |

投稿の関連コードは`src/app/(protected)/posts/actions.ts`、`src/lib/post-data.ts`、`src/components/posts/**`である。`0001_core_rls.test.sql`、`0005_post_edit_rls.test.sql`、`0006_user_profile_posts_rls.test.sql`が主要なDB回帰を担う。

### 4.4 タイムライン

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| timeline共通表示・feed分離 | 実装済み | `/home?feed=following`と`/home?feed=latest`をリンク型navigationで切り替え、選択中リンクへ`aria-current="page"`を付与。投稿者、日時、気分、title、body、reaction、comment件数、詳細導線を共通利用 | body省略、画像、タグ、継続取得がない |
| フォロー中timeline | 実装済み | queryなし・空・未知・複数値を含む既定feed。`follows`からfollow先を取得し、自分＋follow先のauthorへ絞ったうえでRLSがprivate、suspended、soft delete等を最終除外 | 最大50件固定。大量follow時の`.in(...)`は実データで評価が必要 |
| 最新投稿timeline | 実装済み | `feed=latest`で`visibility = public`を明示し、RLS上閲覧可能な全active投稿者のpublic投稿を新着順に表示 | 最大50件固定 |
| pagination / infinite scroll | 未実装 | homeは50件固定、profile投稿とfollow一覧は20件固定で案内文のみ | cursor等による安定した継続取得が必要 |

RLSは権限のない投稿、soft-deleted投稿、suspended投稿者の投稿をDB取得結果から除外する。`getTimelinePosts`は`created_at DESC, id DESC`、最大50件を共通条件とし、作者プロフィール、reaction、comment件数をbatch取得して投稿単位のN+1を避けている。各feedには固有の説明文と空状態がある。

### 4.5 リアクション

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| 3種類・追加・解除・変更・件数 | 実装済み | `empathy`、`support`、`relatable`。1投稿1ユーザー1件のUNIQUE、toggle Server Action、種類別・合計件数を表示 | 自分の投稿へのreactionは現在許可されている |
| reaction通知 | 未実装 | `notifications` tableと通知作成処理なし | 自己通知を除外する通知基盤が必要 |

関連migrationは`20260726000100_create_reactions.sql`、関連テストは`0002_reactions_rls.test.sql`とvisibility変更を扱う`0005_post_edit_rls.test.sql`である。

### 4.6 コメント

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| 投稿・表示・本人soft delete・件数 | 実装済み | 投稿詳細で最大100件を古い順に表示。1〜1,000文字、閲覧可能投稿だけに作成可能。本人専用RPCでsoft delete | 投稿者による他者comment削除方針は未決定 |
| 返信 | 未実装 | `parent_comment_id` column、返信UI・actionなし | 1階層返信と削除済み親の表示方針が必要 |
| 通知 | 未実装 | comment・reply通知なし | 自己通知除外と削除済み対象への安全な遷移が必要 |
| コメント通報 | MVP後 | 正式仕様のPhase 2で通報を整備 | `reports` tableとUIなし |
| コメント編集 | MVP後 | 正式仕様でMVP対象外でもよい | update UI・policyなし |

関連migrationは`20260726000200_create_comments.sql`から`20260726000400_fix_post_visibility_helper.sql`、関連テストは`0003_comments_rls.test.sql`である。

### 4.7 フォロー

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| follow・解除・自己/重複拒否 | 実装済み | Server ActionとRLS、複合PK、CHECKで実装。active targetだけfollow可能 | なし |
| following / followers一覧 | 実装済み | 自分・他者の4 route、最新順、20件、一覧内follow操作、suspended関係の除外 | paginationは未実装 |
| follow通知 | 未実装 | notification処理なし | 通知基盤と自己通知除外が必要 |
| 非公開account・承認制 | MVP後 | MVP対象外 | 将来拡張時にdata modelとRLSを再設計する |

関連migrationはコアschema、`20260726000500_secure_user_search_and_follows.sql`、`20260801000100_secure_follow_lists.sql`、関連テストは`0004`と`0007`である。

### 4.8 検索

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| ユーザー名検索 | 実装済み | `/search`とhardened RPC。1〜50文字、前後空白除去、case-insensitive部分一致、`%`・`_`をliteral扱い、activeユーザー、最大20件 | paginationなし |
| タグ検索 | 未実装 | tag data modelとrouteなし | 自由タグ実装が前提 |
| 投稿title・body検索 | 未実装 | query、RPC、route、UIなし | RLSで閲覧可能投稿だけに限定する |
| 検索category切替・paging | 未実装 | 現在はユーザー検索のみ | 空検索、categoryごとの安定順と継続取得を整備する |

関連コードは`src/app/(protected)/search/page.tsx`、`src/lib/user-search-data.ts`、関連migrationとテストは`20260726000500_secure_user_search_and_follows.sql`と`0004_user_search_and_follows.test.sql`である。

### 4.9 その他のMVP・Phase 2機能

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| カレンダー | 未実装 | route、component、日付別queryなし | timezone、同日複数投稿、気分表示を設計する |
| 通知 | 未実装 | table、route、actionなし | follow、reaction、comment、replyの通知と既読管理が必要 |
| 設定 | 未実装 | `/settings`相当のrouteなし | timezone等の設定UIを定義する |
| レスポンシブ | 一部実装済み | mobile-first class、`min-w-0`、`break-words`、`overflow-wrap:anywhere`、幅制限を主要画面に使用 | repository内にviewport別の自動テストはない。画像UI等の未実装画面は未評価 |
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
| `posts` | 一部実装済み | `id`、`user_id`、`title`、`body`、`mood`、`location_name`、`visibility`、`created_at`、`updated_at`、`deleted_at` | Auth userへのcascade FK、入力値CHECK、user/newestとpublic/newestのpartial index、本人mutation、可視性RLS。画像・タグ等の関連tableは未作成 |
| `follows` | 実装済み | `follower_id`、`following_id`、`created_at` | 両userへのcascade FK、複合PK、self-follow CHECK、active関係だけのSELECT、following/follower安定順index |
| `reactions` | 実装済み | `id`、`post_id`、`user_id`、`reaction_type`、`created_at`、`updated_at` | post/accountへのcascade FK、3種類CHECK、投稿×ユーザーUNIQUE、post/type index、可視post連動RLS |
| `comments` | 一部実装済み | `id`、`post_id`、`user_id`、`body`、`created_at`、`updated_at`、`deleted_at` | post/accountへのcascade FK、body/deleted_at CHECK、未削除post/newest partial index、可視post連動RLS、soft-delete RPC。返信用columnは未作成 |

Postgres enumは使用せず、`role`、`status`、`mood`、`visibility`、`reaction_type`をtextとCHECK制約で管理している。主要FKはuser削除またはpost削除に対するcascadeを設定している。物理DELETEは一般ユーザーへ付与せず、postとcommentは専用RPCでsoft deleteする。

### 5.2 RLS、function、trigger、ACL

- 6つのpublic tableすべてでRLSを明示的に有効化している。
- 現在のpolicyは合計16件で、accounts 2、profiles 2、posts 3、follows 3、reactions 4、comments 2である。
- `posts` SELECTは本人、active viewer、active author、follow関係、visibility、`deleted_at`をDB側で評価する。
- reactionsとcommentsは、参照先postを現在のviewerが閲覧できる場合だけSELECT・mutationできる。
- `my_diary_is_account_active`と`my_diary_can_view_post`をprivate schemaへ置き、再帰的RLSを避けている。
- `my_diary_soft_delete_post`、`my_diary_soft_delete_comment`は本人とactive状態を再検証する。
- `my_diary_search_profiles`はauthenticated identity、入力長、literal wildcard、active対象、20件上限を関数内で検証する。
- `SECURITY DEFINER`関数はownerを`postgres`へ固定し、空の`search_path`または`pg_catalog`固定を使用する。
- table・column・functionの権限は既定権限をREVOKEして必要なauthenticated権限だけをGRANTする。
- `rls_auto_enable()`はevent trigger `ensure_rls`からpublic schemaの新規table、partitioned table、CTAS、SELECT INTOへRLSを有効化する。policyやFORCE RLSは作成しない。
- `rls_auto_enable()`のEXECUTEは`PUBLIC`、`anon`、`authenticated`、`service_role`、`authenticator`からREVOKEされ、`postgres`だけに残る。

通常triggerは、5 tableの`updated_at`更新とAuth user作成時のaccount/profile作成に使用する。別にevent trigger `ensure_rls`が存在する。

### 5.3 未作成の主要table

MVP対象で未作成なのは`post_images`、`tags`、`post_tags`、`notifications`である。Phase 2の`reports`、Phase 3以降のcategories、favorites、communities、plushies、events、albumsと各紐付けtableも未作成である。

## 6. MVP後の機能

| 項目 | 状態 | 現在の基盤・補足 |
| --- | --- | --- |
| 正式カテゴリー・興味タグ | MVP後 | `posts`に`category_id`はなく、カテゴリーtableもない。自由タグMVPも未実装 |
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
| `/posts/new` | page | 日記作成 |
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
| `/search` | page | username検索 |
| `/api/health/supabase` | route handler | Supabase Auth healthの安全な状態応答 |

`not-found.tsx`はpost詳細とprofile系に存在する。専用のprotected layout、`loading.tsx`、`error.tsx`は存在せず、各pageが認証redirectとerror UIを担当している。

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

既存migrationは上記8件で、最新は`20260801000200_manage_rls_auto_enable.sql`である。既存migrationの変更はこの調査では行っていない。

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
| 合計 | 267 | 8ファイル |

### 9.2 実行結果の区別

- 直前作業までの確認済み結果として、全pgTAP `267 / 267`、最新追加分`29 / 29`、`npm run lint`、`npm run typecheck`、`npm run build`成功が作業依頼に記録されている。
- Phase A1では`npm run lint`、`npm run typecheck`、`npm run build`、`git diff --check`を再実行し、すべて成功した。migrationは8件のまま、`supabase/migrations`、`package.json`、`package-lock.json`に差分がないことも確認した。
- Phase A1では全pgTAP `267 / 267`が成功した。今回の文書記録更新では、直前の全件成功を根拠としてpgTAPを再実行していない。
- 認証済みブラウザ検証では、following / latestの表示行列、URL直接アクセス、不正・空・複数feed値、リンク切り替え、再読み込み、戻る・進む、`aria-current`、空状態、動的反映を確認した。320 / 360 / 375 / 390 / 1280pxで横スクロールがなく、長文・改行・連続半角文字列の表示も正常であり、console error / warning、React warning、hydration errorはなかった。ユーザーによる最終手動確認も問題なかった。
- repository内にunit、component、browser E2Eの自動test fileは確認できない。

## 10. 既知の制限・技術的負債

1. `rls_auto_enable()`はRLS有効化失敗をlogへ記録して元DDLを成功させるfail-openである。policyも自動作成しないため、各migrationで明示的なRLSとpolicyが引き続き必須である。
2. event triggerとfunction ACLは一般的なschema diffだけでは完全に検出できないため、migrationのpreflight/postconditionとpgTAPを維持する必要がある。
3. suspended accountはRLSでmutationと他者投稿・follow関係を制限するが、Supabase Authへのlogin自体は拒否していない。
4. `profiles` SELECT policyはauthenticated全体に許可され、直接の他ユーザープロフィールrouteは対象accountのactive状態を検証していない。
5. timelineは最大50件、他者投稿とfollow一覧は最新20件、comment一覧は古い順100件で打ち切り、継続取得を実装していない。
6. timelineはフォロー中と最新投稿に分離済みだが、一覧本文を省略しない。フォロー中feedのauthor filterは`.in(...)`を使用するため、大量follow時のURL長・query性能を実データで評価する必要がある。
7. avatar_pathとlocation_nameはDB基盤だけで、UIから利用できない。
8. comment返信用`parent_comment_id`がなく、通知・通報を含む関連tableも未作成である。
9. unit、component、E2E、accessibility、viewport別responsiveの自動回帰がない。
10. profile件数、timeline補助data、comment件数は複数queryを使う。投稿単位のN+1は避けているが、規模拡大時はRPC、view、集計方式を再評価する必要がある。
11. root-level `loading.tsx`、`error.tsx`、protected layoutがなく、認証・error handlingがpageごとに重複している。

## 11. 次Phase候補

次の候補は確定順ではない。正式仕様のMVP完了条件と、現在の実装差分から選定した。

### 候補A: timelineの継続取得と長文省略

- 目的: 分離済みの2種類のtimelineへ安定した継続取得を追加し、一覧の長文を読みやすくする。
- 現在の不足: `/home`は各feed最大50件固定で、cursor pagination、無限スクロール、長文省略がない。
- 前提: 現行post visibility RLSとfollow RLSを維持する。
- 主な影響範囲: `src/app/(protected)/home`、`src/lib/post-data.ts`、投稿card、必要な回帰テスト。
- 推奨理由: 正式仕様の性能要件と一覧可読性を満たし、現在の最大50件固定を解消できる。

### 候補B: 自由タグとタグ検索

- 目的: 日記への複数タグ付与、タグ一覧・詳細、タグ検索を実装する。
- 現在の不足: `tags`、`post_tags`、UI、検索がすべて未実装。
- 前提: normalized name、重複防止、visibilityを守る検索RLSを先に設計する。
- 主な影響範囲: 新規migration、post form/action、tag route、検索、pgTAP。
- 推奨理由: MVP完了条件のタグ導線と検索差分を同じ基盤で前進できる。

### 候補C: 画像投稿とavatarの共通Storage基盤

- 目的: 最大10枚のpost画像とavatarを安全に扱う。
- 現在の不足: Storage bucket、post_images、upload、preview、並び順、署名URL、削除方針がない。
- 前提: private/followers画像のRLS・Storage policy、形式・容量制限、orphan cleanupを設計する。
- 主な影響範囲: migration、Storage policy、post/profile form、表示component、検証。
- 推奨理由: MVP最大の未実装領域であり、将来の推し・ぬい・イベント画像基盤にもつながる。

### 候補D: コメント返信と通知基盤

- 目的: 1階層返信とfollow/reaction/comment/reply通知を提供する。
- 現在の不足: parent_comment_id、notifications、返信UI、既読管理、自己通知除外がない。
- 前提: 通知targetの削除・soft delete時の扱い、recipientだけが読めるRLSを決める。
- 主な影響範囲: migration、comment action/UI、通知route、各mutation action、pgTAP。
- 推奨理由: 現在の交流機能をMVP仕様までつなげられる。ただし安全な通知data modelを小Phaseへ分割するべきである。

### 候補E: カレンダーと場所名

- 目的: 自分の日記を日付で振り返り、任意の場所名を記録できるようにする。
- 現在の不足: calendar route/query、timezone境界、location form/action/displayがない。
- 前提: `accounts.timezone`の設定方法と日付境界を先に確定する。
- 主な影響範囲: calendar route、post form/action、post display、query/test。
- 推奨理由: 既存`posts.location_name`と`accounts.timezone`を活用でき、比較的小さな単位に分割しやすい。

## 12. 更新履歴

| 日付 | HEAD | 内容 |
| --- | --- | --- |
| 2026-08-02 | `072c73ef460869105051134c3addd1901df3a11b` | Phase A1としてフォロー中・最新投稿timelineとリンク型feed分離を実装。最大50件固定、pagination・無限scroll・長文省略は未実装として維持 |
| 2026-08-02 | `4c7ff37de13b035decb791f91f05adb4038c88b3` | Ver.2.0、repository、8 migration、8 pgTAPに基づき初回作成 |
