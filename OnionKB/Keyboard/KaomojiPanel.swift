import UIKit

/// 顏文字面板（§36 #3）：分類 chip + 捲動格，點即插。覆於鍵列上方。
final class KaomojiPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onInsert: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onDelete: (() -> Void)?

    private let chipScroll = UIScrollView()
    private let chipStack = UIStackView()
    private var collection: UICollectionView!
    private var groupIndex = 0
    private var items: [String] { SymbolGroups.all.indices.contains(groupIndex) ? SymbolGroups.all[groupIndex].items : [] }
    private var isEmojiGroup: Bool { groupIndex < SymbolGroups.emojiCount }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KBColor.panel   // 原廠面板色（§102）
        if #available(iOS 26.0, *) {                                  // 上緣圓角僅 iOS 26（§94）
            layer.cornerRadius = 26
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
        }
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // 分類 chips（捲動）
        chipStack.axis = .horizontal
        chipStack.spacing = 6
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        chipScroll.showsHorizontalScrollIndicator = false
        chipScroll.addSubview(chipStack)
        for (i, g) in SymbolGroups.all.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(" \(g.chip) ", for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 17)
            b.backgroundColor = .clear                              // 原廠分類列：未選扁平（§90）
            b.layer.cornerRadius = 8
            b.layer.cornerCurve = .continuous
            b.tag = i
            b.addAction(UIAction { [weak self] _ in self?.selectGroup(i) }, for: .touchUpInside)
            chipStack.addArrangedSubview(b)
        }
        // 底列：ABC（左）· 分類 chips · ⌫（右）——比照原廠 emoji 鍵盤（§61）
        let abc = UIButton(type: .system)
        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        abc.setTitleColor(.label, for: .normal)
        abc.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        abc.setContentHuggingPriority(.required, for: .horizontal)

        let del = UIButton(type: .system)
        del.setImage(UIImage(systemName: "delete.left"), for: .normal)
        del.tintColor = .label
        del.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        del.setContentHuggingPriority(.required, for: .horizontal)
        let delLP = UILongPressGestureRecognizer(target: self, action: #selector(deleteRepeat(_:)))
        delLP.minimumPressDuration = 0.35
        del.addGestureRecognizer(delLP)

        let bottom = UIStackView(arrangedSubviews: [abc, chipScroll, del])
        bottom.axis = .horizontal
        bottom.spacing = 8
        bottom.alignment = .center
        bottom.translatesAutoresizingMaskIntoConstraints = false

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "k")
        collection.translatesAutoresizingMaskIntoConstraints = false

        addSubview(collection); addSubview(bottom)
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottom.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),
            bottom.heightAnchor.constraint(equalToConstant: 38),
            chipStack.topAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.topAnchor),
            chipStack.bottomAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.bottomAnchor),
            chipStack.leadingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.leadingAnchor),
            chipStack.trailingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.trailingAnchor),
            chipStack.heightAnchor.constraint(equalTo: chipScroll.frameLayoutGuide.heightAnchor),
        ])
        selectGroup(0)
    }

    /// ⌫ 長按連續刪除（§61）。
    private var deleteTimer: Timer?
    @objc private func deleteRepeat(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.onDelete?()
            }
        case .ended, .cancelled, .failed:
            deleteTimer?.invalidate(); deleteTimer = nil
        default: break
        }
    }

    private func selectGroup(_ i: Int) {
        groupIndex = i
        for case let b as UIButton in chipStack.arrangedSubviews {
            b.backgroundColor = (b.tag == i) ? .tertiarySystemFill : .clear   // 原廠選中灰 pill（§90/§99 動態）
        }
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int { items.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "k", for: ip)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.contentView.clipsToBounds = true
        cell.backgroundColor = isEmojiGroup ? .clear : KBColor.contentKey   // emoji 扁平、顏文字保留淡框（§90/§99）
        cell.layer.cornerRadius = isEmojiGroup ? 0 : 8
        cell.layer.cornerCurve = .continuous
        let l = UILabel(frame: cell.contentView.bounds.insetBy(dx: 4, dy: 0))
        l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        l.textAlignment = .center
        l.text = items[ip.item]
        if isEmojiGroup {
            l.font = .systemFont(ofSize: 26)       // emoji 大、等寬小格
        } else {
            l.font = .systemFont(ofSize: 16)        // 顏文字：縮放填滿不切（§38/§41）
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.5
            l.lineBreakMode = .byClipping
        }
        cell.contentView.addSubview(l)
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt ip: IndexPath) -> CGSize {
        let avail = cv.bounds.width - 16          // 扣 sectionInset
        guard avail > 0 else { return CGSize(width: 42, height: 40) }
        if isEmojiGroup {
            return CGSize(width: 42, height: 42)   // emoji：等寬小格（約 8 欄）
        }
        // 顏文字：等寬 2 欄、整齊一致（§41）
        let w = (avail - 6) / 2
        return CGSize(width: floor(w), height: 40)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        onInsert?(items[ip.item])
    }
}
