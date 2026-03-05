import SwiftUI

enum MenuBarLayoutTokens {
    static let hPage: CGFloat = 12
    static let hRow: CGFloat = 10
    static let hDense: CGFloat = 6
    static let hMicro: CGFloat = 3

    static let vRow: CGFloat = 6
    static let vDense: CGFloat = 3
    static let sectionGap: CGFloat = 6

    static let hairline: CGFloat = 0.6
    static let opticalNudge: CGFloat = 1

    static let panelCornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 8
    static let iconCornerRadius: CGFloat = 6
}

extension View {
    func menuRowPadding(vertical: CGFloat = MenuBarLayoutTokens.vRow) -> some View {
        padding(.horizontal, MenuBarLayoutTokens.hRow)
            .padding(.vertical, vertical)
    }
}
