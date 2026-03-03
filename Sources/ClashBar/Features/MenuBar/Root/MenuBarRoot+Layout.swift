import SwiftUI

extension MenuBarRoot {
    var measuredTabContentHeight: CGFloat {
        max(1, tabContentHeights[currentTab] ?? fallbackTabContentHeight)
    }

    var fixedSectionHeight: CGFloat {
        topHeaderHeight + modeAndTabSectionHeight + footerBarHeight
    }

    var maxScrollableContentHeight: CGFloat {
        max(0, popoverLayoutModel.maxPanelHeight - self.fixedSectionHeight)
    }

    var tabScrollAreaHeight: CGFloat {
        min(self.measuredTabContentHeight, self.maxScrollableContentHeight)
    }

    var resolvedPanelHeight: CGFloat {
        let target = self.fixedSectionHeight + self.tabScrollAreaHeight
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
        let clampedHeight = max(1, min(resolvedPanelHeight, popoverLayoutModel.maxPanelHeight)).rounded(.down)
        guard abs(popoverLayoutModel.preferredPanelHeight - clampedHeight) > 0.5 else { return }

        popoverLayoutModel.preferredPanelHeight = clampedHeight
    }

    func menuPanelTabHint(for tab: RootTab) -> MenuPanelTabHint {
        switch tab {
        case .proxy:
            .proxy
        case .rules:
            .rules
        case .activity:
            .activity
        case .logs:
            .logs
        case .system:
            .system
        }
    }

    func rootTab(for hint: MenuPanelTabHint) -> RootTab {
        switch hint {
        case .proxy:
            .proxy
        case .rules:
            .rules
        case .activity:
            .activity
        case .logs:
            .logs
        case .system:
            .system
        }
    }
}
