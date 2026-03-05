import AppKit
import SwiftUI

extension View {
    func forceHiddenScrollIndicators() -> some View {
        self.modifier(HiddenScrollIndicatorsModifier())
    }
}

private struct HiddenScrollIndicatorsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(ScrollViewScrollerConfigurator())
    }
}

private struct ScrollViewScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
        }
    }
}
