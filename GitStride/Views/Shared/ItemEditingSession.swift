import SwiftUI

/// Unsaved content belongs to the window, so navigation can ask before losing it.
@MainActor @Observable
final class ItemEditingSession {
    private(set) var reference: ItemInspectorReference?
    private(set) var original: ProjectItemDetail?
    var title = ""
    var text = ""
    var errorMessage: String?

    var isEditing: Bool { reference != nil }
    var hasChanges: Bool {
        guard let original else { return false }
        return title.trimmingCharacters(in: .whitespacesAndNewlines) != original.title || text != original.body
    }
    var canSave: Bool { hasChanges && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func begin(_ reference: ItemInspectorReference, detail: ProjectItemDetail) {
        self.reference = reference
        original = detail
        title = detail.title
        text = detail.body
        errorMessage = nil
    }

    func end() {
        reference = nil
        original = nil
        title = ""
        text = ""
        errorMessage = nil
    }

    @discardableResult
    func save(in store: ProjectStore) -> Bool {
        guard let reference, let original, canSave else { return false }
        do {
            try store.beginContentEdit(reference, contentID: original.id, title: title, body: text)
            end()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Used by navigation and native window closing before changing the current surface.
    @discardableResult
    func finishBeforeLeaving(in store: ProjectStore) -> Bool {
        guard hasChanges else { end(); return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save changes to this item?")
        alert.informativeText = String(localized: "Your changes haven’t been submitted to GitHub.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Discard Changes"))
        alert.addButton(withTitle: String(localized: "Continue Editing"))
        alert.buttons[0].isEnabled = canSave
        alert.buttons[2].keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save(in: store)
        case .alertSecondButtonReturn: end(); return true
        default: return false
        }
    }
}

/// Intercepts the native close button while preserving SwiftUI's window delegate.
struct ItemEditWindowCloseGuard: NSViewRepresentable {
    let session: ItemEditingSession
    let store: ProjectStore

    func makeNSView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        view.guardDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WindowObserver, context: Context) {
        context.coordinator.session = session
        context.coordinator.store = store
    }

    func makeCoordinator() -> CloseDelegate { CloseDelegate(session: session, store: store) }

    static func dismantleNSView(_ view: WindowObserver, coordinator: CloseDelegate) {
        coordinator.detach()
    }

    final class WindowObserver: NSView {
        var guardDelegate: CloseDelegate?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guardDelegate?.attach(to: window)
        }
    }

    final class CloseDelegate: NSObject, NSWindowDelegate {
        var session: ItemEditingSession
        var store: ProjectStore
        weak var window: NSWindow?
        weak var originalDelegate: (any NSWindowDelegate)?

        init(session: ItemEditingSession, store: ProjectStore) {
            self.session = session
            self.store = store
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            originalDelegate = window?.delegate
            window?.delegate = self
        }

        @MainActor
        func detach() {
            if window?.delegate === self { window?.delegate = originalDelegate }
            window = nil
            originalDelegate = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard session.finishBeforeLeaving(in: store) else { return false }
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (originalDelegate?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if originalDelegate?.responds(to: selector) == true { return originalDelegate }
            return super.forwardingTarget(for: selector)
        }
    }
}
