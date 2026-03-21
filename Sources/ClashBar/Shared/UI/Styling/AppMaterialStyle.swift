import SwiftUI

enum AppMaterialStyle {
    case flat

    static var current: Self {
        .flat
    }
}

enum AppSurfaceFallbackStyle {
    case material(Material)
    case color(Color)
}

struct AppMaterialSurface: View {
    let cornerRadius: CGFloat
    let fallbackStyle: AppSurfaceFallbackStyle
    let stroke: Color
    var lineWidth: CGFloat = MenuBarLayoutTokens.stroke

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)

        self.legacySurface(shape: shape)
        .overlay {
            shape.stroke(self.stroke, lineWidth: self.lineWidth)
        }
    }

    @ViewBuilder
    private func legacySurface(shape: RoundedRectangle) -> some View {
        switch self.fallbackStyle {
        case let .material(material):
            shape.fill(material)
        case let .color(color):
            shape.fill(color)
        }
    }
}

extension View {
    func appBorderedButtonStyle(prominent: Bool = false) -> some View {
        self.appLegacyBorderedButtonStyle(prominent: prominent)
    }

    @ViewBuilder
    private func appLegacyBorderedButtonStyle(prominent: Bool) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
