import SwiftUI
import MarkdownView

/// Reading, preview, and pending edits share the same local Markdown renderer.
struct ItemMarkdownBodyView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Group {
                if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No Description")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownText(markdown)
                        #if os(macOS)
                        .font(NSFont.systemFont(ofSize: NSFont.systemFontSize), for: .body)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
