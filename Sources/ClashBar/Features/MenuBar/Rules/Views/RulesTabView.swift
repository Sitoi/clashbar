import SwiftUI

extension MenuBarRootView {
    var rulesTabBody: some View {
        let visibleRules = self.rulesViewModel.visibleRules
        let providerLookup = self.rulesViewModel.providerLookup

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: MenuBarLayoutTokens.space8) {
                    self.rulesStatChip(title: tr("ui.rule.stats.rules"), value: "\(appSession.rulesCount)")
                    self.rulesStatChip(title: tr("ui.rule.stats.sets"), value: "\(appSession.providerRuleCount)")
                }

                Spacer(minLength: 0)
                self.rulesRefreshButton
            }
            .padding(.vertical, MenuBarLayoutTokens.space6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(nativeSeparator)
                    .frame(height: MenuBarLayoutTokens.stroke)
            }

            HStack(spacing: 0) {
                Color.clear.frame(width: 24)
                Text(tr("ui.rules.column.target_type"))
                    .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .frame(width: 120, alignment: .leading)
                    .padding(.trailing, MenuBarLayoutTokens.space6)
                Text(tr("ui.rules.column.policy"))
                    .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .padding(.leading, MenuBarLayoutTokens.space6)
                    .frame(width: 90, alignment: .leading)
                Text(tr("ui.rules.column.stats"))
                    .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .textCase(.uppercase)
            .padding(.horizontal, MenuBarLayoutTokens.space4)
            .padding(.vertical, MenuBarLayoutTokens.space6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(nativeSeparator)
                    .frame(height: MenuBarLayoutTokens.stroke)
            }

            if visibleRules.isEmpty {
                Text(tr("ui.empty.rules"))
                    .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .regular))
                    .foregroundStyle(nativeSecondaryLabel)
                    .padding(.horizontal, MenuBarLayoutTokens.space4)
                    .padding(.vertical, MenuBarLayoutTokens.space8)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleRules.enumerated()), id: \.element.rowID) { index, rule in
                        self.rulesRow(rule: rule, index: index, providerLookup: providerLookup)

                        if index < visibleRules.count - 1 {
                            Rectangle()
                                .fill(nativeSeparator)
                                .frame(height: MenuBarLayoutTokens.stroke)
                        }
                    }
                }
            }
        }
    }

    func rulesStatChip(title: String, value: String) -> some View {
        HStack(spacing: MenuBarLayoutTokens.space4) {
            Text(title.uppercased())
                .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
            Text(value)
                .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .bold))
                .foregroundStyle(nativePrimaryLabel)
        }
        .padding(.horizontal, MenuBarLayoutTokens.space6)
        .padding(.vertical, MenuBarLayoutTokens.space2)
    }

    var rulesRefreshButton: some View {
        self.compactTopIcon(
            "arrow.clockwise",
            label: tr("ui.action.refresh"),
            toneOverride: nativeInfo,
            isLoading: appSession.isRuleProvidersRefreshing)
        {
            await appSession.refreshRuleProviders()
        }
        .help(tr("ui.action.refresh"))
        .opacity(appSession.isRuleProvidersRefreshing ? 0.6 : 1)
    }

    func rulesRow(rule: RuleItem, index: Int, providerLookup: [String: ProviderDetail]) -> some View {
        let hovered = hoveredRuleIndex == index
        let typeText = (rule.type.trimmedNonEmpty ?? tr("ui.common.na")).uppercased()
        let targetText = rule.payload.trimmedNonEmpty ?? tr("ui.common.na")
        let policyText = rule.proxy.trimmedNonEmpty ?? tr("ui.common.na")
        let iconSpec = self.ruleTypeIcon(for: typeText)
        let badge = self.rulePolicyBadge(for: policyText)
        let stats = self.ruleStats(payload: targetText, providerLookup: providerLookup)

        return HStack(spacing: 0) {
            Image(systemName: iconSpec.symbol)
                .font(.app(size: MenuBarLayoutTokens.FontSize.subhead, weight: .medium))
                .foregroundStyle(iconSpec.color)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: MenuBarLayoutTokens.space1) {
                Text(targetText)
                    .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .medium))
                    .foregroundStyle(nativePrimaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(typeText)
                    .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .regular))
                    .foregroundStyle(nativeTertiaryLabel)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
            .padding(.trailing, MenuBarLayoutTokens.space6)

            HStack(spacing: MenuBarLayoutTokens.space1) {
                if let symbol = badge.symbol {
                    Image(systemName: symbol)
                        .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
                        .foregroundStyle(badge.color)
                }
                Text(policyText)
                    .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
                    .foregroundStyle(badge.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 90, alignment: .leading)

            VStack(alignment: .trailing, spacing: MenuBarLayoutTokens.space1) {
                Text("\(stats.count)")
                    .font(.app(size: MenuBarLayoutTokens.FontSize.body, weight: .regular))
                    .foregroundStyle(stats.hasProvider ? nativeSecondaryLabel : nativeTertiaryLabel)
                if let updatedText = stats.updatedText {
                    Text(updatedText)
                        .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .regular))
                        .foregroundStyle(nativeTertiaryLabel)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, MenuBarLayoutTokens.space4)
        .frame(height: MenuBarLayoutTokens.rowHeight)
        .background(nativeHoverRowBackground(hovered))
        .onHover { hoveredRuleIndex = self.nextHovered(
            current: hoveredRuleIndex, target: index, isHovering: $0) }
    }

    func ruleTypeIcon(for type: String) -> (symbol: String, color: Color) {
        let lower = type.lowercased()
        if lower.contains("ipcidr") {
            return ("globe.americas.fill", nativeInfo.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        if lower.contains("domain") || lower.contains("suffix") || lower.contains("keyword") {
            return ("network", nativeTeal.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        if lower.contains("ruleset") {
            return ("list.bullet.rectangle.fill", nativeWarning.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        return ("circle.grid.2x2.fill", nativeIndigo.opacity(MenuBarLayoutTokens.Opacity.solid))
    }

    func rulePolicyBadge(for policy: String) -> (symbol: String?, color: Color) {
        let lower = policy.lowercased()
        if lower.contains("fishy") {
            return (
                symbol: "exclamationmark.triangle.fill",
                color: nativeAccent.opacity(MenuBarLayoutTokens.Opacity.solid))
        }
        return (
            symbol: nil,
            color: nativeSecondaryLabel)
    }

    func ruleStats(
        payload: String,
        providerLookup: [String: ProviderDetail]) -> (count: Int, updatedText: String?, hasProvider: Bool)
    {
        let payloadTrimmed = payload.trimmed
        guard !payloadTrimmed.isEmpty, payloadTrimmed != tr("ui.common.na") else {
            return (count: 0, updatedText: nil, hasProvider: false)
        }

        if let provider = providerLookup[payloadTrimmed.lowercased()] {
            let count = max(0, provider.ruleCount ?? 0)
            return (
                count: count,
                updatedText: ValueFormatter.relativeTime(from: provider.updatedAt, language: language),
                hasProvider: true)
        }
        return (count: 0, updatedText: nil, hasProvider: false)
    }

    func refreshVisibleRules() {
        self.rulesViewModel.updateVisibleRules(
            items: self.appSession.ruleItems,
            providers: self.appSession.ruleProviders)
    }
}
