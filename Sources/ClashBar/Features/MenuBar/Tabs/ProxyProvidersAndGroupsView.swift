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
            width: 292,
            onWillPresent: {
                Task { await appState.ensureProviderNodesLoaded(provider: name) }
            },
            label: {
                VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense + 1) {
                    HStack(spacing: MenuBarLayoutTokens.hDense) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(nativeTeal.opacity(0.14))
                            .frame(width: 16, height: 16)
                            .overlay {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(nativeTeal.opacity(0.92))
                            }

                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(nativePrimaryLabel)
                            .lineLimit(1)

                        if detail?.subscriptionInfo != nil {
                            Text(expireText)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(nativeSecondaryLabel)
                                .padding(.horizontal, MenuBarLayoutTokens.hMicro + 2)
                                .padding(.vertical, MenuBarLayoutTokens.vDense)
                                .background(nativeBadgeCapsule())
                        }

                        Spacer(minLength: 0)

                        Text(updatedText)
                            .font(.system(size: 10, weight: .regular))
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
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(nativeTertiaryLabel)
                            .frame(width: 8, alignment: .trailing)
                    }

                    if let remaining, let total, let remainingRatio {
                        let quotaText =
                            "\(ValueFormatter.bytesCompactNoSpace(remaining)) / " +
                            "\(ValueFormatter.bytesCompactNoSpace(total))"
                        HStack(spacing: MenuBarLayoutTokens.hDense) {
                            Text(quotaText)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(nativeTeal.opacity(0.92))
                        .frame(width: 16, alignment: .center)

                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(nativePrimaryLabel)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(nodeCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                    ProxyGroupPopoverNodeItem(
                        title: node,
                        delayText: appState.providerNodeDelayText(provider: name, node: node),
                        delayColor: providerNodeDelayColor(provider: name, node: node),
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

        return roundedIconActionButton(
            symbol: symbol,
            size: 14,
            foreground: tone.opacity(0.92),
            isLoading: isLoading,
            action: action)
    }

    var proxyGroupsSection: some View {
        let groups = appState.proxyGroups

        return VStack(alignment: .leading, spacing: MenuBarLayoutTokens.sectionGap) {
            self.nodesSectionHeader(
                tr("ui.section.proxy_groups"),
                symbol: "point.3.connected.trianglepath.dotted",
                count: "\(groups.count)")
            {
                Button {
                    Task { await appState.refreshAllGroupLatencies() }
                } label: {
                    HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
                        Image(systemName: "gauge")
                            .font(.system(size: 10, weight: .semibold))
                        Text(tr("ui.action.test_latency"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
        let rowHorizontalPadding: CGFloat = 4
        let rowVerticalPadding: CGFloat = 1
        let hovered = hoveredProxyGroupName == group.name

        return AttachedPopoverMenu(width: 272) {
            GeometryReader { geo in
                let columns = self.proxyGroupMainColumnWidths(totalWidth: geo.size.width)
                HStack(spacing: MenuBarLayoutTokens.hMicro) {
                    self.proxyGroupLeadingIcon(group)
                        .frame(width: 16, alignment: .center)

                    Text(group.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(nativePrimaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.9)
                        .frame(width: columns.name, alignment: .leading)

                    Text(currentNode)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(groupSelectionColor(for: group))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.9)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(nativeBadgeCapsule())
                        .frame(width: columns.current, alignment: .leading)

                    Text(delayText)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(groupDelayColor(group: group.name, node: currentNode))
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
                        .font(.system(size: 10, weight: .semibold))
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
                self.proxyGroupLeadingIcon(group)
                    .frame(width: 16, alignment: .center)

                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(nativePrimaryLabel)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(currentNode)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(groupSelectionColor(for: group))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(nativeBadgeCapsule())
                    .frame(maxWidth: 116, alignment: .trailing)

                Text("\(nodeCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                    delayColor: groupDelayColor(group: group.name, node: node),
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

    func proxyGroupMainColumnWidths(totalWidth: CGFloat) -> (name: CGFloat, current: CGFloat, delay: CGFloat) {
        let iconWidth: CGFloat = 16
        let actionWidth: CGFloat = 16
        let chevronWidth: CGFloat = 8
        let spacing = MenuBarLayoutTokens.hMicro * 4
        let available = max(0, totalWidth - iconWidth - actionWidth - chevronWidth - spacing)
        let name = floor(available * 0.34)
        let delay = floor(available * 0.17)
        let current = max(0, available - name - delay)
        return (name, current, delay)
    }

    func proxyGroupLeadingIcon(_ group: ProxyGroup) -> some View {
        let tone = groupColor(for: group)

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tone.opacity(0.26), tone.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            .frame(width: 16, height: 16)
            .overlay {
                Image(systemName: groupSymbol(for: group))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone.opacity(0.95))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(tone.opacity(0.30), lineWidth: 0.65)
            }
    }

    func compactGroupAction(
        isLoading: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        asyncBorderedIconButton(
            symbol: "gauge",
            label: tr("ui.action.test_latency"),
            fontSize: 10,
            controlSize: .mini,
            tint: nativeTeal.opacity(0.92),
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
                .frame(width: 14, alignment: .center)

            Text(title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(nativeTertiaryLabel)

            if let count {
                Text(count)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                .font(.system(size: 11, weight: .regular))
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
    let delayColor: Color
    let selected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: MenuBarLayoutTokens.hMicro) {
                Image(systemName: self.selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(self
                        .selected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 11, alignment: .center)

                Text(self.title)
                    .font(.system(size: 12, weight: self.selected ? .semibold : .medium))
                    .foregroundStyle(self.selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 0)

                Text(self.delayText)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(self.delayColor.opacity(self.selected ? 1 : 0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
}
