import SwiftUI

struct MobileItemRow<Metadata: View>: View {
    let item: ProjectItem
    let statusOption: StatusOption?
    var showsStatus: Bool
    let metadata: Metadata

    init(item: ProjectItem, showsStatus: Bool = true, statusOption: StatusOption? = nil, @ViewBuilder metadata: () -> Metadata) {
        self.statusOption = statusOption
        self.item = item
        self.showsStatus = showsStatus
        self.metadata = metadata()
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: stateSymbol)
                .foregroundStyle(stateColor)
                .frame(width: 22, height: 24)
                .accessibilityLabel(stateLabel)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(.body).foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        repositoryLabel
                        statusLabel
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        repositoryLabel
                        statusLabel
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                metadata.font(.caption)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, 4)
    }

    private var repositoryLabel: some View {
        Text((item.repositoryName ?? String(localized: "Draft item"))
             + (item.number.map { " #\($0)" } ?? ""))
    }

    @ViewBuilder
    private var statusLabel: some View {
        if showsStatus, let status = item.status {
            HStack(spacing: 4) {
                if let statusOption {
                    Circle().fill(statusOption.swiftUIColor).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(status)
            }
        }
    }

    private var stateSymbol: String {
        switch item.contentType {
        case .issue: item.issueState == .closed ? "checkmark.circle.fill" : "smallcircle.filled.circle"
        case .pullRequest: item.prState == .merged ? "arrow.triangle.merge" : item.prState == .closed ? "xmark.circle" : item.signals.isDraft ? "pencil.circle" : "arrow.triangle.pull"
        case .draftIssue: "doc.text"
        case .redacted: "lock"
        }
    }

    private var stateColor: Color {
        switch item.contentType {
        case .issue: item.issueState == .closed ? .purple : .green
        case .pullRequest: item.prState == .merged ? .purple : item.prState == .closed ? .red : item.signals.isDraft ? .secondary : .green
        case .draftIssue, .redacted: .secondary
        }
    }

    private var stateLabel: String {
        switch item.contentType {
        case .issue: item.issueState == .closed ? String(localized: "Closed Issue") : String(localized: "Open Issue State", defaultValue: "Open Issue")
        case .pullRequest: item.prState == .merged ? String(localized: "Merged PR") : item.prState == .closed ? String(localized: "Closed PR") : item.signals.isDraft ? String(localized: "Draft PR") : String(localized: "Open PR")
        case .draftIssue: String(localized: "Draft item")
        case .redacted: String(localized: "Restricted item")
        }
    }
}

extension MobileItemRow where Metadata == EmptyView {
    init(item: ProjectItem, showsStatus: Bool = true, statusOption: StatusOption? = nil) {
        self.init(item: item, showsStatus: showsStatus, statusOption: statusOption) { EmptyView() }
    }
}

extension View {
    func mobileSearch(text: Binding<String>, prompt: LocalizedStringKey = "Search items") -> some View {
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
    }
}
