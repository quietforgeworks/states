import AppKit
import ServiceManagement

private final class StatesSettingsSurface: NSView {
    let grouped: Bool
    init(grouped: Bool = false) {
        self.grouped = grouped; super.init(frame: .zero)
        if grouped { wantsLayer = true; layer?.cornerRadius = 10; layer?.masksToBounds = true }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { !grouped }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let base = NSColor.textBackgroundColor
        (grouped ? base.blended(withFraction: 0.045, of: .labelColor) ?? base : base).setFill()
        dirtyRect.fill()
    }
}

private final class StatesSettingsDocument: NSView { override var isFlipped: Bool { true } }

final class StatesSettingsController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private weak var appDelegate: StatesAppDelegate?
    private let titles = ["通用", "外观"]
    private let symbols = ["gearshape.fill", "paintpalette.fill"]
    private let navigation = NSTableView()
    private let pageHost = PageTransitionHost()
    private var pages: [NSView] = []
    private var pageTransition: PageTransitionController?
    private let interval = NSPopUpButton()
    private let menuMetric = NSPopUpButton()
    private let batterySaver = NSSwitch()
    private let login = NSSwitch()
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let appearance = NSPopUpButton()
    private let accent = NSPopUpButton()
    private let awake = NSSwitch()
    private var updating = false

    init(owner appDelegate: StatesAppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 870, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "设置"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isOpaque = true; window.backgroundColor = .textBackgroundColor
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 820, height: 570)
        super.init(window: window); window.delegate = self
        build(); refreshState(); window.setContentSize(NSSize(width: 870, height: 620)); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func label(_ value: String, title: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: value)
        view.font = .systemFont(ofSize: title ? 13 : 12)
        view.textColor = title ? .labelColor : .secondaryLabelColor
        return view
    }
    private func identify(_ view: NSView, _ value: String) {
        view.identifier = NSUserInterfaceItemIdentifier(value); view.setAccessibilityIdentifier(value)
    }
    private func configure(_ popup: NSPopUpButton, values: [(String, String)], id: String) {
        for (title, raw) in values { popup.addItem(withTitle: title); popup.lastItem?.representedObject = raw }
        popup.target = self; popup.action = #selector(changed(_:)); identify(popup, id)
    }
    private func row(_ title: String, detail: String = "", control: NSView) -> NSView {
        let labels = NSStackView(views: detail.isEmpty ? [label(title, title: true)] : [label(title, title: true), label(detail)])
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 4
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let view = NSView()
        for child in [labels, control] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal); control.setAccessibilityLabel(title)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            labels.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 12),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
            labels.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -20),
            control.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 12),
            control.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
        ])
        return view
    }
    private func group(_ rows: [NSView]) -> NSView {
        let surface = StatesSettingsSurface(grouped: true)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -3)
        ])
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = NSBox(); line.boxType = .separator; stack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return surface
    }
    private func page(_ children: [NSView]) {
        let page = StatesSettingsDocument(); page.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(page)
        let heading = NSTextField(labelWithString: titles[pages.count])
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false; page.addSubview(heading)
        let document = StatesSettingsDocument(); document.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay; scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false; page.addSubview(scroll)
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let stack = NSStackView(views: children); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            page.topAnchor.constraint(equalTo: pageHost.topAnchor),
            page.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
            heading.topAnchor.constraint(equalTo: page.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 26),
            heading.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -26),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 26),
            scroll.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -26),
            scroll.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -26)
        ])
        for child in children { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        pages.append(page)
    }
    private func button(_ title: String, id: String, action: Selector) -> NSButton {
        let view = NSButton(title: title, target: self, action: action); view.bezelStyle = .rounded; identify(view, id); return view
    }
    private func build() {
        guard let window else { return }
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
        let left = NSViewController(); left.view = sidebar
        let content = StatesSettingsSurface(); let right = NSViewController(); right.view = content
        let split = NSSplitViewController(); split.splitView.isVertical = true; split.splitView.dividerStyle = .thin
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: left)
        sidebarItem.minimumThickness = 210; sidebarItem.maximumThickness = 210; sidebarItem.canCollapse = false
        split.addSplitViewItem(sidebarItem); split.addSplitViewItem(NSSplitViewItem(viewController: right))
        window.contentViewController = split
        navigation.style = .sourceList; navigation.headerView = nil; navigation.backgroundColor = .clear
        navigation.rowHeight = 36; navigation.intercellSpacing = NSSize(width: 0, height: 4)
        navigation.dataSource = self; navigation.delegate = self; navigation.focusRingType = .none
        identify(navigation, "states-settings-navigation"); navigation.setAccessibilityLabel("设置分类")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page")); column.resizingMask = .autoresizingMask
        navigation.addTableColumn(column); navigation.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let navScroll = NSScrollView(); navScroll.drawsBackground = false; navScroll.documentView = navigation
        navScroll.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(navScroll)
        navigation.frame = NSRect(x: 0, y: 0, width: 190, height: 130); navigation.autoresizingMask = [.width]
        pageHost.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(pageHost)
        NSLayoutConstraint.activate([
            navScroll.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor, constant: 18),
            navScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            navScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            navScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16),
            pageHost.topAnchor.constraint(equalTo: content.topAnchor),
            pageHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageHost.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        configure(interval, values: [("每秒", "1"), ("每 2 秒", "2"), ("每 5 秒", "5")], id: "states-sample-interval")
        configure(menuMetric, values: [("精简概览", "compact"), ("CPU", "cpu"), ("GPU", "gpu"), ("内存", "memory"), ("功率", "power"), ("电池", "battery")], id: "states-menu-metric")
        for (control, id) in [(batterySaver, "states-battery-saver"), (login, "states-launch-at-login"), (awake, "states-keep-awake")] {
            control.target = self; control.action = #selector(changed(_:)); identify(control, id)
        }
        loginStatus.font = .systemFont(ofSize: 12); loginStatus.textColor = .secondaryLabelColor
        page([group([
            row("采样频率", control: interval),
            row("电池节能", detail: "使用电池时降低后台采样频率。", control: batterySaver),
            row("菜单栏显示", control: menuMetric)
        ]), group([row("登录时启动", control: login), row("保持唤醒 1 小时", control: awake)]), loginStatus,
              group([row("监视面板", control: button("打开面板", id: "states-open-dashboard", action: #selector(openDashboard))),
                     row("当前读数", control: button("导出快照…", id: "states-export-snapshot", action: #selector(exportSnapshot)))])])
        configure(appearance, values: [("跟随系统", "system"), ("浅色", "light"), ("深色", "dark")], id: "states-appearance")
        configure(accent, values: [("青色", "teal"), ("蓝色", "blue"), ("紫色", "purple"), ("橙色", "orange")], id: "states-accent")
        page([group([row("外观", control: appearance), row("强调色", control: accent)]),
              group([row("默认外观", detail: "跟随系统，使用青色强调。", control: button("恢复默认外观", id: "states-reset-appearance", action: #selector(resetAppearance)))])])
        pageTransition = PageTransitionController(host: pageHost, pages: pages)
        navigation.reloadData(); navigation.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func refreshState() {
        guard let appDelegate else { return }
        updating = true; defer { updating = false }
        let p = appDelegate.preferences
        for (popup, raw) in [(interval, String(Int(p.interval))), (menuMetric, p.menuMetric), (appearance, p.appearance), (accent, p.accent)] {
            if let item = popup.itemArray.first(where: { $0.representedObject as? String == raw }) { popup.select(item) }
        }
        batterySaver.state = p.batterySaver ? .on : .off
        let loginState = SMAppService.mainApp.status
        login.state = loginState == .enabled || loginState == .requiresApproval ? .on : .off
        loginStatus.stringValue = loginState == .requiresApproval ? "需要在系统设置中批准登录启动。" : ""
        loginStatus.isHidden = loginStatus.stringValue.isEmpty
        awake.state = appDelegate.awake.active ? .on : .off
        window?.appearance = p.nativeAppearance
    }
    func numberOfRows(in tableView: NSTableView) -> Int { titles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView(); let title = NSTextField(labelWithString: titles[row])
        let icon = NSImageView(image: NSImage(systemSymbolName: symbols[row], accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = [.systemGray, .systemPurple, .systemTeal][row]
        title.font = .systemFont(ofSize: 13, weight: .medium); cell.textField = title; cell.imageView = icon
        for view in [icon, title] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8)
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let index = navigation.selectedRow; guard titles.indices.contains(index) else { return }
        refreshState()
        pageTransition?.transition(to: index, animated: window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    func prepareForPresentation() { if window?.isVisible != true { pageTransition?.settle() } }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard self?.window?.isVisible != true else { return }
            self?.pageTransition?.settle()
        }
    }
    @objc private func changed(_ sender: NSControl) {
        guard !updating, let appDelegate else { return }
        if sender === login { appDelegate.setLoginEnabled(login.state == .on); refreshState(); return }
        if sender === awake {
            if awake.state == .on { if !appDelegate.awake.enable() { NSSound.beep() } }
            else { appDelegate.awake.disable() }
            refreshState(); return
        }
        let p = appDelegate.preferences
        if sender === interval { p.interval = Double(interval.selectedItem?.representedObject as? String ?? "2") ?? 2 }
        if sender === menuMetric { p.menuMetric = menuMetric.selectedItem?.representedObject as? String ?? "compact" }
        if sender === batterySaver { p.batterySaver = batterySaver.state == .on }
        if sender === appearance { p.appearance = appearance.selectedItem?.representedObject as? String ?? "system" }
        if sender === accent { p.accent = accent.selectedItem?.representedObject as? String ?? "teal" }
        appDelegate.preferencesChanged(); refreshState()
    }
    @objc private func resetAppearance() { appDelegate?.preferences.appearance = "system"; appDelegate?.preferences.accent = "teal"; appDelegate?.preferencesChanged(); refreshState() }
    @objc private func openDashboard() { appDelegate?.showDashboard() }
    @objc private func exportSnapshot() { appDelegate?.exportSnapshot() }
}
