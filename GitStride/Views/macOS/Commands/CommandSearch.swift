import Foundation

/// Pure ordering rules shared by the palette and keyboard navigation.
enum CommandSearch {
    static func rank(_ query: String, title: String, keywords: String = "") -> Int? {
        let query = normalized(query)
        let title = normalized(title)
        guard !query.isEmpty else { return 0 }
        if title == query { return 0 }
        if query.count == 1 && normalized(keywords).split(whereSeparator: \.isWhitespace).contains(Substring(query)) { return 0 }
        if title.hasPrefix(query) { return 1 }
        if title.contains(query) { return 2 }
        let terms = query.split(whereSeparator: \.isWhitespace)
        let text = title + " " + normalized(keywords)
        return terms.allSatisfy { text.contains($0) } ? 3 : nil
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ItemKeyboardNavigation {
    static func next<ID: Equatable>(from current: ID?, in items: [ID], offset: Int) -> ID? {
        guard !items.isEmpty else { return nil }
        guard let current, let index = items.firstIndex(of: current) else {
            return offset < 0 ? items.last : items.first
        }
        return items[min(max(index + offset, 0), items.count - 1)]
    }

    static func horizontal(from current: String?, columns: [[String]], offset: Int) -> String? {
        let columns = columns.filter { !$0.isEmpty }
        guard let current, let column = columns.firstIndex(where: { $0.contains(current) }),
            let row = columns[column].firstIndex(of: current)
        else { return columns.first?.first }
        let destination = min(max(column + offset, 0), columns.count - 1)
        return columns[destination][min(row, columns[destination].count - 1)]
    }

    static func reconciled<ID: Equatable>(_ current: ID?, old: [ID], new: [ID]) -> ID? {
        guard let current else { return nil }
        if new.contains(current) { return current }
        guard !new.isEmpty else { return nil }
        return new[min(old.firstIndex(of: current) ?? 0, new.count - 1)]
    }
}

/// Keeps the original range anchor while Shift navigation grows or shrinks a selection.
struct ItemRangeSelection {
    private var anchor: String?
    private var base: Set<String> = []
    private var lastDestination: String?

    mutating func reset() { anchor = nil; base = []; lastDestination = nil }

    mutating func extend(from current: String?, to destination: String, in ids: [String],
                         selected: Set<String>) -> Set<String> {
        if anchor == nil || current != lastDestination || !ids.contains(anchor!) {
            anchor = current.flatMap { ids.contains($0) ? $0 : nil } ?? destination
            base = selected.subtracting(current.map { [$0] } ?? [])
        }
        lastDestination = destination
        guard let start = ids.firstIndex(of: anchor!), let end = ids.firstIndex(of: destination) else { return selected }
        return base.intersection(ids).union(ids[min(start, end)...max(start, end)])
    }
}
