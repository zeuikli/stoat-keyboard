import Foundation

/// Rime 資料目錄解析（SPEC §17.1 / §17.6）。兩 target 共用。
enum RimePaths {
    private static var bundleRimeData: URL? {
        Bundle.main.url(forResource: "RimeData", withExtension: nil)
    }
    /// 源 schema/dict（bundle，唯讀）。
    static var sharedDir: String? { bundleRimeData?.appendingPathComponent("shared").path }
    /// 預編譯 .bin（bundle，唯讀，§5.8）。
    static var prebuiltDir: String? { bundleRimeData?.appendingPathComponent("build").path }

    /// userdb / 自訂詞庫目錄。優先 App Group（容器 App 必有；鍵盤需 Full Access）→ 可共享/可見；
    /// 否則退鍵盤私有容器（學習不跨程序，§3.4）。
    static var userDirURL: URL {
        if let g = AppGroup.containerURL {
            return g.appendingPathComponent("Rime/user", isDirectory: true)
        }
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return lib.appendingPathComponent("rime", isDirectory: true)
    }
    static var userDir: String { userDirURL.path }

    /// 是否走 App Group（容器 App 可見/可改的前提）。
    static var usesAppGroup: Bool { AppGroup.containerURL != nil }

    /// 使用者自訂短語檔（RIME custom_phrase 來源；格式：詞<Tab>注音碼<Tab>權重）。
    static var customPhraseURL: URL {
        userDirURL.appendingPathComponent("bopomo_onion.custom.txt")
    }
}
