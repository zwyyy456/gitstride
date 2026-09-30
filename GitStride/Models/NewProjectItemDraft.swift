import Foundation

struct NewProjectItemDraft {
    enum ItemType: String, CaseIterable, Identifiable {
        case issue = "Issue"
        case draft = "Draft"

        var title: String {
            switch self {
            case .issue: String(localized: "Issue")
            case .draft: String(localized: "Draft")
            }
        }

        var id: Self { self }
    }

    var itemType: ItemType = .issue
    var repository = ""
    var title = ""
    var bodyText = ""
    var quickEntry = ""
    var status = ""
    var priority = ""
    var startDate: Date?
    var targetDate: Date?
    var labels = ""
    var assignees = ""
    var usesQuickEntry = false
    var repositoryValidationMessage: String?

    static func statusOptions(in project: Project?) -> [String] {
        guard let project, project.statusField != nil else { return [] }
        let names = project.statusOptions.map(\.name)
        return names.contains { $0.caseInsensitiveCompare("Backlog") == .orderedSame }
            ? names : names + ["Backlog"]
    }

    static func priorityOptions(in project: Project?) -> [String] {
        project?.fields.first {
            $0.kind == .singleSelect && $0.name.caseInsensitiveCompare("Priority") == .orderedSame
        }?.options.map(\.name) ?? []
    }

    mutating func reconcileStatus(in project: Project?) {
        let options = Self.statusOptions(in: project)
        if !options.contains(status) {
            status = options.first { $0.caseInsensitiveCompare("Todo") == .orderedSame } ?? ""
        }
    }

    func canSubmit(in project: Project?) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if itemType == .draft { return true }
        let statuses = Self.statusOptions(in: project)
        return !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (statuses.isEmpty || statuses.contains(status))
    }

    var labelNames: [String] { Self.commaSeparated(labels) }

    func assigneeLogins(currentUser: String?) -> [String] {
        Self.commaSeparated(assignees).map { Self.normalizeAssignee($0, currentUser: currentUser) }
    }

    func hasCurrentUserAssignee(currentUser: String?) -> Bool {
        let login = Self.normalizeAssignee("@me", currentUser: currentUser)
        return assigneeLogins(currentUser: currentUser).contains { $0.caseInsensitiveCompare(login) == .orderedSame }
    }

    mutating func assignToMe() {
        assignees = (Self.commaSeparated(assignees) + ["@me"]).joined(separator: ", ")
    }

    private static func commaSeparated(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeAssignee(_ value: String, currentUser: String?) -> String {
        let login = value.hasPrefix("@") ? String(value.dropFirst()) : value
        return login.lowercased() == "me" ? (currentUser ?? login) : login
    }

    mutating func reviewQuickEntry(repositories: [String], statuses: [String], priorities: [String]) -> String? {
        let request = QuickCreateParser.parse(quickEntry)
        guard request.title.isEmpty == false else {
            return String(localized: "Quick Entry needs a title.")
        }

        title = request.title
        if let requestedRepository = request.repository {
            repository = Self.resolvedRepository(requestedRepository, suggestions: repositories)
        }
        labels = request.labels.joined(separator: ", ")
        assignees = request.assignees.map { "@\($0)" }.joined(separator: ", ")
        let matchedStatus = Self.matchedOption(request.status, in: statuses)
        let matchedPriority = Self.matchedOption(request.priority, in: priorities)
        if request.status != nil {
            status = matchedStatus ?? ""
        }
        priority = matchedPriority ?? ""

        var unavailableOptions: [String] = []
        if let requestedStatus = request.status, matchedStatus == nil {
            unavailableOptions.append(String(localized: "status \(requestedStatus)"))
        }
        if let requestedPriority = request.priority, matchedPriority == nil {
            unavailableOptions.append(String(localized: "priority \(requestedPriority)"))
        }

        if unavailableOptions.isEmpty {
            usesQuickEntry = false
            return nil
        } else {
            return String(localized: "Unavailable project option: \(unavailableOptions.joined(separator: ", ")).")
        }
    }

    private static func matchedOption(_ requestedValue: String?, in options: [String]) -> String? {
        guard let requestedValue else { return nil }
        return options.first {
            $0.caseInsensitiveCompare(requestedValue) == .orderedSame
        }
    }

    private static func resolvedRepository(_ value: String, suggestions: [String]) -> String {
        guard value.contains("/") == false else { return value }
        let matches = suggestions.filter {
            $0.split(separator: "/").last?.caseInsensitiveCompare(value) == .orderedSame
        }
        return matches.count == 1 ? matches[0] : value
    }
}
