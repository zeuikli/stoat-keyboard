import Foundation

/// 大千式注音鍵盤布局（SPEC §15.3）。
/// 每鍵帶「顯示注音符號」+「送給 librime 的實體 ASCII keycode」（大千鍵位）。
enum BopomoLayout {
    struct Key {
        let symbol: String
        let code: Int32

        var char: Character { Character(Unicode.Scalar(UInt32(code)) ?? " ") }
        /// 角落英文標：字母轉大寫、標點原樣；**數字不顯**（與第一行數字列重複，§28 #1）。
        var englishLabel: String {
            if char.isNumber { return "" }
            return char.isLetter ? String(char).uppercased() : String(char)
        }
        /// 上下划輸入英文（§28 #2）。數字鍵不掛（數字列已負責）。
        var hasSwipe: Bool { !char.isNumber }
        var swipeLower: String { String(char) }
        var swipeUpper: String { char.isLetter ? String(char).uppercased() : String(char) }
    }
    private static func k(_ s: String, _ c: Character) -> Key { Key(symbol: s, code: Int32(c.asciiValue!)) }

    // 大千鍵位＝實體鍵 1234567890- / qwertyuiop / asdfghjkl; / zxcvbnm,./
    // ㄦ 在「-」鍵（數字列），故置於第 1 列末——與 iOS 原生注音排列一致（11/10/10/10）。
    static let rows: [[Key]] = [
        [k("ㄅ","1"), k("ㄉ","2"), k("ˇ","3"), k("ˋ","4"), k("ㄓ","5"), k("ˊ","6"), k("˙","7"), k("ㄚ","8"), k("ㄞ","9"), k("ㄢ","0"), k("ㄦ","-")],
        [k("ㄆ","q"), k("ㄊ","w"), k("ㄍ","e"), k("ㄐ","r"), k("ㄔ","t"), k("ㄗ","y"), k("ㄧ","u"), k("ㄛ","i"), k("ㄟ","o"), k("ㄣ","p")],
        [k("ㄇ","a"), k("ㄋ","s"), k("ㄎ","d"), k("ㄑ","f"), k("ㄕ","g"), k("ㄘ","h"), k("ㄨ","j"), k("ㄜ","k"), k("ㄠ","l"), k("ㄤ",";")],
        [k("ㄈ","z"), k("ㄌ","x"), k("ㄏ","c"), k("ㄒ","v"), k("ㄖ","b"), k("ㄙ","n"), k("ㄩ","m"), k("ㄝ",","), k("ㄡ","."), k("ㄥ","/")],
    ]

    /// 大千鍵字元 → 注音符號（§32 #1 自繪 preedit 用）。
    static let keyToSymbol: [Character: String] = {
        var m: [Character: String] = [:]
        for row in rows { for k in row { m[k.char] = k.symbol } }
        return m
    }()

    /// 由 librime get_input（大千鍵序）轉注音字串顯示；tone1 空白略過，未知字原樣。
    static func bopomoPreedit(fromInput input: String) -> String {
        input.compactMap { ch -> String? in
            if ch == " " { return nil }
            return keyToSymbol[ch] ?? String(ch)
        }.joined()
    }

    /// 數字鍵上划符號（一般鍵盤 shift-數字，§35 #2）。
    static let numberSymbols: [Int: String] = [
        1: "!", 2: "@", 3: "#", 4: "$", 5: "%", 6: "^", 7: "&", 8: "*", 9: "(", 0: ")",
    ]

    /// 英文 QWERTY 頁（§46，比照 iOS 原廠）。小寫，依 Shift 轉大寫。
    static let englishRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    /// 123 數字/符號頁（§82，兩套：英文半形 IMG_1951 / 中文全形）。row3 中段符號（左加 #+=/123、右加 ⌫）。
    // ── 英文半形（IMG_1951）──
    static let numberPage0En: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]
    static let numberPage1En: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]
    // ── 中文全形 ──
    static let numberPage0Zh: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", "：", "；", "（", "）", "$", "@", "「", "」"],
        ["。", "，", "、", "？", "！"],
    ]
    static let numberPage1Zh: [[String]] = [
        ["［", "］", "｛", "｝", "#", "%", "^", "＊", "＋", "＝"],
        ["＿", "—", "＼", "｜", "～", "《", "》", "￥", "＆", "·"],
        ["。", "，", "、", "？", "！"],
    ]

    /// 無組字時的常用符號 + 顏文字快捷列（§35 #1）。
    static let quickSymbols: [String] = [
        "，", "。", "、", "！", "？", "：", "；", "…", "～", "—",
        "「」", "（）", "【】", "《》",
        "(´・ω・`)", "(・∀・)", "(＾▽＾)", "^_^", "orz", "Q_Q", "ʕ•ᴥ•ʔ", "(ㆆ_ㆆ)",
    ]

    static let keySpace: Int32 = 0x20
    static let keyBackspace: Int32 = 0xff08   // XK_BackSpace
    static let keyEnter: Int32 = 0xff0d        // XK_Return
    static let keyPageDown: Int32 = 0xff56     // XK_Page_Down（候選翻頁，§30）
    static let keyPageUp: Int32 = 0xff55        // XK_Page_Up
}
