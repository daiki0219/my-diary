# iOS Release Readinessチェックリスト

> [!IMPORTANT]
> この文書は将来のiOS公開準備用です。現在の状態は`NOT STARTED`です。
> Apple等の具体的な要件はiOS公開準備時点の最新公式資料で確認し、現時点の記憶や推測を固定仕様にしません。

## 1. External verification

- [ ] iOS公開準備時点の最新Apple公式資料を確認した
- [ ] 使用したsource、version / 更新日、確認日を記録した
- [ ] App Store review要件とProduct Requirementのgapを記録した
- [ ] 必要に応じて公式窓口・専門家へ確認した

## 2. Product safety / UGC

- [ ] general account deletionの実装要否と最新要件を照合した
- [ ] Exchange participant削除semanticsが既存仕様どおり維持されている
- [ ] global user blockの必要性と必要範囲を最新公式資料と照合し、必要な場合は設計・実装・確認した
- [ ] Exchange invitation blockをglobal blockの代替にしていない
- [ ] 通常post / comment / user reportを確認した
- [ ] Exchange reportと通常SNS reportを区別した
- [ ] moderation queue、evidence、takedown、appeal等の必要範囲を確認した
- [ ] reporter privacy、exact evidence、whole-diary bypass禁止を維持した

## 3. Privacy / legal / user support

- [ ] Privacy PolicyをiOS提供内容と整合させた
- [ ] App Privacy等のprivacy申告要否と内容を確認した
- [ ] data collection / external transmission / provider flowをiOS client込みで再確認した
- [ ] 問い合わせ導線をApplication内から利用できる
- [ ] 削除申出・権利侵害申出の導線と運用を確認した
- [ ] 未成年者方針とage / ratingを最新要件へ照合した

## 4. Authentication / account

- [ ] 既存email / password、recovery、Google / Apple login仕様とiOSの最新認証要件を照合した
- [ ] Sign in with Apple等の要否を最新公式資料で確認した
- [ ] callback / deep link / session / logout / recoveryを確認した
- [ ] non-active accountとaccount deletionのfail-closed境界を確認した

## 5. Architecture / security

- [ ] native / WebView / hybrid等のApplication UX方式をarchitecture Phaseで決定した
- [ ] 単純なWebView wrapperだけを前提とせず、iOS上の適切な体験をreviewした
- [ ] Supabase Auth / Postgres / RLS / Storage / RPCの共有境界を文書化した
- [ ] native clientでもRLSを最終認可とし、client user IDを信頼していない
- [ ] Next.js Server Action / component / Tailwind / Route Handlerの非共有境界を設計した
- [ ] secret、publishable information、keychain / device storage等の扱いをreviewした

## 6. App quality / pre-release

- [ ] supported device / OS / orientationを決定した
- [ ] accessibility、keyboard、screen reader、contrastを確認した
- [ ] network loss、retry、unknown outcome、background / resumeを確認した
- [ ] production backendで主要E2Eを確認した
- [ ] crash / error / performance / production monitoringを確認した
- [ ] TestFlight等のpre-release確認を完了した
- [ ] App Store提出物とreview用情報を確認した

## 7. Premium / IAP

- [ ] digital premium機能をiOS Application内で販売するか決定した
- [ ] 販売する場合、開始時点の最新platform課金要件を確認した
- [ ] 販売しない場合、対象外の根拠を記録した

このchecklistはpremium / IAPを現在の実装対象へ昇格させない。

## 8. Release decision

- [ ] 未完了項目、external verification、risk acceptanceを記録した
- [ ] Product、Security、Privacy、Operationsのownerが承認した
- [ ] iOS公開可能と判断した
