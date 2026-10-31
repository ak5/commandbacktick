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
        let native = axElements(application, kAXWindowsAttribute).filter {
            axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole
        }
        let visible = visibleBounds(pid: app.processIdentifier)
        let rows = windowMenu(app)
        var windows: [WindowChoice] = []
        if app.bundleIdentifier == "com.google.Chrome" {
            // The browser's IDs remain stable when its menu is rebuilt or a tab title changes.
            let result = try chromeScript("""
                set output to {}
                repeat with w in windows
                    set end of output to {id of w, name of w, bounds of w, minimized of w}
                end repeat
                return output
                """)
            for index in 1..<(result.numberOfItems + 1) {
                guard let row = result.atIndex(index), let id = row.atIndex(1)?.int32Value,
                      let title = row.atIndex(2)?.stringValue else { continue }
                let candidates = native.filter { axString($0, kAXTitleAttribute).hasPrefix(title) }
                let isFocused = index == 1
                let full = (isFocused ? focused : (candidates.count == 1 ? candidates.first : nil))
                    .map { axString($0, kAXTitleAttribute) } ?? ""
                windows.append(WindowChoice(id: "browser:\(id)", owner: app, title: title, fullTitle: full,
                    local: row.atIndex(4)?.booleanValue != true &&
                        (isFocused || (candidates.count == 1 && candidates.first.flatMap(axBounds).map { rect in
                            visible.contains { sameBounds($0, rect) }
                        } == true)),
                    focused: isFocused, target: .chrome(Int(id))))
            }
        } else if !rows.isEmpty {
            for row in rows {
                let matches = native.filter { axString($0, kAXTitleAttribute).hasPrefix(row.title) }
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
        switch choice.target {
        case .chrome(let id):
            _ = try chromeScript("set minimized of window id \(id) to false\nset index of window id \(id) to 1")
        case .accessibility(let element):
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            guard AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success else {
                throw EngineError.failed("The window could not be raised. Try again.")
            }
        case .menu(let ordinal):
            let fresh = windowMenu(choice.owner)
            let index = resolvedMenuIndex(original: snapshot.windows.filter { $0.owner.processIdentifier == choice.owner.processIdentifier }.map(\.title),
                                          current: fresh.map(\.title), selected: ordinal)
            let target = index.map { fresh[$0] }
            guard let target, AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success else {
                throw EngineError.failed("The app changed its Window menu. Open the switcher again.")
            }
        }
        // Raising a window does not transfer keyboard focus or the menu bar to its app.
        let application = AXUIElementCreateApplication(choice.owner.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.4)
        try await confirmAppActivation(targetPID: choice.owner.processIdentifier,
            frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            request: {
                guard !choice.owner.isTerminated else { throw EngineError.failed("The application has quit.") }
                AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
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

    private func chromeScript(_ body: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: "tell application \"Google Chrome\"\n\(body)\nend tell") else {
            throw EngineError.failed("Could not create the browser window request.")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil {
            // Do not put returned browser data in errors or logs.
            throw EngineError.failed("Chrome window access failed. Allow CommandBacktick → Google Chrome in Privacy & Security → Automation, then retry.")
        }
        return result
    }
}

@MainActor func confirmAppActivation(targetPID: pid_t, frontmostPID: () -> pid_t?,
                                    request: () throws -> Void,
                                    pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 100_000_000) }) async throws {
    let previousPID = frontmostPID()
    for _ in 0..<8 {
        try Task.checkCancellation()
        if let current = frontmostPID(), current != previousPID && current != targetPID {
            throw CancellationError()
        }
        try request()
        try await pause()
        try Task.checkCancellation()
        if frontmostPID() == targetPID { return }
    }
    throw EngineError.failed("The window was selected, but its app did not gain keyboard focus. Try again after the desktop transition finishes.")
}
