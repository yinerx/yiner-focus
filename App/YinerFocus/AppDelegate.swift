import AppKit
import SwiftUI
import YinerFocusCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let blocker = BrowserBlocker()
    private let hider = AppHider()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var statsWindow: NSWindow?
    private var clockTimer: Timer?
    private var pollTimer: Timer?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.onChromeChange = { [weak self] in self?.applyChrome() }
        model.onHidePopover = { [weak self] in self?.popover?.performClose(nil) }
        model.onShowSettings = { [weak self] in self?.showSettings() }
        model.onShowStats = { [weak self] in self?.showStats() }
        blocker.onUpdate = { [weak self] messages in
            self?.model.applyBrowserPoll(messages)
        }
        model.boot()
        setupStatusItem()
        setupPopover()
        setupKeys()
        hider.start(model: model)
        applyChrome()
        clockTimer = Timer.scheduledTimer(withTimeInterval: YinerDefaults.menuBarTickSeconds, repeats: true) { [weak self] _ in
            self?.model.tick()
            self?.updateStatusItem()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: YinerDefaults.blockPollSeconds, repeats: true) { [weak self] _ in
            self?.pollBrowsers()
        }
        if model.settings.showPopoverAtLaunch {
            openPopover()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.save()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(model)
        )
    }

    private func setupKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.keyCode == 53 {
                self.popover.performClose(nil)
                return nil
            }
            if event.keyCode == 49 {
                if self.isEditingText {
                    return event
                }
                self.model.toggleTimer()
                self.updateStatusItem()
                return nil
            }
            return event
        }
    }

    private var isEditingText: Bool {
        guard let responder = popover.contentViewController?.view.window?.firstResponder else { return false }
        return responder is NSTextView
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.behavior = model.settings.windowAlwaysOnTop ? .applicationDefined : .transient
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
        if model.settings.windowAlwaysOnTop {
            popover.contentViewController?.view.window?.level = .floating
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let running = model.snapshot.engine.runState == .running
        menu.addItem(item("\(running ? "暂停" : "开始")", #selector(menuToggle)))
        menu.addItem(item("打开主弹窗", #selector(menuOpen)))
        menu.addItem(item("打开设置", #selector(menuSettings)))
        menu.addItem(.separator())
        menu.addItem(item("退出银耳专注", #selector(menuQuit)))
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }

    @objc private func menuToggle() {
        model.toggleTimer()
        updateStatusItem()
    }

    @objc private func menuOpen() { openPopover() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "设置", root: SettingsView(), size: NSSize(width: 560, height: 720))
        }
        present(settingsWindow)
    }

    private func showStats() {
        if statsWindow == nil {
            statsWindow = makeWindow(title: "统计", root: StatsView(), size: NSSize(width: 760, height: 680))
        }
        present(statsWindow)
    }

    private func makeWindow<Content: View>(title: String, root: Content, size: NSSize) -> NSWindow {
        let host = NSHostingController(rootView: root.environmentObject(model))
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.minSize = NSSize(width: 480, height: 420)
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        window.level = model.settings.windowAlwaysOnTop ? .floating : .normal
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func updateStatusItem() {
        let label = model.snapshot.engine.menuBarLabel(at: model.now)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statusItem.button?.attributedTitle = NSAttributedString(
            string: label.text,
            attributes: [
                .font: font,
                .foregroundColor: StatusPalette.color(for: label.style)
            ]
        )
    }

    private func applyChrome() {
        AppearanceBridge.apply(model.settings.appearance)
        updateStatusItem()
        let level: NSWindow.Level = model.settings.windowAlwaysOnTop ? .floating : .normal
        settingsWindow?.level = level
        statsWindow?.level = level
    }

    private func pollBrowsers() {
        blocker.poll(snapshot: model.snapshot, blockPageURL: blockPageURL())
    }

    private func blockPageURL() -> URL? {
        if let url = Bundle.main.url(forResource: "YinerBlock", withExtension: "html") {
            return url
        }
        return Bundle.main.url(forResource: "YinerBlock", withExtension: "html", subdirectory: "Resources")
    }
}
