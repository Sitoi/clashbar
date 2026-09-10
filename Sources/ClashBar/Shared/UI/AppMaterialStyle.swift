import SwiftUI

struct AppMaterialSurface: View {
    let cornerRadius: CGFloat
    let stroke: Color
    var lineWidth: CGFloat = MenuBarLayoutTokens.stroke

    init(
        cornerRadius: CGFloat,
        stroke: Color,
        lineWidth: CGFloat = MenuBarLayoutTokens.stroke)
    {
        self.cornerRadius = cornerRadius
        self.stroke = stroke
        self.lineWidth = lineWidth
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
        shape.fill(.regularMaterial)
            .overlay {
                shape.stroke(self.stroke, lineWidth: self.lineWidth)
            }
    }
}

extension View {
    @ViewBuilder
    func appBorderedButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
