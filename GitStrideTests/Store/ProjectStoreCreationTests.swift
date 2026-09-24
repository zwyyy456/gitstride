import Foundation
import Testing
@testable import GitStride

extension ProjectStoreTests {
    private static let issueRepositoryResponse =
        #"{"data":{"repository":{"id":"REPO1","labels":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#

    private static let createdIssueResponse =
        #"{"data":{"createIssue":{"issue":{"id":"CONTENT1","url":"https://github.com/acme/app/issues/1"}}}}"#

    private func issueCreationCount(_ inputs: [Data?]) -> Int {
        inputs.compactMap { $0 }.filter {
            String(decoding: $0, as: UTF8.self).contains("createIssue(input:")
        }.count
    }

    private static let addedIssueResponse =
        #"{"data":{"addProjectV2ItemById":{"item":{"id":"NEW_ITEM"}}}}"#

    private static let missingProjectMembershipResponse =
        #"{"data":{"node":{"projectItems":{"nodes":[]}}}}"#

    private static let confirmedProjectMembershipResponse =
        #"{"data":{"node":{"projectItems":{"nodes":[{"id":"NEW_ITEM","project":{"id":"P1"}}]}}}}"#

    @Test func missingMembershipInCreateResponseDoesNotAddTheIssueTwice() async throws {
        let runner = FixtureGitHubHTTPClient(responses: Self.mutationProjectResponses + [
            Self.issueRepositoryResponse, Self.createdIssueResponse,
            Self.confirmedProjectMembershipResponse
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let creation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                      labels: [], assignees: [])

        try await store.resumeIssueCreation(creation)

        #expect(creation.phase == .completed(issueURL: "https://github.com/acme/app/issues/1"))
        #expect(store.selectedProject?.items.contains { $0.id == "NEW_ITEM" } == true)
        let requests = await runner.recordedRequests()
        #expect(requests.filter { $0.graphQLQuery == GraphQLQueries.issueProjectItems }.count == 1)
        #expect(requests.filter { $0.graphQLQuery == GraphQLQueries.addItemToProject }.isEmpty)
    }

    @Test func membershipAppearingDuringAddIsTreatedAsCreated() async throws {
        let runner = FixtureGitHubHTTPClient(responses: Self.mutationProjectResponses + [
            Self.issueRepositoryResponse, Self.createdIssueResponse,
            Self.missingProjectMembershipResponse,
            #"{"errors":[{"message":"Content already exists in this project"}]}"#,
            Self.confirmedProjectMembershipResponse
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let creation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                      labels: [], assignees: [])

        try await store.resumeIssueCreation(creation)

        #expect(creation.phase == .completed(issueURL: "https://github.com/acme/app/issues/1"))
        #expect(store.selectedProject?.items.contains { $0.id == "NEW_ITEM" } == true)
        let requests = await runner.recordedRequests()
        #expect(requests.filter { $0.graphQLQuery == GraphQLQueries.issueProjectItems }.count == 2)
        #expect(requests.filter { $0.graphQLQuery == GraphQLQueries.addItemToProject }.count == 1)
    }

    @Test func optimisticIssueCreationUsesTheProjectItemReturnedByCreateIssue() async throws {
        let createdWithProject = #"{"data":{"createIssue":{"issue":{"id":"CONTENT1","url":"https://github.com/acme/app/issues/1","projectItems":{"nodes":[{"id":"NEW_ITEM","project":{"id":"P1"}}]}}}}}"#
        let runner = SuspendingGitHubHTTPClient(steps: Self.mutationProjectResponses.map { .response($0) } + [
            .response(Self.issueRepositoryResponse), .suspended("create", createdWithProject)
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let creation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "Draft body",
                                                      labels: [], assignees: [])

        try store.beginIssueCreation(creation)
        #expect(store.pendingCreationList.map(\.title) == ["New"])
        #expect(store.selectedProject?.items.contains { $0.id.hasPrefix("pending:") && $0.title == "New" } == true)
        await runner.waitUntilSuspended("create")
        await runner.release("create")
        for _ in 0..<100 {
            if store.pendingCreationList.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.pendingCreationList.isEmpty)
        #expect(store.selectedProject?.items.contains { $0.id.hasPrefix("pending:") } == false)
        #expect(store.selectedProject?.items.contains { $0.id == "NEW_ITEM" } == true)
        let calls = await runner.recordedRequests()
        #expect(calls.filter { $0.graphQLQuery == GraphQLQueries.addItemToProject }.isEmpty)
        let create = try #require(calls.first { $0.graphQLQuery == GraphQLQueries.createIssue })
        let data = try #require(create.httpBody)
        let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let variables = try #require(request["variables"] as? [String: Any])
        #expect(variables["projectV2Ids"] as? [String] == ["P1"])
    }

    @Test(arguments: [true, false])
    func linkedRepositoryIsDefaultEvenWithoutMatchingItems(hasItems: Bool) async throws {
        var responses = Self.mutationProjectResponses
        responses[3] = responses[3].replacingOccurrences(
            of: #""repositories":{"nodes":[]"#,
            with: #""repositories":{"nodes":[{"nameWithOwner":"acme/linked"}]"#
        )
        if !hasItems { responses[4] = Self.emptyItemsResponse }
        let (store, cleanup) = makeStore(runner: FixtureGitHubHTTPClient(responses: responses))
        defer { cleanup() }
        await store.loadProjects()
        #expect(store.defaultIssueRepository == "acme/linked")
        #expect(store.repositorySuggestions.first == "acme/linked")
    }

    @Test func multipleLinkedRepositoriesRequireAChoice() async throws {
        var responses = Self.mutationProjectResponses
        responses[3] = responses[3].replacingOccurrences(
            of: #""repositories":{"nodes":[]"#,
            with: #""repositories":{"nodes":[{"nameWithOwner":"acme/one"},{"nameWithOwner":"acme/two"}]"#
        )
        let (store, cleanup) = makeStore(runner: FixtureGitHubHTTPClient(responses: responses))
        defer { cleanup() }
        await store.loadProjects()
        #expect(store.defaultIssueRepository.isEmpty)
        #expect(store.repositorySuggestions == ["acme/one", "acme/two", "acme/app"])
    }

    @Test func interruptedLabelCreationAllowsEditingAndRetryWithoutDuplicatingTheLabel() async throws {
        let repositoryWithLabel = Self.issueRepositoryResponse.replacingOccurrences(
            of: #""nodes":[]"#, with: #""nodes":[{"id":"FEATURE","name":"feature"}]"#
        )
        let runner = SuspendingGitHubHTTPClient(steps: Self.mutationProjectResponses.map { .response($0) } + [
            .response(Self.issueRepositoryResponse), .failure(.timedOut),
            .response(repositoryWithLabel), .response(Self.createdIssueResponse),
            .response(Self.missingProjectMembershipResponse),
            .response(Self.addedIssueResponse),
            .response(Self.mutationFieldsResponse), .response(Self.mutationItemsResponse)
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let operation = try store.prepareIssueCreation(repository: "acme/app", title: "Original", body: "",
                                                       labels: ["feature"], assignees: [])
        do {
            try await store.resumeIssueCreation(operation)
            Issue.record("Expected label creation to be interrupted")
        } catch {
            guard case GitHubError.issueCreationNotStarted = error else { throw error }
        }
        #expect(operation.phase == .ready)
        #expect(operation.canResume)
        #expect(!operation.isRunning)
        #expect(issueCreationCount(await runner.recordedBodies()) == 0)

        // A ready failure releases the form's operation so the edited draft can be submitted.
        let edited = try store.prepareIssueCreation(repository: "acme/app", title: "Edited", body: "",
                                                    labels: ["feature"], assignees: [])
        try await store.resumeIssueCreation(edited)
        #expect(edited.phase == .completed(issueURL: "https://github.com/acme/app/issues/1"))
        #expect(issueCreationCount(await runner.recordedBodies()) == 1)
        let calls = await runner.recordedRequests()
        #expect(calls.filter { $0.graphQLQuery == GraphQLQueries.createLabel }.count == 1)
    }

    @Test func issueValidationFailureKeepsTheFormEditable() async throws {
        let runner = FixtureGitHubHTTPClient(responses: Self.mutationProjectResponses + [
            Self.issueRepositoryResponse, #"{"errors":[{"message":"Title can't be blank"}]}"#
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let operation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                       labels: [], assignees: [])
        do {
            try await store.resumeIssueCreation(operation)
            Issue.record("Expected an explicit validation failure")
        } catch {
            guard case GitHubError.graphQLError = error else { throw error }
        }
        #expect(operation.phase == .ready)
        #expect(operation.canResume)
        #expect(operation.errorMessage?.contains("Title can't be blank") == true)
    }

    @Test func creationRejectsRepositoryFromAnotherOwner() async throws {
        let runner = FixtureGitHubHTTPClient(responses: [])
        let store = ProjectStore(gitHubService: GitHubService(http: runner))
        let owner = ProjectOwner(id: "OWNER", login: "me", name: nil, kind: .user)
        do {
            try await store.createProject(
                owner: owner, title: "Project",
                repository: ProjectRepository(id: "R", nameWithOwner: "other/repo", ownerID: "OTHER")
            )
            Issue.record("Expected a repository ownership error")
        } catch ProjectStoreError.repositoryOwnerMismatch {}
        #expect(await runner.recordedRequests().isEmpty)
        #expect(!store.isCreatingProject)
    }

    @Test func createdProjectSurvivesFollowupReadFailure() async throws {
        let runner = FixtureGitHubHTTPClient(responses: [
            Self.createdProjectResponse,
            #"{"errors":[{"message":"List unavailable"}]}"#,
            #"{"errors":[{"message":"Details unavailable"}]}"#
        ])
        let suite = "CreateProjectTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProjectStore(gitHubService: GitHubService(http: runner), defaults: defaults)
        let owner = ProjectOwner(id: "OWNER", login: "me", name: nil, kind: .user)
        try await store.createProject(owner: owner, title: "New project")
        #expect(store.selectedProjectId == "NEW")
        #expect(store.selectedOwnerId == "OWNER")
        #expect(store.projects.map(\.id) == ["NEW"])
        #expect(!store.isCreatingProject)
        #expect(!store.isLoading)
        #expect(store.operationErrorMessage != nil)
        #expect(await runner.recordedRequests().count == 3)
    }

    @Test func createdIssueIsCommittedBeforeStaleReconciliation() async throws {
        var initial = Self.mutationProjectResponses
        initial[4] = Self.emptyItemsResponse
        let runner = SuspendingGitHubHTTPClient(steps: initial.map { .response($0) } + [
            .response(Self.issueRepositoryResponse), .response(Self.createdIssueResponse),
            .response(Self.missingProjectMembershipResponse),
            .response(Self.addedIssueResponse), .response(Self.graphQLSuccessResponse),
            .suspended("reconcile", Self.mutationFieldsResponse), .response(Self.emptyItemsResponse)
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let operation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                       labels: [], assignees: [], status: "Todo")

        try await store.resumeIssueCreation(operation)
        await runner.waitUntilSuspended("reconcile")

        #expect(operation.phase == .completed(issueURL: "https://github.com/acme/app/issues/1"))
        #expect(operation.errorMessage == nil)
        #expect(store.selectedProject?.items.first?.id == "NEW_ITEM")
        #expect(store.selectedProject?.items.first?.status == "Todo")

        let release = Task { await runner.release("reconcile") }
        await store.loadProjectDetails(id: "P1")
        await release.value
        #expect(store.selectedProject?.items.first?.id == "NEW_ITEM")
        #expect(store.selectedProject?.items.first?.status == "Todo")
    }

    @Test func createdIssueFinishesInOriginalProjectAndRetryDoesNotRecreateIt() async throws {
        let fields = Self.mutationFieldsResponse
        let items = Self.mutationItemsResponse
        let runner = SuspendingGitHubHTTPClient(steps: Self.mutationProjectResponses.map { .response($0) } + [
            .response(Self.issueRepositoryResponse), .suspended("create", Self.createdIssueResponse),
            .response(Self.missingProjectMembershipResponse),
            .response(Self.addedIssueResponse),
            .response(Self.graphQLFailureResponse),
            .response(Self.graphQLSuccessResponse),
            .response(fields), .response(items)
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let operation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                       labels: [], assignees: [], status: "Review")
        let creation = Task { try await store.resumeIssueCreation(operation) }
        await runner.waitUntilSuspended("create")
        do {
            try await store.resumeIssueCreation(operation)
            Issue.record("Expected a concurrent submission to be rejected")
        } catch {
            guard case ProjectStoreError.operationInProgress = error else { throw error }
        }
        store.selectedProjectId = "P2"
        await runner.release("create")
        do {
            try await creation.value
            Issue.record("Expected field failure with a resumable issue")
        } catch {
            #expect(operation.projectID == "P1")
            #expect(operation.phase == .applyingFields(issueURL: "https://github.com/acme/app/issues/1", itemID: "NEW_ITEM"))
            try await store.resumeIssueCreation(operation)
        }
        #expect(operation.phase == .completed(issueURL: "https://github.com/acme/app/issues/1"))
        let calls = await runner.recordedRequests()
        #expect(issueCreationCount(await runner.recordedBodies()) == 1)
        #expect(calls.filter { $0.hasVariable("optionId", "REVIEW") }.count == 2)
        #expect(calls.filter { $0.hasVariable("optionId", "REVIEW") }.allSatisfy { $0.hasVariable("projectId", "P1") && $0.hasVariable("itemId", "NEW_ITEM") })
        #expect(store.selectedProjectId == "P2")
    }

    @Test func createdIssueResumesAddingToItsOriginalProject() async throws {
        let fields = Self.mutationFieldsResponse
        let items = Self.mutationItemsResponse
        let runner = FixtureGitHubHTTPClient(responses: Self.mutationProjectResponses + [
            Self.issueRepositoryResponse, Self.createdIssueResponse,
            Self.missingProjectMembershipResponse, Self.graphQLFailureResponse,
            Self.missingProjectMembershipResponse,
            Self.missingProjectMembershipResponse,
            Self.addedIssueResponse,
            Self.graphQLSuccessResponse, fields, items
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let operation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                       labels: [], assignees: [], status: "Review")
        do {
            try await store.resumeIssueCreation(operation)
            Issue.record("Expected membership failure")
        } catch {
            #expect(operation.phase == .addingToProject(issueURL: "https://github.com/acme/app/issues/1"))
            #expect(operation.canResume)
        }
        store.selectedProjectId = "P2"
        try await store.resumeIssueCreation(operation)
        #expect(operation.phase == .completed(issueURL: "https://github.com/acme/app/issues/1"))
        let calls = await runner.recordedRequests()
        #expect(issueCreationCount(await runner.recordedBodies()) == 1)
        let additions = calls.filter { $0.hasVariable("contentId", "CONTENT1") }
        #expect(additions.count == 2)
        #expect(additions.allSatisfy { $0.hasVariable("projectId", "P1") })
        #expect(calls.filter { $0.hasVariable("optionId", "REVIEW") }.count == 1)
        #expect(store.selectedProjectId == "P2")
    }

    @Test func creationRetriesOnlyUnfinishedFields() async throws {
        let priority = #"{"__typename":"ProjectV2SingleSelectField","id":"PRIORITY","name":"Priority","dataType":"SINGLE_SELECT","options":[{"id":"HIGH","name":"High","color":"RED"}]},"#
        let fields = Self.mutationFieldsResponse.replacingOccurrences(
            of: #""fields":{"nodes":["#, with: #""fields":{"nodes":[\#(priority)"#
        )
        let items = Self.mutationItemsResponse
        var initial = Self.mutationProjectResponses
        initial[3] = fields
        let runner = FixtureGitHubHTTPClient(responses: initial + [
            Self.issueRepositoryResponse, Self.createdIssueResponse,
            Self.missingProjectMembershipResponse, Self.addedIssueResponse,
            Self.graphQLSuccessResponse, Self.graphQLFailureResponse,
            Self.graphQLSuccessResponse,
            fields, items
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let operation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                       labels: [], assignees: [], status: "Review", priority: "High")
        do {
            try await store.resumeIssueCreation(operation)
            Issue.record("Expected the second field to fail")
        } catch {
            #expect(operation.phase == .applyingFields(issueURL: "https://github.com/acme/app/issues/1", itemID: "NEW_ITEM"))
        }
        try await store.resumeIssueCreation(operation)
        #expect(operation.phase == .completed(issueURL: "https://github.com/acme/app/issues/1"))
        let calls = await runner.recordedRequests()
        #expect(issueCreationCount(await runner.recordedBodies()) == 1)
        #expect(calls.filter { $0.hasVariable("contentId", "CONTENT1") }.count == 1)
        #expect(calls.filter { $0.hasVariable("optionId", "REVIEW") }.count == 1)
        #expect(calls.filter { $0.hasVariable("optionId", "HIGH") }.count == 2)
    }

    @Test(arguments: [
        #"{"data":{"createIssue":{"issue":{"id":"CONTENT1","url":""}}}}"#,
        #"{"data":{"createIssue":{"issue":{}}}}"#
    ])
    func creationWithoutAConfirmedIdentityCannotBeResubmitted(response: String) async throws {
        let runner = FixtureGitHubHTTPClient(responses: Self.mutationProjectResponses + [
            Self.issueRepositoryResponse, response
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let operation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                       labels: [], assignees: [])
        for _ in 0..<2 {
            do {
                try await store.resumeIssueCreation(operation)
                Issue.record("Expected an unconfirmed creation result")
            } catch {
                switch error {
                case GitHubError.issueCreationUnconfirmed, GitHubError.decodingError: break
                default: throw error
                }
            }
        }
        #expect(operation.phase == .unconfirmed)
        #expect(!operation.canResume)
        #expect(issueCreationCount(await runner.recordedBodies()) == 1)
    }

    @Test(arguments: [true, false])
    func interruptedCreationKeepsItsOutcomeUnconfirmed(_ cancelled: Bool) async throws {
        let runner = SuspendingGitHubHTTPClient(steps: Self.mutationProjectResponses.map { .response($0) } + [
            .response(Self.issueRepositoryResponse),
            cancelled ? .cancelled : .failure(.timedOut),
            .suspended("reconcile", Self.mutationFieldsResponse), .response(Self.mutationItemsResponse)
        ])
        let (store, cleanup) = makeStore(runner: runner)
        defer { cleanup() }
        await store.loadProjects()
        let operation = try store.prepareIssueCreation(repository: "acme/app", title: "New", body: "",
                                                       labels: [], assignees: [])
        do {
            try await store.resumeIssueCreation(operation)
            Issue.record("Expected an interrupted creation")
        } catch {
            #expect(operation.phase == .unconfirmed)
            #expect(!operation.canResume)
            #expect(operation.errorMessage?.contains(GitHubError.issueCreationUnconfirmed.localizedDescription) == true)
        }
        await runner.waitUntilSuspended("reconcile")
        let release = Task { await runner.release("reconcile") }
        await store.loadProjectDetails(id: "P1")
        await release.value
        do {
            try await store.resumeIssueCreation(operation)
            Issue.record("Expected resubmission to be blocked")
        } catch {
            #expect((error as? GitHubError) == .issueCreationUnconfirmed)
        }
        #expect(issueCreationCount(await runner.recordedBodies()) == 1)
    }
}
