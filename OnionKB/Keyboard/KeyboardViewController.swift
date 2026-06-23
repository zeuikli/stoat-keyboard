import UIKit

/// 閉包式 swipe 手勢（上下划輸入英文，§28 #2）。
final class ClosureSwipe: UISwipeGestureRecognizer {
    private let handler: () -> Void
    init(direction: UISwipeGestureRecognizer.Direction, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(target: nil, action: nil)
        self.direction = direction
        addTarget(self, action: #selector(fire))
    }
    @objc private func fire() { handler() }
}

/// 按鍵：覆寫 isHighlighted 做原廠按壓高亮（按下即時、放開快速淡出，§57）。
/// `pressedColor == nil` → 不手動高亮（交給 iOS 26 glass 互動動畫或系統）。
final class KeyButton: UIButton {
    var restingColor: UIColor? = .white
    var pressedColor: UIColor? = .systemGray4
    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted, let pressed = pressedColor else { return }
            if isHighlighted {
                backgroundColor = pressed                                   // 原廠：按下即時高亮
            } else {
                UIView.animate(withDuration: 0.12) { self.backgroundColor = self.restingColor }
            }
        }
    }
}

/// 注音鍵盤主控制器（SPEC §7.2 / §15.3 / §24 / §27）。
/// 真 librime 驅動：大千鍵 → keycode → librime → 組字/候選/上字。
/// 選項（半全/標點/簡繁）移到容器 App 設定（§27 #1）；中/英為功能列快切鍵。
final class KeyboardViewController: UIInputViewController {

    private lazy var engine: RimeEngine = RimeEngineLibrime() ?? RimeEngineStub()

    private let compositionLabel = UILabel()
    private let optionsButton = UIButton(type: .system)
    private let candidateBar = UIScrollView()
    private let candidateStack = UIStackView()
    private weak var candidateRowRef: UIStackView?   // 非注音模式隱藏（§80）
    private var currentCandidates: [Candidate] = []
    private var bopomoKeys: [(key: BopomoLayout.Key, main: UIButton, eng: UILabel)] = []
    private var cnEnButton: UIButton?                                // 中/英 快切鍵
    private var shiftButton: UIButton?                              // ⇧（保留供 updateModeStyling，已無實體鍵）
    private var heightConstraint: NSLayoutConstraint?
    private var kaomojiPanel: KaomojiPanel?                         // 顏文字面板（§36 #3）
    private var keyRowsStack: UIStackView!                          // 鍵列容器（模式切換，§44/§46）
    private var rootStack: UIStackView!                            // topBar + keyRowsStack（展開面板需插入，§89）
    private let expandButton = UIButton(type: .system)             // 候選展開/收合 chevron（§89）
    private var expandedPanel: UIScrollView?                       // 展開候選格面板（§89）
    private var isExpanded = false
    private enum KBMode { case bopomo, english, numbers }
    private var mode: KBMode = .bopomo
    private var lastLetterMode: KBMode = .bopomo                   // 123 返回的字母模式（注音/英文）

    // 空白鍵長按滑動移游標（§39）
    private var spaceCursorLastX: CGFloat = 0
    private var spaceCursorAccum: CGFloat = 0
    private let cursorStep: CGFloat = 9

    private enum ShiftState { case off, shifted, capsLock }
    private var shiftState: ShiftState = .off
    private var lastShiftTap = Date.distantPast
    private var englishMode: Bool { engine.getOption(SchemaOption.asciiMode.rawValue) }
    private var typeUppercase: Bool { shiftState != .off }

    private var fontScale: CGFloat { KBSettings.keyFontScale }       // 按鍵字體縮放（§27 #3）

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.82, alpha: 1)
        view.layer.cornerRadius = 12                                 // iOS 26 鍵盤上緣圓角（§90）
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        buildUI()
        applyOptionDefaults()   // 套用容器 App 設定的選項預設（§27 #1）
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 每次鍵盤出現重套 App 設定（簡繁/全形/標點 + glass/字體/提示）——拾取改設定後的最新值（需 Full Access，§63）
        applyOptionDefaults()
        rebuildKeyRows()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyHeight()
    }

    private func applyHeight() {
        // 原廠風格變動高度（§90，使用者選）：固定鍵高、總高度隨列數變（注音最高、英文/123 較矮、按鍵全模式同大小）。
        guard keyRowsStack != nil else { return }
        let rowGap: CGFloat = 7                                       // keyRowsStack spacing（§54）
        let preeditH: CGFloat = 26, candH: CGFloat = 40
        let baseChrome: CGFloat = 4 + preeditH + 5 + 4               // 上邊距 + preedit + rootSpacing + 下邊距
        let bopomoChrome = baseChrome + 2 + candH                    // 注音另含 topBar 內距 + 候選列
        let refRows = CGFloat(showNumberRow ? 6 : 5)                 // 注音參考列數（數字列 + 4 注音 + 功能）
        // 由注音反推固定鍵高 → 各模式套同一 rowH，按鍵大小一致
        let rowH = max(38, (KBSettings.keyboardHeight - bopomoChrome - (refRows - 1) * rowGap) / refRows)
        let curRows = CGFloat(max(1, keyRowsStack.arrangedSubviews.count))
        let chrome = (mode == .bopomo) ? bopomoChrome : baseChrome   // 候選列僅注音顯示
        let h = chrome + curRows * rowH + (curRows - 1) * rowGap
        if let c = heightConstraint {
            c.constant = h
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: h)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    // MARK: - 鍵盤本地選項（不依賴 App Group，側載也可用，§65）
    private let localStore = UserDefaults.standard
    private func localOpt(_ key: String, default d: Bool = false) -> Bool {
        localStore.object(forKey: key) == nil ? d : localStore.bool(forKey: key)
    }
    private func setLocalOpt(_ key: String, _ v: Bool) { localStore.set(v, forKey: key) }
    private func optKey(_ o: SchemaOption) -> String { "kbopt_" + o.rawValue }
    private static let glassKey = "kbopt_glass"
    private static let engHintKey = "kbopt_engHint"
    private static let numberRowKey = "kbopt_numberRow"
    private var numberSubPage = 0                       // 123 頁子頁（0/1，§66）
    private var showNumberRow: Bool { localOpt(Self.numberRowKey, default: true) }

    /// 123 標點模式（§82）：0=自動依中英、1=半形、2=全形。
    private static let n123ModeKey = "kbopt_123mode"
    private var is123Half: Bool {
        switch localStore.integer(forKey: Self.n123ModeKey) {
        case 1: return true
        case 2: return false
        default: return lastLetterMode == .english   // 自動：英文→半形、注音→全形
        }
    }
    /// 123 頁當前兩頁符號（依 is123Half，§82）。
    private var numberPages: ([[String]], [[String]]) {
        is123Half ? (BopomoLayout.numberPage0En, BopomoLayout.numberPage1En)
                  : (BopomoLayout.numberPage0Zh, BopomoLayout.numberPage1Zh)
    }
    /// 123 頁符號鍵（直接插入，§82）。
    private func numberKey(_ sym: String) -> UIButton {
        keyButton(title: sym) { [weak self] in self?.insertEnglish(sym) }
    }

    /// 套用 schema 選項（半全/標點/簡繁/中英）——讀鍵盤本地存儲（§65）。
    private func applyOptionDefaults() {
        for opt in SchemaOption.allCases {
            engine.setOption(opt.rawValue, localOpt(optKey(opt), default: opt.defaultOn))
        }
        updateModeStyling()
    }

    /// 鍵盤內建選項選單（⚙）：toggle 即時套用 + 本地持久化（§65）。
    private func refreshOptionsMenu() {
        func toggle(_ title: String, _ key: String, _ on: Bool, _ apply: @escaping (Bool) -> Void) -> UIAction {
            UIAction(title: title, state: on ? .on : .off) { [weak self] _ in
                self?.setLocalOpt(key, !on); apply(!on); self?.refreshOptionsMenu()
            }
        }
        var items: [UIMenuElement] = SchemaOption.allCases.filter { $0 != .asciiMode }.map { opt in
            toggle(opt.title, optKey(opt), localOpt(optKey(opt), default: opt.defaultOn)) { [weak self] v in
                self?.engine.setOption(opt.rawValue, v)
                if opt == .fullShape { self?.rebuildKeyRows() }   // 123 頁半全形即時更新（§71）
            }
        }
        if #available(iOS 26.0, *) {
            items.append(toggle("iOS 26 玻璃按鍵", Self.glassKey, localOpt(Self.glassKey, default: false)) { [weak self] _ in self?.rebuildKeyRows() })
        }
        items.append(toggle("常駐數字列", Self.numberRowKey, localOpt(Self.numberRowKey, default: true)) { [weak self] _ in self?.rebuildKeyRows() })
        items.append(toggle("注音鍵英文提示", Self.engHintKey, localOpt(Self.engHintKey)) { [weak self] _ in self?.rebuildKeyRows() })
        // 123 標點：自動依中英 / 半形 / 全形（§82）
        let cur = localStore.integer(forKey: Self.n123ModeKey)
        func p123(_ title: String, _ v: Int) -> UIAction {
            UIAction(title: title, state: cur == v ? .on : .off) { [weak self] _ in
                self?.localStore.set(v, forKey: Self.n123ModeKey)
                if self?.mode == .numbers { self?.rebuildKeyRows() }
                self?.refreshOptionsMenu()
            }
        }
        items.append(UIMenu(title: "123 標點", options: .singleSelection,
                            children: [p123("自動（依中英）", 0), p123("半形", 1), p123("全形", 2)]))
        optionsButton.menu = UIMenu(title: "輸入選項", children: items)
    }

    // MARK: - UI

    private func buildUI() {
        // 組字注音 + 右上角縮小鍵：獨立一列（§30 #1 / §56）
        compositionLabel.font = .systemFont(ofSize: 15 * fontScale, weight: .medium)
        compositionLabel.textColor = .systemGray
        compositionLabel.text = " "

        optionsButton.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)   // 鍵盤內建選項（§65）
        optionsButton.tintColor = .darkGray
        optionsButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
        optionsButton.showsMenuAsPrimaryAction = true
        refreshOptionsMenu()

        let collapseButton = UIButton(type: .system)               // 縮小/收鍵盤；置右上角避免誤按候選（§56）
        collapseButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        collapseButton.tintColor = .darkGray
        collapseButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
        collapseButton.addAction(UIAction { [weak self] _ in self?.dismissKeyboard() }, for: .touchUpInside)

        let preeditRow = UIStackView(arrangedSubviews: [compositionLabel, optionsButton, collapseButton])
        preeditRow.axis = .horizontal
        preeditRow.alignment = .center
        let preeditH = preeditRow.heightAnchor.constraint(equalToConstant: 26)
        preeditH.priority = UILayoutPriority(999)   // 可壓縮：host 高度不足時讓位（§58）
        preeditH.isActive = true

        // 候選：獨立全寬捲動列 + 右側「▾」翻頁鍵
        candidateStack.axis = .horizontal
        candidateStack.spacing = 12
        candidateStack.alignment = .center
        candidateBar.showsHorizontalScrollIndicator = false
        candidateBar.addSubview(candidateStack)
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateBar.contentLayoutGuide.leadingAnchor, constant: 8),
            candidateStack.trailingAnchor.constraint(equalTo: candidateBar.contentLayoutGuide.trailingAnchor, constant: -8),
            candidateStack.topAnchor.constraint(equalTo: candidateBar.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateBar.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateBar.frameLayoutGuide.heightAnchor),
        ])
        expandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)   // 原廠灰 chevron（§89，去藍 ▾）
        expandButton.tintColor = .secondaryLabel
        expandButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        expandButton.addAction(UIAction { [weak self] _ in self?.toggleExpanded() }, for: .touchUpInside)

        let candidateRow = UIStackView(arrangedSubviews: [candidateBar, expandButton])
        candidateRow.axis = .horizontal
        candidateRow.spacing = 2
        candidateRowRef = candidateRow
        let candidateH = candidateRow.heightAnchor.constraint(equalToConstant: 40)
        candidateH.priority = UILayoutPriority(999)  // 可壓縮：host 高度不足時讓位（§58）
        candidateH.isActive = true

        let topBar = UIStackView(arrangedSubviews: [preeditRow, candidateRow])
        topBar.axis = .vertical
        topBar.spacing = 2

        keyRowsStack = UIStackView()
        keyRowsStack.axis = .vertical
        keyRowsStack.spacing = 7                 // 原廠列距（§54）
        keyRowsStack.distribution = .fillEqually
        keyRowsStack.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)  // 唯一彈性帶：多餘高度灌入按鍵、不留空白帶（§59）
        rebuildKeyRows()

        rootStack = UIStackView(arrangedSubviews: [topBar, keyRowsStack])
        rootStack.axis = .vertical
        rootStack.spacing = 5
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),   // 不依賴 host top inset（§58）
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])
        refresh(RimeUpdate(preedit: "", candidates: [], commit: nil))
    }

    private func makeKeyRow(_ keys: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: keys)
        row.axis = .horizontal
        row.spacing = 6                  // 原廠鍵距，避免擁擠（§54）
        row.distribution = .fillEqually
        return row
    }

    /// 統一鍵寬列（§78）：所有鍵同寬＝容器/11−60/11（11 欄基準），列置中。
    /// 11 鍵列填滿、10 鍵列同寬置中內縮 → 大千錯落但鍵大小一致。
    private func uniformRow(_ keys: [UIView]) -> UIView {
        let row = UIStackView(arrangedSubviews: keys)
        row.axis = .horizontal; row.spacing = 6; row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        for k in keys {
            k.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 1.0/11.0, constant: -60.0/11.0).isActive = true
        }
        return container
    }

    /// 依模式重建鍵列（注音/英文/數字，§44/§46）。
    private func rebuildKeyRows() {
        keyRowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        bopomoKeys.removeAll()
        cnEnButton = nil; shiftButton = nil
        switch mode {
        case .numbers:
            let pages = numberSubPage == 0 ? numberPages.0 : numberPages.1   // 半/全形依模式+設定（§82）
            for (i, row) in pages.enumerated() {
                if i == pages.count - 1 {                           // row3：[切頁鍵] + 中段符號 + ⌫（兩頁切換，§66）
                    let switchTitle = numberSubPage == 0 ? "#+=" : "123"
                    let switchKey = grayKey(keyButton(title: switchTitle) { [weak self] in
                        self?.numberSubPage = self?.numberSubPage == 0 ? 1 : 0
                        self?.rebuildKeyRows()
                    })
                    var keys: [UIView] = [switchKey]
                    keys.append(contentsOf: row.map { numberKey($0) })
                    keys.append(backspaceKey())
                    keyRowsStack.addArrangedSubview(makeKeyRow(keys))
                } else {
                    keyRowsStack.addArrangedSubview(makeKeyRow(row.map { numberKey($0) }))
                }
            }
            keyRowsStack.addArrangedSubview(numberFunctionRow())
        case .english:
            buildEnglishRows()
        case .bopomo:
            if showNumberRow { keyRowsStack.addArrangedSubview(makeKeyRow(numberRowKeys())) }   // 數字列滿版對齊（§83 撤 §78 錯落）
            for (i, row) in BopomoLayout.rows.enumerated() {
                let notes = row.map { bopomoKey($0) }
                if i == BopomoLayout.rows.count - 1 {            // 第4列：注音鍵 + 加寬 ⌫（好按，§83）
                    let del = backspaceKey()
                    let r = UIStackView(arrangedSubviews: notes + [del])
                    r.axis = .horizontal; r.spacing = 6; r.distribution = .fill
                    for n in notes { n.widthAnchor.constraint(equalTo: notes[0].widthAnchor).isActive = true }
                    del.widthAnchor.constraint(equalTo: notes[0].widthAnchor, multiplier: 1.6).isActive = true
                    keyRowsStack.addArrangedSubview(r)
                } else {
                    keyRowsStack.addArrangedSubview(makeKeyRow(notes))   // 滿版對齊、不錯落（§83）
                }
            }
            keyRowsStack.addArrangedSubview(bopomoFunctionRow())
        }
        candidateRowRef?.isHidden = (mode != .bopomo)   // 英文/123 收候選列→去上方留白（§86）
        if mode == .english { refreshEnglishCase() } else { updateModeStyling() }
        applyHeight()                                   // 列數變動即更新高度（§90 原廠風格變動高度）
    }

    // MARK: - 英文 QWERTY 頁（§46）

    private var englishLetterButtons: [(letter: String, button: UIButton)] = []

    private func buildEnglishRows() {
        englishLetterButtons.removeAll()
        let rows = BopomoLayout.englishRows
        if showNumberRow { keyRowsStack.addArrangedSubview(makeKeyRow(numberRowKeys())) }   // 數字快捷列（§53/§66 可關，英文頁滿版對齊 QWERTY）
        // Row1：10 字母滿版
        keyRowsStack.addArrangedSubview(makeKeyRow(rows[0].map { englishKey($0) }))
        // Row2：9 字母置中內縮（寬度同 row1）。用純 UIView 容器避免 stack distribution 與置中打架→歪邊（§76）
        let r2 = makeKeyRow(rows[1].map { englishKey($0) })
        let r2c = UIView()
        r2.translatesAutoresizingMaskIntoConstraints = false
        r2c.addSubview(r2)
        NSLayoutConstraint.activate([
            r2.topAnchor.constraint(equalTo: r2c.topAnchor),
            r2.bottomAnchor.constraint(equalTo: r2c.bottomAnchor),
            r2.centerXAnchor.constraint(equalTo: r2c.centerXAnchor),
            r2.widthAnchor.constraint(equalTo: r2c.widthAnchor, multiplier: 0.9),
        ])
        keyRowsStack.addArrangedSubview(r2c)
        // Row3：⇧ + 7 字母 + ⌫
        let shift = grayKey(iconButton(shiftIcon()) { [weak self] in self?.tapShift() })
        shiftButton = shift
        let letters = rows[2].map { englishKey($0) }
        let del = backspaceKey()
        let r3 = UIStackView(arrangedSubviews: [shift] + letters + [del])
        r3.axis = .horizontal; r3.spacing = 6; r3.distribution = .fill
        for k in letters { k.widthAnchor.constraint(equalTo: letters[0].widthAnchor).isActive = true }
        shift.widthAnchor.constraint(equalTo: letters[0].widthAnchor, multiplier: 1.5).isActive = true
        del.widthAnchor.constraint(equalTo: letters[0].widthAnchor, multiplier: 1.5).isActive = true
        keyRowsStack.addArrangedSubview(r3)
        keyRowsStack.addArrangedSubview(englishFunctionRow())
    }

    private func englishKey(_ lower: String) -> UIButton {
        let b = keyButton(title: lower.uppercased()) { [weak self] in self?.tapEnglish(lower) }
        englishLetterButtons.append((lower, b))
        return b
    }

    private func tapEnglish(_ lower: String) {
        textDocumentProxy.insertText(typeUppercase ? lower.uppercased() : lower)
        if shiftState == .shifted { shiftState = .off; refreshEnglishCase() }
    }

    private func refreshEnglishCase() {
        for (lower, b) in englishLetterButtons {
            let t = typeUppercase ? lower.uppercased() : lower
            if b.configuration != nil { b.configuration?.title = t } else { b.setTitle(t, for: .normal) }
        }
        shiftButton?.setImage(UIImage(systemName: shiftIcon()), for: .normal)
        if useGlassKeys, #available(iOS 26.0, *) {
            // glass：Shift 啟用＝藍前景高亮、關閉＝預設（§55）
            shiftButton?.configuration?.baseForegroundColor = shiftState == .off ? .label : .systemBlue
        } else {
            shiftButton?.tintColor = .black
            // 原廠：Shift 啟用＝白底高亮、關閉＝灰底（§49）
            (shiftButton as? KeyButton)?.restingColor = shiftState == .off ? Self.funcKeyGray : .white
            shiftButton?.backgroundColor = shiftState == .off ? Self.funcKeyGray : .white
        }
    }

    private func shiftIcon() -> String {
        switch shiftState {
        case .capsLock: return "capslock.fill"
        case .shifted: return "shift.fill"
        case .off: return "shift"
        }
    }

    /// 系統「切換鍵盤」鍵（§60）：tap→下一鍵盤、長按→鍵盤清單（Apple 標準）。custom KB 須自備，不可依賴系統 bar（Telegram 會藏）。
    private func nextKeyboardButton() -> UIButton {
        let b = iconButton("globe") { }     // 實際行為由 handleInputModeList 處理
        b.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        return grayKey(b)
    }

    /// 依 `needsInputModeSwitchKey` 在功能列最前面插入切換鍵盤鍵。
    private func withGlobe(_ keys: [UIView]) -> [UIView] {
        needsInputModeSwitchKey ? [nextKeyboardButton()] + keys : keys
    }

    /// iOS English 原廠底列：`中 · 123 · 😀 · 寬空格 · return`（§79，對齊 IMG_1950）。中→回注音。
    private func englishFunctionRow() -> UIStackView {
        let zh = grayKey(keyButton(title: "中") { [weak self] in self?.setMode(.bopomo) })   // 回注音
        let num = grayKey(keyButton(title: "123") { [weak self] in self?.setMode(.numbers) })
        let emoji = grayKey(keyButton(title: "😀") { [weak self] in self?.showKaomojiPanel() })
        let space = wideSpaceKey()
        let ret = grayKey(iconButton("return") { [weak self] in self?.tapEnter() })
        let keys = [zh, num, emoji, space, ret]
        return widebar(keys, wideIndex: keys.firstIndex { $0 === space }!, ref: zh)
    }

    static let funcKeyGray = UIColor(red: 172/255, green: 176/255, blue: 186/255, alpha: 1)

    static let keyRadius: CGFloat = 8   // iOS 26 鍵盤鍵圓角（§77，較圓潤）

    /// iOS 26 「玻璃」鍵（§92）：系統 UIButton.Configuration.glass() 在實機渲染異常
    /// （§88 藍底、§92 浮凸陰影，本機無 GUI 不可重現）→ 改用可預期的**半透明霜白**：
    /// 僅換底色、沿用 keyButton 既有圓角與 1px 細陰影，無系統材質＝無浮凸/無偏色。
    @available(iOS 26.0, *)
    private func applyGlass(_ b: UIButton, prominent: Bool) {
        b.titleLabel?.font = .systemFont(ofSize: (prominent ? 23 : 16) * fontScale)
        let rest = UIColor.white.withAlphaComponent(prominent ? 0.55 : 0.30)   // content 較實、function 較透
        let press = UIColor.white.withAlphaComponent(prominent ? 0.85 : 0.60)
        b.backgroundColor = rest
        if let k = b as? KeyButton { k.restingColor = rest; k.pressedColor = press }
    }

    /// 功能鍵樣式：iOS 26 + 開關 on → Liquid Glass（regular）；否則灰底 #ABB0BB + 小字 + 原廠按壓高亮。
    private func grayKey(_ b: UIButton) -> UIButton {
        if useGlassKeys, #available(iOS 26.0, *) {
            applyGlass(b, prominent: false)
        } else {
            b.backgroundColor = Self.funcKeyGray
            b.titleLabel?.font = .systemFont(ofSize: 16 * fontScale)
            if let k = b as? KeyButton {             // 原廠：灰鍵按下變白（§57）
                k.restingColor = Self.funcKeyGray
                k.pressedColor = .white
            }
        }
        return b
    }

    /// 常駐數字列鍵（§45）：1-0 + 角落符號小標 + 上划輸入符號（§35 #2）。列佈局由呼叫端決定（注音用 uniformRow、英文用 makeKeyRow，§78）。
    private func numberRowKeys() -> [UIButton] {
        let digits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
        return digits.map { d -> UIButton in
            let b = keyButton(title: "\(d)") { [weak self] in self?.textDocumentProxy.insertText("\(d)") }
            if let sym = BopomoLayout.numberSymbols[d] {
                let lbl = UILabel()
                lbl.text = sym
                lbl.font = .systemFont(ofSize: 10 * fontScale, weight: .medium)
                lbl.textColor = .systemGray
                lbl.translatesAutoresizingMaskIntoConstraints = false
                b.addSubview(lbl)
                NSLayoutConstraint.activate([
                    lbl.topAnchor.constraint(equalTo: b.topAnchor, constant: 2),
                    lbl.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -4),
                ])
                b.addGestureRecognizer(ClosureSwipe(direction: .up) { [weak self] in self?.insertEnglish(sym) })
            }
            return b
        }
    }

    /// 注音功能列（原廠：123 · 中/英 · 😀 · 寬空格 · ⏎，§44）。
    private func bopomoFunctionRow() -> UIStackView {
        let num = grayKey(keyButton(title: "123") { [weak self] in self?.setMode(.numbers) })
        let cnEn = grayKey(keyButton(title: "英") { [weak self] in self?.setMode(.english) })  // 切英文 QWERTY
        let emoji = grayKey(keyButton(title: "😀") { [weak self] in self?.showKaomojiPanel() })
        let space = wideSpaceKey()
        let ret = grayKey(iconButton("return") { [weak self] in self?.tapEnter() })
        let keys = withGlobe([num, cnEn, emoji, space, ret])
        return widebar(keys, wideIndex: keys.firstIndex { $0 === space }!, ref: num)
    }

    /// 數字頁功能列（返回字母模式 · 😀 · 寬空格 · ⏎，§44）。
    private func numberFunctionRow() -> UIStackView {
        let backTitle = lastLetterMode == .english ? "ABC" : "注音"
        let back = grayKey(keyButton(title: backTitle) { [weak self] in self?.setMode(self?.lastLetterMode ?? .bopomo) })
        let emoji = grayKey(keyButton(title: "😀") { [weak self] in self?.showKaomojiPanel() })
        let space = wideSpaceKey()
        let ret = grayKey(iconButton("return") { [weak self] in self?.tapEnter() })
        let keys = withGlobe([back, emoji, space, ret])
        return widebar(keys, wideIndex: keys.firstIndex { $0 === space }!, ref: back)
    }

    private func wideSpaceKey() -> UIButton {
        let space = keyButton(title: "空格") { [weak self] in self?.tapSpace() }
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(spaceLongPress(_:)))
        lp.minimumPressDuration = 0.3
        space.addGestureRecognizer(lp)                     // 長按滑動移游標（§39）
        return space
    }

    /// 功能列：小鍵等寬、指定一鍵（空格）加寬，比照 iOS。
    private func widebar(_ keys: [UIView], wideIndex: Int, ref: UIView) -> UIStackView {
        let row = UIStackView(arrangedSubviews: keys)
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fill
        for (i, k) in keys.enumerated() where i != wideIndex && k !== ref {
            k.widthAnchor.constraint(equalTo: ref.widthAnchor).isActive = true
        }
        keys[wideIndex].widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: 3.0).isActive = true   // 空格寬、功能鍵不過窄防換行（§88，從 §81 的 4.5 收回）
        return row
    }

    private func setMode(_ m: KBMode) {
        if isExpanded { collapseExpanded() }           // 切模式先收展開面板（§89）
        if m == .bopomo || m == .english { lastLetterMode = m }
        if m == .numbers { numberSubPage = 0 }        // 進 123 頁從第一頁開始（§66）
        mode = m
        rebuildKeyRows()
        applyHeight()                                  // 切模式即時更新高度（§81）
        if m == .bopomo {
            refresh(RimeUpdate(preedit: "", candidates: [], commit: nil))   // 還原閒置快捷符號列（§35）
        } else {                                                            // 英文/123 頁：清注音組字殘留，候選列改顯快捷符號（填滿、高度一致，§84）
            engine.clear()
            currentCandidates = []
            compositionLabel.text = " "
            candidateStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        }
    }

    /// Shift：單擊 off↔shifted、雙擊 capsLock（比照 iOS，§31）。
    private func tapShift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3 {
            shiftState = .capsLock
        } else {
            switch shiftState {
            case .off: shiftState = .shifted
            case .shifted, .capsLock: shiftState = .off
            }
        }
        lastShiftTap = now
        if mode == .english { refreshEnglishCase() } else { updateModeStyling() }
    }

    /// iOS 26 玻璃功能鍵是否啟用（鍵盤本地開關 + 系統版本，§57/§65）。
    private var useGlassKeys: Bool {
        if #available(iOS 26.0, *) { return localOpt(Self.glassKey, default: false) }   // 預設關：原廠實心白鍵/灰功能鍵（§88）
        return false
    }

    private func keyButton(title: String, action: @escaping () -> Void) -> UIButton {
        let b = KeyButton(frame: .zero)         // 必用 designated init：UIButton(type:) 工廠會忽略子類（§57）
        b.setContentCompressionResistancePriority(.defaultLow, for: .vertical)   // 高度不足時鍵自縮、不撐爆（§58）
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 23 * fontScale)   // 原廠內容鍵大字（§49）
        b.titleLabel?.numberOfLines = 1                            // 防 123/ABC/#+= 換行（§88）
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.6
        b.titleLabel?.lineBreakMode = .byClipping
        b.backgroundColor = .white
        b.setTitleColor(.black, for: .normal)
        b.layer.cornerRadius = Self.keyRadius
        b.layer.cornerCurve = .continuous                        // iOS 26 squircle 圓角（§90）
        b.layer.shadowColor = UIColor.black.cgColor               // 原廠 1px 底陰影（§49）
        b.layer.shadowOpacity = 0.3
        b.layer.shadowOffset = CGSize(width: 0, height: 1)
        b.layer.shadowRadius = 0
        b.layer.masksToBounds = false
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        if !title.isEmpty, useGlassKeys, #available(iOS 26.0, *) {   // 內容鍵也 glass（§77）
            applyGlass(b, prominent: true)
        }
        return b
    }

    /// SF Symbol 圖示鍵（比照 iOS 原廠圖示，§43）。
    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> UIButton {
        let b = keyButton(title: "", action: action)
        b.setImage(UIImage(systemName: systemName), for: .normal)
        b.tintColor = .black
        return b
    }

    /// 雙標注音鍵：大字注音 + 角落小字英文；上下划輸入英文（§26.2 / §28）。
    private func bopomoKey(_ key: BopomoLayout.Key) -> UIButton {
        let b = keyButton(title: key.symbol) { [weak self] in self?.tapBopomo(key) }
        let eng = UILabel()
        eng.text = key.englishLabel
        eng.font = .systemFont(ofSize: 10 * fontScale, weight: .medium)
        eng.textColor = .systemGray
        eng.isHidden = !localOpt(Self.engHintKey)        // 預設純原廠；提示開關控制（§48）
        eng.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(eng)
        NSLayoutConstraint.activate([
            eng.topAnchor.constraint(equalTo: b.topAnchor, constant: 2),
            eng.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -4),
        ])
        if key.hasSwipe {        // 上下划英文與標示解耦：永遠有效（大千≡QWERTY，§48）
            b.addGestureRecognizer(ClosureSwipe(direction: .up) { [weak self] in self?.insertEnglish(key.swipeLower) })
            b.addGestureRecognizer(ClosureSwipe(direction: .down) { [weak self] in self?.insertEnglish(key.swipeUpper) })
        }
        bopomoKeys.append((key, b, eng))
        return b
    }

    /// 上下划：清掉進行中的注音組字後，直接插英文（§28 #2）。
    private func insertEnglish(_ s: String) {
        if !isPreeditEmpty {
            engine.clear()
            refresh(RimeUpdate(preedit: "", candidates: [], commit: nil))
        }
        textDocumentProxy.insertText(s)
    }

    /// 英文模式凸顯英文（依 Shift 顯示大/小寫）、淡化注音；同步 中/英、Shift 鍵（§26.2 / §31）。
    private func updateModeStyling() {
        let english = englishMode
        let upper = typeUppercase
        for (key, main, eng) in bopomoKeys {
            main.setTitleColor(english ? .systemGray3 : .black, for: .normal)
            if english {
                eng.isHidden = false
                eng.text = upper ? key.swipeUpper : key.swipeLower   // 標籤反映將輸出的大小寫（iOS 風）
                eng.textColor = .label
                eng.font = .systemFont(ofSize: 16 * fontScale, weight: .semibold)
            } else {
                eng.isHidden = !localOpt(Self.engHintKey)              // 純原廠時隱藏（§48）
                eng.text = key.englishLabel
                eng.textColor = .systemGray
                eng.font = .systemFont(ofSize: 10 * fontScale, weight: .medium)
            }
        }
        cnEnButton?.setTitle(english ? "英" : "中", for: .normal)
        cnEnButton?.setTitleColor(english ? .systemBlue : .black, for: .normal)
        // Shift 視覺：off ⇧灰 / shifted ⇧藍 / capsLock ⇪藍；注音模式淡化
        let shiftTitle = shiftState == .capsLock ? "⇪" : "⇧"
        shiftButton?.setTitle(shiftTitle, for: .normal)
        shiftButton?.setTitleColor(!english ? .systemGray3 : (shiftState == .off ? .black : .systemBlue), for: .normal)
        shiftButton?.backgroundColor = (english && shiftState != .off) ? UIColor.systemBlue.withAlphaComponent(0.15) : UIColor(white: 0.95, alpha: 1)
    }

    // MARK: - Input

    private func tapKey(_ code: Int32) { apply(engine.processKey(code)) }

    /// 注音鍵 tap：英文模式插字面字母（依 Shift 大小寫，§29 #1 / §31）；否則送注音。
    private func tapBopomo(_ key: BopomoLayout.Key) {
        if englishMode {
            textDocumentProxy.insertText(typeUppercase ? key.swipeUpper : key.swipeLower)
            if shiftState == .shifted { shiftState = .off; updateModeStyling() }
        } else {
            apply(engine.processKey(key.code))
        }
    }

    private func tapNumber(_ digit: Int) {
        let idx = (digit == 0) ? 9 : digit - 1
        if idx < currentCandidates.count {
            apply(engine.selectCandidate(idx))
        } else {
            textDocumentProxy.insertText("\(digit)")
        }
    }

    private func toggleAsciiMode() {
        engine.setOption(SchemaOption.asciiMode.rawValue, !engine.getOption(SchemaOption.asciiMode.rawValue))
        updateModeStyling()
    }

    private func tapSpace() {
        if isPreeditEmpty { textDocumentProxy.insertText(" ") }
        else { apply(engine.processKey(BopomoLayout.keySpace)) }
    }

    /// 長按空白鍵滑動移游標（§39，比照 iOS 觸控板）。
    @objc private func globeLongPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { showKaomojiPanel() }
    }

    @objc private func spaceLongPress(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            spaceCursorLastX = g.location(in: view).x
            spaceCursorAccum = 0
        case .changed:
            let x = g.location(in: view).x
            spaceCursorAccum += x - spaceCursorLastX
            spaceCursorLastX = x
            while spaceCursorAccum >= cursorStep {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: 1); spaceCursorAccum -= cursorStep
            }
            while spaceCursorAccum <= -cursorStep {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: -1); spaceCursorAccum += cursorStep
            }
        default:
            break
        }
    }

    private var isPreeditEmpty: Bool {
        compositionLabel.text == " " || compositionLabel.text?.isEmpty == true
    }

    /// ⌫ 鍵：單擊刪一字；長按連續刪除（§62）。
    private var backspaceTimer: Timer?
    private func backspaceKey() -> UIButton {
        let b = grayKey(iconButton("delete.left") { [weak self] in self?.tapBackspace() })
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(backspaceLongPress(_:)))
        lp.minimumPressDuration = 0.35
        b.addGestureRecognizer(lp)
        return b
    }

    @objc private func backspaceLongPress(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            tapBackspace()                                  // 立即刪一次（長按已擋掉 button 的 tap）
            backspaceTimer?.invalidate()
            backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.tapBackspace()
            }
        case .ended, .cancelled, .failed:
            backspaceTimer?.invalidate(); backspaceTimer = nil
        default: break
        }
    }

    private func tapBackspace() {
        if isPreeditEmpty { textDocumentProxy.deleteBackward() }
        else { apply(engine.processKey(BopomoLayout.keyBackspace)) }
    }

    private func tapEnter() {
        if isPreeditEmpty { textDocumentProxy.insertText("\n") }
        else { apply(engine.processKey(BopomoLayout.keyEnter)) }
    }

    private func apply(_ update: RimeUpdate) {
        if let commit = update.commit, !commit.isEmpty {
            textDocumentProxy.insertText(commit)
        }
        refresh(update)
    }

    private func refresh(_ update: RimeUpdate) {
        currentCandidates = update.candidates
        compositionLabel.text = update.preedit.isEmpty ? " " : update.preedit
        candidateStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if update.candidates.isEmpty && update.preedit.isEmpty {
            if isExpanded { collapseExpanded() }                 // 組字清空→自動收合展開面板（§89）
            showQuickSymbols()                                   // 無組字→常用符號/顏文字（§35 #1）
            return
        }
        for (i, cand) in update.candidates.enumerated() {
            guard Self.isRenderable(cand.text) else { continue }   // 過濾生僻字 tofu（§69）；保留原 index
            let b = UIButton(type: .system)
            b.setTitle(cand.text, for: .normal)                    // 原廠候選無編號（§53）
            b.titleLabel?.font = .systemFont(ofSize: 22 * fontScale)
            b.setTitleColor(.black, for: .normal)
            b.addAction(UIAction { [weak self] _ in
                self?.apply(self!.engine.selectCandidate(i))
            }, for: .touchUpInside)
            candidateStack.addArrangedSubview(b)
        }
    }

    // MARK: - 候選展開面板（§89，比照原廠格狀展開）

    private func toggleExpanded() {
        if isExpanded { collapseExpanded() }
        else if !isPreeditEmpty { buildExpandedPanel() }   // 僅組字中可展開
    }

    private func collapseExpanded() {
        expandedPanel?.removeFromSuperview()
        expandedPanel = nil
        isExpanded = false
        keyRowsStack.isHidden = false
        expandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    }

    /// 展開：隱鍵盤、改顯全候選格（依字寬 wrap、左對齊、絕對索引選字）。
    private func buildExpandedPanel() {
        let cands = engine.allCandidates().enumerated().filter { Self.isRenderable($0.element.text) }
        guard !cands.isEmpty else { return }

        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = true
        scroll.alwaysBounceVertical = true
        scroll.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)   // 吃彈性高度，與 keyRowsStack 一致（§59）

        let vstack = UIStackView()
        vstack.axis = .vertical
        vstack.spacing = 0                                       // 列距由分隔線處理（§91）
        vstack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(vstack)

        let font = UIFont.systemFont(ofSize: 22 * fontScale)
        let avail = view.bounds.width - 16
        let cols = max(5, min(7, Int(avail / 62)))               // 等寬欄（原廠約 6 欄，§91）
        let cellW = avail / CGFloat(cols)
        let arr = Array(cands)
        var i = 0
        while i < arr.count {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 0
            rowStack.distribution = .fill
            var placed = 0
            while placed < cols, i < arr.count {
                let (absIdx, cand) = arr[i]
                rowStack.addArrangedSubview(expandedCandButton(cand.text, absoluteIndex: absIdx, font: font, width: cellW))
                placed += 1; i += 1
            }
            if placed < cols {                                   // 末列補 spacer 維持左對齊
                let spacer = UIView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                rowStack.addArrangedSubview(spacer)
            }
            vstack.addArrangedSubview(rowStack)
            if i < arr.count {                                   // 列間細橫線（原廠分隔，§91）
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                vstack.addArrangedSubview(sep)
            }
        }

        NSLayoutConstraint.activate([
            vstack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            vstack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            vstack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
            vstack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -4),
            vstack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -16),
        ])

        keyRowsStack.isHidden = true
        rootStack.addArrangedSubview(scroll)
        expandedPanel = scroll
        isExpanded = true
        expandButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
    }

    private func expandedCandButton(_ text: String, absoluteIndex: Int, font: UIFont, width: CGFloat) -> UIButton {
        let b = KeyButton(frame: .zero)
        b.setTitle(text, for: .normal)
        b.titleLabel?.font = font
        b.titleLabel?.adjustsFontSizeToFitWidth = true           // 長詞縮放不溢出欄（§91）
        b.titleLabel?.minimumScaleFactor = 0.6
        b.titleLabel?.lineBreakMode = .byClipping
        b.setTitleColor(.black, for: .normal)
        b.backgroundColor = .clear                               // 原廠扁平無框（§91）
        b.restingColor = .clear
        b.pressedColor = UIColor(white: 0.6, alpha: 0.3)         // 按下淡灰（非白框）
        b.widthAnchor.constraint(equalToConstant: width).isActive = true
        b.heightAnchor.constraint(equalToConstant: 46).isActive = true
        b.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.apply(self.engine.selectCandidateAbsolute(absoluteIndex))
            if self.isExpanded { self.collapseExpanded() }   // 選字後收合回候選列（§89）
        }, for: .touchUpInside)
        return b
    }

    /// 字形可顯示性檢測（§69）：任一字落到 LastResort 字型＝tofu → 不可顯示。per-scalar 快取。
    private static var glyphCache: [Unicode.Scalar: Bool] = [:]
    private static func isRenderable(_ text: String) -> Bool {
        let base = UIFont.systemFont(ofSize: 17) as CTFont
        for sc in text.unicodeScalars {
            if sc.value < 0x2E80 { continue }                      // ASCII/常見符號一律可顯示，免查
            if let c = glyphCache[sc] { if !c { return false }; continue }
            let ns = String(sc) as NSString
            let sub = CTFontCreateForString(base, ns as CFString, CFRange(location: 0, length: ns.length))
            let ok = !((CTFontCopyPostScriptName(sub) as String).contains("LastResort"))
            glyphCache[sc] = ok
            if !ok { return false }
        }
        return true
    }

    /// 無組字時的常用符號快捷列（點即插，§35 #1）。表情/顏文字改由功能列 😀 開面板（§37）。
    private func showQuickSymbols() {
        for sym in BopomoLayout.quickSymbols {
            let b = UIButton(type: .system)
            b.setTitle(sym, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 19 * fontScale)
            b.setTitleColor(.darkGray, for: .normal)
            b.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.insertText(sym) }, for: .touchUpInside)
            candidateStack.addArrangedSubview(b)
        }
    }

    // MARK: - 顏文字面板（§36 #3）

    private func showKaomojiPanel() {
        guard kaomojiPanel == nil else { return }
        let panel = KaomojiPanel(frame: .zero)
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.onInsert = { [weak self] s in self?.textDocumentProxy.insertText(s) }
        panel.onClose = { [weak self] in self?.hideKaomojiPanel() }
        panel.onDelete = { [weak self] in self?.tapBackspace() }   // ⌫ 刪除（§61）
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        kaomojiPanel = panel
    }

    private func hideKaomojiPanel() {
        kaomojiPanel?.removeFromSuperview()
        kaomojiPanel = nil
    }

    // 語音：自訂鍵盤無法錄音/叫起 iOS 聽寫（§32 #2）→ 鍵盤端不提供觸發。
    // 容器 App 若有錄音結果（手動開 App 錄製），viewWillAppear 仍會掃描上字。
}
