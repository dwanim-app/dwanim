# dwanim — Deferred Work / Backlog

文件版本：v0.1 ｜ 日期：2026-06-24 ｜ 狀態：本地工作清單（隨 `md_files/` gitignore）

> **單一事實來源**，記錄所有「刻意延後 / 尚未做」的實作與決策，避免散落在程式碼註解、
> commit message 與記憶中而被遺忘。完成一項就勾掉或移除；新發現的延後項往這裡加。
> 相關：[ARCHITECTURE.md](ARCHITECTURE.md)（ADR/§12）、[WORKFLOW.md](WORKFLOW.md)、[dwanim-PRD.md](dwanim-PRD.md)。
> autonomous loop 取下一項任務時以本檔 + PRD §11 里程碑為來源。
>
> **定位**：本檔是「**接下來做什麼**」的主任務佇列——挑下一件事以它為準。但它**不凌駕**
> PRD（§8 法律）、ARCHITECTURE（ADR/§12）、WORKFLOW;那三者規範「怎麼做、守什麼」。
> **決策寫進 ADR,不是這裡**——本檔只放待辦/延後項。某項若與 ADR/§8 衝突,以後者為準(或先改 ADR)。

---

## 預設皮膚清單 加入/移除 UX（2026-07-18，user-reported「預設皮膚無法移除歌曲」→ 已實作,待 GUI 驗收）

- [ ] **(延後,非缺陷)金色選取**:唯一可行路徑是把 App 的 **AccentColor 資產設成金色**,但會全 App 影響其他 accent 控制項 —— 當成獨立的視覺主題任務再評估。
- [ ] **接受的 NIT / 延後**:append 也清多選(無害、已註解;要精修可只在 shrink/reorder 清)。gear 選單 ~11 項,未來加項可改子選單。排序標籤少「List」、context menu 無 Invert Selection(與 classic 輕微措辭差)。crop 未接。`listVerticalPadding=8` 經驗值待長清單確認。

## .m3u 開啟支援(2026-07-17,user-reported「Open Audio 打不開 .m3u」→ 已做)

- [ ] **.m3u 讀檔寫死 `.utf8`**:UTF-16/Latin-1 的 .m3u 會被略過(選單與拖放共用限制)。修法:共用的 `expandPlaylist(at:)` 內改 `String(contentsOf:usedEncoding:)` 自動偵測 + utf8 fallback。低優先。
- [ ] **App-tier DropRouter 分類無單元測試**:App target 無 test target(既有狀況);純分類邏輯(skin/playlist/audio bucket)僅 runtime 驗證。`M3UPlaylist.parse` 已在 SkinKit 測。若要補,屬「整個 DropRouter 抽測」的 backlog,非本 delta 阻擋項。
- [ ] **`M3UPlaylist.parse` 相對路徑以 process CWD 解析**(非 .m3u 所在目錄)→ 相對路徑條目變幽靈路徑(播放時略過)。既有 parse 行為,選單/拖放共用;沙箱下相對路徑本就多半不可達。低優先。

## 全 200 皮膚掃描 + X-men_Gambit「白洞」調查（2026-07-17，抽測延伸）

延後項（低優先，皆非回歸、皆與 thumb/merge 無關）：
- [ ] **harness `--png` 對 shaped skin 的呈現**：region 外目前烤成透明→PNG 白底,易被誤判為破圖。改成 region 外畫棋盤格/洋紅底,讓 snapshot 一眼看出是「形狀」而非「白洞」。（本次假警報的直接肇因;純測試工具改善。）
- [ ] **case-collision resolver 一致性**：畸形 archive 同名不同 case 多檔時,background 與 region（及其他 sheet）可能各自選到不同子皮膚。可考慮「同一 winner 來源」一致選取,或至少對 background↔region 尺寸/來源不匹配時 fallback 到無 region。僅影響「一包兩皮膚」的畸形檔;正常 Windows 皮膚無此衝突。`SkinArchiveReviewTests.swift`（Gap 2, ~L69-140）有 stale 註解（寫「never falls back」,但現已實作 fallback loop），順手更正。
- [ ] **〔設計缺口,pre-existing〕App 未實作 region 視窗塑形**：classic 視窗一律矩形,region skin 的圓角/異形外框不生效（該透明的角落顯示為不透明矩形）。與 thumb/本疊無關;windowshape 屬 M-later。

## Phase 2 — 預設皮實機 UX（user-reported 2026-06-25,使用者跑起 app 實機回報）

- **P2-4 icon — 完成（2026-08-28 複查）**:asset catalog
  `App/DwanimIt/Resources/Assets.xcassets/AppIcon.appiconset` 已備齊 **全 10 個 macOS 尺寸**,
  含 1024px 行銷圖（`icon_512x512@2x.png`,實測 1024×1024）;bundle 圖示由 actool 從 catalog
  產生並已在 built bundle 中驗證存在。Finder 大圖不再糊,App Store 行銷圖亦由此取得。
  （repo 內已無手工 `.icns` 來源檔——`project.yml` 的 sources 仍留著排除 `Resources/AppIcon.icns`
  的那行,屬無害殘留,見「## 上架前置與待辦」。）

## A. SkinKit 核心 — 解析層內部延後項

- [ ] **EQ + 播放清單「視窗」sprite 座標**：`SpriteCoordinates.mainWindow` 目前只含主視窗。
      需補 `eqmain.bmp` / `eq_ex.bmp`（EQ 視窗）、`pledit.bmp`（清單視窗）的 sprite rects。
      〔來源：`SpriteCoordinates.swift:22-23` TODO〕。**做的時機**：渲染 EQ / 清單視窗時（M3+）。
- [ ] **provisional sprite 偏移**：部分座標為「夠用但未像素級確認」，待渲染時目視微調——
      playpaus work-indicator〔`SpriteCoordinates.swift:152,154`〕、titlebar 視窗按鈕 x/y、
      `text.bmp` 點陣字 glyph 對應/字元排序。**做的時機**：M2/M3 開視窗能看到時。
- [ ] **`region.txt` 的 `[Equalizer]` / `[WindowShade]` 區段**：目前只解析 `[Normal]`。
      〔來源：`RegionParser.swift:31` TODO〕。**做的時機**：處理 EQ 視窗形狀 / windowshade
      （注意 windowshade 本身在 PRD §7 列為 v2 之後）。
- [ ] **自寫 BMP fallback parser**：ADR-3 的 backlog「保險」。ImageIO 目前 ~100% 覆蓋；
      **僅當野外出現 ImageIO 解不了的真 skin 才觸發**。
- [ ] **設定檔編碼**：loader 用 `.isoLatin1` fallback；真正的 Windows-1252 在 0x80–0x9F 區段不同。
      僅當真實 Font/文字出現亂碼時再處理。
- [ ] **（範圍外，僅備查）** pledit 3 位數 hex / 具名色：格式未用到，除非真實檔需要。

## B. 尚未拍板的架構決策（會 block 其依賴的工作）

- **預設 UI 技術 — 已決:SwiftUI**（M4 拍板,Cadence Phase 1–3 落實,2026-08-27/28）:
  預設臉（`SkinKit/Sources/DwanimItUI`）為 SwiftUI + `PlayerCore`,不走 AppKit/MVC。
  AppKit 僅留在平台殼（`SkinAppKit` 視窗、`NSOpenPanel`、classic `.wsz` 呈現）。此項不再阻擋依賴工作。
- [ ] **模組再拆分**：介面穩後把 `PlayerCore` / `PlaybackKit` / `SkinRender` 從 app target 抽出（ADR-4 暫緩）。

## C. 尚未開工的里程碑（PRD §11）

- **M2 渲染（後半）**：把 `Skin` 畫進視窗。
  - [ ] forward-fit：kbps 真值（async AVAsset，M5）；`BitmapText` 拆成 text/marquee + `BitmapText+Numbers`（M5 render entry 時，§E drawDigits 項一併）。
  - [ ] **region 非矩形視窗** → 拆兩半〔audit〕：純 polygon→coverage 在 `SkinRender`/core（可測）+ 平台視窗形狀
        在 harness（NSWindow mask／CAShapeLayer，去 `.titled`）；**不要把遮罩烤進 bitmap**。
  - [ ] **靜態/動態接縫**〔audit ARCH-MED〕：把 `SkinRender` 的 `overwrite`/blit 提 public，動態內容
        （time 1Hz、跑馬燈、visualizer ~25Hz）局部 patch 已保留 base，別每幀整窗重合成。
        **未開；visualizer（§H）已用整窗重合成出貨，接縫延後 M5 與真 controller 一起做。**
  - [ ] [NIT] `SkinImageView` 自 `SkinRendering.swift` 拆出（harness，可延 M5）；`MainWindowLayout` 的「預設視覺狀態」
        選擇屬 render policy，互動/動態狀態表放 `SkinRender`、不加回 core。
- [ ] **M5 上架**：App Sandbox + security-scoped bookmark；簽章 + 公證；App Store 送審。

## D. 雜項 / 較小

- [ ] `region.txt` 同時用於繪圖裁切與 hit-test 的實作細節（渲染時）。
- [ ] 接近無縫 / gapless 播放的目標水準（做音訊時決定）。
- [ ] `SkinArchive.entryPaths` 每次重算的微效率〔audit NIT〕——只有 profiling 顯示才優化。
- [ ] **typed sprite keys**〔audit ARCH-MED〕：`Skin.sprites` 目前 stringly-typed `[sheet:[name:bitmap]]`，
      正確且 collision-safe，但 typo→silent nil。考慮 typed key（`SpriteID`/enum）或集中字面常數。
      **SkinRender 消費前再決定**（若 string keys 在渲染時易錯就升級處理）。
- [ ] viscolor **24-vs-23 語意**：渲染時確認 palette 應有長度/索引慣例（目前存 raw 陣列 + `visColor(at:)` 安全存取）。
- [ ] config 字體 **CP1252 vs isoLatin1**〔audit NIT〕：僅影響 `Font` 名的 0x80–0x9F 字元；
      `.windowsCP1252` 跨平台可用性待確認，故暫用 isoLatin1。
- [ ] 清理 `*ReviewTests` 內過時註解（誤稱 parser 只 split `\n`、CRLF 會壞——實際已處理）。

---

## E. Render 第二輪 cadence 稽核發現（2026-06-24）

- [ ] **【決策待拍板】region 遮罩做法**：目前實作把 alpha 烤進 bitmap（透明窗顯示），與先前記錄的
      「視窗層級遮罩、不要烤進 bitmap」相左。建議 dev-harness 階段**接受烤 alpha**（可行、保留
      `RegionCoverage.mask` 供 hit-test）、視窗層級遮罩留 M5 真 app；或現在重構。
- [ ] **更正：靜態/動態接縫尚未真正開**——只加了 blit（`SkinCanvas.overlay`），仍缺「保留 base + 局部
      patch / dirty-rect」抽象，且每次 mutate 整桶複製（COW 不友善）。
      **延後：visualizer（§H）已用整窗重合成出貨，接縫待 M5 與真 controller 一起做。**
- [ ] [CONVENTION] `glyphName` 在 core(`SpriteCoordinates`) 與 render(`BitmapText`) 重複且已微異 → core 出 public、render 呼叫。
- [ ] BitmapText 靜態字串；跑馬燈需 scroll offset + 部分字元裁切；`drawDigits` 抽出供 kbps/kHz 重用。
- [ ] ARCHITECTURE §3.6 過時（仍稱 SkinRender 用 AppKit）→ 更新為純 Foundation 像素合成、視窗形狀在 harness。
- [ ] `MainWindowLayout` 漸含 render policy → M1/PlayerCore 邊界時把「狀態→顯示」移出 core。
- [ ] **防 drift**〔audit ARCH-MED〕：harness `CGPath` 與 `RegionCoverage.mask` 是兩套 polygon→shape，
      加交叉檢查守護（以 `RegionCoverage.mask` 為基準），避免 PNG 對、視窗錯而無人察覺。
- [ ] **hit-test 前**〔audit ARCH-MED〕：把 skin↔layer 座標轉換（scale、no-flip）抽成共用純 helper
      （SkinRender/core），別留 harness-only——點擊命中是它的逆轉換。
- [ ] **M5 前**：把 harness 的「compose + text + time + mask」render recipe 收進可重用的 SkinRender 入口，免真 app 重抄。

## F. M1 音訊 — 完成 + forward-fit（2026-06-24，branch `feat/m1-audio`）

- **forward-fit（M1 稽核建議，延後）：**
  - [ ] **M3 FFT tap**：獨立 `AudioTapProviding` 協定（`[Float]`+sampleRate 回呼），`AVAudioEnginePlayer` 橋接
        `mainMixerNode.installTap`；visualizer 經 shell 直接消費，PCM **不經** `PlayerCore`。
  - [ ] 引擎**狀態/錯誤回呼**（`onStateChange`/`PlaybackEngineState`）；別再 `try?` 吞 `engine.start()`（目前僅記 `lastStartError`）。
  - [ ] **balance / pan**：M1 未做（PRD §3.2 列為狀態）；之後鏡射 volume + player-node pan。
  - [ ] **strict concurrency**：`PlayerCore` `@MainActor` + 回呼 `@Sendable`（Swift 6 前，~M5）。
  - [ ] harness 的 engine+core+run-loop 組裝 → M5 收進可重用入口（同 render recipe）。
  - [ ] `formatTimecode` 與 `BitmapText.drawTime` 的「秒→分秒」共用一個 helper（M3 時間顯示時）。
- [ ] FFT 頻譜 **visualizer 本身** → M3（非 M1）。

## G. 互動（skin 控制播放）— 完成 + forward-fit（2026-06-24，branch `feat/m1-audio`）

- **forward-fit（延後）：**
  - [ ] toggle 的 **on/off pressed 美術**（目前都用 off 變體；`SkinControl.spriteName` 留了 TODO）。
  - [ ] harness 重繪改 **`@Observable` 驅動 + 靜態/動態 patch**（別每 tick 整窗重合成；M5 與真 controller 一起，見 §H）。
  - [ ] **M5**：把「compose+text+mask + 點擊控制」收成可重用的 classic-skin Renderer/Controller 入口（harness 是 throwaway）。
  - [ ] harness NIT：`SkinImageView` / `fail` / `--scale` 在各 mode 重複，可抽共用。

## H. M3 頻譜 visualizer — 完成 + forward-fit（2026-06-24，branch `feat/m3-visualizer`）

- **forward-fit（延後）：**
  - [ ] **viscolor 頻譜索引語意**：classic `viscolor.txt` 的 spectrum bar 色 / peak dot / 背景是**固定索引**，非整條漸層；目前 M3-lite 用整 palette 漸層。需文件化真實索引對應 + 補 peak-dot 繪製（目前無）。〔取代 M3-lite 漸層；非 §D line 71 的「長度」議題〕
  - [ ] **靜態/動態接縫**：visualizer 目前每 tick（~25Hz）整窗重合成 275×116（dev-harness 可接受）；真 app 改 `@Observable` 驅動 + 局部 patch（保留 base、只補 vis/time 區），與 M5 controller 一起做。
  - [ ] **lift `LatestSamples`→純 `SpectrumFeed`**：tap-stash holder 是純 Foundation+NSLock、可重用；M5 controller 抽出時一併，只留 tap-install + timer 在平台殼。
  - [ ] `SpectrumAnalyzer` 主執行緒隔離（`@MainActor`）併入 §F strict-concurrency。
  - [ ] `visualizationFrame`(24,43,76,16) 與導出的 barCount 為 provisional，渲染時對真 skin 微調。
  - [ ] [nit] `LogFrequencyBands` 的 static/stored `minFrequency` 影子，可清。

## I. 全 codebase 稽核（2026-06-24，branch `fix/audit-findings`）

- **稽核點出、仍待辦（非 bug）：**
  - [ ] **even-odd vs non-zero 不一致**：`RegionCoverage`（even-odd，PNG）與 `RegionMaskLayer`（nonZero，窗）兩套 fill rule;§E 的「防 drift」交叉檢查應斷言**形狀相等**並挑一個 rule 統一（hit-test/region 硬化前）。
  - [ ] [nit] 第三份「秒→MM:SS」在 `InteractiveController.redraw`（併入 §F 的 helper 整併）；`FakePlaybackEngine` 在兩個 test target 各一份（暫不抽）。

## J. Sprite 座標 vs 真實 sheet 尺寸 — 稽核發現（2026-06-24，branch `fix/balance-slider-width`）

- [ ] **[TEST-GAP，可能還有同類 bug] fit test 是循環的**〔本次暴露〕：`SpriteCoordinatesFitTests` 拿宣告值去比對**自己寫死的字面常數**、不讀任何真 sheet，所以「宣告 vs 真實 sheet 尺寸」的不符它一律抓不到——balance 就這樣漏掉。**其他 sheet 也可能有同類不符**。後續：寫一個用真實（或代表性合成）sheet 解碼尺寸來驗證**所有** sprite rect 的測試／稽核。
- [ ] **缺 balance.bmp 的 fallback**：200 個裡 9 個沒 balance.bmp；格式既定 fallback 是改用 volume.bmp，目前我們什麼都不畫 → 渲染層補 fallback。
- [ ] **退化/超界 sheet**：S.E.wsz 的 balance 46 寬（47 仍越界，原本 68 也壞、非回歸）；1x1 佔位、單列 13/14px 高 strip 被 15px frame 假設誤服務。罕見、先記。
- [ ] **更根本**：sprite 寬度其實**逐 skin 不同**（balance 47 vs 68），靜態座標表無法同時完美貼合；47 是「都在界內」的安全最小公分母，真正正解是**依實際 sheet 尺寸自適應裁切**（M5 渲染層再做）。

## K. 全 sheet 座標 vs 真實尺寸稽核（2026-06-24，branch `fix/slider-height-overrun`）

- [ ] **posbar.bmp 短條（2–9px 高）~9% 失去 track**：刻意**不改 rect**（307×10 是 canonical，縮了會弄壞 96.5% 多數）。
- [ ] posbar 短條 + volume 2px 的**根本解（cutter 高度越界改 clamp）→ 移到 §Z（很久以後再修，使用者拍板）**。

## Z. 很久以後再說（低優先、非里程碑；目前狀態可接受）

> 確認過「現狀可接受、影響只在少數 skin 或極細微」的事，刻意擺到很遠的未來。挑近期任務時跳過這區。

- [ ] **`SpriteCutter` 高度越界改 clamp（而非丟棄）**〔使用者 2026-06-24 拍板：很久以後〕：遇到「只是高度超出 sheet」的 rect，裁到可用列再用，而非整個丟。一次解掉 §K 的兩件事——posbar 短條（2–9px）失去 track、以及 volume/balance 那個把最後一格 cap 到 418 的 2px 取捨——外加任何「差幾 px」的近差 sheet。需改 `SpriteCutter` 契約 + `SpriteCutterTests`（目前是「越界即 skip」），屬**跨切面**變更、影響所有 sprite，要慎重。更徹底的同路解是 §J 的「依實際 sheet 尺寸自適應裁切」（M5 渲染層）。理由可擺很久：受影響都是少數 skin、純 cosmetic，volume 那 2px 是最高格底部最不顯眼的一條、使用者確認不會被發現。

## L. M4 預設皮（DwanimUI）— 完成 + forward-fit（2026-06-24，已 merge 進 main）

- **forward-fit（延後,多數 M5）：**
  - [ ] **mark 樣式**：使用者可再 steer「公羊角」味道（盲調第二版;geometry 獨立、易改）。
  - [ ] **共用 transport 詞彙（M5）**：classic 走 `PlayerControl.apply`、default 直接呼叫 `PlayerCore`,語意重疊小但會 drift;M5 把 control→PlayerCore 映射抽成 **SkinRender-free** 共用層,兩 UI 共用一套受測詞彙（default 也還沒接 shuffle/repeat）。
  - [ ] **harness controller/feed lift（M5）**：`DefaultSkinMode` 的 controller + `LatestSamples` + timer 與 `InteractiveMode` 重複;把 spectrum/clock-feed glue 抽出 harness 成可重用。
  - [ ] **`PlayerCore @MainActor`（M5 strict-concurrency,併 §F）**：目前主執行緒存取靠慣例;`PlayerViewModel` 已 `@MainActor`,`PlayerCore` 未;strict-concurrency pass 對齊。
  - [ ] **.icns / asset catalog（M5）**：icon 美術已 render,裝配需 Xcode app target。
  - [ ] [nit] `DwennimmenMark` 對稱測試只驗 bounding-box（非逐點）;`fitTransform` 負/NaN rect belt-and-suspenders;`SpectrumBars` bar 數對齊寬度;argv dispatch 用 leading flag。皆非阻斷。
  - [ ] **seek 拖曳**：進度條目前唯讀,拖曳 seek 未接（同 volume/balance 拖曳）。

## M. 播放清單（PLEDIT,可換皮）— 進行中（2026-06-24,branch `feat/m3-playlist`）

- **待辦（增量 4 + 收尾）：**
  - [ ] 互動：**點按播放**曲目、滾輪慣性手感修正、（可選）拖曳調大小（composer 已支援任意尺寸,差視窗 resize 接線）。
  - [ ] **標題列微調**：填充目前取到 skin 內建標題字、平鋪重複;正解 = 平鋪純紋理 + 標題顯示一次（sprite 座標 + composer 加 centered-title）。
  - [ ] [M5] harness **四**視窗模式（Interactive/DefaultSkin/Playlist/EQ）的 controller + scaled-NSView + window-delegate teardown 重複 → 抽共用 base（M5 真 controller lift 時做）。
  - [ ] [nit] 外框 corner/edge 寬度不對稱（provisional 幾何,真實 pledit 封裝定了再調）。
  - [ ] [nit,cadence audit 2026-06-25] resize 到「非 scale 整數倍」高度時,外框 bitmap 拉伸填滿 vs 文字在 `skinHeight*scale` 空間排版,最多差 (scale-1)px 的 cosmetic 垂直漂移(非選取 bug,點擊/落點皆正確)。正解:resize 時把視窗 content 高度 snap 成 scale 整數倍(或外框畫進 `skinHeight*scale` 矩形而非 full bounds）。

## N. EQ 等化器（真 DSP + 可換皮視窗）— 完成（2026-06-25,已 merge）

- **forward-fit（延後）：**
  - [ ] AUTO on-state（無 auto-preset 旗標,目前畫 off;**點擊也是刻意的靜默 no-op**——
    model 無 auto-preset 概念,待 preset/EQF 一起做）。
  - [ ] EQ 視窗拖曳調大小（固定 275×116）;eq_ex.bmp windowshade。
  - [ ] preset/EQF 載入 + 文字顯示。

## M5 上架（App Store）— 前置進行中（2026-06-25 起）
- [ ] [polish] 經典窗保活時、預設臉暫無法重開 → 加 View/Window 選單項重新呈現(NIT)。
- [ ] [follow-up,非 bug] graduate 到 Swift 6 語言模式（`.swiftLanguageMode(.v6)` / `SWIFT_VERSION 6.0`,需 bump tools-version 6.0）→ 讓 race 警告變**硬錯誤**(CI guard);目前 Swift 5 模式為 warning-level。

**卡 Apple 帳號（M5 本體）:** 不需帳號的腳手架**全部備好**（merge `ad60259`;見 `md_files/SHIPPING.md` runbook）;剩下純帳號操作:
- ⑦ 帳號設定 — **拆成兩半（2026-08-28）**:
  - [~] **Team ID / `DEVELOPMENT_TEAM` — 進行中(同批另一 agent 接線中)**:Team ID `7GRD9Y5U7W`
    寫進 `App/project.yml`(`DEVELOPMENT_TEAM` + `CODE_SIGN_STYLE: Automatic`)與
    `App/ExportOptions-AppStore.plist` / `App/ExportOptions-DeveloperID.plist` 的 `teamID`,
    取代原本的 `REPLACE_WITH_YOUR_TEAM_ID` 佔位字串。Team ID 非機密(每個簽章 binary 內都有),
    故可入庫。完成後 archive/export 指令**無需再帶簽章參數**。
  - [ ] **portal 帳號操作（仍未開始）**:
    - [ ] 在 Apple Developer portal 註冊 **explicit** App ID `app.dwanim.dwanimit`（不可 wildcard,
      否則 App Sandbox / provisioning 不成立）。
    - [ ] 建立 **macOS 專用**憑證(iOS 那組不通用):**Mac App Distribution**
      (`3rd Party Mac Developer Application`,簽 .app)+ **Mac Installer Distribution**
      (`3rd Party Mac Developer Installer`,簽 .pkg)——上架**兩張都要**;另 Mac App Store
      provisioning profile。(Developer-ID 備援路線另需 Developer ID Application 憑證。)
    - [ ] 在 **App Store Connect** 建立 app 紀錄:My Apps → + → New App → **macOS** →
      綁 `app.dwanim.dwanimit` → 名稱「dwanim it」。上傳前必須先存在。
    - [ ] 確認 **Paid Applications 合約 / 稅務 / 銀行**狀態(iOS app 有 live IAP,理應已完備
      → **只需驗證,非阻擋**),並把 app 設為付費;**價格級距尚未決定**。
- [ ] ⑧ `xcodebuild archive` → exportArchive(選對 plist,macOS 產出的是 **`.pkg` 不是 `.ipa`**)
  → 用既有 App Store Connect API key 上傳(`xcrun altool --upload-app --type macos`,
  **注意是 `macos` 不是 `ios`**)→ 送審 / 或 notarytool+stapler 直發。(照 SHIPPING.md PART B)

## 全面複查 3（2026-06-25,M5-prep 後,539 測試）

- **延後（非 bug）:**
  - [ ] [ARCH-MED] Interactive/EQ controller 非 `@MainActor` → M5 strict-concurrency pass 時與 PlayerCore + 四 controller **一次統一**（auditor 因組合提高優先序,仍建議一次做）。
  - [ ] [polish] 關預設視窗會退 app 即使經典皮視窗開著（單視窗模型合理行為;⑥b-4 時可細調）。

## 經典主視窗控制全接線（2026-06-27,577→608 測試,feat/classic-controls-full）

**延後（非 bug,本任務刻意不做,已於程式碼註記）:**
- [ ] [feature-LARGE] windowshade/collapse 模式 — 整個新的 compose path + shade layout 表
  (compact ~275x14 face + mini time/vis) + 視窗 resize + region-mask 換 + 摺疊狀態 model。
  與已延後的 EQ `eq_ex.bmp` windowshade 同級。SkinControl/SpriteCoordinates 已註記。
- [ ] [defer] kbps bitrate(引擎 `loadedBitrateKbps` 仍 0,待 M5 async `AVAsset.load(.estimatedDataRate)`)。
- [ ] [defer] clutter-bar 按鈕(option/A/I/D/V 選單、always-on-top 等)未建模。

## 手修批次 + PLEDIT 底欄增量（2026-07-16,branch `feat/pledit-buttons`）

**延後項（本增量刻意不做）:**
- [ ] **Add URL…** — sandbox **無網路權限**（entitlements 刻意只有 user-selected read-write +
  bookmarks;見 M5 前置「無網路權限」決定）,串流/URL 曲目屬範圍外;若未來要做需先翻 M5
  的 no-network 決策。
- [ ] **File info…** — 曲目資訊對話框未建模。
- [ ] **sprite-menu authentic 變體** — 底欄選單目前用**原生 NSMenu**;classic 的
  sprite 繪製選單（pledit.bmp 選單美術）留待後續。
- [ ] **shift range-select** — 清單目前單選/雙擊播放;shift 連續範圍選取未接。

## 整合稽核殘餘 lower 項（2026-07-17,temp/merge-staging 整合閘,無 must-fix）

- [ ] **EQ 停靠推移無螢幕邊界夾限**:主窗貼近螢幕底時開 EQ,被推移的播放清單可能整個落到螢幕外(borderless 窗無法自行拖回;可 ⌘⇧D 或重開復原)。修法:`ClassicSkinPresenter.dock/push-down` 以 anchor 螢幕的 `visibleFrame` 夾限。
- [ ] **播放清單選取集以「位置」而非「曲目身分」修剪**:清單外部突變(host append、上方列被移除)後,高亮停在位移後的列直到下一次點擊(cosmetic;窗內編輯會自行重建選取)。與 reorder-selection parity 同批處理。
- [ ] **〔pre-existing,M1 起就在 main〕暫停中換清單引擎殘留舊檔**:`PlayerCore.load(_:)` 只在 `isPlaying` 時停引擎;暫停狀態下 LIST OPTS > Open List 換清單後,舊曲的凍結時間/時長仍顯示直到按播放。修法:`load()` 一律 `engine.stop()` + 清 pausedTime。非本疊回歸,下輪處理。

## 音量/平衡滑塊 thumb（2026-07-17,user-reported,已修）

- [ ] 待眼球:某個裁切到 418/419 的真皮上「只有軌道無旋鈕」的降級外觀是否可接受（headless 測不到)。

## Phase-4 預設臉（Cadence）redesign — 刻意延後（2026-08-28，cadence review，0 must-fix）

**延後項（皆非缺陷，Cadence Phase-4 刻意不做，已於程式碼註記；`DwanimItUI` 維持純 SwiftUI + PlayerCore，下列 App-tier 項需 AppKit 故不在此層做）：**

- [ ] **P3 — 精準毛玻璃背板**：設計稿的 `blur(48px) saturate(1.6)` frosted backdrop 目前以 SwiftUI `.ultraThinMaterial` 近似（純 SwiftUI 可得的最接近值）。正解 = App-tier 包一個 `NSVisualEffectView` representable（含自訂 blur radius / saturation）注入為背板。屬平台殼工作，`DwanimItUI` 不引 AppKit。
- [ ] **P4 — 自訂視窗投影**：設計稿的 `0 30px 70px rgba(0,0,0,0.62)` drop-shadow 目前用 AppKit 預設視窗陰影。正解 = 透明視窗留邊界 margin + layer shadow（App tier）畫出精準柔和大陰影。與 P3 同屬平台殼。
- [ ] **C1 — visualizer 遮蔽時暫停驗證**：預設臉被 classic `.wsz` 皮覆蓋（藏於其後）時，visualizer 應停止燒幀——目前倚賴 `TimelineView(.animation)` 於視窗遮蔽時自動暫停。需驗證/守護：若實測仍持續重繪，改由 App 層向下 thread 一個 `paused` flag 到 `CadenceVisualizer`。
- [ ] **C2 —（選配）idle visualizer 重繪節流**：idle（無訊號）時目前以全 display-rate（60/120fps）重繪，屬刻意設計。可選加 `TimelineView(.animation(minimumInterval: 1/30))` 上限以省 idle 能耗；非必要，做前先確認手感不受影響。

*本文件隨開發演進更新。*
