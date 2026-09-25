import Foundation
import Testing
@testable import GitStride

struct ProjectRoadmapTests {
    private let fields = [
        ProjectField(id: "start", name: "Start", kind: .date, options: [], iterations: []),
        ProjectField(id: "end", name: "End", kind: .date, options: [], iterations: []),
        ProjectField(id: "sprint", name: "Sprint", kind: .iteration, options: [], iterations: [
            ProjectIteration(id: "i1", title: "Past iteration", startDate: "2024-03-09", duration: 3)
        ])
    ]

    @Test func calendarDatesAndIterationDurationsDoNotShiftAcrossDST() throws {
        let schedule = RoadmapSchedule.make(values: ["sprint": .iteration(id: "i1", title: "Past iteration")],
                                            fields: fields, startFieldID: "sprint", endFieldID: "sprint")
        #expect(schedule.start == RoadmapCalendar.date("2024-03-09"))
        #expect(schedule.end == RoadmapCalendar.date("2024-03-11"))
        #expect(!schedule.isInvalid)
        let start = try #require(schedule.start)
        let end = try #require(schedule.end)
        #expect(RoadmapCalendar.days(from: start, to: end) == 2)
        #expect(RoadmapCalendar.date("2024-02-29") != nil)
        #expect(RoadmapCalendar.date("2025-02-29") == nil)
        #expect(RoadmapCalendar.date("2024-13-01") == nil)
    }

    @Test func missingEndpointsStayUnscheduledOrSingleEndedAndInvalidDatesAreVisible() {
        func schedule(_ values: [String: ProjectFieldValue]) -> RoadmapSchedule {
            .make(values: values, fields: fields, startFieldID: "start", endFieldID: "end")
        }
        #expect(schedule([:]).dates.isEmpty)
        #expect(!schedule([:]).isInvalid)
        let partial = schedule(["end": .date("2026-09-25")])
        #expect(partial.start == nil)
        #expect(partial.end == RoadmapCalendar.date("2026-09-25"))
        #expect(!partial.isInvalid)
        #expect(schedule(["start": .date("2026-09-26"), "end": .date("2026-09-25")]).isInvalid)
        #expect(schedule(["start": .date("invalid")]).isInvalid)
        let missingIteration = RoadmapSchedule.make(values: ["sprint": .iteration(id: "missing", title: "Gone")],
            fields: fields, startFieldID: "sprint", endFieldID: "sprint")
        #expect(missingIteration.isInvalid)
    }

    @Test func movingAndResizingDatesPreservesDurationAndRejectsReversedRanges() throws {
        let values: [String: ProjectFieldValue] = ["start": .date("2024-02-28"), "end": .date("2024-03-02")]
        let moved = try RoadmapEdit.make(values: values, fields: fields,
            startFieldID: "start", endFieldID: "end", kind: .move, days: 2)
        #expect(moved.changes.map(\.fieldID) == ["end", "start"])
        #expect(moved.schedule.start == RoadmapCalendar.date("2024-03-01"))
        #expect(moved.schedule.end == RoadmapCalendar.date("2024-03-04"))
        let earlier = try RoadmapEdit.make(values: values, fields: fields,
            startFieldID: "start", endFieldID: "end", kind: .move, days: -1)
        #expect(earlier.changes.map(\.fieldID) == ["start", "end"])
        let resized = try RoadmapEdit.make(values: values, fields: fields,
            startFieldID: "start", endFieldID: "end", kind: .end, days: 1)
        #expect(resized.changes.count == 1)
        #expect(resized.schedule.start == RoadmapCalendar.date("2024-02-28"))
        #expect(throws: RoadmapEditError.self) {
            try RoadmapEdit.make(values: values, fields: fields,
                startFieldID: "start", endFieldID: "end", kind: .start, days: 4)
        }
    }

    @Test func iterationMovesSnapAcrossGapsAndWriteASharedFieldOnlyOnce() throws {
        let field = ProjectField(id: "sprint", name: "Sprint", kind: .iteration, options: [], iterations: [
            ProjectIteration(id: "old", title: "Previous", startDate: "2024-03-01", duration: 7),
            ProjectIteration(id: "new", title: "Next", startDate: "2024-03-11", duration: 14)
        ])
        let values: [String: ProjectFieldValue] = ["sprint": .iteration(id: "old", title: "Previous")]
        let edit = try RoadmapEdit.make(values: values, fields: [field],
            startFieldID: field.id, endFieldID: field.id, kind: .move, days: 6)
        #expect(edit.changes == [.init(fieldID: field.id, value: .iteration(id: "new", title: "Next"))])
        #expect(edit.schedule.start == RoadmapCalendar.date("2024-03-11"))
        #expect(edit.schedule.end == RoadmapCalendar.date("2024-03-24"))
        let noChange = try RoadmapEdit.make(values: values, fields: [field],
            startFieldID: field.id, endFieldID: field.id, kind: .move, days: 1)
        #expect(noChange.changes.isEmpty)
    }

    @Test func legacyProjectAndSavedViewLayoutsSurviveRoadmapSelection() throws {
        let suite = "GitStrideTests.Roadmap.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(Set(["P1", "P2"])), forKey: "projectTableLayouts")
        let legacyView: [String: Any] = [
            "id": "V1", "projectID": "P1", "name": "Release", "usesTable": true,
            "filter": ["assignedToMe": false, "statusIDs": [], "completion": "All"],
            "hiddenStatusIDs": ["done"]
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: [legacyView]), forKey: "savedProjectWorkViews")
        let preferences = ProjectWorkPreferences(defaults: defaults)
        #expect(preferences.layout(projectID: "P1") == .table)
        #expect(preferences.views.first?.layout == .table)
        try preferences.setLayout(.roadmap, projectID: "P1", viewID: nil)
        try preferences.setLayout(.roadmap, projectID: "P1", viewID: "V1")
        let loaded = ProjectWorkPreferences(defaults: defaults)
        #expect(loaded.layout(projectID: "P1") == .roadmap)
        #expect(loaded.layout(projectID: "P2") == .table)
        #expect(loaded.layout(projectID: "P3") == .board)
        #expect(loaded.views.first?.layout == .roadmap)
        #expect(loaded.views.first?.hiddenStatusIDs == ["done"])
        #expect(defaults.object(forKey: "projectTableLayouts") == nil)
    }
}
