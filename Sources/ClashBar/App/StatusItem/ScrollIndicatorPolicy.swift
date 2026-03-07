import AppKit

@MainActor
enum ScrollIndicatorPolicy {
    static func suppressRecursively(in rootView: NSView?) {
        guard let rootView else { return }

        for scrollView in self.allScrollViews(in: rootView) {
            self.suppress(for: scrollView)
        }
    }

    private static func allScrollViews(in rootView: NSView) -> [NSScrollView] {
        var stack: [NSView] = [rootView]
        var scrollViews: [NSScrollView] = []

        while let view = stack.popLast() {
            if let scrollView = view as? NSScrollView {
                scrollViews.append(scrollView)
            }
            stack.append(contentsOf: view.subviews)
        }

        return scrollViews
    }

    private static func suppress(for scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
    }
}
