import Foundation
import Testing
@testable import GitStride

struct NewProjectItemDraftTests {
    @Test @MainActor func bothPlatformsRequireAValidStatusAndShareItsDefault() {
        var project = ProjectStoreTests.kanbanProject()
        var draft = NewProjectItemDraft(repository: "  acme/app  ", title: "New")
        #expect(!draft.canSubmit(in: project))
        draft.reconcileStatus(in: project)
        #expect(draft.status == "Todo")
        #expect(draft.canSubmit(in: project))
        draft.repository = "  "
        #expect(!draft.canSubmit(in: project))
        draft.itemType = .draft
        #expect(draft.canSubmit(in: project))
        draft.title = " \n "
        #expect(!draft.canSubmit(in: project))
        project.statusField = StatusField(id: "STATUS", name: "Status", options: [])
        #expect(NewProjectItemDraft.statusOptions(in: project) == ["Backlog"])
        project.statusField = nil
        #expect(NewProjectItemDraft.statusOptions(in: project).isEmpty)
    }

    @Test func quickEntryResolvesProjectChoicesBeforeReturningToTheForm() {
        var draft = NewProjectItemDraft()
        draft.usesQuickEntry = true
        draft.quickEntry = ">Repair login repo:app status:todo priority:high @me #bug"
        let error = draft.reviewQuickEntry(repositories: ["acme/app"], statuses: ["Todo"], priorities: ["High"])
        #expect(error == nil)
        #expect(!draft.usesQuickEntry)
        #expect(draft.title == "Repair login")
        #expect(draft.repository == "acme/app")
        #expect(draft.status == "Todo")
        #expect(draft.priority == "High")
        #expect(draft.assigneeLogins(currentUser: "octocat") == ["octocat"])
        #expect(draft.labelNames == ["bug"])
    }

    @Test func unavailableChoicesStayInQuickEntryWithoutGuessingAnAmbiguousRepository() {
        var draft = NewProjectItemDraft()
        draft.usesQuickEntry = true
        draft.quickEntry = "Repair login repo:app status:Missing priority:Unknown"
        let error = draft.reviewQuickEntry(repositories: ["acme/app", "other/app"], statuses: ["Todo"], priorities: ["High"])
        let choices = [
            String(localized: "status \("Missing")"),
            String(localized: "priority \("Unknown")")
        ].joined(separator: ", ")
        #expect(error == String(localized: "Unavailable project option: \(choices)."))
        #expect(draft.usesQuickEntry)
        #expect(draft.repository == "app")
        #expect(draft.status.isEmpty)
        #expect(draft.priority.isEmpty)
    }
}
