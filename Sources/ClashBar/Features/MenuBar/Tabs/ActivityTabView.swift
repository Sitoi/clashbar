import AppKit
import SwiftUI

extension MenuBarRoot {
    private enum ActivityLayout {
        static let topLineSpacing: CGFloat = MenuBarLayoutTokens.space2
        static let topMetaSpacing: CGFloat = MenuBarLayoutTokens.space1
        static let secondLineSpacing: CGFloat = MenuBarLayoutTokens.space2
        static let rowLineHeight: CGFloat = 16
        static let topRuleMinWidth: CGFloat = 26
        static let topPayloadMinWidth: CGFloat = 14
    }

    private static let activityISO8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let activityISO8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var activityTabBody: some View {
        let connections = self.visibleConnections

        return VStack(alignment: .leading, spacing: MenuBarLayoutTokens.space6) {
            self.activityControlCard

            if connections.isEmpty {
                emptyCard(tr("ui.empty.connections"))
            } else {
                MeasurementAwareVStack(spacing: 0) {
                    SeparatedForEach(data: connections, id: \.id, separator: nativeSeparator) { conn in
                        self.connectionRow(conn)
                    }
                }
            }
        }
    }

    var activityControlCard: some View {
        VStack(alignment: .leading, spacing: MenuBarLayoutTokens.space4) {
            HStack(spacing: MenuBarLayoutTokens.space6) {
                Text(tr("ui.tab.activity"))
                    .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(nativeTertiaryLabel)

                Spacer(minLength: 0)

                self.compactTopIcon(
                    "arrow.clockwise",
                    label: tr("ui.action.refresh"),
                    toneOverride: nativeInfo)
                {
                    await appState.refreshConnections()
                }
                .help(tr("ui.action.refresh"))

                self.compactTopIcon(
                    "xmark",
                    label: tr("ui.action.close_all"),
                    warning: true)
                {
                    await appState.closeAllConnections()
                }
                .help(tr("ui.action.close_all"))
            }

            TextField(tr("ui.placeholder.filter_connection"), text: $networkFilterText)
                .textFieldStyle(.roundedBorder)
                .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)

            HStack(spacing: MenuBarLayoutTokens.space6) {
                self.activityFilterMenu
                self.activitySortMenu

                self.compactTopIcon(
                    "line.3.horizontal.decrease.circle",
                    label: tr("ui.action.reset_network_filters"))
                {
                    self.resetNetworkControls()
                }
                .help(tr("ui.action.reset_network_filters"))
                .disabled(!self.hasActiveNetworkControls)

                Spacer(minLength: 0)

                self.networkCountSummaryBadge
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuRowPadding(vertical: MenuBarLayoutTokens.space4)
    }

    var activityFilterMenu: some View {
        self.compactSelectionMenu(
            selection: self.networkTransportFilter,
            options: NetworkTransportFilter.allCases,
            symbol: "line.3.horizontal.decrease.circle",
            helpText: tr("ui.network.filter.transport"),
            optionTitle: { self.tr($0.titleKey) },
            onSelect: { self.networkTransportFilter = $0 })
    }

    var activitySortMenu: some View {
        self.compactSelectionMenu(
            selection: self.networkSortOption,
            options: NetworkSortOption.allCases,
            symbol: "arrow.up.arrow.down",
            helpText: tr("ui.network.sort.label"),
            optionTitle: { self.tr($0.titleKey) },
            onSelect: { self.networkSortOption = $0 })
    }

    var networkCountSummaryBadge: some View {
        self.fractionSummaryBadge(
            current: self.visibleConnections.count,
            total: min(self.appState.connections.count, 120))
    }

    var trimmedNetworkKeyword: String {
        self.networkFilterText.trimmed
    }

    var hasActiveNetworkControls: Bool {
        !self.trimmedNetworkKeyword.isEmpty || self.networkTransportFilter != .all || self.networkSortOption != .default
    }

    func resetNetworkControls() {
        self.networkFilterText = ""
        self.networkTransportFilter = .all
        self.networkSortOption = .default
    }

    func sortedConnections(_ source: [ConnectionSummary]) -> [ConnectionSummary] {
        switch self.networkSortOption {
        case .default:
            source
        case .newest:
            source.sorted { lhs, rhs in
                let left = self.connectionSortTimestamp(lhs.start) ?? -1
                let right = self.connectionSortTimestamp(rhs.start) ?? -1
                if left != right { return left > right }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
        case .oldest:
            source.sorted { lhs, rhs in
                let left = self.connectionSortTimestamp(lhs.start) ?? .greatestFiniteMagnitude
                let right = self.connectionSortTimestamp(rhs.start) ?? .greatestFiniteMagnitude
                if left != right { return left < right }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
        case .uploadDesc:
            self.connectionsSortedByTraffic(source) { $0.upload ?? 0 }
        case .downloadDesc:
            self.connectionsSortedByTraffic(source) { $0.download ?? 0 }
        case .totalDesc:
            self.connectionsSortedByTraffic(source) { ($0.upload ?? 0) + ($0.download ?? 0) }
        }
    }

    private func connectionsSortedByTraffic(
        _ source: [ConnectionSummary],
        _ metric: (ConnectionSummary) -> Int64) -> [ConnectionSummary]
    {
        source.sorted { lhs, rhs in
            let left = metric(lhs)
            let right = metric(rhs)
            if left != right { return left > right }
            return (self.connectionSortTimestamp(lhs.start) ?? -1) > (self.connectionSortTimestamp(rhs.start) ?? -1)
        }
    }

    func connectionSortTimestamp(_ start: String?) -> TimeInterval? {
        guard let value = start.trimmedNonEmpty else { return nil }
        if let date = Self.activityISO8601WithFractional.date(from: value) {
            return date.timeIntervalSince1970
        }
        return Self.activityISO8601Basic.date(from: value)?.timeIntervalSince1970
    }

    func refreshVisibleConnections() {
        let source = self.appState.connections.prefix(120)
        let keyword = self.trimmedNetworkKeyword

        let filtered: [ConnectionSummary] = if keyword.isEmpty, self.networkTransportFilter == .all {
            Array(source)
        } else {
            source.filter { conn in
                guard self.networkTransportFilter.matches(conn.metadata?.network) else { return false }
                guard keyword.isEmpty || self.connectionSearchText(for: conn).localizedStandardContains(keyword) else {
                    return false
                }
                return true
            }
        }

        let nextConnections = self.sortedConnections(filtered)
        guard nextConnections != self.visibleConnections else { return }
        self.visibleConnections = nextConnections
    }

    func connectionRow(_ conn: ConnectionSummary) -> some View {
        let visual = self.connectionVisual(for: conn)
        let hovered = hoveredConnectionID == conn.id
        let hostText = conn.metadata?.host.trimmedNonEmpty
            ?? conn.metadata?.destinationIP.trimmedNonEmpty
            ?? tr("ui.common.na")
        let networkType = conn.metadata?.network.trimmedNonEmpty?.uppercased() ?? "--"
        let timeText = self.connectionTimeOnly(conn.start)
        let upText = ValueFormatter.bytesCompactNoSpace(conn.upload ?? 0)
        let downText = ValueFormatter.bytesCompactNoSpace(conn.download ?? 0)
        let parsedRule = self.parseConnectionRule(conn.rule)
        let ruleTypeText = self.connectionRuleTypeText(conn.rule, fallback: parsedRule?.type)
        let rulePayloadText = conn.rulePayload.trimmedNonEmpty
            ?? parsedRule?.payload.trimmedNonEmpty
            ?? "--"

        return HStack(alignment: .center, spacing: MenuBarLayoutTokens.space6) {
            Image(systemName: visual.symbol)
                .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .semibold))
                .foregroundStyle(visual.color)
                .frame(
                    width: MenuBarLayoutTokens.rowLeadingIcon,
                    height: MenuBarLayoutTokens.rowLeadingIcon,
                    alignment: .center)

            VStack(alignment: .leading, spacing: MenuBarLayoutTokens.space2) {
                self.connectionRowTopLine(host: hostText, ruleType: ruleTypeText, rulePayload: rulePayloadText)
                self.connectionRowMetrics(time: timeText, network: networkType, up: upText, down: downText)
                self.activityChainsLine(parts: self.connectionChainsParts(conn.chains))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.connectionRowCloseButton(id: conn.id, hovered: hovered)
        }
        .padding(.horizontal, MenuBarLayoutTokens.space4)
        .padding(.vertical, MenuBarLayoutTokens.space2)
        .background(nativeHoverRowBackground(hovered))
        .onHover { hoveredConnectionID = self.nextHovered(
            current: hoveredConnectionID, target: conn.id, isHovering: $0) }
        .contextMenu { self.connectionRowContextMenu(conn) }
    }

    private func connectionRowTopLine(host: String, ruleType: String, rulePayload: String) -> some View {
        GeometryReader { proxy in
            let layout = self.activityTopLineLayout(
                totalWidth: max(proxy.size.width, 0),
                ruleText: ruleType,
                payloadText: rulePayload)

            HStack(spacing: ActivityLayout.topLineSpacing) {
                Text(host)
                    .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(nativePrimaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: layout.hostWidth, alignment: .leading)

                HStack(spacing: ActivityLayout.topMetaSpacing) {
                    self.activityTopBadge(text: ruleType)
                        .frame(width: layout.ruleWidth, alignment: .trailing)
                    self.activityTopPayload(text: rulePayload)
                        .frame(width: layout.payloadWidth, alignment: .trailing)
                }
                .frame(
                    width: layout.ruleWidth + ActivityLayout.topMetaSpacing + layout.payloadWidth,
                    alignment: .trailing)
            }
        }
        .frame(height: ActivityLayout.rowLineHeight)
    }

    private func connectionRowMetrics(time: String, network: String, up: String, down: String) -> some View {
        GeometryReader { proxy in
            let totalWidth = max(proxy.size.width, 0)
            let columnWidth = max((totalWidth - (ActivityLayout.secondLineSpacing * 3)) / 4, 0)

            HStack(spacing: ActivityLayout.secondLineSpacing) {
                self.activityMetricColumn(symbol: "clock", text: time, fallback: tr("ui.common.na"), width: columnWidth)
                self.activityMetricColumn(
                    symbol: "network",
                    text: network,
                    fallback: tr("ui.common.na"),
                    width: columnWidth)
                self.activityMetricColumn(
                    symbol: "arrow.up",
                    text: up,
                    symbolColor: nativeInfo.opacity(MenuBarLayoutTokens.Opacity.solid),
                    spacing: 0,
                    truncation: .tail,
                    width: columnWidth)
                self.activityMetricColumn(
                    symbol: "arrow.down",
                    text: down,
                    symbolColor: nativePositive.opacity(MenuBarLayoutTokens.Opacity.solid),
                    spacing: 0,
                    truncation: .tail,
                    width: columnWidth)
            }
        }
        .frame(height: ActivityLayout.rowLineHeight)
    }

    private func connectionRowCloseButton(id: String, hovered: Bool) -> some View {
        Button {
            Task { await appState.closeConnection(id: id) }
        } label: {
            Image(systemName: "xmark")
                .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
                .frame(width: 10, height: 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovered ? nativeSecondaryLabel : nativeTertiaryLabel)
        .frame(width: 12, height: 12)
        .opacity(hovered ? 1 : 0)
        .animation(.easeInOut(duration: 0.14), value: hovered)
    }

    @ViewBuilder
    private func connectionRowContextMenu(_ conn: ConnectionSummary) -> some View {
        Button(role: .destructive) {
            Task { await appState.closeConnection(id: conn.id) }
        } label: {
            Label(tr("ui.action.close_connection"), systemImage: "xmark.circle")
        }

        if let host = appState.resolvedConnectionHost(for: conn) {
            Button {
                appState.copyConnectionHost(host)
            } label: {
                Label(tr("ui.action.copy_host"), systemImage: "doc.on.doc")
            }
        }

        Button {
            appState.copyConnectionID(conn.id)
        } label: {
            Label(tr("ui.action.copy_connection_id"), systemImage: "number")
        }
    }

    func activityMetricColumn(
        symbol: String,
        text: String,
        symbolColor: Color = .secondary,
        textColor: Color = .secondary,
        fallback: String? = nil,
        spacing: CGFloat = MenuBarLayoutTokens.space2,
        truncation: Text.TruncationMode = .middle,
        width: CGFloat) -> some View
    {
        let renderedText = text.isEmpty ? (fallback ?? "") : text

        return HStack(spacing: spacing) {
            Image(systemName: symbol)
                .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 10, alignment: .leading)
            Text(renderedText)
                .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .regular))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(truncation)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }

    func activityTopBadge(text: String) -> some View {
        Text(text)
            .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
            .foregroundStyle(nativeSecondaryLabel)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(MenuBarLayoutTokens.minimumScale)
            .padding(.horizontal, MenuBarLayoutTokens.space2)
            .padding(.vertical, MenuBarLayoutTokens.space1)
            .background(nativeBadgeCapsule())
    }

    func activityTopPayload(text: String) -> some View {
        Text(text)
            .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
            .foregroundStyle(nativeSecondaryLabel)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(MenuBarLayoutTokens.minimumScale)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    func activityChainsLine(parts: [String]) -> some View {
        let chainText = parts.joined(separator: " > ")
        let displayText = parts.isEmpty ? tr("ui.common.na") : chainText

        return HStack(spacing: MenuBarLayoutTokens.space2) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeSecondaryLabel)
                .frame(width: 10, alignment: .leading)

            Text(displayText)
                .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .regular))
                .foregroundStyle(nativeSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: ActivityLayout.rowLineHeight, alignment: .leading)
    }

    func activityTopLineLayout(
        totalWidth: CGFloat,
        ruleText: String,
        payloadText: String) -> (hostWidth: CGFloat, ruleWidth: CGFloat, payloadWidth: CGFloat)
    {
        guard totalWidth > 0 else { return (0, 0, 0) }

        let hostMinWidth = floor(totalWidth * 0.5)
        let metaMaxWidth = max(totalWidth - ActivityLayout.topLineSpacing - hostMinWidth, 0)

        var ruleWidth = max(
            ActivityLayout.topRuleMinWidth,
            self
                .activityMonospacedTextWidth(ruleText, size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold) +
                4)
        var payloadWidth = max(
            ActivityLayout.topPayloadMinWidth,
            self.activityMonospacedTextWidth(payloadText, size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
        let desiredMetaWidth = ruleWidth + ActivityLayout.topMetaSpacing + payloadWidth

        if desiredMetaWidth > metaMaxWidth {
            var overflow = desiredMetaWidth - metaMaxWidth

            let payloadReducible = max(payloadWidth - ActivityLayout.topPayloadMinWidth, 0)
            let payloadReduction = min(overflow, payloadReducible)
            payloadWidth -= payloadReduction
            overflow -= payloadReduction

            if overflow > 0 {
                let ruleReducible = max(ruleWidth - ActivityLayout.topRuleMinWidth, 0)
                let ruleReduction = min(overflow, ruleReducible)
                ruleWidth -= ruleReduction
                overflow -= ruleReduction
            }

            if overflow > 0 {
                let metaContentWidth = max(metaMaxWidth - ActivityLayout.topMetaSpacing, 0)
                if metaContentWidth <= 0 {
                    ruleWidth = 0
                    payloadWidth = 0
                } else {
                    let total = max(ruleWidth + payloadWidth, 1)
                    let ruleRatio = ruleWidth / total
                    ruleWidth = floor(metaContentWidth * ruleRatio)
                    payloadWidth = max(metaContentWidth - ruleWidth, 0)
                }
            }
        }

        let metaWidth = ruleWidth + ActivityLayout.topMetaSpacing + payloadWidth
        let hostWidth = max(totalWidth - ActivityLayout.topLineSpacing - metaWidth, hostMinWidth)
        return (hostWidth, ruleWidth, payloadWidth)
    }

    func activityMonospacedTextWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    func connectionRuleTypeText(_ raw: String?, fallback: String?) -> String {
        let candidate = fallback.trimmedNonEmpty ?? raw.trimmedNonEmpty ?? ""
        guard !candidate.isEmpty else { return "--" }

        let normalized = candidate.uppercased()
        if normalized == "MATCH" || normalized == "FINAL" { return "--" }
        return candidate
    }

    func connectionChainsParts(_ chains: [String]?) -> [String] {
        Array((chains ?? []).compactMap(\.trimmedNonEmpty).reversed())
    }

    func parseConnectionRule(_ raw: String?) -> (type: String, payload: String?)? {
        guard let raw = raw.trimmedNonEmpty else {
            return nil
        }

        if let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close {
            let type = raw[..<open].trimmed
            let payload = raw[raw.index(after: open)..<close].trimmed
            if let type = type.nonEmpty {
                return (type, payload.nonEmpty)
            }
        }

        let commaParts = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        if commaParts.count == 2 {
            let type = commaParts[0].trimmed
            let payload = commaParts[1].trimmed
            if let type = type.nonEmpty {
                return (type, payload.nonEmpty)
            }
        }

        return (raw, nil)
    }

    func connectionTimeOnly(_ input: String?) -> String {
        let full = ValueFormatter.dateTimeFromISO(input)
        guard full != "--" else { return full }
        return full.split(separator: " ").last.map(String.init) ?? full
    }

    func connectionVisual(for conn: ConnectionSummary) -> (symbol: String, color: Color) {
        let host = conn.metadata?.host?.lowercased() ?? ""
        let network = conn.metadata?.network?.lowercased() ?? ""

        if host.contains("google") || host.contains("gstatic") {
            return ("shield.fill", nativePurple.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        if host.contains("icloud") || host.contains("apple") {
            return ("icloud.fill", nativeInfo.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        if host.contains("github") {
            return ("terminal.fill", nativeIndigo.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        if host.contains("twitter") || host.contains("x.com") {
            return ("lock.fill", nativePositive.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        if host.contains("amazon") {
            return ("cart.fill", nativeWarning.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        if network.contains("udp") {
            return ("dot.radiowaves.left.and.right", nativeTeal.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        if network.contains("tcp") {
            return ("network", nativeInfo.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        return ("globe", nativeSecondaryLabel)
    }

    func connectionSearchText(for conn: ConnectionSummary) -> String {
        let host = conn.metadata?.host ?? ""
        let destinationIP = conn.metadata?.destinationIP ?? ""
        let sourceIP = conn.metadata?.sourceIP ?? ""
        let network = conn.metadata?.network ?? ""
        let id = conn.id
        let rule = conn.rule ?? ""
        let rulePayload = conn.rulePayload ?? ""
        let chains = self.connectionChainsParts(conn.chains).joined(separator: " > ")
        let start = conn.start ?? ""
        return "\(host) \(destinationIP) \(sourceIP) \(network) \(id) \(rule) \(rulePayload) \(chains) \(start)"
    }
}
