import AppKit
import SwiftUI

extension MenuBarRoot {
    var proxyProvidersSection: some View {
        let providers = appState.sortedProxyProviderNames

        return VStack(alignment: .leading, spacing: MenuBarLayoutTokens.sectionGap) {
            self.nodesSectionHeader(
                tr("ui.section.proxy_providers"),
                symbol: "shippingbox.fill",
                count: "\(providers.count)")

            if providers.isEmpty {
                emptyCard(tr("ui.empty.proxy_providers"))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(providers.enumerated()), id: \.element) { index, name in
                        self.proxyProviderRow(name: name, detail: appState.proxyProvidersDetail[name])

                        if index < providers.count - 1 {
                            Rectangle()
                                .fill(nativeSeparator)
                                .frame(height: MenuBarLayoutTokens.hairline)
                        }
                    }
                }
                .background(nativeSectionCard())
            }
        }
    }

    func proxyProviderRow(name: String, detail: ProviderDetail?) -> some View {
        let nodeCount = detail?.proxies?.count ?? 0
        let updatedText = ValueFormatter.relativeTime(from: detail?.updatedAt, language: language)
        let expireText = ValueFormatter.daysUntilExpiryShort(from: detail?.subscriptionInfo?.expire, language: language)
        let upload = detail?.subscriptionInfo?.upload
        let download = detail?.subscriptionInfo?.download
        let total = detail?.subscriptionInfo?.total
        let remaining = ValueFormatter.subscriptionRemaining(total: total, upload: upload, download: download)
        let remainingRatio = ValueFormatter.subscriptionRemainingRatio(total: total, upload: upload, download: download)
        let quotaTextColumnWidth: CGFloat = 124
        let rowHorizontalPadding: CGFloat = 4
        let hovered = hoveredProxyProviderName == name

        return AttachedPopoverMenu(
            onWillPresent: {
                Task { await appState.ensureProviderNodesLoaded(provider: name) }
            },
            label: {
                VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense + 1) {
                    HStack(spacing: MenuBarLayoutTokens.hDense) {
                        RoundedRectangle(cornerRadius: MenuBarLayoutTokens.iconCornerRadius, style: .continuous)
                            .fill(nativeTeal.opacity(0.14))
                            .frame(width: 16, height: 16)
                            .overlay {
                                Image(systemName: "shippingbox.fill")
                                    .font(.appSystem(size: 9, weight: .semibold))
                                    .foregroundStyle(nativeTeal.opacity(0.92))
                            }

                        Text(name)
                            .font(.appSystem(size: 12, weight: .semibold))
                            .foregroundStyle(nativePrimaryLabel)
                            .lineLimit(1)

                        if detail?.subscriptionInfo != nil {
                            Text(expireText)
                                .font(.appSystem(size: 10, weight: .regular))
                                .foregroundStyle(nativeSecondaryLabel)
                                .padding(.horizontal, MenuBarLayoutTokens.hMicro + 2)
                                .padding(.vertical, MenuBarLayoutTokens.vDense)
                                .background(nativeBadgeCapsule())
                        }

                        Spacer(minLength: 0)

                        Text(updatedText)
                            .font(.appSystem(size: 10, weight: .regular))
                            .foregroundStyle(nativeTertiaryLabel)

                        self.providerActionButton(
                            "gauge",
                            isLoading: appState.providerBatchTesting.contains(name))
                        {
                            await appState.testAllProxyProviderNodes(provider: name)
                        }

                        self.providerActionButton(
                            "arrow.clockwise",
                            isLoading: appState.providerUpdating.contains(name))
                        {
                            await appState.updateProxyProvider(name: name)
                        }

                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 10, weight: .semibold))
                            .foregroundStyle(nativeTertiaryLabel)
                            .frame(width: 8, alignment: .trailing)
                    }

                    if let remaining, let total, let remainingRatio {
                        let quotaText =
                            "\(ValueFormatter.bytesCompactNoSpace(remaining)) / " +
                            "\(ValueFormatter.bytesCompactNoSpace(total))"
                        HStack(spacing: MenuBarLayoutTokens.hDense) {
                            Text(quotaText)
                                .font(.appMonospaced(size: 10, weight: .regular))
                                .foregroundStyle(nativeSecondaryLabel)
                                .lineLimit(1)
                                .frame(width: quotaTextColumnWidth, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(nativeControlFill.opacity(0.92))
                                    Capsule()
                                        .fill(nativeAccent.opacity(0.9))
                                        .frame(width: geo.size.width * remainingRatio)
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }
                .padding(.horizontal, rowHorizontalPadding)
                .padding(.vertical, MenuBarLayoutTokens.vDense + 1)
                .background(nativeHoverRowBackground(hovered))
                .animation(.easeInOut(duration: 0.14), value: hovered)
            },
            content: { dismiss in
                HStack(spacing: MenuBarLayoutTokens.hMicro) {
                    Image(systemName: "shippingbox.fill")
                        .font(.appSystem(size: 12, weight: .semibold))
                        .foregroundStyle(nativeTeal.opacity(0.92))
                        .frame(width: 16, alignment: .center)

                    Text(name)
                        .font(.appSystem(size: 12, weight: .semibold))
                        .foregroundStyle(nativePrimaryLabel)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(nodeCount)")
                        .font(.appMonospaced(size: 10, weight: .medium))
                        .foregroundStyle(nativeSecondaryLabel)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(nativeBadgeCapsule())
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

                Divider()
                    .overlay(nativeSeparator)
                    .padding(.bottom, 1)

                let nodes = sortedProviderNodes(provider: name, detail: detail)
                self.popoverNodesList(nodes) { node in
                    let nodeKey = appState.providerNodeKey(provider: name, node: node)
                    ProxyGroupPopoverNodeItem(
                        title: node,
                        delayText: appState.providerNodeDelayText(provider: name, node: node),
                        delayValue: appState.providerNodeLatencies[name]?[node],
                        delayColor: latencyColor(appState.providerNodeLatencies[name]?[node]),
                        isTesting: appState.providerNodeTesting.contains(nodeKey),
                        selected: false)
                    {
                        dismiss()
                        Task { await appState.testProxyProviderNode(provider: name, node: node) }
                    }
                }
            })
            .onHover { hoveredProxyProviderName = self.nextHoveredName(
                current: hoveredProxyProviderName,
                target: name,
                isHovering: $0) }
    }

    func providerActionButton(
        _ symbol: String,
        isLoading: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        let tone = symbol == "gauge" ? nativeTeal : (symbol == "arrow.clockwise" ? nativeInfo : nativeAccent)
        let icon = symbol == "gauge"
            ? "gauge.with.dots.needle.50percent"
            : (symbol == "arrow.clockwise" ? "arrow.triangle.2.circlepath" : symbol)
        let label = symbol == "gauge" ? tr("ui.action.test_latency") : tr("ui.action.refresh")

        return BorderlessAsyncIconActionButton(
            symbol: icon,
            label: label,
            tint: tone.opacity(0.96),
            isLoading: isLoading,
            action: action)
    }

    var proxyGroupsSection: some View {
        let groups = hideHiddenProxyGroups
            ? appState.proxyGroups.filter { $0.hidden != true }
            : appState.proxyGroups

        return VStack(alignment: .leading, spacing: MenuBarLayoutTokens.sectionGap) {
            self.nodesSectionHeader(
                tr("ui.section.proxy_groups"),
                symbol: "point.3.connected.trianglepath.dotted",
                count: "\(groups.count)")
            {
                HStack(spacing: MenuBarLayoutTokens.hDense) {
                    self.compactTopIcon(
                        hideHiddenProxyGroups ? "eye.slash" : "eye",
                        label: tr(
                            hideHiddenProxyGroups
                                ? "ui.action.show_hidden_proxy_groups"
                                : "ui.action.hide_hidden_proxy_groups"),
                        toneOverride: nativeIndigo)
                    {
                        hideHiddenProxyGroups.toggle()
                    }
                    .help(
                        tr(
                            hideHiddenProxyGroups
                                ? "ui.action.show_hidden_proxy_groups"
                                : "ui.action.hide_hidden_proxy_groups"))

                    self.compactTopIcon(
                        "gauge",
                        label: tr("ui.action.test_latency"),
                        toneOverride: nativeTeal)
                    {
                        await appState.refreshAllGroupLatencies(includeHiddenGroups: !hideHiddenProxyGroups)
                    }
                    .help(tr("ui.action.test_latency"))
                }
            }

            if groups.isEmpty {
                emptyCard(tr("ui.empty.proxy_groups"))
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(groups, id: \.name) { group in
                        self.proxyGroupInlineRow(group)
                    }
                }
            }
        }
    }

    func proxyGroupInlineRow(_ group: ProxyGroup) -> some View {
        let currentNode = group.now ?? tr("ui.common.na")
        let delayText = appState.delayText(group: group.name, node: currentNode)
        let nodeCount = group.all.count
        let iconURL = self.proxyGroupIconURL(group)
        let hasLeadingIcon = iconURL != nil
        let rowHorizontalPadding: CGFloat = 4
        let rowVerticalPadding: CGFloat = 1
        let hovered = hoveredProxyGroupName == group.name

        return AttachedPopoverMenu {
            GeometryReader { geo in
                let columns = self.proxyGroupMainColumnWidths(
                    totalWidth: geo.size.width,
                    hasLeadingIcon: hasLeadingIcon)
                HStack(spacing: MenuBarLayoutTokens.hMicro) {
                    if let iconURL {
                        self.proxyGroupLeadingIcon(iconURL)
                    }

                    Text(group.name)
                        .font(.appSystem(size: 12, weight: .semibold))
                        .foregroundStyle(nativePrimaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.9)
                        .frame(width: columns.name, alignment: .leading)

                    Text(currentNode)
                        .font(.appSystem(size: 11, weight: .medium))
                        .foregroundStyle(nativeSecondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.9)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(nativeBadgeCapsule())
                        .frame(width: columns.current, alignment: .leading)

                    Text(delayText)
                        .font(.appMonospaced(size: 10, weight: .regular))
                        .foregroundStyle(latencyColor(appState.delayValue(group: group.name, node: currentNode)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(width: columns.delay, alignment: .trailing)

                    self.compactGroupAction(
                        isLoading: appState.groupLatencyLoading.contains(group.name))
                    {
                        await appState.refreshGroupLatency(group)
                    }
                    .frame(width: 18, alignment: .center)

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 10, weight: .semibold))
                        .foregroundStyle(nativeTertiaryLabel)
                        .frame(width: 8, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 20)
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .background(nativeHoverRowBackground(hovered))
            .animation(.easeInOut(duration: 0.14), value: hovered)
        } content: { dismiss in
            HStack(spacing: MenuBarLayoutTokens.hMicro) {
                if let iconURL {
                    self.proxyGroupLeadingIcon(iconURL)
                }

                Text(group.name)
                    .font(.appSystem(size: 12, weight: .semibold))
                    .foregroundStyle(nativePrimaryLabel)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(nodeCount)")
                    .font(.appMonospaced(size: 10, weight: .medium))
                    .foregroundStyle(nativeSecondaryLabel)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(nativeBadgeCapsule())
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            Divider()
                .overlay(nativeSeparator)
                .padding(.bottom, 1)

            let nodes = sortedGroupNodes(group)
            self.popoverNodesList(nodes) { node in
                ProxyGroupPopoverNodeItem(
                    title: node,
                    delayText: appState.delayText(group: group.name, node: node),
                    delayValue: appState.delayValue(group: group.name, node: node),
                    delayColor: latencyColor(appState.delayValue(group: group.name, node: node)),
                    isTesting: false,
                    selected: node == group.now)
                {
                    dismiss()
                    Task { await appState.switchProxy(group: group.name, target: node) }
                }
            }
        }
        .onHover { hoveredProxyGroupName = self.nextHoveredName(
            current: hoveredProxyGroupName,
            target: group.name,
            isHovering: $0) }
    }

    func proxyGroupMainColumnWidths(
        totalWidth: CGFloat,
        hasLeadingIcon: Bool) -> (name: CGFloat, current: CGFloat, delay: CGFloat)
    {
        let iconWidth: CGFloat = hasLeadingIcon ? 16 : 0
        let actionWidth: CGFloat = 16
        let chevronWidth: CGFloat = 8
        let spacingCount: CGFloat = hasLeadingIcon ? 4 : 3
        let spacing = MenuBarLayoutTokens.hMicro * spacingCount
        let available = max(0, totalWidth - iconWidth - actionWidth - chevronWidth - spacing)
        let name = floor(available * 0.34)
        let delay = floor(available * 0.17)
        let current = max(0, available - name - delay)
        return (name, current, delay)
    }

    func proxyGroupLeadingIcon(_ iconURL: URL) -> some View {
        AsyncImage(url: iconURL) { phase in
            if case let .success(image) = phase {
                image
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 16, maxHeight: 16)
            }
        }
        .frame(width: 16, height: 16)
    }

    func proxyGroupIconURL(_ group: ProxyGroup) -> URL? {
        guard let icon = group.icon else { return nil }
        return URL(string: icon)
    }

    func compactGroupAction(
        isLoading: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        BorderlessAsyncIconActionButton(
            symbol: "gauge.with.dots.needle.50percent",
            label: tr("ui.action.test_latency"),
            tint: nativeTeal.opacity(0.96),
            isLoading: isLoading,
            action: action)
    }

    func nodesSectionHeader(
        _ title: String,
        symbol: String,
        count: String? = nil,
        @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View
    {
        HStack(spacing: MenuBarLayoutTokens.hDense) {
            Image(systemName: symbol)
                .font(.appSystem(size: 10, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
                .frame(width: 14, alignment: .center)

            Text(title)
                .font(.appSystem(size: 12, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(nativeTertiaryLabel)

            if let count {
                Text(count)
                    .font(.appMonospaced(size: 10, weight: .bold))
                    .foregroundStyle(nativeSecondaryLabel)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(nativeBadgeCapsule())
            }

            Spacer(minLength: 0)
            trailing()
        }
    }

    func nextHoveredName(current: String?, target: String, isHovering: Bool) -> String? {
        isHovering ? target : (current == target ? nil : current)
    }

    @ViewBuilder
    func popoverNodesList<Node: Hashable>(
        _ nodes: [Node],
        @ViewBuilder row: @escaping (Node) -> some View) -> some View
    {
        if nodes.isEmpty {
            Text(tr("ui.common.na"))
                .font(.appSystem(size: 11, weight: .regular))
                .foregroundStyle(nativeSecondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 2) {
                ForEach(nodes, id: \.self) { node in
                    row(node)
                }
            }
        }
    }
}

private struct ProxyGroupPopoverNodeItem: View {
    let title: String
    let delayText: String
    let delayValue: Int?
    let delayColor: Color
    let isTesting: Bool
    let selected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: MenuBarLayoutTokens.hMicro) {
                Image(systemName: self.selected ? "checkmark.circle.fill" : "circle")
                    .font(.appSystem(size: 10, weight: .semibold))
                    .foregroundStyle(self
                        .selected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 11, alignment: .center)

                Text(self.title)
                    .font(.appSystem(size: 12, weight: self.selected ? .semibold : .medium))
                    .foregroundStyle(self.selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 0)

                Group {
                    if self.isTesting {
                        LatencyLoadingIndicator()
                    } else {
                        self.delayMetricView
                    }
                }
                .frame(width: 56, alignment: .trailing)
            }
            .frame(height: 20)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(self.rowBackground))
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
    }

    var rowBackground: Color {
        if self.selected {
            return Color(nsColor: .controlAccentColor).opacity(0.18)
        }
        if self.isHovered {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
        }
        return .clear
    }

    @ViewBuilder
    var delayMetricView: some View {
        if let delayValue {
            let isTimeout = delayValue == 0
            let foreground: Color = isTimeout ? Color(nsColor: .secondaryLabelColor) : .white
            let background: Color = isTimeout
                ? Color(nsColor: .quaternaryLabelColor).opacity(0.48)
                : self.delayColor.opacity(self.selected ? 1 : 0.94)

            Text(self.delayText)
                .font(.appMonospaced(size: 10, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(background))
        } else {
            Text(self.delayText)
                .font(.appMonospaced(size: 10, weight: .regular))
                .foregroundStyle(self.delayColor.opacity(self.selected ? 1 : 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct LatencyLoadingIndicator: View {
    var body: some View {
        ProgressView()
            .controlSize(.mini)
            .frame(width: 30, height: 14, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.24)))
    }
}

private struct BorderlessAsyncIconActionButton: View {
    let symbol: String
    let label: String
    let tint: Color
    let isLoading: Bool
    let action: () async -> Void

    @State private var hovered = false

    var body: some View {
        Button {
            Task { await self.action() }
        } label: {
            ZStack {
                Image(systemName: self.symbol)
                    .font(.appSystem(size: 10.5, weight: .semibold))
                    .foregroundStyle(self.hovered ? self.tint : Color(nsColor: .secondaryLabelColor))
                    .symbolRenderingMode(.hierarchical)
                    .opacity(self.isLoading ? 0 : 1)

                ProgressView()
                    .controlSize(.mini)
                    .opacity(self.isLoading ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(self.label)
        .disabled(self.isLoading)
        .onHover { self.hovered = $0 }
    }
}
