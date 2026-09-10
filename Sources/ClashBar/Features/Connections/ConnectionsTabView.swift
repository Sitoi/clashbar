import AppKit
import MihomoKit
import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct ConnectionsTabView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var connectionsStore: ConnectionsStore
    @AppStorage("clashbar.connections.transport_filter") private var storedTransportFilterRawValue =
        ConnectionsTransportFilter.all.rawValue
    @AppStorage("clashbar.connections.sort_option") private var storedSortOptionRawValue =
        ConnectionsSortOption.default.rawValue

    private enum ConnectionsLayout {
        static let topLineSpacing: CGFloat = T.space2
        static let topMetaSpacing: CGFloat = T.space1
        static let secondLineSpacing: CGFloat = T.space2
        static let rowLineHeight: CGFloat = 16
        static let topRuleMinWidth: CGFloat = 26
        static let topPayloadMinWidth: CGFloat = 14
        static let rowContentWidth: CGFloat =
            T.panelWidth
                - (T.space8 * 2)
                - (T.space4 * 2)
                - T.rowLeadingIcon
                - (T.space6 * 2)
                - 12
    }

    private static var textWidthCache: [String: CGFloat] = [:]

    var body: some View {
        let connections = self.connectionsStore.visibleConnections

        return VStack(alignment: .leading, spacing: T.space6) {
            self.connectionsControlCard

            if connections.isEmpty {
                emptyCard(self.tr("ui.empty.connections"))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(connections) { conn in
                        self.connectionRow(conn)
                        if conn.id != connections.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .onAppear {
            self.restoreStoredPreferences()
        }
    }

    private func restoreStoredPreferences() {
        let transportFilter = ConnectionsTransportFilter(rawValue: self.storedTransportFilterRawValue) ?? .all
        let sortOption = ConnectionsSortOption(rawValue: self.storedSortOptionRawValue) ?? .default

        self.connectionsStore.transportFilter = transportFilter
        self.connectionsStore.sortOption = sortOption

        if self.storedTransportFilterRawValue != transportFilter.rawValue {
            self.storedTransportFilterRawValue = transportFilter.rawValue
        }
        if self.storedSortOptionRawValue != sortOption.rawValue {
            self.storedSortOptionRawValue = sortOption.rawValue
        }
    }

    private func selectTransportFilter(_ filter: ConnectionsTransportFilter) {
        self.connectionsStore.transportFilter = filter
        self.storedTransportFilterRawValue = filter.rawValue
    }

    private func selectSortOption(_ sortOption: ConnectionsSortOption) {
        self.connectionsStore.sortOption = sortOption
        self.storedSortOptionRawValue = sortOption.rawValue
    }

    var connectionsControlCard: some View {
        VStack(alignment: .leading, spacing: T.space4) {
            HStack(spacing: T.space6) {
                self.connectionsFilterMenu
                self.connectionsSortMenu

                Spacer(minLength: 0)

                self.fractionSummaryBadge(
                    current: self.connectionsStore.visibleConnections.count,
                    total: min(self.connectionsStore.connections.count, 120))

                self.compactTopIcon(
                    "xmark",
                    label: self.tr("ui.action.close_all"),
                    warning: true)
                {
                    await self.connectionsStore.closeAllConnections()
                }
                .help(self.tr("ui.action.close_all"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField(self.tr("ui.placeholder.filter_connection"), text: self.$connectionsStore.filterText)
                .textFieldStyle(.roundedBorder)
                .font(.app(size: T.FontSize.body, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)
        }
        .menuRowPadding(vertical: T.space4)
    }

    var connectionsFilterMenu: some View {
        self.compactSelectionMenu(.init(
            selection: self.connectionsStore.transportFilter,
            options: ConnectionsTransportFilter.allCases,
            symbol: "line.3.horizontal.decrease.circle",
            helpText: self.tr("ui.network.filter.transport"),
            optionTitle: { self.tr($0.titleKey) },
            onSelect: { self.selectTransportFilter($0) }))
    }

    var connectionsSortMenu: some View {
        self.compactSelectionMenu(.init(
            selection: self.connectionsStore.sortOption,
            options: ConnectionsSortOption.allCases,
            symbol: "arrow.up.arrow.down",
            helpText: self.tr("ui.network.sort"),
            optionTitle: { self.tr($0.titleKey) },
            onSelect: { self.selectSortOption($0) }))
    }

    func connectionRow(_ conn: ConnectionSummary) -> some View {
        let visual = self.connectionVisual(for: conn)
        let hovered = self.connectionsStore.hoveredConnectionID == conn.id
        let hostText = conn.metadata?.host?.trimmedNonEmpty
            ?? conn.metadata?.destinationIP?.trimmedNonEmpty
            ?? self.tr("ui.common.na")
        let networkType = conn.metadata?.network?.trimmedNonEmpty?.uppercased() ?? "--"
        let timeText = self.connectionTimeOnly(conn.start)
        let upText = ValueFormatter.bytesCompactNoSpace(conn.upload ?? 0)
        let downText = ValueFormatter.bytesCompactNoSpace(conn.download ?? 0)
        let parsedRule = self.parseConnectionRule(conn.rule)
        let ruleTypeText = self.connectionRuleTypeText(conn.rule, fallback: parsedRule?.type)
        let rulePayloadText = conn.rulePayload?.trimmedNonEmpty
            ?? parsedRule?.payload?.trimmedNonEmpty
            ?? "--"

        return HStack(alignment: .center, spacing: T.space6) {
            Image(systemName: visual.symbol)
                .font(.app(size: T.FontSize.body, weight: .semibold))
                .foregroundStyle(visual.color)
                .frame(
                    width: T.rowLeadingIcon,
                    height: T.rowLeadingIcon,
                    alignment: .center)

            VStack(alignment: .leading, spacing: T.space2) {
                self.connectionRowTopLine(host: hostText, ruleType: ruleTypeText, rulePayload: rulePayloadText)
                self.connectionRowMetrics(time: timeText, network: networkType, up: upText, down: downText)
                self.connectionsChainsLine(parts: self.connectionChainsParts(conn.chains))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.connectionRowCloseButton(id: conn.id, hovered: hovered)
        }
        .padding(.horizontal, T.space4)
        .padding(.vertical, T.space2)
        .background(self.nativeHoverRowBackground(hovered))
        .onHover { self.connectionsStore.hoveredConnectionID = self.nextHovered(
            current: self.connectionsStore.hoveredConnectionID, target: conn.id, isHovering: $0) }
        .contextMenu { self.connectionRowContextMenu(conn) }
    }

    private func connectionRowTopLine(host: String, ruleType: String, rulePayload: String) -> some View {
        let layout = self.connectionsTopLineLayout(
            totalWidth: ConnectionsLayout.rowContentWidth,
            ruleText: ruleType,
            payloadText: rulePayload)

        return HStack(spacing: ConnectionsLayout.topLineSpacing) {
            Text(host)
                .font(.app(size: T.FontSize.body, weight: .semibold))
                .foregroundStyle(nativePrimaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: layout.hostWidth, alignment: .leading)

            HStack(spacing: ConnectionsLayout.topMetaSpacing) {
                self.connectionsTopBadge(text: ruleType)
                    .frame(width: layout.ruleWidth, alignment: .trailing)
                self.connectionsTopPayload(text: rulePayload)
                    .frame(width: layout.payloadWidth, alignment: .trailing)
            }
            .frame(
                width: layout.ruleWidth + ConnectionsLayout.topMetaSpacing + layout.payloadWidth,
                alignment: .trailing)
        }
        .frame(height: ConnectionsLayout.rowLineHeight)
    }

    private func connectionRowMetrics(time: String, network: String, up: String, down: String) -> some View {
        let columnWidth = max(
            (ConnectionsLayout.rowContentWidth - (ConnectionsLayout.secondLineSpacing * 3)) / 4,
            0)

        return HStack(spacing: ConnectionsLayout.secondLineSpacing) {
            self.connectionsMetricColumn(
                symbol: "clock",
                text: time,
                fallback: self.tr("ui.common.na"),
                width: columnWidth)
            self.connectionsMetricColumn(
                symbol: "network",
                text: network,
                fallback: self.tr("ui.common.na"),
                width: columnWidth)
            self.connectionsMetricColumn(
                symbol: "arrow.up",
                text: up,
                symbolColor: nativeInfo.opacity(T.Opacity.solid),
                textColor: nativeInfo.opacity(T.Opacity.solid),
                spacing: 0,
                truncation: .tail,
                width: columnWidth)
            self.connectionsMetricColumn(
                symbol: "arrow.down",
                text: down,
                symbolColor: nativePositive.opacity(T.Opacity.solid),
                textColor: nativePositive.opacity(T.Opacity.solid),
                spacing: 0,
                truncation: .tail,
                width: columnWidth)
        }
        .frame(height: ConnectionsLayout.rowLineHeight)
    }

    private func connectionRowCloseButton(id: String, hovered: Bool) -> some View {
        Button {
            Task { await self.connectionsStore.closeConnection(id: id) }
        } label: {
            Image(systemName: "xmark")
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .frame(width: 10, height: 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovered ? nativeSecondaryLabel : nativeTertiaryLabel)
        .frame(width: 12, height: 12)
        .opacity(hovered ? 1 : 0)
    }

    @ViewBuilder
    private func connectionRowContextMenu(_ conn: ConnectionSummary) -> some View {
        Button(role: .destructive) {
            Task { await self.connectionsStore.closeConnection(id: conn.id) }
        } label: {
            Label(self.tr("ui.action.close_connection"), systemImage: "xmark.circle")
        }

        if let host = self.connectionsStore.resolvedConnectionHost(for: conn) {
            Button {
                self.connectionsStore.copyConnectionHost(host)
            } label: {
                Label(self.tr("ui.action.copy_host"), systemImage: "doc.on.doc")
            }
        }

        Button {
            self.connectionsStore.copyConnectionID(conn.id)
        } label: {
            Label(self.tr("ui.action.copy_connection_id"), systemImage: "number")
        }
    }

    func connectionsMetricColumn(
        symbol: String,
        text: String,
        symbolColor: Color = .secondary,
        textColor: Color = .secondary,
        fallback: String? = nil,
        spacing: CGFloat = T.space2,
        truncation: Text.TruncationMode = .middle,
        width: CGFloat) -> some View
    {
        let renderedText = text.isEmpty ? (fallback ?? "") : text

        return HStack(spacing: spacing) {
            Image(systemName: symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 10, alignment: .leading)
            Text(renderedText)
                .font(.app(size: T.FontSize.caption, weight: .regular))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(truncation)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }

    func connectionsTopBadge(text: String) -> some View {
        Text(text)
            .font(.app(size: T.FontSize.caption, weight: .semibold))
            .foregroundStyle(nativeSecondaryLabel)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(T.minimumScale)
            .padding(.horizontal, T.space2)
            .padding(.vertical, T.space1)
            .background(nativeBadgeCapsule())
    }

    func connectionsTopPayload(text: String) -> some View {
        Text(text)
            .font(.app(size: T.FontSize.caption, weight: .medium))
            .foregroundStyle(nativeSecondaryLabel)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(T.minimumScale)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    func connectionsChainsLine(parts: [String]) -> some View {
        let chainText = parts.joined(separator: " > ")
        let displayText = parts.isEmpty ? self.tr("ui.common.na") : chainText

        return HStack(spacing: T.space2) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeSecondaryLabel)
                .frame(width: 10, alignment: .leading)

            Text(displayText)
                .font(.app(size: T.FontSize.caption, weight: .regular))
                .foregroundStyle(nativeSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: ConnectionsLayout.rowLineHeight, alignment: .leading)
    }

    func connectionsTopLineLayout(
        totalWidth: CGFloat,
        ruleText: String,
        payloadText: String) -> (hostWidth: CGFloat, ruleWidth: CGFloat, payloadWidth: CGFloat)
    {
        guard totalWidth > 0 else { return (0, 0, 0) }

        let hostMinWidth = floor(totalWidth * 0.5)
        let metaMaxWidth = max(totalWidth - ConnectionsLayout.topLineSpacing - hostMinWidth, 0)

        var ruleWidth = max(
            ConnectionsLayout.topRuleMinWidth,
            self
                .connectionsMonospacedTextWidth(
                    ruleText,
                    size: T.FontSize.caption,
                    weight: .semibold) +
                4)
        var payloadWidth = max(
            ConnectionsLayout.topPayloadMinWidth,
            self.connectionsMonospacedTextWidth(
                payloadText,
                size: T.FontSize.caption,
                weight: .medium))
        let desiredMetaWidth = ruleWidth + ConnectionsLayout.topMetaSpacing + payloadWidth

        if desiredMetaWidth > metaMaxWidth {
            var overflow = desiredMetaWidth - metaMaxWidth

            let payloadReducible = max(payloadWidth - ConnectionsLayout.topPayloadMinWidth, 0)
            let payloadReduction = min(overflow, payloadReducible)
            payloadWidth -= payloadReduction
            overflow -= payloadReduction

            if overflow > 0 {
                let ruleReducible = max(ruleWidth - ConnectionsLayout.topRuleMinWidth, 0)
                let ruleReduction = min(overflow, ruleReducible)
                ruleWidth -= ruleReduction
                overflow -= ruleReduction
            }

            if overflow > 0 {
                let metaContentWidth = max(metaMaxWidth - ConnectionsLayout.topMetaSpacing, 0)
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

        let metaWidth = ruleWidth + ConnectionsLayout.topMetaSpacing + payloadWidth
        let hostWidth = max(totalWidth - ConnectionsLayout.topLineSpacing - metaWidth, hostMinWidth)
        return (hostWidth, ruleWidth, payloadWidth)
    }

    func connectionsMonospacedTextWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let cacheKey = "\(text)\0\(size)\0\(weight.rawValue)"
        if let cached = Self.textWidthCache[cacheKey] {
            return cached
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
        ]
        let width = ceil((text as NSString).size(withAttributes: attributes).width)
        Self.textWidthCache[cacheKey] = width
        return width
    }

    func connectionRuleTypeText(_ raw: String?, fallback: String?) -> String {
        let candidate = fallback?.trimmedNonEmpty ?? raw?.trimmedNonEmpty ?? ""
        guard !candidate.isEmpty else { return "--" }

        let normalized = candidate.uppercased()
        if normalized == "MATCH" || normalized == "FINAL" {
            return "--"
        }
        return candidate
    }

    func connectionChainsParts(_ chains: [String]?) -> [String] {
        Array((chains ?? []).compactMap(\.trimmedNonEmpty).reversed())
    }

    func parseConnectionRule(_ raw: String?) -> (type: String, payload: String?)? {
        guard let raw = raw?.trimmedNonEmpty else {
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
            return ("shield.fill", nativePurple.opacity(T.Opacity.solid))
        }
        if host.contains("icloud") || host.contains("apple") {
            return ("icloud.fill", nativeInfo.opacity(T.Opacity.solid))
        }
        if host.contains("github") {
            return ("terminal.fill", nativeIndigo.opacity(T.Opacity.solid))
        }
        if host.contains("twitter") || host.contains("x.com") {
            return ("lock.fill", nativePositive.opacity(T.Opacity.solid))
        }
        if host.contains("amazon") {
            return ("cart.fill", nativeWarning.opacity(T.Opacity.solid))
        }
        if network.contains("udp") {
            return ("dot.radiowaves.left.and.right", nativeTeal.opacity(T.Opacity.solid))
        }
        if network.contains("tcp") {
            return ("network", nativeInfo.opacity(T.Opacity.solid))
        }
        return ("globe", nativeSecondaryLabel)
    }
}
