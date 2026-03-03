import SwiftUI

extension MenuBarRoot {
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
        Color(nsColor: .secondaryLabelColor)
    }

    var nativeTertiaryLabel: Color {
        Color(nsColor: .tertiaryLabelColor)
    }

    var nativeSeparator: Color {
        Color(nsColor: .separatorColor).opacity(0.55)
    }

    var nativeControlFill: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.62)
    }

    var nativeControlBorder: Color {
        Color(nsColor: .separatorColor).opacity(0.45)
    }

    var nativeCardFill: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.56)
    }

    var nativeCardBorder: Color {
        Color(nsColor: .separatorColor).opacity(0.40)
    }

    var nativeHoverFill: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(0.20)
    }

    var nativeBadgeFill: Color {
        Color(nsColor: .quaternaryLabelColor).opacity(0.16)
    }

    func nativeSectionCard(cornerRadius: CGFloat = 10) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(self.nativeCardFill)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(self.nativeCardBorder, lineWidth: 0.6)
            }
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
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(self.nativeSecondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .menuRowPadding()
            .background(self.nativeSectionCard(cornerRadius: 8))
    }

    var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(self.nativeSeparator)
                .frame(height: MenuBarLayoutTokens.hairline)
                .padding(.bottom, MenuBarLayoutTokens.vDense)

            HStack(spacing: MenuBarLayoutTokens.hDense) {
                if let mihomoRepositoryURL {
                    self.footerInfoLink(
                        tr("ui.footer.core_mihomo", appState.version),
                        url: mihomoRepositoryURL,
                        iconSystemName: self.footerMihomoSymbol,
                        alignment: .leading)
                } else {
                    self.footerInfoText(
                        tr("ui.footer.core_mihomo", appState.version),
                        iconSystemName: self.footerMihomoSymbol,
                        alignment: .leading)
                }

                Spacer(minLength: 0)

                if let clashBarRepositoryURL {
                    self.footerInfoLink(
                        tr("ui.footer.version", self.appVersionText),
                        url: clashBarRepositoryURL,
                        iconSystemName: self.footerGitHubSymbol,
                        alignment: .trailing)
                } else {
                    self.footerInfoText(
                        tr("ui.footer.version", self.appVersionText),
                        iconSystemName: self.footerGitHubSymbol,
                        alignment: .trailing)
                }
            }
            .padding(.horizontal, MenuBarLayoutTokens.hRow)
            .padding(.vertical, MenuBarLayoutTokens.vDense + 2)
            .background(self.footerSurfaceBackground)
        }
    }

    var footerSurfaceBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(self.nativeControlFill.opacity(0.86))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(self.nativeControlBorder.opacity(0.9), lineWidth: 0.6)
            }
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.16), radius: 10, x: 0, y: -3)
    }

    func footerInfoText(_ text: String, iconSystemName: String? = nil, alignment: Alignment) -> some View {
        self.footerInfoLabel(text, iconSystemName: iconSystemName, alignment: alignment)
    }

    func footerInfoLink(_ text: String, url: URL, iconSystemName: String? = nil, alignment: Alignment) -> some View {
        Link(destination: url) {
            self.footerInfoLabel(text, iconSystemName: iconSystemName, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    func footerInfoLabel(_ text: String, iconSystemName: String?, alignment: Alignment) -> some View {
        HStack(spacing: 4) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(self.nativeSecondaryLabel)
            }

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(self.nativeSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    var footerMihomoSymbol: String {
        "antenna.radiowaves.left.and.right"
    }

    var footerGitHubSymbol: String {
        "chevron.left.forwardslash.chevron.right"
    }

    var mihomoRepositoryURL: URL? {
        URL(string: "https://github.com/MetaCubeX/mihomo")
    }

    var clashBarRepositoryURL: URL? {
        URL(string: "https://github.com/Sitoi/ClashBar")
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

        let names = Array(Set(proxies.map(\.name)))
        return names.sorted { lhs, rhs in
            let left = self.providerNodeSortWeight(provider: provider, node: lhs)
            let right = self.providerNodeSortWeight(provider: provider, node: rhs)
            if left != right { return left < right }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func providerNodeSortWeight(provider: String, node: String) -> Int {
        guard let value = appState.providerNodeLatencies[provider]?[node] else { return Int.max }
        if value == 0 { return Int.max - 1 }
        return value
    }

    func providerNodeDelayColor(provider: String, node: String) -> Color {
        guard let value = appState.providerNodeLatencies[provider]?[node] else {
            return self.nativeTertiaryLabel
        }
        if value == 0 { return self.nativeCritical.opacity(0.9) }
        if value <= 400 { return self.nativePositive.opacity(0.9) }
        return self.nativeWarning.opacity(0.9)
    }

    func sortedGroupNodes(_ group: ProxyGroup) -> [String] {
        group.all.sorted { lhs, rhs in
            let left = self.sortWeight(group: group.name, node: lhs)
            let right = self.sortWeight(group: group.name, node: rhs)
            if left != right { return left < right }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func sortWeight(group: String, node: String) -> Int {
        guard let value = appState.delayValue(group: group, node: node) else { return Int.max }
        if value == 0 { return Int.max - 1 }
        return value
    }

    func groupColor(for group: ProxyGroup) -> Color {
        let info = self.normalizedProxyGroupInfo(group)
        let lower = info.lowerName
        let compactType = info.compactType

        if compactType == "global" || lower.contains("global") { return self.nativeIndigo }
        if lower.contains("manual") { return self.nativeWarning }
        if lower.contains("media") { return self.nativePurple }
        if lower.contains("apple") { return self.nativeSecondaryLabel }

        switch compactType {
        case "selector", "select":
            return self.nativeAccent
        case "fallback":
            return self.nativeWarning
        case "urltest":
            return self.nativeTeal
        case "loadbalance":
            return self.nativePurple
        default:
            return self.nativeInfo
        }
    }

    func groupSymbol(for group: ProxyGroup) -> String {
        let info = self.normalizedProxyGroupInfo(group)
        let lower = info.lowerName
        let compactType = info.compactType

        if compactType == "global" || lower.contains("global") { return "globe.americas.fill" }

        switch compactType {
        case "selector", "select":
            return "list.bullet.circle"
        case "urltest":
            return "gauge"
        case "fallback":
            return "arrow.triangle.branch"
        case "loadbalance":
            return "shuffle"
        default:
            break
        }

        if lower.contains("apple") { return "apple.logo" }
        if lower.contains("media") { return "film.fill" }
        if lower.contains("manual") { return "hand.raised.fill" }
        return "point.3.filled.connected.trianglepath.dotted"
    }

    func normalizedProxyGroupInfo(_ group: ProxyGroup) -> (lowerName: String, compactType: String) {
        let lowerName = group.name.lowercased()
        let compactType = group.type?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "-", with: "") ?? ""
        return (lowerName, compactType)
    }

    func groupSelectionColor(for group: ProxyGroup) -> Color {
        self.nativeSecondaryLabel
    }

    func groupDelayColor(group: String, node: String) -> Color {
        guard let value = appState.delayValue(group: group, node: node) else {
            return self.nativeTertiaryLabel
        }
        if value == 0 { return self.nativeCritical.opacity(0.9) }
        if value <= 400 { return self.nativePositive.opacity(0.9) }
        return self.nativeWarning.opacity(0.9)
    }

    private struct AsyncBorderedIconStyle {
        let fontSize: CGFloat
        let frameSize: CGFloat
        let controlSize: ControlSize
        let tint: Color
    }

    @ViewBuilder
    func asyncBorderedIconButton(
        symbol: String,
        label: String? = nil,
        fontSize: CGFloat = 11,
        frameSize: CGFloat = 12,
        controlSize: ControlSize = .small,
        tint: Color = .accentColor,
        isLoading: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        let style = AsyncBorderedIconStyle(
            fontSize: fontSize,
            frameSize: frameSize,
            controlSize: controlSize,
            tint: tint)
        if let label {
            self.baseAsyncBorderedIconButton(
                symbol: symbol,
                style: style,
                isLoading: isLoading,
                action: action)
                .accessibilityLabel(label)
        } else {
            self.baseAsyncBorderedIconButton(
                symbol: symbol,
                style: style,
                isLoading: isLoading,
                action: action)
        }
    }

    func roundedIconActionButton(
        symbol: String,
        size: CGFloat,
        foreground: Color,
        isLoading: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        self.asyncBorderedIconButton(
            symbol: symbol,
            fontSize: 11,
            frameSize: max(12, size),
            controlSize: .mini,
            tint: foreground,
            isLoading: isLoading,
            action: action)
    }

    private func baseAsyncBorderedIconButton(
        symbol: String,
        style: AsyncBorderedIconStyle,
        isLoading: Bool,
        action: @escaping () async -> Void) -> some View
    {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: style.fontSize, weight: .semibold))
                    .opacity(isLoading ? 0 : 1)

                ProgressView()
                    .controlSize(style.controlSize)
                    .opacity(isLoading ? 1 : 0)
            }
            .frame(width: max(12, style.frameSize), height: max(12, style.frameSize))
        }
        .buttonStyle(.bordered)
        .controlSize(style.controlSize)
        .tint(style.tint)
        .disabled(isLoading)
    }
}
