import MihomoKit
import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

extension MenuBarRootView {
    private struct SegmentedControlStyle {
        let isMode: Bool

        static let mode = SegmentedControlStyle(isMode: true)
        static let tab = SegmentedControlStyle(isMode: false)

        var selectionBackgroundID: String {
            self.isMode ? "mode-segmented-selection-background" : "tab-segmented-selection-background"
        }

        var selectionIndicatorID: String {
            self.isMode ? "mode-segmented-selection-indicator" : "tab-segmented-selection-indicator"
        }

        var indicatorWidth: CGFloat {
            self.isMode ? 0 : 16
        }

        var indicatorBottomPadding: CGFloat {
            self.isMode ? 0 : 2
        }

        var cornerRadius: CGFloat {
            self.isMode ? 10 : 0
        }

        var rowHeight: CGFloat {
            self.isMode ? 38 : 26
        }

        var stackSpacing: CGFloat {
            self.isMode ? T.space1 : 0
        }

        var contentVerticalPadding: CGFloat {
            self.isMode ? 3 : 2
        }

        func selectedFillOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.10 : 0.045) : (isDark ? 0.22 : 0.12)
        }

        func selectedBorderOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.14 : 0.08) : (isDark ? 0.20 : 0.14)
        }

        func hoverFillOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.06 : 0.035) : 0
        }

        func selectedForegroundOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.96 : 0.88) : (isDark ? 0.96 : 0.92)
        }

        func selectedIconOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.88 : 0.80) : (isDark ? 0.98 : 0.94)
        }
    }

    var modeAndTabSection: some View {
        VStack(spacing: T.space2) {
            self.modeSwitcher
            self.topTabs
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var modeSwitcher: some View {
        HStack(spacing: T.space2) {
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
        .padding(T.space1)
        .frame(width: contentWidth)
        .background(self.nativeControlSurface(cornerRadius: SegmentedControlStyle.mode.cornerRadius))
    }

    func modeSegmentButton(title: String, mode: CoreMode, symbol: String) -> some View {
        let style = SegmentedControlStyle.mode
        let selected = settingsStore.editableSettings.mode == mode
        let switchingThisMode = switchingMode == mode
        let hovered = hoveredMode == mode

        return Button {
            guard appViewModel.isModeSwitchEnabled, switchingMode == nil,
                  mode != settingsStore.editableSettings.mode else { return }

            switchingMode = mode
            Task { @MainActor in
                await appViewModel.switchMode(to: mode)
                switchingMode = nil
            }
        } label: {
            ZStack(alignment: .bottom) {
                VStack(spacing: style.stackSpacing) {
                    if switchingThisMode {
                        ProgressView()
                            .controlSize(.small)
                            .tint(self.segmentedAccentColor(style: style))
                    } else {
                        Image(systemName: symbol)
                            .font(.app(size: T.FontSize.caption, weight: .bold))
                            .foregroundStyle(self.segmentedIconColor(
                                style: style,
                                selected: selected,
                                hovered: hovered))
                    }

                    Text(title)
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(self.segmentedLabelColor(style: style, selected: selected, hovered: hovered))
                }
                .padding(.vertical, style.contentVerticalPadding)
                .frame(maxWidth: .infinity)
                .frame(height: style.rowHeight)
                .background(self.segmentedButtonBackground(style: style, selected: selected, hovered: hovered))
                .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .onHover { hoveredMode = self.nextHovered(current: hoveredMode, target: mode, isHovering: $0) }
        .animation(.snappy(duration: 0.18), value: settingsStore.editableSettings.mode)
        .animation(.easeOut(duration: 0.12), value: hoveredMode)
    }

    var topTabs: some View {
        HStack(spacing: T.space2) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                self.tabSegmentButton(tab)
            }
        }
        .frame(width: contentWidth)
    }

    func tabSegmentButton(_ tab: RootTab) -> some View {
        let style = SegmentedControlStyle.tab
        let selected = self.currentTab == tab
        let hovered = hoveredTab == tab

        return Button {
            guard self.currentTab != tab else { return }
            withAnimation(.snappy(duration: 0.18)) {
                self.currentTab = tab
            }
        } label: {
            ZStack(alignment: .bottom) {
                Text(self.tr(tab.titleKey))
                    .font(.app(size: T.FontSize.body, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(T.minimumScale)
                    .foregroundStyle(self.segmentedLabelColor(style: style, selected: selected, hovered: hovered))
                    .frame(maxWidth: .infinity)
                    .frame(height: style.rowHeight)

                if selected {
                    Capsule(style: .continuous)
                        .fill(self.segmentedAccentColor(style: style))
                        .frame(width: style.indicatorWidth, height: 2)
                        .padding(.bottom, style.indicatorBottomPadding)
                        .matchedGeometryEffect(id: style.selectionIndicatorID, in: self.segmentedSelectionNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredTab = self.nextHovered(current: hoveredTab, target: tab, isHovering: $0) }
        .animation(.snappy(duration: 0.18), value: self.currentTab)
        .animation(.easeOut(duration: 0.12), value: hoveredTab)
    }

    @ViewBuilder
    private func segmentedButtonBackground(
        style: SegmentedControlStyle,
        selected: Bool,
        hovered: Bool) -> some View
    {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        if selected, style.isMode {
            shape
                .fill(self.segmentedSelectionFill(style: style))
                .overlay {
                    shape.stroke(
                        self.segmentedSelectionBorder(style: style),
                        lineWidth: T.stroke)
                }
                .matchedGeometryEffect(id: style.selectionBackgroundID, in: self.segmentedSelectionNamespace)
        } else if hovered {
            shape.fill(self.segmentedHoverFill(style: style))
        } else {
            Color.clear
        }
    }

    private func segmentedLabelColor(style: SegmentedControlStyle, selected: Bool, hovered: Bool) -> Color {
        if selected {
            return style.isMode
                ? nativePrimaryLabel.opacity(style.selectedForegroundOpacity(isDark: isDarkAppearance))
                : nativePrimaryLabel
        }
        if hovered {
            return nativePrimaryLabel.opacity(isDarkAppearance ? 0.82 : (style.isMode ? 0.72 : 0.74))
        }
        return nativeSecondaryLabel
    }

    private func segmentedIconColor(style: SegmentedControlStyle, selected: Bool, hovered: Bool) -> Color {
        if selected {
            return style.isMode
                ? self.segmentedAccentColor(style: style).opacity(style.selectedIconOpacity(isDark: isDarkAppearance))
                : self.segmentedSelectedForeground(style: style)
        }
        if hovered {
            return nativeSecondaryLabel.opacity(isDarkAppearance ? 0.96 : 0.84)
        }
        return nativeTertiaryLabel
    }

    private func segmentedAccentColor(style: SegmentedControlStyle) -> Color {
        isDarkAppearance
            ? (style.isMode ? Color(red: 0.56, green: 0.77, blue: 0.98) : Color(red: 0.50, green: 0.72, blue: 0.95))
            : (style.isMode ? Color(red: 0.16, green: 0.36, blue: 0.67) : Color(red: 0.20, green: 0.40, blue: 0.71))
    }

    private func segmentedSelectionFill(style: SegmentedControlStyle) -> Color {
        self.segmentedAccentColor(style: style).opacity(style.selectedFillOpacity(isDark: isDarkAppearance))
    }

    private func segmentedSelectionBorder(style: SegmentedControlStyle) -> Color {
        self.segmentedAccentColor(style: style).opacity(style.selectedBorderOpacity(isDark: isDarkAppearance))
    }

    private func segmentedHoverFill(style: SegmentedControlStyle) -> Color {
        nativeHoverFill.opacity(style.hoverFillOpacity(isDark: isDarkAppearance))
    }

    private func segmentedSelectedForeground(style: SegmentedControlStyle) -> Color {
        self.segmentedAccentColor(style: style)
            .opacity(style.selectedForegroundOpacity(isDark: self.isDarkAppearance))
    }
}
