import SwiftUI

private typealias T = MenuBarLayoutTokens

extension MenuBarRoot {
    var quickRowTrailingColumnWidth: CGFloat {
        min(170, max(126, contentWidth * 0.44))
    }

    var proxyTabBody: some View {
        VStack(alignment: .leading, spacing: T.space6) {
            self.trafficOverview
            self.proxyQuickRows
            if !appState.sortedProxyProviderNames.isEmpty {
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
                upValues: appState.trafficHistoryUp,
                downValues: appState.trafficHistoryDown)
                .frame(height: sparklineHeight)
                .padding(.horizontal, sparklineHorizontalInset)

            VStack(spacing: 0) {
                HStack(spacing: T.space6) {
                    self.cornerMetric(
                        symbol: "link",
                        value: "\(appState.connectionsCount)",
                        color: nativeIndigo)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    self.cornerMetric(
                        symbol: "arrow.up.circle",
                        value: ValueFormatter.speedAndTotal(
                            rate: appState.traffic.up,
                            total: appState.displayUpTotal),
                        color: nativeInfo,
                        iconTrailing: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Spacer(minLength: 0)

                HStack(spacing: T.space6) {
                    self.cornerMetric(
                        symbol: "memorychip",
                        value: ValueFormatter.bytesInteger(appState.memory.inuse),
                        color: nativeTeal)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    self.cornerMetric(
                        symbol: "arrow.down.circle",
                        value: ValueFormatter.speedAndTotal(
                            rate: appState.traffic.down,
                            total: appState.displayDownTotal),
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
            AttachedPopoverMenu {
                self.quickRowContent(
                    title: tr("ui.quick.switch_config"),
                    symbol: "doc.text",
                    foreground: nativePurple,
                    background: nativePurple.opacity(T.Opacity.tint))
                {
                    HStack(spacing: T.space2) {
                        Text(appState.selectedConfigName)
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
                ForEach(appState.availableConfigFileNames, id: \.self) { name in
                    AttachedPopoverMenuItem(
                        title: name,
                        selected: name == appState.selectedConfigName)
                    {
                        dismiss()
                        Task { await appState.selectConfigFile(named: name) }
                    }
                }
                AttachedPopoverMenuDivider()
                AttachedPopoverMenuItem(title: tr("ui.quick.reload_config_list")) {
                    dismiss()
                    appState.reloadConfigFileList()
                }
                AttachedPopoverMenuItem(title: tr("ui.quick.import_local_config")) {
                    dismiss()
                    appState.importLocalConfigFile()
                }
                AttachedPopoverMenuItem(title: tr("ui.quick.import_remote_config")) {
                    dismiss()
                    Task { await appState.importRemoteConfigFile() }
                }
                AttachedPopoverMenuItem(title: tr("ui.quick.update_remote_configs")) {
                    dismiss()
                    Task { await appState.updateAllRemoteConfigFiles() }
                }
                AttachedPopoverMenuItem(title: tr("ui.quick.show_in_finder")) {
                    dismiss()
                    appState.showSelectedConfigInFinder()
                }
            }
            .buttonStyle(.plain)

            self.quickToggleRow(
                title: tr("ui.quick.system_proxy"),
                symbol: "network",
                foreground: nativeInfo,
                background: nativeInfo.opacity(T.Opacity.tint),
                isDisabled: appState.isProxySyncing,
                isOn: Binding(
                    get: { appState.isSystemProxyEnabled },
                    set: { value in
                        Task { await appState.toggleSystemProxy(value) }
                    }))

            self.quickToggleRow(
                title: tr("ui.quick.tun_mode"),
                symbol: "shield.lefthalf.filled",
                foreground: nativePositive,
                background: nativePositive.opacity(T.Opacity.tint),
                isDisabled: !appState.isTunToggleEnabled,
                isOn: Binding(
                    get: { appState.isTunEnabled },
                    set: { value in
                        Task { await appState.toggleTunMode(value) }
                    }))

            Button {
                appState.copyProxyCommand()
            } label: {
                self.quickRowContent(
                    title: tr("ui.quick.copy_terminal"),
                    symbol: "terminal",
                    foreground: nativeWarning,
                    background: nativeWarning.opacity(T.Opacity.tint))
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
        background: Color,
        @ViewBuilder trailing: () -> some View) -> some View
    {
        HStack(spacing: T.space6) {
            self.quickIcon(symbol: symbol, foreground: foreground, background: background)
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
        background: Color,
        isDisabled: Bool,
        isOn: Binding<Bool>) -> some View
    {
        self.quickRowContent(
            title: title,
            symbol: symbol,
            foreground: foreground,
            background: background)
        {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isDisabled)
        }
    }

    func quickIcon(symbol: String, foreground: Color, background: Color) -> some View {
        RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
            .fill(background)
            .frame(
                width: T.rowLeadingIcon,
                height: T.rowLeadingIcon)
            .overlay {
                Image(systemName: symbol)
                    .font(.app(size: T.FontSize.body, weight: .semibold))
                    .foregroundStyle(foreground)
            }
    }
}
