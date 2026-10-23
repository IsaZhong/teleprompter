// 录屏提词器 (macOS)
// 编译运行: swiftc teleprompter.swift -o teleprompter && ./teleprompter
// 窗口设为 sharingType = .none：屏幕上可见，录屏时不会被录进去。
// 文字和设置自动保存，下次打开还在。

import Cocoa

let textKey = "teleprompterText"
let defaultText = """
点"编辑"，把这里的文字删掉，粘贴或输入你的提词。
点"完成"后，用"播放"自动滚动，或者直接用鼠标滚轮滚动。
"""

// (名称, 文字颜色, 背景颜色, 文字阴影颜色, 窗口外观)
let colorOptions: [(String, NSColor, NSColor, NSColor, NSAppearance.Name)] = [
    ("白字黑底", .white, .black, .black, .darkAqua),
    ("黑字白底", .black, .white, .white, .aqua),
]

// 没有菜单栏时，手动接上 Cmd+X/C/V/A/Z
final class PromptPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
            var action: Selector?
            switch key {
            case "x": action = #selector(NSText.cut(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            case "z": action = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
            default: action = nil
            }
            if let a = action, NSApp.sendAction(a, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class Prompter: NSObject, NSWindowDelegate, NSTextViewDelegate {
    let panel: NSPanel
    let scrollView: NSScrollView
    let textView: NSTextView

    var editButton: NSButton!
    var playButton: NSButton!
    let speedLabel = NSTextField(labelWithString: "")
    let alphaLabel = NSTextField(labelWithString: "")
    var alphaSlider: NSSlider!
    var colorPopup: NSPopUpButton!

    var editing = false
    var timer: Timer?
    var lastTick = Date()

    // 设置（自动保存）
    var speed: CGFloat = 40         // 每秒滚动的像素
    var fontSize: CGFloat = 30
    var bgAlpha: CGFloat = 0.75     // 背景不透明度，0 = 全透明
    var colorIndex = 0

    override init() {
        let sv = NSTextView.scrollableTextView()
        scrollView = sv
        textView = sv.documentView as! NSTextView
        panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        super.init()

        loadSettings()

        panel.isOpaque = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true   // 播放时点按钮不抢浏览器焦点
        panel.hidesOnDeactivate = false
        panel.sharingType = .none             // 录屏不录这个窗口
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 480, height: 220)
        panel.delegate = self

        buildUI()
        textView.string = UserDefaults.standard.string(forKey: textKey) ?? defaultText
        applyBackground()
        applyStyle()
        setEditing(false)
        updateSpeedLabel()

        if let f = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.maxX - 680, y: f.maxY - 500))
        }
        panel.orderFrontRegardless()
    }

    // MARK: 设置

    func loadSettings() {
        let d = UserDefaults.standard
        if d.object(forKey: "speed") != nil { speed = CGFloat(d.double(forKey: "speed")) }
        if d.object(forKey: "fontSize") != nil { fontSize = CGFloat(d.double(forKey: "fontSize")) }
        if d.object(forKey: "bgAlpha") != nil { bgAlpha = CGFloat(d.double(forKey: "bgAlpha")) }
        let idx = d.integer(forKey: "colorIndex")
        colorIndex = (idx >= 0 && idx < colorOptions.count) ? idx : 0
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(Double(speed), forKey: "speed")
        d.set(Double(fontSize), forKey: "fontSize")
        d.set(Double(bgAlpha), forKey: "bgAlpha")
        d.set(colorIndex, forKey: "colorIndex")
    }

    // MARK: UI

    func makeButton(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return b
    }

    func makeLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    func buildUI() {
        editButton = makeButton("编辑", #selector(toggleEdit))
        playButton = makeButton("▶ 播放", #selector(togglePlay))
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        speedLabel.textColor = .secondaryLabelColor

        let row1 = NSStackView(views: [
            editButton, playButton,
            makeButton("慢", #selector(slower)), speedLabel, makeButton("快", #selector(faster)),
            makeButton("A-", #selector(smaller)), makeButton("A+", #selector(bigger)),
            makeButton("回到开头", #selector(toTop)),
            makeButton("清空", #selector(clearText)),
        ])
        row1.orientation = .horizontal
        row1.spacing = 4

        alphaSlider = NSSlider(value: Double(bgAlpha), minValue: 0, maxValue: 1,
                               target: self, action: #selector(alphaChanged))
        alphaSlider.controlSize = .small
        alphaSlider.isContinuous = true
        alphaSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        alphaLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        alphaLabel.textColor = .secondaryLabelColor

        colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        colorPopup.controlSize = .small
        colorPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        colorPopup.addItems(withTitles: colorOptions.map { $0.0 })
        colorPopup.selectItem(at: colorIndex)
        colorPopup.target = self
        colorPopup.action = #selector(colorChanged)

        let row2 = NSStackView(views: [
            makeLabel("背景透明度"), alphaSlider, alphaLabel,
            makeLabel("   配色"), colorPopup,
        ])
        row2.orientation = .horizontal
        row2.spacing = 6

        for v in [row1, row2, scrollView] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        textView.delegate = self
        textView.isRichText = false            // 粘贴时去掉原格式
        textView.allowsUndo = true             // 编辑时可 Cmd+Z 撤销
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)

        let content = panel.contentView!
        content.addSubview(row1)
        content.addSubview(row2)
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            row1.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            row1.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            row1.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
            row2.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 6),
            row2.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            row2.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: row2.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    func applyBackground() {
        let option = colorOptions[colorIndex]
        panel.appearance = NSAppearance(named: option.4)
        panel.backgroundColor = option.2.withAlphaComponent(bgAlpha)
        alphaLabel.stringValue = "\(Int((1 - bgAlpha) * 100))%"
    }

    func applyStyle() {
        let color = colorOptions[colorIndex].1
        let shadowColor = colorOptions[colorIndex].3
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = fontSize * 0.35
        ps.paragraphSpacing = fontSize * 0.6
        let shadow = NSShadow()                 // 背景透明时文字也看得清
        shadow.shadowColor = shadowColor.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: ps,
            .shadow: shadow,
        ]
        if let storage = textView.textStorage {
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
        textView.typingAttributes = attrs
        textView.insertionPointColor = color
    }

    func updateSpeedLabel() { speedLabel.stringValue = "速度 \(Int(speed))" }

    @objc func alphaChanged() {
        bgAlpha = CGFloat(alphaSlider.doubleValue)
        applyBackground()
        saveSettings()
    }

    @objc func colorChanged() {
        colorIndex = max(0, colorPopup.indexOfSelectedItem)
        applyBackground()
        applyStyle()
        saveSettings()
    }

    // MARK: 编辑

    func setEditing(_ on: Bool) {
        editing = on
        textView.isEditable = on
        textView.isSelectable = on
        editButton.title = on ? "完成" : "编辑"
        panel.title = on ? "提词器 · 编辑中" : "提词器"
        if on {
            stopPlay()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(textView)
        } else {
            panel.makeFirstResponder(nil)
            saveText()
        }
    }

    @objc func toggleEdit() { setEditing(!editing) }

    @objc func clearText() {
        setEditing(true)
        let range = NSRange(location: 0, length: (textView.string as NSString).length)
        if textView.shouldChangeText(in: range, replacementString: "") {
            textView.replaceCharacters(in: range, with: "")
            textView.didChangeText()       // 可 Cmd+Z 撤销
        }
    }

    func textDidChange(_ notification: Notification) {
        applyStyle()
        saveText()
    }

    func saveText() { UserDefaults.standard.set(textView.string, forKey: textKey) }

    // MARK: 滚动

    @objc func togglePlay() { timer == nil ? startPlay() : stopPlay() }

    func startPlay() {
        if editing { setEditing(false) }
        playButton.title = "❚❚ 暂停"
        lastTick = Date()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPlay() {
        timer?.invalidate()
        timer = nil
        playButton?.title = "▶ 播放"
    }

    func tick() {
        let now = Date()
        let dt = CGFloat(now.timeIntervalSince(lastTick))
        lastTick = now
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        var origin = clip.bounds.origin
        origin.y = min(maxY, origin.y + speed * dt)   // 鼠标滚动后从当前位置继续
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        if origin.y >= maxY { stopPlay() }
    }

    @objc func toTop() {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc func slower() { speed = max(10, speed - 10); updateSpeedLabel(); saveSettings() }
    @objc func faster() { speed = min(300, speed + 10); updateSpeedLabel(); saveSettings() }
    @objc func smaller() { fontSize = max(14, fontSize - 2); applyStyle(); saveSettings() }
    @objc func bigger() { fontSize = min(64, fontSize + 2); applyStyle(); saveSettings() }

    func windowWillClose(_ notification: Notification) {
        saveText()
        saveSettings()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let prompter = Prompter()
app.run()
