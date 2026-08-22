# Legal / Privacy公開前確認チェックリスト

> [!IMPORTANT]
> この文書は公開前確認事項の管理用であり、法的結論そのものではありません。
> 現時点の状態は`NEEDS EXTERNAL VERIFICATION`です。公開時点の最新公式資料を確認し、必要に応じて公式窓口・専門家へ確認します。

## 1. 状態

各項目は次のいずれかで管理する。

- `未確認`
- `公式source確認必要`
- `専門家 / 行政窓口確認候補`
- `対応中`
- `完了`
- `対象外（根拠記録必須）`

現在は、明示したものを除きすべて`未確認`である。法令、届出義務、具体的な対象年齢、外部platform要件を推測で確定しない。

## 2. Review metadata

- 対象release: `未確認`
- 確認日: `未確認`
- 確認者: `未確認`
- 使用した公式sourceと確認日: `未確認`
- 外部確認先・回答記録: `未確認`

## 3. Applicable law / service classification

| 確認項目 | 状態 | 記録する内容 |
| --- | --- | --- |
| サービス構成に適用される日本国内の法令・規制inventory | 未確認 | 公式source、適用判断、確認日 |
| 電気通信関連の届出・登録等の要否 | 公式source確認必要 | 要否、根拠、必要な期限 |
| Exchange等の通信・privacy上の義務 | 専門家 / 行政窓口確認候補 | 対象data、運用、アクセス境界 |
| 権利侵害・削除申出・takedown | 未確認 | 受付、本人確認、判断、通知、記録 |
| 投稿者の著作権・肖像・privacy等に関する利用者向け投稿ルールと申出対応の整合 | 未確認 | 禁止・許容範囲、表示文面、受付・判断・通知手順 |

## 4. Personal data / privacy

| 確認項目 | 状態 | 記録する内容 |
| --- | --- | --- |
| 取得する個人情報・個人データinventory | 未確認 | data category、取得元、保存先 |
| 利用目的 | 未確認 | 利用者への提示内容と提示箇所 |
| 安全管理 | 未確認 | technical / organizational control |
| 開示・訂正・利用停止等 | 未確認 | 受付、本人確認、処理、回答 |
| 保存・削除方針 | 未確認 | data category別の期間、削除、例外 |
| account削除・削除申出 | 未確認 | UI有無とは別の受付・対応方針 |
| 漏えい・incident対応 | 未確認 | 検知、初動、連絡、記録、外部確認 |

## 5. External transmission / provider

| 確認項目 | 状態 | 記録する内容 |
| --- | --- | --- |
| Cookie / SDK / third-party data flow | 未確認 | 送信先、送信data、目的、制御 |
| Supabase等のbackend provider利用 | 未確認 | role、data location、契約・設定確認 |
| Netlify等のhosting provider利用 | 未確認 | access log、data flow、契約・設定確認 |
| その他external provider | 未確認 | provider、目的、送信data |

## 6. User-facing deliverables

- [ ] 利用規約を作成・reviewし、提示箇所を確認した
- [ ] Privacy Policyを作成・reviewし、提示箇所を確認した（`NOT YET COMPLETE / REQUIRED BEFORE RELEASE`）
- [ ] 問い合わせ手段を決定し、提示箇所と運用担当を確認した
- [ ] 削除申出の受付方法を決定した
- [ ] 権利侵害申出・takedownの受付方法を決定した
- [ ] moderation方針と利用者向け説明の整合を確認した

法務文面そのものはこのchecklistへ置かず、review対象と版を参照する。

## 7. Minors / age

| 確認項目 | 状態 |
| --- | --- |
| Web公開前の未成年者・年齢方針 | 未確認 |
| 同意・問い合わせ・moderation等への影響 | 未確認 |
| Privacy Policy / Termsとの整合 | 未確認 |
| 将来iOSのage / ratingとの再照合 | 未確認 |

具体的な年齢は、公式情報とproduct判断を確認するまで決定しない。

## 8. Retention decisions

既存Exchange lifecycleとして、never-confirmed orphanは24時間、confirmed removed imageは7日、terminal report evidenceは実際のterminal遷移後30日というsemanticsがある。これらは削除・purge可能になる最短時刻であり、automatic deletion deadlineではない。通常は期限到達後の次回daily maintenanceで処理し、incident、unknown outcome、reference protection等により追加保持される場合がある。

次は別対象であり、現在`DECISION REQUIRED BEFORE PUBLIC RELEASE`である。Maintenance-2の30日purgeはsnapshot rowとsnapshot image relationを削除し、reports rowとStorage physical bytesは削除しない。referenceが外れたbytesは、他の保護referenceと各eligibilityを再評価したうえでconfirmed / orphan cleanup lifecycleへ収束する。

- report row
- reason
- details
- status / resolved_at等のmoderation record

公開前に次を決定する。

- retention purpose
- retention period
- 削除申出との関係
- incident / legal holdまたは通常期限を超える保持の適用条件
- moderation recordとして必要なminimum data

## 9. Completion gate

- [ ] すべての公開前必須項目が`完了`または根拠付き`対象外`になっている
- [ ] 未確認・対応中項目と公開判断への影響を記録した
- [ ] 利用規約、Privacy Policy、問い合わせ手段を公開可能にした
- [ ] Web release checklistへ結果を反映した
