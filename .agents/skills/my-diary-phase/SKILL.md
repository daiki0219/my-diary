---
name: my-diary-phase
description: my-diaryリポジトリの通常の小規模Phaseを、安全ゲート付きで事前調査・機能実装・回帰修正・実装後検証・コミット前確認まで進める共通ワークフロー。個別プロンプトで明示的に`$my-diary-phase`と指定された場合に使用する。大規模なDB migration中心のPhase、セキュリティ監査のみ、レスポンシブ検証のみ、セッション引き継ぎのみ、他リポジトリ、一般的な質問・相談、Git状態を見るだけの依頼には使用しない。
---

# my-diary Phase進行

## 目的と適用範囲

my-diaryの通常Phaseを、動作確認可能な小さな単位で進める。Phase固有の仕様、対象範囲、許可事項、停止条件は個別プロンプトから受け取る。このSkillは明示呼び出しを前提とし、単独で作業範囲や許可を拡張しない。

最初にリポジトリの`AGENTS.md`を読み、常に優先して守る。Skillと個別プロンプトが矛盾する場合は変更せず停止し、矛盾点を報告する。Phase固有情報を推測で補わない。

## 必須入力を確認する

個別プロンプトから次を確認する。

- Phase名と作業目的
- 基準HEAD
- 対象機能と対象画面または対象領域
- 対象外
- DB変更の有無
- migration作成の可否
- リモートDB操作の可否
- ブラウザ検証の範囲
- commitの可否
- pushの可否
- 固有の停止条件

不足があっても安全な読み取り専用調査だけができる場合は、不足項目を示し、変更せず調査に限定する。安全に範囲を確定できない場合は、ファイルを変更せず停止して不足情報を求める。基準HEAD、テスト件数、migration件数などの変動情報を固定値で補わない。

## 作業開始前

変更前に[preflight.md](references/preflight.md)を読み、次を確認する。

1. `AGENTS.md`
2. 個別プロンプトが通常Phaseと厳密な読み取り専用Phaseのどちらを許可するか
3. 許可範囲に応じたリモート確認、branch、HEAD、`origin/main`、ahead/behind
4. `git status`と予期しない差分
5. migration履歴
6. 作業に必要な場合のDocker Desktop、ローカルSupabase、開発サーバー

通常Phaseでは個別プロンプトがGit管理領域の更新を許可する場合に`git fetch origin`を使用できる。ファイルシステムやGit管理領域への書き込みが禁止された厳密な読み取り専用Phaseではfetchせず、[preflight.md](references/preflight.md)の非書き込み手順を使う。実リモートや環境を確認できなかった場合は、推測せず未確認として扱う。

現在のGit状態が個別プロンプトの基準と異なる、未コミット変更や予期しない設定がある、または必要な安全条件を確認できない場合は変更せず停止する。既存のユーザー変更を破棄しない。

## subagentによる調査

通常Phaseでは、並列化や専門的な調査が有効な場合、`AGENTS.md`のsubagent運用方針に従ってread-onlyの調査・レビューをsubagentへ分担できる。Mainだけで十分な小さな作業では無理に利用しない。

subagentはファイル、migration、DB / Storage、Git、package等を変更せず、実装・修正は報告を確認したMainが行う。security-criticalな結論は、Main自身が一次資料、現在のrepository、DB定義を確認して最終判断する。個別プロンプトのより厳しい禁止・許可を優先し、subagent利用によってPhaseの操作権限を拡張しない。

## 実装前の基準検証

変更内容と個別プロンプトに応じて、既存pgTAP、lint、typecheck、build、既存画面、既存DB権限、migration履歴から必要な項目を選ぶ。重い検証を無条件に実行しない。基準検証が失敗した場合は、今回の変更前からの問題かを切り分け、範囲を勝手に拡張せず停止または報告する。

## 実装時の原則

- 小さな変更に限定し、無関係なリファクタリングや仕様外機能を追加しない。
- `AGENTS.md`の設計、セキュリティ、外部サービス、DB、Gitの規則を守る。
- 既存migrationを改変しない。新規migrationは明示許可がある場合だけ作成する。
- Service Roleを使用しない。RLSを最終認可として維持し、クライアント由来のユーザーIDを信用しない。
- 秘密情報やユーザー固有の認証情報をコード、ログ、報告へ含めない。
- package変更、テストデータ作成、既存プロセスの強制終了は明示許可がある場合だけ行う。
- DB変更が必要になったら許可範囲を再確認する。リモートDB変更の明示許可が未確認なら直前で停止する。
- Skillを危険な操作の承認根拠にしない。

常にforce push、`git reset --hard`、`git clean -fd`、`git clean -fdx`、無関係な変更の破棄、Service Role使用、秘密情報の出力、既存migrationの改変、本番データへの無断操作を行わない。

## 実装後の検証

[verification.md](references/verification.md)を読み、変更内容に応じてpgTAP、lint、typecheck、production build、`git diff --check`、migration履歴、linked schema diff、秘密情報混入、変更ファイルを確認する。すべてを無条件に実行せず、選択理由と未実施理由を残す。DB変更がない場合はmigrationの作成・適用を行わない。

## ブラウザ検証

UI変更がある場合だけ、個別プロンプトの範囲で320px、360px、375px、390px、1280pxを確認する。横スクロール、長文・改行・連続半角文字列、フォーム状態、アクセシビリティ、保存中表示、二重送信、console warning/error、hydration errorを検証する。詳細は[verification.md](references/verification.md)を使う。

自動ブラウザで再現できない操作を成功扱いにせず、「未実施・手動確認」として残す。UI変更がないPhaseではブラウザ検証を要求しない。

## commit・push・リモート操作前のゲート

個別プロンプトで明示許可されていない場合は、commit、push、リモートDBへのmigration適用、migration repair、破壊的操作の直前で停止する。`supabase db push`を自動承認しない。

commitが許可されていても、対象ファイル、検証結果、秘密情報、migration差分を直前に確認する。通常push、新規migration作成、リモートDB操作、package変更、テストデータ作成、既存プロセスの強制終了には、それぞれ個別の明示許可を必要とする。force pushは個別プロンプトに記載されていても実行しない。

## 最終報告

必要時に[report-template.md](references/report-template.md)を読み、事実だけを報告する。個別プロンプトの必須入力、適用した安全ゲート、発動または適用した停止条件、読み取り専用・変更なしの確認を含める。対象外と未実施を区別し、検証不能項目を成功扱いしない。commit・push・DB操作を行っていない場合も明記する。
