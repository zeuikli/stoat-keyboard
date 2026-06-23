import SwiftUI

/// 使用者詞庫：打「字詞」自動轉注音碼（SPEC §29 #2）。看 + 改自己的 Rime UserData。
struct UserDataView: View {
    @State private var wordsText = ""          // 一行一詞，可加「 權重」
    @State private var files: [FileRow] = []
    @State private var deploying = false
    @State private var status = ""
    @FocusState private var editing: Bool

    struct FileRow: Identifiable { let id = UUID(); let name: String; let size: Int }

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

            Section {
                Button(deploying ? "部署中…" : "儲存並套用（部署）") { save() }
                    .disabled(deploying || entries.isEmpty)
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
        let lines = (try? String(contentsOf: RimePaths.customPhraseURL, encoding: .utf8)) ?? ""
        wordsText = lines.split(separator: "\n").compactMap { ln -> String? in
            if ln.hasPrefix("#") { return nil }
            let cols = ln.split(separator: "\t")
            guard let w = cols.first.map(String.init) else { return nil }
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
        try? out.write(to: RimePaths.customPhraseURL, atomically: true, encoding: .utf8)

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
