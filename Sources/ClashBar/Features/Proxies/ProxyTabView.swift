import MihomoKit
import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct ProxyTabView: TranslatingView {
    enum ProxyCommandCopyTarget: Equatable {
        case local
        case currentEndpoint
    }

    private struct ConfigMenuItemContext: Identifiable {
        let name: String
        let isRemote: Bool
        let isSelected: Bool
        let remoteState: RemoteConfigMenuState
        let remoteSubtitle: String?
        let boundSSIDs: [String]
        let currentSSID: String?
        let isCurrentSSIDBound: Bool
        let showsPermissionAction: Bool
        let remoteSubscriptionURL: String?
        let itemHelpText: String?
        let ssidBadgeText: String?
        let ssidBadgeHelpText: String?

        var id: String {
            self.name
        }

        var showsSSIDActions: Bool {
            self.currentSSID != nil || self.showsPermissionAction || !self.boundSSIDs.isEmpty
        }

        var showsRemoteCopyAction: Bool {
            self.remoteSubscriptionURL != nil
        }
    }

    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var proxyStore: ProxyStore
    @EnvironmentObject var configurationStore: ConfigurationStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var trafficStore: TrafficStore
    @EnvironmentObject var connectionsStore: ConnectionsStore

    @AppStorage("clashbar.proxy.group.sort_nodes_by_latency") var sortGroupNodesByLatency: Bool = false
    @AppStorage("clashbar.proxy.group.show_latency_history") var showLatencyHistory: Bool = false
    @AppStorage("clashbar.proxy.group.hide_hidden") var hideHiddenProxyGroups: Bool = true
    @AppStorage("clashbar.proxy.providers.collapsed") var isProxyProvidersCollapsed: Bool = false

    @State var copiedProxyCommandTarget: ProxyCommandCopyTarget?
    @State var proxyCommandCopyResetTask: Task<Void, Never>?
    @State var hoveredProviderName: String?

    var body: some View {
        self.proxyTabBody
            .onDisappear {
                self.proxyCommandCopyResetTask?.cancel()
                self.proxyCommandCopyResetTask = nil
            }
    }

    func handleCopyProxyCommand(_ target: ProxyCommandCopyTarget, action: () -> Void) {
        action()

        self.proxyCommandCopyResetTask?.cancel()
        self.proxyCommandCopyResetTask = nil

        withAnimation(.snappy(duration: 0.16)) {
            self.copiedProxyCommandTarget = target
        }

        self.proxyCommandCopyResetTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_600_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                self.copiedProxyCommandTarget = nil
            }
            self.proxyCommandCopyResetTask = nil
        }
    }

    var quickRowTrailingColumnWidth: CGFloat {
        let contentWidth = T.panelWidth - (T.space8 * 2)
        return min(170, max(126, contentWidth * 0.44))
    }

    private func configMenuLeadingSymbol(for context: ConfigMenuItemContext) -> String {
        context.isRemote ? "link" : "doc.text"
    }

    private func configMenuLeadingTint(for context: ConfigMenuItemContext) -> Color {
        context.isRemote
            ? self.nativePurple.opacity(T.Opacity.solid)
            : self.nativeInfo.opacity(T.Opacity.solid)
    }

    private func configMenuRemoteSubtitle(state: RemoteConfigMenuState) -> String? {
        ValueFormatter.remoteConfigMenuStatusLine(
            autoUpdateEnabled: state.autoUpdateEnabled,
            nextUpdateAt: state.nextUpdateAt,
            lastUpdateAt: state.updatedAt,
            language: self.appViewModel.uiLanguage)
            ?? state.updatedAt.map(ValueFormatter.dateTime)
            ?? "--"
    }

    private func configMenuSSIDBadgeText(for ssids: [String]) -> String? {
        guard !ssids.isEmpty else { return nil }
        let joined = ssids.joined(separator: ", ")
        if joined.count <= 22 {
            return joined
        }
        guard let firstSSID = ssids.first else { return nil }
        let remainingCount = ssids.count - 1
        guard remainingCount > 0 else { return firstSSID }
        return "\(firstSSID) +\(remainingCount)"
    }

    private func configMenuSSIDBadgeTint(for context: ConfigMenuItemContext) -> Color {
        context.isCurrentSSIDBound
            ? self.nativePositive.opacity(T.Opacity.solid)
            : self.nativeInfo.opacity(T.Opacity.solid)
    }

    private func configMenuItemHelpText(ssidHelpText: String?, remoteSubtitle: String?) -> String? {
        let parts = [ssidHelpText, remoteSubtitle]
            .compactMap { $0?.trimmedNonEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    private func makeConfigMenuItemContext(for name: String) -> ConfigMenuItemContext {
        let remoteSubscription = self.configurationStore.subscriptions[name]
        let isRemote = remoteSubscription != nil
        let remoteState = self.configurationStore.remoteConfigMenuState(for: name)
        let remoteSubtitle = isRemote ? self.configMenuRemoteSubtitle(state: remoteState) : nil
        let normalizedConfigFileName = name.trimmed
        let boundSSIDs = self.configurationStore.ssidStrategyRules
            .filter { $0.configFileName == normalizedConfigFileName }
            .map(\.ssid)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let currentSSID = self.configurationStore.ssidStrategyCurrentSSID?.trimmedNonEmpty
        let isCurrentSSIDBound = currentSSID.map { boundSSIDs.contains($0) } ?? false
        let showsPermissionAction = self.configurationStore.ssidStrategyEnabled
            && currentSSID == nil
            && self.configurationStore.ssidStrategyAuthorizationStatus == .notDetermined
        let ssidBadgeHelpText = boundSSIDs.isEmpty
            ? nil
            : self.tr("ui.quick.ssid.bound_label", boundSSIDs.joined(separator: ", "))

        return ConfigMenuItemContext(
            name: name,
            isRemote: isRemote,
            isSelected: name == self.configurationStore.selectedConfigName,
            remoteState: remoteState,
            remoteSubtitle: remoteSubtitle,
            boundSSIDs: boundSSIDs,
            currentSSID: currentSSID,
            isCurrentSSIDBound: isCurrentSSIDBound,
            showsPermissionAction: showsPermissionAction,
            remoteSubscriptionURL: remoteSubscription?.urlString.trimmedNonEmpty,
            itemHelpText: self.configMenuItemHelpText(
                ssidHelpText: ssidBadgeHelpText,
                remoteSubtitle: remoteSubtitle),
            ssidBadgeText: self.configMenuSSIDBadgeText(for: boundSSIDs),
            ssidBadgeHelpText: ssidBadgeHelpText)
    }

    private func ssidStrategyMenuStatusText() -> String {
        if self.configurationStore.ssidStrategyAuthorizationStatus == .authorized {
            return self.configurationStore.ssidStrategyCurrentSSID?.trimmedNonEmpty ?? "--"
        }
        switch self.configurationStore.ssidStrategyAuthorizationStatus {
        case .authorized: return self.tr("ui.common.authorized")
        case .denied: return self.tr("ui.common.denied")
        case .notDetermined: return self.tr("ui.common.not_determined")
        case .restricted: return self.tr("ui.settings.ssid_strategy.status.restricted")
        case .servicesDisabled: return self.tr("ui.settings.ssid_strategy.status.services_disabled")
        }
    }

    private func ssidStrategyMenuUsageHint() -> String {
        self.tr("ui.quick.ssid.usage_hint")
    }

    private func configMenuItemContexts() -> [ConfigMenuItemContext] {
        self.configurationStore.availableConfigFileNames
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { self.makeConfigMenuItemContext(for: $0) }
    }

    private func configMenuSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.app(size: T.FontSize.caption, weight: .bold))
            .foregroundStyle(self.nativeTertiaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, T.space6)
            .padding(.top, T.space2)
            .padding(.bottom, T.space1)
            .textCase(.uppercase)
    }

    private func configMenuItem(for context: ConfigMenuItemContext, dismiss: @escaping () -> Void) -> some View {
        ConfigMenuItemView(
            title: context.name,
            leadingSymbol: self.configMenuLeadingSymbol(for: context),
            leadingTint: self.configMenuLeadingTint(for: context),
            selected: context.isSelected,
            subtitle: context.isRemote ? context.remoteSubtitle : nil,
            itemHelpText: context.itemHelpText,
            ssidBadgeText: context.ssidBadgeText,
            ssidBadgeTint: self.configMenuSSIDBadgeTint(for: context),
            ssidBadgeHelpText: context.ssidBadgeHelpText,
            refreshPhase: context.isRemote ? context.remoteState.phase : nil,
            refreshHelpText: [self.tr("ui.action.refresh"), context.remoteSubtitle]
                .compactMap { $0?.trimmedNonEmpty }
                .joined(separator: "\n"),
            refreshingAccessibilityLabel: self.tr("ui.quick.remote.refreshing"),
            refreshFailedHelpText: self.tr("ui.quick.remote.refresh_failed"))
        {
            dismiss()
            Task { await self.configurationStore.selectConfigFile(named: context.name) }
        } onRefresh: {
            Task { await self.configurationStore.refreshRemoteConfigFile(named: context.name) }
        }
        .contextMenu {
            if let currentSSID = context.currentSSID {
                Button(
                    context.isCurrentSSIDBound
                        ? self.tr("ui.quick.ssid.unbind_current_named", currentSSID)
                        : self.tr("ui.quick.ssid.bind_current_named", currentSSID))
                {
                    self.configurationStore.toggleCurrentSSIDBinding(for: context.name)
                }
            } else if context.showsPermissionAction {
                Button(self.tr("ui.quick.ssid.request_permission")) {
                    self.appViewModel.refreshSSIDStrategyState(requestAuthorizationIfNeeded: true)
                }
            }

            ForEach(context.boundSSIDs, id: \.self) { ssid in
                Button(self.tr("ui.quick.ssid.unbind_named", ssid)) {
                    self.configurationStore.removeSSIDStrategyBinding(ssid: ssid)
                }
            }

            if context.showsSSIDActions {
                Divider()
            }

            if let urlString = context.remoteSubscriptionURL {
                Button(self.tr("ui.action.copy_subscription_url")) {
                    self.appViewModel.copyTextToPasteboard(urlString)
                }
            }

            if context.showsSSIDActions || context.showsRemoteCopyAction {
                Divider()
            }
            Button(role: .destructive) {
                Task { await self.configurationStore.deleteConfigFile(named: context.name) }
            } label: {
                Text(self.tr("ui.action.delete"))
            }
        }
    }

    @ViewBuilder
    private func configMenuContent(dismiss: @escaping () -> Void) -> some View {
        let contexts = self.configMenuItemContexts()
        let localContexts = contexts.filter { !$0.isRemote }
        let remoteContexts = contexts.filter(\.isRemote)

        if !localContexts.isEmpty {
            self.configMenuSectionHeader(self.tr("ui.quick.configs.local_section"))
            ForEach(localContexts) { context in
                self.configMenuItem(for: context, dismiss: dismiss)
            }
        }

        if !remoteContexts.isEmpty {
            if !localContexts.isEmpty {
                AttachedPopoverMenuDivider()
            }
            self.configMenuSectionHeader(self.tr("ui.quick.configs.remote_section"))
            ForEach(remoteContexts) { context in
                self.configMenuItem(for: context, dismiss: dismiss)
            }
        }
        AttachedPopoverMenuDivider()
        AttachedPopoverMenuItem(
            title: self.tr("ui.quick.reload_config_list"),
            leadingSymbol: "arrow.clockwise",
            leadingTint: self.nativeInfo.opacity(T.Opacity.solid))
        {
            dismiss()
            self.configurationStore.reloadConfigs()
        }
        AttachedPopoverMenuItem(
            title: self.tr("ui.quick.import_local_config"),
            leadingSymbol: "square.and.arrow.down",
            leadingTint: self.nativePositive.opacity(T.Opacity.solid))
        {
            dismiss()
            self.configurationStore.importLocalConfigFile()
        }
        AttachedPopoverMenuItem(
            title: self.tr("ui.quick.import_remote_config"),
            leadingSymbol: "link.badge.plus",
            leadingTint: self.nativePurple.opacity(T.Opacity.solid))
        {
            dismiss()
        }
        AttachedPopoverMenuItem(
            title: self.tr("ui.quick.update_remote_configs"),
            leadingSymbol: "arrow.triangle.2.circlepath",
            leadingTint: self.nativeWarning.opacity(T.Opacity.solid))
        {
            dismiss()
            Task { await self.configurationStore.updateAllRemoteConfigFiles() }
        }
        AttachedPopoverMenuItem(
            title: self.tr("ui.quick.show_in_finder"),
            leadingSymbol: "folder",
            leadingTint: self.nativeSecondaryLabel)
        {
            dismiss()
            self.configurationStore.showSelectedConfigInFinder()
        }
        AttachedPopoverMenuDivider()
        AttachedPopoverMenuItem(
            title: self.configurationStore.ssidStrategyEnabled
                ? self.tr("ui.quick.ssid.disable_auto_switch")
                : self.tr("ui.quick.ssid.enable_auto_switch"),
            subtitle: self.ssidStrategyMenuUsageHint(),
            leadingSymbol: self.configurationStore.ssidStrategyEnabled ? "wifi.circle.fill" : "wifi.circle",
            leadingTint: self.configurationStore.ssidStrategyEnabled
                ? self.nativePositive.opacity(T.Opacity.solid)
                : self.nativeSecondaryLabel,
            trailingStatusText: self.ssidStrategyMenuStatusText(),
            trailingStatusTextColor: self.configurationStore.ssidStrategyEnabled
                ? self.nativePositive.opacity(T.Opacity.solid)
                : self.nativeSecondaryLabel)
        {
            self.configurationStore.ssidStrategyEnabled.toggle()
        }
    }

    var proxyTabBody: some View {
        VStack(alignment: .leading, spacing: T.space6) {
            self.trafficOverview
            self.proxyQuickRows
            if !self.proxyStore.sortedProxyProviderNames.isEmpty {
                proxyProvidersSection
            }
            proxyGroupsSection
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    var trafficOverview: some View {
        let sparklineHeight: CGFloat = 64
        let sparklineHorizontalInset = T.space4

        return ZStack {
            TrafficSparklineView(
                upValues: self.trafficStore.trafficHistoryUp,
                downValues: self.trafficStore.trafficHistoryDown)
                .frame(height: sparklineHeight)
                .padding(.horizontal, sparklineHorizontalInset)

            VStack(spacing: 0) {
                HStack(spacing: T.space6) {
                    self.cornerMetric(
                        symbol: "link",
                        value: "\(self.connectionsStore.connectionsCount)",
                        color: nativeIndigo)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    self.cornerMetric(
                        symbol: "arrow.up.circle",
                        value: ValueFormatter.speedAndTotal(
                            rate: self.trafficStore.traffic.up,
                            total: self.trafficStore.displayUpTotal),
                        color: nativeInfo,
                        iconTrailing: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Spacer(minLength: 0)

                HStack(spacing: T.space6) {
                    self.cornerMetric(
                        symbol: "memorychip",
                        value: ValueFormatter.bytesCompact(self.trafficStore.memory.inuse),
                        color: nativeTeal)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    self.cornerMetric(
                        symbol: "arrow.down.circle",
                        value: ValueFormatter.speedAndTotal(
                            rate: self.trafficStore.traffic.down,
                            total: self.trafficStore.displayDownTotal),
                        color: nativePositive.opacity(T.Opacity.solid),
                        iconTrailing: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, T.space4)
            .padding(.vertical, T.space2)
        }
        .frame(height: sparklineHeight)
        .padding(.top, T.space2)
    }

    func cornerMetric(
        symbol: String,
        value: String,
        color: Color,
        iconTrailing: Bool = false) -> some View
    {
        let icon = Image(systemName: symbol)
            .font(.app(size: T.FontSize.caption, weight: .semibold))
            .foregroundStyle(color)
        let text = Text(value)
            .font(.app(size: T.FontSize.body, weight: .regular))
            .foregroundStyle(nativeSecondaryLabel)
            .lineLimit(1)
            .minimumScaleFactor(T.minimumScale)

        return HStack(spacing: iconTrailing ? T.space1 : T.space2) {
            if iconTrailing {
                text; icon
            } else {
                icon; text
            }
        }
    }

    var proxyQuickRows: some View {
        let localTargetDisplay = self.appViewModel.localProxyCommandTargetDisplay()
        let managedTargetDisplay = self.appViewModel.managedEndpointProxyCommandTargetDisplay()
        let showManagedTargetAction = localTargetDisplay != managedTargetDisplay

        return VStack(spacing: 0) {
            if self.appViewModel.isRemoteTarget {
                self.quickRowContent(
                    title: self.tr("ui.quick.switch_config"),
                    symbol: "doc.text",
                    foreground: nativePurple)
                {
                    Text(self.tr("ui.machine.remote_readonly"))
                        .font(.app(size: T.FontSize.caption, weight: .regular))
                        .lineLimit(1)
                        .foregroundStyle(nativeTertiaryLabel)
                }
            } else {
                AttachedPopoverMenu(
                    onWillPresent: {
                        self.configurationStore.reloadConfigs()
                    },
                    label: { _ in
                        self.quickRowContent(
                            title: self.tr("ui.quick.switch_config"),
                            symbol: "doc.text",
                            foreground: nativePurple)
                        {
                            HStack(spacing: T.space2) {
                                Text(self.configurationStore.selectedConfigName)
                                    .font(.app(size: T.FontSize.caption, weight: .regular))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(nativeSecondaryLabel)
                                Image(systemName: "chevron.right")
                                    .font(.app(size: T.FontSize.caption, weight: .medium))
                                    .foregroundStyle(nativeTertiaryLabel)
                            }
                        }
                    },
                    content: { dismiss in
                        self.configMenuContent(dismiss: dismiss)
                    })
                    .buttonStyle(.plain)
            }

            self.systemProxyQuickToggleRow

            self.quickToggleRow(
                title: self.tr("ui.quick.tun_mode"),
                symbol: "shield.lefthalf.filled",
                foreground: nativePositive,
                isDisabled: !self.appViewModel.isTunToggleEnabled,
                isOn: Binding(
                    get: { self.settingsStore.editableSettings.tunEnabled },
                    set: { value in
                        Task { await self.proxyStore.toggleTunMode(value) }
                    }))

            self.quickRowContent(
                title: self.tr("ui.quick.copy_terminal"),
                symbol: "terminal",
                foreground: nativeWarning,
                trailingFitsContent: true)
            {
                HStack(spacing: T.space2) {
                    self.proxyCommandActionButton(
                        title: "127.0.0.1",
                        target: .local,
                        helpTitle: self.tr("ui.quick.copy_terminal"),
                        helpDetail: localTargetDisplay)
                    {
                        self.appViewModel.copyLocalProxyCommand()
                    }

                    if showManagedTargetAction {
                        self.proxyCommandActionButton(
                            title: self.appViewModel.managedEndpointProxyCommandHostDisplay(),
                            target: .currentEndpoint,
                            helpTitle: self.tr("ui.quick.copy_terminal_current_endpoint"),
                            helpDetail: managedTargetDisplay)
                        {
                            self.appViewModel.copyManagedEndpointProxyCommand()
                        }
                    }
                }
            }
        }
    }

    func proxyCommandActionButton(
        title: String,
        target: ProxyCommandCopyTarget,
        helpTitle: String,
        helpDetail: String,
        action: @escaping () -> Void) -> some View
    {
        let copied = self.copiedProxyCommandTarget == target
        let foreground = copied
            ? self.nativePositive.opacity(T.Opacity.solid)
            : self.nativeSecondaryLabel
        let iconForeground = copied
            ? self.nativePositive.opacity(T.Opacity.solid)
            : self.nativeTertiaryLabel

        return Button {
            self.handleCopyProxyCommand(target) {
                action()
            }
        } label: {
            HStack(spacing: T.space4) {
                Text(title)
                    .font(.app(size: T.FontSize.caption, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(T.minimumScale)
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.app(size: T.FontSize.caption, weight: .semibold))
                    .foregroundStyle(iconForeground)
            }
            .padding(T.space2)
            .background {
                Capsule(style: .continuous)
                    .fill(copied ? self.nativePositive.opacity(T.Opacity.tint) : self.nativeBadgeFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                copied
                                    ? self.nativePositive.opacity(0.18)
                                    : self.nativeControlBorder.opacity(0.42),
                                lineWidth: T.stroke)
                    }
            }
        }
        .buttonStyle(.plain)
        .help("\(helpTitle)\n\(helpDetail)")
    }

    var systemProxyRowDetailText: String? {
        if let failureHint = self.systemProxyInlineFailureText {
            return failureHint
        }

        return nil
    }

    func quickRowContent(
        title: String,
        symbol: String,
        foreground: Color,
        trailingWidth: CGFloat? = nil,
        trailingFitsContent: Bool = false,
        @ViewBuilder trailing: () -> some View) -> some View
    {
        HStack(spacing: T.space6) {
            self.quickIcon(symbol: symbol, foreground: foreground)
            Text(title)
                .font(.app(size: T.FontSize.body, weight: .medium))
                .foregroundStyle(nativePrimaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(T.minimumScale)
            Spacer(minLength: 0)
            if trailingFitsContent {
                trailing()
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                trailing()
                    .frame(width: trailingWidth ?? self.quickRowTrailingColumnWidth, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.space4)
        .padding(.vertical, T.space2)
    }

    var systemProxyRowTitle: String {
        if let scopeLabel = self.systemProxyScopeLabel {
            return "\(self.tr("ui.quick.system_proxy")) (\(scopeLabel))"
        }
        return self.tr("ui.quick.system_proxy")
    }

    var systemProxyRowDetailColor: Color {
        if self.systemProxyInlineFailureText != nil {
            return nativeWarning.opacity(T.Opacity.solid)
        }
        return nativeSecondaryLabel
    }

    var systemProxyQuickToggleRow: some View {
        HStack(spacing: T.space6) {
            self.systemProxyCompositeIcon
            HStack(spacing: T.space2) {
                Text(self.systemProxyRowTitle)
                    .font(.app(size: T.FontSize.body, weight: .medium))
                    .foregroundStyle(nativePrimaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(T.minimumScale)

                if self.shouldShowSystemProxyRemoteWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(nativeWarning.opacity(T.Opacity.solid))
                        .help(self.tr("ui.system_proxy.remote_target_warning"))
                        .accessibilityLabel(self.tr("ui.system_proxy.remote_target_warning"))
                }
            }

            if let detailText = self.systemProxyRowDetailText {
                Text(detailText)
                    .font(.app(size: T.FontSize.caption, weight: .medium))
                    .foregroundStyle(self.systemProxyRowDetailColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(T.minimumScale)
            }

            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { self.proxyStore.isSystemProxyEnabled },
                set: { value in
                    Task { await self.proxyStore.toggleSystemProxy(value) }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(self.proxyStore.isProxySyncing)
                .frame(width: 50, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.space4)
        .padding(.vertical, T.space2)
    }

    var systemProxyInlineFailureText: String? {
        guard !self.proxyStore.isSystemProxyEnabled else { return nil }
        return self.proxyStore.systemProxyOpenFailureHint?.trimmedNonEmpty
    }

    var systemProxyScopeLabel: String? {
        if self.proxyStore.isSystemProxyUsingRemoteCore {
            return self.tr("ui.machine.remote_label")
        }
        if self.appViewModel.isRemoteTarget {
            return self.tr("ui.machine.local_label")
        }
        return nil
    }

    var shouldShowSystemProxyRemoteWarning: Bool {
        self.proxyStore.isSystemProxyUsingRemoteCore
    }

    func quickToggleRow(
        title: String,
        symbol: String,
        foreground: Color,
        isDisabled: Bool,
        isOn: Binding<Bool>) -> some View
    {
        self.quickRowContent(
            title: title,
            symbol: symbol,
            foreground: foreground,
            trailingWidth: 50)
        {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isDisabled)
        }
    }

    func quickIcon(symbol: String, foreground: Color) -> some View {
        Image(systemName: symbol)
            .font(.app(size: T.FontSize.body, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 18, height: 18, alignment: .center)
    }

    var systemProxyCompositeIcon: some View {
        ZStack {
            self.systemProxyCompositeIconLayer(
                tint: self.systemProxyBackgroundActivityTint,
                alignment: .leading)
            self.systemProxyCompositeIconLayer(
                tint: self.systemProxyHelperProcessTint,
                alignment: .trailing)
        }
        .frame(width: 18, height: 18)
        .help(self.systemProxyCompositeIconHelp)
    }

    func systemProxyCompositeIconLayer(tint: Color, alignment: Alignment) -> some View {
        Image(systemName: "network")
            .font(.app(size: T.FontSize.body, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 18, height: 18)
            .mask(alignment: alignment) {
                Rectangle()
                    .frame(width: 9)
            }
    }

    var systemProxyBackgroundActivityTint: Color {
        switch self.proxyStore.systemProxyBackgroundActivityAllowed {
        case .some(true):
            nativePositive.opacity(T.Opacity.solid)
        case .some(false):
            nativeCritical.opacity(T.Opacity.solid)
        case .none:
            nativeSecondaryLabel
        }
    }

    var systemProxyHelperProcessTint: Color {
        switch self.proxyStore.systemProxyHelperProcessRunning {
        case .some(true):
            nativePositive.opacity(T.Opacity.solid)
        case .some(false):
            nativeWarning.opacity(T.Opacity.solid)
        case .none:
            nativeSecondaryLabel
        }
    }

    var systemProxyBackgroundActivityHelp: String {
        let value = switch self.proxyStore.systemProxyBackgroundActivityAllowed {
        case .some(true):
            self.tr("ui.system_proxy.background_activity.allowed")
        case .some(false):
            self.tr("ui.system_proxy.background_activity.blocked")
        case .none:
            self.tr("ui.common.unknown")
        }
        return "\(self.tr("ui.system_proxy.background_activity")): \(value)"
    }

    var systemProxyHelperProcessHelp: String {
        let value = switch self.proxyStore.systemProxyHelperProcessRunning {
        case .some(true):
            self.tr("ui.system_proxy.helper_process.running")
        case .some(false):
            self.tr("ui.system_proxy.helper_process.stopped")
        case .none:
            self.tr("ui.common.unknown")
        }
        return "\(self.tr("ui.system_proxy.helper_process")): \(value)"
    }

    var systemProxyCompositeIconHelp: String {
        "\(self.systemProxyBackgroundActivityHelp)\n\(self.systemProxyHelperProcessHelp)"
    }
}

private struct ConfigMenuItemView: View {
    let title: String
    let leadingSymbol: String?
    let leadingTint: Color
    let selected: Bool
    let subtitle: String?
    let itemHelpText: String?
    let ssidBadgeText: String?
    let ssidBadgeTint: Color
    let ssidBadgeHelpText: String?
    let refreshPhase: RemoteConfigRefreshPhase?
    let refreshHelpText: String
    let refreshingAccessibilityLabel: String
    let refreshFailedHelpText: String
    let onSelect: () -> Void
    let onRefresh: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: T.space6) {
            self.selectionButton

            if let refreshPhase, let onRefresh {
                self.refreshControl(phase: refreshPhase, onRefresh: onRefresh)
            }
        }
        .padding(.horizontal, T.space6)
        .padding(.vertical, T.space2)
        .background(
            RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                .fill(self.rowBackground))
        .contentShape(Rectangle())
        .onHover { self.isHovered = $0 }
    }

    private var selectionButton: some View {
        Button(action: self.onSelect) {
            HStack(alignment: .center, spacing: T.space6) {
                if let leadingSymbol {
                    Image(systemName: leadingSymbol)
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(self.leadingSymbolForeground)
                        .frame(width: 12, alignment: .center)
                }

                VStack(alignment: .leading, spacing: T.space1) {
                    HStack(spacing: T.space4) {
                        Text(self.title)
                            .font(.app(size: T.FontSize.body, weight: self.selected ? .semibold : .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(self.primaryTextColor)
                            .layoutPriority(1)

                        if let ssidBadgeText {
                            ConfigSSIDBadge(
                                text: ssidBadgeText,
                                tint: self.ssidBadgeTint,
                                isHovered: self.isHovered)
                                .help(self.ssidBadgeHelpText ?? ssidBadgeText)
                        }
                    }

                    if let subtitle = self.subtitle?.trimmedNonEmpty {
                        Text(subtitle)
                            .font(.app(size: T.FontSize.caption, weight: .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .monospacedDigit()
                            .foregroundStyle(self.secondaryTextColor)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(self.itemHelpText ?? self.title)
    }

    private func refreshControl(
        phase: RemoteConfigRefreshPhase,
        onRefresh: @escaping () -> Void) -> some View
    {
        let failureTint = self.nativeCritical
        let helpText: String
        let tint: Color
        let baseTint: Color
        let isLoading = phase == .refreshing

        switch phase {
        case .idle:
            helpText = self.refreshHelpText
            tint = self.nativeAccent
            baseTint = self.secondaryTextColor
        case .refreshing:
            helpText = self.refreshingAccessibilityLabel
            tint = self.secondaryTextColor
            baseTint = self.secondaryTextColor
        case .failed:
            helpText = self.refreshFailedHelpText
            tint = failureTint
            baseTint = failureTint.opacity(0.92)
        }

        return CompactAsyncIconButton(
            symbol: "arrow.clockwise",
            tint: tint,
            baseTint: baseTint,
            role: nil,
            isLoading: isLoading,
            size: 20,
            fontSize: T.FontSize.body,
            hierarchicalSymbol: false,
            action: { onRefresh() })
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var primaryTextColor: Color {
        if self.isHovered {
            return self.nativeSelectedMenuText
        }
        return self.nativePrimaryLabel
    }

    private var secondaryTextColor: Color {
        if self.isHovered {
            return self.nativeSelectedMenuText.opacity(0.88)
        }
        return self.selected ? self.nativePrimaryLabel.opacity(0.72) : self.nativeSecondaryLabel
    }

    private var leadingSymbolForeground: Color {
        if self.isHovered {
            return self.nativeSelectedMenuText
        }
        return self.leadingTint
    }

    private var rowBackground: Color {
        if self.isHovered {
            return self.nativeHoverFill
        }
        if self.selected {
            return self.nativeHoverFill.opacity(0.34)
        }
        return .clear
    }
}

private struct ConfigSSIDBadge: View {
    let text: String
    let tint: Color
    let isHovered: Bool

    var body: some View {
        Text(self.text)
            .font(.app(size: T.FontSize.caption, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(self.foreground)
            .padding(.horizontal, T.space4)
            .padding(.vertical, T.space1)
            .background(
                Capsule(style: .continuous)
                    .fill(self.background))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(self.border, lineWidth: T.stroke)
            }
            .frame(maxWidth: 132)
    }

    private var foreground: Color {
        if self.isHovered {
            return self.nativeSelectedMenuText.opacity(0.96)
        }
        return self.tint
    }

    private var background: Color {
        if self.isHovered {
            return self.nativeSelectedMenuText.opacity(0.14)
        }
        return self.tint.opacity(0.12)
    }

    private var border: Color {
        if self.isHovered {
            return self.nativeSelectedMenuText.opacity(0.18)
        }
        return self.tint.opacity(0.18)
    }
}
