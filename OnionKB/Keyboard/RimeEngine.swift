import Foundation

/// 候選形狀（SPEC §15.1 引擎↔UI 接縫契約）。
struct Candidate {
    let text: String
    let comment: String?
}

/// 一次按鍵/選字後的引擎狀態快照。
struct RimeUpdate {
    var preedit: String           // 組字串（注音）；顯示於鍵盤內（§3.5）
    var candidates: [Candidate]
    var commit: String?           // 若產生上字文字
}

/// 引擎協定——UI 只依賴此抽象。實作：`RimeEngineLibrime`（真）/`RimeEngineStub`（後備）。
protocol RimeEngine: AnyObject {
    var isReady: Bool { get }
    func processKey(_ keycode: Int32) -> RimeUpdate
    /// §200 二階段 phase1：送鍵 + 取 commit + 組字 preedit（**不算候選**＝不觸發 get_context 翻譯/grammar，便宜立即）。
    func processKeyPreedit(_ keycode: Int32) -> RimeUpdate
    /// §200 二階段 phase2：當前候選（觸發 get_context → 翻譯 + octagram grammar，昂貴 → 由 UI async 延後）。
    func fetchCandidates() -> [Candidate]
    /// §222 組字中？（get_input，便宜）——space/⌫/↵ 的引擎真值路由：main 的 preeditText 可能落後 in-flight 鍵。
    func isComposing() -> Bool
    func selectCandidate(_ index: Int) -> RimeUpdate
    func allCandidates() -> [Candidate]                       // 全候選（展開面板，§89）
    func selectCandidateAbsolute(_ index: Int) -> RimeUpdate  // 絕對索引選字（展開面板，§89）
    func clear()
    func setOption(_ name: String, _ value: Bool)
    func getOption(_ name: String) -> Bool
}


/// 後備 stub：librime 初始化失敗時用，避免鍵盤全黑（僅顯示提示）。
final class RimeEngineStub: RimeEngine {
    private var buffer = ""
    var isReady: Bool { true }

    func processKey(_ keycode: Int32) -> RimeUpdate {
        if keycode == 0xff08 {                 // backspace
            if !buffer.isEmpty { buffer.removeLast() }
        } else if let scalar = Unicode.Scalar(UInt32(max(0, keycode))), keycode < 128 {
            buffer.unicodeScalars.append(scalar)
        }
        return RimeUpdate(preedit: buffer,
                          candidates: buffer.isEmpty ? [] : [Candidate(text: "（無引擎）", comment: nil)],
                          commit: nil)
    }
    func processKeyPreedit(_ keycode: Int32) -> RimeUpdate { processKey(keycode) }   // stub：無二階段差異
    func fetchCandidates() -> [Candidate] {
        buffer.isEmpty ? [] : [Candidate(text: "（無引擎）", comment: nil)]
    }
    func isComposing() -> Bool { !buffer.isEmpty }   // §222
    func selectCandidate(_ index: Int) -> RimeUpdate {
        let t = buffer; buffer = ""
        return RimeUpdate(preedit: "", candidates: [], commit: t)
    }
    func allCandidates() -> [Candidate] {
        buffer.isEmpty ? [] : [Candidate(text: "（無引擎）", comment: nil)]
    }
    func selectCandidateAbsolute(_ index: Int) -> RimeUpdate {
        let t = buffer; buffer = ""
        return RimeUpdate(preedit: "", candidates: [], commit: t)
    }
    func clear() { buffer = "" }
    func setOption(_ name: String, _ value: Bool) {}
    func getOption(_ name: String) -> Bool { false }
}
