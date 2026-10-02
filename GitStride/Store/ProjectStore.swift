import Foundation
import SwiftUI

enum ProjectContentPhase: Equatable {
    case summary
    case cached
    case loading
    case loaded
    case refreshing
    case failed(String)
}

enum SelectedProjectContentState: Equatable {
    case none
    case loading(Project)
    case content(Project, isRefreshing: Bool, isCached: Bool)
    case empty(Project, isRefreshing: Bool, isCached: Bool)
    case failed(Project, String)
}

enum ProjectStoreError: LocalizedError {
    case repositoryOwnerMismatch
    case noProjectSelected
    case readOnlyProject
    case itemUnavailable
    case operationInProgress
    case emptyItemTitle
    case itemDetailsFailed(String)
    case missingFieldOption(field: String, option: String)

    var errorDescription: String? {
        switch self {
        case .repositoryOwnerMismatch:
            String(localized: "Choose a repository owned by the same account as the project.")
        case .noProjectSelected:
            String(localized: "No project is selected.")
        case .readOnlyProject:
            String(localized: "This project is read-only.")
        case .operationInProgress:
            String(localized: "Another change to this item is still in progress.")
        case .emptyItemTitle:
            String(localized: "Enter a title.")
        case .itemDetailsFailed(let message):
            message
        case .itemUnavailable:
            String(localized: "This item is no longer available.")
        case .missingFieldOption(let field, let option):
            String(localized: "\(field) has no option named \(option).")
        }
    }
}

@MainActor
@Observable
final class IssueCreation {
    enum Phase: Equatable {
        case ready
        case addingToProject(issueURL: String)
        case applyingFields(issueURL: String, itemID: String)
        case completed(issueURL: String)
        case unconfirmed
    }

    fileprivate let sessionID: UUID
    let projectID: String
    var displayTitle: String { title }
    let repository: String
    fileprivate let title: String
    fileprivate let body: String
    fileprivate let labels: [String]
    fileprivate let assignees: [String]
    fileprivate let selectedStatusName: String?
    fileprivate var backlogFieldToPrepare: ProjectField?
    fileprivate var dateFieldsToPrepare: [(String, ProjectFieldValue)]
    fileprivate var remainingFields: [(ProjectField, ProjectFieldValue)]
    fileprivate var createdIssue: CreatedIssue?
    fileprivate var createdItem: ProjectItem?
    fileprivate(set) var phase: Phase = .ready
    fileprivate(set) var isRunning = false
    fileprivate(set) var errorMessage: String?

    var canResume: Bool {
        guard !isRunning else { return false }
        switch phase {
        case .unconfirmed, .completed: return false
        default: return true
        }
    }

    fileprivate init(sessionID: UUID, projectID: String, repository: String, title: String, body: String,
                     labels: [String], assignees: [String], selectedStatusName: String?,
                     backlogFieldToPrepare: ProjectField?, fields: [(ProjectField, ProjectFieldValue)],
                     dateFieldsToPrepare: [(String, ProjectFieldValue)] = []) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.repository = repository
        self.title = title
        self.body = body
        self.labels = labels
        self.assignees = assignees
        self.selectedStatusName = selectedStatusName
        self.backlogFieldToPrepare = backlogFieldToPrepare
        self.dateFieldsToPrepare = dateFieldsToPrepare
        remainingFields = fields
    }
}

enum PendingSyncState {
    case syncing
    case failed(String)
    case unconfirmed(String)
}

struct PendingItemCreation: Identifiable {
    enum Kind {
        case issue(IssueCreation)
        case draft(title: String, body: String)
    }

    let id: UUID
    let projectID: String
    let title: String
    let kind: Kind
    var state: PendingSyncState = .syncing
}

enum ContentEditTarget {
    case project(ItemInspectorReference)
    case personal(PersonalWorkItem)
}

struct PendingContentEdit: Identifiable {
    let id: String
    let target: ContentEditTarget
    var reference: ItemInspectorReference? {
        if case .project(let reference) = target { return reference }
        return nil
    }
    let title: String
    let body: String
    let author: ItemAuthor?
    var state: PendingSyncState = .syncing
}

private struct ItemDetailEntry {
    let sourceUpdatedAt: String?
    let state: ItemDetailState
}

private struct ItemMutationKey: Hashable {
    let projectID: String
    let itemID: String
}

private struct PendingStatusMove {
    let operationID: UUID
    let fieldID: String
    let status: StatusOption
}

private struct ConfirmedContentVersion {
    let title: String
    let updatedAt: String
}

private struct ProjectState {
    enum Source { case catalog, cache, remote }
    enum Load { case idle, loading, failed(String) }

    let owner: ProjectOwner
    var snapshot: Project?
    var source: Source = .catalog
    var load: Load = .idle
    var latestReadID: UUID?
    var mutationRevision: UInt64 = 0
    var mutations: Set<UUID> = []
    var needsRefresh = false
    var createdItemFieldsAwaitingObservation: [String: [String: ProjectFieldValue]] = [:]
    var confirmedContentAwaitingObservation: [String: ConfirmedContentVersion] = [:]

    var phase: ProjectContentPhase {
        switch load {
        case .loading: return source == .catalog ? .loading : .refreshing
        case .failed(let message):
            if source == .catalog { return .failed(message) }
        case .idle: break
        }
        switch source {
        case .catalog: return .summary
        case .cache: return .cached
        case .remote: return .loaded
        }
    }
}

private struct ProjectReadTicket {
    let projectID: String
    let requestID: UUID
    let mutationRevision: UInt64
    let contentRevision: UInt64
    let followedGeneration: Int?
}

@MainActor
@Observable
final class ProjectStore {
    var sessionState: GitHubSessionState = .checking
    var owners: [ProjectOwner] = []
    private(set) var personalWork: [MyWorkFilter: PersonalWorkResult] = [:]
    private(set) var personalWorkErrors: [MyWorkFilter: String] = [:]
    private(set) var loadingPersonalWork: Set<MyWorkFilter> = []
    private var personalWorkTasks: [MyWorkFilter: Task<Void, Never>] = [:]
    private var personalWorkReadIDs: [MyWorkFilter: UUID] = [:]
    private var personalWorkNeedsRefresh: Set<MyWorkFilter> = []

    func refreshPersonalWork(_ filter: MyWorkFilter) async {
        await startPersonalWorkRefresh(filter)?.value
    }

    @discardableResult
    private func startPersonalWorkRefresh(_ filter: MyWorkFilter) -> Task<Void, Never>? {
        guard isActive, filter.isPersonal, let account = currentAccount else { return nil }
        guard pendingContentMutations.isEmpty else {
            personalWorkNeedsRefresh.insert(filter)
            return nil
        }
        if let task = personalWorkTasks[filter] { return task }
        let readID = UUID()
        personalWorkReadIDs[filter] = readID
        loadingPersonalWork.insert(filter)
        personalWorkErrors[filter] = nil
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.personalWorkReadIDs[filter] == readID {
                    self.loadingPersonalWork.remove(filter)
                    self.personalWorkTasks[filter] = nil
                }
            }
            do {
                let result = try await self.gitHubService.fetchPersonalWork(filter: filter, login: account.login)
                try Task.checkCancellation()
                guard self.isActive, self.currentAccount == account,
                      self.personalWorkReadIDs[filter] == readID else { return }
                self.personalWork[filter] = result
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.isActive, self.personalWorkReadIDs[filter] == readID else { return }
                self.personalWorkErrors[filter] = error.localizedDescription
            }
        }
        personalWorkTasks[filter] = task
        return task
    }

    private(set) var isLoadingFollowedProjects = false
    private(set) var followedProjectsErrorMessage: String?
    var selectedOwnerId: String? {
        didSet {
            defaults.set(selectedOwnerId, forKey: "selectedOwnerId")
        }
    }
    var selectedProjectId: String? {
        didSet {
            defaults.set(selectedProjectId, forKey: "selectedProjectId")
        }
    }

    // nil means "All", otherwise filter by status name
    var selectedStatusFilter: String? {
        didSet {
            defaults.set(selectedStatusFilter, forKey: "selectedStatusFilter")
        }
    }

    private var repositoryLists: [String: RepositoryListState] = [:]
    private var repositoryReadIDs: [String: UUID] = [:]
    private(set) var linkingRepositoryProjectIDs: Set<String> = []
    private(set) var deletingProjectIDs: Set<String> = []
    private var deletedProjectIDs: Set<String> = []
    private(set) var isCreatingProject = false
    var isLoading = false
    var error: Error?
    private(set) var operationErrorMessage: String?
    var lastUpdated: Date?
    private(set) var currentAccount: GitHubAccount?
    var currentUserLogin: String? { currentAccount?.login }
    private var isActive = true
    private let sessionID = UUID()

    private var catalogGeneration = 0
    private var projectGeneration = 0
    private var followedProjectsGeneration = 0
    private var projectStates: [String: ProjectState] = [:]
    private var contentRevision: UInt64 = 0
    private var reconciliationTasks: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var catalogProjectIDs: [String] = []
    private var followedProjectIDs: Set<String> = []
    private var didRestoreCache = false
    private var cachedAccountLogin: String?
    private var projectLoadTask: Task<Project?, Error>?
    private var itemDetailEntries: [String: ItemDetailEntry] = [:]
    private var itemDetailTasks: [String: Task<ProjectItemDetail, Error>] = [:]
    private var itemDetailGenerations: [String: Int] = [:]
    private(set) var refreshingItemReferences: Set<ItemInspectorReference> = []
    private var repositoryMilestones: [String: RepositoryMilestonesState] = [:]
    private var pendingItemMutations: [ItemMutationKey: UUID] = [:]
    private var pendingRoadmapEdits: [ItemMutationKey: RoadmapEdit] = [:]
    private var pendingStatusMoves: [ItemMutationKey: PendingStatusMove] = [:]
    private var pendingContentMutations: [String: UUID] = [:]
    private(set) var pendingCreations: [UUID: PendingItemCreation] = [:]
    private(set) var pendingContentEdits: [String: PendingContentEdit] = [:]
    private var pendingCreationTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingEditTasks: [String: Task<Void, Never>] = [:]

    private let gitHubService: GitHubService
    private let projectCache: ProjectCache
    private let defaults: UserDefaults

    var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return project(id: id)
    }

    var projects: [Project] {
        catalogProjectIDs.compactMap { project(id: $0) }
    }

    var selectedOwner: ProjectOwner? {
        guard let id = selectedOwnerId else { return nil }
        return owners.first { $0.id == id }
    }

    var selectedProjectContentState: SelectedProjectContentState {
        guard let id = selectedProjectId else { return .none }
        return projectContentState(id: id)
    }

    func projectContentState(id: String) -> SelectedProjectContentState {
        guard let project = project(id: id) else { return .none }
        switch projectStates[project.id]?.phase ?? .summary {
        case .summary, .loading:
            return .loading(project)
        case .cached:
            return project.items.isEmpty
                ? .empty(project, isRefreshing: false, isCached: true)
                : .content(project, isRefreshing: false, isCached: true)
        case .loaded:
            return project.items.isEmpty
                ? .empty(project, isRefreshing: false, isCached: false)
                : .content(project, isRefreshing: false, isCached: false)
        case .refreshing:
            let isCached = projectStates[project.id]?.source == .cache
            return project.items.isEmpty
                ? .empty(project, isRefreshing: true, isCached: isCached)
                : .content(project, isRefreshing: true, isCached: isCached)
        case .failed(let message):
            return .failed(project, message)
        }
    }

    var isShowingCachedData: Bool {
        selectedProjectId.flatMap { projectStates[$0]?.source } == .cache
    }

    var canEditSelectedProject: Bool {
        selectedProjectId.map(canEditProject) ?? false
    }

    func project(id: String) -> Project? {
        guard var project = projectStates[id]?.snapshot else { return nil }
        project.items += pendingCreations.values
            .filter { $0.projectID == id }
            .map(makePendingProjectItem)
        for edit in pendingContentEdits.values {
            for index in project.items.indices where project.items[index].contentId == edit.id {
                project.items[index].title = edit.title
            }
        }
        for (key, move) in pendingStatusMoves where key.projectID == id {
            guard let index = project.items.firstIndex(where: { $0.id == key.itemID }) else { continue }
            project.items[index].status = move.status.name
            project.items[index].statusOptionId = move.status.id
            project.items[index].fieldValues[move.fieldID] = .singleSelect(
                optionId: move.status.id, name: move.status.name
            )
        }
        for (key, edit) in pendingRoadmapEdits where key.projectID == id {
            guard let index = project.items.firstIndex(where: { $0.id == key.itemID }) else { continue }
            for change in edit.changes { project.items[index].fieldValues[change.fieldID] = change.value }
        }
        return project
    }

    func isUpdatingRoadmap(itemID: String, projectID: String) -> Bool {
        pendingRoadmapEdits[ItemMutationKey(projectID: projectID, itemID: itemID)] != nil
    }

    func canEditRoadmap(itemID: String, projectID: String) -> Bool {
        canEditProject(id: projectID) && pendingCreationState(for: itemID) == nil
            && pendingItemMutations[ItemMutationKey(projectID: projectID, itemID: itemID)] == nil
    }

    func pendingCreationState(for itemID: String) -> PendingSyncState? {
        guard itemID.hasPrefix("pending:"),
              let id = UUID(uuidString: String(itemID.dropFirst("pending:".count))) else { return nil }
        return pendingCreations[id]?.state
    }

    func pendingSyncState(for item: ProjectItem) -> PendingSyncState? {
        if let state = pendingCreationState(for: item.id) { return state }
        return item.contentId.flatMap { pendingContentEdits[$0]?.state }
    }

    private func makePendingProjectItem(_ operation: PendingItemCreation) -> ProjectItem {
        let contentType: ItemContentType
        let status: String?
        let statusOptionID: String?
        switch operation.kind {
        case .issue(let creation):
            contentType = .issue
            let selectedStatus = creation.remainingFields.first {
                $0.0.name.caseInsensitiveCompare("Status") == .orderedSame
            }?.1
            if case .singleSelect(let id, let name) = selectedStatus {
                status = creation.createdItem?.status ?? name
                statusOptionID = creation.createdItem?.statusOptionId ?? id
            } else {
                status = creation.createdItem?.status ?? creation.selectedStatusName
                statusOptionID = creation.createdItem?.statusOptionId
            }
        case .draft:
            contentType = .draftIssue
            status = nil
            statusOptionID = nil
        }
        return ProjectItem(
            id: "pending:\(operation.id.uuidString)", contentId: nil,
            contentType: contentType, title: operation.title, number: nil, url: nil,
            issueState: contentType == .issue ? .open : nil, prState: nil,
            status: status, statusOptionId: statusOptionID, assignees: []
        )
    }

    var allProjects: [Project] {
        projectStates.keys.compactMap { project(id: $0) }
    }

    func isProjectCached(_ id: String) -> Bool { projectStates[id]?.source == .cache }

    func statusChangeUnavailableReason(_ reference: ItemInspectorReference) -> String? {
        guard isActive, let project = project(id: reference.projectID), item(for: reference) != nil else {
            return String(localized: "This item is no longer available.")
        }
        guard canEditProject(id: reference.projectID) else { return String(localized: "This project is read-only.") }
        guard project.statusField != nil else { return String(localized: "This project has no status field.") }
        if pendingCreationState(for: reference.itemID) != nil ||
            pendingItemMutations[ItemMutationKey(projectID: reference.projectID, itemID: reference.itemID)] != nil {
            return String(localized: "Another change to this item is still in progress.")
        }
        return nil
    }

    func followedProject(id: String) -> Project? {
        followedProjectIDs.contains(id) ? project(id: id) : nil
    }

    func item(for reference: ItemInspectorReference) -> ProjectItem? {
        project(id: reference.projectID)?.items.first { $0.id == reference.itemID }
    }

    func canManageProject(id: String) -> Bool {
        guard let state = projectStates[id], state.source != .cache else { return false }
        return state.snapshot?.viewerCanUpdate == true
    }

    func canEditProject(id: String) -> Bool {
        guard !deletingProjectIDs.contains(id), let project = project(id: id), project.viewerCanUpdate else { return false }
        return projectStates[id]?.source == .remote
    }

    func itemDetailState(for item: ProjectItem) -> ItemDetailState {
        guard let contentID = item.contentId else {
            return .failed(String(localized: "Details are unavailable for this item."))
        }
        guard let entry = itemDetailEntries[contentID],
              entry.sourceUpdatedAt == item.updatedAt else { return .idle }
        return entry.state
    }

    func isRefreshingItem(_ reference: ItemInspectorReference) -> Bool {
        refreshingItemReferences.contains(reference)
    }

    func canEditItemContent(_ reference: ItemInspectorReference) -> Bool {
        guard isActive, let item = item(for: reference), item.contentId != nil,
              case .loaded(let detail) = itemDetailState(for: item) else { return false }
        switch item.contentType {
        case .issue, .pullRequest: return detail.viewerCanUpdate
        case .draftIssue: return canEditProject(id: reference.projectID)
        case .redacted: return false
        }
    }

    func updateItemContent(_ reference: ItemInspectorReference, contentID: String, title: String, body: String) async throws {
        guard isActive else { throw CancellationError() }
        guard let item = item(for: reference), item.contentId == contentID else {
            throw ProjectStoreError.itemUnavailable
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ProjectStoreError.emptyItemTitle }
        guard pendingContentMutations[contentID] == nil else { throw ProjectStoreError.operationInProgress }

        // A failed or concurrent content mutation may have invalidated the permission snapshot.
        await loadItemDetail(for: item)
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
        guard self.item(for: reference)?.contentId == contentID else { throw ProjectStoreError.itemUnavailable }
        switch itemDetailState(for: item) {
        case .loaded: break
        case .failed(let message): throw ProjectStoreError.itemDetailsFailed(message)
        case .idle, .loading: throw ProjectStoreError.operationInProgress
        }
        guard canEditItemContent(reference) else { throw GitHubError.insufficientPermissions }

        try await performContentMutation([contentID], operation: {
            try await self.gitHubService.updateItemContent(
                contentID: contentID, contentType: item.contentType, title: title, body: body
            )
        }) { updated in
            self.updateContent(contentID: contentID) { item in
                item.title = updated.title
                item.updatedAt = updated.updatedAt
            }
            self.updatePersonalSummary(contentID: contentID, updated: updated)
            self.updateDetail(contentID: contentID, sourceUpdatedAt: updated.updatedAt) { detail in
                detail.title = updated.title
                detail.body = updated.body
                detail.updatedAt = updated.updatedAt
            }
        }
    }

    var pendingEditList: [PendingContentEdit] {
        pendingContentEdits.values.sorted { $0.title < $1.title }
    }

    func beginContentEdit(_ reference: ItemInspectorReference, contentID: String,
                          title: String, body: String) throws {
        guard isActive, let item = item(for: reference), item.contentId == contentID else {
            throw ProjectStoreError.itemUnavailable
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ProjectStoreError.emptyItemTitle }
        guard pendingContentEdits[contentID] == nil,
              pendingContentMutations[contentID] == nil else { throw ProjectStoreError.operationInProgress }
        guard canEditItemContent(reference) else { throw GitHubError.insufficientPermissions }
        guard case .loaded(let detail) = itemDetailState(for: item) else {
            throw ProjectStoreError.operationInProgress
        }
        pendingContentEdits[contentID] = PendingContentEdit(
            id: contentID, target: .project(reference), title: title, body: body, author: detail.author
        )
        startPendingEdit(contentID)
    }

    func retryPendingEdit(_ contentID: String) {
        guard var edit = pendingContentEdits[contentID], pendingEditTasks[contentID] == nil else { return }
        edit.state = .syncing
        pendingContentEdits[contentID] = edit
        startPendingEdit(contentID)
    }

    func dismissPendingEdit(_ contentID: String) {
        guard pendingEditTasks[contentID] == nil else { return }
        guard let edit = pendingContentEdits.removeValue(forKey: contentID) else { return }
        Task {
            switch edit.target {
            case .project(let reference):
                if let item = self.item(for: reference) { await self.loadItemDetail(for: item, forceRefresh: true) }
            case .personal(let item):
                await self.loadPersonalItemDetail(item, forceRefresh: true)
            }
        }
    }

    private func startPendingEdit(_ contentID: String) {
        pendingEditTasks[contentID] = Task { [weak self] in
            await self?.runPendingEdit(contentID)
        }
    }

    private func runPendingEdit(_ contentID: String) async {
        defer { pendingEditTasks[contentID] = nil }
        var retryCount = 0
        while let edit = pendingContentEdits[contentID] {
            do {
                switch edit.target {
                case .project(let reference):
                    try await updateItemContent(reference, contentID: contentID, title: edit.title, body: edit.body)
                case .personal(let item):
                    try await updatePersonalItemContent(item, title: edit.title, body: edit.body)
                }
                pendingContentEdits[contentID] = nil
                return
            } catch is CancellationError {
                return
            } catch {
                if shouldRetryTransientWrite(error), retryCount < 2 {
                    retryCount += 1
                    do { try await Task.sleep(for: .milliseconds(retryCount == 1 ? 500 : 1_000)) }
                    catch { return }
                    continue
                }
                guard var current = pendingContentEdits[contentID] else { return }
                current.state = .failed(error.localizedDescription)
                pendingContentEdits[contentID] = current
                return
            }
        }
    }

    func refreshItem(_ reference: ItemInspectorReference) async throws {
        guard refreshingItemReferences.contains(reference) == false,
              let project = project(id: reference.projectID) else { return }

        refreshingItemReferences.insert(reference)
        defer { refreshingItemReferences.remove(reference) }

        guard try await refreshProjectSnapshot(id: project.id) != nil else { return }

        if let refreshedItem = item(for: reference) {
            await loadItemDetail(for: refreshedItem, forceRefresh: true)

            if case .loaded(let detail) = itemDetailState(for: refreshedItem),
               let metadata = detail.issueMetadata,
               metadata.viewerCanSetMilestone {
                await loadMilestones(
                    repository: metadata.repository,
                    forceRefresh: true
                )
            }
        }

        try Task.checkCancellation()
        await persistCache()
    }

    func milestoneState(for repository: String) -> RepositoryMilestonesState {
        repositoryMilestones[repository] ?? .idle
    }

    func loadItemDetail(for item: ProjectItem, forceRefresh: Bool = false) async {
        guard let contentID = item.contentId else { return }
        await loadContentDetail(contentID: contentID, updatedAt: item.updatedAt, forceRefresh: forceRefresh)
    }

    func personalItemDetailState(_ contentID: String) -> ItemDetailState {
        itemDetailEntries[contentID]?.state ?? .idle
    }

    func loadPersonalItemDetail(_ item: PersonalWorkItem, forceRefresh: Bool = false) async {
        await loadContentDetail(contentID: item.id, updatedAt: item.updatedAt, forceRefresh: forceRefresh)
    }

    func beginPersonalContentEdit(_ item: PersonalWorkItem, title: String, body: String) throws {
        guard isActive else { throw CancellationError() }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ProjectStoreError.emptyItemTitle }
        guard pendingContentEdits[item.id] == nil, pendingContentMutations[item.id] == nil else {
            throw ProjectStoreError.operationInProgress
        }
        guard case .loaded(let detail) = personalItemDetailState(item.id), detail.viewerCanUpdate else {
            throw GitHubError.insufficientPermissions
        }
        pendingContentEdits[item.id] = PendingContentEdit(
            id: item.id, target: .personal(item), title: title, body: body, author: detail.author
        )
        startPendingEdit(item.id)
    }

    private func updatePersonalItemContent(_ item: PersonalWorkItem, title: String, body: String) async throws {
        guard isActive else { throw CancellationError() }
        guard pendingContentMutations[item.id] == nil else { throw ProjectStoreError.operationInProgress }
        await loadPersonalItemDetail(item)
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
        switch personalItemDetailState(item.id) {
        case .loaded(let detail):
            guard detail.viewerCanUpdate else { throw GitHubError.insufficientPermissions }
        case .failed(let message): throw ProjectStoreError.itemDetailsFailed(message)
        case .idle, .loading: throw ProjectStoreError.operationInProgress
        }
        try await performContentMutation([item.id], operation: {
            try await self.gitHubService.updateItemContent(
                contentID: item.id, contentType: item.isPullRequest ? .pullRequest : .issue,
                title: title, body: body
            )
        }) { updated in
            self.updateContent(contentID: item.id) { projectItem in
                projectItem.title = updated.title
                projectItem.updatedAt = updated.updatedAt
            }
            self.updatePersonalSummary(contentID: item.id, updated: updated)
            self.updateDetail(contentID: item.id, sourceUpdatedAt: updated.updatedAt) { detail in
                detail.title = updated.title
                detail.body = updated.body
                detail.updatedAt = updated.updatedAt
            }
        }
    }

    private func loadContentDetail(contentID: String, updatedAt: String?, forceRefresh: Bool) async {
        guard isActive, pendingContentMutations[contentID] == nil else { return }
        if forceRefresh == false,
           let entry = itemDetailEntries[contentID],
           entry.sourceUpdatedAt == updatedAt {
            switch entry.state {
            case .loaded:
                return
            case .loading:
                if let task = itemDetailTasks[contentID] {
                    await finishItemDetailLoad(
                        task,
                        contentID: contentID,
                        sourceUpdatedAt: updatedAt,
                        generation: itemDetailGenerations[contentID, default: 0]
                    )
                }
                return
            case .idle, .failed:
                break
            }
        }

        itemDetailTasks[contentID]?.cancel()
        let generation = itemDetailGenerations[contentID, default: 0] + 1
        itemDetailGenerations[contentID] = generation
        itemDetailEntries[contentID] = ItemDetailEntry(
            sourceUpdatedAt: updatedAt,
            state: .loading
        )

        let task = Task { try await gitHubService.fetchItemDetail(contentID: contentID) }
        itemDetailTasks[contentID] = task
        await finishItemDetailLoad(
            task,
            contentID: contentID,
            sourceUpdatedAt: updatedAt,
            generation: generation
        )
    }

    func loadMilestones(repository: String, forceRefresh: Bool = false) async {
        if forceRefresh == false {
            switch milestoneState(for: repository) {
            case .loading, .loaded:
                return
            case .idle, .failed:
                break
            }
        }

        repositoryMilestones[repository] = .loading
        do {
            let milestones = try await gitHubService.fetchRepositoryMilestones(
                repository: repository
            )
            repositoryMilestones[repository] = .loaded(milestones)
        } catch is CancellationError {
            repositoryMilestones[repository] = .idle
        } catch {
            repositoryMilestones[repository] = .failed(error.localizedDescription)
        }
    }

    func setMilestone(_ milestone: RepositoryMilestone?, on item: ProjectItem) async throws {
        guard let contentID = item.contentId,
              case .loaded(let detail) = itemDetailState(for: item),
              let metadata = detail.issueMetadata, metadata.viewerCanSetMilestone else { return }

        try await performContentMutation([contentID], operation: {
            try await self.gitHubService.updateIssueMilestone(issueID: contentID, milestoneID: milestone?.id)
        }) {
            self.updateContent(contentID: contentID) { item in
                item.milestone = milestone.map {
                    ProjectPlanningReference(id: $0.id, title: $0.title,
                                             repository: metadata.repository, number: nil)
                }
            }
            self.updateDetail(contentID: contentID) { detail in
                detail.issueMetadata?.milestone = milestone
            }
        }
    }

    func addRelation(
        _ kind: IssueRelationKind,
        target: GitHubItemCandidate,
        on item: ProjectItem
    ) async throws {
        guard target.contentType == .issue,
              let issueID = item.contentId,
              case .loaded(let detail) = itemDetailState(for: item),
              detail.issueMetadata?.viewerCanUpdate == true else { return }
        let endpoints = kind.endpoints(issueID: issueID, relatedIssueID: target.id)

        var affectedContentIDs: Set<String> = [issueID, target.id]
        if kind == .parent, let previousParent = detail.issueMetadata?.parent {
            affectedContentIDs.insert(previousParent.id)
        }
        try await performRelationshipMutation(affectedContentIDs) {
            switch kind {
            case .parent, .subIssue:
                try await self.gitHubService.addSubIssue(
                    parentIssueID: endpoints.issueID,
                    subIssueID: endpoints.relatedIssueID,
                    replacingParent: kind == .parent
                )
            case .blockedBy, .blocking:
                try await self.gitHubService.addBlockedBy(
                    issueID: endpoints.issueID,
                    blockingIssueID: endpoints.relatedIssueID
                )
            }
        }
    }

    func removeRelation(
        _ kind: IssueRelationKind,
        relatedIssue: IssueReference,
        from item: ProjectItem
    ) async throws {
        guard let issueID = item.contentId,
              case .loaded(let detail) = itemDetailState(for: item),
              detail.issueMetadata?.viewerCanUpdate == true else { return }
        let endpoints = kind.endpoints(issueID: issueID, relatedIssueID: relatedIssue.id)

        try await performRelationshipMutation([issueID, relatedIssue.id]) {
            switch kind {
            case .parent, .subIssue:
                try await self.gitHubService.removeSubIssue(
                    parentIssueID: endpoints.issueID,
                    subIssueID: endpoints.relatedIssueID
                )
            case .blockedBy, .blocking:
                try await self.gitHubService.removeBlockedBy(
                    issueID: endpoints.issueID,
                    blockingIssueID: endpoints.relatedIssueID
                )
            }
        }
    }

    var repositorySuggestions: [String] {
        guard let project = selectedProject else { return [] }
        let linked = project.linkedRepositories.sorted()
        let used = Set(project.items.compactMap(\.repositoryName)).subtracting(linked)
        return linked + used.sorted()
    }

    var defaultIssueRepository: String {
        guard let project = selectedProject else { return "" }
        return defaultIssueRepository(in: project)
    }

    func defaultIssueRepository(in project: Project) -> String {
        if project.linkedRepositories.count == 1 { return project.linkedRepositories[0] }
        let suggestions = Set(project.items.compactMap(\.repositoryName)).sorted()
        return project.linkedRepositories.isEmpty && suggestions.count == 1 ? suggestions[0] : ""
    }

    init(
        gitHubService: GitHubService = GitHubService(),
        projectCache: ProjectCache = ProjectCache(),
        defaults: UserDefaults = .standard
    ) {
        self.gitHubService = gitHubService
        self.projectCache = projectCache
        self.defaults = defaults
        selectedOwnerId = defaults.string(forKey: "selectedOwnerId")
        selectedProjectId = defaults.string(forKey: "selectedProjectId")
        selectedStatusFilter = defaults.string(forKey: "selectedStatusFilter")
    }

    func invalidateSession() async throws {
        isActive = false
        personalWorkTasks.values.forEach { $0.cancel() }
        personalWorkTasks = [:]
        personalWorkReadIDs = [:]
        personalWorkNeedsRefresh = []
        personalWork = [:]
        personalWorkErrors = [:]
        loadingPersonalWork = []
        catalogGeneration += 1
        followedProjectsGeneration += 1
        contentRevision += 1
        cancelProjectLoad()
        reconciliationTasks.values.forEach { $0.task.cancel() }
        reconciliationTasks = [:]
        itemDetailTasks.values.forEach { $0.cancel() }
        itemDetailTasks = [:]
        itemDetailGenerations = [:]
        itemDetailEntries = [:]
        projectStates = [:]
        catalogProjectIDs = []
        followedProjectIDs = []
        pendingItemMutations = [:]
        pendingContentMutations = [:]
        pendingCreationTasks.values.forEach { $0.cancel() }
        pendingEditTasks.values.forEach { $0.cancel() }
        pendingCreationTasks = [:]
        pendingEditTasks = [:]
        pendingCreations = [:]
        pendingContentEdits = [:]
        pendingStatusMoves = [:]
        pendingRoadmapEdits = [:]
        owners = []
        repositoryLists = [:]
        repositoryReadIDs = [:]
        repositoryMilestones = [:]
        selectedOwnerId = nil
        selectedProjectId = nil
        selectedStatusFilter = nil
        currentAccount = nil
        sessionState = .signedOut
        await gitHubService.invalidate()
        try await projectCache.invalidate()
    }

    func loadProjects() async {
        cancelProjectLoad()
        guard isActive else { return }
        catalogGeneration += 1
        let generation = catalogGeneration
        isLoading = true
        error = nil
        operationErrorMessage = nil
        sessionState = .checking
        defer {
            if generation == catalogGeneration { isLoading = false }
        }

        let session = await gitHubService.inspectSession()
        guard generation == catalogGeneration, !Task.isCancelled else { return }
        sessionState = session

        guard case .ready(let account) = session else {
            if isShowingCachedData {
                error = nil
                operationErrorMessage = cachedDataMessage(for: session)
            } else {
                error = sessionError(for: session)
            }
            return
        }

        currentAccount = account
        await restoreCacheIfNeeded(account: account)
        guard generation == catalogGeneration, isActive else { return }

        do {
            let loadedOwners = try await gitHubService.fetchOwners()
            try Task.checkCancellation()
            guard generation == catalogGeneration else { return }
            owners = loadedOwners

            let owner = loadedOwners.first { $0.id == selectedOwnerId } ?? loadedOwners.first
            guard let owner else {
                replaceCatalog(with: [])
                selectedOwnerId = nil
                selectedProjectId = nil
                return
            }
            selectedOwnerId = owner.id
            await loadProjects(for: owner, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == catalogGeneration else { return }
            if isShowingCachedData {
                self.error = nil
                operationErrorMessage = String(localized: "Showing cached data because GitHub owners could not refresh: \(error.localizedDescription)")
            } else {
                self.error = error
            }
        }
    }

    func loadProjectDetails(id: String) async {
        guard projectStates[id] != nil else { return }
        cancelProjectLoad()
        if let reconciliation = reconciliationTasks[id] {
            await reconciliation.task.value
            return
        }
        let generation = projectGeneration
        operationErrorMessage = nil
        let task = Task { try await refreshProjectSnapshot(id: id) }
        projectLoadTask = task
        defer {
            if generation == projectGeneration {
                projectLoadTask = nil
            }
        }
        do {
            _ = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
        } catch is CancellationError {
        } catch {
            guard generation == projectGeneration else { return }
            operationErrorMessage = error.localizedDescription
        }
    }

    func selectOwner(_ owner: ProjectOwner) async {
        guard owner.id != selectedOwnerId else { return }
        cancelProjectLoad()
        catalogGeneration += 1
        let generation = catalogGeneration
        selectedOwnerId = owner.id
        selectedProjectId = nil
        selectedStatusFilter = nil
        isLoading = true
        error = nil

        await loadProjects(for: owner, generation: generation)
    }

    func refresh() async {
        guard let selectedId = selectedProjectId else {
            await loadProjects()
            return
        }

        await loadProjectDetails(id: selectedId)
    }

    func refreshFollowedProjects(_ references: [FollowedProject]) async {
        setFollowedProjects(references)
        let generation = followedProjectsGeneration

        guard references.isEmpty == false else { return }

        isLoadingFollowedProjects = true
        defer {
            if generation == followedProjectsGeneration {
                isLoadingFollowedProjects = false
            }
        }

        do {
            _ = try await refreshMonitoredProjects(references)
        } catch is CancellationError {
            return
        } catch {
            guard generation == followedProjectsGeneration else { return }
            followedProjectsErrorMessage = error.localizedDescription
        }
    }

    func setFollowedProjects(_ references: [FollowedProject]) {
        let references = references.filter { !deletedProjectIDs.contains($0.id) }
        followedProjectsGeneration += 1
        let previousIDs = followedProjectIDs
        followedProjectIDs = Set(references.map(\.id))
        for reference in references where projectStates[reference.id] == nil {
            projectStates[reference.id] = ProjectState(owner: reference.owner)
        }
        for id in previousIDs.subtracting(followedProjectIDs)
            where !catalogProjectIDs.contains(id) {
            removeProject(id: id)
        }
        followedProjectsErrorMessage = nil
        isLoadingFollowedProjects = false
    }

    // nil means this cycle was superseded, not that the projects are empty.
    func refreshMonitoredProjects(_ references: [FollowedProject]) async throws -> [Project]? {
        let generation = followedProjectsGeneration
        let revision = contentRevision
        let revisions = references.map { projectStates[$0.id]?.mutationRevision }
        var snapshots: [Project] = []
        for reference in references {
            try Task.checkCancellation()
            guard generation == followedProjectsGeneration,
                  followedProjectIDs.contains(reference.id) else { return nil }
            if let snapshot = try await refreshProjectSnapshot(id: reference.id, followedGeneration: generation) {
                snapshots.append(snapshot)
            }
        }
        guard snapshots.count == references.count,
              generation == followedProjectsGeneration, revision == contentRevision,
              revisions == references.map({ projectStates[$0.id]?.mutationRevision }),
              pendingContentMutations.isEmpty,
              references.allSatisfy({ projectStates[$0.id]?.mutations.isEmpty == true }) else { return nil }
        return snapshots
    }

    func repositoryListState(ownerID: String) -> RepositoryListState {
        repositoryLists[ownerID] ?? .idle
    }

    func loadRepositories(owner: ProjectOwner) async {
        let readID = UUID()
        repositoryReadIDs[owner.id] = readID
        repositoryLists[owner.id] = .loading
        do {
            let repositories = try await gitHubService.fetchRepositories(owner: owner)
            try Task.checkCancellation()
            guard repositoryReadIDs[owner.id] == readID else { return }
            repositoryLists[owner.id] = .loaded(repositories)
        } catch {
            guard repositoryReadIDs[owner.id] == readID else { return }
            repositoryLists[owner.id] = error is CancellationError ? .idle : .failed(error.localizedDescription)
        }
    }

    func deleteProject(id: String) async throws {
        guard let project = project(id: id), project.viewerCanUpdate,
              projectStates[id]?.source != .cache else { throw ProjectStoreError.readOnlyProject }
        guard !deletingProjectIDs.contains(id),
              projectStates[id]?.mutations.isEmpty == true,
              pendingContentMutations.isEmpty,
              !linkingRepositoryProjectIDs.contains(id) else { throw ProjectStoreError.operationInProgress }
        deletingProjectIDs.insert(id)
        defer {
            deletingProjectIDs.remove(id)
            scheduleReconciliation()
        }
        try await gitHubService.deleteProject(id: id)

        // Reject catalog and monitoring responses that were already in flight.
        deletedProjectIDs.insert(id)
        followedProjectIDs.remove(id)
        followedProjectsGeneration += 1
        isLoadingFollowedProjects = false
        followedProjectsErrorMessage = nil
        let contentIDs = project.items.compactMap(\.contentId)
        invalidateContentDetails(contentIDs)
        catalogProjectIDs.removeAll { $0 == id }
        removeProject(id: id)
        let wasSelected = selectedProjectId == id
        if wasSelected {
            cancelProjectLoad()
            selectedProjectId = catalogProjectIDs.first
            selectedStatusFilter = nil
            operationErrorMessage = nil
            error = nil
        }
        lastUpdated = Date()
        if wasSelected, let next = selectedProject {
            await selectProject(next)
        }
        do {
            try await projectCache.removeProject(id: id)
        } catch {
            operationErrorMessage = String(localized: "Project deleted, but its local cache could not be removed: \(error.localizedDescription)")
        }
    }

    func linkRepository(_ repository: ProjectRepository, to projectID: String) async throws {
        guard let project = project(id: projectID) else { throw ProjectStoreError.noProjectSelected }
        guard !deletingProjectIDs.contains(projectID), project.viewerCanUpdate, projectStates[projectID]?.source != .cache else { throw ProjectStoreError.readOnlyProject }
        guard repository.ownerID == project.owner.id else { throw ProjectStoreError.repositoryOwnerMismatch }
        guard linkingRepositoryProjectIDs.insert(projectID).inserted else {
            throw ProjectStoreError.operationInProgress
        }
        defer { linkingRepositoryProjectIDs.remove(projectID) }
        try await gitHubService.linkProjectRepository(projectID: projectID, repositoryID: repository.id)
    }

    func createProject(owner: ProjectOwner, title: String, repository: ProjectRepository? = nil) async throws {
        if let repository, repository.ownerID != owner.id { throw ProjectStoreError.repositoryOwnerMismatch }
        guard !isCreatingProject else { throw ProjectStoreError.operationInProgress }
        isCreatingProject = true
        defer { isCreatingProject = false }
        var project = try await gitHubService.createProject(owner: owner, title: title, repositoryID: repository?.id)
        project.linkedRepositories = repository.map { [$0.nameWithOwner] } ?? []

        // The mutation succeeded. Subsequent read failures must not invite creation again.
        cancelProjectLoad()
        catalogGeneration += 1
        let generation = catalogGeneration
        let existing = selectedOwnerId == owner.id ? projects : []
        selectedOwnerId = owner.id
        replaceCatalog(with: [project] + existing.filter { $0.id != project.id })
        selectedProjectId = project.id
        selectedStatusFilter = nil
        error = nil
        operationErrorMessage = nil
        isLoading = true
        do {
            let catalog = try await gitHubService.fetchProjects(owner: owner)
            guard generation == catalogGeneration else { return }
            replaceCatalog(with: [project] + mergingCatalog(catalog.filter { $0.id != project.id }))
        } catch {
            guard generation == catalogGeneration else { return }
            operationErrorMessage = String(localized: "Project created, but the project list could not refresh: \(error.localizedDescription)")
        }
        guard generation == catalogGeneration else { return }
        isLoading = false
        // Uses the normal detail state and retry UI if fields or items cannot load.
        let catalogError = operationErrorMessage
        await loadProjectDetails(id: project.id)
        if operationErrorMessage == nil { operationErrorMessage = catalogError }
    }

    func selectProject(_ project: Project, refresh: Bool = false) async {
        let phase = projectStates[project.id]?.phase ?? .summary
        guard refresh || project.id != selectedProjectId || phase != .loaded else { return }
        selectedProjectId = project.id
        selectedStatusFilter = nil
        operationErrorMessage = nil
        guard refresh || (phase != .loading && phase != .refreshing) else { return }
        await loadProjectDetails(id: project.id)
    }

    func openProject(_ reference: FollowedProject) async {
        if selectedOwnerId != reference.owner.id {
            let owner = owners.first { $0.id == reference.owner.id } ?? reference.owner
            await selectOwner(owner)
        }
        if let project = project(id: reference.id) {
            await selectProject(project)
        }
    }

    private func loadProjects(for owner: ProjectOwner, generation: Int) async {
        defer {
            if generation == catalogGeneration { isLoading = false }
        }
        do {
            let loadedProjects = try await gitHubService.fetchProjects(owner: owner).filter { !deletedProjectIDs.contains($0.id) }
            try Task.checkCancellation()
            guard generation == catalogGeneration, selectedOwnerId == owner.id else { return }
            let mergedProjects = mergingCatalog(loadedProjects)
            replaceCatalog(with: mergedProjects)

            let selectedProject = loadedProjects.first { $0.id == selectedProjectId }
                ?? loadedProjects.first
            if selectedProjectId != selectedProject?.id {
                selectedStatusFilter = nil
            }
            selectedProjectId = selectedProject?.id

            if let selectedProject {
                await loadProjectDetails(id: selectedProject.id)
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == catalogGeneration else { return }
            if isShowingCachedData {
                self.error = nil
                operationErrorMessage = String(localized: "Showing cached data because the project list could not refresh: \(error.localizedDescription)")
            } else if projects.contains(where: { $0.owner.id == owner.id }) {
                operationErrorMessage = String(localized: "The project list could not refresh: \(error.localizedDescription)")
            } else {
                replaceCatalog(with: [])
                selectedProjectId = nil
                self.error = error
            }
        }
    }

    private func restoreCacheIfNeeded(account: GitHubAccount) async {
        guard didRestoreCache == false else { return }
        didRestoreCache = true

        guard let snapshot = try? await projectCache.load(),
              snapshot.accountID == account.id, isActive,
              snapshot.projects.isEmpty == false else { return }

        cachedAccountLogin = snapshot.accountLogin
        owners = [snapshot.owner]
        let cachedProjects = snapshot.projects.map(makeReadOnly)
        replaceCatalog(with: cachedProjects)
        for id in snapshot.detailedProjectIDs where projectStates[id] != nil {
            projectStates[id]?.source = .cache
        }
        selectedOwnerId = snapshot.owner.id
        selectedProjectId = snapshot.projects.contains { $0.id == snapshot.selectedProjectId }
            ? snapshot.selectedProjectId
            : snapshot.projects.first?.id

        if let selectedStatusFilter = snapshot.selectedStatusFilter,
           selectedProject?.statusOptions.contains(where: { $0.name == selectedStatusFilter }) == true {
            self.selectedStatusFilter = selectedStatusFilter
        } else {
            self.selectedStatusFilter = nil
        }
        lastUpdated = snapshot.savedAt
    }

    private func persistCache() async {
        guard isActive, let account = currentAccount,
              let owner = selectedOwner,
              projects.isEmpty == false else { return }
        do {
            try await projectCache.save(
                ProjectCacheSnapshot(
                    accountID: account.id,
                    accountLogin: account.login,
                    owner: owner,
                    projects: catalogProjectIDs.compactMap { projectStates[$0]?.snapshot },
                    detailedProjectIDs: Set(projectStates.compactMap { id, state in
                        state.source == .catalog ? nil : id
                    }),
                    selectedProjectId: selectedProjectId,
                    selectedStatusFilter: selectedStatusFilter
                )
            )
            cachedAccountLogin = account.login
        } catch {
            operationErrorMessage = String(localized: "Project loaded, but the local cache could not be updated: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func refreshProjectSnapshot(id: String, followedGeneration: Int? = nil) async throws -> Project? {
        guard let state = projectStates[id] else { return nil }
        guard !deletingProjectIDs.contains(id), state.mutations.isEmpty, pendingContentMutations.isEmpty else {
            projectStates[id]?.needsRefresh = true
            return nil
        }
        let ticket = ProjectReadTicket(
            projectID: id, requestID: UUID(), mutationRevision: state.mutationRevision,
            contentRevision: contentRevision, followedGeneration: followedGeneration
        )
        projectStates[id]?.latestReadID = ticket.requestID
        projectStates[id]?.load = .loading
        projectStates[id]?.needsRefresh = false
        do {
            var snapshot = try await gitHubService.fetchProjectWithItems(id: id, owner: state.owner)
            try Task.checkCancellation()
            guard canCommit(ticket) else {
                discardRead(ticket)
                return nil
            }
            snapshot = try await reconcilingCreatedItems(in: snapshot, projectID: id)
            try Task.checkCancellation()
            guard canCommit(ticket) else {
                discardRead(ticket)
                return nil
            }
            projectStates[id]?.createdItemFieldsAwaitingObservation = [:]
            snapshot = mergingConfirmedContent(into: snapshot, projectID: id)
            projectStates[id]?.snapshot = snapshot
            projectStates[id]?.source = .remote
            projectStates[id]?.load = .idle
            lastUpdated = Date()
            await persistCache()
            return canCommit(ticket) ? snapshot : nil
        } catch {
            guard canCommit(ticket) else { discardRead(ticket); return nil }
            projectStates[id]?.load = error is CancellationError ? .idle : .failed(error.localizedDescription)
            throw error
        }
    }

    private func canCommit(_ ticket: ProjectReadTicket) -> Bool {
        guard let state = projectStates[ticket.projectID] else { return false }
        return !deletingProjectIDs.contains(ticket.projectID) && state.latestReadID == ticket.requestID
            && state.mutationRevision == ticket.mutationRevision
            && contentRevision == ticket.contentRevision
            && state.mutations.isEmpty && pendingContentMutations.isEmpty
            && (ticket.followedGeneration == nil || ticket.followedGeneration == followedProjectsGeneration)
    }

    private func discardRead(_ ticket: ProjectReadTicket) {
        guard projectStates[ticket.projectID]?.latestReadID == ticket.requestID else { return }
        projectStates[ticket.projectID]?.load = .idle
        if projectStates[ticket.projectID]?.mutationRevision != ticket.mutationRevision
            || contentRevision != ticket.contentRevision
            || (ticket.followedGeneration != nil && ticket.followedGeneration != followedProjectsGeneration
                && followedProjectIDs.contains(ticket.projectID)) {
            projectStates[ticket.projectID]?.needsRefresh = true
            scheduleReconciliation()
        }
    }

    private func scheduleReconciliation() {
        guard pendingContentMutations.isEmpty else { return }
        for (id, state) in projectStates where state.needsRefresh && state.mutations.isEmpty {
            guard reconciliationTasks[id] == nil else { continue }
            let taskID = UUID()
            let task = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.reconciliationTasks[id]?.id == taskID {
                        self.reconciliationTasks[id] = nil
                        self.scheduleReconciliation()
                    }
                }
                do {
                    try Task.checkCancellation()
                    guard self.projectStates[id]?.needsRefresh == true else { return }
                    _ = try await self.refreshProjectSnapshot(id: id)
                }
                catch is CancellationError {}
                catch { self.operationErrorMessage = error.localizedDescription }
            }
            reconciliationTasks[id] = (taskID, task)
        }
    }

    private func removeProject(id: String) {
        projectStates[id] = nil
        pendingRoadmapEdits = pendingRoadmapEdits.filter { $0.key.projectID != id }
        pendingStatusMoves = pendingStatusMoves.filter { $0.key.projectID != id }
        pendingItemMutations = pendingItemMutations.filter { $0.key.projectID != id }
        reconciliationTasks.removeValue(forKey: id)?.task.cancel()
    }

    private func mergingCatalog(_ loadedProjects: [Project]) -> [Project] {
        let detailedProjects = projectStates.compactMapValues(\.snapshot)
        return loadedProjects.map { project in
            guard let source = projectStates[project.id]?.source, source != .catalog,
                  let detailed = detailedProjects[project.id] else {
                return project
            }
            return Project(
                id: project.id,
                owner: project.owner,
                title: project.title,
                number: project.number,
                url: project.url,
                viewerCanUpdate: projectStates[project.id]?.source == .cache
                    ? false
                    : project.viewerCanUpdate,
                linkedRepositories: detailed.linkedRepositories,
                fields: detailed.fields,
                statusField: detailed.statusField,
                items: detailed.items
            )
        }
    }

    private func commitCreatedItem(_ item: ProjectItem, projectID: String) {
        guard var project = projectStates[projectID]?.snapshot else { return }
        project.items.removeAll { $0.id == item.id || (item.contentId != nil && $0.contentId == item.contentId) }
        project.items.append(item)
        projectStates[projectID]?.snapshot = project
        projectStates[projectID]?.createdItemFieldsAwaitingObservation[item.id] = item.fieldValues
        lastUpdated = Date()
    }

    private func reconcilingCreatedItems(in snapshot: Project, projectID: String) async throws -> Project {
        let confirmed = projectStates[projectID]?.createdItemFieldsAwaitingObservation ?? [:]
        var reconciled = snapshot
        for (id, fields) in confirmed.sorted(by: { $0.key < $1.key }) {
            if let observed = snapshot.items.first(where: { $0.id == id }),
               fields.allSatisfy({ observed.fieldValues[$0.key] == $0.value }) { continue }

            // A list read can lag behind creation. Resolve this membership directly once;
            // differing remote fields may be a later edit, not a stale response.
            let current = try await gitHubService.fetchProjectItem(id: id)
            reconciled.items.removeAll { $0.id == id }
            if let current { reconciled.items.append(current) }
        }
        return reconciled
    }

    private func mergingConfirmedContent(into snapshot: Project, projectID: String) -> Project {
        guard let versions = projectStates[projectID]?.confirmedContentAwaitingObservation,
              !versions.isEmpty else { return snapshot }
        var merged = snapshot
        for (contentID, version) in versions {
            guard let index = snapshot.items.firstIndex(where: { $0.contentId == contentID }) else { continue }
            if (snapshot.items[index].title == version.title &&
                snapshot.items[index].updatedAt == version.updatedAt) ||
                isNewerGitHubTimestamp(snapshot.items[index].updatedAt, than: version.updatedAt) {
                projectStates[projectID]?.confirmedContentAwaitingObservation[contentID] = nil
            } else {
                merged.items[index].title = version.title
                merged.items[index].updatedAt = version.updatedAt
            }
        }
        return merged
    }

    private func isNewerGitHubTimestamp(_ observed: String?, than confirmed: String) -> Bool {
        guard let observed else { return false }
        let formatter = ISO8601DateFormatter()
        func date(_ value: String) -> Date? {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: value) { return parsed }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
        guard let observedDate = date(observed), let confirmedDate = date(confirmed) else { return false }
        return observedDate > confirmedDate
    }

    private func replaceCatalog(with projects: [Project]) {
        let projects = projects.filter { !deletedProjectIDs.contains($0.id) }
        let newIDs = Set(projects.map(\.id))
        for id in Set(catalogProjectIDs).subtracting(newIDs) where !followedProjectIDs.contains(id) {
            removeProject(id: id)
        }
        catalogProjectIDs = projects.map(\.id)
        for project in projects {
            if projectStates[project.id] == nil { projectStates[project.id] = ProjectState(owner: project.owner) }
            projectStates[project.id]?.snapshot = project
        }
    }

    private func makeReadOnly(_ project: Project) -> Project {
        Project(
            id: project.id,
            owner: project.owner,
            title: project.title,
            number: project.number,
            url: project.url,
            viewerCanUpdate: false,
            linkedRepositories: project.linkedRepositories,
            fields: project.fields,
            statusField: project.statusField,
            items: project.items
        )
    }

    private func cachedDataMessage(for state: GitHubSessionState) -> String {
        let reason = sessionError(for: state)?.localizedDescription ?? String(localized: "GitHub is unavailable.")
        return String(localized: "Showing cached data. \(reason)")
    }

    private func cancelProjectLoad() {
        projectLoadTask?.cancel()
        projectLoadTask = nil
        projectGeneration += 1
    }

    private func sessionError(for state: GitHubSessionState) -> GitHubError? {
        switch state {
        case .checking, .ready:
            return nil
        case .missingCLI:
            return .ghCLINotFound
        case .signedOut:
            return .notAuthenticated
        case .missingProjectScope:
            return .missingProjectScope
        case .failed(let message):
            return .connectionError(message)
        }
    }

    func moveItem(
        _ item: ProjectItem, toStatus status: StatusOption, in projectID: String
    ) async throws {
        let project = try editableProject(id: projectID)
        guard let fieldID = project.statusField?.id,
              project.statusOptions.contains(where: { $0.id == status.id }),
              project.items.contains(where: { $0.id == item.id }) else {
            throw ProjectStoreError.itemUnavailable
        }
        try await performProjectMutation(
            projectID: projectID, itemID: item.id, optimisticStatus: (fieldID, status)
        ) {
            try await self.gitHubService.updateItemStatus(
                projectId: projectID, itemId: item.id, fieldId: fieldID, optionId: status.id
            )
        } apply: { _ in
            self.updateItem(projectID: projectID, itemID: item.id) { item in
                item.status = status.name
                item.statusOptionId = status.id
                item.fieldValues[fieldID] = .singleSelect(optionId: status.id, name: status.name)
            }
        }
        await persistCache()
    }

    func deleteItem(_ item: ProjectItem, from projectID: String) async throws {
        _ = try editableProject(id: projectID)
        try await performProjectMutation(projectID: projectID, itemID: item.id) {
            try await self.gitHubService.deleteItem(projectId: projectID, itemId: item.id)
        } apply: { _ in
            self.projectStates[projectID]?.snapshot?.items.removeAll { $0.id == item.id }
            self.projectStates[projectID]?.createdItemFieldsAwaitingObservation[item.id] = nil
            self.invalidateContentDetails([item.contentId].compactMap { $0 })
        }
        await persistCache()
    }

    func archiveItem(_ item: ProjectItem, in projectID: String) async throws {
        _ = try editableProject(id: projectID)
        try await performProjectMutation(projectID: projectID, itemID: item.id) {
            try await self.gitHubService.archiveItem(projectId: projectID, itemId: item.id)
        } apply: { _ in
            self.projectStates[projectID]?.snapshot?.items.removeAll { $0.id == item.id }
            self.projectStates[projectID]?.createdItemFieldsAwaitingObservation[item.id] = nil
            self.invalidateContentDetails([item.contentId].compactMap { $0 })
        }
        await persistCache()
    }

    func updateRoadmap(
        on item: ProjectItem, in projectID: String, startFieldID: String, endFieldID: String,
        kind: RoadmapEditKind, days: Int
    ) async throws {
        let project = try editableProject(id: projectID)
        let key = ItemMutationKey(projectID: projectID, itemID: item.id)
        guard pendingItemMutations[key] == nil, pendingCreationState(for: item.id) == nil else {
            throw ProjectStoreError.operationInProgress
        }
        guard let current = project.items.first(where: { $0.id == item.id }) else {
            throw ProjectStoreError.itemUnavailable
        }
        for id in Set([startFieldID, endFieldID]) where !id.isEmpty {
            guard project.fields.contains(where: { $0.id == id && ($0.kind == .date || $0.kind == .iteration) }),
                  current.fieldValues[id] == item.fieldValues[id] else { throw RoadmapEditError.changedSchedule }
        }
        let edit = try RoadmapEdit.make(values: item.fieldValues, fields: project.fields,
            startFieldID: startFieldID, endFieldID: endFieldID, kind: kind, days: days)
        guard !edit.changes.isEmpty else { return }
        do {
            try await performProjectMutation(projectID: projectID, itemID: item.id) {
                let operationID = self.pendingItemMutations[key]
                self.pendingRoadmapEdits[key] = edit
                defer { self.pendingRoadmapEdits[key] = nil }
                do {
                    for change in edit.changes {
                        try Task.checkCancellation()
                        try await self.gitHubService.updateItemField(
                            projectId: projectID, itemId: item.id, fieldId: change.fieldID, value: change.value
                        )
                        guard self.isActive, self.pendingItemMutations[key] == operationID else {
                            throw CancellationError()
                        }
                        self.updateItem(projectID: projectID, itemID: item.id) {
                            $0.fieldValues[change.fieldID] = change.value
                        }
                    }
                } catch {
                    // Each field is a separate remote write, and a lost response can be ambiguous.
                    if self.isActive, self.pendingItemMutations[key] == operationID {
                        self.projectStates[projectID]?.needsRefresh = true
                    }
                    throw error
                }
            }
        } catch {
            await persistCache()
            if error is CancellationError { throw error }
            if error is ProjectStoreError { throw error }
            throw RoadmapEditError.incompleteWrite(error.localizedDescription)
        }
        await persistCache()
    }

    func setDefaultPriority(_ priority: ProjectPriority, on item: ProjectItem, in projectID: String) async throws {
        let project = try editableProject(id: projectID)
        let field: ProjectField
        if let existing = try ProjectField.priorityField(in: project.fields) {
            field = existing
        } else {
            field = try await performProjectMutation(projectID: projectID, itemID: item.id) {
                try await self.gitHubService.ensureProjectPriorityField(projectID: projectID)
            } apply: { field in
                if var project = self.projectStates[projectID]?.snapshot {
                    project.fields.removeAll { $0.id == field.id }
                    project.fields.append(field)
                    self.projectStates[projectID]?.snapshot = project
                }
            }
        }
        // Retain the confirmed field even if assigning the item fails. A retry reuses it.
        let matches = field.options.filter { $0.name.caseInsensitiveCompare(priority.rawValue) == .orderedSame }
        guard matches.count == 1, let option = matches.first else {
            throw ProjectField.PriorityResolutionError.changedOptions
        }
        try await updateField(on: item, in: projectID, field: field,
                              value: .singleSelect(optionId: option.id, name: option.name))
    }

    func updateField(
        on item: ProjectItem, in projectID: String, field: ProjectField, value: ProjectFieldValue?
    ) async throws {
        _ = try editableProject(id: projectID)
        try await performProjectMutation(projectID: projectID, itemID: item.id) {
            try await self.gitHubService.updateItemField(
                projectId: projectID, itemId: item.id, fieldId: field.id, value: value
            )
        } apply: { _ in
            self.updateItem(projectID: projectID, itemID: item.id) { item in
                item.fieldValues[field.id] = value
                if self.projectStates[projectID]?.snapshot?.statusField?.id == field.id {
                    if case .singleSelect(let id, let name) = value {
                        item.status = name
                        item.statusOptionId = id
                    } else {
                        item.status = nil
                        item.statusOptionId = nil
                    }
                }
            }
        }
        await persistCache()
    }

    func moveItemToStatus(
        projectID: String,
        itemID: String,
        fieldID: String,
        optionID: String
    ) async throws {
        guard let project = project(id: projectID),
              project.statusField?.id == fieldID,
              let option = project.statusOptions.first(where: { $0.id == optionID }),
              let item = project.items.first(where: { $0.id == itemID }) else {
            throw ProjectStoreError.itemUnavailable
        }
        try await moveItem(item, toStatus: option, in: projectID)
    }

    func moveItems(
        _ items: [ProjectItem],
        to status: StatusOption,
        in projectID: String
    ) async throws {
        for item in items where item.status != status.name {
            try await moveItem(item, toStatus: status, in: projectID)
        }
    }

    func archiveItems(_ items: [ProjectItem], in projectID: String) async throws {
        for item in items {
            try await archiveItem(item, in: projectID)
        }
    }

    func searchUsers(query: String) async throws -> [Assignee] {
        try await gitHubService.searchUsers(query: query)
    }

    func addAssignee(to item: ProjectItem, in projectID: String, user: Assignee) async throws {
        try await setAssignee(user, assigned: true, on: item, in: projectID)
    }

    func removeAssignee(from item: ProjectItem, in projectID: String, user: Assignee) async throws {
        try await setAssignee(user, assigned: false, on: item, in: projectID)
    }

    private func setAssignee(
        _ user: Assignee, assigned: Bool, on item: ProjectItem, in projectID: String
    ) async throws {
        guard let contentID = item.contentId, let url = item.url,
              canEditProject(id: projectID) else { return }
        try await performContentMutation([contentID], operation: {
            if assigned {
                try await self.gitHubService.addAssignee(issueUrl: url, userLogin: user.login)
            } else {
                try await self.gitHubService.removeAssignee(issueUrl: url, userLogin: user.login)
            }
        }) {
            self.updateContent(contentID: contentID) { item in
                item.assignees.removeAll { $0.login.caseInsensitiveCompare(user.login) == .orderedSame }
                if assigned { item.assignees.append(user) }
            }
        }
    }

    func repositoryLabels(for reference: ItemInspectorReference) async throws -> [RepositoryLabel] {
        guard isActive, let url = item(for: reference)?.url else { throw ProjectStoreError.itemUnavailable }
        let labels = try await gitHubService.repositoryLabels(issueURL: url)
        guard isActive else { throw CancellationError() }
        return labels
    }

    func addLabel(to item: ProjectItem, in projectID: String, name: String) async throws {
        try await setLabel(name, assigned: true, on: item, in: projectID)
    }

    func removeLabel(from item: ProjectItem, in projectID: String, name: String) async throws {
        try await setLabel(name, assigned: false, on: item, in: projectID)
    }

    private func setLabel(
        _ name: String, assigned: Bool, on item: ProjectItem, in projectID: String
    ) async throws {
        guard let contentID = item.contentId, let url = item.url,
              canEditProject(id: projectID) else { return }
        try await performContentMutation([contentID], operation: {
            if assigned {
                return try await self.gitHubService.addLabel(issueUrl: url, label: name)
            } else {
                return try await self.gitHubService.removeLabel(issueUrl: url, label: name)
            }
        }) { labels in
            self.updateContent(contentID: contentID) { $0.labels = labels }
        }
    }

    func prepareIssueCreation(
        repository: String,
        title: String,
        body: String,
        labels: [String],
        assignees: [String],
        status: String? = nil,
        priority: String? = nil,
        startDate: Date? = nil,
        targetDate: Date? = nil,
        projectID: String? = nil
    ) throws -> IssueCreation {
        let project = try projectID.map { try editableProject(id: $0) } ?? editableSelectedProject()
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ProjectStoreError.emptyItemTitle }
        let repository = repository.trimmingCharacters(in: .whitespacesAndNewlines)

        let requestedFields = [("Status", status), ("Priority", priority)].compactMap { name, value in
            value.map { (name, $0) }
        }
        var resolvedFields: [(ProjectField, ProjectFieldValue)] = []
        var backlogFieldToPrepare: ProjectField?
        for (name, value) in requestedFields {
            guard let field = project.fields.first(where: {
                $0.kind == .singleSelect && $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else {
                throw ProjectStoreError.missingFieldOption(field: name, option: value)
            }
            guard let option = field.options.first(where: {
                $0.name.caseInsensitiveCompare(value) == .orderedSame
            }) else {
                if name == "Status" && value.caseInsensitiveCompare("Backlog") == .orderedSame {
                    backlogFieldToPrepare = field
                    continue
                }
                throw ProjectStoreError.missingFieldOption(field: name, option: value)
            }
            resolvedFields.append((field, .singleSelect(optionId: option.id, name: option.name)))
        }

        var dateFieldsToPrepare: [(String, ProjectFieldValue)] = []
        for (name, date) in [("Start date", startDate), ("Target date", targetDate)] {
            guard let date else { continue }
            let field = try ProjectField.dateField(named: name, in: project.fields)
            let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
            let value = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
            if let field { resolvedFields.append((field, .date(value))) }
            else { dateFieldsToPrepare.append((name, .date(value))) }
        }

        return IssueCreation(sessionID: sessionID, projectID: project.id, repository: repository, title: title, body: body,
                             labels: labels, assignees: assignees, selectedStatusName: status,
                             backlogFieldToPrepare: backlogFieldToPrepare, fields: resolvedFields,
                             dateFieldsToPrepare: dateFieldsToPrepare)
    }

    var pendingCreationList: [PendingItemCreation] {
        pendingCreations.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func beginIssueCreation(_ creation: IssueCreation) throws {
        guard isActive, creation.sessionID == sessionID,
              projectStates[creation.projectID] != nil else { throw GitHubError.accountChanged }
        let operation = PendingItemCreation(id: UUID(), projectID: creation.projectID,
                                            title: creation.displayTitle, kind: .issue(creation))
        pendingCreations[operation.id] = operation
        startPendingCreation(operation.id)
    }

    func beginDraftCreation(title: String, body: String, projectID: String? = nil) throws {
        let project = try projectID.map { try editableProject(id: $0) } ?? editableSelectedProject()
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ProjectStoreError.emptyItemTitle }
        let operation = PendingItemCreation(id: UUID(), projectID: project.id,
                                            title: title, kind: .draft(title: title, body: body))
        pendingCreations[operation.id] = operation
        startPendingCreation(operation.id)
    }

    func retryPendingCreation(_ id: UUID) {
        guard var operation = pendingCreations[id], pendingCreationTasks[id] == nil else { return }
        if case .unconfirmed = operation.state { return }
        operation.state = .syncing
        pendingCreations[id] = operation
        startPendingCreation(id)
    }

    func dismissPendingCreation(_ id: UUID) {
        guard pendingCreationTasks[id] == nil else { return }
        pendingCreations[id] = nil
    }

    private func startPendingCreation(_ id: UUID) {
        pendingCreationTasks[id] = Task { [weak self] in
            await self?.runPendingCreation(id)
        }
    }

    private func runPendingCreation(_ id: UUID) async {
        defer { pendingCreationTasks[id] = nil }
        var retryCount = 0
        while let operation = pendingCreations[id] {
            do {
                switch operation.kind {
                case .issue(let creation):
                    try await resumeIssueCreation(creation)
                case .draft(let title, let body):
                    try await createDraftIssue(title: title, body: body, projectID: operation.projectID)
                }
                pendingCreations[id] = nil
                return
            } catch is CancellationError {
                return
            } catch {
                let canRetry: Bool
                switch operation.kind {
                case .issue(let creation):
                    if case .ready = creation.phase,
                       case GitHubError.issueCreationNotStarted(_, let retryable) = error {
                        canRetry = retryable
                    } else if case .applyingFields = creation.phase {
                        canRetry = shouldRetryTransientWrite(error)
                    } else {
                        canRetry = false
                    }
                case .draft:
                    canRetry = false
                }
                if canRetry, retryCount < 2 {
                    retryCount += 1
                    do { try await Task.sleep(for: .milliseconds(retryCount == 1 ? 500 : 1_000)) }
                    catch { return }
                    continue
                }
                guard var current = pendingCreations[id] else { return }
                if case .issue(let creation) = current.kind, creation.phase == .unconfirmed {
                    current.state = .unconfirmed(creation.errorMessage ?? error.localizedDescription)
                } else if case .draft = current.kind, requiresReconciliation(error) {
                    current.state = .unconfirmed(error.localizedDescription)
                } else {
                    current.state = .failed(error.localizedDescription)
                }
                pendingCreations[id] = current
                return
            }
        }
    }

    func resumeIssueCreation(_ creation: IssueCreation) async throws {
        guard isActive, creation.sessionID == sessionID else { throw GitHubError.accountChanged }
        guard !creation.isRunning else { throw ProjectStoreError.operationInProgress }
        if case .completed = creation.phase { return }
        guard creation.phase != .unconfirmed else { throw GitHubError.issueCreationUnconfirmed }
        creation.isRunning = true
        creation.errorMessage = nil
        defer { creation.isRunning = false }
        do {
            if creation.phase == .ready {
                while let (name, value) = creation.dateFieldsToPrepare.first {
                    do {
                        let _: ProjectField = try await performProjectMutation(projectID: creation.projectID) {
                            try await self.gitHubService.ensureProjectDateField(projectID: creation.projectID, name: name)
                        } apply: { field in
                            if var project = projectStates[creation.projectID]?.snapshot {
                                project.fields.removeAll { $0.id == field.id }
                                project.fields.append(field)
                                projectStates[creation.projectID]?.snapshot = project
                            }
                            creation.remainingFields.append((field, value))
                            creation.dateFieldsToPrepare.removeFirst()
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        throw GitHubError.issueCreationNotStarted(error.localizedDescription,
                            retryable: shouldRetryTransientWrite(error))
                    }
                }
                if let field = creation.backlogFieldToPrepare {
                    do {
                        let _: [ProjectFieldOption] = try await performProjectMutation(projectID: creation.projectID) {
                            try await self.gitHubService.ensureProjectStatusOption(
                                fieldID: field.id, name: "Backlog", color: "GRAY"
                            )
                        } apply: { options in
                            guard let backlog = options.first(where: {
                                $0.name.caseInsensitiveCompare("Backlog") == .orderedSame
                            }) else { return }
                            creation.remainingFields.insert((field, .singleSelect(optionId: backlog.id, name: backlog.name)), at: 0)
                            creation.backlogFieldToPrepare = nil
                            if var project = projectStates[creation.projectID]?.snapshot {
                                if let index = project.fields.firstIndex(where: { $0.id == field.id }) {
                                    project.fields[index] = ProjectField(
                                        id: field.id, name: field.name, kind: field.kind,
                                        options: options, iterations: field.iterations
                                    )
                                }
                                if project.statusField?.id == field.id {
                                    project.statusField = StatusField(
                                        id: field.id, name: field.name,
                                        options: options.map {
                                            StatusOption(id: $0.id, name: $0.name, color: $0.color ?? "GRAY")
                                        }
                                    )
                                }
                                projectStates[creation.projectID]?.snapshot = project
                            }
                        }
                        guard creation.backlogFieldToPrepare == nil else { throw GitHubError.invalidResponse }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw GitHubError.issueCreationNotStarted(
                            error.localizedDescription, retryable: shouldRetryTransientWrite(error)
                        )
                    }
                }
                try await performProjectMutation(projectID: creation.projectID) {
                    do {
                        let issue = try await self.gitHubService.createIssue(
                            repository: creation.repository, projectID: creation.projectID,
                            title: creation.title, body: creation.body,
                            labels: creation.labels, assignees: creation.assignees
                        )
                        creation.createdIssue = issue
                        creation.phase = .addingToProject(issueURL: issue.url)
                    } catch {
                        switch error {
                        case GitHubError.issueCreationUnconfirmed, GitHubError.decodingError:
                            creation.phase = .unconfirmed
                        default:
                            if self.requiresReconciliation(error) { creation.phase = .unconfirmed }
                        }
                        throw error
                    }
                }
            }
            if case .addingToProject(let issueURL) = creation.phase {
                guard let issue = creation.createdIssue else { throw GitHubError.issueCreationUnconfirmed }
                let itemID: String
                if let projectItemID = issue.projectItemID {
                    itemID = projectItemID
                } else {
                    let existingID = try await gitHubService.projectItemID(
                        issueID: issue.contentID, projectID: creation.projectID
                    )
                    if let existingID {
                        itemID = existingID
                    } else {
                        do {
                            itemID = try await performProjectMutation(projectID: creation.projectID) {
                                try await self.gitHubService.addExistingItem(
                                    projectId: creation.projectID, contentId: issue.contentID
                                )
                            }
                        } catch {
                            // Membership may have appeared between the read and add request.
                            guard let confirmedID = try? await gitHubService.projectItemID(
                                issueID: issue.contentID, projectID: creation.projectID
                            ) else { throw error }
                            itemID = confirmedID
                        }
                    }
                }
                creation.createdItem = issue.projectItem(id: itemID)
                creation.phase = creation.remainingFields.isEmpty
                    ? .completed(issueURL: issueURL)
                    : .applyingFields(issueURL: issueURL, itemID: itemID)
            }
            if case .applyingFields(let issueURL, let itemID) = creation.phase {
                try await performProjectMutation(projectID: creation.projectID, itemID: itemID) {
                    while let (field, value) = creation.remainingFields.first {
                        try await self.gitHubService.updateItemField(
                            projectId: creation.projectID, itemId: itemID, fieldId: field.id,
                            value: value
                        )
                        creation.createdItem?.fieldValues[field.id] = value
                        if field.name.caseInsensitiveCompare("Status") == .orderedSame,
                           case .singleSelect(let id, let name) = value {
                            creation.createdItem?.status = name
                            creation.createdItem?.statusOptionId = id
                        }
                        creation.remainingFields.removeFirst()
                    }
                }
                creation.phase = .completed(issueURL: issueURL)
            }
            if case .completed = creation.phase, let item = creation.createdItem {
                commitCreatedItem(item, projectID: creation.projectID)
                await persistCache()
                projectStates[creation.projectID]?.needsRefresh = true
                scheduleReconciliation()
            }
        } catch {
            let context: String
            switch creation.phase {
            case .addingToProject(let url):
                context = String(localized: "The issue was created at \(url). Retry to add it to the original project. ")
            case .applyingFields(let url, _):
                context = String(localized: "The issue at \(url) was added. Retry to finish its Project fields. ")
            case .unconfirmed:
                context = GitHubError.issueCreationUnconfirmed.localizedDescription + " "
            case .ready, .completed:
                context = ""
            }
            creation.errorMessage = context + (creation.phase == .unconfirmed
                && (error as? GitHubError) == .issueCreationUnconfirmed ? "" : error.localizedDescription)
            throw error
        }
    }

    func createDraftIssue(title: String, body: String, projectID: String? = nil) async throws {
        let project = try projectID.map { try editableProject(id: $0) } ?? editableSelectedProject()
        let itemID = try await performProjectMutation(projectID: project.id) {
            try await self.gitHubService.createDraftIssue(projectId: project.id, title: title, body: body)
        }
        commitCreatedItem(ProjectItem(id: itemID, contentId: nil, contentType: .draftIssue,
                                      title: title, number: nil, url: nil, issueState: nil, prState: nil,
                                      status: nil, statusOptionId: nil, assignees: []), projectID: project.id)
        await persistCache()
        projectStates[project.id]?.needsRefresh = true
        scheduleReconciliation()
    }

    func searchItems(query: String) async throws -> [GitHubItemCandidate] {
        try await gitHubService.searchItems(query: query)
    }

    func resolveItem(url: String) async throws -> GitHubItemCandidate {
        try await gitHubService.resolveItem(url: url)
    }

    func addExistingItem(_ candidate: GitHubItemCandidate, projectID: String? = nil) async throws {
        let project = try projectID.map { try editableProject(id: $0) } ?? editableSelectedProject()
        let itemID = try await performProjectMutation(projectID: project.id) {
            try await self.gitHubService.addExistingItem(projectId: project.id, candidate: candidate)
        }
        commitCreatedItem(ProjectItem(id: itemID, contentId: candidate.id, contentType: candidate.contentType,
                                      title: candidate.title, number: candidate.number, url: candidate.url,
                                      issueState: nil, prState: nil, status: nil,
                                      statusOptionId: nil, assignees: []), projectID: project.id)
        await persistCache()
        projectStates[project.id]?.needsRefresh = true
        scheduleReconciliation()
    }

    func clearOperationError() {
        operationErrorMessage = nil
    }

    private func editableSelectedProject() throws -> Project {
        guard let selectedProjectId else { throw ProjectStoreError.noProjectSelected }
        return try editableProject(id: selectedProjectId)
    }

    private func editableProject(id: String) throws -> Project {
        guard let project = project(id: id), canEditProject(id: id) else {
            throw ProjectStoreError.readOnlyProject
        }
        return project
    }

    private func performProjectMutation<Result>(
        projectID: String,
        itemID: String? = nil,
        optimisticStatus: (String, StatusOption)? = nil,
        operation: () async throws -> Result,
        apply: (Result) -> Void = { _ in }
    ) async throws -> Result {
        if let itemID, pendingCreationState(for: itemID) != nil {
            throw ProjectStoreError.operationInProgress
        }
        guard !deletingProjectIDs.contains(projectID), projectStates[projectID] != nil else { throw ProjectStoreError.itemUnavailable }
        let key = itemID.map { ItemMutationKey(projectID: projectID, itemID: $0) }
        if let key, pendingItemMutations[key] != nil { throw ProjectStoreError.operationInProgress }
        let operationID = UUID()
        projectStates[projectID]?.mutations.insert(operationID)
        projectStates[projectID]?.mutationRevision += 1
        if let key {
            pendingItemMutations[key] = operationID
            if let (field, status) = optimisticStatus {
                pendingStatusMoves[key] = PendingStatusMove(operationID: operationID, fieldID: field, status: status)
            }
        }
        defer {
            if let key, pendingItemMutations[key] == operationID {
                pendingItemMutations[key] = nil
                if pendingStatusMoves[key]?.operationID == operationID { pendingStatusMoves[key] = nil }
            }
            if projectStates[projectID]?.mutations.remove(operationID) != nil {
                projectStates[projectID]?.mutationRevision += 1
            }
            scheduleReconciliation()
        }
        do {
            let result = try await operation()
            guard projectStates[projectID]?.mutations.contains(operationID) == true else { throw CancellationError() }
            apply(result)
            lastUpdated = Date()
            return result
        } catch {
            if projectStates[projectID]?.mutations.contains(operationID) == true,
               requiresReconciliation(error) { projectStates[projectID]?.needsRefresh = true }
            throw error
        }
    }

    private func performRelationshipMutation(
        _ contentIDs: Set<String>, operation: () async throws -> Void
    ) async throws {
        try await performContentMutation(contentIDs, operation: {
            try await operation()
            var details: [String: ProjectItemDetail] = [:]
            for id in contentIDs.sorted() {
                let detail = try await self.gitHubService.fetchItemDetail(contentID: id)
                guard detail.issueMetadata != nil else { throw GitHubError.invalidResponse }
                details[id] = detail
            }
            return details
        }) { details in
            for (id, fetched) in details {
                guard let value = fetched.issueMetadata else { continue }
                if let entry = self.itemDetailEntries[id], case .loading = entry.state {
                    self.itemDetailEntries[id] = ItemDetailEntry(sourceUpdatedAt: entry.sourceUpdatedAt, state: .loaded(fetched))
                }
                self.updateDetail(contentID: id) { detail in
                    detail.issueMetadata?.parent = value.parent
                    detail.issueMetadata?.subIssues = value.subIssues
                    detail.issueMetadata?.subIssueProgress = value.subIssueProgress
                    detail.issueMetadata?.blockedBy = value.blockedBy
                    detail.issueMetadata?.blocking = value.blocking
                }
                self.updateContent(contentID: id) { item in
                    item.parentIssue = value.parent.map {
                        ProjectPlanningReference(id: $0.id, title: $0.title, repository: $0.repository, number: $0.number)
                    }
                    var signals = item.engineeringSignals ?? EngineeringSignals()
                    signals.subIssueProgress = value.subIssueProgress
                    signals.blockedByCount = value.blockedBy.count
                    signals.blockingCount = value.blocking.count
                    item.engineeringSignals = signals
                }
            }
        }
    }

    private func updateDetail(contentID: String, sourceUpdatedAt: String? = nil,
                              transform: (inout ProjectItemDetail) -> Void) {
        // Reject an older read only when this write actually changes detail fields.
        itemDetailTasks.removeValue(forKey: contentID)?.cancel()
        itemDetailGenerations[contentID, default: 0] += 1
        guard let entry = itemDetailEntries[contentID], case .loaded(var detail) = entry.state else { return }
        transform(&detail)
        itemDetailEntries[contentID] = ItemDetailEntry(
            sourceUpdatedAt: sourceUpdatedAt ?? entry.sourceUpdatedAt, state: .loaded(detail)
        )
    }

    private func performContentMutation<Result>(
        _ contentIDs: Set<String>,
        operation: () async throws -> Result,
        apply: (Result) -> Void
    ) async throws {
        do {
            guard contentIDs.allSatisfy({ pendingContentMutations[$0] == nil }) else {
                throw ProjectStoreError.operationInProgress
            }
            let operationID = UUID()
            for id in contentIDs { pendingContentMutations[id] = operationID }
            personalWorkNeedsRefresh.formUnion(personalWork.keys)
            personalWorkNeedsRefresh.formUnion(personalWorkTasks.keys)
            personalWorkTasks.values.forEach { $0.cancel() }
            personalWorkTasks = [:]
            personalWorkReadIDs = [:]
            loadingPersonalWork = []
            contentRevision += 1
            defer {
                let ownedIDs = contentIDs.filter { pendingContentMutations[$0] == operationID }
                for id in ownedIDs { pendingContentMutations[id] = nil }
                if !ownedIDs.isEmpty {
                    contentRevision += 1
                }
                scheduleReconciliation()
                if pendingContentMutations.isEmpty {
                    let filters = personalWorkNeedsRefresh
                    personalWorkNeedsRefresh = []
                    for filter in filters { startPersonalWorkRefresh(filter) }
                }
            }
            do {
                let result = try await operation()
                guard contentIDs.allSatisfy({ pendingContentMutations[$0] == operationID }) else { throw CancellationError() }
                apply(result)
                lastUpdated = Date()
            } catch {
                if contentIDs.allSatisfy({ pendingContentMutations[$0] == operationID }),
                   requiresReconciliation(error) {
                    for id in projectStates.keys { projectStates[id]?.needsRefresh = true }
                }
                throw error
            }
        }
        await persistCache()
    }

    private func requiresReconciliation(_ error: Error) -> Bool {
        if error is CancellationError || error is URLError { return true }
        if case GitHubError.httpError(let status) = error, status >= 500 { return true }
        if case GitHubError.connectionError = error { return true }
        return false
    }

    private func shouldRetryTransientWrite(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        if case GitHubError.httpError(let status) = error { return status >= 500 }
        if case GitHubError.connectionError = error { return true }
        return false
    }

    private func invalidateContentDetails(_ contentIDs: [String]) {
        for id in contentIDs {
            itemDetailTasks.removeValue(forKey: id)?.cancel()
            itemDetailEntries[id] = nil
            itemDetailGenerations[id, default: 0] += 1
        }
    }

    private func projectsContaining(contentID: String) -> [String] {
        projectStates.values.compactMap(\.snapshot).filter { project in
            project.items.contains { $0.contentId == contentID }
        }.map(\.id).sorted()
    }

    private func updatePersonalSummary(contentID: String, updated: UpdatedItemContent) {
        for filter in personalWork.keys {
            guard var result = personalWork[filter] else { continue }
            for index in result.items.indices where result.items[index].id == contentID {
                result.items[index].title = updated.title
                result.items[index].updatedAt = updated.updatedAt
            }
            personalWork[filter] = result
        }
    }

    private func updateContent(contentID: String, transform: (inout ProjectItem) -> Void) {
        for id in projectsContaining(contentID: contentID) {
            guard var project = projectStates[id]?.snapshot else { continue }
            for index in project.items.indices where project.items[index].contentId == contentID {
                let originalTitle = project.items[index].title
                let originalUpdatedAt = project.items[index].updatedAt
                transform(&project.items[index])
                let item = project.items[index]
                if (item.title != originalTitle || item.updatedAt != originalUpdatedAt),
                   let updatedAt = item.updatedAt {
                    projectStates[id]?.confirmedContentAwaitingObservation[contentID] =
                        ConfirmedContentVersion(title: item.title, updatedAt: updatedAt)
                }
                if projectStates[id]?.createdItemFieldsAwaitingObservation[item.id] != nil {
                    projectStates[id]?.createdItemFieldsAwaitingObservation[item.id] = item.fieldValues
                }
            }
            projectStates[project.id]?.snapshot = project
        }
    }

    private func updateItem(
        projectID: String,
        itemID: String,
        transform: (inout ProjectItem) -> Void
    ) {
        guard var project = projectStates[projectID]?.snapshot,
              let itemIndex = project.items.firstIndex(where: { $0.id == itemID }) else { return }
        transform(&project.items[itemIndex])
        let item = project.items[itemIndex]
        if projectStates[projectID]?.createdItemFieldsAwaitingObservation[item.id] != nil {
            projectStates[projectID]?.createdItemFieldsAwaitingObservation[item.id] = item.fieldValues
        }
        projectStates[project.id]?.snapshot = project
    }

    private func finishItemDetailLoad(
        _ task: Task<ProjectItemDetail, Error>,
        contentID: String,
        sourceUpdatedAt: String?,
        generation: Int
    ) async {
        do {
            let detail = try await task.value
            guard itemDetailGenerations[contentID] == generation else { return }
            itemDetailTasks[contentID] = nil
            itemDetailEntries[contentID] = ItemDetailEntry(
                sourceUpdatedAt: sourceUpdatedAt,
                state: .loaded(detail)
            )
        } catch is CancellationError {
            guard itemDetailGenerations[contentID] == generation else { return }
            itemDetailTasks[contentID] = nil
            itemDetailEntries[contentID] = nil
        } catch {
            guard itemDetailGenerations[contentID] == generation else { return }
            itemDetailTasks[contentID] = nil
            itemDetailEntries[contentID] = ItemDetailEntry(
                sourceUpdatedAt: sourceUpdatedAt,
                state: .failed(error.localizedDescription)
            )
        }
    }


}
