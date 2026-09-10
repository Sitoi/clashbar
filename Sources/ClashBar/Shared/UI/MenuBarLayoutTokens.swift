import SwiftUI

enum MenuBarLayoutTokens {
    static let panelWidth: CGFloat = 360

    static let space1: CGFloat = 1
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8

    static let stroke: CGFloat = 0.65

    static let panelCornerRadius: CGFloat = 10
    static let cornerRadius: CGFloat = 6

    static let compactRowHeight: CGFloat = 20
    static let rowHeight: CGFloat = 32

    static let rowLeadingIcon: CGFloat = 16

    static let minimumScale: CGFloat = 0.85

    enum Opacity {
        static let solid: CGFloat = 0.92
        static let tint: CGFloat = 0.18
        static let selection: CGFloat = 0.10
    }

    enum AnimationDuration {
        static let quick: CGFloat = 0.15
        static let standard: CGFloat = 0.35
    }

    enum Shadow {
        static let standard = (opacity: 0.20, radius: 12.0, x: 0.0, y: 6.0)
    }

    enum FontSize {
        static let mini: CGFloat = 9
        static let statusBar: CGFloat = 10
        static let caption: CGFloat = 10
        static let subheadline: CGFloat = 11
        static let callout: CGFloat = 12
        static let body: CGFloat = 13
        static let title3: CGFloat = 15
    }
}

extension View {
    func menuRowPadding(vertical: CGFloat = MenuBarLayoutTokens.space6) -> some View {
        padding(.horizontal, MenuBarLayoutTokens.space4)
            .padding(.vertical, vertical)
    }
}

extension Font {
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
