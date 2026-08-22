# my-diary Design Direction v1.0

## 1. この文書の位置づけ

この文書は、my-diaryの初回公開に向けたDesign Polishで使用するデザイン基準を定める。

正式なプロダクト仕様、認証・認可、DB、RLS、Storage、機能要件を変更する文書ではない。

機能仕様についてはrepository内の最新正式仕様と現在の実装を正とする。

この文書と参考画像は、主に以下を統一するためのvisual referenceである。

- 色
- typographyの雰囲気
- surface
- card
- radius
- shadow
- spacing
- navigationの見せ方
- responsive時の構成
- my-diaryらしい全体のtone

---

# 2. Design Concept

my-diaryのデザインコンセプトは：

**「ゆるく、あたたかく、日記らしく。」**

とする。

キーワード：

- ゆるい
- やわらかい
- 暖かい
- 親しみやすい
- 落ち着く
- 日記らしい
- 気負わず使える
- 長く読んでも疲れにくい

SNSらしい刺激の強さや、業務システム的な硬さは避ける。

サービスの中心はあくまで「日記を書く・読む・振り返る」体験とする。

---

# 3. Approved Reference Images

## Mobile

```text
docs/design/references/home-mobile-reference.png
```

スマートフォン版Homeの基準デザイン。

主に以下を参考にする。

- warm ivory / creamのbackground
- handwritten feelingの`my-diary` logo
- 暖色系のprimary CTA
- 枝・小花のmotif
- 大きめだが過剰ではないradius
- soft surface
- borderを強調しないcard
- warm brown系text
- feedを主役にした縦方向layout
- bottom navigation
- mobileでのゆったりしたspacing

MobileではHome内にCalendar widgetを追加することを、この画像だけを理由には要求しない。

Calendarは既存のCalendar導線・画面を維持する。

---

## Desktop

```text
docs/design/references/home-desktop-reference.png
```

PC版Homeの基準デザイン。

主に以下を参考にする。

- Mobileと共通した色・font tone・surface
- top navigation
- main feed + secondary sidebarのdesktop layout
- 十分な横幅と余白の利用
- profile summaryなどの補助情報を主役にしすぎない構成
- Calendarをdesktopで見つけやすくする構成
- 右columnを使った情報整理
- cardを増やしすぎず、視線の優先順位を明確にする

Desktopでも日記feedを主役とする。

Sidebarは補助領域であり、feedより強く見せない。

---

# 4. Reference Image Rule

参考画像はpixel-perfect implementation specificationではない。

画像から採用するもの：

- design language
- visual hierarchy
- composition
- spacing感
- color direction
- typography direction
- card / button / navigationの見せ方
- responsive layoutの考え方

画像から自動的に採用してはいけないもの：

- repositoryに存在しない機能
- 新しいDB field
- 新しいroute
- 新しいmutation
- 新しいnotification
- bookmark機能
- favorite機能
- draft機能
- memo機能
- profile handle
- 新しいstats
- その他、画像生成時に例示として描かれただけの機能

**Reference Image is not Feature Specification.**

画像と現在の正式仕様・repositoryが異なる場合は、正式仕様とrepositoryを優先する。

新機能が必要に見える場合はDesign Polishへ混ぜず、別途提案する。

---

# 5. Color Direction

基本palette：

- warm off-white
- ivory
- cream
- soft beige
- muted apricot
- terracotta
- very soft coral
- warm brown

背景を真っ白一色にしない。

cardもpure whiteだけに依存せず、backgroundとの微妙なsurface差を利用する。

primary actionは暖色系solidを使用する。

ただし白文字を使用するprimary backgroundは、通常文字でWCAG AAのcontrastを満たす濃さにする。

既存Auditで確認された`orange-600 + white`相当のcontrast不足をそのまま維持しない。

danger / destructiveは通常のbrand orangeとは区別する。

success / warning / errorは意味を失うほど暖色へ統一しない。

---

# 6. Typography

全体の印象：

- 柔らかい
- 読みやすい
- 少し日記らしい
- 手書き感を過度に使わない

`my-diary` brand logoにはreferenceのような手書き感を許可する。

一方、日記本文・form・admin UIでは可読性を最優先する。

reference imageのfontを完全再現するためだけに、新しい外部font serviceやdependencyを導入しない。

まず既存環境で安全に実現可能なfont stackを使用する。

新しいfont導入が必要な場合は別途判断する。

bold / semiboldを画面全体へ多用しない。

以下のhierarchyを明確にする。

- page title
- section title
- diary title
- diary body
- username
- label
- metadata
- helper
- badge

日記本文は十分なline-heightを確保する。

---

# 7. Surface / Card

現在の「白card + border」の反復を減らす。

基本：

```text
warm page background
↓
soft surface
↓
必要な場所だけsubtle border / shadow
```

とする。

すべてのpanelをborderで囲まない。

cardはreference imageのように：

- soft background
- large-to-medium radius
- very subtle shadow
- comfortable padding

を基本とする。

nested cardを必要以上に作らない。

---

# 8. Radius

丸みはmy-diaryらしさとして維持する。

ただし、すべてをpill shapeにはしない。

目安：

- page / large card: large radius
- form / small card: medium radius
- button: medium〜large radius
- tag / badge: pill可
- tiny actionすべてをpill化しない

---

# 9. Shadow / Border

shadowは装飾ではなくsurface separationのためだけに使う。

強いshadowは禁止。

borderも必要箇所だけ使用する。

特に：

- card inside card
- alert inside card
- gallery inside card
- form inside card

でborderが何重にも見えないようにする。

---

# 10. Primary Action

「日記を書く」はサービスの主要CTAである。

reference imageのように：

- 暖色solid
- 十分なtouch target
- 高い視認性
- やわらかいradius
- 明確なfocus state

を持たせる。

ただし常に巨大表示する必要はなく、画面contextに応じて適切なsizeへ変える。

---

# 11. Buttons

semantic variantを基本とする。

- primary
- secondary
- neutral
- destructive
- text / quiet action

同じ意味のbuttonを画面ごとに別styleへしない。

solid buttonを増やしすぎない。

画面内のすべての操作を同じ強さで見せない。

---

# 12. Forms

input / textarea / selectは：

- 16px以上を基本
- warm neutral surface
- subtle border
- clear focus state
- sufficient contrast
- comfortable padding

とする。

validation、pending、disabled、success、errorの意味はvisual polish後も維持する。

---

# 13. Tags / Mood

Tagは淡い暖色surfaceのchipを基本とする。

Moodは既存の：

```text
emoji + text
```

を維持する。

色だけで意味を伝えない。

派手なcategory color systemへ拡張しない。

---

# 14. Branch / Flower Motif

reference imageにある、小さな枝・小花のmotifをmy-diaryのvisual accentとして採用する。

使用目的：

- Home hero
- empty state
- auth page等の小さなaccent
- 必要に応じたsection decoration

使用しすぎない。

すべてのcardへ装飾しない。

日記本文より目立たせない。

Admin / Maintenanceでは原則として装飾を控える。

---

# 15. Mobile Direction

中心viewport：

```text
360px〜390px
```

Mobileではfeedを主役にする。

基本構成：

```text
brand / utility
↓
gentle hero
↓
日記を書く
↓
following / latest
↓
diary feed
↓
bottom navigation
```

reference imageのように縦方向へ自然に流す。

Home上部へ多数の機能menuを積み重ねない。

主要機能への移動はnavigationへ整理する。

最終保証viewport：

```text
320
360
375
390
1280
```

---

# 16. Desktop Direction

DesktopではMobile layoutを単純に横へ引き伸ばさない。

基本：

```text
top navigation

main feed
+
secondary sidebar
```

の2-column構成を基準とする。

Main feedを広く、sidebarを狭くする。

sidebar候補は、**既に実装されている機能だけ**から選ぶ。

CalendarはDesktop sidebarとの相性がよいため、既存Calendar data / navigationを利用できる範囲で優先候補とする。

profile summaryも既存情報で安全に構成できる場合は候補とする。

referenceに描かれた「最近のメモ」等、未実装機能は追加しない。

---

# 17. Navigation

MobileとDesktopで情報architectureそのものを別物にしない。

Mobile：

- compact navigation
- bottom navigationを有力候補とする

Desktop：

- top navigationを有力候補とする

ただし既存routing、query parameter、back / forward、deep linkを壊さない。

navigation全面再設計はDesign Polishの範囲を超えて行わない。

---

# 18. Profile Numbers

投稿数・following・followers等の数字を競争的に強調しすぎない。

表示が必要な場合でも：

- text hierarchyを抑える
- large bold numberを主役にしない
- diary contentより目立たせない

という原則を守る。

---

# 19. Empty / Error / Success

Empty stateは冷たいsystem messageだけにしない。

- 余白
- 短くやさしい説明
- 必要なら控えめな枝motif
- 明確な次action

を利用する。

Error / warningは意味を薄めない。

「やわらかいデザイン」と「危険性が分かりにくいデザイン」を混同しない。

---

# 20. Exchange Diary

Exchange Diaryも同じDesign Systemを使用する。

別アプリのような見た目にしない。

ただし：

- diary content
- participant action
- archive
- delete
- report
- safety operation

のvisual hierarchyは明確に分ける。

安全操作を可愛く装飾しすぎない。

---

# 21. Admin / Maintenance

Adminも別Design Systemを作らない。

一般画面と：

- typography
- spacing
- radius
- surface
- base colors
- form style

を共有する。

ただし：

- status
- evidence
- destructive action
- maintenance
- unknown outcome
- error

は判断性を優先する。

枝・花などのdecorative motifは基本的に使用しない。

---

# 22. Accessibility

Design Polishで既存accessibilityを後退させない。

特に：

- text contrast
- keyboard
- focus-visible
- labels
- heading hierarchy
- role=alert
- role=status
- aria-live
- confirmation focus
- Escape
- focus return
- touch target
- color-only state禁止

を維持・改善する。

primary CTAのcontrastは必ず実測する。

---

# 23. Implementation Principle

Design Polishはvisual / presentation改善を中心とする。

原則として行わない：

- DB変更
- migration
- RLS変更
- Storage変更
- Auth仕様変更
- Exchange仕様変更
- 投稿仕様変更
- 新機能追加
- navigation全面再設計
- package追加
- 新しい外部service導入

実装は小Phaseへ分割する。

---

# 24. Final Goal

my-diary全体が、

**「開くと少しほっとして、気負わず日記を書きたくなる場所」**

に見えることを最終的なvisual goalとする。

派手さよりも：

- 温かさ
- 読みやすさ
- 余白
- 安心感
- 一貫性

を優先する。