# Maintenance runbook

> [!IMPORTANT]
> この文書はmaintenance運用の骨格です。現在、Applicationからのtrusted maintenance実行経路は未実装であり、`NOT YET OPERATIONAL`です。
> 存在しないcommandや未確認の権限経路を推測して実行しません。

## 1. Security boundary

- maintenanceは通常userのApplication権限から分離する。
- active admin等の既存trusted境界、RLS、ACL、Storage policy、RPC内の再検証を迂回しない。
- Service Role、Auth Admin API、Dashboard直操作を、このrunbookだけを根拠に使用しない。
- report moderationではtarget / reporter本人のadminを除外し、whole-diary accessを付与しない。
- destructive cleanupは対象、grace / retention、reference、lock、結果を確認してから行う。

## 2. 現在確定しているlifecycle

| 対象 | 既存semantics | 備考 |
| --- | --- | --- |
| never-confirmed Exchange image orphan | Storage `created_at`基準で24時間後 | live metadata、confirmed candidate、report snapshot evidenceを除外 |
| confirmed removed Exchange image | relation解除後7日 | 通常participantから即不可視、trusted cleanup対象 |
| terminal report evidence | 実際の`resolved` / `dismissed`遷移後30日 | snapshot本文・tag・image metadata・underlying evidence bytesが対象 |

次は同じ30日へ合わせない。

- report row
- reason
- details

これらの長期retentionは`DECISION REQUIRED`であり、Legal / Privacy reviewとOperations判断で決定する。

## 3. Trusted execution path

- Application実行経路: `NOT YET IMPLEMENTED`
- 実行主体・権限: `DECISION REQUIRED`
- 呼び出す既存RPC / functionとexact signature: 実装Phaseでrepository・catalogを確認して記録する
- dry-run / listing方法: `DECISION REQUIRED`
- 実行結果とaudit記録の保存先: `DECISION REQUIRED`

実行経路の実装・security review・回帰確認が完了するまで、手動SQLや推測したcommandで代替しない。

## 4. Cadence

| 対象 | cadence | owner |
| --- | --- | --- |
| never-confirmed orphan確認 | DECISION REQUIRED | DECISION REQUIRED |
| confirmed cleanup candidate | DECISION REQUIRED | DECISION REQUIRED |
| terminal evidence purge | DECISION REQUIRED | DECISION REQUIRED |
| cleanup backlog / completion監視 | DECISION REQUIRED | DECISION REQUIRED |
| report / moderation queue | DECISION REQUIRED | DECISION REQUIRED |

## 5. Preflight for every run

- [ ] 対象environmentとprojectを確認した
- [ ] 実行者の権限とconflict-of-interest境界を確認した
- [ ] 対象categoryとretention thresholdを確認した
- [ ] listing結果の件数・最古日時・reference除外を確認した
- [ ] active incident、legal hold、known migration中断がないことを確認した
- [ ] concurrent create / updateとのlock・race境界を確認した
- [ ] rollback不能な影響と停止条件を確認した

## 6. Retry / failure handling

- automatic retry policy: `DECISION REQUIRED`
- retry上限・backoff: `DECISION REQUIRED`
- partial successの記録方法: `DECISION REQUIRED`
- unknown outcome時の扱い: 通常retryや追加DELETEを停止し、対象と結果を再確認する
- permission / reference / lock failure: fail-closedとして削除せず記録する
- repeated failure escalation: `DECISION REQUIRED`

## 7. Backlog monitoring

- [ ] candidate件数とage distributionを確認した
- [ ] 実行前後の件数と成功・拒否・失敗を記録した
- [ ] live metadata / evidence除外件数を区別した
- [ ] grace / retention未到達を失敗扱いしていない
- [ ] 閾値超過時のalertとownerを決定した

thresholdとalerting methodは`DECISION REQUIRED`である。

## 8. Evidence purge / Storage cleanup

- [ ] reportが実際にterminal stateへ遷移した日時を基準にした
- [ ] target / reporter本人adminをpurge主体から除外した
- [ ] 期限前evidenceを削除していない
- [ ] whole diaryや無関係entryを対象にしていない
- [ ] same Storage objectへの複数referenceを再評価した
- [ ] metadataとphysical bytesの結果を区別して記録した
- [ ] participant向けlive image routeへevidenceを戻していない

## 9. Incident escalation

- severityとowner: `DECISION REQUIRED`
- cleanup誤対象・data loss疑い: 実行停止、対象保全、incident ownerへ連絡
- privacy / security疑い: 通常logへ本文やevidenceを転載せず、承認済み経路でescalateする
- 法令・通知要否: `NEEDS EXTERNAL VERIFICATION`

## 10. Post-run record

- [ ] environment、実行者、開始・終了時刻を記録した
- [ ] 対象category、threshold、candidate件数を記録した
- [ ] success / rejected / failed / unknownを分離した
- [ ] secret、本文、evidence、個人データを通常記録へ含めていない
- [ ] follow-up ownerと期限を記録した
