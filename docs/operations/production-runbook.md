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

production dataを破壊するfixtureや特権操作は、別途承認された安全なtest計画なしに実行しない。

## 9. Logs / monitoring / incident

- [ ] Netlify access / function logの取得範囲とretentionを確認した
- [ ] Supabase Auth / Database / Storage logの確認方法と権限を確認した
- [ ] 日記本文、Exchange本文、report evidence、credential、tokenを通常logへ出していない
- [ ] health、5xx、Auth、upload、maintenance failureの監視方法を決定した
- [ ] incident severity、初動、連絡、記録、外部確認の流れを決定した

## 10. Rollback

- Rollback条件: `DECISION REQUIRED`
- Rollback実行者: `DECISION REQUIRED`
- Application deploy rollback手順: `NOT YET VERIFIED`
- DB migrationを伴うreleaseの扱い: `DECISION REQUIRED`

DBを破壊的に戻すことを通常rollbackとしない。既存commitの改変、force push、無断migration repair / resetを行わない。

## 11. Closeout

- [ ] Web release checklistへ証拠と結果を反映した
- [ ] 未完了項目とrisk acceptanceを記録した
- [ ] monitoringとincident ownerへhandoffした
- [ ] rollback判断期限を終了した
