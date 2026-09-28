import SwiftUI

struct MobileDisplayFields: View {
    let project: Project
    @AppStorage private var fields: String

    init(project: Project, preferenceID: String) {
        self.project = project
        _fields = AppStorage(
            wrappedValue: "assignees",
            ProjectDisplayPreferences(id: preferenceID).key(for: .cardFields))
    }

    var body: some View {
        Section("Show Fields") {
            Toggle("Assignees", isOn: binding("assignees"))
            Toggle("Labels", isOn: binding("labels"))
            Toggle("Milestone", isOn: binding("milestone"))
            Toggle("Engineering", isOn: binding("signals"))
            ForEach(project.fields) { field in
                Toggle(field.name, isOn: binding("field:" + field.id))
            }
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { fields.split(separator: ",").contains(Substring(key)) },
            set: { enabled in
                var values = Set(fields.split(separator: ",").map(String.init))
                if enabled { values.insert(key) } else { values.remove(key) }
                fields = values.sorted().joined(separator: ",")
            })
    }
}

struct MobileConfiguredItemRow: View {
    let item: ProjectItem
    let fields: [ProjectField]
    @AppStorage private var visible: String

    init(item: ProjectItem, fields: [ProjectField], preferenceID: String) {
        self.item = item
        self.fields = fields
        _visible = AppStorage(
            wrappedValue: "assignees",
            ProjectDisplayPreferences(id: preferenceID).key(for: .cardFields))
    }

    var body: some View {
        let keys = Set(visible.split(separator: ",").map(String.init))
        VStack(alignment: .leading, spacing: 6) {
            MobileItemRow(item: item)
            if !item.isWorkComplete && item.signals.blockedByCount > 0 {
                Label("Blocked by \(item.signals.blockedByCount)", systemImage: "hand.raised")
                    .foregroundStyle(.orange)
            }
            if keys.contains("assignees"), !item.assignees.isEmpty {
                Text(item.assignees.map { "@\($0.login)" }.joined(separator: ", "))
            }
            if keys.contains("labels"), !item.labels.isEmpty {
                Text(item.labels.map(\.name).joined(separator: ", "))
            }
            if keys.contains("milestone"), let milestone = item.milestone { Text(milestone.title) }
            if keys.contains("signals") { EngineeringSignalsView(item: item, limit: 3) }
            ForEach(fields.filter { keys.contains("field:" + $0.id) }) { field in
                if let value = item.fieldValues[field.id] { Text("\(field.name): \(label(value))") }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func label(_ value: ProjectFieldValue) -> String {
        switch value {
        case .singleSelect(_, let name), .iteration(_, let name), .text(let name): name
        case .date(let raw): RoadmapCalendar.date(raw).map(RoadmapCalendar.label) ?? raw
        case .number(let number): number.formatted()
        }
    }
}
