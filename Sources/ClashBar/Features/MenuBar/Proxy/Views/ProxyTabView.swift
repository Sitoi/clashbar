import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

extension MenuBarRootView {
    var quickRowTrailingColumnWidth: CGFloat {
        min(170, max(126, contentWidth * 0.44))
    }

    var proxyTabBody: some View {
        VStack(alignment: .leading, spacing: T.space6) {
            self.trafficOverview
            self.proxyQuickRows
            if !appSession.sortedProxyProviderNames.isEmpty {
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
                upValues: appSession.trafficHistoryUp,
                downValues: appSession.trafficHistoryDown)
                .frame(height: sparklineHeight)
                .padding(.horizontal, sparklineHorizontalInset)

            VStack(spacing: 0) {
                HStack(spacing: T.space6) {
                    self.cornerMetric(
                        symbol: "link",
                        value: "\(connectionsStore.connectionsCount)",
                        color: nativeIndigo)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    self.cornerMetric(
                        symbol: "arrow.up.circle",
                        value: ValueFormatter.speedAndTotal(
                            rate: appSession.traffic.up,
                            total: appSession.displayUpTotal),
                        color: nativeInfo,
                        iconTrailing: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Spacer(minLength: 0)

                HStack(spacing: T.space6) {
                    self.cornerMetric(
                        symbol: "memorychip",
                        value: ValueFormatter.bytesInteger(appSession.memory.inuse),
                        color: nativeTeal)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    self.cornerMetric(
                        symbol: "arrow.down.circle",
                        value: ValueFormatter.speedAndTotal(
                            rate: appSession.traffic.down,
                            total: appSession.displayDownTotal),
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
            if iconTrailing { text; icon } else { icon; text }
        }
    }

    var proxyQuickRows: some View {
        VStack(spacing: 0) {
            AttachedPopoverMenu { _ in
                self.quickRowContent(
                    title: tr("ui.quick.switch_config"),
                    symbol: "doc.text",
                    foreground: nativePurple)
                {
                    HStack(spacing: T.space2) {
                        Text(appSession.selectedConfigName)
                            .font(.app(size: T.FontSize.caption, weight: .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(nativeSecondaryLabel)
                        Image(systemName: "chevron.right")
                            .font(.app(size: T.FontSize.caption, weight: .medium))
                            .foregroundStyle(nativeTertiaryLabel)
                    }
                }
            } content: { dismiss in
                ForEach(appSession.availableConfigFileNames, id: \.self) { name in
                    AttachedPopoverMenuItem(
                        title: name,
                        selected: name == appSession.selectedConfigName)
                    {
                        dismiss()
                        Task { await appSession.selectConfigFile(named: name) }
                    }
                }
                AttachedPopoverMenuDivider()
                AttachedPopoverMenuItem(title: tr("ui.quick.reload_config_list")) {
                    dismiss()
                    appSession.reloadConfigFileList()
                }
                AttachedPopoverMenuItem(title: tr("ui.quick.import_local_config")) {
                    dismiss()
                    appSession.importLocalConfigFile()
                }
                AttachedPopoverMenuItem(title: tr("ui.quick.import_remote_config")) {
                    dismiss()
                    Task { await appSession.importRemoteConfigFile() }
                }
                AttachedPopoverMenuItem(title: tr("ui.quick.update_remote_configs")) {
                    dismiss()
                    Task { await appSession.updateAllRemoteConfigFiles() }
                }
                AttachedPopoverMenuItem(title: tr("ui.quick.show_in_finder")) {
                    dismiss()
                    appSession.showSelectedConfigInFinder()
                }
            }
            .buttonStyle(.plain)

            self.quickToggleRow(
                title: tr("ui.quick.system_proxy"),
                symbol: "network",
                foreground: nativeInfo,
                isDisabled: appSession.isProxySyncing,
                isOn: Binding(
                    get: { appSession.isSystemProxyEnabled },
                    set: { value in
                        Task { await appSession.toggleSystemProxy(value) }
                    }))

            self.quickToggleRow(
                title: tr("ui.quick.tun_mode"),
                symbol: "shield.lefthalf.filled",
                foreground: nativePositive,
                isDisabled: !appSession.isTunToggleEnabled,
                isOn: Binding(
                    get: { appSession.isTunEnabled },
                    set: { value in
                        Task { await appSession.toggleTunMode(value) }
                    }))

            Button {
                appSession.copyProxyCommand()
            } label: {
                self.quickRowContent(
                    title: tr("ui.quick.copy_terminal"),
                    symbol: "terminal",
                    foreground: nativeWarning)
                {
                    Image(systemName: "doc.on.doc")
                        .font(.app(size: T.FontSize.body, weight: .medium))
                        .foregroundStyle(hoveringCopyRow ? nativeSecondaryLabel : nativeTertiaryLabel.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .onHover { hoveringCopyRow = $0 }
        }
    }

    func quickRowContent(
        title: String,
        symbol: String,
        foreground: Color,
        @ViewBuilder trailing: () -> some View) -> some View
    {
        HStack(spacing: T.space6) {
            self.quickIcon(symbol: symbol, foreground: foreground)
            Text(title)
                .font(.app(size: T.FontSize.body, weight: .medium))
                .foregroundStyle(nativePrimaryLabel)
            Spacer(minLength: 0)
            trailing()
                .frame(width: self.quickRowTrailingColumnWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.space4)
        .padding(.vertical, T.space2)
    }

    // swiftlint:disable:next function_parameter_count
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
            foreground: foreground)
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
}
