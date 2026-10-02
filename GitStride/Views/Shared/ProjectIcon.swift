import SwiftUI

struct ProjectIcon: View {
    let projectID: String

    private var color: Color {
        let palette: [Color] = [.blue, .teal, .green, .orange, .pink, .purple, .indigo]
        // Keep the sidebar and command palette consistent across launches and renames.
        let hash = projectID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    var body: some View {
        Image(systemName: "square.fill")
            .font(.system(size: 14))
            .foregroundStyle(color)
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }
}

