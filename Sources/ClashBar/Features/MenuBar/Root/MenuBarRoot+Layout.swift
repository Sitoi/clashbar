import SwiftUI

extension MenuBarRoot {
    private var hasMeasuredFixedSections: Bool {
        topHeaderHeight > 0 && modeAndTabSectionHeight > 0 && footerBarHeight > 0
    }

    private var hasResolvedCurrentTabLayout: Bool {
        self.hasMeasuredFixedSections && self.currentTabContentHeight > 0
    }

    private var fixedSectionHeight: CGFloat {
        topHeaderHeight + modeAndTabSectionHeight + footerBarHeight
    }

    private var fallbackTabScrollAreaHeight: CGFloat {
        max(0, popoverLayoutModel.resolvedPanelHeight - self.fixedSectionHeight)
    }

    private var availableTabScrollAreaHeight: CGFloat {
        max(0, popoverLayoutModel.maxPanelHeight - self.fixedSectionHeight)
    }

    var tabScrollAreaHeight: CGFloat {
        guard self.hasResolvedCurrentTabLayout else { return self.fallbackTabScrollAreaHeight }
        return min(max(1, self.currentTabContentHeight), self.availableTabScrollAreaHeight)
    }

    var resolvedPanelHeight: CGFloat {
        guard self.hasResolvedCurrentTabLayout else { return popoverLayoutModel.resolvedPanelHeight }
        return max(1, min(self.fixedSectionHeight + self.tabScrollAreaHeight, popoverLayoutModel.maxPanelHeight))
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

    func updateCurrentTabContentHeight(_ measured: CGFloat, for tab: RootTab) {
        guard tab == self.currentTab else { return }

        let normalized = max(1, measured)
        guard abs(self.currentTabContentHeight - normalized) > 0.5 else { return }

        self.currentTabContentHeight = normalized
    }

    func publishPreferredPanelHeight() {
        guard self.hasResolvedCurrentTabLayout else { return }
        popoverLayoutModel.requestPanelHeight(max(1, self.resolvedPanelHeight.rounded(.up)))
    }
}
