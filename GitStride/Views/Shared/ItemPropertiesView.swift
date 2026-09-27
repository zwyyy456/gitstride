import SwiftUI

struct ItemPropertiesView: View {
    @Bindable var store: ProjectStore
    let reference: ItemInspectorReference

    @State private var isWorking = false

    private var project: Project? { store.project(id: reference.projectID) }
    private var item: ProjectItem? { store.item(for: reference) }
    private var canEdit: Bool { store.canEditProject(id: reference.projectID) }

    var body: some View {
        Form {
            if let project, let item {
                fieldSection(project: project, item: item)
                Section(
                    item.contentType == .issue
                        ? String(localized: "Issue Details") : String(localized: "Item Properties")
                ) {
                    ItemAssigneesSection(
                        store: store, item: item,
                        projectID: reference.projectID)
                    if item.contentType == .issue {
                        ItemLabelsSection(
                            store: store, item: item,
                            projectID: reference.projectID)
                        ItemMilestoneSection(store: store, item: item)
                    }
                }
                if item.contentType == .issue {
                    ItemRelationshipsSection(store: store, item: item)
                }
                signalsSection(item)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .controlSize(.small)
        #endif
    }

    private func fieldSection(project: Project, item: ProjectItem) -> some View {
        Section(String(localized: "Project Fields")) {
            ForEach(project.fields.filter(\.isEditable)) { field in
                ProjectFieldEditor(
                    field: field,
                    value: item.fieldValues[field.id],
                    isEditable: canEdit && isWorking == false
                ) { value in
                    isWorking = true
                    defer { isWorking = false }
                    try await store.updateField(on: item, in: reference.projectID, field: field, value: value)
                }
            }
        }
    }

    @ViewBuilder
    private func signalsSection(_ item: ProjectItem) -> some View {
        if (item.contentType == .pullRequest && item.engineeringSignals != nil)
            || item.linkedPR != nil
        {
            Section(String(localized: "Engineering")) {
                if item.contentType == .pullRequest {
                    EngineeringSignalsView(item: item, limit: 5)
                }

                if let linkedPR = item.linkedPR, let url = URL(string: linkedPR.url) {
                    Link(destination: url) {
                        Label("PR #\(linkedPR.number): \(linkedPR.title)", systemImage: "arrow.triangle.pull")
                            .lineLimit(2)
                    }
                }
            }
        }
    }

}
