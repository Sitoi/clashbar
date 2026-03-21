import SwiftUI

enum MenuBarLayoutTokens {
    static let panelWidth: CGFloat = 360

    // MARK: - Spacing

    static let space1: CGFloat = 1
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8

    // MARK: - Stroke

    static let stroke: CGFloat = 0.65

    // MARK: - Corner Radius

    static let panelCornerRadius: CGFloat = 10
    static let cornerRadius: CGFloat = 6

    // MARK: - Row Heights

    static let compactRowHeight: CGFloat = 20
    static let rowHeight: CGFloat = 32

    // MARK: - Icon Size

    static let rowLeadingIcon: CGFloat = 16

    // MARK: - Text

    static let minimumScale: CGFloat = 0.85

    // MARK: - Opacity

    enum Opacity {
        static let solid: CGFloat = 0.92
        static let tint: CGFloat = 0.18
    }

    // MARK: - Theme Appearance

    enum Theme {
        enum Dark {
            static let labelSecondary: CGFloat = 0.75
            static let labelTertiary: CGFloat = 0.52
            static let separator: CGFloat = 0.70
            static let controlFill: CGFloat = 0.78
            static let controlBorder: CGFloat = 0.60
            static let hoverFill: CGFloat = 0.28
            static let borderEmphasis: CGFloat = 0.82
        }

        enum Light {
            static let labelSecondary: CGFloat = 0.62
            static let labelTertiary: CGFloat = 0.42
            static let separator: CGFloat = 0.55
            static let controlFill: CGFloat = 0.92
            static let controlBorder: CGFloat = 0.42
            static let hoverFill: CGFloat = 0.18
            static let borderEmphasis: CGFloat = 0.82
        }
    }

    // MARK: - Shadow

    enum Shadow {
        static let standard = (opacity: 0.20, radius: 12.0, x: 0.0, y: 6.0)
    }

    // MARK: - Font Sizes

    enum FontSize {
        static let caption: CGFloat = 10
        static let body: CGFloat = 12
        static let subhead: CGFloat = 14
        static let title: CGFloat = 16
    }
}

extension View {
    func menuRowPadding(vertical: CGFloat = MenuBarLayoutTokens.space6) -> some View {
        padding(.horizontal, MenuBarLayoutTokens.space4)
            .padding(.vertical, vertical)
    }
}
