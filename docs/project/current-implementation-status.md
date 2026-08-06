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
- 調査基準日: 2026-08-06
- 調査時branch: `main`
- 作業開始時HEAD: `1b73043e6262aa410c4f7d593fb36ae9c612ee52`
- 作業開始時HEADのmessage: `feat: add tag browsing pages`

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
| 実装済み | 20 |
| 一部実装済み | 8 |
| 未実装 | 13 |
| MVP後 | 17 |
| 確認不能 | 0 |
| 合計 | 58 |

現在は、メールアドレスとパスワードによる認証、プロフィールの表示・編集、日記の作成・詳細・編集・soft delete、6種類の気分、自由タグの入力・保存・投稿上のリンク表示・タグ一覧・タグ詳細・部分一致検索、3段階の公開範囲、フォロー中・最新投稿の2種類のタイムライン、3種類のリアクション、コメントの投稿・表示・soft delete、フォロー・解除・一覧、ユーザー名検索まで実装されている。

DB側では、`accounts`、`profiles`、`posts`、`follows`、`reactions`、`comments`、`tags`、`post_tags`の8 tableと、公開範囲・active状態を守るRLS、権限を限定した関数、RLS自動有効化の安全網がmigration管理されている。自由タグはNFKCによるcanonical name、SELECT専用RLS、投稿とタグを同一transactionで作成・更新するatomic RPC、一般アプリ経路での1投稿最大5個保証に加え、チップ入力、作成・編集、投稿上のUUIDリンク、閲覧可能タグの一覧・詳細・部分一致検索まで実装済みである。タグ一覧は50件、タグ詳細と検索は20件のforward cursor paginationを使用する。pgTAPは11ファイル、plan合計476 assertionで、認証後の権限境界、soft delete、visibility変更、suspended状態、follow一覧、タグ名漏えい防止、ユーザー・タグ検索、atomic mutationとrollback、RLS自動有効化とACLを対象としている。

MVP完了条件との差分は、画像、場所入力UI、タイムラインのページネーション、コメント返信、通知、投稿検索、カレンダー、設定である。パスワードリセットとOAuth、avatarも未完成である。MVP後のカテゴリー、推し活、コミュニティ、ぬい活、イベント、アルバム、おすすめ、AI、プレミアムは未着手であり、現時点のMVP欠陥としては扱わない。

## 3. 技術・リポジトリ状態

| 項目 | 現在の状態 | 根拠 |
| --- | --- | --- |
| framework | Next.js 16.2.11、App Router | `package.json`、`src/app/**` |
| language | TypeScript 5、React 19.2.4 | `package.json`、`tsconfig.json` |
| styling | Tailwind CSS 4、mobile-firstのutility class | `package.json`、`src/app/globals.css`、各component |
| backend | Supabase Auth、Postgres、RLS、Supabase SSR | `@supabase/ssr`、`@supabase/supabase-js`、migration |
| 認証方式 | email/password、SSR cookie session、認証callback | `src/app/auth/actions.ts`、`src/app/auth/callback/route.ts`、`src/proxy.ts` |
| migration | 11ファイル | `supabase/migrations/*.sql` |
| DB table | 8 table | `accounts`、`profiles`、`posts`、`follows`、`reactions`、`comments`、`tags`、`post_tags` |
| pgTAP | 11ファイル、plan合計476 | `supabase/tests/database/*.sql` |
| その他の自動テスト | repository内では未確認 | unit、component、E2Eのtest fileは存在しない |
| npm検証 | `lint`、`typecheck`、`build` | `package.json` |
| 最新commit | `1b73043e6262aa410c4f7d593fb36ae9c612ee52` | `feat: add tag browsing pages`。Phase B2b-3aはcommit前 |

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
| 作成・詳細・編集・soft delete | 実装済み | `/posts/new`、`/posts/[postId]`、`/posts/[postId]/edit`、`/profile/posts`。作成・編集はatomic post/tag RPC、削除はsoft-delete RPCを使用 | なし |
| title・body・入力検証 | 実装済み | titleは任意120文字、bodyは1〜10,000文字。ClientとServer Action、DB CHECKで検証 | なし |
| 気分 | 実装済み | 6種類と未設定を作成・編集・一覧・詳細で扱う。DB CHECKあり | なし |
| 公開範囲 | 実装済み | `private`、`followers`、`public`。作成・編集可能で、RLSが閲覧を制御 | 未認証public閲覧は対象外の運用 |
| 画像 | 未実装 | `post_images` table、Storage、upload、preview、並び順、画像表示なし | 最大10枚、形式・容量検証、非公開画像の認可が必要 |
| 自由タグ | 実装済み | `tags`、`post_tags`、NFKC canonical name、文字数・文字種制約、重複防止、可視post連動SELECT RLS、atomic作成・差分更新RPC、一般アプリ経路の最大5個保証を実装。作成・編集のチップ入力、投稿詳細・following・latest・自他プロフィール投稿一覧のUUIDリンク、`/tags`、`/tags/[tagId]`、部分一致検索、forward cursor paginationまで接続済み。直接mutation権限なし | なし |
| 場所名 | 一部実装済み | `posts.location_name`と100文字CHECKは存在。Phase B2a RPCには含めず、作成時NULL・更新時既存値維持 | form、Server Actionの入力・保存、表示がない |
| カテゴリー・推し・ぬい・イベント・アルバム関連 | MVP後 | 正式仕様でPhase 3以降 | MVP完了条件には含めない |

投稿の関連コードは`src/app/(protected)/posts/actions.ts`、`src/lib/post-data.ts`、`src/lib/tag-data.ts`、`src/components/posts/**`である。`0001_core_rls.test.sql`、`0005_post_edit_rls.test.sql`、`0006_user_profile_posts_rls.test.sql`、`0009_tags_rls.test.sql`、`0010_post_tag_mutation_rpc.test.sql`が主要なDB回帰を担う。

### 4.4 タイムライン

| 項目 | 状態 | 実装概要・根拠 | 残課題 |
| --- | --- | --- | --- |
| timeline共通表示・feed分離 | 実装済み | `/home?feed=following`と`/home?feed=latest`をリンク型navigationで切り替え、選択中リンクへ`aria-current="page"`を付与。投稿者、日時、気分、title、body、タグ、reaction、comment件数、詳細導線を共通利用 | body省略、画像、継続取得がない |
| フォロー中timeline | 実装済み | queryなし・空・未知・複数値を含む既定feed。`follows`からfollow先を取得し、自分＋follow先のauthorへ絞ったうえでRLSがprivate、suspended、soft delete等を最終除外 | 最大50件固定。大量follow時の`.in(...)`は実データで評価が必要 |
| 最新投稿timeline | 実装済み | `feed=latest`で`visibility = public`を明示し、RLS上閲覧可能な全active投稿者のpublic投稿を新着順に表示 | 最大50件固定 |
| pagination / infinite scroll | 未実装 | homeは50件固定、profile投稿とfollow一覧は20件固定で案内文のみ | cursor等による安定した継続取得が必要 |

RLSは権限のない投稿、soft-deleted投稿、suspended投稿者の投稿をDB取得結果から除外する。`getTimelinePosts`は`created_at DESC, id DESC`、最大50件を共通条件とし、タグはposts queryのnested select、作者プロフィール、reaction、comment件数はbatch取得として投稿単位のN+1を避けている。タグrelationの取得・shape検証に失敗した場合はタグ0件へ丸めず投稿取得エラーとする。各feedには固有の説明文と空状態がある。

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
| ユーザー名検索 | 実装済み | `/search?category=users`とhardened RPC。NFKC、1〜50 codepoint、前後空白除去、case-insensitive部分一致、`\\`・`%`・`_`をliteral扱い、activeユーザー、最大20件 | paginationなし |
| タグ検索 | 実装済み | `/search?category=tags`。入力をtag規則でNFKC canonical化し、`\\`・`%`・`_`をliteral扱い、RLS上閲覧可能なタグだけを`normalized_name`順に20件ずつ表示 | 大量データ時の部分一致性能は別途評価が必要 |
| 投稿title・body検索 | 未実装 | query、RPC、route、UIなし | RLSで閲覧可能投稿だけに限定する |
| 検索category切替・paging | 一部実装済み | users / tagsをリンク型navigationで切り替え、queryを維持してcursorを破棄する。タグはquery紐付きのopaque forward cursorを使用 | posts categoryと投稿検索pagingは未実装 |

関連コードは`src/app/(protected)/search/page.tsx`、`src/components/search/**`、`src/lib/search-query.ts`、`src/lib/search-cursor.ts`、`src/lib/user-search-data.ts`、`src/lib/tag-search-data.ts`である。関連migrationとテストは`20260726000500_secure_user_search_and_follows.sql`、`20260804000100_extend_user_and_tag_search.sql`、`0004_user_search_and_follows.test.sql`、`0011_user_and_tag_search.test.sql`である。

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
| `posts` | 一部実装済み | `id`、`user_id`、`title`、`body`、`mood`、`location_name`、`visibility`、`created_at`、`updated_at`、`deleted_at` | Auth userへのcascade FK、入力値CHECK、partial index、可視性RLS。authenticatedの直接INSERT/UPDATEを閉じ、atomic post/tag RPCだけを一般作成・更新経路とする。画像関連tableは未作成 |
| `follows` | 実装済み | `follower_id`、`following_id`、`created_at` | 両userへのcascade FK、複合PK、self-follow CHECK、active関係だけのSELECT、following/follower安定順index |
| `reactions` | 実装済み | `id`、`post_id`、`user_id`、`reaction_type`、`created_at`、`updated_at` | post/accountへのcascade FK、3種類CHECK、投稿×ユーザーUNIQUE、post/type index、可視post連動RLS |
| `comments` | 一部実装済み | `id`、`post_id`、`user_id`、`body`、`created_at`、`updated_at`、`deleted_at` | post/accountへのcascade FK、body/deleted_at CHECK、未削除post/newest partial index、可視post連動RLS、soft-delete RPC。返信用columnは未作成 |
| `tags` | 実装済み | `id`、`name`、`normalized_name`、`created_at` | NFKC canonical name、30 codepoint上限、文字種制約、UNIQUE、可視post連動SELECT。master mutationはatomic RPC内部だけで、入力・投稿表示・一覧・詳細・検索UIを実装済み |
| `post_tags` | 一部実装済み | `post_id`、`tag_id`、`created_at` | 複合PK、cascade FK、逆引きindex、可視post連動SELECT RLS。RPC内の最大5個検証、post row lock、差分更新を実装 |

Postgres enumは使用せず、`role`、`status`、`mood`、`visibility`、`reaction_type`をtextとCHECK制約で管理している。主要FKはuser削除またはpost削除に対するcascadeを設定している。物理DELETEは一般ユーザーへ付与せず、postとcommentは専用RPCでsoft deleteする。

### 5.2 RLS、function、trigger、ACL

- 8つのpublic tableすべてでRLSを明示的に有効化している。
- 現在のpolicyは合計18件で、accounts 2、profiles 2、posts 3、follows 3、reactions 4、comments 2、tags 1、post_tags 1である。
- `posts` SELECTは本人、active viewer、active author、follow関係、visibility、`deleted_at`をDB側で評価する。
- reactionsとcommentsは、参照先postを現在のviewerが閲覧できる場合だけSELECT・mutationできる。
- post_tagsは可視postだけをSELECTでき、tagsは可視なpost_tagsが存在する場合だけSELECTできる。tags → post_tags → postsの一方向評価とし、private・権限外followers・soft-delete済みpostだけに紐づくtag名を隠す。
- `my_diary_is_account_active`と`my_diary_can_view_post`をprivate schemaへ置き、再帰的RLSを避けている。
- `my_diary_normalize_tag_name`をprivate schemaへ置き、NFKC、前後空白、先頭`#`、連続空白、ASCII caseを決定的にcanonical化する。一般application roleにはEXECUTEを付与しない。
- `my_diary_soft_delete_post`、`my_diary_soft_delete_comment`は本人とactive状態を再検証する。
- `my_diary_create_post_with_tags`と`my_diary_update_post_with_tags`は投稿本体とtag relationを同一transactionで処理し、後者はpost row lockと差分更新を使用する。
- `my_diary_search_profiles`はauthenticated identity、NFKC、入力長、literal wildcard、active対象、20件上限を関数内で検証する。
- `my_diary_search_tags`は`SECURITY INVOKER`で既存tags RLSを通し、authenticated identity、NFKC canonical query、literal wildcard、cursor、21件取得を検証する。21件目はUIの次ページ判定だけに使用する。
- `SECURITY DEFINER`関数はownerを`postgres`へ固定し、空の`search_path`または`pg_catalog`固定を使用する。
- table・column・functionの権限は既定権限をREVOKEして必要なauthenticated権限だけをGRANTする。
- `rls_auto_enable()`はevent trigger `ensure_rls`からpublic schemaの新規table、partitioned table、CTAS、SELECT INTOへRLSを有効化する。policyやFORCE RLSは作成しない。
- `rls_auto_enable()`のEXECUTEは`PUBLIC`、`anon`、`authenticated`、`service_role`、`authenticator`からREVOKEされ、`postgres`だけに残る。

通常triggerは、5 tableの`updated_at`更新とAuth user作成時のaccount/profile作成に使用する。別にevent trigger `ensure_rls`が存在する。

### 5.3 未作成の主要table

MVP対象で未作成なのは`post_images`と`notifications`である。`tags`と`post_tags`はDB読み取り・mutation基盤、利用者向け入力・投稿リンク、タグ一覧・詳細・検索まで作成済みである。Phase 2の`reports`、Phase 3以降のcategories、favorites、communities、plushies、events、albumsと各紐付けtableも未作成である。

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
| `/tags` | page | RLS上閲覧可能なタグをcanonical名順に50件ずつ表示 |
| `/tags/[tagId]` | dynamic page | UUIDで識別したタグと、RLS上閲覧可能な投稿を20件ずつ表示 |
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
| `/search` | page | users / tags category切替、NFKC canonical query、ユーザー・タグ部分一致検索、タグcursor pagination |
| `/api/health/supabase` | route handler | Supabase Auth healthの安全な状態応答 |

`not-found.tsx`はpost詳細、profile系、tag詳細に存在する。タグrouteには共通`loading.tsx`がある。専用のprotected layoutと`error.tsx`は存在せず、各pageが認証redirectとerror UIを担当している。

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

Phase B2b-3aでは既存10 migrationを変更せず、`20260804000100_extend_user_and_tag_search.sql`を1件追加した。ローカルresetで11件すべてをfresh適用した後、この1件だけをリンク済みのリモート開発DBへ通常適用した。local / remote履歴は11件で一致し、適用後の再dry-runはup to date、pg-deltaによる`public,my_diary_private`のlinked schema diffは空だった。migration transaction内のpostconditionと空のcatalog diffを組み合わせ、両検索RPCとprivate helperのsignature、引数名、return shape、owner、volatility、security属性、固定search path、ACL、および既存tags RLS・policy・table ACLの維持を確認した。適用後のcatalog cache生成では一時CA証明書を参照できない補助warningが発生したが、migration適用は終了コード0で完了し、remote履歴と再dry-runで成功を確認したため再適用していない。リモートfixture・ユーザーデータ操作・Service Roleは使用せず、Git stage・commit・pushも実施していない。

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
| 合計 | 476 | 11ファイル |

### 9.2 実行結果の区別

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
3. suspended accountはRLSでmutationと他者投稿・follow関係を制限するが、Supabase Authへのlogin自体は拒否していない。
4. `profiles` SELECT policyはauthenticated全体に許可され、直接の他ユーザープロフィールrouteは対象accountのactive状態を検証していない。
5. timelineは最大50件、他者投稿とfollow一覧は最新20件、comment一覧は古い順100件で打ち切り、継続取得を実装していない。
6. timelineはフォロー中と最新投稿に分離済みだが、一覧本文を省略しない。フォロー中feedのauthor filterは`.in(...)`を使用するため、大量follow時のURL長・query性能を実データで評価する必要がある。
7. avatar_pathとlocation_nameはDB基盤だけで、UIから利用できない。
8. comment返信用`parent_comment_id`がなく、通知・通報を含む関連tableも未作成である。
9. unit、component、E2E、accessibility、viewport別responsiveの自動回帰がない。
10. profile件数、timeline補助data、comment件数は複数queryを使う。投稿単位のN+1は避けているが、規模拡大時はRPC、view、集計方式を再評価する必要がある。
11. root-level `loading.tsx`、`error.tsx`、protected layoutがなく、認証・error handlingがpageごとに重複している。
12. 自由タグは入力・投稿リンク・一覧・詳細・検索まで実装済みである。入力順を保存するcolumnはなく、投稿上はcode point順、タグ一覧・検索はDBの`normalized_name`順で表示する。検索の部分一致は現時点で専用indexを追加せず、RLS適用後のscan性能は大規模データで再評価が必要である。最大5個はauthenticatedのRPC経路で保証し、特権roleの直接SQLを禁止するconstraint triggerは置いていない。認証済みブラウザ回帰は完了したが、同一`created_at`の実データ、suspended author、瞬間的loading、実キーボードによるTab / Enterは未確認である。

## 11. 次Phase候補

次の候補は確定順ではない。正式仕様のMVP完了条件と、現在の実装差分から選定した。

### 候補A: timelineの継続取得と長文省略

- 目的: 分離済みの2種類のtimelineへ安定した継続取得を追加し、一覧の長文を読みやすくする。
- 現在の不足: `/home`は各feed最大50件固定で、cursor pagination、無限スクロール、長文省略がない。
- 前提: 現行post visibility RLSとfollow RLSを維持する。
- 主な影響範囲: `src/app/(protected)/home`、`src/lib/post-data.ts`、投稿card、必要な回帰テスト。
- 推奨理由: 正式仕様の性能要件と一覧可読性を満たし、現在の最大50件固定を解消できる。

### 候補B: 投稿検索（Phase B2b-3b）

- 目的: viewerが閲覧できる投稿だけをtitle・bodyから安全に検索できるようにする。
- 現在の不足: users / tagsの検索基盤とcategory切替は実装済みだが、posts category、投稿検索query、安定したpaginationがない。
- 前提: 既存posts SELECT RLSを最終認可とし、private・権限外followers・soft delete・suspended投稿を結果へ混入させない。
- 主な影響範囲: `/search`、post検索data queryまたはRPC、検索結果card、cursor、必要な回帰テスト。
- 推奨理由: 今回の検索UI基盤を再利用して、残る検索MVP差分を独立した小Phaseで実装できる。

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
| 2026-08-06 | commit前。基準HEAD `1b73043e6262aa410c4f7d593fb36ae9c612ee52` | Phase B2b-3aの`20260804000100`だけをリモート開発DBへ通常適用。local / remote履歴11件一致、再dry-runはup to date、remote catalog属性・ACL・tags RLS前提の一致、`public,my_diary_private`のlinked schema diffが空であることを確認。適用後のcatalog cache生成warningはSQL成功と切り分け、リモートfixture・ユーザーデータ操作、Git stage・commit・pushは未実施 |
| 2026-08-04 | commit前。基準HEAD `1b73043e6262aa410c4f7d593fb36ae9c612ee52` | Phase B2b-3aとしてusers / tags検索UI基盤、ユーザー検索NFKC対応、RLSを通すタグ部分一致検索、20件forward cursor pagination、厳格なquery/cursor検証を実装。新migration・pgTAPを各1件追加し、ローカルreset後に全pgTAP 476件、npm検証、認証済みブラウザ・レスポンシブ検証を完了。リモートDB操作、既存migration/test変更、Git stage・commit・pushは未実施 |
| 2026-08-03 | commit前。基準HEAD `37b055ea9b18c19ec04fb040e3851ff579534938` | Phase B2b-2としてRLS上閲覧可能なタグ一覧・タグ詳細、UUID canonical route、50件・20件のforward cursor pagination、投稿タグのUUIDリンク、home導線、404・空状態・loadingを実装。通常のauthenticated経路だけで認証済みブラウザ、PostgREST実response、RLS、responsiveを検証し、fixtureをローカルDB resetで清掃後に全pgTAP 406件とnpm検証を完了。DB・migration・pgTAP定義は変更なし |
| 2026-08-02 | commit前。基準HEAD `756a32e341c9a84de2e3106c82f534335445087d` | Phase B2b-1としてタグのチップ入力、Server Action validationと実配列送信、nested select、投稿詳細・timeline・自他投稿一覧の非リンク表示を実装。全pgTAP 406件とnpm検証、認証済みブラウザ・レスポンシブ検証を完了。タグ一覧・詳細・検索は未実装として維持 |
| 2026-08-02 | 作業開始時 `9bdd08682cfa963bb9e4da531849f195c8772531` | Phase B2aとしてatomic post/tag作成・更新RPC、最大5個保証、posts直接mutation閉鎖、Server Action移行、pgTAPを追加。UI・route・検索は未実装として維持 |
| 2026-08-02 | `9bdd08682cfa963bb9e4da531849f195c8772531` | Phase B1として自由タグDB読み取り基盤、NFKC canonical制約、可視post連動SELECT RLS、pgTAPを追加。mutation・最大5個保証・UI・route・検索は未実装として維持 |
| 2026-08-02 | `072c73ef460869105051134c3addd1901df3a11b` | Phase A1としてフォロー中・最新投稿timelineとリンク型feed分離を実装。最大50件固定、pagination・無限scroll・長文省略は未実装として維持 |
| 2026-08-02 | `4c7ff37de13b035decb791f91f05adb4038c88b3` | Ver.2.0、repository、8 migration、8 pgTAPに基づき初回作成 |
