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
        .controlSize(.small)
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

// Compact selected values shared by the assignee and label fields.
struct ItemPropertyToken<Icon: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let removeLabel: String
    let canRemove: Bool
    let remove: () -> Void
    @ViewBuilder let icon: () -> Icon
    @State private var isHoveringRemove = false

    var body: some View {
        HStack(spacing: 6) {
            icon()
                .fixedSize()
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
                .fontWeight(.regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(title)
            if canRemove {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(isHoveringRemove ? 1 : 0.8))
                        #if os(macOS)
                        .frame(width: 20, height: 24)
                        #else
                        .frame(width: 44, height: 44)
                        #endif
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .onHover { isHoveringRemove = $0 }
                .help(removeLabel)
                .accessibilityLabel(removeLabel)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, canRemove ? 4 : 8)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ItemPropertyTokenLayout: Layout {
    private let spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let frames = frames(for: subviews, width: width)
        return CGSize(width: width ?? frames.map(\.maxX).max() ?? 0,
                      height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat?) -> [CGRect] {
        let availableWidth = width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, availableWidth), height: nil))
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
