# my-diary

日々の出来事や気持ちを気軽に記録し、必要なときだけ人とゆるくつながれる「ゆる日記SNS」のWebアプリケーションです。

現在はPhase 0-Bとして、Next.jsとSupabaseの接続基盤までを構築しています。機能要件は `my-diary_MVP_spec_v1.0.md`、開発ルールは `AGENTS.md` を参照してください。

## 必要な環境

- Node.js 20以上
- npm
- ローカルSupabaseを起動する場合はDocker互換のコンテナ環境

## セットアップ

```bash
npm install
```

`.env.example` をコピーして `.env.local` を作成し、Supabase Dashboardで確認した開発プロジェクトの値を設定します。

```dotenv
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=
```

`.env.local` はGit管理対象外です。値をソースコード、README、チャット、コミットへ記載しないでください。

## 開発サーバー

```bash
npm run dev
```

ブラウザで [http://localhost:3000](http://localhost:3000) を開きます。

## 品質チェック

```bash
npm run lint
npm run typecheck
npm run build
```

本番ビルドを起動する場合は、ビルド後に次を実行します。

```bash
npm run start
```

## Supabase CLI

Supabase CLIはプロジェクトのdev依存としてバージョン固定しています。グローバルインストールは不要です。

```bash
npm run supabase -- --version
npm run supabase -- --help
```

`supabase/` は `supabase init` で初期化済みです。ローカルSupabaseを起動する場合はDockerを起動してから次を実行します。

```bash
npm run supabase -- start
npm run supabase -- status
npm run supabase -- stop
```

ローカル環境を外部ネットワークへ公開しないでください。

## 開発プロジェクトとのlink

linkにはSupabaseアカウントの認証と開発プロジェクトのproject refが必要です。認証情報やデータベースパスワードはファイル、チャット、コミットへ記載せず、CLIの対話入力またはOSの安全な資格情報ストアで扱います。

```bash
npm run supabase -- login
npm run supabase -- link --project-ref <PROJECT_REF>
```

project refはSupabase DashboardのプロジェクトURLに含まれるIDです。link後も、リモート変更を行う `db push` や破壊的な `db reset --linked` は、変更内容と対象環境を確認せず実行しないでください。

## Supabase接続確認

`.env.local` を設定して開発サーバーを起動した後、次のURLへアクセスします。

```text
http://localhost:3000/api/health/supabase
```

接続できた場合は次のJSONを返します。

```json
{
  "ok": true,
  "status": "connected"
}
```

環境変数が未設定の場合は `configuration_missing`、Supabase Authへ到達できない場合は `unreachable` とHTTP 503を返します。レスポンスにはURLやキーを含めません。この確認はAuthのヘルスチェックのみで、テーブル、RLS、Storage、OAuth、リモートデータを変更しません。

## Supabaseクライアント

- `src/lib/supabase/client.ts`: Client Component向けブラウザクライアント
- `src/lib/supabase/server.ts`: Server Component、Route Handler、Server Action向けCookie対応サーバークライアント
- `src/lib/supabase/env.ts`: 公開接続情報の取得と未設定チェック

認証実装時には、サーバー側のセッション更新を担うNext.js Proxyを追加します。認可は画面表示だけに依存させず、テーブル作成時にSupabase RLSを最終防衛線として設計します。

## 技術構成

- Next.js App Router
- React
- TypeScript
- Tailwind CSS
- ESLint
- Supabase JavaScript Client
- Supabase SSR
- Supabase CLI

ORMは使用せず、データベース変更はSupabase CLIのマイグレーションで管理します。
