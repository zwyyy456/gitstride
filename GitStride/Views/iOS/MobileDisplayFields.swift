import SwiftUI

struct MobileDisplayFields: View {
    let project: Project
    @AppStorage private var fields: String

    init(project: Project, preferenceID: String) {
        self.project = project
        _fields = AppStorage(
            wrappedValue: ProjectDisplayPreferences.defaultCardFields,
            ProjectDisplayPreferences(id: preferenceID).key(for: .cardFields))
    }

    var body: some View {
        Section("Show Fields") {
            Toggle("Assignees", isOn: binding("assignees"))
            Toggle("Labels", isOn: binding("labels"))
            Toggle("Milestone", isOn: binding("milestone"))
            Toggle("Engineering", isOn: binding("signals"))
            ForEach(project.fields) { field in
                Toggle(field.name, isOn: binding(ProjectDisplayPreferences.cardFieldID(field)))
            }
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { ProjectDisplayPreferences.cardFields(fields).contains(key) },
            set: { enabled in
                ProjectDisplayPreferences.setCardField(key, visible: enabled, in: &fields)
            })
    }
}

struct MobileConfiguredItemRow: View {
    let item: ProjectItem
    let statusOption: StatusOption?
    let showsStatus: Bool
    let fields: [ProjectField]
    @AppStorage private var visible: String

    init(item: ProjectItem, fields: [ProjectField], preferenceID: String, showsStatus: Bool = true, statusOption: StatusOption? = nil) {
        self.statusOption = statusOption
        self.showsStatus = showsStatus
        self.item = item
        self.fields = fields
        _visible = AppStorage(
            wrappedValue: ProjectDisplayPreferences.defaultCardFields,
            ProjectDisplayPreferences(id: preferenceID).key(for: .cardFields))
    }

    var body: some View {
        let keys = ProjectDisplayPreferences.cardFields(visible)
        MobileItemRow(item: item, showsStatus: showsStatus, statusOption: statusOption) {
            if !item.isWorkComplete && item.signals.blockedByCount > 0 {
                Label("Blocked by \(item.signals.blockedByCount)", systemImage: "hand.raised")
                    .foregroundStyle(.orange)
            }
            if keys.contains("assignees"), !item.assignees.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(item.assignees.prefix(2))) { assignee in assigneeLabel(assignee) }
                        if item.assignees.count > 2 { Text("+\(item.assignees.count - 2)").foregroundStyle(.secondary) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(item.assignees.prefix(2))) { assignee in assigneeLabel(assignee) }
                        if item.assignees.count > 2 { Text("+\(item.assignees.count - 2)").foregroundStyle(.secondary) }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.assignees.map { "@\($0.login)" }.joined(separator: ", "))
            }
            if keys.contains("labels"), !item.labels.isEmpty {
                Text(item.labels.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary)
            }
            if keys.contains("milestone"), let milestone = item.milestone { Text(milestone.title).foregroundStyle(.secondary) }
            if keys.contains("signals") { EngineeringSignalsView(item: item, limit: 3) }
            ForEach(fields.filter { keys.contains(ProjectDisplayPreferences.cardFieldID($0)) }) { field in
                if let value = item.fieldValues[field.id] { Text("\(field.name): \(label(value))").foregroundStyle(.secondary) }
            }
        }
        .font(.caption).foregroundStyle(.primary)
    }

    private func assigneeLabel(_ assignee: Assignee) -> some View {
        HStack(spacing: 4) {
            AsyncImage(url: URL(string: assignee.avatarUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: { Image(systemName: "person.crop.circle.fill").foregroundStyle(.secondary) }
            .frame(width: 18, height: 18).clipShape(Circle()).accessibilityHidden(true)
            Text("@\(assignee.login)").foregroundStyle(.secondary)
        }
    }

    private func label(_ value: ProjectFieldValue) -> String {
        switch value {
        case .singleSelect(_, let name), .iteration(_, let name), .text(let name): name
        case .date(let raw): RoadmapCalendar.date(raw).map(RoadmapCalendar.label) ?? raw
        case .number(let number): number.formatted()
        }
    }
}
