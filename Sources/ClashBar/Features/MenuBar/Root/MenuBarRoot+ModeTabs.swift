import SwiftUI

extension MenuBarRoot {
    var modeAndTabSection: some View {
        VStack(spacing: MenuBarLayoutTokens.sectionGap) {
            self.modeSwitcher
            self.topTabs
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(nativeSeparator).frame(height: MenuBarLayoutTokens.hairline)
        }
    }

    var modeSwitcher: some View {
        HStack(spacing: 0) {
            self.modeSegmentButton(
                title: tr("ui.mode.rule"),
                mode: .rule,
                symbol: "line.3.horizontal.decrease.circle")
            self.modeSegmentButton(
                title: tr("ui.mode.global"),
                mode: .global,
                symbol: "globe")
            self.modeSegmentButton(
                title: tr("ui.mode.direct"),
                mode: .direct,
                symbol: "paperplane")
        }
        .padding(2)
        .frame(width: contentWidth)
        .background(
            nativeControlFill,
            in: RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cardCornerRadius, style: .continuous)
                .stroke(nativeControlBorder, lineWidth: 0.7)
        }
    }

    func modeSegmentButton(title: String, mode: CoreMode, symbol: String) -> some View {
        let selected = appState.currentMode == mode
        let switchingThisMode = switchingMode == mode
        let hovered = hoveredMode == mode

        return Button {
            if !appState.isModeSwitchEnabled || switchingMode != nil || mode == appState.currentMode { return }

            switchingMode = mode
            Task { @MainActor in
                await appState.switchMode(to: mode)
                switchingMode = nil
            }
        } label: {
            VStack(spacing: 2) {
                if switchingThisMode {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(.appSystem(size: 11, weight: .semibold))
                }

                Text(title)
                    .font(.appSystem(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle((selected || hovered) ? nativePrimaryLabel : nativeSecondaryLabel)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: MenuBarLayoutTokens.iconCornerRadius, style: .continuous)
                    .fill(
                        selected
                            ? nativeAccent.opacity(0.16)
                            : (hovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.20) : .clear)))
            .overlay {
                if selected || hovered {
                    RoundedRectangle(cornerRadius: MenuBarLayoutTokens.iconCornerRadius, style: .continuous)
                        .stroke(
                            selected ? nativeAccent.opacity(0.30) : nativeControlBorder.opacity(0.82),
                            lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hoveredMode = self.nextHovered(
            current: hoveredMode, target: mode, isHovering: $0) }
    }

    var topTabs: some View {
        Picker(
            "",
            selection: Binding(
                get: { self.currentTab },
                set: { self.setCurrentTabWithoutAnimation($0) }))
        {
            ForEach(RootTab.allCases, id: \.self) { tab in
                Text(self.tr(tab.titleKey))
                    .tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: contentWidth, height: 24, alignment: .leading)
    }
}
