import AppKit

struct WindowChoice {
    enum Target { case chrome(Int), accessibility(AXUIElement), menu(Int) }
    let id: String
    let owner: NSRunningApplication
    var stagePeer = false
    let title: String
    var fullTitle: String
    var local: Bool
    var focused: Bool
    let target: Target
    var badge: NSImage?
    var profile: String?
}
struct WindowSnapshot {
    let app: NSRunningApplication
    let windows: [WindowChoice]
}

enum EngineError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
}

final class WindowEngine {
    // Read state on demand. No watcher can leave the shortcut permanently disabled.
    func snapshot(_ app: NSRunningApplication) throws -> WindowSnapshot {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.4)
        let focused = axElement(application, kAXFocusedWindowAttribute)
        let allNative = try applicationWindows {
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
            return (status, value as? [AXUIElement] ?? [])
        }
        let native = allNative.filter { axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
        if CommandLine.arguments.contains("--debug") {
            let roles = allNative.map { axString($0, kAXSubroleAttribute) }
            fputs("Window read: bundle=\(app.bundleIdentifier ?? "unknown") active=\(app.isActive) windows=\(allNative.count) subroles=\(roles) focused=\(focused != nil)\n", stderr)
        }
        let visible = visibleBounds(pid: app.processIdentifier)
        let rows = windowMenu(app)
        var windows: [WindowChoice] = []
        if app.bundleIdentifier == "com.google.Chrome" {
            // The browser's IDs remain stable when its menu is rebuilt or a tab title changes.
            let browserWindows = try ChromeWindows(pid: app.processIdentifier).windows()
            if CommandLine.arguments.contains("--debug") {
                fputs("Chrome window read: pid=\(app.processIdentifier) windows=\(browserWindows.count)\n", stderr)
            }
            for (index, window) in browserWindows.enumerated() {
                let id = window.id
                let title = window.title
                let candidates = native.filter { axString($0, kAXTitleAttribute).hasPrefix(title) }
                let isFocused = index == 0
                let full = (isFocused ? focused : (candidates.count == 1 ? candidates.first : nil))
                    .map { axString($0, kAXTitleAttribute) } ?? ""
                windows.append(WindowChoice(id: "browser:\(id)", owner: app, title: title, fullTitle: full,
                    local: !window.minimized &&
                        (isFocused || (candidates.count == 1 && candidates.first.flatMap(axBounds).map { rect in
                            visible.contains { sameBounds($0, rect) }
                        } == true)),
                    focused: isFocused, target: .chrome(id)))
            }
        } else if !rows.isEmpty {
            for row in rows {
                let matches = native.filter { axString($0, kAXTitleAttribute) == row.title }
                let unique = matches.count == 1 ? matches[0] : nil
                let exact = row.focused ? focused : unique
                let local = exact.flatMap(axBounds).map { rect in visible.contains { sameBounds($0, rect) } } ?? false
                windows.append(WindowChoice(id: "menu:\(row.ordinal)", owner: app, title: row.title,
                    fullTitle: exact.map { axString($0, kAXTitleAttribute) } ?? "", local: local,
                    focused: row.focused, target: .menu(row.ordinal)))
            }
        } else {
            windows = native.enumerated().map { index, element in
                let title = axString(element, kAXTitleAttribute)
                return WindowChoice(id: "ax:\(index)", owner: app, title: title, fullTitle: title,
                    local: axBounds(element).map { rect in visible.contains { sameBounds($0, rect) } } ?? false,
                    focused: focused.map { CFEqual($0, element) } ?? false, target: .accessibility(element))
            }
        }
        guard !windows.isEmpty else { throw EngineError.failed("No switchable windows were found for this app.") }
        ProfileCatalog.attach(to: &windows, bundleID: app.bundleIdentifier)
        windows += stagePeers(for: app, focusedBounds: focused.flatMap(axBounds))
        return WindowSnapshot(app: app, windows: windows)
    }

    @MainActor func activate(_ choice: WindowChoice, from snapshot: WindowSnapshot) async throws {
        try Task.checkCancellation()
        guard !choice.owner.isTerminated else { throw EngineError.failed("The application has quit.") }
        var selectedWindow: AXUIElement?
        var selectedMenuIndex: Int?
        switch choice.target {
        case .chrome(let id):
            try ChromeWindows(pid: choice.owner.processIdentifier).activate(id: id)
        case .accessibility(let element):
            selectedWindow = element
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            guard AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success else {
                throw EngineError.failed("The window could not be raised. Try again.")
            }
        case .menu(let ordinal):
            let fresh = windowMenu(choice.owner)
            let index = resolvedMenuIndex(original: snapshot.windows.filter { $0.owner.processIdentifier == choice.owner.processIdentifier }.map(\.title),
                                          current: fresh.map(\.title), selected: ordinal)
            selectedMenuIndex = index
            let target = index.map { fresh[$0] }
            guard let target, AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success else {
                throw EngineError.failed("The app changed its Window menu. Open the switcher again.")
            }
        }
        // Raising a window does not transfer keyboard focus or the menu bar to its app.
        let application = AXUIElementCreateApplication(choice.owner.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.4)
        func isVisible(_ window: AXUIElement) -> Bool {
            guard let bounds = axBounds(window) else { return false }
            return visibleBounds(pid: choice.owner.processIdentifier).contains { sameBounds($0, bounds) }
        }
        func resolveSelectedWindow() -> AXUIElement? {
            if case .accessibility(let window) = choice.target { return window }
            if let selectedWindow, isVisible(selectedWindow) { return selectedWindow }
            guard case .menu = choice.target else { return nil }
            let matches = axElements(application, kAXWindowsAttribute).filter {
                axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole &&
                    axString($0, kAXTitleAttribute) == choice.title && isVisible($0)
            }
            if matches.count == 1 { return matches[0] }
            // Identical titles need the selected menu item's mark to identify the focused window.
            let fresh = windowMenu(choice.owner)
            if let index = selectedMenuIndex, fresh.indices.contains(index),
               fresh[index].title == choice.title, fresh[index].focused {
                guard let focused = axElement(application, kAXFocusedWindowAttribute), isVisible(focused) else { return nil }
                return focused
            }
            return nil
        }
        try await confirmAppActivation(targetPID: choice.owner.processIdentifier,
            frontmostPID: {
                let foreground = NSWorkspace.shared.frontmostApplication
                return focusHandoffPID(pid: foreground?.processIdentifier, bundleID: foreground?.bundleIdentifier)
            },
            focusReady: {
                guard choice.owner.isActive,
                      let focused = axElement(application, kAXFocusedWindowAttribute),
                      isVisible(focused) else { return false }
                let ready: Bool
                if case .chrome = choice.target { ready = true }
                else { ready = selectedWindow.map { CFEqual($0, focused) } ?? false }
                if CommandLine.arguments.contains("--debug") {
                    fputs("Focus check: bundle=\(choice.owner.bundleIdentifier ?? "unknown") selected=\(selectedWindow != nil) matches=\(ready)\n", stderr)
                }
                return ready
            },
            request: {
                guard !choice.owner.isTerminated else { throw EngineError.failed("The application has quit.") }
                selectedWindow = resolveSelectedWindow()
                if let window = selectedWindow, isVisible(window) {
                    let main = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                    let raise = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    if CommandLine.arguments.contains("--debug") {
                        fputs("Focus request: main=\(main.rawValue) raise=\(raise.rawValue)\n", stderr)
                    }
                } else if case .menu = choice.target {
                    // Wait for the destination window instead of reactivating the departing desktop.
                    return
                }
                if !choice.owner.isActive {
                    AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                }
                _ = choice.owner.activate(options: [])
            })
    }

    private func stagePeers(for app: NSRunningApplication, focusedBounds: CGRect?) -> [WindowChoice] {
        // shortcut: infer the group from visible AX windows; use a public group API if macOS adds one.
        guard UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") == true,
              let focusedBounds else { return [] }
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
        guard let display = displays.first(where: { $0.contains(CGPoint(x: focusedBounds.midX, y: focusedBounds.midY)) }) else { return [] }
        var result: [WindowChoice] = []
        var nativeByPID: [pid_t: [AXUIElement]] = [:]
        for visible in onScreenWindows() where visible.pid != app.processIdentifier &&
            visible.pid != ProcessInfo.processInfo.processIdentifier {
            guard display.contains(CGPoint(x: visible.bounds.midX, y: visible.bounds.midY)),
                  let owner = NSRunningApplication(processIdentifier: visible.pid),
                  owner.activationPolicy == .regular else { continue }
            if nativeByPID[visible.pid] == nil {
                let element = AXUIElementCreateApplication(visible.pid)
                AXUIElementSetMessagingTimeout(element, 0.2)
                nativeByPID[visible.pid] = axElements(element, kAXWindowsAttribute).filter {
                    axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole &&
                    (axValue($0, kAXMinimizedAttribute) as? Bool) != true
                }
            }
            // Thumbnail/strip surfaces must not be mistaken for full-size stage windows.
            let matches = (nativeByPID[visible.pid] ?? []).filter {
                axBounds($0).map { sameBounds($0, visible.bounds) } ?? false
            }
            guard matches.count == 1, let element = matches.first else { continue }
            let title = axString(element, kAXTitleAttribute)
            var choices = [WindowChoice(id: "stage:\(visible.pid):\(visible.id)", owner: owner, stagePeer: true,
                title: title, fullTitle: title, local: true, focused: false, target: .accessibility(element))]
            ProfileCatalog.attach(to: &choices, bundleID: owner.bundleIdentifier)
            result += choices
        }
        return result
    }
}

func focusHandoffPID(pid: pid_t?, bundleID: String?) -> pid_t? {
    // WindowManager can own the menu bar temporarily while a desktop transition is in flight.
    bundleID == "com.apple.WindowManager" ? nil : pid
}

@MainActor func confirmAppActivation(targetPID: pid_t, frontmostPID: () -> pid_t?,
                                    focusReady: () -> Bool = { true },
                                    request: () throws -> Void,
                                    pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 100_000_000) }) async throws {
    let previousPID = frontmostPID()
    var confirmed = false
    for _ in 0..<8 {
        try Task.checkCancellation()
        if let current = frontmostPID(), current != previousPID && current != targetPID {
            throw CancellationError()
        }
        if !confirmed { try request() }
        try await pause()
        try Task.checkCancellation()
        let ready = frontmostPID() == targetPID && focusReady()
        if ready && confirmed { return }
        confirmed = ready
    }
    throw EngineError.failed("The window was selected, but its app did not gain keyboard focus. Try again after the desktop transition finishes.")
}
