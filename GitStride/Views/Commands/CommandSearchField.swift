import SwiftUI

/// NSTextInputClient handles marked text before navigation commands reach the delegate.
struct CommandSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt = String(localized: "Search commands, projects, and loaded items")
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.setAccessibilityLabel(prompt)
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.font = .preferredFont(forTextStyle: .body)
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: CommandSearchField
        init(_ parent: CommandSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.move(-1)
            case #selector(NSResponder.moveDown(_:)): parent.move(1)
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            default: return false
            }
            return true
        }
    }
}

@MainActor
enum KeyboardInput {
    static var isEditingText: Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return responder is NSTextView || responder is NSTextField
            || (responder as? NSTextInputClient)?.hasMarkedText() == true
    }
}

/// A window-local handler whose closure is refreshed with the owning SwiftUI surface.
struct WorkspaceKeyHandler: NSViewRepresentable {
    var onPointerDown: (() -> Void)? = nil
    let handle: (NSEvent) -> Bool
    func makeNSView(context: Context) -> KeyView { KeyView(handle: handle, pointerDown: onPointerDown) }
    func updateNSView(_ view: KeyView, context: Context) { view.handle = handle; view.pointerDown = onPointerDown }
    static func dismantleNSView(_ view: KeyView, coordinator: ()) { view.stop() }

    final class KeyView: NSView {
        var handle: (NSEvent) -> Bool
        var pointerDown: (() -> Void)?
        private var monitor: Any?
        init(handle: @escaping (NSEvent) -> Bool, pointerDown: (() -> Void)?) {
            self.handle = handle
            self.pointerDown = pointerDown
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      window.isKeyWindow, window.attachedSheet == nil, !self.isHiddenOrHasHiddenAncestor else { return event }
                if event.type == .leftMouseDown { self.pointerDown?(); return event }
                guard !KeyboardInput.isEditingText else { return event }
                return self.handle(event) ? nil : event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

struct ItemSelectionKeyboard: ViewModifier {
    let ids: [String]
    @Binding var current: String?
    @Binding var selected: Set<String>
    @Binding var isSelecting: Bool
    @State private var range = ItemRangeSelection()
    @State private var scopeID = UUID()
    @FocusedValue(\.itemSelectionScope) private var focusedScope

    func body(content: Content) -> some View {
        content
        .focusedValue(\.itemSelectionScope, scopeID)
        .focusedValue(\.itemCommandScope, true)
        .background(WorkspaceKeyHandler { event in
            guard focusedScope == scopeID else { return false }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let key = event.charactersIgnoringModifiers?.lowercased()
            if modifiers == .command, key == "a" {
                guard !ids.isEmpty else { return false }
                range.reset()
                isSelecting = true
                selected = Set(ids)
                if current == nil { current = ids.first }
                return true
            }
            if modifiers.isEmpty, event.keyCode == 53, isSelecting || !selected.isEmpty {
                range.reset()
                selected = []
                isSelecting = false
                return true
            }
            if modifiers.isEmpty, key == "x", let current, ids.contains(current) {
                range.reset()
                if !isSelecting { selected = []; isSelecting = true }
                if selected.contains(current) { selected.remove(current) } else { selected.insert(current) }
                return true
            }
            if modifiers == .shift, event.keyCode == 125 || event.keyCode == 126 {
                guard let next = ItemKeyboardNavigation.next(from: current, in: ids,
                    offset: event.keyCode == 126 ? -1 : 1) else { return false }
                let existing = isSelecting ? selected : []
                selected = range.extend(from: current, to: next, in: ids, selected: existing)
                isSelecting = true
                current = next
                return true
            }
            // A new non-range gesture begins a new anchor, including ordinary navigation.
            range.reset()
            return false
        })
        .onChange(of: ids) { _, ids in
            range.reset()
            selected.formIntersection(ids)
        }

    }
}

extension View {
    func itemSelectionKeyboard(ids: [String], current: Binding<String?>,
                               selected: Binding<Set<String>>, isSelecting: Binding<Bool>) -> some View {
        modifier(ItemSelectionKeyboard(ids: ids, current: current, selected: selected, isSelecting: isSelecting))
    }
}

private struct ItemSelectionScopeKey: FocusedValueKey { typealias Value = UUID }
private struct ItemCommandScopeKey: FocusedValueKey { typealias Value = Bool }
extension FocusedValues {
    var itemSelectionScope: UUID? {
        get { self[ItemSelectionScopeKey.self] }
        set { self[ItemSelectionScopeKey.self] = newValue }
    }
    var itemCommandScope: Bool? {
        get { self[ItemCommandScopeKey.self] }
        set { self[ItemCommandScopeKey.self] = newValue }
    }
}

private struct WorkspaceSidebarScopeKey: FocusedValueKey { typealias Value = Bool }
extension FocusedValues {
    var workspaceSidebarScope: Bool? {
        get { self[WorkspaceSidebarScopeKey.self] }
        set { self[WorkspaceSidebarScopeKey.self] = newValue }
    }
}

/// Navigation sidebars use arrows and Tab, not implicit type-to-select navigation.
struct SidebarKeyboardNavigation: ViewModifier {
    @FocusedValue(\.workspaceSidebarScope) private var isFocused
    func body(content: Content) -> some View {
        content.focusedValue(\.workspaceSidebarScope, true)
            .background(WorkspaceKeyHandler { event in
                guard isFocused == true,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      let text = event.characters, !text.isEmpty else { return false }
                return text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            })
    }
}
