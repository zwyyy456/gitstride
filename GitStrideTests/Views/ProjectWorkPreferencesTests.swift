import Foundation
import Testing
@testable import GitStride

struct ProjectWorkPreferencesTests {
    @Test func roadmapDefaultsPreserveExplicitNoneAndDoNotReplaceRemovedFields() throws {
        let suite = "GitStrideTests.RoadmapMapping.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = ProjectDisplayPreferences(projectID: "P1", viewID: nil)
        let saved = ProjectDisplayPreferences(projectID: "P1", viewID: "V1")
        let fields = [
            ProjectField(id: "start", name: "Start date", kind: .date, options: [], iterations: []),
            ProjectField(id: "sprint", name: "Sprint", kind: .iteration, options: [], iterations: [])
        ]
        func resolved(_ preferences: ProjectDisplayPreferences, fields: [ProjectField]) -> String {
            ProjectDisplayPreferences.roadmapFieldID(
                defaults.string(forKey: preferences.key(for: .roadmapStartField)),
                defaultName: "Start date", fields: fields)
        }
        #expect(resolved(project, fields: []) == "")
        #expect(resolved(project, fields: fields) == "start")
        defaults.set("", forKey: project.key(for: .roadmapStartField))
        project.copy(to: saved, defaults: defaults)
        #expect(resolved(project, fields: fields) == "")
        #expect(resolved(saved, fields: fields) == "")
        defaults.set("sprint", forKey: project.key(for: .roadmapStartField))
        #expect(resolved(project, fields: fields) == "sprint")
        #expect(resolved(project, fields: [fields[0]]) == "")
        #expect(resolved(saved, fields: fields) == "")
    }

    @Test func savedViewsKeepTheirOwnLayoutFilterAndDisplayPreferences() throws {
        let suite = "GitStrideTests.WorkPreferences.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ProjectWorkPreferences(defaults: defaults)
        let original = ProjectDisplayPreferences(projectID: "P1", viewID: nil)
        defaults.set(false, forKey: original.key(for: .sortAscending))
        try preferences.setLayout(.table, projectID: "P1", viewID: nil)
        let view = SavedProjectWorkView(projectID: "P1", name: "Delivery", filter: ProjectWorkFilter(), layout: .table)
        try preferences.save(view, copyingDisplayFrom: original.id)
        try preferences.setLayout(.roadmap, projectID: "P1", viewID: view.id)
        try preferences.setHiddenStatuses(["DONE"], viewID: view.id)
        var filter = ProjectWorkFilter()
        filter.milestoneID = "M1"
        try preferences.setFilter(filter, viewID: view.id)

        let loaded = ProjectWorkPreferences(defaults: defaults)
        let restored = try #require(loaded.views.first)
        #expect(restored.id == view.id)
        #expect(restored.layout == .roadmap)
        #expect(restored.filter == filter)
        #expect(restored.hiddenStatusIDs == ["DONE"])
        #expect(loaded.layout(projectID: "P1") == .table)
        #expect(loaded.layout(projectID: "P2") == .board)
        let savedDisplay = ProjectDisplayPreferences(projectID: "P1", viewID: view.id)
        #expect(defaults.object(forKey: savedDisplay.key(for: .sortAscending)) as? Bool == false)
        try loaded.delete(viewID: view.id)
        #expect(loaded.views.isEmpty)
        #expect(defaults.object(forKey: savedDisplay.key(for: .sortAscending)) == nil)
        #expect(defaults.object(forKey: original.key(for: .sortAscending)) as? Bool == false)
    }
}
