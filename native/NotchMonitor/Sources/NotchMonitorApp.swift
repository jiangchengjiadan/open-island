import SwiftUI
import Combine

@main
struct NotchMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panelWindow: NotchPanelWindow?
    var onboardingWindow: SetupGuideWindow?
    var mouseMonitor: Any?
    var localMouseMonitor: Any?
    var permissionAttentionObserver: AnyCancellable?
    var bootstrapObserver: AnyCancellable?
    var onboardingObserver: AnyCancellable?
    var socketStartObserver: AnyCancellable?
    var delayedSocketStartWorkItem: DispatchWorkItem?
    private var hadPendingPermission = false
    private var didStartSocketService = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "NotchMonitor")
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 创建面板窗口并显示
        panelWindow = NotchPanelWindow()
        panelWindow?.orderFrontRegardless()

        // 自动安装 hooks / wrapper 并启动内置 bridge
        AppBootstrapService.shared.startIfNeeded()

        // 等 bridge 起稳后再接 socket，避免 DMG 首启时 process fallback 和 socket 注册打架
        scheduleSocketStartup()
        observePermissionAttention()
        observeBootstrapState()
        observeOnboardingState()

        // 启动鼠标监听
        startMouseMonitoring()

        // 注册退出处理
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        // 处理 SIGINT (Ctrl+C)
        signal(SIGINT) { _ in
            NSApplication.shared.terminate(nil)
        }

        print("NotchMonitor 启动完成")
        print("点击灵动岛或状态栏图标可展开面板")
    }

    @objc func handleStatusItemClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        togglePanel()
    }

    @objc func togglePanel() {
        print("togglePanel 被调用")
        panelWindow?.toggle()
    }

    @objc func openSetupGuide() {
        AppBootstrapService.shared.presentOnboarding()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func appWillTerminate() {
        cleanup()
    }

    func cleanup() {
        AppBootstrapService.shared.stop()
        permissionAttentionObserver?.cancel()
        permissionAttentionObserver = nil
        bootstrapObserver?.cancel()
        bootstrapObserver = nil
        onboardingObserver?.cancel()
        onboardingObserver = nil
        socketStartObserver?.cancel()
        socketStartObserver = nil
        delayedSocketStartWorkItem?.cancel()
        delayedSocketStartWorkItem = nil
        onboardingWindow?.close()
        onboardingWindow = nil
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        panelWindow?.close()
        panelWindow = nil
    }

    func observePermissionAttention() {
        permissionAttentionObserver?.cancel()
        permissionAttentionObserver = SocketService.shared.$agents
            .receive(on: RunLoop.main)
            .sink { [weak self] agents in
                guard let self else { return }
                let hasPendingPermission = agents.contains { $0.needsPermission }
                if hasPendingPermission && !self.hadPendingPermission {
                    print("检测到新的权限审批，主动展开面板")
                    self.panelWindow?.expandForAttention()
                }
                self.hadPendingPermission = hasPendingPermission
            }
    }

    func observeBootstrapState() {
        bootstrapObserver?.cancel()
        bootstrapObserver = Publishers.CombineLatest(
            AppBootstrapService.shared.$checks,
            AppBootstrapService.shared.$isBootstrapping
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.panelWindow?.refreshCollapsedSummary()
            self?.panelWindow?.refreshExpandedLayoutIfNeeded()
        }
    }

    func observeOnboardingState() {
        onboardingObserver?.cancel()
        onboardingObserver = AppBootstrapService.shared.$shouldPresentOnboarding
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldPresent in
                guard let self else { return }
                if shouldPresent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        self.presentOnboardingIfNeeded()
                    }
                } else {
                    self.onboardingWindow?.orderOut(nil)
                }
            }
    }

    func scheduleSocketStartup() {
        socketStartObserver?.cancel()
        socketStartObserver = AppBootstrapService.shared.$isBridgeRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] isRunning in
                guard let self else { return }
                if isRunning {
                    self.startSocketServiceIfNeeded()
                }
            }

        let fallback = DispatchWorkItem { [weak self] in
            self?.startSocketServiceIfNeeded()
        }
        delayedSocketStartWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: fallback)
    }

    func startSocketServiceIfNeeded() {
        guard !didStartSocketService else { return }
        didStartSocketService = true
        delayedSocketStartWorkItem?.cancel()
        delayedSocketStartWorkItem = nil
        SocketService.shared.startListening()
    }

    func presentOnboardingIfNeeded() {
        if onboardingWindow == nil {
            onboardingWindow = SetupGuideWindow()
        }
        onboardingWindow?.showWindow()
    }

    func showStatusMenu() {
        let menu = NSMenu()
        let setupItem = NSMenuItem(title: "Open Setup Guide", action: #selector(openSetupGuide), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        let retryItem = NSMenuItem(title: "Run Setup Again", action: #selector(runSetupAgain), keyEquivalent: "")
        retryItem.target = self
        menu.addItem(retryItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Open Island", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc func runSetupAgain() {
        AppBootstrapService.shared.retrySetup()
    }

    func startMouseMonitoring() {
        // 检查是否有辅助功能权限
        let hasPermission = AXIsProcessTrusted()
        print("辅助功能权限状态: \(hasPermission ? "已授权" : "未授权")")

        if !hasPermission {
            // 请求权限
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            print("需要辅助功能权限才能启用鼠标悬停展开功能")
            print("请在系统偏好设置 > 隐私与安全性 > 辅助功能 中授权")
            print("授权后请重启应用")
        }

        // 监听全局鼠标移动
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMoved(event)
        }

        // 同时监听本地事件（当应用处于前台时）
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }

        print("鼠标监听已启动")
    }

    func handleMouseMoved(_ event: NSEvent) {
        guard let panel = panelWindow, let screen = NSScreen.main else { return }

        // 如果正在动画中，不处理
        if panel.isAnimating {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = screen.frame

        // 定义触发区域：屏幕顶部中间 200pt 宽度，顶部 50pt 高度
        let triggerWidth: CGFloat = 260
        let triggerHeight: CGFloat = 64
        let triggerRect = NSRect(
            x: screenFrame.midX - triggerWidth / 2,
            y: screenFrame.maxY - triggerHeight,
            width: triggerWidth,
            height: triggerHeight
        )

        // 检查鼠标是否在触发区域
        if triggerRect.contains(mouseLocation) {
            panel.cancelScheduledCollapse()
            if !panel.isExpanded {
                print("鼠标进入触发区域，展开面板")
                panel.expand()
            }
        } else if panel.isExpanded {
            let keepRect = panel.hoverKeepRect(for: screen)

            if keepRect.contains(mouseLocation) {
                panel.cancelScheduledCollapse()
            } else {
                panel.scheduleCollapse()
            }
        }
    }

    deinit {
        cleanup()
    }
}

// MARK: - Clickable Notch View
class ClickableNotchView: NSView {
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        print("ClickableNotchView 被点击")
        onClicked?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class SetupGuideWindow: NSPanel {
    private var hostingController: NSHostingController<OnboardingSetupView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = OnboardingSetupView()
        let controller = NSHostingController(rootView: rootView)
        controller.view.frame = NSRect(x: 0, y: 0, width: 560, height: 460)
        contentViewController = controller
        hostingController = controller
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        positionWindow()
    }

    func showWindow() {
        positionWindow()
        alphaValue = 1
        orderFrontRegardless()
    }

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let width: CGFloat = 560
        let height: CGFloat = 460
        let x = frame.midX - width / 2
        let y = frame.maxY - height - 72
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

// MARK: - Notch Panel Window
class NotchPanelWindow: NSPanel {
    private(set) var isExpanded = false
    private(set) var isAnimating = false
    private var notchView: NSView?
    private var collapseTimer: Timer?
    private var hoverCheckTimer: Timer?
    private var panelHostingController: NSViewController?
    private var agentCountLabel: NSTextField?
    private var collapsedTitleLabel: NSTextField?
    private var collapsedStatusGlow: NSView?
    private var collapsedStatusLight: NSView?
    private var agentsObserver: AnyCancellable?

    // 尺寸配置
    private let collapsedSize = NSSize(width: 226, height: 40)
    private let expandedWidth: CGFloat = 520
    private let topInset: CGFloat = 0

    init() {
        // 初始化为收起状态
        super.init(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.acceptsMouseMovedEvents = true

        // 创建灵动岛视图
        setupNotchView()

        // 定位到刘海处
        positionWindow()
    }

    private func setupNotchView() {
        // 创建可点击的灵动岛容器
        let notchContainer = ClickableNotchView(frame: NSRect(origin: .zero, size: collapsedSize))
        notchContainer.wantsLayer = true
        notchContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.98).cgColor
        notchContainer.layer?.cornerRadius = 18
        notchContainer.layer?.masksToBounds = true
        notchContainer.onClicked = { [weak self] in
            self?.expand()
        }

        // 添加边框
        notchContainer.layer?.borderWidth = 0.5
        notchContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor

        let statusGlow = NSView(frame: NSRect(x: 18, y: 12, width: 18, height: 18))
        statusGlow.wantsLayer = true
        statusGlow.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.28).cgColor
        statusGlow.layer?.cornerRadius = 9
        statusGlow.layer?.shadowColor = NSColor.systemGreen.cgColor
        statusGlow.layer?.shadowOpacity = 0.9
        statusGlow.layer?.shadowRadius = 10
        statusGlow.layer?.shadowOffset = .zero
        notchContainer.addSubview(statusGlow)
        self.collapsedStatusGlow = statusGlow

        let statusLight = NSView(frame: NSRect(x: 22, y: 16, width: 10, height: 10))
        statusLight.wantsLayer = true
        statusLight.layer?.backgroundColor = NSColor.systemGreen.cgColor
        statusLight.layer?.cornerRadius = 5
        notchContainer.addSubview(statusLight)
        self.collapsedStatusLight = statusLight

        let titleLabel = NSTextField(labelWithString: collapsedSummaryText(for: SocketService.shared.agents))
        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        titleLabel.lineBreakMode = .byTruncatingTail
        notchContainer.addSubview(titleLabel)
        self.collapsedTitleLabel = titleLabel

        let countLabel = NSTextField(labelWithString: collapsedCountText(for: SocketService.shared.agents))
        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        countLabel.alignment = .right
        countLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        notchContainer.addSubview(countLabel)
        self.agentCountLabel = countLabel

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: notchContainer.leadingAnchor, constant: 56),
            titleLabel.centerYAnchor.constraint(equalTo: notchContainer.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),

            countLabel.trailingAnchor.constraint(equalTo: notchContainer.trailingAnchor, constant: -18),
            countLabel.centerYAnchor.constraint(equalTo: notchContainer.centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: 18)
        ])

        self.contentView = notchContainer
        self.notchView = notchContainer
        observeAgentCountIfNeeded()
    }

    private func observeAgentCountIfNeeded() {
        guard agentsObserver == nil else { return }

        agentsObserver = SocketService.shared.$agents
            .receive(on: RunLoop.main)
            .sink { [weak self] agents in
                self?.agentCountLabel?.stringValue = self?.collapsedCountText(for: agents) ?? ""
                self?.collapsedTitleLabel?.stringValue = self?.collapsedSummaryText(for: agents) ?? ""
                self?.updateCollapsedStatusLight(for: agents)
                self?.refreshExpandedLayoutIfNeeded()
            }
    }

    func positionWindow() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let size = isExpanded ? expandedSize : collapsedSize

        // 计算刘海区域位置（居中）
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height - topInset

        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hoverKeepRect(for screen: NSScreen? = NSScreen.main) -> NSRect {
        guard let screen else {
            return frame.insetBy(dx: -16, dy: -16)
        }

        let screenFrame = screen.frame
        let triggerRect = NSRect(
            x: screenFrame.midX - 130,
            y: screenFrame.maxY - 42,
            width: 260,
            height: 42
        )

        return frame
            .insetBy(dx: -16, dy: -16)
            .union(triggerRect.insetBy(dx: -12, dy: -12))
    }

    func expand() {
        guard !isExpanded, !isAnimating else { return }
        cancelScheduledCollapse()
        isAnimating = true
        isExpanded = true
        let expandedSize = currentExpandedSize()

        // 创建展开后的内容视图
        let contentView = NotchPanelView()
            .environmentObject(SocketService.shared)
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = NSRect(origin: .zero, size: expandedSize)
        panelHostingController = hostingController
        self.contentViewController = hostingController
        self.contentMinSize = expandedSize
        self.contentMaxSize = expandedSize
        self.setContentSize(expandedSize)
        self.contentView?.frame = NSRect(origin: .zero, size: expandedSize)

        let targetFrame = anchoredFrame(for: expandedSize)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true

            self.animator().setFrame(targetFrame, display: true)
            self.alphaValue = 1
        } completionHandler: {
            self.isAnimating = false
            self.startHoverChecking()
            print("面板展开完成")
        }

        self.makeKeyAndOrderFront(nil)
    }

    func expandForAttention() {
        cancelScheduledCollapse()
        if isExpanded {
            makeKeyAndOrderFront(nil)
            return
        }
        expand()
    }

    func collapse() {
        guard isExpanded, !isAnimating else { return }
        guard !shouldStayExpandedForAttention() else { return }
        cancelScheduledCollapse()
        stopHoverChecking()
        isAnimating = true
        isExpanded = false

        let targetFrame = anchoredFrame(for: collapsedSize)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            context.allowsImplicitAnimation = true

            self.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            self.contentViewController = nil
            self.panelHostingController = nil
            self.contentMinSize = self.collapsedSize
            self.contentMaxSize = self.collapsedSize
            self.setContentSize(self.collapsedSize)
            self.setupNotchView()
            self.positionWindow()
            self.isAnimating = false
            print("面板收起完成")
        }
    }

    func scheduleCollapse() {
        guard isExpanded, !isAnimating else { return }
        guard !shouldStayExpandedForAttention() else { return }
        guard collapseTimer == nil else { return }

        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.collapseTimer = nil
            print("鼠标离开面板区域，收起面板")
            self.collapse()
        }
    }

    func cancelScheduledCollapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
    }

    func startHoverChecking() {
        hoverCheckTimer?.invalidate()
        hoverCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, self.isExpanded, !self.isAnimating else { return }
            if self.shouldStayExpandedForAttention() {
                self.cancelScheduledCollapse()
                return
            }
            let mouseLocation = NSEvent.mouseLocation
            if !self.hoverKeepRect().contains(mouseLocation) {
                self.scheduleCollapse()
            } else {
                self.cancelScheduledCollapse()
            }
        }
    }

    func stopHoverChecking() {
        hoverCheckTimer?.invalidate()
        hoverCheckTimer = nil
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    private func anchoredFrame(for size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: frame.origin, size: size)
        }

        let screenFrame = screen.frame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height - topInset
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func refreshCollapsedSummary() {
        let agents = SocketService.shared.agents
        agentCountLabel?.stringValue = collapsedCountText(for: agents)
        collapsedTitleLabel?.stringValue = collapsedSummaryText(for: agents)
        updateCollapsedStatusLight(for: agents)
    }

    func refreshExpandedLayoutIfNeeded() {
        guard isExpanded, !isAnimating else { return }

        let targetSize = currentExpandedSize()
        if abs(frame.width - targetSize.width) < 0.5 && abs(frame.height - targetSize.height) < 0.5 {
            return
        }

        contentMinSize = targetSize
        contentMaxSize = targetSize
        setContentSize(targetSize)
        contentView?.frame = NSRect(origin: .zero, size: targetSize)
        setFrame(anchoredFrame(for: targetSize), display: true, animate: true)
    }

    private func shouldStayExpandedForAttention() -> Bool {
        SocketService.shared.agents.contains { $0.needsPermission }
    }

    private func collapsedSummaryText(for agents: [Agent]) -> String {
        if agents.isEmpty, AppBootstrapService.shared.hasBlockingIssue {
            return shortTitle(for: AppBootstrapService.shared.headline)
        }
        if let priorityAgent = agents.first(where: { $0.needsPermission }) {
            return shortTitle(for: priorityAgent.permissionRequest?.message ?? priorityAgent.currentTask ?? priorityAgent.name)
        }
        if let priorityAgent = agents.first(where: { $0.interactivePrompt != nil }) {
            return shortTitle(for: priorityAgent.interactivePrompt?.title ?? priorityAgent.currentTask ?? priorityAgent.name)
        }
        if let firstAgent = agents.first {
            return shortTitle(for: firstAgent.currentTask ?? firstAgent.name)
        }
        return "Open Island"
    }

    private func collapsedCountText(for agents: [Agent]) -> String {
        if agents.isEmpty, AppBootstrapService.shared.hasBlockingIssue {
            return "!"
        }
        let count = agents.count
        return count > 0 ? "\(count)" : ""
    }

    private func shortTitle(for text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.isEmpty {
            return "Open Island"
        }
        return String(compact.prefix(28))
    }

    private func updateCollapsedStatusLight(for agents: [Agent]) {
        let color: NSColor
        if AppBootstrapService.shared.hasBlockingIssue {
            color = NSColor.systemOrange
        } else if agents.contains(where: { $0.needsPermission }) {
            color = NSColor.systemOrange
        } else if agents.contains(where: { $0.status == .error }) {
            color = NSColor.systemRed
        } else if agents.contains(where: { $0.status == .waiting }) {
            color = NSColor.systemYellow
        } else if AppBootstrapService.shared.isBootstrapping {
            color = NSColor.systemBlue
        } else {
            color = NSColor.systemGreen
        }

        collapsedStatusLight?.layer?.backgroundColor = color.cgColor
        collapsedStatusGlow?.layer?.shadowColor = color.cgColor
        collapsedStatusGlow?.layer?.backgroundColor = color.withAlphaComponent(0.24).cgColor
    }

    private var expandedSize: NSSize {
        currentExpandedSize()
    }

    private func currentExpandedSize() -> NSSize {
        let agentCount = SocketService.shared.agents.count
        if agentCount == 0 {
            let issueCount = AppBootstrapService.shared.checks.filter { $0.state != .ready }.count
            let height: CGFloat
            if issueCount == 0 {
                height = 132
            } else {
                height = min(286, CGFloat(112 + (min(issueCount, 4) * 42)))
            }
            return NSSize(width: expandedWidth, height: height)
        }

        let visibleAgents = Array(SocketService.shared.agents.prefix(6))
        let rowsHeight = visibleAgents.reduce(CGFloat(0)) { total, agent in
            total + expandedRowHeight(for: agent)
        }
        let height = 16 + rowsHeight
        return NSSize(width: expandedWidth, height: height)
    }

    private func expandedRowHeight(for agent: Agent) -> CGFloat {
        if agent.needsPermission || agent.interactivePrompt != nil {
            return 98
        }
        return 54
    }

    deinit {
        collapseTimer?.invalidate()
        hoverCheckTimer?.invalidate()
        agentsObserver?.cancel()
    }
}

// MARK: - NSColor Extension
extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
