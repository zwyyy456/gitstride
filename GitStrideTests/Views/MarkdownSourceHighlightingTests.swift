import Foundation
import Testing
@testable import GitStride

@MainActor
struct MarkdownSourceHighlightingTests {
    @Test func codeFencesProtectTheirContentsAndUnclosedFencesReachTheEnd() {
        let text = "😀 Intro\n````markdown\n# not a heading\n```\n**still code**\n`````\n# Heading\n~~~\n[unfinished](url)"
        let source = text as NSString
        let spans = MarkdownSourceHighlighting.spans(in: text)
        let code = spans.filter { $0.kind == .code }.map { source.substring(with: $0.range) }
        #expect(code == ["````markdown\n# not a heading\n```\n**still code**\n`````\n", "~~~\n[unfinished](url)"])
        #expect(spans.filter { $0.kind == .marker }.map { source.substring(with: $0.range) } == ["#"])
        #expect(!spans.contains { $0.kind == .emphasis || $0.kind == .link })
    }

    @Test func unicodeOffsetsAndInlineCodeDoNotCorruptOtherHighlights() {
        let text = "中文 👩🏽‍💻 **强调** `**literal**` [文档](https://example.com)"
        let source = text as NSString
        let spans = MarkdownSourceHighlighting.spans(in: text)
        #expect(spans.filter { $0.kind == .emphasis }.map { source.substring(with: $0.range) } == ["**强调**"])
        #expect(spans.filter { $0.kind == .code }.map { source.substring(with: $0.range) } == ["`**literal**`"])
        #expect(spans.filter { $0.kind == .link }.map { source.substring(with: $0.range) } == ["[文档](https://example.com)"])
    }
}
