# my-diary

日々の出来事や気持ちを気軽に記録し、必要なときだけ人とゆるくつながれる「ゆる日記SNS」のWebアプリケーションです。

現在はPhase 0-Aとして、Next.jsの開発・品質基盤のみを構築しています。機能要件は `my-diary_MVP_spec_v1.0.md`、開発ルールは `AGENTS.md` を参照してください。

## 必要な環境

- Node.js 20.9以上
- npm

## セットアップ

```bash
npm install
```

必要な環境変数は `.env.example` を確認し、値を設定した `.env.local` を作成します。`.env.local` はGit管理対象外です。

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

すべて成功することを確認してから変更をコミットします。

## その他のコマンド

```bash
# 本番ビルドを起動
npm run start
```

## 技術構成

- Next.js App Router
- React
- TypeScript
- Tailwind CSS
- ESLint

## セキュリティ

- 秘密情報をコードやGitへ追加しない
- `.env.local` をコミットしない
- `.env.example` には変数名だけを記載する
- Supabaseの認可は、今後RLSを最終的なアクセス制御として実装する
