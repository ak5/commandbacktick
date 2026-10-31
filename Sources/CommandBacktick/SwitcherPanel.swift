import AppKit

final class SwitcherPanel {
    private var panel: NSPanel?
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("CommandBacktickSwitcher")
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        return panel
    }
    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
    func redisplay(snapshot: WindowSnapshot, state: CycleState) {
        // Recreate on the active desktop so Stage Manager cannot retain an old group assignment.
        hide()
        show(snapshot: snapshot, state: state)
    }
    func show(snapshot: WindowSnapshot, state: CycleState) {
        guard let selectedID = state.selected, let selected = snapshot.windows.first(where: { $0.id == selectedID }) else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let count = min(state.ids.count, 7, max(1, Int((screen.visibleFrame.width - 64) / 132)))
        let first = max(0, min(state.index - count / 2, state.ids.count - count))
        let width = CGFloat(count * 132 + 32)
        let height: CGFloat = 210
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
        effect.wantsLayer = true; effect.layer?.cornerRadius = 22; effect.layer?.masksToBounds = true
        for i in first..<(first + count) {
            guard let choice = snapshot.windows.first(where: { $0.id == state.ids[i] }) else { continue }
            let x = CGFloat((i - first) * 132 + 16)
            let card = NSView(frame: NSRect(x: x, y: 65, width: 128, height: 132))
            if i == state.index {
                card.wantsLayer = true; card.layer?.cornerRadius = 14
                card.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
                card.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.2).cgColor
                card.layer?.borderWidth = 1
            }
            let image = NSImageView(frame: NSRect(x: 28, y: 49, width: 72, height: 72))
            image.image = choice.owner.icon; image.imageScaling = .scaleProportionallyUpOrDown
            card.addSubview(image)
            if let badge = choice.badge {
                let avatar = NSImageView(frame: NSRect(x: 77, y: 43, width: 32, height: 32))
                avatar.image = badge; avatar.imageScaling = .scaleProportionallyUpOrDown
                avatar.wantsLayer = true; avatar.layer?.cornerRadius = 16; avatar.layer?.masksToBounds = true
                avatar.layer?.borderWidth = 2; avatar.layer?.borderColor = NSColor.windowBackgroundColor.cgColor
                card.addSubview(avatar)
            }
            let label = text(choice.title, size: 12)
            label.frame = NSRect(x: 6, y: 7, width: 116, height: 32)
            label.maximumNumberOfLines = 2
            card.addSubview(label)
            card.setAccessibilityLabel(choice.title)
            effect.addSubview(card)
        }
        let title = text(selected.profile == selected.title ? selected.title : [selected.profile, selected.title].compactMap { $0 }.joined(separator: " — "), size: 15)
        title.frame = NSRect(x: 20, y: 34, width: width - 40, height: 23)
        effect.addSubview(title)
        let countLabel = text("\(state.index + 1) of \(state.ids.count) · release ⌘ to switch · Esc to cancel", size: 11)
        countLabel.textColor = .labelColor
        countLabel.frame = NSRect(x: 20, y: 12, width: width - 40, height: 18)
        effect.addSubview(countLabel)
        panel.contentView = effect
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - width/2, y: f.midY - height/2, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
    private func text(_ value: String, size: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: size); field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        return field
    }
    func render(to url: URL) throws {
        guard let view = panel?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw EngineError.failed("No preview view")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url)
    }
    func preview() {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first ?? .current
        let windows = (1...3).map { WindowChoice(id: "\($0)", owner: app, title: "Example window \($0)", fullTitle: "", local: true,
            focused: $0 == 1, target: .menu($0)) }
        var state = CycleState(ids: windows.map(\.id), focused: "1", local: Set(windows.map(\.id)))
        state.step(1); show(snapshot: WindowSnapshot(app: app, windows: windows), state: state)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.hide() }
    }
}
