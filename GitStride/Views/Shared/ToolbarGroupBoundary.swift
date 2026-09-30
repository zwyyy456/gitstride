import SwiftUI

/// Separates functional groups using each supported system's toolbar presentation.
struct ToolbarGroupBoundary: ToolbarContent {
    var placement: ToolbarItemPlacement = .automatic

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: placement)
        } else {
            ToolbarItem(placement: placement) {
                Spacer()
                    .frame(width: 12, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
