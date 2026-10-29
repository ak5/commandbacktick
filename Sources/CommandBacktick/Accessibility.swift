import AppKit
import ApplicationServices

func axValue(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func axElements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    axValue(element, name) as? [AXUIElement] ?? []
}
func axElement(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = axValue(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
}
func axString(_ element: AXUIElement, _ name: String) -> String {
    axValue(element, name) as? String ?? ""
}

struct MenuWindow {
    let element: AXUIElement
    let title: String
    let ordinal: Int
    let focused: Bool
}
func windowMenu(_ app: NSRunningApplication) -> [MenuWindow] {
    let application = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 0.4)
    guard let bar = axElement(application, kAXMenuBarAttribute) else { return [] }
    for item in axElements(bar, kAXChildrenAttribute) where axString(item, kAXTitleAttribute) == "Window" {
        guard let menu = axElements(item, kAXChildrenAttribute).first else { continue }
        var rows: [AXUIElement] = []
        for row in axElements(menu, kAXChildrenAttribute) {
            if axString(row, kAXTitleAttribute).isEmpty { rows = [] } else { rows.append(row) }
        }
        let entries = rows.enumerated().map { index, row in
            MenuWindow(element: row, title: axString(row, kAXTitleAttribute), ordinal: index,
                       focused: !axString(row, "AXMenuItemMarkChar").isEmpty)
        }
        if entries.contains(where: \.focused) { return entries }
    }
    return []
}

struct OnScreenWindow {
    let id: CGWindowID
    let pid: pid_t
    let bounds: CGRect
}
func onScreenWindows() -> [OnScreenWindow] {
    let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return infos.compactMap { info in
        guard let pid = info[kCGWindowOwnerPID as String] as? Int,
              let id = info[kCGWindowNumber as String] as? UInt32,
              info[kCGWindowLayer as String] as? Int == 0,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let data = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: data as CFDictionary),
              bounds.width > 0, bounds.height > 0 else { return nil }
        return OnScreenWindow(id: id, pid: pid_t(pid), bounds: bounds)
    }
}
func visibleBounds(pid: pid_t) -> [CGRect] {
    onScreenWindows().filter { $0.pid == pid }.map(\.bounds)
}
func axBounds(_ element: AXUIElement) -> CGRect? {
    guard let p = axValue(element, kAXPositionAttribute), let s = axValue(element, kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
          AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
func sameBounds(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX-b.minX) < 3 && abs(a.minY-b.minY) < 3 && abs(a.width-b.width) < 3 && abs(a.height-b.height) < 3
}
