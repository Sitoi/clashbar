import CoreGraphics
import SwiftUI

@MainActor
final class PopoverLayoutModel: ObservableObject {
    @Published private(set) var maxPanelHeight: CGFloat
    @Published private(set) var resolvedPanelHeight: CGFloat

    let minPanelHeight: CGFloat
    private var requestedPanelHeight: CGFloat

    init(
        maxPanelHeight: CGFloat = 640,
        preferredPanelHeight: CGFloat = 320,
        minPanelHeight: CGFloat = 280)
    {
        self.minPanelHeight = minPanelHeight
        self.maxPanelHeight = max(1, maxPanelHeight.rounded(.down))
        self.requestedPanelHeight = max(1, preferredPanelHeight)
        self.resolvedPanelHeight = 1
        self.recalculateResolvedPanelHeight()
    }

    func requestPanelHeight(_ height: CGFloat) {
        let normalized = max(1, height)
        guard abs(self.requestedPanelHeight - normalized) > 0.5 else { return }

        self.requestedPanelHeight = normalized
        self.recalculateResolvedPanelHeight()
    }

    func updateMaximumPanelHeight(_ height: CGFloat) {
        let normalized = max(1, height.rounded(.down))
        guard abs(self.maxPanelHeight - normalized) > 0.5 else { return }

        self.maxPanelHeight = normalized
        self.recalculateResolvedPanelHeight()
    }

    private func recalculateResolvedPanelHeight() {
        let minimum = min(self.minPanelHeight, self.maxPanelHeight)
        let resolved = min(self.maxPanelHeight, max(minimum, self.requestedPanelHeight.rounded(.up)))
        guard abs(self.resolvedPanelHeight - resolved) > 0.5 else { return }

        self.resolvedPanelHeight = resolved
    }
}
