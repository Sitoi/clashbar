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
        self.applyScrollViewStyleIfNeeded(from: nsView, retries: 6)
    }

    private func applyScrollViewStyleIfNeeded(from view: NSView, retries: Int) {
        DispatchQueue.main.async {
            if let windowContent = view.window?.contentView {
                ScrollIndicatorPolicy.suppressRecursively(in: windowContent)
                return
            }

            guard retries > 0 else { return }
            self.applyScrollViewStyleIfNeeded(from: view, retries: retries - 1)
        }
    }
}
