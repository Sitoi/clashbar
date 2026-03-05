import SwiftUI

extension MenuBarRoot {
    var rulesTabBody: some View {
        let visibleRules = Array(appState.ruleItems.prefix(100))
        let providerLookup = self.ruleProviderLookupMap()

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    self.rulesStatChip(title: tr("ui.rule.stats.rules"), value: "\(appState.rulesCount)")
                    self.rulesStatChip(title: tr("ui.rule.stats.sets"), value: "\(appState.providerRuleCount)")
                }

                Spacer(minLength: 0)
                self.rulesRefreshButton
            }
            .padding(.vertical, MenuBarLayoutTokens.vRow)
            .background(Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(nativeSeparator)
                    .frame(height: MenuBarLayoutTokens.hairline)
            }

            HStack(spacing: 0) {
                Color.clear.frame(width: 24)
                Text(tr("ui.rules.column.target_type"))
                    .font(.appSystem(size: 11, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .frame(width: 120, alignment: .leading)
                Text(tr("ui.rules.column.policy"))
                    .font(.appSystem(size: 11, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .frame(width: 90, alignment: .leading)
                Text(tr("ui.rules.column.stats"))
                    .font(.appSystem(size: 11, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .textCase(.uppercase)
            .tracking(0.7)
            .padding(.horizontal, MenuBarLayoutTokens.hRow)
            .padding(.vertical, 6)
            .background(nativeControlFill.opacity(0.35))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(nativeSeparator)
                    .frame(height: MenuBarLayoutTokens.hairline)
            }

            if appState.ruleItems.isEmpty {
                Text(tr("ui.empty.rules"))
                    .font(.appSystem(size: 12, weight: .regular))
                    .foregroundStyle(nativeSecondaryLabel)
                    .padding(.horizontal, MenuBarLayoutTokens.hRow)
                    .padding(.vertical, MenuBarLayoutTokens.vDense + 6)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleRules.enumerated()), id: \.offset) { index, rule in
                        self.rulesRow(rule: rule, index: index, providerLookup: providerLookup)

                        if index < visibleRules.count - 1 {
                            Rectangle()
                                .fill(nativeSeparator)
                                .frame(height: MenuBarLayoutTokens.hairline)
                        }
                    }
                }
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
            }
        }
    }

    func rulesStatChip(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(.appSystem(size: 11, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
            Text(value)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundStyle(nativePrimaryLabel)
        }
        .padding(.horizontal, MenuBarLayoutTokens.hDense)
        .padding(.vertical, MenuBarLayoutTokens.vDense)
    }

    var rulesRefreshButton: some View {
        self.compactTopIcon(
            "arrow.clockwise",
            label: tr("ui.action.refresh"),
            toneOverride: nativeInfo,
            isLoading: appState.isRuleProvidersRefreshing)
        {
            await appState.refreshRuleProviders()
        }
        .help(tr("ui.action.refresh"))
        .opacity(appState.isRuleProvidersRefreshing ? 0.6 : 1)
    }

    func rulesRow(rule: RuleItem, index: Int, providerLookup: [String: ProviderDetail]) -> some View {
        let hovered = hoveredRuleIndex == index
        let normalizedType = rule.type?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPayload = rule.payload?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProxy = rule.proxy?.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeText = ((normalizedType?.isEmpty == false ? normalizedType : tr("ui.common.na")) ?? tr("ui.common.na"))
            .uppercased()
        let targetText = (normalizedPayload?.isEmpty == false ? normalizedPayload : tr("ui.common.na")) ??
            tr("ui.common.na")
        let policyText = (normalizedProxy?.isEmpty == false ? normalizedProxy : tr("ui.common.na")) ??
            tr("ui.common.na")
        let iconSpec = self.ruleTypeIcon(for: typeText)
        let badge = self.rulePolicyBadge(for: policyText)
        let stats = self.ruleStats(for: rule, payload: targetText, providerLookup: providerLookup)

        return HStack(spacing: 0) {
            Image(systemName: iconSpec.symbol)
                .font(.appSystem(size: 14, weight: .medium))
                .foregroundStyle(iconSpec.color)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(targetText)
                    .font(.appSystem(size: 13, weight: .medium))
                    .foregroundStyle(nativePrimaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(typeText)
                    .font(.appSystem(size: 11, weight: .regular))
                    .foregroundStyle(nativeTertiaryLabel)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
            .padding(.trailing, MenuBarLayoutTokens.hDense)

            HStack(spacing: MenuBarLayoutTokens.hMicro) {
                if let symbol = badge.symbol {
                    Image(systemName: symbol)
                        .font(.appSystem(size: 10, weight: .semibold))
                        .foregroundStyle(badge.color)
                }
                Text(policyText)
                    .font(.appSystem(size: 11, weight: .medium))
                    .foregroundStyle(badge.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, MenuBarLayoutTokens.hDense)
            .padding(.vertical, MenuBarLayoutTokens.vDense)
            .background(
                Capsule(style: .continuous)
                    .fill(badge.background))
            .frame(width: 90, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1.5) {
                Text("\(stats.count)")
                    .font(.appMonospaced(size: 12, weight: .regular))
                    .foregroundStyle(stats.hasProvider ? nativeSecondaryLabel : nativeTertiaryLabel)
                if let updatedText = stats.updatedText {
                    Text(updatedText)
                        .font(.appSystem(size: 10, weight: .regular))
                        .foregroundStyle(nativeTertiaryLabel)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, MenuBarLayoutTokens.hRow)
        .frame(height: 32)
        .background(nativeHoverRowBackground(hovered))
        .onHover { isHovering in
            hoveredRuleIndex = isHovering ? index : (hoveredRuleIndex == index ? nil : hoveredRuleIndex)
        }
    }

    func ruleTypeIcon(for type: String) -> (symbol: String, color: Color) {
        let lower = type.lowercased()
        if lower.contains("ipcidr") {
            return ("globe.americas.fill", nativeInfo.opacity(0.9))
        }
        if lower.contains("domain") || lower.contains("suffix") || lower.contains("keyword") {
            return ("network", nativeTeal.opacity(0.9))
        }
        if lower.contains("ruleset") {
            return ("archivebox.fill", nativeWarning.opacity(0.9))
        }
        return ("circle.grid.2x2.fill", nativeIndigo.opacity(0.9))
    }

    func rulePolicyBadge(for policy: String) -> (symbol: String?, color: Color, background: Color) {
        let lower = policy.lowercased()
        if lower.contains("fishy") {
            return (
                symbol: "exclamationmark.triangle.fill",
                color: nativeAccent.opacity(0.92),
                background: nativeAccent.opacity(0.16))
        }
        return (
            symbol: nil,
            color: nativeSecondaryLabel,
            background: nativeBadgeFill)
    }

    func ruleStats(
        for rule: RuleItem,
        payload: String,
        providerLookup: [String: ProviderDetail]) -> (count: Int, updatedText: String?, hasProvider: Bool)
    {
        let payloadTrimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let type = rule.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if type.contains("ruleset") {
            return (count: 0, updatedText: nil, hasProvider: false)
        }
        return (count: 0, updatedText: nil, hasProvider: false)
    }

    func ruleProviderLookupMap() -> [String: ProviderDetail] {
        var map: [String: ProviderDetail] = [:]
        map.reserveCapacity(appState.ruleProviders.count * 2)

        for (key, detail) in appState.ruleProviders {
            map[key.lowercased()] = detail

            if let name = detail.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty
            {
                map[name.lowercased()] = detail
            }
        }
        return map
    }
}
