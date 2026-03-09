import AppKit
import SwiftUI

extension MenuBarRoot {
    var modeAndTabSection: some View {
        VStack(spacing: MenuBarLayoutTokens.space6) {
            self.modeSwitcher
            self.topTabs
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(nativeSeparator).frame(height: MenuBarLayoutTokens.stroke)
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
        .padding(MenuBarLayoutTokens.space2)
        .frame(width: contentWidth)
        .background(
            nativeControlFill,
            in: RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cornerRadius, style: .continuous)
                .stroke(nativeControlBorder, lineWidth: MenuBarLayoutTokens.stroke)
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
            VStack(spacing: MenuBarLayoutTokens.space2) {
                if switchingThisMode {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
                }

                Text(title)
                    .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle((selected || hovered) ? nativePrimaryLabel : nativeSecondaryLabel)
            .frame(maxWidth: .infinity)
            .frame(height: MenuBarLayoutTokens.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cornerRadius, style: .continuous)
                    .fill(
                        selected
                            ? nativeAccent.opacity(MenuBarLayoutTokens.Opacity.tint)
                            : (hovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(MenuBarLayoutTokens.Opacity.tint) : .clear)))
            .overlay {
                if selected || hovered {
                    RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cornerRadius, style: .continuous)
                        .stroke(
                            selected ? nativeAccent.opacity(MenuBarLayoutTokens.Opacity.tint) : nativeControlBorder.opacity(MenuBarLayoutTokens.Theme.Dark.borderEmphasis),
                            lineWidth: MenuBarLayoutTokens.stroke)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hoveredMode = self.nextHovered(
            current: hoveredMode, target: mode, isHovering: $0) }
    }

    var topTabs: some View {
        let tabs = RootTab.allCases
        let labels = tabs.map { self.tr($0.titleKey) }
        let selectedIndex = Binding<Int>(
            get: { tabs.firstIndex(of: self.currentTab) ?? 0 },
            set: { index in
                guard tabs.indices.contains(index) else { return }
                self.setCurrentTabWithoutAnimation(tabs[index])
            })

        return EqualWidthSegmentedControl(labels: labels, selectedIndex: selectedIndex)
            .frame(width: contentWidth, height: 24)
    }
}

@MainActor
private struct EqualWidthSegmentedControl: NSViewRepresentable {
    let labels: [String]
    @Binding var selectedIndex: Int

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.segmentChanged(_:)))
        control.segmentDistribution = .fillEqually
        control.selectedSegment = selectedIndex
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        for (i, label) in labels.enumerated() {
            if control.label(forSegment: i) != label {
                control.setLabel(label, forSegment: i)
            }
        }
        if control.selectedSegment != selectedIndex {
            control.selectedSegment = selectedIndex
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: EqualWidthSegmentedControl

        init(_ parent: EqualWidthSegmentedControl) {
            self.parent = parent
        }

        @MainActor @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard index >= 0, index < parent.labels.count else { return }
            parent.selectedIndex = index
        }
    }
}
