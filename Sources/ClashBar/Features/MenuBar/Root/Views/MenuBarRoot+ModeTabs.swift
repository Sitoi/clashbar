import SwiftUI

extension MenuBarRootView {
    private enum SegmentedControlStyle {
        case mode
        case tab

        var selectionBackgroundID: String {
            switch self {
            case .mode:
                "mode-segmented-selection-background"
            case .tab:
                "tab-segmented-selection-background"
            }
        }

        var selectionIndicatorID: String {
            switch self {
            case .mode:
                "mode-segmented-selection-indicator"
            case .tab:
                "tab-segmented-selection-indicator"
            }
        }

        var indicatorWidth: CGFloat {
            switch self {
            case .mode:
                0
            case .tab:
                0
            }
        }

        var indicatorBottomPadding: CGFloat {
            switch self {
            case .mode:
                0
            case .tab:
                0
            }
        }

        var contentVerticalOffset: CGFloat {
            switch self {
            case .mode:
                0
            case .tab:
                0
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .mode:
                12
            case .tab:
                14
            }
        }

        var rowHeight: CGFloat {
            switch self {
            case .mode:
                28
            case .tab:
                40
            }
        }

        var stackSpacing: CGFloat {
            switch self {
            case .mode:
                MenuBarLayoutTokens.space2
            case .tab:
                MenuBarLayoutTokens.space1
            }
        }

        var contentVerticalPadding: CGFloat {
            2
        }

        func selectedFillOpacity(isDark: Bool) -> CGFloat {
            switch self {
            case .mode:
                isDark ? 0.96 : 1.0
            case .tab:
                isDark ? 0.22 : 0.12
            }
        }

        func selectedBorderOpacity(isDark: Bool) -> CGFloat {
            switch self {
            case .mode:
                isDark ? 0.22 : 0.10
            case .tab:
                isDark ? 0.20 : 0.14
            }
        }

        func hoverFillOpacity(isDark: Bool) -> CGFloat {
            switch self {
            case .mode:
                isDark ? 0.10 : 0.04
            case .tab:
                isDark ? 0.08 : 0.03
            }
        }

        func selectedForegroundOpacity(isDark: Bool) -> CGFloat {
            switch self {
            case .mode:
                isDark ? 0.98 : 0.96
            case .tab:
                isDark ? 0.96 : 0.92
            }
        }

        func selectedIconOpacity(isDark: Bool) -> CGFloat {
            switch self {
            case .mode:
                isDark ? 0.96 : 0.90
            case .tab:
                isDark ? 0.98 : 0.94
            }
        }

        func shadowOpacity(isDark: Bool) -> CGFloat {
            switch self {
            case .mode:
                isDark ? 0.18 : 0.10
            case .tab:
                isDark ? 0.0 : 0.0
            }
        }

        func shadowRadius(isDark _: Bool) -> CGFloat {
            switch self {
            case .mode:
                10
            case .tab:
                0
            }
        }

        func shadowYOffset(isDark _: Bool) -> CGFloat {
            switch self {
            case .mode:
                2
            case .tab:
                0
            }
        }
    }

    var modeAndTabSection: some View {
        VStack(spacing: MenuBarLayoutTokens.space2) {
            self.modeSwitcher
            self.topTabs
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var modeSwitcher: some View {
        HStack(spacing: MenuBarLayoutTokens.space2) {
            self.modeSegmentButton(
                title: tr("ui.mode.rule"),
                mode: .rule,
                symbol: "shield.lefthalf.filled")
            self.modeSegmentButton(
                title: tr("ui.mode.global"),
                mode: .global,
                symbol: "globe")
            self.modeSegmentButton(
                title: tr("ui.mode.direct"),
                mode: .direct,
                symbol: "bolt.fill")
        }
        .padding(MenuBarLayoutTokens.space1)
        .frame(width: contentWidth)
        .background(
            RoundedRectangle(cornerRadius: SegmentedControlStyle.mode.cornerRadius, style: .continuous)
                .fill(self.modeSwitcherBackgroundFill))
        .overlay {
            RoundedRectangle(cornerRadius: SegmentedControlStyle.mode.cornerRadius, style: .continuous)
                .stroke(self.modeSwitcherBorderColor, lineWidth: MenuBarLayoutTokens.stroke)
        }
    }

    func modeSegmentButton(title: String, mode: CoreMode, symbol: String) -> some View {
        let style = SegmentedControlStyle.mode
        let selected = appSession.currentMode == mode
        let switchingThisMode = switchingMode == mode
        let hovered = hoveredMode == mode

        return Button {
            guard appSession.isModeSwitchEnabled, switchingMode == nil, mode != appSession.currentMode else { return }

            switchingMode = mode
            Task { @MainActor in
                await appSession.switchMode(to: mode)
                switchingMode = nil
            }
        } label: {
            HStack(spacing: style.stackSpacing) {
                if switchingThisMode {
                    ProgressView()
                        .controlSize(.small)
                        .tint(self.segmentedAccentColor(style: style))
                } else {
                    Image(systemName: symbol)
                        .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .bold))
                        .foregroundStyle(self.segmentedIconColor(style: style, selected: selected, hovered: hovered))
                }

                Text(title)
                    .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(self.segmentedLabelColor(style: style, selected: selected, hovered: hovered))
            }
            .padding(.vertical, style.contentVerticalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: style.rowHeight)
            .background(self.segmentedButtonBackground(style: style, selected: selected, hovered: hovered))
            .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredMode = self.nextHovered(current: hoveredMode, target: mode, isHovering: $0) }
        .animation(.snappy(duration: 0.18), value: appSession.currentMode)
        .animation(.easeOut(duration: 0.12), value: hoveredMode)
    }

    var topTabs: some View {
        HStack(spacing: MenuBarLayoutTokens.space2) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                self.tabSegmentButton(tab)
            }
        }
        .frame(width: contentWidth)
    }

    func tabSegmentButton(_ tab: RootTab) -> some View {
        let style = SegmentedControlStyle.tab
        let selected = self.rootViewModel.currentTab == tab
        let hovered = hoveredTab == tab

        return Button {
            guard self.rootViewModel.currentTab != tab else { return }
            withAnimation(.snappy(duration: 0.18)) {
                self.rootViewModel.syncCurrentTab(tab)
            }
        } label: {
            VStack(spacing: style.stackSpacing) {
                Image(systemName: tab.symbolName)
                    .font(.app(size: MenuBarLayoutTokens.FontSize.subhead, weight: .bold))
                    .foregroundStyle(self.segmentedIconColor(style: style, selected: selected, hovered: hovered))

                Text(self.tr(tab.titleKey))
                    .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(MenuBarLayoutTokens.minimumScale)
                    .foregroundStyle(self.segmentedLabelColor(style: style, selected: selected, hovered: hovered))
            }
            .padding(.horizontal, MenuBarLayoutTokens.space2)
            .padding(.vertical, style.contentVerticalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: style.rowHeight)
            .background(self.segmentedButtonBackground(style: style, selected: selected, hovered: hovered))
            .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredTab = self.nextHovered(current: hoveredTab, target: tab, isHovering: $0) }
        .animation(.snappy(duration: 0.18), value: self.rootViewModel.currentTab)
        .animation(.easeOut(duration: 0.12), value: hoveredTab)
    }

    @ViewBuilder
    private func segmentedButtonBackground(
        style: SegmentedControlStyle,
        selected: Bool,
        hovered: Bool) -> some View
    {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)

        if selected {
            if style == .tab {
                Color.clear
            } else {
                shape
                    .fill(self.segmentedSelectionFill(style: style))
                    .overlay {
                        shape.stroke(
                            self.segmentedSelectionBorder(style: style),
                            lineWidth: MenuBarLayoutTokens.stroke)
                    }
                    .shadow(
                        color: self.segmentedSelectionShadow(style: style),
                        radius: style.shadowRadius(isDark: self.isDarkAppearance),
                        x: 0,
                        y: style.shadowYOffset(isDark: self.isDarkAppearance))
                    .matchedGeometryEffect(id: style.selectionBackgroundID, in: self.segmentedSelectionNamespace)
            }
        } else if hovered {
            shape
                .fill(self.segmentedHoverFill(style: style))
        } else {
            Color.clear
        }
    }

    private func segmentedLabelColor(style: SegmentedControlStyle, selected: Bool, hovered: Bool) -> Color {
        if selected {
            return self.segmentedSelectedForeground(style: style)
        }
        if hovered {
            return self.nativePrimaryLabel.opacity(self.isDarkAppearance ? 0.82 : 0.72)
        }
        return self.nativeSecondaryLabel
    }

    private func segmentedIconColor(style: SegmentedControlStyle, selected: Bool, hovered: Bool) -> Color {
        if selected {
            return self.segmentedSelectedForeground(style: style)
        }
        if hovered {
            return self.nativeSecondaryLabel.opacity(self.isDarkAppearance ? 0.96 : 0.84)
        }
        return self.nativeTertiaryLabel
    }

    private func segmentedAccentColor(style: SegmentedControlStyle) -> Color {
        if self.isDarkAppearance {
            switch style {
            case .mode:
                Color(red: 0.56, green: 0.77, blue: 0.98)
            case .tab:
                Color(red: 0.50, green: 0.72, blue: 0.95)
            }
        } else {
            switch style {
            case .mode:
                Color(red: 0.16, green: 0.36, blue: 0.67)
            case .tab:
                Color(red: 0.20, green: 0.40, blue: 0.71)
            }
        }
    }

    private var modeSwitcherBackgroundFill: Color {
        Color(nsColor: self.isDarkAppearance ? .controlBackgroundColor : .windowBackgroundColor)
            .opacity(self.isDarkAppearance ? 0.70 : 0.92)
    }

    private var modeSwitcherBorderColor: Color {
        self.nativeControlBorder.opacity(self.isDarkAppearance ? 0.40 : 0.18)
    }

    private func segmentedSelectionFill(style: SegmentedControlStyle) -> Color {
        switch style {
        case .mode:
            return Color(nsColor: self.isDarkAppearance ? .windowBackgroundColor : .white)
                .opacity(style.selectedFillOpacity(isDark: self.isDarkAppearance))
        case .tab:
            return self.segmentedAccentColor(style: style)
                .opacity(style.selectedFillOpacity(isDark: self.isDarkAppearance))
        }
    }

    private func segmentedSelectionBorder(style: SegmentedControlStyle) -> Color {
        switch style {
        case .mode:
            return self.nativeControlBorder.opacity(style.selectedBorderOpacity(isDark: self.isDarkAppearance))
        case .tab:
            return self.segmentedAccentColor(style: style)
                .opacity(style.selectedBorderOpacity(isDark: self.isDarkAppearance))
        }
    }

    private func segmentedSelectionShadow(style: SegmentedControlStyle) -> Color {
        Color.black.opacity(style.shadowOpacity(isDark: self.isDarkAppearance))
    }

    private func segmentedHoverFill(style: SegmentedControlStyle) -> Color {
        switch style {
        case .mode:
            return self.nativeHoverFill.opacity(style.hoverFillOpacity(isDark: self.isDarkAppearance))
        case .tab:
            return self.nativeHoverFill.opacity(style.hoverFillOpacity(isDark: self.isDarkAppearance))
        }
    }

    private func segmentedSelectedForeground(style: SegmentedControlStyle) -> Color {
        self.segmentedAccentColor(style: style)
            .opacity(style.selectedForegroundOpacity(isDark: self.isDarkAppearance))
    }
}
