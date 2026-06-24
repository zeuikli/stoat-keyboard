# Stoat 白鼬注音

iOS 自製**注音輸入法**——以自建 `librime.xcframework` 為引擎，從 macOS Squirrel SPEC 移植，內建洋蔥純注音詞庫，主打「貼近 Apple 原廠手感 ＋ RIME 強大選字」。

- **Bundle**：`com.frost.stoat`（鍵盤 `com.frost.stoat.keyboard`）
- **平台**：iOS 16.0+（iOS 26 視覺特性自動加載）
- **引擎**：librime（自建 xcframework，含 librime-lua + octagram + predict）
- **詞庫**：Onion 純注音 `bopomo_onion.schema.yaml`，預編譯 `.bin` 隨 App 打包

---

## 特點

### 輸入核心
- **聲韻母亂序（free-order）** — RIME 精髓。聲母、韻母、聲調不必照順序打，引擎自動還原正確字。
- **大千鍵位 ≡ QWERTY 實體鍵** — 同一顆鍵服務注音輸入；注音鍵**上下划即輸入英文**（ㄆ↔q、ㄇ↔a、ㄈ↔z…），不必切頁。
- **智慧候選排序** — octagram 語法模型（`contextual_suggestions`）依上下文重排候選，越打越準。
- **預測候選** — 選字後接續預測下一詞。

### 候選體驗（比照原廠）
- **展開候選面板** — 點候選列右側 chevron，鍵盤區展開成**扁平等寬格狀**候選（列間細橫線分隔），再點收合。
- **emoji 候選** — 打「哈哈哈」直接出 🤣。
- **顏文字候選** — 與輸入連動。
- **生僻字 tofu 過濾** — 字型無法顯示（豆腐格）的候選自動濾除。
- 候選無編號、原廠灰 chevron，視覺對齊系統鍵盤。

### 鍵盤版面
- **原廠風格變動高度** — 固定鍵高、總高度隨列數變（注音最高、英文/123 較矮、**按鍵全模式同大小**）。
- **英文 QWERTY 頁** — 對齊 iOS 原廠，含可選常駐數字列。
- **123 數字符號頁** — 半／全形依中英模式自動切換，亦可在設定強制。
- **表情／顏文字面板** — 分類捲動、原廠扁平排版、內建 ⌫（長按連刪）。
- **iOS 26 圓角** — 鍵盤上緣與按鍵採連續（squircle）圓角。
- **Liquid Glass 玻璃按鍵** — iOS 26 可選開關（預設關，原廠實心白鍵/灰功能鍵）。

### 手感細節
- ⌫ 長按**連續刪除**；空白鍵長按**滑動移游標**。
- 中／英快切鍵常駐功能列。
- 原廠按壓高亮動畫（按下即時、放開淡出）。
- 簡繁、全半形、標點切換。
- **第一列快捷列可開關**（⚙）— idle 時的「標點」與「顏文字」兩段各自開/關；兩段全關時連空候選列一併收起、鍵盤自動變矮、不留空白帶。

### 切換手感（對標原廠）
- **不疊加自家動畫** — 高度變更全程非動畫，切 App 不會額外彈跳。
- **轉場交給系統** — 不在系統轉場期重繪介面，純讓系統 snapshot/轉場動畫處理，貼近原廠平順。
- **App resume 後乾淨重套** — 掛 `willEnterForegroundNotification`，回前景後在轉場完成時校正高度。
- 誠實邊界：自訂鍵盤跨進程、只能在首繪後改高，首次呈現的微 flash 為 iOS 系統限制（Apple DTS 證實）、原生無法完全消除；App 切換的卡片動畫亦為系統行為。

### 設定與部署
- **鍵盤內建選項選單**（⚙）— 側載重簽會使 App Group 失效，故選項直接存鍵盤本地，側載也可用。
- **自訂詞庫 / UserData** — 容器 App 內可看可改個人詞庫。
- **免裝機部署** — bundle 內帶預編譯 `.bin`，`prebuilt_data_dir` 直接指過去，裝置端免重建。

### 隱私
- **全程離線**，無網路請求。
- **無語音輸入**（iOS 自訂鍵盤沙盒無法錄音／叫起聽寫，已整段移除）。
- 個人詞庫僅存於裝置本地。

---

## 架構

```
rimeless/
├─ OnionKB/              # Xcode 專案（容器 App + 鍵盤 extension 兩 target）
│  ├─ App/               #   容器 App（設定、詞庫管理、狀態）
│  ├─ Keyboard/          #   鍵盤 extension（KeyboardViewController…）
│  ├─ Shared/Rime/       #   RimeBridge.mm（librime C API 的 ObjC++ 薄包裝）
│  └─ Scripts/           #   package-ipa.sh（unsigned device build → IPA）
├─ RimeData/
│  ├─ shared/            #   schema / 詞庫源（bopomo_onion.schema.yaml…）
│  └─ build/             #   預編譯 .bin（prism / table / reverse）
├─ ios-build/            # librime.xcframework 建置（含 selftest）
└─ SPEC-iOS.md           # 實作日誌與決策真相來源（§1–§91）
```

**資料流**：大千鍵 → keycode → `RimeBridge` → librime → 組字／候選／上字 → UI。
引擎與 UI 以 `RimeEngine` 協定解耦（真 `RimeEngineLibrime` / 後備 `RimeEngineStub`）。

---

## 建置

**模擬器（驗證編譯）**
```bash
cd OnionKB
xcodebuild -project OnionKB.xcodeproj -scheme OnionKB \
  -sdk iphonesimulator -configuration Debug \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

**裝置 IPA（unsigned，側載重簽）**
```bash
cd OnionKB
bash Scripts/package-ipa.sh        # 產出 build/ipa/OnionKB.ipa
```
以 AltStore／Sideloadly 等工具重簽安裝；裝後於
**設定 → 一般 → 鍵盤 → 加入新鍵盤 → Stoat**，並開「允許完全取用」以同步設定。

---

## 文件

- **`CHANGELOG.md`** — 由動工到最新版的時序紀錄，每里程碑附 Debug／設計 Insight。
- **`SPEC-iOS.md`** — 完整實作日誌與架構決策（真相來源）。

---

## 授權

移植自 RIME / librime / Squirrel 生態與洋蔥詞庫；散佈前須處理對應授權（見 `SPEC-iOS.md` §11 授權紅線）。
