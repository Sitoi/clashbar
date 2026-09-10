import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct CompactSelectionMenuConfiguration<Option: Hashable & Identifiable> {
    let selection: Option
    let options: [Option]
    let symbol: String
    let helpText: String
    let optionTitle: (Option) -> String
    let onSelect: (Option) -> Void
}

extension View {
    var isDarkAppearance: Bool {
        // swiftlint:disable:next implicit_return
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    var nativeAccent: Color {
        .accentColor
    }

    var nativeInfo: Color {
        .blue
    }

    var nativePositive: Color {
        .green
    }

    var nativeWarning: Color {
        .orange
    }

    var nativeCritical: Color {
        .red
    }

    var nativeTeal: Color {
        .teal
    }

    var nativeIndigo: Color {
        .indigo
    }

    var nativePurple: Color {
        .purple
    }

    var nativePrimaryLabel: Color {
        .primary
    }

    var nativeSecondaryLabel: Color {
        .secondary
    }

    var nativeTertiaryLabel: Color {
        Color(nsColor: .tertiaryLabelColor)
    }

    var nativeBadgeFill: Color {
        Color(nsColor: .quaternaryLabelColor).opacity(T.Opacity.tint)
    }

    var nativeSelectedMenuText: Color {
        Color(nsColor: .selectedMenuItemTextColor)
    }

    var nativeShadow: Color {
        Color(nsColor: .shadowColor)
    }

    var nativeSeparator: Color {
        Color(nsColor: .separatorColor)
    }

    var nativeControlFill: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    var nativeControlBorder: Color {
        Color(nsColor: .separatorColor)
    }

    var nativeHoverFill: Color {
        Color(nsColor: .selectedContentBackgroundColor)
    }

    func nativeHoverRowBackground(
        _ hovered: Bool,
        cornerRadius: CGFloat = T.cornerRadius) -> some View
    {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(hovered ? self.nativeHoverFill : .clear)
    }

    func nativeBadgeCapsule() -> some View {
        Capsule(style: .continuous).fill(self.nativeBadgeFill)
    }

    /// 统一的筛选 chip：选中为实心强调色 + 白字，未选为浅底胶囊 + 次级文字。可选尾随计数。
    func filterChip(
        title: String,
        count: Int? = nil,
        selected: Bool,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            HStack(spacing: T.space2) {
                Text(title)
                    .font(.app(size: T.FontSize.caption, weight: .medium))
                if let count {
                    Text("\(count)")
                        .font(.app(size: T.FontSize.caption, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : self.nativeTertiaryLabel)
                }
            }
            .foregroundStyle(selected ? Color.white : self.nativeSecondaryLabel)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, T.space6)
            .padding(.vertical, T.space2)
            .background {
                if selected {
                    Capsule(style: .continuous).fill(self.nativeInfo.opacity(T.Opacity.solid))
                } else {
                    self.nativeBadgeCapsule()
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func nativeRowFill(active: Bool, hovered: Bool) -> Color {
        if active {
            return self.nativeAccent.opacity(T.Opacity.selection)
        }
        if hovered {
            return self.nativeHoverFill
        }
        return self.nativeControlFill
    }

    func nativeActionBackground(hovered: Bool, destructive: Bool = false) -> Color {
        guard hovered else { return .clear }
        return destructive ? self.nativeCritical.opacity(T.Opacity.tint) : self.nativeHoverFill
    }

    func nativeActionForeground(hovered: Bool, destructive: Bool = false) -> Color {
        if destructive {
            return hovered ? self.nativeCritical : self.nativeSecondaryLabel
        }
        return hovered ? self.nativePrimaryLabel : self.nativeSecondaryLabel
    }

    func nativeControlSurface(cornerRadius: CGFloat = T.cornerRadius) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(self.nativeControlFill.opacity(self.isDarkAppearance ? 0.54 : 0.38))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        self.nativeControlBorder.opacity(self.isDarkAppearance ? 0.40 : 0.12),
                        lineWidth: T.stroke)
            }
    }

    func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.app(size: T.FontSize.body, weight: .regular))
            .foregroundStyle(self.nativeSecondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .menuRowPadding()
    }

    func fractionSummaryBadge(current: Int, total: Int) -> some View {
        HStack(spacing: T.space1) {
            Text("\(current)")
                .font(.app(size: T.FontSize.caption, weight: .bold))
                .foregroundStyle(self.nativePrimaryLabel)
            Text("/")
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .foregroundStyle(self.nativeTertiaryLabel)
            Text("\(total)")
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .foregroundStyle(self.nativeSecondaryLabel)
        }
        .padding(.horizontal, T.space6)
        .padding(.vertical, T.space2)
        .background(self.nativeBadgeCapsule())
    }

    func compactAsyncIconButton(
        symbol: String,
        label: String,
        tint: Color,
        baseTint: Color? = nil,
        role: ButtonRole? = nil,
        isLoading: Bool = false,
        size: CGFloat = 20,
        fontSize: CGFloat = T.FontSize.body,
        hierarchicalSymbol: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        CompactAsyncIconButton(
            symbol: symbol,
            tint: tint,
            baseTint: baseTint ?? self.nativeSecondaryLabel,
            role: role,
            isLoading: isLoading,
            size: size,
            fontSize: fontSize,
            hierarchicalSymbol: hierarchicalSymbol,
            action: action)
            .accessibilityLabel(label)
    }

    func compactTopIcon(
        _ symbol: String,
        label: String,
        role: ButtonRole? = nil,
        warning: Bool = false,
        toneOverride: Color? = nil,
        isLoading: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        let tone: Color = if let toneOverride {
            toneOverride
        } else if warning {
            self.nativeCritical
        } else {
            self.nativeSecondaryLabel
        }

        return self.compactAsyncIconButton(
            symbol: symbol,
            label: label,
            tint: tone.opacity(T.Opacity.solid),
            role: role,
            isLoading: isLoading,
            action: action)
    }

    func compactSelectionMenu(
        _ configuration: CompactSelectionMenuConfiguration<some Hashable & Identifiable>) -> some View
    {
        Menu {
            ForEach(configuration.options) { option in
                Button {
                    configuration.onSelect(option)
                } label: {
                    if configuration.selection == option {
                        Label(configuration.optionTitle(option), systemImage: "checkmark")
                    } else {
                        Text(configuration.optionTitle(option))
                    }
                }
            }
        } label: {
            Label(configuration.optionTitle(configuration.selection), systemImage: configuration.symbol)
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .lineLimit(1)
        }
        .appBorderedButtonStyle()
        .controlSize(.small)
        .help(configuration.helpText)
    }

    func compareLatency(lhs: Int?, rhs: Int?, ascending: Bool) -> ComparisonResult {
        let leftAvailable = self.isProxyNodeAvailable(lhs)
        let rightAvailable = self.isProxyNodeAvailable(rhs)
        if leftAvailable != rightAvailable {
            return leftAvailable ? .orderedAscending : .orderedDescending
        }
        guard leftAvailable, rightAvailable, let lhs, let rhs, lhs != rhs else {
            return .orderedSame
        }
        return (ascending ? lhs < rhs : lhs > rhs) ? .orderedAscending : .orderedDescending
    }

    func isProxyNodeAvailable(_ latency: Int?) -> Bool {
        guard let latency else { return false }
        return latency > 0
    }

    func latencyColor(_ value: Int?) -> Color {
        guard let value else { return self.nativeTertiaryLabel }
        if value == 0 {
            return self.nativeCritical.opacity(T.Opacity.solid)
        }
        if value <= 400 {
            return self.nativePositive.opacity(T.Opacity.solid)
        }
        return self.nativeWarning.opacity(T.Opacity.solid)
    }

    func nextHovered<V: Equatable>(current: V?, target: V, isHovering: Bool) -> V? {
        isHovering ? target : (current == target ? nil : current)
    }

    func machineStatusTint(_ status: MachineConnectionStatus) -> Color {
        switch status {
        case .unknown:
            self.nativeSecondaryLabel
        case .checking:
            self.nativeWarning.opacity(T.Opacity.solid)
        case .connected:
            self.nativePositive.opacity(T.Opacity.solid)
        case .failed:
            self.nativeCritical.opacity(T.Opacity.solid)
        }
    }
}

struct CompactAsyncIconButton: View {
    let symbol: String
    let tint: Color
    let baseTint: Color
    let role: ButtonRole?
    let isLoading: Bool
    let size: CGFloat
    let fontSize: CGFloat
    let hierarchicalSymbol: Bool
    let action: () async -> Void

    @State private var hovered = false

    var body: some View {
        Button(role: self.role) {
            Task { await self.action() }
        } label: {
            ZStack {
                Image(systemName: self.symbol)
                    .font(.app(size: self.fontSize, weight: .semibold))
                    .foregroundStyle(self.hovered ? self.tint : self.baseTint)
                    .symbolRenderingMode(self.hierarchicalSymbol ? .hierarchical : .monochrome)
                    .opacity(self.isLoading ? 0 : 1)

                ProgressView()
                    .controlSize(.mini)
                    .opacity(self.isLoading ? 1 : 0)
            }
            .frame(width: self.size, height: self.size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(self.isLoading)
        .onHover { self.hovered = $0 }
    }
}
