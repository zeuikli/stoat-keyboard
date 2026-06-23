import Foundation

/// App Group 共享容器存取（SPEC §9 / §17.1）。
/// group id 集中常數管理——側載重簽可能改寫識別字（§9），故只此一處。
enum AppGroup {
    static let identifier = "group.com.frost.stoat"

    /// 共享容器根；無 Full Access 或重簽改 ID 時回 nil → 呼叫端優雅降級（§9）。
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
