import MihomoKit
import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens
struct RulesTabView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var rulesStore: RulesStore
    @AppStorage("clashbar.rules.group_by_policy.v1") private var storedGroupByPolicy = false
    @State private var hoveredRuleKey: String?
    @State private var hoveredGroupPolicy: String?
    @State private var expandedPolicies: Set<String> = []

    var body: some View {
        let output = self.rulesStore.output
        let visibleRules = output.rules
        let providerLookup = output.providerLookup

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: T.space8) {
                    self.rulesStatChip(title: self.tr("ui.rule.stats.rules"), value: "\(self.rulesStore.rulesCount)")
                    self.rulesStatChip(
                        title: self.tr("ui.rule.stats.sets"),
                        value: "\(self.rulesStore.providerRuleCount)")
                }

                Spacer(minLength: 0)
                HStack(spacing: T.space4) {
                    self.rulesGroupToggle
                    self.rulesRefreshButton
                }
            }
            .padding(.vertical, T.space6)
            .overlay(alignment: .bottom) { self.hairline }

            self.rulesControlCard
                .overlay(alignment: .bottom) { self.hairline }

            HStack(spacing: 0) {
                Color.clear.frame(width: 24)
                Text(self.tr("ui.rules.column.target_type"))
                    .font(.app(size: T.FontSize.caption, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .frame(width: 120, alignment: .leading)
                    .padding(.trailing, T.space6)
                Text(self.tr("ui.rules.column.policy"))
                    .font(.app(size: T.FontSize.caption, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .padding(.leading, T.space6)
                    .frame(width: 90, alignment: .leading)
                Text(self.tr("ui.rules.column.stats"))
                    .font(.app(size: T.FontSize.caption, weight: .medium))
                    .foregroundStyle(nativeTertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .textCase(.uppercase)
            .padding(.horizontal, T.space4)
            .padding(.vertical, T.space6)
            .overlay(alignment: .bottom) { self.hairline }

            if visibleRules.isEmpty {
                self.rulesEmptyState
            } else if self.rulesStore.groupByPolicy {
                self.groupedRulesList(groups: output.groups, providerLookup: providerLookup)
            } else {
                self.flatRulesList(visibleRules: visibleRules, providerLookup: providerLookup)
            }
        }
        .onAppear {
            self.rulesStore.groupByPolicy = self.storedGroupByPolicy
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(nativeSeparator)
            .frame(height: T.stroke)
    }

    var rulesControlCard: some View {
        VStack(alignment: .leading, spacing: T.space4) {
            HStack(spacing: T.space4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: T.space4) {
                        ForEach(RulesTypeFilter.allCases) { filter in
                            self.ruleTypeChip(filter)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                self.fractionSummaryBadge(
                    current: self.rulesStore.output.rules.count,
                    total: self.rulesStore.rulesCount)
            }

            HStack(spacing: T.space6) {
                TextField(self.tr("ui.placeholder.filter_rule"), text: self.$rulesStore.filterText)
                    .textFieldStyle(.roundedBorder)
                    .font(.app(size: T.FontSize.body, weight: .regular))
                    .foregroundStyle(nativePrimaryLabel)

                self.rulesPolicyMenu
            }
        }
        .menuRowPadding(vertical: T.space4)
    }

    func ruleTypeChip(_ filter: RulesTypeFilter) -> some View {
        self.filterChip(
            title: self.tr(filter.titleKey),
            count: self.rulesStore.output.typeCounts[filter] ?? 0,
            selected: self.rulesStore.typeFilter == filter)
        {
            self.rulesStore.typeFilter = filter
        }
    }

    var rulesPolicyMenu: some View {
        self.compactSelectionMenu(.init(
            selection: self.rulesStore.policyFilter,
            options: self.rulesStore.output.policyOptions,
            symbol: "arrow.triangle.branch",
            helpText: self.tr("ui.rules.filter.policy"),
            optionTitle: { $0.isAll ? self.tr("ui.rules.policy.all") : $0.name },
            onSelect: { self.rulesStore.policyFilter = $0 }))
    }

    var rulesGroupToggle: some View {
        let grouped = self.rulesStore.groupByPolicy
        return self.compactTopIcon(
            grouped ? "rectangle.3.group.fill" : "list.bullet",
            label: self.tr("ui.rules.group.toggle"),
            toneOverride: grouped ? nativeInfo : nil)
        {
            self.rulesStore.groupByPolicy.toggle()
            self.storedGroupByPolicy = self.rulesStore.groupByPolicy
        }
        .help(self.tr("ui.rules.group.toggle"))
    }

    var rulesEmptyState: some View {
        let key = self.rulesStore.ruleItems.isEmpty ? "ui.empty.rules" : "ui.empty.rules.no_match"
        return Text(self.tr(key))
            .font(.app(size: T.FontSize.body, weight: .regular))
            .foregroundStyle(nativeSecondaryLabel)
            .padding(.horizontal, T.space4)
            .padding(.vertical, T.space8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
    }

    func flatRulesList(visibleRules: [RuleItem], providerLookup: [String: ProviderDetail]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(visibleRules.enumerated()), id: \.offset) { index, rule in
                self.rulesRow(rule: rule, rowKey: "\(index)", providerLookup: providerLookup)

                if index < visibleRules.count - 1 {
                    self.hairline
                }
            }
        }
    }

    func groupedRulesList(groups: [RuleGroup], providerLookup: [String: ProviderDetail]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(groups) { group in
                self.policyGroupHeader(group)

                self.hairline

                if self.expandedPolicies.contains(group.policy) {
                    ForEach(Array(group.rules.enumerated()), id: \.offset) { index, rule in
                        self.rulesRow(
                            rule: rule,
                            rowKey: "\(group.policy)#\(index)",
                            providerLookup: providerLookup,
                            showsPolicy: false)

                        self.hairline
                    }
                }
            }
        }
    }

    func policyGroupHeader(_ group: RuleGroup) -> some View {
        let isExpanded = self.expandedPolicies.contains(group.policy)
        let isHovered = self.hoveredGroupPolicy == group.policy

        return HStack(spacing: T.space6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
                .frame(width: 12)

            Text(group.policy.isEmpty ? self.tr("ui.rules.policy.direct") : group.policy)
                .font(.app(size: T.FontSize.body, weight: .bold))
                .foregroundStyle(nativePrimaryLabel)

            Spacer(minLength: 0)

            Text("\(group.rules.count)")
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .foregroundStyle(nativeTertiaryLabel)
                .padding(.horizontal, T.space6)
                .padding(.vertical, 1)
                .background(self.nativeControlSurface(cornerRadius: 8))
        }
        .padding(.horizontal, T.space6)
        .padding(.vertical, T.space4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? self.nativeHoverFill : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                if isExpanded {
                    self.expandedPolicies.remove(group.policy)
                } else {
                    self.expandedPolicies.insert(group.policy)
                }
            }
        }
        .onHover { self.hoveredGroupPolicy = $0 ? group.policy : nil }
    }

    func rulesStatChip(title: String, value: String) -> some View {
        HStack(spacing: T.space4) {
            Text(title)
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .foregroundStyle(nativeTertiaryLabel)
            Text(value)
                .font(.app(size: T.FontSize.caption, weight: .bold))
                .foregroundStyle(nativePrimaryLabel)
        }
        .padding(.horizontal, T.space6)
        .padding(.vertical, T.space2)
        .background(self.nativeControlSurface(cornerRadius: 6))
    }

    var rulesRefreshButton: some View {
        self.compactTopIcon(
            "arrow.clockwise",
            label: self.tr("ui.action.refresh"),
            toneOverride: nativeInfo,
            isLoading: self.rulesStore.isRuleProvidersRefreshing)
        {
            await self.rulesStore.refreshRuleProviders()
        }
        .help(self.tr("ui.action.refresh"))
        .opacity(self.rulesStore.isRuleProvidersRefreshing ? 0.6 : 1)
    }

    func rulesRow(
        rule: RuleItem,
        rowKey: String,
        providerLookup: [String: ProviderDetail],
        showsPolicy: Bool = true) -> some View
    {
        let rawPayload = rule.payload.trimmedOrEmpty
        let payload = rawPayload.isEmpty ? self.tr("ui.common.na") : rawPayload
        let rawType = rule.type.trimmedOrEmpty
        let type = rawType.isEmpty ? self.tr("ui.common.na") : rawType
        let rawPolicy = rule.proxy.trimmedOrEmpty
        let policy = rawPolicy.isEmpty ? self.tr("ui.common.na") : rawPolicy
        let stats = self.ruleStats(payload: payload, providerLookup: providerLookup)
        let isHovered = self.hoveredRuleKey == rowKey
        let iconConfig = self.ruleTypeIcon(for: type)
        let policyConfig = self.rulePolicyBadge(for: policy)

        return HStack(spacing: 0) {
            Image(systemName: iconConfig.symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(iconConfig.color)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(payload)
                    .font(.app(size: T.FontSize.body, weight: .medium))
                    .foregroundStyle(nativePrimaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(type)
                    .font(.app(size: T.FontSize.mini, weight: .regular))
                    .foregroundStyle(nativeTertiaryLabel)
            }
            .frame(width: 120, alignment: .leading)
            .padding(.trailing, T.space6)

            if showsPolicy {
                HStack(spacing: T.space2) {
                    if let sym = policyConfig.symbol {
                        Image(systemName: sym)
                            .font(.app(size: T.FontSize.mini, weight: .semibold))
                            .foregroundStyle(policyConfig.color)
                    }
                    Text(policy)
                        .font(.app(size: T.FontSize.caption, weight: .medium))
                        .foregroundStyle(policyConfig.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: 90, alignment: .leading)
                .padding(.trailing, T.space6)
            }

            Spacer(minLength: 0)

            HStack(spacing: T.space4) {
                if stats.hasProvider {
                    if let updated = stats.updatedText {
                        Text(updated)
                            .font(.app(size: T.FontSize.mini, weight: .regular))
                            .foregroundStyle(nativeTertiaryLabel)
                    }
                    Text("\(stats.count)")
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(nativeSecondaryLabel)
                }
            }
        }
        .padding(.horizontal, T.space4)
        .padding(.vertical, T.space4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? self.nativeHoverFill : Color.clear))
        .contentShape(Rectangle())
        .onHover { self.hoveredRuleKey = $0 ? rowKey : nil }
    }

    func ruleTypeIcon(for type: String) -> (symbol: String, color: Color) {
        let lower = type.lowercased()
        if lower.contains("ipcidr") {
            return ("globe.americas.fill", nativeInfo.opacity(T.Opacity.solid))
        }
        if lower.contains("domain") || lower.contains("suffix") || lower.contains("keyword") {
            return ("network", nativeTeal.opacity(T.Opacity.solid))
        }
        if lower.contains("ruleset") {
            return ("list.bullet.rectangle.fill", nativeWarning.opacity(T.Opacity.solid))
        }
        return ("circle.grid.2x2.fill", nativeIndigo.opacity(T.Opacity.solid))
    }

    func rulePolicyBadge(for policy: String) -> (symbol: String?, color: Color) {
        let lower = policy.lowercased()
        if lower.contains("fishy") {
            return (
                symbol: "exclamationmark.triangle.fill",
                color: nativeAccent.opacity(T.Opacity.solid))
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
        guard !payloadTrimmed.isEmpty, payloadTrimmed != self.tr("ui.common.na") else {
            return (count: 0, updatedText: nil, hasProvider: false)
        }

        if let provider = providerLookup[payloadTrimmed.lowercased()] {
            let count = max(0, provider.ruleCount ?? 0)
            return (
                count: count,
                updatedText: ValueFormatter.relativeTime(from: provider.updatedAt, language: self.language),
                hasProvider: true)
        }
        return (count: 0, updatedText: nil, hasProvider: false)
    }
}
