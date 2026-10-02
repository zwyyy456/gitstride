import SwiftUI

struct ItemContentEditorView: View {
    @Bindable var session: ItemEditingSession
    @Binding var showsPreview: Bool
    @FocusState private var isTitleFocused: Bool
    @State private var descriptionFocusRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $session.title, axis: .vertical)
                    .font(.title2.bold())
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .accessibilityLabel("Title")
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.isEmpty else { return .ignored }
                        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                           editor.hasMarkedText() {
                            return .ignored
                        }
                        if !showsPreview {
                            isTitleFocused = false
                            descriptionFocusRequest += 1
                        }
                        return .handled
                    }
                if let error = session.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            ZStack {
                // Keep the editor mounted so preview doesn't reset selection, undo, or scrolling.
                MarkdownSourceEditor(text: $session.text, isActive: !showsPreview,
                                     focusRequest: descriptionFocusRequest)
                    .opacity(showsPreview ? 0 : 1)
                    .allowsHitTesting(!showsPreview)
                    .accessibilityHidden(showsPreview)
                if showsPreview {
                    ItemMarkdownBodyView(markdown: session.text)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { isTitleFocused = true }
    }
}
