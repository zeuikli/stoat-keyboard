import SwiftUI

/// 使用者詞庫：打「字詞」自動轉注音碼（SPEC §29 #2）。看 + 改自己的 Rime UserData。
struct UserDataView: View {
    @State private var wordsText = ""          // 一行一詞，可加「 權重」
    @State private var kaomojiText = ""        // §204 一行一條「觸發詞=顏文字」
    @State private var files: [FileRow] = []
    @State private var deploying = false
    @State private var status = ""
    @FocusState private var editing: Bool

    struct FileRow: Identifiable { let id = UUID(); let name: String; let size: Int }
    private static let kaomojiStoreKey = "stoat_kaomoji_text"   // §204 顏文字詞條 raw（供 round-trip；custom.txt col1 為顏文字無法反推觸發詞）

    /// 解析輸入 → (詞, 碼, 權重, 未知字)。
    private var entries: [(word: String, code: String, weight: Int, unknown: [Character])] {
        wordsText.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let w = parts.first.map(String.init), !w.isEmpty else { return nil }
            let weight = parts.count > 1 ? (Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 100) : 100
            let r = Han2Code.code(for: w)
            return (w, r.code, weight, r.unknown)
        }
    }

    /// §204 顏文字詞條：輸出＝顏文字、碼＝觸發詞（Han2Code）。格式「觸發詞=顏文字」。
    private var kaomojiEntries: [(kaomoji: String, code: String, weight: Int, unknown: [Character])] {
        kaomojiText.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let trigger = parts[0].trimmingCharacters(in: .whitespaces)
            let kao = parts[1].trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty, !kao.isEmpty else { return nil }
            let r = Han2Code.code(for: trigger)
            return (kao, r.code, 100, r.unknown)
        }
    }

    var body: some View {
        List {
            Section("自訂詞庫（一行一詞，可在詞後加空格與權重）") {
                TextEditor(text: $wordsText)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .focused($editing)
                Text("範例：\n你好\n台積電 500").font(.footnote).foregroundStyle(.secondary)
            }

            if !entries.isEmpty {
                Section("轉換預覽（注音碼）") {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                        HStack {
                            Text(e.word)
                            Spacer()
                            if e.unknown.isEmpty {
                                Text(e.code.isEmpty ? "—" : e.code)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("查無：\(String(e.unknown))").foregroundStyle(.red).font(.callout)
                            }
                        }
                    }
                }
            }

            Section("顏文字詞庫（一行一條「觸發詞=顏文字」，§204）") {
                TextEditor(text: $kaomojiText)
                    .frame(minHeight: 90)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .focused($editing)
                Text("範例：\n笑=(^▽^)\n無奈=╮(╯_╰)╭\n打「笑」的注音即出現該顏文字候選").font(.footnote).foregroundStyle(.secondary)
            }

            if !kaomojiEntries.isEmpty {
                Section("顏文字轉換預覽（觸發詞注音碼）") {
                    ForEach(Array(kaomojiEntries.enumerated()), id: \.offset) { _, e in
                        HStack {
                            Text(e.kaomoji).lineLimit(1)
                            Spacer()
                            if e.unknown.isEmpty {
                                Text(e.code.isEmpty ? "—" : e.code)
                                    .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                            } else {
                                Text("查無：\(String(e.unknown))").foregroundStyle(.red).font(.callout)
                            }
                        }
                    }
                }
            }

            Section {
                Button(deploying ? "部署中…" : "儲存並套用（部署）") { save() }
                    .disabled(deploying || (entries.isEmpty && kaomojiEntries.isEmpty))
                if !status.isEmpty {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("UserData 檔案（\(RimePaths.usesAppGroup ? "App Group 共享" : "私有；開 Full Access 才與鍵盤共享")）") {
                if files.isEmpty { Text("（尚無）").foregroundStyle(.secondary) }
                ForEach(files) { f in
                    HStack {
                        Image(systemName: f.size < 0 ? "folder" : "doc.text")
                        Text(f.name); Spacer()
                        if f.size >= 0 { Text("\(f.size) B").foregroundStyle(.secondary).font(.caption) }
                    }
                }
                Text(RimePaths.userDir).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("我的詞庫 / UserData")
        .scrollDismissesKeyboard(.immediately)          // 滑動即收鍵盤（§32 #4）
        .toolbar {
            if editing {
                ToolbarItem(placement: .keyboard) {
                    Button("完成") { editing = false }   // 收鍵盤、方便後續操作
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        RimeDeployer.ensureCustomPhraseFile()
        // 由 custom.txt 第一欄還原使用者的詞清單（含權重）
        kaomojiText = UserDefaults.standard.string(forKey: Self.kaomojiStoreKey) ?? ""   // §204 顏文字編輯源
        let kaoSet = Set(kaomojiEntries.map { $0.kaomoji })
        let lines = (try? String(contentsOf: RimePaths.customPhraseURL, encoding: .utf8)) ?? ""
        wordsText = lines.split(separator: "\n").compactMap { ln -> String? in
            if ln.hasPrefix("#") { return nil }
            let cols = ln.split(separator: "\t")
            guard let w = cols.first.map(String.init) else { return nil }
            if kaoSet.contains(w) { return nil }   // §204 排除顏文字條（編輯源在 kaomojiText、非此欄）
            if cols.count >= 3, let wt = Int(cols[2]), wt != 100 { return "\(w) \(wt)" }
            return w
        }.joined(separator: "\n")
        files = listFiles()
    }

    private func listFiles() -> [FileRow] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: RimePaths.userDirURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return [] }
        return items.map { url in
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            return FileRow(name: url.lastPathComponent, size: (v?.isDirectory ?? false) ? -1 : (v?.fileSize ?? 0))
        }.sorted { $0.name < $1.name }
    }

    private func save() {
        editing = false   // 收鍵盤（§32 #4）
        // 組 custom.txt：詞<Tab>碼<Tab>權重（跳過查無字者）
        var out = "# Stoat 自訂詞庫（由 App 自動轉碼，§29）\n"
        var skipped: [String] = []
        for e in entries {
            if !e.unknown.isEmpty || e.code.isEmpty { skipped.append(e.word); continue }
            out += "\(e.word)\t\(e.code)\t\(e.weight)\n"
        }
        for e in kaomojiEntries {   // §204 顏文字條：輸出顏文字、碼＝觸發詞
            if !e.unknown.isEmpty || e.code.isEmpty { skipped.append(e.kaomoji); continue }
            out += "\(e.kaomoji)\t\(e.code)\t\(e.weight)\n"
        }
        try? out.write(to: RimePaths.customPhraseURL, atomically: true, encoding: .utf8)
        UserDefaults.standard.set(kaomojiText, forKey: Self.kaomojiStoreKey)   // §204 raw 存 App 端供 round-trip

        deploying = true; status = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = RimeDeployer.deploy()
            DispatchQueue.main.async {
                deploying = false
                var s = ok ? "✓ 已部署；切回鍵盤、下次彈出生效" : "✗ 部署失敗"
                if !skipped.isEmpty { s += "（略過查無字：\(skipped.joined(separator: "、"))）" }
                status = s
                files = listFiles()
            }
        }
    }
}
