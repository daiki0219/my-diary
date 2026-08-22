# Production runbook

> [!IMPORTANT]
> この文書はproduction公開作業の骨格です。現時点の状態は`NOT YET VERIFIED`です。
> secret、credential、token、接続文字列、実際のenvironment value、個人データを記載しません。

## 1. Scopeとsource-of-truth

- Product Requirement: [`my-diary_spec_v2.2.md`](../../my-diary_spec_v2.2.md)
- 実装状態: [`current-implementation-status.md`](../project/current-implementation-status.md)
- Release判定: [`web-release-checklist.md`](../release/web-release-checklist.md)
- Hosting platform: Netlify。実際のproduction site / team / deploy設定は公開前に確認する。
- Backend: Supabase。実際のproject、Auth、Database、Storage設定は公開前に確認する。
- linked `my-diary-dev`はdevelopment remoteであり、production Supabase projectではない。
- production Supabase project、Netlify site / team、production branch mapping、NetlifyからSupabaseへのmapping、production active-adminは`NOT YET VERIFIED`である。

## 2. Roles and approvals

- Release owner: `DECISION REQUIRED`
- Production configuration owner: `DECISION REQUIRED`
- Rollback decision owner: `DECISION REQUIRED`
- Incident contact: `DECISION REQUIRED`
- Legal / Privacy approval reference: `NOT YET VERIFIED`

## 3. Environment configuration

repositoryで使用する変数名は次のとおり。値はNetlify等の承認済みsecret / environment管理へ設定し、この文書やGitへ記載しない。

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_SITE_URL`

- [ ] productionとpreviewのscopeを分離した
- [ ] 値の設定者・reviewer・更新日を外部管理記録へ残した
- [ ] 不要なsecretやService Role keyをclient環境へ置いていない
- [ ] build log / deploy logへ値が出ていない

## 4. Domain / HTTPS / callback

- [ ] production domainの所有・DNS・有効化を確認した
- [ ] Netlifyのproduction domainとpublish対象branchを確認した
- [ ] HTTPS certificateとHTTPからHTTPSへの挙動を確認した
- [ ] `NEXT_PUBLIC_SITE_URL`と公開originの一致を確認した
- [ ] Supabase Auth Site URLを確認した
- [ ] Redirect URLsに必要なproduction callbackだけが許可されている
- [ ] Auth callback / recovery callbackがsame-originの期待どおりに動作する
- [ ] HTTPS上のsession / Cookie、logout、expired sessionを確認した

具体domainやURLはrelease記録または承認済みconfiguration管理で追跡し、secretと混在させない。

## 5. Email / Auth

- [ ] email confirmationがproductionで届く
- [ ] SMTP設定と送信元を確認した
- [ ] production email templateとcallback先をreviewした
- [ ] 登録済み・未登録emailでpassword recoveryの案内が情報漏えいを起こさない
- [ ] recovery callback初回表示を通常の実ブラウザで確認した
- [ ] expired / reused / malformed recovery linkをgenericに拒否する
- [ ] password更新後のlogoutと新password loginを確認した
- [ ] non-active accountがapplicationとDBの両方でfail-closedになる

## 6. Pre-deploy validation

repositoryに定義された次のcommandを、対象commitと同じ状態で実行し結果をrelease記録へ残す。

```text
npm run lint
npm run typecheck
npm run build
```

- [ ] documentation / migration / package差分をreviewした
- [ ] known warningとreleaseへの影響を記録した
- [ ] production environmentでbuildに必要な変数名が揃っている
- [ ] deploy artifactやsource mapにsecretがない

## 7. Deploy

Netlifyの具体的なproject操作・権限・deploy方式はproduction設定確認後にこのrunbookへ追記する。存在を確認していないCLI commandは記載しない。

- [ ] 対象branch / commitを確認した
- [ ] previewで主要smokeを実施した
- [ ] production deployの実行者と時刻を記録した
- [ ] deploy後のhealth、Auth、Storageを確認した
- [ ] unexpected redirect、404、5xx、console errorを確認した

## 8. Production smoke / E2E

### 8.1 Development remote smokeとの責務分離

Maintenance-4のcontrolled development remote smokeは、linked `my-diary-dev`でauthenticated admin path、Storage RLS、server-side candidate selection、cleanup action、remaining / reloadを確認する。現時点では`NOT YET VERIFIED`であり、このdocs-only Phaseでは実行しない。

development smokeではconfirmed 1 objectとorphan 1 objectだけを扱い、通常Application / authenticated publishable clientでfixtureを準備して実際に7日 / 24時間待つ。Service Role、Auth Admin API、privileged SQL timestamp rewrite、migrationによるdue化、production user dataは使わない。development smokeの成功をproduction wiringの確認済みとは扱わない。

### 8.2 Production E2E

production deploy後、次のproduction mappingとruntime境界を実測する。

- [ ] production Netlify site / team / branch mapping
- [ ] production Supabase projectとNetlify environmentのmapping
- [ ] actual production domain / HTTPS
- [ ] production cookie / session
- [ ] production active-admin
- [ ] production Storage configuration / RLS
- [ ] `/admin/reports`、exact evidence Routeの認可smoke
- [ ] `/admin/maintenance`へactive-adminだけが到達でき、summary、zero state、confirmation、reloadを非破壊で確認できる
- [ ] physical cleanupがproduction確認に必要な場合だけ、別途承認された専用fixture 1件以下で実施し、既存production dataを対象にしない

- [ ] sign-up / email confirmation
- [ ] login / logout / session refresh
- [ ] password recovery
- [ ] private / followers / public visibility
- [ ] post image upload / display / edit / cleanup境界
- [ ] follow / reaction / comment / search / calendar / notification
- [ ] Exchange invitation / block / entry / image / archive
- [ ] Exchange report submission / moderation / exact evidence
- [ ] third party / non-active / malformed inputのfail-closed
- [ ] §20.5のlogging privacy

production maintenance smokeの標準範囲はroute / authorization / summary / zero state / confirmation / reloadの非破壊確認とする。physical cleanupは別途承認された専用fixture計画がある場合だけ実行し、既存production data、Service Role、Auth Admin API、privileged timestamp rewriteを使用しない。

## 9. Manual maintenance handoff

初回productionのmaintenanceは、active-admin humanが`/admin/maintenance`から1日1回実行する。Netlify Scheduled Functions、Supabase Cron、machine principal、Service Role、Auth Admin APIは使用しない。対象選択はserver-side、実行principalは同じauthenticated admin、最終認可はRLS / Storage RLSである。

通常sign-upはadminを作成しない。production公開前にapproved active-adminが既に存在し、本人が通常loginできることを確認する。adminを準備できない場合はmaintenanceを迂回せず、Production Readiness / Operations Handoffを未完了としてreleaseを停止する。

標準順は`Evidence → Confirmed → Orphan`。各categoryは最大10件 / runで、追加runを同日継続できるのはoutcomeが`success`かつremainingが0より大きい場合だけである。その場合もfull reloadし、current summaryを確認してから新しいrunを実行する。`partial`、`changed`、`unavailable`、explicit failure、`unknown`、summary failure、authorization failureはremainingがあってもこのmulti-run ruleを適用せず、outcome別retry、COI、record、escalation、stop conditionを含めて[`maintenance-runbook.md`](maintenance-runbook.md)の個別handling ruleに従う。特に`partial`は同日retryせず、affected categoryを停止して調査する。

daily manual backlog checkを初回公開のprimary detection mechanismとし、external monitoringとmaintenance history DB tableは必須化しない。operator recordへはenvironment、date / time、category、before / after count、outcome、follow-upだけを残し、ID、path、本文、evidence、raw error、secretを残さない。

## 10. Logs / monitoring / incident

- [ ] Netlify access / function logの取得範囲とretentionを確認した
- [ ] Supabase Auth / Database / Storage logの確認方法と権限を確認した
- [ ] 日記本文、Exchange本文、report evidence、credential、tokenを通常logへ出していない
- [ ] health、5xx、Auth、upload、maintenance failureの監視方法を決定した
- [ ] incident severity、初動、連絡、記録、外部確認の流れを決定した

## 11. Rollback

- Rollback条件: `DECISION REQUIRED`
- Rollback実行者: `DECISION REQUIRED`
- Application deploy rollback手順: `NOT YET VERIFIED`
- DB migrationを伴うreleaseの扱い: `DECISION REQUIRED`

DBを破壊的に戻すことを通常rollbackとしない。既存commitの改変、force push、無断migration repair / resetを行わない。

## 12. Closeout

- [ ] Web release checklistへ証拠と結果を反映した
- [ ] 未完了項目とrisk acceptanceを記録した
- [ ] monitoringとincident ownerへhandoffした
- [ ] rollback判断期限を終了した
