import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shortcut = Shortcut()
    private let engine = WindowEngine()
    private let panel = SwitcherPanel()
    private var statusItem: NSStatusItem!
    private let enableItem = NSMenuItem(title: "Enable Command–`", action: #selector(toggle), keyEquivalent: "")
    private let infoItem = NSMenuItem(title: "Paused", action: nil, keyEquivalent: "")
    private var snapshot: WindowSnapshot?
    private var cycle: CycleState?
    private var release = ReleaseState()
    private var timer: Timer?
    private var activationTask: Task<Void, Never>?
    private var lastError: String?
    private var activationObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private let accessibilityPermissionName = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        ? "Device Control and Data Access" : "Accessibility"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--diagnose") {
            print("Accessibility: \(AXIsProcessTrusted()); Input Monitoring: \(CGPreflightListenEventAccess())")
            NSApp.terminate(nil); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            panel.preview()
            do { try panel.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Preview rendering failed\n", stderr) }
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌘`"
        statusItem.button?.setAccessibilityLabel("CommandBacktick")
        let menu = NSMenu()
        infoItem.isEnabled = false; menu.addItem(infoItem)
        enableItem.target = self; menu.addItem(enableItem)
        add("Permissions…", #selector(permissions), to: menu)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if CommandLine.arguments.contains("--debug") {
            let diagnostics = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            add("Preview Interface", #selector(preview), to: submenu)
            add("Last Switching Error…", #selector(showLastError), to: submenu)
            diagnostics.submenu = submenu
            menu.addItem(diagnostics)
        }
        menu.addItem(.separator())
        add("Quit CommandBacktick", #selector(quit), to: menu)
        statusItem.menu = menu
        shortcut.onStep = { [weak self] direction in self?.step(direction) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let snapshot = self.snapshot,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != snapshot.app.processIdentifier else { return }
            self.cancel()
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let snapshot = self.snapshot, let cycle = self.cycle,
                  Shortcut.commandHeld else { return }
            self.panel.redisplay(snapshot: snapshot, state: cycle)
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.cancel() }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.cancel(); return event
        }
        if UserDefaults.standard.bool(forKey: "shortcutEnabled") { enable() }
        else { infoItem.title = "Paused" }
    }

    private func add(_ title: String, _ action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }
    @objc private func toggle() {
        if shortcut.active {
            cancel(); shortcut.stop(); enableItem.state = .off
            infoItem.title = "Paused"; UserDefaults.standard.set(false, forKey: "shortcutEnabled")
        } else { enable() }
    }
    private func enable() {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            report("Grant CommandBacktick \(accessibilityPermissionName) access in System Settings → Privacy & Security, then choose Enable Command–` again.")
            return
        }
        guard CGPreflightListenEventAccess() else {
            _ = CGRequestListenEventAccess()
            report("Grant CommandBacktick Input Monitoring access so it can read physical modifier keys. Relaunch the app if macOS requests it, then enable again.")
            return
        }
        do {
            try shortcut.start(); enableItem.state = .on
            infoItem.title = "Ready — hold ⌘ and tap `"
            UserDefaults.standard.set(true, forKey: "shortcutEnabled")
        } catch { report(error.localizedDescription) }
    }
    private func step(_ direction: Int) {
        activationTask?.cancel(); activationTask = nil
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else {
            cancel(); report("A required permission is missing. Check Permissions in the menu."); return
        }
        if snapshot == nil {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            release = ReleaseState()
            _ = release.update(held: Shortcut.commandHeld)
            guard release.sawHeld else {
                report("The physical Command key could not be read. Check Input Monitoring and retry while holding Command.")
                return
            }
            do {
                let value = try engine.snapshot(app)
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                snapshot = value
                cycle = CycleState(ids: value.windows.map(\.id), focused: value.windows.first(where: \.focused)?.id,
                                   local: Set(value.windows.filter(\.local).map(\.id)),
                                   stagePeers: Set(value.windows.filter(\.stagePeer).map(\.id)))
            } catch { report(error.localizedDescription); return }
        }
        guard let snapshot, cycle != nil else { return }
        cycle!.step(direction)
        panel.show(snapshot: snapshot, state: cycle!)
        if timer == nil {
            let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.005; RunLoop.main.add(t, forMode: .common); timer = t
        }
    }
    private func tick() {
        guard let snapshot, let cycle else { cancel(); return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.app.processIdentifier,
              !snapshot.app.isTerminated else { cancel(); return }
        if Shortcut.escapeHeld { cancel(); return }
        if release.update(held: Shortcut.commandHeld) {
            let selected = snapshot.windows.first { $0.id == cycle.selected }
            cancel()
            guard let selected else { return }
            activationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await self.engine.activate(selected, from: snapshot) }
                catch is CancellationError { }
                catch { self.report(error.localizedDescription) }
            }
        }
    }
    private func cancel() {
        activationTask?.cancel(); activationTask = nil
        timer?.invalidate(); timer = nil; snapshot = nil; cycle = nil; panel.hide()
    }
    private func report(_ message: String) {
        lastError = message
        infoItem.title = shortcut.active ? "Ready — last attempt failed" : "Paused — setup required"
        let alert = NSAlert()
        alert.messageText = "CommandBacktick"; alert.informativeText = message
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    @objc private func permissions() {
        let alert = NSAlert()
        alert.messageText = "CommandBacktick permissions"
        alert.informativeText = "\(accessibilityPermissionName): \(AXIsProcessTrusted() ? "allowed" : "needed")\nInput Monitoring: \(CGPreflightListenEventAccess() ? "allowed" : "needed")\n\nFind these under System Settings → Privacy & Security. Chrome also requires Automation access. Profile pictures in its data folder may require a separate browser-data prompt. Screen Recording is not used."
        alert.addButton(withTitle: "Window Control Settings")
        alert.addButton(withTitle: "Input Monitoring Settings")
        alert.addButton(withTitle: "Close")
        let answer = alert.runModal()
        if answer == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else if answer == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
    }
    @objc private func showLastError() {
        let alert = NSAlert(); alert.messageText = "Last switching error"
        alert.informativeText = lastError ?? "No switching errors recorded in this session."
        alert.runModal()
    }
    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } catch { report("Could not update launch at login: \(error.localizedDescription)") }
    }
    @objc private func preview() { panel.preview() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        cancel(); shortcut.stop()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    }
}

@main enum CommandBacktickMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
