import SwiftUI

struct HeightReportingModifier: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear
                    .task(id: geometry.size.height) {
                        self.onChange(geometry.size.height)
                    }
            }
        }
    }
}

extension View {
    func reportHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(HeightReportingModifier(onChange: onChange))
    }
}
