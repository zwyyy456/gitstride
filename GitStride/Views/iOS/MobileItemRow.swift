import SwiftUI

struct MobileItemRow: View {
    let item: ProjectItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.displayTitle).font(.body).foregroundStyle(.primary)
            HStack {
                Text(item.repositoryName ?? String(localized: "Draft item"))
                if let number = item.number { Text("#\(number)") }
                Spacer(minLength: 4)
                if let status = item.status { Text(status) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
