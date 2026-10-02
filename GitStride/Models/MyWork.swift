import Foundation

struct FollowedProject: Identifiable, Codable, Hashable {
    let id: String
    let owner: ProjectOwner
    let displayTitle: String?

    init(project: Project) {
        id = project.id
        owner = project.owner
        displayTitle = project.title
    }

    private enum CodingKeys: String, CodingKey {
        case id, ownerId, ownerLogin, ownerKind
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        owner = ProjectOwner(
            id: try values.decode(String.self, forKey: .ownerId),
            login: try values.decode(String.self, forKey: .ownerLogin),
            name: nil,
            kind: try values.decode(ProjectOwnerKind.self, forKey: .ownerKind)
        )
        displayTitle = nil
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(owner.id, forKey: .ownerId)
        try values.encode(owner.login, forKey: .ownerLogin)
        try values.encode(owner.kind, forKey: .ownerKind)
    }
}

enum MyWorkFilter: String, CaseIterable, Codable, Identifiable {
    case assigned = "Assigned to Me"
    case authored = "My Pull Requests"
    case reviewRequested = "Review Requested"
    case allOpen = "Open Items"
    case readyToMerge = "Ready to Merge"
    case ciFailed = "CI Failed"
    case due = "Due Soon"
    case blocked = "Blocked"
    case recent = "Recently Updated"
    case stale = "Stale"

    var title: String {
        switch self {
        case .assigned: String(localized: "Assigned to Me")
        case .authored: String(localized: "My Pull Requests")
        case .reviewRequested: String(localized: "Review Requested")
        case .allOpen: String(localized: "Open Items")
        case .readyToMerge: String(localized: "Ready to Merge")
        case .ciFailed: String(localized: "CI Failed")
        case .due: String(localized: "Due Soon")
        case .blocked: String(localized: "Blocked")
        case .recent: String(localized: "Recently Updated")
        case .stale: String(localized: "Stale")
        }
    }

    var id: Self { self }

    var icon: String {
        switch self {
        case .assigned: "person.crop.circle"
        case .authored: "arrow.triangle.pull"
        case .reviewRequested: "text.bubble"
        case .allOpen: "tray"
        case .readyToMerge: "arrow.triangle.merge"
        case .ciFailed: "xmark.octagon"
        case .due: "calendar.badge.clock"
        case .blocked: "exclamationmark.octagon"
        case .recent: "clock.arrow.circlepath"
        case .stale: "zzz"
        }
    }

    static let personalCases: [Self] = [.assigned, .authored, .reviewRequested]
    static let followedCases: [Self] = [.allOpen, .readyToMerge, .ciFailed, .due, .blocked, .recent, .stale]
    var isPersonal: Bool { Self.personalCases.contains(self) }

    func searchQuery(login: String) -> String? {
        switch self {
        case .assigned: "is:open is:issue assignee:\(login) sort:updated-desc"
        case .authored: "is:open is:pr author:\(login) sort:updated-desc"
        case .reviewRequested: "is:open is:pr review-requested:\(login) -author:\(login) sort:updated-desc"
        default: nil
        }
    }

    func includes(
        _ workItem: MyWorkItem,
        currentUserLogin: String?,
        now: Date = Date()
    ) -> Bool {
        let item = workItem.item
        switch self {
        case .assigned:
            guard let currentUserLogin else { return false }
            return item.assignees.contains {
                $0.login.caseInsensitiveCompare(currentUserLogin) == .orderedSame
            } && workItem.isOpen
        case .authored:
            return false // Authored PRs come from the account query, not Project membership.
        case .reviewRequested:
            guard let currentUserLogin else { return false }
            return workItem.isOpen && item.signals.reviewRequested(for: currentUserLogin)
        case .allOpen:
            return workItem.isOpen
        case .readyToMerge:
            return workItem.isOpen && item.signals.isReadyToMerge
        case .ciFailed:
            return workItem.isOpen && item.signals.hasFailedChecks
        case .due:
            guard let dueDate = workItem.dueDate else { return false }
            return workItem.isOpen && dueDate <= now.addingTimeInterval(7 * 24 * 60 * 60)
        case .blocked:
            let hasBlockedLabel = item.labels.contains {
                $0.name.caseInsensitiveCompare("blocked") == .orderedSame
            }
            let hasBlockedField = item.fieldValues.values.contains { value in
                if case .singleSelect(_, let name) = value {
                    return name.caseInsensitiveCompare("blocked") == .orderedSame
                }
                return false
            }
            return workItem.isOpen && (hasBlockedLabel || hasBlockedField)
        case .recent:
            return workItem.updatedDate >= now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .stale:
            return workItem.isOpen
                && workItem.updatedDate < now.addingTimeInterval(-30 * 24 * 60 * 60)
        }
    }
}

struct MyWorkItem: Identifiable, Hashable {
    let project: Project
    let item: ProjectItem

    var id: String { "\(project.id):\(item.id)" }

    var isOpen: Bool {
        switch item.contentType {
        case .issue: item.issueState != .closed
        case .pullRequest: item.prState == .open
        case .draftIssue: true
        case .redacted: false
        }
    }

    var updatedDate: Date {
        guard let updatedAt = item.updatedAt else { return .distantPast }
        return (try? Date(updatedAt, strategy: .iso8601)) ?? .distantPast
    }

    var dueDate: Date? {
        let field = project.fields.first {
            guard $0.kind == .date else { return false }
            let name = $0.name.lowercased()
            return name == "due" || name.contains("due date") || name.contains("target date")
        }
        guard let field,
              case .date(let value) = item.fieldValues[field.id] else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }
}

/// Account search results use Issue/PR identity and have no Project membership.
struct PersonalWorkItem: Identifiable, Hashable {
    let id: String
    var title: String
    let number: Int
    let url: URL
    let repository: String
    let isPullRequest: Bool
    var updatedAt: String
    var signals: EngineeringSignals
}

struct PersonalWorkResult {
    var items: [PersonalWorkItem]
    let totalCount: Int
    var isTruncated: Bool { totalCount > items.count }
}

enum PullRequestWorkStatus: String, CaseIterable, Identifiable {
    case all, ready, failed, draft, review
    var id: Self { self }
    var title: String {
        switch self {
        case .all: String(localized: "All Pull Requests")
        case .ready: String(localized: "Ready to Merge")
        case .failed: String(localized: "CI Failed")
        case .draft: String(localized: "Draft")
        case .review: String(localized: "Awaiting Review")
        }
    }
    func includes(_ signals: EngineeringSignals) -> Bool {
        switch self {
        case .all: true
        case .ready: signals.isReadyToMerge
        case .failed: signals.hasFailedChecks
        case .draft: signals.isDraft
        case .review: signals.reviewDecision == .reviewRequired
        }
    }
}
