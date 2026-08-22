# Maintenance runbook

> [!IMPORTANT]
> 初回公開時のmaintenanceは、active-adminの人間が`/admin/maintenance`から1日1回実行するmanual operationです。
> これは実装漏れではなく、初回productionで採用する運用設計です。対象選択はserver-sideで行い、同じauthenticated principalに対するRLS / Storage RLSを最終認可境界とします。

## 1. Architectureと禁止事項

- Primary operator: daily maintenanceを担当するapproved active-admin human。
- Application path: `/admin/maintenance`。
- ApplicationはClientからreport ID、Storage path、user ID等を受け取らず、対象をserver-sideで選択する。
- Server Actionはoperatorと同じauthenticated Supabase principalを使用し、DB / Storageのactive-admin、COI、reference protectionを迂回しない。
- Netlify Scheduled Functions、Supabase Cron、machine principal、Service Role、Auth Admin APIは使用しない。
- Dashboard直操作、手動SQL、credential共有、同一人物の別accountによるCOI迂回を標準手順にしない。
- external monitoringとmaintenance history DB tableは初回公開の必須条件にしない。daily manual backlog checkをprimary detection mechanismとする。

毎回の開始前に、対象environment / projectを識別できること、current sessionがapproved active-adminであること、summaryを取得できること、active incidentやmigration作業と競合しないことを確認する。通常sign-upはadminを作成しないため、approved active-adminが存在しないenvironmentでは実行せず、production / operations ownerへescalateする。

## 2. Retentionの読み方

24時間、7日、30日は、削除・purge可能になる最短時刻であり、exact automatic deletion deadlineではない。通常は期限到達後の次回daily maintenanceで処理する。incident、unknown outcome、別reference、COI、その他のfail-closedな保護により、追加保持される場合がある。

| category | eligibility | 1 runの上限 | action |
| --- | --- | ---: | --- |
| Report evidence | reportが実際に`resolved` / `dismissed`へ遷移してから30日 | 10 reports | snapshot rowとsnapshot image relationをatomic RPCでpurgeする。report rowとStorage physical bytesは削除しない |
| Confirmed removed Exchange image | live relation解除後7日 | 10 objects | 1 pathずつStorage DELETEし、completion RPCでcandidateを完了する。relation解除後はparticipantから即不可視 |
| Never-confirmed orphan | upload後、metadataへconfirmされないまま24時間 | 10 objects | 1 pathずつStorage DELETEする。live metadata、confirmed candidate、report evidence referenceは対象外 |

report row、reason、details、status、resolved_at等の長期retentionはevidenceの30日へ合わせない。retention purpose、期間、削除申出との関係、incident / legal hold、moderation recordとして必要なminimum dataは`DECISION REQUIRED BEFORE PUBLIC RELEASE`である。

## 3. Daily cadenceと実行順

標準cadenceは1日1回。開始時に3 categoryの`due count`と`oldest due at`を確認する。標準実行順は次のとおり。

1. Evidence
2. Confirmed
3. Orphan

Evidenceを先にpurgeすると、そのevidence relationだけに保護されていたStorage objectが既存Exchange cleanup lifecycleへ収束できる。ただしevidence purge自体はphysical DELETEではない。confirmed candidateの7日未到達、live relation、別report evidence等が残るobjectは削除されない。

現在のUI表示順は`Confirmed → Orphan → Evidence`で、標準運用順と異なる。この既知のLOW operational riskは、本runbookに従って`Evidence → Confirmed → Orphan`の順に操作することで吸収する。UI変更は後続Design Phaseで扱う。

終了時に各categoryの`remaining`、`oldest`、`outcome`、unknown / failureの有無を確認する。

## 4. Multi-run rule

最大10件は`per run`であり`per day`ではない。success後にremainingが残る場合は、full reloadまたはcurrent summaryの更新を確認してから同categoryを追加runできる。必要run数の目安は`ceil(due count / 10)`だが、固定回数を連打せず、各runの前後にcurrent stateを再評価する。

## 5. Outcome別handling

| outcome | operator handling |
| --- | --- |
| `success` | remainingを確認し、0より大きければreload後に次run |
| `empty` | 正常終了。次回dailyまで待つ |
| `changed` | full reloadし、current backlogを再確認。dueが残る場合だけ新しいrunを最大1回 |
| `partial` | 完了済み分はrollbackしない。UIではunavailableとfailedを個別判別できないため、reload後にaffected categoryを停止して調査し、同日retryしない |
| `unavailable` | `partial`に含まれる。UI aggregateから原因を推測せず、連続retryしない |
| explicit failure / `error` | reload後のcontrolled retryは最大1回。同じfailureならaffected categoryを停止 |
| `unknown` | §6に従う |
| summary failure | 全categoryを実行しない。reloadを1回行い、再発ならmaintenance全停止 |
| authorization failure | 通常loginで再認証する。role変更、Dashboard操作、credential workaroundで迂回しない。継続する場合はmaintenance全停止 |

Applicationではindividual `unavailable` / `failed`が区別されず、aggregateの`partial`として表示される。表示されたaggregate countを用い、個別対象のIDやpathを調べるために境界を迂回しない。

## 6. Unknown outcome

1. 即再submitしない。
2. `selected / processed / reconciled / remaining`等のaggregateだけを記録し、IDやpathは記録しない。
3. full reloadする。
4. count、oldest、remainingを再確認する。
5. backlogが減少または消失している場合、確定済み分を再処理しない。
6. summary、environment、admin境界が正常でdueが残る場合だけ、新しいrunを1回許可する。
7. 同categoryで再度unknownになった場合は、そのcategoryを停止してescalateする。

Category固有の扱い：

- Confirmed: Storage DELETE outcomeが不明なとき、ApplicationはDELETEをretryせずcompletion-only reconciliationを試みる。operatorは`processed / reconciled`のaggregateを確認し、即DELETE retryをしない。
- Evidence: purge RPCはatomic。commit済みなら次回candidateから消え、未commitならdueのまま残る。
- Orphan: separate ledger / completion RPCはない。reload後のStorage-backed backlogを正とし、残る場合だけ新しいrunで再選択させる。

## 7. Daily record

operator記録には次だけを残す。

- environment
- date / time
- category
- before count
- after count
- outcome
- follow-up

report ID、Storage path、user / entry / diary / evidence ID、日記本文、evidence内容、raw error、credential、tokenは記録しない。

## 8. Monitoring、capacity、escalation

### 即時に全maintenance停止

- project / environmentを判別できない
- authorization boundaryに異常がある
- summaryをreload後も取得できない
- protected / live / evidence objectを削除した疑いがある
- Browserへinternal ID、Storage path、raw errorが露出した
- backlogが予期せず急増した
- active migrationまたはincident対応と競合している

### affected categoryを同日停止・調査

- unknownがreload後の新しいrunでも再発した
- 同じexplicit failureが2回続いた
- Storage categoryだけが繰り返し失敗する

daily window内にbacklogをdrainできなかった場合は24時間以内に調査する。oldest dueが48時間以上超過した場合、または同categoryでcountが減らない・oldest dueが前進しない状態が2回のdaily windowで続く場合はincidentとして扱う。

次のいずれかを満たしたらmanual dailyのcapacityを再reviewする。

- 同categoryで3 run以上を2日連続で必要とする
- 処理後もcountが増加し続ける
- oldest dueが48時間以上古い

このreviewはautomation導入を自動決定しない。batch capacity、cadence、automation、monitoringを別Phaseで再設計する。

## 9. Owner、backup、COI

- Primary operatorはdaily maintenanceを担当するactive-admin humanとする。個人名は承認済み外部運用記録で管理する。
- dailyの常時backupは必須ではない。ただしCOIまたは48時間超の不在に備え、独立したapproved active-admin operatorを推奨する。
- credential共有は禁止する。

Evidence purgeでは、current adminがreporterまたはreported userであるreportはsummary、candidate、purgeから除外される。unrelated active-adminへhandoffする。独立operatorがいない場合は処理せずevidenceを保持し、release / operational decisionへescalateする。Service Roleや同一人物の別accountで迂回しない。

Exchange image cleanupではApplicationがreport COIを推測しない。report evidence relationが残る限りStorage RLSがDELETEを拒否する。operatorはreport内容からeligibilityを判断せず、DB / Storage reference protectionへ委ねる。

## 10. Controlled development remote smoke（未実施）

linked `my-diary-dev`はdevelopment remoteであり、controlled remote Storage smokeは`NOT YET VERIFIED`である。実施には別Phaseの明示許可が必要。

- 通常sign-upではadminにならない。既存のdedicated test accountとapproved active-adminを使い、credentialを共有しない。
- approved smoke commit、linked project identity、repository / remote migration historyの一致を確認し、対象bucketを`exchange-entry-images`へ限定する。値を推測せず、確認できなければ停止する。
- fixture ownerとなるdedicated participant accountとmaintenance operatorを区別し、既存production userや本人用accountをfixtureにしない。
- baselineのrelevant due categoryが0であることを確認する。server-side target selectionのため、既存dueがあればfixtureを狙い撃ちできないので停止する。
- Confirmedは通常Applicationで画像付きentryを作成し、editでremoveして7日待つ。
- Orphanは通常authenticated publishable clientでstrict pathへ1 objectだけuploadし、metadataへconfirmせず24時間待つ。
- evidenceは30日待機が必要でStorage physical DELETEも検証しないため、最小Storage smokeには含めない。
- remote timestampを書き換えて即due化しない。Service Role、Auth Admin API、privileged SQL、migration、production user dataをfixture accelerationに使わない。
- remoteでlocalの`12 → 10 → 2`を再現せず、confirmed 1 objectとorphan 1 objectだけを確認する。
- 各categoryでbaseline `0 → 1`、実行後`remaining 0`を確認し、smoke対象の2 Storage objectが存在しないことをauthenticated経路で確認する。対象objectの残存は成功扱いにしない。
- 通常UIでsoft delete / archiveできるfixtureは終了時に整理する。特権cleanupなしでは残るAuth / diary等のDB residualはIDや個人情報なしで記録し、Storage objectの必須不存在とは区別する。

## 11. Productionとの分離

development smokeはauthenticated admin path、Storage RLS、candidate selection、cleanup action、remaining / reloadを確認するが、production wiringの証明にはならない。production deploy後はProduction runbookに従い、production Netlify、production Supabase、production cookie / session、production active-admin、production Storage設定、actual domainを明示的に確認する。
