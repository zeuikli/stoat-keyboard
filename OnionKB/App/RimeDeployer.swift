import Foundation

/// 容器 App 端部署（SPEC §17.5）。編譯自訂詞庫 → user/build，鍵盤下次彈出生效（§8.2 L2）。
enum RimeDeployer {
    static func ensureCustomPhraseFile() {
        let url = RimePaths.customPhraseURL
        try? FileManager.default.createDirectory(at: RimePaths.userDirURL,
                                                 withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            let header = "# Stoat 自訂詞庫（詞<Tab>注音碼<Tab>權重）\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 同步阻塞部署；回 true 成功。建議於背景執行緒呼叫。
    static func deploy() -> Bool {
        guard let shared = RimePaths.sharedDir, let prebuilt = RimePaths.prebuiltDir else { return false }
        ensureCustomPhraseFile()
        return RimeBridge.deploy(withSharedDir: shared, userDir: RimePaths.userDir, prebuiltDir: prebuilt)
    }
}
