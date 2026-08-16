# Web初回公開チェックリスト

> [!IMPORTANT]
> この文書は[`my-diary_spec_v2.2.md`](../../my-diary_spec_v2.2.md)のWeb Initial Release Gateを実行可能な粒度で確認するための管理表です。
> 現在の状態は`NOT YET COMPLETED`です。未確認項目を完了扱いにしません。

## 1. 使い方

- 実施日、対象commit、production環境、確認者、証拠への参照を各release reviewで記録する。
- 外部設定や画面を実測できなかった項目は未完了のまま残す。
- secret、credential、token、接続文字列、個人データをこの文書へ記載しない。
- Product Requirementは正式仕様、実装状態は[`current-implementation-status.md`](../project/current-implementation-status.md)を正とする。

## 2. Release metadata

- [ ] 対象commitを記録した
- [ ] production deploy identifierを記録した
- [ ] 確認日時・確認者を記録した
- [ ] known deferred itemsとrelease判断者を記録した

## 3. Product

- [ ] Web初回公開対象の主要Product Requirementを確定した
- [ ] email / password認証、login、logout、password recoveryを確認した
- [ ] profile、post、visibility、image、timeline、follow、reaction、comment、search、calendar、notification、settingsの初回公開対象を確認した
- [ ] Exchangeの初回公開対象を確認した
- [x] E3f-2 Exchange entry report UIを完了・確認した
- [x] E3f-3 Exchange user-report scope hardeningを完了・確認した
- [x] E3f-4 Exchange counterpart report UIを完了・確認した
- [ ] admin report queueを実装し、security reviewと回帰確認を完了した
- [ ] moderator exact-evidence経路を実装し、security reviewと回帰確認を完了した
- [ ] maintenance実行経路を実装し、security reviewと回帰確認を完了した
- [ ] OAuth、avatar、pagination、settings等のdeferred itemを明示した
- [ ] account完全削除とglobal user blockがWeb公開後roadmapであることをrelease判断へ反映した

## 4. Design Completion

### 4.1 主要route・状態

- [ ] auth
- [ ] home / timeline
- [ ] post create / detail / edit
- [ ] own / other profile、follow list
- [ ] search / tags
- [ ] calendar
- [ ] notifications
- [ ] settings
- [ ] Exchange list / invitation / detail / create / edit
- [ ] Exchange report / moderation
- [ ] empty / loading / validation / error / success / confirmation

### 4.2 Viewport matrix

次の各幅で、主要routeと主要状態の意図しない横scroll、navigation、form、card、dialog、long contentを確認する。

| 幅 | 確認 |
| ---: | --- |
| 320px | [ ] |
| 360px | [ ] |
| 375px | [ ] |
| 390px | [ ] |
| 1280px | [ ] |

### 4.3 Content・accessibility・console

- [ ] 長文、改行、連続半角文字列、長いusername / tag / locationでlayoutを確認した
- [ ] keyboardだけで主要操作を完了できる
- [ ] focus indicator、focus順、dialogのfocus移動・復帰を確認した
- [ ] label、heading、landmark、list、form等のsemantic structureを確認した
- [ ] screen readerで重要な状態・結果・操作の意味が伝わる
- [ ] contrastとcolor-only禁止を確認した
- [ ] loading、error、success、pendingが支援技術へ通知される
- [ ] console error / warning、React warning、hydration errorがない

## 5. Security

- [ ] RLSがprivate / followers / publicとparticipant-only境界の最終認可になっている
- [ ] non-active account、ownership、mutation境界を確認した
- [ ] private post / image / Exchange dataの第三者取得を拒否する
- [ ] report targetへreporter、reason、details、evidenceを漏らさない
- [ ] admin whole-diary bypassがなく、exact evidenceだけを扱う
- [ ] target / reporter本人であるadminのconflict-of-interest境界を確認した
- [ ] unresolved security blockerがない
- [ ] repository、client response、log、deploy artifactへsecretやprivate dataを露出していない

## 6. Production

- [ ] production domainとHTTPSを確認した
- [ ] production environment variable名・設定先・責任者を確認した
- [ ] Auth Site URL / Redirect URLs / callbackを確認した
- [ ] email confirmation、SMTP、実メール、email templateを確認した
- [ ] recovery callback初回表示とexpired recovery linkを確認した
- [ ] HTTPS上のsession / Cookie挙動を確認した
- [ ] private Storage accessとraw path非露出を確認した
- [ ] production buildとdeployを確認した
- [ ] sign-up、login、logout、recovery、visibility、Storage、Exchange、Exchange限定report / moderationのproduction E2Eを確認した
- [ ] §20.5のlogging privacyをproductionでも満たす

詳細手順は[`production-runbook.md`](../operations/production-runbook.md)を参照する。

## 7. Operations

- [ ] production release / rollback判断がrunbook化されている
- [ ] maintenance実行経路と権限境界が確認されている
- [ ] cadence、retry、failure handling、backlog monitoringが決定されている
- [ ] incident escalationと連絡先が決定されている
- [ ] moderationとtakedownの運用が決定されている
- [ ] retention / purge運用が決定されている
- [ ] report row / reason / detailsの長期retention判断を記録した

詳細は[`maintenance-runbook.md`](../operations/maintenance-runbook.md)を参照する。

## 8. Legal / Privacy

- [ ] [`legal-privacy-checklist.md`](../legal/legal-privacy-checklist.md)の公開前必須項目が完了している
- [ ] 利用規約を利用者へ提示できる
- [ ] Privacy Policyを利用者へ提示できる
- [ ] 問い合わせ手段を利用者へ提示できる
- [ ] 削除申出・権利侵害申出の受付方針が決定している
- [ ] 未成年者・年齢方針が決定している
- [ ] external provider / data flowの確認結果を記録した

## 9. Final release decision

- [ ] 未完了項目、例外、延期項目とrisk acceptanceを記録した
- [ ] Product、Security、Design、Legal / Privacy、Production、Operationsの各Gate ownerが承認した
- [ ] Web初回公開可能と判断した
