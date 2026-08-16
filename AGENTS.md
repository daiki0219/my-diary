# my-diary Codex作業ルール

## 基本方針

- `my-diary_spec_v2.2.md` を本プロジェクトの仕様書として扱う
- 一度に全機能を実装せず、動作確認可能な小さな単位で進める
- 既存機能や設定を壊さない
- AI機能、課金、広告、ゲーム要素は、明示的な指示があるまで実装しない
- スマートフォンを優先したレスポンシブ設計にする

## Subagent運用

- Codex Mainは、並列化や専門的な調査が有効な場合、個別プロンプトに明記がなくてもsubagentを利用できる。ただし、subagent利用自体を目的とせず、Mainだけで十分な小さな作業では無理に起動しない
- subagentは、repository構造・既存実装・DB / RLS・ACL・migration履歴・test gap・影響範囲・logの調査、security・accessibility review、仕様と実装の照合など、主にread-onlyの調査・レビューへ使用する。独立した調査対象は必要に応じて並列化できる
- subagentは原則read-onlyとし、ファイルの作成・編集・`apply_patch`、migrationの作成・編集、DB / Storage mutation、`git add`・`git commit`・`git push`・`git stash`・`git reset`・`git clean`、packageの追加・更新、Service Role・Auth Admin APIの使用、秘密情報の出力を行わせない
- 実装・修正は、subagentの報告をMainが確認したうえでMain自身が行う。重要な結論、変更対象、security境界、実装判断をMainでも確認し、subagentの推測や未確認事項をそのまま実装根拠にしない
- RLS、ACL、`SECURITY DEFINER`、Storage policy、Auth、account status境界、migration、DB trigger、privilege、秘密情報、remote DB操作は、subagentの報告だけで完了扱いにしない。Main自身が一次資料、現在のrepository、DB定義を確認して最終判断する
- 個別Phaseのプロンプトにsubagent禁止、strict read-only、特定調査だけの許可、特定操作の禁止など、より厳しい条件がある場合は個別プロンプトを優先する。subagent利用はDB変更、remote・Git操作、package変更、破壊的操作などの許可範囲を拡張せず、Mainに許可されていない操作はsubagentにも許可されない

## セキュリティ

- 非公開投稿やフォロワー限定投稿の認可を画面側だけに依存させない
- Supabase RLSを最終的なアクセス制御として使用する
- `SUPABASE_SERVICE_ROLE_KEY` は、明示的な許可があるまで使用しない
- APIキー、パスワード、トークン、接続文字列などの秘密情報をコードへ直接記載しない
- `.env.local` や秘密情報をGitへ追加しない
- `.env.example` には変数名だけを記載し、値は記載しない
- push前に `git status` とコミット対象を確認し、秘密情報が含まれていないことを確認する

## 外部サービスと課金

- 有料プランへの変更や、有料サービスの導入を行わない
- 課金が発生する可能性がある操作は、実行前に内容を説明して確認を求める
- Apple Developer Programなど、有料登録が必要な機能は勝手に進めない

## データベースとStorage

- リモートSupabaseに対する破壊的操作を勝手に実行しない
- データ削除、DBリセット、Storage削除、既存テーブルの削除は実行前に確認を求める
- リモートへのマイグレーション適用前に、変更内容を提示する
- `supabase db reset` はローカル環境であることを確認してから実行する
- Dashboardで直接スキーマ変更せず、原則としてマイグレーションで管理する

## Git

- 大きな変更の前に作業内容を説明する
- GitHubへの初回pushや、重要な変更のpushは実行前に確認を求める
- 既存コミットを勝手に削除、改変、強制pushしない
- `git reset --hard`、`git clean -fd`、force pushなどの破壊的操作は、明示的な許可なしに実行しない

## 実装後の確認

実装後は、可能な範囲で以下を実行する。

- `npm run lint`
- `npm run typecheck`
- `npm run build`
- 対象機能に必要なテスト

作業完了時は以下を報告する。

- 変更ファイル
- 実装内容
- 実行したコマンド
- 動作確認結果
- 未解決の問題
- 次に行うべき作業
