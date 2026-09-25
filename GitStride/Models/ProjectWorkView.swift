import Foundation

struct ProjectPlanningReference: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let repository: String
    let number: Int?

    var displayName: String {
        if let number { return "\(repository) #\(number) · \(title)" }
        return "\(repository) · \(title)"
    }
}

struct ProjectIssueType: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

enum ProjectWorkCompletion: String, Codable, CaseIterable, Identifiable {
    case all = "All"
    case unfinished = "Unfinished"
    case blocked = "Blocked"

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .unfinished: String(localized: "Unfinished")
        case .blocked: String(localized: "Blocked")
        }
    }

    var id: Self { self }
}

struct ProjectWorkFilter: Codable, Equatable {
    var assignedToMe = false
    var statusIDs: Set<String> = []
    var labelID: String?
    var issueTypeID: String?
    var milestoneID: String?
    var parentIssueID: String?
    var completion: ProjectWorkCompletion = .all

    var isActive: Bool { self != Self() }
    var isDelivery: Bool { milestoneID != nil || parentIssueID != nil }

    func deliveryItems(in items: [ProjectItem]) -> [ProjectItem] {
        items.filter { item in
            (milestoneID == nil || item.milestone?.id == milestoneID)
                && (parentIssueID == nil || item.parentIssue?.id == parentIssueID)
        }
    }

    func apply(to items: [ProjectItem], currentUserLogin: String?) -> [ProjectItem] {
        deliveryItems(in: items).filter { item in
            if assignedToMe {
                guard let login = currentUserLogin,
                      item.assignees.contains(where: { $0.login.caseInsensitiveCompare(login) == .orderedSame }) else { return false }
            }
            if !statusIDs.isEmpty && !statusIDs.contains(item.statusOptionId ?? "") { return false }
            if let labelID, !item.labels.contains(where: { $0.id == labelID }) { return false }
            if let issueTypeID, item.issueType?.id != issueTypeID { return false }
            switch completion {
            case .all: return true
            case .unfinished: return !item.isWorkComplete
            case .blocked: return !item.isWorkComplete && item.signals.blockedByCount > 0
            }
        }
    }
}

enum ProjectLayout: String, Codable, CaseIterable {
    case board, table, roadmap

    var title: String {
        switch self {
        case .board: String(localized: "Board")
        case .table: String(localized: "Table")
        case .roadmap: String(localized: "Roadmap")
        }
    }
}

struct SavedProjectWorkView: Codable, Identifiable {
    var id = UUID().uuidString
    let projectID: String
    var name: String
    var filter: ProjectWorkFilter
    var layout: ProjectLayout
    var hiddenStatusIDs: Set<String> = []

    init(projectID: String, name: String, filter: ProjectWorkFilter,
         layout: ProjectLayout, hiddenStatusIDs: Set<String> = []) {
        self.projectID = projectID
        self.name = name
        self.filter = filter
        self.layout = layout
        self.hiddenStatusIDs = hiddenStatusIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, name, filter, layout, hiddenStatusIDs
    }
    private enum LegacyKeys: String, CodingKey { case usesTable }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        projectID = try values.decode(String.self, forKey: .projectID)
        name = try values.decode(String.self, forKey: .name)
        filter = try values.decode(ProjectWorkFilter.self, forKey: .filter)
        hiddenStatusIDs = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenStatusIDs) ?? []
        if let stored = try values.decodeIfPresent(ProjectLayout.self, forKey: .layout) {
            layout = stored
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            layout = try legacy.decode(Bool.self, forKey: .usesTable) ? .table : .board
        }
    }
}

extension ProjectItem {
    /// Completion uses the content's GitHub state, never a guessed Project status name.
    var isWorkComplete: Bool {
        issueState == .closed || prState == .merged || prState == .closed
    }
}
