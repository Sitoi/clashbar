import SwiftUI

struct HeightReportingModifier: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        self.onChange(geometry.size.height)
                    }
                    .onChange(of: geometry.size.height) { _, newHeight in
                        self.onChange(newHeight)
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
