import AppKit
import SwiftUI

extension MenuBarRoot {
    private enum ActivityLayout {
        static let topLineSpacing: CGFloat = 2
        static let topMetaSpacing: CGFloat = 1
        static let secondLineSpacing: CGFloat = 2
        static let rowLineHeight: CGFloat = 15
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
        let connections = self.filteredConnections

        return VStack(alignment: .leading, spacing: MenuBarLayoutTokens.sectionGap) {
            self.activityControlCard

            if connections.isEmpty {
                emptyCard(tr("ui.empty.connections"))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(connections.enumerated()), id: \.element.id) { index, conn in
                        self.connectionRow(conn)

                        if index < connections.count - 1 {
                            Rectangle()
                                .fill(nativeSeparator)
                                .frame(height: MenuBarLayoutTokens.hairline)
                        }
                    }
                }
            }
        }
    }

    var activityControlCard: some View {
        VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense + 2) {
            HStack(spacing: MenuBarLayoutTokens.hDense) {
                Text(tr("ui.tab.activity"))
                    .font(.appSystem(size: 12, weight: .bold))
                    .tracking(1.2)
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
                .font(.appSystem(size: 12, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)

            HStack(spacing: MenuBarLayoutTokens.hDense) {
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
        .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
    }

    var activityFilterMenu: some View {
        Menu {
            ForEach(NetworkTransportFilter.allCases) { filter in
                Button {
                    self.networkTransportFilter = filter
                } label: {
                    if self.networkTransportFilter == filter {
                        Label(self.tr(filter.titleKey), systemImage: "checkmark")
                    } else {
                        Text(self.tr(filter.titleKey))
                    }
                }
            }
        } label: {
            Label(self.tr(self.networkTransportFilter.titleKey), systemImage: "line.3.horizontal.decrease.circle")
                .font(.appSystem(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(tr("ui.network.filter.transport"))
    }

    var activitySortMenu: some View {
        Menu {
            ForEach(NetworkSortOption.allCases) { option in
                Button {
                    self.networkSortOption = option
                } label: {
                    if self.networkSortOption == option {
                        Label(self.tr(option.titleKey), systemImage: "checkmark")
                    } else {
                        Text(self.tr(option.titleKey))
                    }
                }
            }
        } label: {
            Label(self.tr(self.networkSortOption.titleKey), systemImage: "arrow.up.arrow.down")
                .font(.appSystem(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(tr("ui.network.sort.label"))
    }

    var networkCountSummaryBadge: some View {
        HStack(spacing: MenuBarLayoutTokens.hMicro) {
            Text("\(self.filteredConnections.count)")
                .font(.appMonospaced(size: 11, weight: .bold))
            Text("/")
                .font(.appMonospaced(size: 10, weight: .medium))
            Text("\(self.networkSourceConnections.count)")
                .font(.appMonospaced(size: 11, weight: .medium))
        }
        .foregroundStyle(nativeSecondaryLabel)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(nativeBadgeCapsule())
    }

    var trimmedNetworkKeyword: String {
        self.networkFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasActiveNetworkControls: Bool {
        !self.trimmedNetworkKeyword.isEmpty || self.networkTransportFilter != .all || self.networkSortOption != .default
    }

    func resetNetworkControls() {
        self.networkFilterText = ""
        self.networkTransportFilter = .all
        self.networkSortOption = .default
    }

    var networkSourceConnections: [ConnectionSummary] {
        Array(appState.connections.prefix(120))
    }

    var filteredConnections: [ConnectionSummary] {
        let keyword = self.trimmedNetworkKeyword
        let filtered = self.networkSourceConnections.filter { conn in
            guard self.networkTransportFilter.matches(conn.metadata?.network) else { return false }
            guard keyword.isEmpty || self.connectionSearchText(for: conn).localizedStandardContains(keyword) else {
                return false
            }
            return true
        }
        return self.sortedConnections(filtered)
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
            source.sorted { lhs, rhs in
                let left = lhs.upload ?? 0
                let right = rhs.upload ?? 0
                if left != right { return left > right }
                return (self.connectionSortTimestamp(lhs.start) ?? -1) > (self.connectionSortTimestamp(rhs.start) ?? -1)
            }
        case .downloadDesc:
            source.sorted { lhs, rhs in
                let left = lhs.download ?? 0
                let right = rhs.download ?? 0
                if left != right { return left > right }
                return (self.connectionSortTimestamp(lhs.start) ?? -1) > (self.connectionSortTimestamp(rhs.start) ?? -1)
            }
        case .totalDesc:
            source.sorted { lhs, rhs in
                let left = (lhs.upload ?? 0) + (lhs.download ?? 0)
                let right = (rhs.upload ?? 0) + (rhs.download ?? 0)
                if left != right { return left > right }
                return (self.connectionSortTimestamp(lhs.start) ?? -1) > (self.connectionSortTimestamp(rhs.start) ?? -1)
            }
        }
    }

    func connectionSortTimestamp(_ start: String?) -> TimeInterval? {
        guard let value = self.trimmedNonEmpty(start) else { return nil }
        if let date = Self.activityISO8601WithFractional.date(from: value) {
            return date.timeIntervalSince1970
        }
        return Self.activityISO8601Basic.date(from: value)?.timeIntervalSince1970
    }

    func connectionRow(_ conn: ConnectionSummary) -> some View {
        let visual = self.connectionVisual(for: conn)
        let hovered = hoveredConnectionID == conn.id
        let host = conn.metadata?.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationIP = conn.metadata?.destinationIP?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostText = self.trimmedNonEmpty(host) ?? self.trimmedNonEmpty(destinationIP) ?? tr("ui.common.na")
        let networkType = self.trimmedNonEmpty(conn.metadata?.network)?.uppercased() ?? "--"
        let timeText = self.connectionTimeOnly(conn.start)
        let upText = ValueFormatter.bytesCompactNoSpace(conn.upload ?? 0)
        let downText = ValueFormatter.bytesCompactNoSpace(conn.download ?? 0)
        let parsedRule = self.parseConnectionRule(conn.rule)
        let ruleTypeText = self.connectionRuleTypeText(conn.rule, fallback: parsedRule?.type)
        let rulePayloadText = self.trimmedNonEmpty(conn.rulePayload)
            ?? self.trimmedNonEmpty(parsedRule?.payload)
            ?? "--"
        let chainParts = self.connectionChainsParts(conn.chains)

        return HStack(alignment: .center, spacing: MenuBarLayoutTokens.hDense) {
            Image(systemName: visual.symbol)
                .font(.appSystem(size: 12, weight: .semibold))
                .foregroundStyle(visual.color)
                .frame(
                    width: MenuBarLayoutTokens.rowLeadingIconColumnWidth,
                    height: MenuBarLayoutTokens.rowLeadingIconSize,
                    alignment: .center)

            VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense) {
                GeometryReader { proxy in
                    let layout = self.activityTopLineLayout(
                        totalWidth: max(proxy.size.width, 0),
                        ruleText: ruleTypeText,
                        payloadText: rulePayloadText)

                    HStack(spacing: ActivityLayout.topLineSpacing) {
                        Text(hostText)
                            .font(.appSystem(size: 12, weight: .semibold))
                            .foregroundStyle(nativePrimaryLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: layout.hostWidth, alignment: .leading)

                        HStack(spacing: ActivityLayout.topMetaSpacing) {
                            self.activityTopBadge(text: ruleTypeText)
                                .frame(width: layout.ruleWidth, alignment: .trailing)
                            self.activityTopPayload(text: rulePayloadText)
                                .frame(width: layout.payloadWidth, alignment: .trailing)
                        }
                        .frame(
                            width: layout.ruleWidth + ActivityLayout.topMetaSpacing + layout.payloadWidth,
                            alignment: .trailing)
                    }
                }
                .frame(height: ActivityLayout.rowLineHeight)

                GeometryReader { proxy in
                    let totalWidth = max(proxy.size.width, 0)
                    let columnWidth = max((totalWidth - (ActivityLayout.secondLineSpacing * 3)) / 4, 0)

                    HStack(spacing: ActivityLayout.secondLineSpacing) {
                        self.activityMetricColumn(
                            symbol: "clock",
                            text: timeText,
                            fallback: tr("ui.common.na"),
                            width: columnWidth)

                        self.activityMetricColumn(
                            symbol: "network",
                            text: networkType,
                            fallback: tr("ui.common.na"),
                            width: columnWidth)

                        self.activityMetricColumn(
                            symbol: "arrow.up",
                            text: upText,
                            symbolColor: nativeInfo.opacity(0.9),
                            spacing: 0,
                            truncation: .tail,
                            width: columnWidth)

                        self.activityMetricColumn(
                            symbol: "arrow.down",
                            text: downText,
                            symbolColor: nativePositive.opacity(0.9),
                            spacing: 0,
                            truncation: .tail,
                            width: columnWidth)
                    }
                }
                .frame(height: ActivityLayout.rowLineHeight)

                self.activityChainsLine(parts: chainParts)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await appState.closeConnection(id: conn.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.appSystem(size: 8, weight: .semibold))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(hovered ? nativeSecondaryLabel : nativeTertiaryLabel)
            .frame(width: 12, height: 12)
            .opacity(hovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.14), value: hovered)
        }
        .padding(.horizontal, MenuBarLayoutTokens.hRow)
        .padding(.vertical, MenuBarLayoutTokens.vDense + 1)
        .background(nativeHoverRowBackground(hovered))
        .onHover { isHovering in
            hoveredConnectionID = isHovering ? conn.id : (hoveredConnectionID == conn.id ? nil : hoveredConnectionID)
        }
        .contextMenu {
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
    }

    func activityMetricColumn(
        symbol: String,
        text: String,
        symbolColor: Color = .secondary,
        textColor: Color = .secondary,
        fallback: String? = nil,
        spacing: CGFloat = 2,
        truncation: Text.TruncationMode = .middle,
        width: CGFloat) -> some View
    {
        let renderedText = text.isEmpty ? (fallback ?? "") : text

        return HStack(spacing: spacing) {
            Image(systemName: symbol)
                .font(.appSystem(size: 9, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 10, alignment: .leading)
            Text(renderedText)
                .font(.appMonospaced(size: 10, weight: .regular))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(truncation)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }

    func activityTopBadge(text: String) -> some View {
        Text(text)
            .font(.appMonospaced(size: 9, weight: .semibold))
            .foregroundStyle(nativeSecondaryLabel)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(nativeBadgeCapsule())
    }

    func activityTopPayload(text: String) -> some View {
        Text(text)
            .font(.appMonospaced(size: 9, weight: .medium))
            .foregroundStyle(nativeSecondaryLabel)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    func activityChainsLine(parts: [String]) -> some View {
        let chainText = parts.joined(separator: " > ")
        let displayText = parts.isEmpty ? tr("ui.common.na") : chainText

        return HStack(spacing: 2) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.appSystem(size: 9, weight: .semibold))
                .foregroundStyle(nativeSecondaryLabel)
                .frame(width: 10, alignment: .leading)

            Text(displayText)
                .font(.appMonospaced(size: 10, weight: .regular))
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
            self.activityMonospacedTextWidth(ruleText, size: 9, weight: .semibold) + 4)
        var payloadWidth = max(
            ActivityLayout.topPayloadMinWidth,
            self.activityMonospacedTextWidth(payloadText, size: 9, weight: .medium))
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
        let candidate = self.trimmedNonEmpty(fallback) ?? self.trimmedNonEmpty(raw) ?? ""
        guard !candidate.isEmpty else { return "--" }

        let normalized = candidate.uppercased()
        if normalized == "MATCH" || normalized == "FINAL" { return "--" }
        return candidate
    }

    func connectionChainsParts(_ chains: [String]?) -> [String] {
        Array((chains ?? []).compactMap(self.trimmedNonEmpty).reversed())
    }

    func parseConnectionRule(_ raw: String?) -> (type: String, payload: String?)? {
        guard let raw = trimmedNonEmpty(raw) else {
            return nil
        }

        if let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close {
            let type = raw[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = raw[raw.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
            if !type.isEmpty {
                return (String(type), payload.isEmpty ? nil : String(payload))
            }
        }

        let commaParts = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        if commaParts.count == 2 {
            let type = commaParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = commaParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !type.isEmpty {
                return (String(type), payload.isEmpty ? nil : String(payload))
            }
        }

        return (raw, nil)
    }

    func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func connectionTimeOnly(_ input: String?) -> String {
        let full = ValueFormatter.dateTimeFromISO(input)
        guard full != "--" else { return full }
        return full.split(separator: " ").last.map(String.init) ?? full
    }

    func connectionVisual(for conn: ConnectionSummary) -> (symbol: String, color: Color) {
        let host = conn.metadata?.host?.lowercased() ?? ""
        let network = conn.metadata?.network?.lowercased() ?? ""
        let symbol = if host.contains("google") || host.contains("gstatic") {
            "shield.fill"
        } else if host.contains("icloud") || host.contains("apple") {
            "icloud.fill"
        } else if host.contains("github") {
            "terminal.fill"
        } else if host.contains("twitter") || host.contains("x.com") {
            "lock.fill"
        } else if host.contains("amazon") {
            "cart.fill"
        } else if network.contains("udp") {
            "dot.radiowaves.left.and.right"
        } else if network.contains("tcp") {
            "network"
        } else {
            "globe"
        }

        let iconColor: Color = switch symbol {
        case "shield.fill":
            nativePurple.opacity(0.92)
        case "icloud.fill":
            nativeInfo.opacity(0.92)
        case "terminal.fill":
            nativeIndigo.opacity(0.9)
        case "lock.fill":
            nativePositive.opacity(0.92)
        case "cart.fill":
            nativeWarning.opacity(0.92)
        case "dot.radiowaves.left.and.right":
            nativeTeal.opacity(0.92)
        case "network":
            nativeInfo.opacity(0.92)
        default:
            nativeSecondaryLabel
        }
        return (symbol, iconColor)
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
