import Foundation

/// GitHub date fields are calendar days, not instants in the viewer's time zone.
enum RoadmapCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func date(_ value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        guard result.year == year, result.month == month, result.day == day else { return nil }
        return date
    }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    static func days(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day!
    }

    static var today: Date {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return calendar.date(from: components)!
    }

    static func label(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted,
                                        calendar: calendar, timeZone: calendar.timeZone))
    }
}

struct RoadmapSchedule: Equatable {
    let start: Date?
    let end: Date?
    let isInvalid: Bool

    var dates: [Date] { isInvalid ? [] : [start, end].compactMap { $0 } }

    var summary: String {
        if isInvalid { return String(localized: "Check schedule dates") }
        switch (start, end) {
        case (.some(let start), .some(let end)):
            return "\(RoadmapCalendar.label(start)) – \(RoadmapCalendar.label(end))"
        case (.some(let start), nil):
            return String(localized: "Starts \(RoadmapCalendar.label(start))")
        case (nil, .some(let end)):
            return String(localized: "Target \(RoadmapCalendar.label(end))")
        case (nil, nil): return String(localized: "Unscheduled")
        }
    }

    static func make(values: [String: ProjectFieldValue], fields: [ProjectField],
                     startFieldID: String, endFieldID: String) -> Self {
        func endpoint(_ id: String, isEnd: Bool) -> (Date?, Bool) {
            guard !id.isEmpty, let field = fields.first(where: { $0.id == id }),
                  let value = values[id] else { return (nil, false) }
            switch (field.kind, value) {
            case (.date, .date(let raw)):
                let date = RoadmapCalendar.date(raw)
                return (date, date == nil)
            case (.iteration, .iteration(let iterationID, _)):
                guard let iteration = field.iterations.first(where: { $0.id == iterationID }),
                      let start = RoadmapCalendar.date(iteration.startDate), iteration.duration > 0 else {
                    return (nil, true)
                }
                // Duration counts the start day; a one-day iteration ends that same day.
                return (isEnd ? RoadmapCalendar.adding(days: iteration.duration - 1, to: start) : start, false)
            default: return (nil, true)
            }
        }
        let (start, invalidStart) = endpoint(startFieldID, isEnd: false)
        let (end, invalidEnd) = endpoint(endFieldID, isEnd: true)
        let reversed = start.map { start in end.map { $0 < start } ?? false } ?? false
        return Self(start: start, end: end, isInvalid: invalidStart || invalidEnd || reversed)
    }
}

enum RoadmapZoom: String, CaseIterable {
    case month, quarter, year

    var title: String {
        switch self {
        case .month: String(localized: "Month")
        case .quarter: String(localized: "Quarter")
        case .year: String(localized: "Year")
        }
    }

    var visibleDays: Double {
        switch self {
        case .month: 31
        case .quarter: 92
        case .year: 366
        }
    }
}

enum RoadmapEditKind { case move, start, end }

enum RoadmapEditError: LocalizedError {
    case invalidRange
    case changedSchedule
    case unavailableIteration
    case incompleteWrite(String)

    var errorDescription: String? {
        switch self {
        case .invalidRange: String(localized: "The target date must not be earlier than the start date.")
        case .changedSchedule: String(localized: "The schedule changed while you were editing. Review the dates and try again.")
        case .unavailableIteration: String(localized: "No iteration is available for this schedule.")
        case .incompleteWrite(let reason):
            String(localized: "The schedule update did not finish. Confirmed changes were kept; refresh to check the current dates. \(reason)")
        }
    }
}

struct RoadmapEdit {
    struct Change: Equatable {
        let fieldID: String
        let value: ProjectFieldValue
    }
    let changes: [Change]
    let schedule: RoadmapSchedule

    static func make(values: [String: ProjectFieldValue], fields: [ProjectField],
                     startFieldID: String, endFieldID: String,
                     kind: RoadmapEditKind, days: Int) throws -> Self {
        let original = RoadmapSchedule.make(values: values, fields: fields,
                                            startFieldID: startFieldID, endFieldID: endFieldID)
        guard !original.isInvalid, !original.dates.isEmpty else { throw RoadmapEditError.invalidRange }
        if days == 0 { return Self(changes: [], schedule: original) }
        var changes: [Change] = []
        var updated = values
        var ids: [(String, Date, Bool)] = []
        if kind != .end, let start = original.start { ids.append((startFieldID, start, false)) }
        if kind != .start, let end = original.end,
           !ids.contains(where: { $0.0 == endFieldID }) { ids.append((endFieldID, end, true)) }
        for (id, date, isEnd) in ids {
            guard let field = fields.first(where: { $0.id == id }) else { throw RoadmapEditError.changedSchedule }
            let target = RoadmapCalendar.adding(days: days, to: date)
            let value: ProjectFieldValue
            switch field.kind {
            case .date:
                let parts = RoadmapCalendar.calendar.dateComponents([.year, .month, .day], from: target)
                guard let year = parts.year, (1...9999).contains(year) else { throw RoadmapEditError.invalidRange }
                value = .date(String(format: "%04d-%02d-%02d", year, parts.month!, parts.day!))
            case .iteration:
                let candidates = field.iterations.compactMap { iteration -> (ProjectIteration, Date)? in
                    guard let start = RoadmapCalendar.date(iteration.startDate), iteration.duration > 0 else { return nil }
                    return (iteration, isEnd ? RoadmapCalendar.adding(days: iteration.duration - 1, to: start) : start)
                }
                guard let closest = candidates.min(by: { lhs, rhs in
                    let left = abs(RoadmapCalendar.days(from: lhs.1, to: target))
                    let right = abs(RoadmapCalendar.days(from: rhs.1, to: target))
                    if left == right { return days > 0 ? lhs.1 > rhs.1 : lhs.1 < rhs.1 }
                    return left < right
                }) else { throw RoadmapEditError.unavailableIteration }
                value = .iteration(id: closest.0.id, title: closest.0.title)
            default: throw RoadmapEditError.changedSchedule
            }
            if value != values[id] {
                changes.append(Change(fieldID: id, value: value))
                updated[id] = value
            }
        }
        let result = RoadmapSchedule.make(values: updated, fields: fields,
                                          startFieldID: startFieldID, endFieldID: endFieldID)
        guard !result.isInvalid else { throw RoadmapEditError.invalidRange }
        // Extend the end first when moving forward, so intermediate writes remain valid.
        if kind == .move, days > 0 { changes.reverse() }
        return Self(changes: changes, schedule: result)
    }
}
