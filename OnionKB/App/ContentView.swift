import SwiftUI

/// 容器 App 設定/狀態占位（SPEC §7.2 SettingsView 的 M0 版）。
/// 完整設定鍵（speechBackend/language/cleanup…，§17.3）待 M6。
struct ContentView: View {
    @State private var keyboardHeight = KBSettings.keyboardHeight
    @State private var fontScale = KBSettings.keyFontScale
    @State private var bopomoEngHint = KBSettings.bopomoEngHint
    @State private var glassKeys = KBSettings.glassKeys
    @State private var options: [SchemaOption: Bool] = Dictionary(
        uniqueKeysWithValues: SchemaOption.allCases.map { ($0, KBSettings.optionDefault($0)) })

    var body: some View {
        NavigationStack {
            List {
                Section("輸入選項") {
                    ForEach(SchemaOption.allCases.filter { $0 != .asciiMode }, id: \.self) { opt in  // 預設英文模式無效（只改引擎不切版面）→ 移除（§92）
                        Toggle(opt.title, isOn: Binding(
                            get: { options[opt] ?? false },
                            set: { options[opt] = $0; KBSettings.setOptionDefault(opt, $0) }))
                    }
                    Toggle("注音鍵顯示英文提示", isOn: $bopomoEngHint)
                        .onChange(of: bopomoEngHint) { KBSettings.bopomoEngHint = $0 }
                    Toggle("iOS 26 玻璃按鍵（Liquid Glass）", isOn: $glassKeys)
                        .onChange(of: glassKeys) { KBSettings.glassKeys = $0 }
                    Text("預設關（原廠實心白鍵 + 灰功能鍵）。實驗性：部分裝置玻璃會偏色，建議維持關閉").font(.footnote).foregroundStyle(.secondary)
                    Text("關閉＝純原廠版面；注音鍵上下划輸入英文（大千＝QWERTY 鍵位）不受此開關影響").font(.footnote).foregroundStyle(.secondary)
                    Text("鍵盤上保留「中/英」鍵可隨時快切；其餘於此設定").font(.footnote).foregroundStyle(.secondary)
                }
                Section("鍵盤高度") {
                    Slider(value: $keyboardHeight,
                           in: KBSettings.minHeight...KBSettings.maxHeight,
                           step: 4) {
                        Text("高度")
                    } minimumValueLabel: { Text("矮") } maximumValueLabel: { Text("高") }
                    .onChange(of: keyboardHeight) { newValue in
                        KBSettings.keyboardHeight = newValue
                    }
                    Text("目前：\(Int(keyboardHeight)) pt（需開「允許完全取用」才會同步到鍵盤）")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("按鍵字體大小") {
                    Slider(value: $fontScale,
                           in: KBSettings.minFontScale...KBSettings.maxFontScale,
                           step: 0.05) {
                        Text("字體")
                    } minimumValueLabel: { Text("小") } maximumValueLabel: { Text("大") }
                    .onChange(of: fontScale) { newValue in KBSettings.keyFontScale = newValue }
                    Text("目前：\(Int(fontScale * 100))%").font(.footnote).foregroundStyle(.secondary)
                }
                Section("注音（內建洋蔥純注音）") {
                    Label("加入鍵盤後即可打注音", systemImage: "keyboard")
                    Text("設定 → 一般 → 鍵盤 → 加入新鍵盤 → Stoat")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("詞庫 / UserData") {
                    NavigationLink {
                        UserDataView()
                    } label: {
                        Label("我的詞庫 / UserData（看 + 改）", systemImage: "books.vertical")
                    }
                }
                Section("狀態") {
                    Text("引擎：librime（洋蔥純注音，內建預編譯詞庫）")
                    Text("注音支援聲韻母亂序、表情/顏文字候選、選項切換與自訂詞庫")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Stoat 白鼬注音")
        }
    }
}
