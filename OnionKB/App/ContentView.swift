import SwiftUI

/// 容器 App 設定/狀態占位（SPEC §7.2 SettingsView 的 M0 版）。
/// 完整設定鍵（speechBackend/language/cleanup…，§17.3）待 M6。
struct ContentView: View {
    @State private var keyboardHeight = KBSettings.keyboardHeight
    @State private var fontScale = KBSettings.keyFontScale

    var body: some View {
        NavigationStack {
            List {
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
                Section("純注音與Plus") {
                    Label("加入鍵盤後即可打注音", systemImage: "keyboard")
                    Text("設定 → 一般 → 鍵盤 → 加入新鍵盤 → Stoat")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("提供兩種詞庫版本：純注音（核心字詞）與 Plus（再加 81 萬擴充詞組），分別打包，安裝對應版本即可。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("詞庫 / UserData") {
                    NavigationLink {
                        UserDataView()
                    } label: {
                        Label("我的詞庫 / UserData（看 + 改）", systemImage: "books.vertical")
                    }
                }
            }
            .navigationTitle("Stoat 白鼬注音")
        }
    }
}
