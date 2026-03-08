import SwiftUI

struct SeparatedForEach<Element: Equatable, ID: Hashable, RowContent: View>: View {
    private struct Item: Identifiable {
        let id: ID
        let element: Element
        let isLast: Bool
    }

    private let items: [Item]
    private let separator: Color
    private let content: (Element) -> RowContent

    init<Data: RandomAccessCollection>(
        data: Data,
        id idPath: KeyPath<Element, ID>,
        separator: Color,
        @ViewBuilder content: @escaping (Element) -> RowContent) where Data.Element == Element
    {
        let array = Array(data)
        self.items = array.enumerated().map { index, el in
            Item(id: el[keyPath: idPath], element: el, isLast: index == array.count - 1)
        }
        self.separator = separator
        self.content = content
    }

    var body: some View {
        ForEach(self.items) { item in
            self.content(item.element)
            if !item.isLast {
                Rectangle()
                    .fill(self.separator)
                    .frame(height: MenuBarLayoutTokens.hairline)
            }
        }
    }
}

struct MeasurementAwareVStack<Content: View>: View {
    @Environment(\.panelMeasurementMode) private var panelMeasurementMode

    let alignment: HorizontalAlignment
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(alignment: HorizontalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if self.panelMeasurementMode {
            VStack(alignment: self.alignment, spacing: self.spacing) { self.content }
        } else {
            LazyVStack(alignment: self.alignment, spacing: self.spacing) { self.content }
        }
    }
}

extension MenuBarRoot {
    func fractionSummaryBadge(current: Int, total: Int) -> some View {
        HStack(spacing: MenuBarLayoutTokens.hMicro) {
            Text("\(current)")
                .font(.appMonospaced(size: 11, weight: .bold))
            Text("/")
                .font(.appMonospaced(size: 10, weight: .medium))
            Text("\(total)")
                .font(.appMonospaced(size: 11, weight: .medium))
        }
        .foregroundStyle(self.nativeSecondaryLabel)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(self.nativeBadgeCapsule())
    }

    // swiftlint:disable:next function_parameter_count
    func compactSelectionMenu<Option: Hashable & Identifiable>(
        selection: Option,
        options: [Option],
        symbol: String,
        helpText: String,
        optionTitle: @escaping (Option) -> String,
        onSelect: @escaping (Option) -> Void) -> some View
    {
        Menu {
            ForEach(options) { option in
                Button {
                    onSelect(option)
                } label: {
                    if selection == option {
                        Label(optionTitle(option), systemImage: "checkmark")
                    } else {
                        Text(optionTitle(option))
                    }
                }
            }
        } label: {
            Label(optionTitle(selection), systemImage: symbol)
                .font(.appSystem(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(helpText)
    }

    var isDarkAppearance: Bool {
        self.colorScheme == .dark
    }

    var nativeAccent: Color {
        Color(nsColor: .controlAccentColor)
    }

    var nativeInfo: Color {
        Color(nsColor: .systemBlue)
    }

    var nativePositive: Color {
        Color(nsColor: .systemGreen)
    }

    var nativeWarning: Color {
        Color(nsColor: .systemOrange)
    }

    var nativeCritical: Color {
        Color(nsColor: .systemRed)
    }

    var nativeTeal: Color {
        Color(nsColor: .systemTeal)
    }

    var nativeIndigo: Color {
        Color(nsColor: .systemIndigo)
    }

    var nativePurple: Color {
        Color(nsColor: .systemPurple)
    }

    var nativePrimaryLabel: Color {
        Color(nsColor: .labelColor)
    }

    var nativeSecondaryLabel: Color {
        Color(nsColor: .labelColor).opacity(self.isDarkAppearance ? 0.88 : 0.80)
    }

    var nativeTertiaryLabel: Color {
        Color(nsColor: .labelColor).opacity(self.isDarkAppearance ? 0.72 : 0.64)
    }

    var nativeSeparator: Color {
        Color(nsColor: .separatorColor).opacity(self.isDarkAppearance ? 0.70 : 0.55)
    }

    var nativeControlFill: Color {
        Color(nsColor: self.isDarkAppearance ? .controlBackgroundColor : .windowBackgroundColor)
            .opacity(self.isDarkAppearance ? 0.78 : 0.92)
    }

    var nativeControlBorder: Color {
        Color(nsColor: .separatorColor).opacity(self.isDarkAppearance ? 0.60 : 0.42)
    }

    var nativeHoverFill: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(self.isDarkAppearance ? 0.28 : 0.20)
    }

    var nativeBadgeFill: Color {
        Color(nsColor: .quaternaryLabelColor).opacity(self.isDarkAppearance ? 0.30 : 0.16)
    }

    func nativeHoverRowBackground(_ hovered: Bool, cornerRadius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(hovered ? self.nativeHoverFill : .clear)
    }

    func nativeBadgeCapsule() -> some View {
        Capsule(style: .continuous)
            .fill(self.nativeBadgeFill)
    }

    func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.appSystem(size: 12, weight: .regular))
            .foregroundStyle(self.nativeSecondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .menuRowPadding()
    }

    var footerBar: some View {
        let mihomoRepositoryURL = URL(string: "https://github.com/MetaCubeX/mihomo")
        let clashBarRepositoryURL = URL(string: "https://github.com/Sitoi/ClashBar")
        let mihomoSymbol = "antenna.radiowaves.left.and.right"
        let gitHubSymbol = "chevron.left.forwardslash.chevron.right"

        return VStack(spacing: 0) {
            HStack(spacing: MenuBarLayoutTokens.hDense) {
                self.footerInfo(
                    tr("ui.footer.core_mihomo", appState.version),
                    url: mihomoRepositoryURL,
                    iconSystemName: mihomoSymbol)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                self.footerInfo(
                    tr("ui.footer.version", self.appVersionText),
                    url: clashBarRepositoryURL,
                    iconSystemName: gitHubSymbol)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
            .background(self.footerSurfaceBackground)
        }
    }

    var footerSurfaceBackground: some View {
        RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cardCornerRadius, style: .continuous)
            .fill(self.nativeControlFill.opacity(0.86))
            .overlay {
                RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cardCornerRadius, style: .continuous)
                    .stroke(self.nativeControlBorder.opacity(0.9), lineWidth: 0.6)
            }
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.16), radius: 10, x: 0, y: -3)
    }

    @ViewBuilder
    func footerInfo(_ text: String, url: URL?, iconSystemName: String? = nil) -> some View {
        if let url {
            Link(destination: url) {
                self.footerInfoLabel(text, iconSystemName: iconSystemName)
            }
            .buttonStyle(.plain)
        } else {
            self.footerInfoLabel(text, iconSystemName: iconSystemName)
        }
    }

    func footerInfoLabel(_ text: String, iconSystemName: String?) -> some View {
        HStack(spacing: 4) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.appSystem(size: 10, weight: .semibold))
                    .foregroundStyle(self.nativeSecondaryLabel)
            }

            Text(text)
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundStyle(self.nativeSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
        }
        .help(text)
    }

    var statusColor: Color {
        switch appState.runtimeVisualStatus {
        case .runningHealthy: self.nativePositive.opacity(0.95)
        case .runningDegraded: self.nativeWarning.opacity(0.95)
        case .starting: self.nativeInfo.opacity(0.95)
        case .failed: self.nativeCritical.opacity(0.95)
        case .stopped: self.nativeSecondaryLabel
        }
    }

    var runtimeBadgeText: String {
        switch appState.runtimeVisualStatus {
        case .runningHealthy, .runningDegraded:
            tr("ui.header.status.running")
        case .starting:
            tr("ui.header.status.starting")
        case .failed:
            tr("ui.header.status.failed")
        case .stopped:
            tr("ui.header.status.stopped")
        }
    }

    var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short, !short.isEmpty { return short }
        if let build, !build.isEmpty { return build }
        return "0.0.1"
    }

    func sortedProviderNodes(provider: String, detail: ProviderDetail?) -> [String] {
        guard let proxies = detail?.proxies else { return [] }
        return self.sortedNodes(
            names: proxies.map(\.name),
            latencyForNode: { self.appState.providerNodeLatencies[provider]?[$0] })
    }

    func orderedUniqueNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        ordered.reserveCapacity(names.count)

        for name in names where !name.isEmpty {
            if seen.insert(name).inserted {
                ordered.append(name)
            }
        }

        return ordered
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

        if ascending {
            return lhs < rhs ? .orderedAscending : .orderedDescending
        }
        return lhs > rhs ? .orderedAscending : .orderedDescending
    }

    func isProxyNodeAvailable(_ latency: Int?) -> Bool {
        guard let latency else { return false }
        return latency > 0
    }

    func latencyColor(_ value: Int?) -> Color {
        guard let value else {
            return self.nativeTertiaryLabel
        }
        if value == 0 { return self.nativeCritical.opacity(0.9) }
        if value <= 400 { return self.nativePositive.opacity(0.9) }
        return self.nativeWarning.opacity(0.9)
    }

    func sortedGroupNodes(_ group: ProxyGroup) -> [String] {
        self.sortedNodes(
            names: group.all,
            latencyForNode: { self.appState.delayValue(group: group.name, node: $0) })
    }

    private func sortedNodes(names: [String], latencyForNode: (String) -> Int?) -> [String] {
        let unique = self.orderedUniqueNames(names)
        let sorted = unique.sorted { lhs, rhs in
            let cmp = self.compareLatency(lhs: latencyForNode(lhs), rhs: latencyForNode(rhs), ascending: true)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        guard self.appState.hideUnavailableProxyNodes else { return sorted }
        return sorted.filter { self.isProxyNodeAvailable(latencyForNode($0)) }
    }

    func compactAsyncIconButton(
        symbol: String,
        label: String,
        tint: Color,
        baseTint: Color? = nil,
        role: ButtonRole? = nil,
        isLoading: Bool = false,
        size: CGFloat = 20,
        fontSize: CGFloat = 13,
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
}

private struct CompactAsyncIconButton: View {
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
                    .font(.appSystem(size: self.fontSize, weight: .semibold))
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
