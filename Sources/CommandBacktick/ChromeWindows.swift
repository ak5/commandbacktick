import AppKit
import ScriptingBridge
import Carbon

struct ChromeWindow {
    let id: Int
    let title: String
    let minimized: Bool

    init(id: Any?, title: Any?, minimized: Any?) throws {
        let number = (id as? NSNumber)?.intValue ?? (id as? String).flatMap(Int.init)
        guard let number, number > 0, let title = title as? String, let minimized = minimized as? Bool else {
            throw EngineError.failed("Chrome returned incomplete window information. Try again.")
        }
        self.id = number; self.title = title; self.minimized = minimized
    }
}

private final class ChromeEventErrors: NSObject, SBApplicationDelegate {
    var failed = false
    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
        failed = true
        return nil
    }
}

final class ChromeWindows {
    private let application: SBApplication
    private let errors = ChromeEventErrors()

    init(pid: pid_t) throws {
        guard let application = SBApplication(processIdentifier: pid) else {
            throw EngineError.failed("The selected Chrome process is no longer available. Try again.")
        }
        self.application = application
        application.delegate = errors
    }

    private func check() throws {
        guard !errors.failed else {
            // Apple-event errors can include browser data; report only a fixed message.
            throw EngineError.failed("Chrome window access failed. Allow CommandBacktick → Google Chrome in Privacy & Security → Automation, then retry.")
        }
    }

    // Chrome exposes minimized as the scripting property pmnd (0x706d6e64).
    func windows() throws -> [ChromeWindow] {
        let objects = application.elementArray(withCode: DescType(cWindow)).get() as? [SBObject]
        try check()
        guard let objects else { throw EngineError.failed("Chrome did not return a valid window list. Try again.") }
        return try objects.map { window in
            let rawID = window.property(withCode: AEKeyword(pID)).get()
            let title = window.property(withCode: AEKeyword(pName)).get() as? String
            let minimized = window.property(withCode: 0x706d6e64).get() as? Bool
            try check()
            return try ChromeWindow(id: rawID, title: title, minimized: minimized)
        }
    }

    func activate(id: Int) throws {
        guard let window = application.elementArray(withCode: DescType(cWindow)).object(withID: String(id)) as? SBObject else {
            throw EngineError.failed("The selected Chrome window is no longer available. Try again.")
        }
        window.property(withCode: 0x706d6e64).setTo(false)
        try check()
        window.property(withCode: AEKeyword(pIndex)).setTo(1)
        try check()
        application.activate()
        try check()
    }
}
