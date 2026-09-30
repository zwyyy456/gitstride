import SwiftUI

/// Source highlighting never changes the Markdown string or its character offsets.
enum MarkdownSourceHighlighting {
    enum Kind { case marker, emphasis, link, code }
    struct Span: Equatable {
        let range: NSRange
        let kind: Kind
    }

    private static let rules: [(NSRegularExpression, Kind)] = [
        (#"`+[^`\n]+`+"#, Kind.code),
        (#"(?m)^ {0,3}(?:#{1,6}(?=\s)|>+|[-+*] \[[ xX]\]|[-+*](?=\s)|[0-9]+[.)](?=\s))"#, Kind.marker),
        (#"!?\[[^\]\n]*\]\([^\)\n]*\)"#, Kind.link),
        (#"\*\*[^*\n]+\*\*|__[^_\n]+__|(?<!\w)\*[^*\n]+\*|(?<!\w)_[^_\n]+_"#, Kind.emphasis)
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    private static let fence = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})(.*)$"#)

    static func spans(in text: String) -> [Span] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var spans: [Span] = []
        var opening: (start: Int, marker: String, count: Int)?
        var offset = 0
        while offset < source.length {
            let lineRange = source.lineRange(for: NSRange(location: offset, length: 0))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines) as NSString
            if let match = fence.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) {
                let delimiter = line.substring(with: match.range(at: 1))
                let marker = String(delimiter.prefix(1))
                let suffix = line.substring(with: match.range(at: 2))
                if let current = opening {
                    if marker == current.marker, delimiter.count >= current.count,
                       suffix.trimmingCharacters(in: .whitespaces).isEmpty {
                        spans.append(Span(range: NSRange(location: current.start,
                            length: NSMaxRange(lineRange) - current.start), kind: .code))
                        opening = nil
                    }
                } else if marker != "`" || !suffix.contains("`") {
                    opening = (lineRange.location, marker, delimiter.count)
                }
            }
            offset = NSMaxRange(lineRange)
        }
        if let opening {
            spans.append(Span(range: NSRange(location: opening.start, length: source.length - opening.start), kind: .code))
        }
        for (expression, kind) in rules {
            for match in expression.matches(in: text, range: fullRange) {
                guard !spans.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
                spans.append(Span(range: match.range, kind: kind))
            }
        }
        return spans
    }
}

struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let isActive: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = SourceTextView(frame: .zero)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        editor.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        editor.textColor = .textColor
        editor.insertionPointColor = .textColor
        editor.drawsBackground = false
        editor.setAccessibilityLabel(String(localized: "Description"))
        editor.string = text
        editor.delegate = context.coordinator
        scroll.documentView = editor
        context.coordinator.highlight(editor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let editor = scroll.documentView as? SourceTextView else { return }
        if !isActive, scroll.window?.firstResponder === editor {
            scroll.window?.makeFirstResponder(nil)
        }
        editor.isEditable = isActive
        guard !editor.hasMarkedText() else { return }
        if editor.string != text {
            editor.string = text
            coordinator.highlight(editor)
        } else if coordinator.colorScheme != colorScheme {
            coordinator.highlight(editor)
        }
        coordinator.colorScheme = colorScheme
    }

    final class SourceTextView: NSTextView {
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            let inset = NSSize(width: max(24, (newSize.width - 760) / 2), height: 24)
            if textContainerInset != inset { textContainerInset = inset }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceEditor
        var colorScheme: ColorScheme?
        init(_ parent: MarkdownSourceEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
            parent.text = editor.string
            highlight(editor)
        }

        @MainActor
        func highlight(_ editor: NSTextView) {
            guard let manager = editor.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: (editor.string as NSString).length)
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            for span in MarkdownSourceHighlighting.spans(in: editor.string) {
                let color: NSColor = switch span.kind {
                case .marker: .secondaryLabelColor
                case .emphasis: .systemPurple
                case .link: .linkColor
                case .code: .systemTeal
                }
                manager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: span.range)
            }
        }
    }
}
