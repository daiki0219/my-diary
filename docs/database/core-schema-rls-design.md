# コアデータモデル・RLS設計案

## 対象と前提

この設計案は、最初のデータベース単位として `accounts`、`profiles`、
`posts`、`follows` のみを対象とする。投稿画像、タグ、リアクション、
コメント、通知、通報、Storageは含めない。

全体公開投稿を含めて閲覧はログイン必須とする。`anon` には4テーブルの
権限を付与せず、`authenticated` に対してもRLSと列権限の両方で制御する。

今回作成したSQLはレビュー用の案であり、リモートSupabaseには未適用である。

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
`soft_delete_post` 関数だけを削除経路とする。
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
- ソフトデリート: 本人だけが `soft_delete_post` 関数で `deleted_at` を設定
- DELETE: 一般ユーザーには権限もRLSポリシーも付与しない

列権限により、一般ユーザーは `id`、`user_id`、作成・更新日時を直接変更
できない。`updated_at` はトリガーで更新する。

### profiles

- SELECT: ログイン済みユーザー
- UPDATE: 本人だけ
- INSERT / DELETE: 一般ユーザーには許可しない

### follows

- SELECT: アクティブなログイン済みユーザー
- INSERT / DELETE: `follower_id = auth.uid()` の行だけ
- UPDATE: 許可しない

### accounts

- SELECT: 本人の行だけ
- UPDATE: 本人の `timezone` 列だけ
- INSERT / DELETE: 一般ユーザーには許可しない

## セキュリティ関数

### `handle_new_auth_user`

`auth.users` 作成時に同じUUIDの `accounts` と `profiles` を生成し、1対1の
ライフサイクルを保証するトリガー関数。`auth` スキーマから `public`
スキーマへ書き込むため `SECURITY DEFINER` が必要である。
初回適用時点ですでに存在する `auth.users` は、トリガー作成前の
`INSERT ... SELECT ... ON CONFLICT DO NOTHING` で安全に補完する。

危険を抑えるため、引数を受け取らずトリガーの `new.id` だけを使い、
`search_path = ''` と完全修飾名を使用し、`public` の実行権限を剥奪する。
ユーザー由来メタデータから `role` や `status` を設定しない。

### `private.is_account_active`

指定ユーザーの `accounts.status` が `active` かだけを返し、suspended投稿者の
投稿を他ユーザーから隠すために使用する。accountsのRLSを迂回して投稿者状態を
確認する必要があるため `SECURITY DEFINER` とする。

状態列そのものは返さずbooleanだけを返し、`search_path = ''` と完全修飾名を
使用する。また、PostgRESTの公開対象ではない `private` スキーマに配置し、
`public` の実行権限を剥奪する。`authenticated` にはRLS評価に必要な
USAGEとEXECUTEだけを付与する。

### `soft_delete_post`

通常のUPDATEでは、更新後にSELECTポリシー上見えなくなる行を安全に扱えないため、
投稿IDを受け取り、投稿者本人・未削除・activeアカウントを確認して
`deleted_at` を設定する限定RPC関数とする。この狭い操作だけRLSを迂回する必要が
あるため `SECURITY DEFINER` を使用する。

任意SQLや他ユーザーIDは受け取らず、`auth.uid()` と完全修飾名だけを使用する。
`search_path = ''` を固定し、`public` と `anon` の実行権限を剥奪して
`authenticated` だけにEXECUTEを付与する。処理結果は成功・不成功のbooleanで、
投稿内容は返さない。

### `set_updated_at`

更新時刻を統一する通常のトリガー関数。追加権限が不要なので
`SECURITY DEFINER` は使用しない。`search_path = ''` は固定する。

## インデックス

- `posts_user_created_at_idx`: ユーザープロフィール、本人の日記、
  フォロー中タイムラインを新しい順に取得するため
- `posts_public_created_at_idx`: 最新の全体公開投稿を新しい順に取得するため
- `follows` の主キー: 閲覧者が投稿者をフォロー中かを確認するRLSの
  `(follower_id, following_id)` 検索に使用
- `follows_following_follower_idx`: フォロワー一覧とフォロワー数の逆向き検索用
- `profiles_username_lower_idx`: 大文字小文字を無視したユーザー名検索の準備

部分インデックスでは `deleted_at is null` を条件にし、通常の取得対象だけを
小さく保つ。

## マイグレーションの再実行性と依存順

初回スキーマは1ファイルのトランザクションで、依存順を次のように固定する。

1. 拡張と非公開関数用スキーマ
2. 親となる `auth.users` を参照するテーブル
3. インデックス
4. 関数とトリガー
5. 権限
6. RLSポリシー

テーブルとインデックスには `IF NOT EXISTS`、関数には
`CREATE OR REPLACE`、トリガーとポリシーには `DROP IF EXISTS` 後の再作成を
使用している。ただし、Supabaseのマイグレーション履歴で一度だけ適用するのが
原則であり、既存テーブル定義を修正する用途で同じファイルを再実行しない。
変更は必ず後続マイグレーションとして追加する。

## テスト方針

pgTAPテストはトランザクション内にA・B・Cの認証ユーザーと投稿を作成し、
JWT claimとDB roleを切り替えてRLSを検証し、最後にロールバックする。
最低限、次を確認する。

- private / followers / public / deleted投稿の閲覧境界
- フォロー解除直後のアクセス喪失
- 投稿の本人名義作成、本人だけの更新・ソフトデリート
- 一般ユーザーによる物理DELETEの拒否
- suspended投稿者の投稿を本人以外から非表示
- 自己フォロー、重複、他人名義のフォロー操作
- `accounts.role` / `accounts.status` の更新拒否
- 他ユーザーのaccountsを閲覧できないこと
- ログイン済みユーザーによるprofiles閲覧
- 本人だけのプロフィール更新
- 本人だけのタイムゾーン更新

## 未確定事項

- body、bio等の文字数上限の最終値
- `timezone` のIANA名をDBでも厳密検証するか、アプリ入力候補で保証するか
- ソフトデリート後の保持期間とPhase 2での物理削除手順
- Phase 2で実装する管理者のrole/status変更経路と監査ログ
- 将来のプロフィール公開範囲とブロック機能
