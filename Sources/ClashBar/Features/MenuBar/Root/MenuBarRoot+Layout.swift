import SwiftUI

extension MenuBarRoot {
    var panelVerticalPadding: CGFloat {
        0
    }

    var clampedPreferredPanelHeight: CGFloat {
        max(1, min(popoverLayoutModel.preferredPanelHeight, popoverLayoutModel.maxPanelHeight))
    }

    var maxPanelContentHeight: CGFloat {
        max(0, popoverLayoutModel.maxPanelHeight - self.panelVerticalPadding)
    }

    var currentPanelContentHeight: CGFloat {
        max(0, self.clampedPreferredPanelHeight - self.panelVerticalPadding)
    }

    var hasMeasuredFixedSections: Bool {
        topHeaderHeight > 0 && modeAndTabSectionHeight > 0 && footerBarHeight > 0
    }

    var hasMeasuredCurrentTabContent: Bool {
        tabContentHeights[currentTab] != nil
    }

    var hasMeasuredLayoutForCurrentTab: Bool {
        self.hasMeasuredFixedSections && self.hasMeasuredCurrentTabContent
    }

    var unresolvedTabScrollAreaHeight: CGFloat {
        max(0, self.currentPanelContentHeight - self.fixedSectionHeight)
    }

    var measuredTabContentHeight: CGFloat {
        max(1, tabContentHeights[currentTab] ?? self.unresolvedTabScrollAreaHeight)
    }

    var fixedSectionHeight: CGFloat {
        topHeaderHeight + modeAndTabSectionHeight + footerBarHeight
    }

    var maxScrollableContentHeight: CGFloat {
        max(0, self.maxPanelContentHeight - self.fixedSectionHeight)
    }

    var tabScrollAreaHeight: CGFloat {
        guard self.hasMeasuredLayoutForCurrentTab else { return self.unresolvedTabScrollAreaHeight }
        return min(self.measuredTabContentHeight, self.maxScrollableContentHeight)
    }

    var resolvedPanelHeight: CGFloat {
        guard self.hasMeasuredLayoutForCurrentTab else { return self.clampedPreferredPanelHeight }
        let target = self.fixedSectionHeight + self.tabScrollAreaHeight + self.panelVerticalPadding
        return max(1, min(target, popoverLayoutModel.maxPanelHeight))
    }

    enum SectionHeightTarget {
        case header
        case modeAndTab
        case footer
    }

    func updateSectionHeight(_ measured: CGFloat, target: SectionHeightTarget) {
        let normalized = max(0, measured)

        switch target {
        case .header:
            if abs(topHeaderHeight - normalized) > 0.5 {
                topHeaderHeight = normalized
            }
        case .modeAndTab:
            if abs(modeAndTabSectionHeight - normalized) > 0.5 {
                modeAndTabSectionHeight = normalized
            }
        case .footer:
            if abs(footerBarHeight - normalized) > 0.5 {
                footerBarHeight = normalized
            }
        }
    }

    func updateTabContentHeight(_ measured: CGFloat, for tab: RootTab) {
        let normalized = max(1, measured)
        let existing = tabContentHeights[tab] ?? 0
        guard abs(existing - normalized) > 0.5 else { return }

        tabContentHeights[tab] = normalized
    }

    func publishPreferredPanelHeight() {
        guard self.hasMeasuredLayoutForCurrentTab else { return }
        let clampedHeight = max(1, min(resolvedPanelHeight, popoverLayoutModel.maxPanelHeight)).rounded(.up)
        guard abs(popoverLayoutModel.preferredPanelHeight - clampedHeight) > 0.5 else { return }

        popoverLayoutModel.preferredPanelHeight = clampedHeight
    }
}
