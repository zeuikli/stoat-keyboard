import Foundation
import CoreGraphics

/// 洋蔥 schema 的選項開關（switches 見 bopomo_onion.schema.yaml）。兩 target 共用。
enum SchemaOption: String, CaseIterable {
    case asciiMode = "ascii_mode"          // 中文 / 英文
    case fullShape = "full_shape"          // 半形 / 全形
    case asciiPunct = "ascii_punct"        // 。， / ．，
    case simplification = "simplification" // 原體 / 简体
    case emoji = "emoji"                   // 表情候選（§68）
    case kaomoji = "kaomoji"               // 顏文字候選（§69）

    var labels: (off: String, on: String) {
        switch self {
        case .asciiMode: return ("中", "英")
        case .fullShape: return ("半", "全")
        case .asciiPunct: return ("。", "．")
        case .simplification: return ("原", "简")
        case .emoji: return ("🚫", "😄")
        case .kaomoji: return ("🚫", "^▽^")
        }
    }
    /// 設定頁顯示名。
    var title: String {
        switch self {
        case .asciiMode: return "預設英文模式"
        case .fullShape: return "全形標點/字元"
        case .asciiPunct: return "英式標點（．，）"
        case .simplification: return "簡體輸出"
        case .emoji: return "表情候選（哈哈哈→🤣）"
        case .kaomoji: return "顏文字候選（笑→(^▽^)）"
        }
    }
    /// 預設啟用（emoji 比照原廠預設開；顏文字預設關，避免候選過多）。
    var defaultOn: Bool { self == .emoji }
}

/// 共享設定（SPEC §17.3）。經 App Group UserDefaults（容器 App 寫、鍵盤讀）。
/// 無 Full Access 時鍵盤讀不到 App Group → 退回預設值（§3.4 降級）。
enum KBSettings {
    private static var store: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    // 鍵盤高度（§24 #5）
    static let minHeight: CGFloat = 280
    static let maxHeight: CGFloat = 480
    static let defaultHeight: CGFloat = 350
    private static let kHeight = "keyboardHeight"

    static var keyboardHeight: CGFloat {
        get {
            let v = store.double(forKey: kHeight)
            return v == 0 ? defaultHeight : CGFloat(min(max(v, Double(minHeight)), Double(maxHeight)))
        }
        set { store.set(Double(newValue), forKey: kHeight) }
    }

    // 按鍵字體縮放（§27 #3）
    static let minFontScale: CGFloat = 0.8
    static let maxFontScale: CGFloat = 1.5
    private static let kFontScale = "keyFontScale"

    static var keyFontScale: CGFloat {
        get {
            let v = store.double(forKey: kFontScale)
            return v == 0 ? 1.0 : CGFloat(min(max(v, Double(minFontScale)), Double(maxFontScale)))
        }
        set { store.set(Double(newValue), forKey: kFontScale) }
    }

    // 注音鍵角落英文提示（§48）：預設 off＝純原廠版面；上下划英文不受此開關影響。
    private static let kBopomoEngHint = "bopomoEngHint"
    static var bopomoEngHint: Bool {
        get { store.bool(forKey: kBopomoEngHint) }
        set { store.set(newValue, forKey: kBopomoEngHint) }
    }

    // iOS 26 Liquid Glass 功能鍵（§57）：預設 on；僅 iOS 26 生效，可關回原廠灰底。
    private static let kGlassKeys = "glassKeys"
    static var glassKeys: Bool {
        get { store.object(forKey: kGlassKeys) == nil ? false : store.bool(forKey: kGlassKeys) }
        set { store.set(newValue, forKey: kGlassKeys) }
    }

    // schema 選項預設（§27 #1，容器 App 設定、鍵盤啟動套用）
    static func optionDefault(_ opt: SchemaOption) -> Bool { store.bool(forKey: "opt_" + opt.rawValue) }
    static func setOptionDefault(_ opt: SchemaOption, _ value: Bool) {
        store.set(value, forKey: "opt_" + opt.rawValue)
    }
}
