import Foundation

/// 漢字 → 大千碼 轉換（SPEC §29 #2）。表由 prebuild 產生、bundle 於 RimeData/shared/han2code.json。
enum Han2Code {
    private static let table: [String: String] = {
        guard let url = Bundle.main.url(forResource: "RimeData", withExtension: nil)?
                .appendingPathComponent("shared/han2code.json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }()

    static var isLoaded: Bool { !table.isEmpty }

    /// 詞 → 大千碼（逐字串接，含 tone1 尾空白）。回 (碼, 查不到的字)。
    static func code(for word: String) -> (code: String, unknown: [Character]) {
        var code = ""
        var unknown: [Character] = []
        for ch in word where ch != " " {
            if let c = table[String(ch)] {
                code += c
            } else {
                unknown.append(ch)
            }
        }
        return (code, unknown)
    }
}
