import Foundation

/// 洋蔥顏文字資料（§36 #3）。由 prebuild 產 kaomoji.json（依 ;N 分組）。
enum Kaomoji {
    static let groups: [(name: String, items: [String])] = {
        guard let url = Bundle.main.url(forResource: "RimeData", withExtension: nil)?
                .appendingPathComponent("shared/kaomoji.json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
        let order = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"]
        var out: [(String, [String])] = order.compactMap { k in dict[k].map { (k, $0) } }
        for k in dict.keys.sorted() where !order.contains(k) {
            if let v = dict[k] { out.append((k, v)) }
        }
        return out
    }()

    static var isEmpty: Bool { groups.isEmpty }
}
