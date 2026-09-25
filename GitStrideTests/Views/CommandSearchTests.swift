import Foundation
import Testing

@testable import GitStride

struct CommandSearchTests {
    @Test func commandMatchingRanksTitlesBeforeAliasesAndSupportsLocalizedTerms() {
        #expect(CommandSearch.rank("  REFRESH  ", title: "Refresh") == 0)
        #expect(CommandSearch.rank("refresh", title: "Refresh Project") == 1)
        #expect(CommandSearch.rank("project", title: "Refresh Project") == 2)
        #expect(CommandSearch.rank("刷新", title: "Refresh", keywords: "刷新 reload") == 3)
        #expect(CommandSearch.rank("status move", title: "Change Status", keywords: "move") == 3)
        #expect(CommandSearch.rank("missing", title: "Refresh") == nil)
    }

    @Test func boardNavigationSkipsEmptyColumnsAndClampsRowAndColumnEdges() {
        let columns = [["a", "b", "c"], [], ["d"], ["e", "f"]]
        #expect(ItemKeyboardNavigation.horizontal(from: "c", columns: columns, offset: 1) == "d")
        #expect(ItemKeyboardNavigation.horizontal(from: "f", columns: columns, offset: -1) == "d")
        #expect(ItemKeyboardNavigation.horizontal(from: "a", columns: columns, offset: -1) == "a")
        #expect(ItemKeyboardNavigation.horizontal(from: nil, columns: [[], []], offset: 1) == nil)
    }

    @Test func navigationKeepsIdentityAcrossRefreshAndUsesANeighborAfterRemoval() {
        #expect(ItemKeyboardNavigation.next(from: nil, in: ["a", "b"], offset: -1) == "b")
        #expect(ItemKeyboardNavigation.next(from: "b", in: ["a", "b"], offset: 1) == "b")
        #expect(ItemKeyboardNavigation.reconciled("b", old: ["a", "b", "c"], new: ["c", "b"]) == "b")
        #expect(ItemKeyboardNavigation.reconciled("b", old: ["a", "b", "c"], new: ["a", "c"]) == "c")
        #expect(ItemKeyboardNavigation.reconciled("b", old: ["a", "b"], new: []) == nil)
        #expect(ItemKeyboardNavigation.reconciled(nil, old: ["a"], new: ["b"]) == nil)
    }
}
