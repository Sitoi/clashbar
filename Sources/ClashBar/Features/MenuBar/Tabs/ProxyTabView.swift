import AppKit
import SwiftUI

extension MenuBarRoot {
    var proxyModuleSpacing: CGFloat {
        MenuBarLayoutTokens.sectionGap
    }

    var quickRowTrailingColumnWidth: CGFloat {
        min(170, max(126, contentWidth * 0.44))
    }

    var proxyTabBody: some View {
        VStack(alignment: .leading, spacing: self.proxyModuleSpacing) {
            self.trafficOverview
            self.proxyQuickRows
            if !appState.sortedProxyProviderNames.isEmpty {
                proxyProvidersSection
            }
            proxyGroupsSection
        }
    }

    var trafficOverview: some View {
        let sparklineHeight: CGFloat = 64
        let sparklineHorizontalInset = MenuBarLayoutTokens.hRow

        return ZStack {
            TrafficSparklineView(
                upValues: appState.trafficHistoryUp,
                downValues: appState.trafficHistoryDown)
                .frame(height: sparklineHeight)
                .padding(.horizontal, sparklineHorizontalInset)

            VStack(spacing: 0) {
                HStack(spacing: MenuBarLayoutTokens.hDense) {
                    self.cornerIconMetric(
                        symbol: "link",
                        value: "\(appState.connectionsCount)",
                        color: nativeIndigo)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    self.cornerTrafficMetric(
                        symbol: "arrow.up.circle",
                        color: nativeInfo,
                        value: ValueFormatter.speedAndTotal(
                            rate: appState.traffic.up,
                            total: appState.displayUpTotal))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Spacer(minLength: 0)

                HStack(spacing: MenuBarLayoutTokens.hDense) {
                    self.cornerIconMetric(
                        symbol: "memorychip",
                        value: ValueFormatter.bytesInteger(appState.memory.inuse),
                        color: nativeTeal)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    self.cornerTrafficMetric(
                        symbol: "arrow.down.circle",
                        color: nativePositive.opacity(0.92),
                        value: ValueFormatter.speedAndTotal(
                            rate: appState.traffic.down,
                            total: appState.displayDownTotal))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, MenuBarLayoutTokens.hRow)
            .padding(.vertical, MenuBarLayoutTokens.vDense)
        }
        .frame(height: sparklineHeight)
        .padding(.top, MenuBarLayoutTokens.vDense)
    }

    func cornerIconMetric(
        symbol: String,
        value: String,
        color: Color) -> some View
    {
        HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
            Image(systemName: symbol)
                .font(.appSystem(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.appMonospaced(size: 12, weight: .regular))
                .foregroundStyle(nativeSecondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.80)
        }
    }

    func cornerTrafficMetric(
        symbol: String,
        color: Color,
        value: String) -> some View
    {
        HStack(spacing: MenuBarLayoutTokens.hMicro) {
            Text(value)
                .font(.appMonospaced(size: 12, weight: .regular))
                .foregroundStyle(nativeSecondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.80)
            Image(systemName: symbol)
                .font(.appSystem(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    var proxyQuickRows: some View {
        let rowHorizontalPadding = MenuBarLayoutTokens.hRow
        let rowVerticalPadding: CGFloat = MenuBarLayoutTokens.vDense + 1
        let trailingColumnWidth = self.quickRowTrailingColumnWidth

        return VStack(spacing: 0) {
            AttachedPopoverMenu {
                HStack(spacing: MenuBarLayoutTokens.hDense) {
                    self.quickIcon(symbol: "doc.text", foreground: nativePurple, background: nativePurple.opacity(0.14))
                    Text(tr("ui.quick.switch_config"))
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundStyle(nativePrimaryLabel)
                    Spacer(minLength: 0)
                    HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
                        Text(appState.selectedConfigName)
                            .font(.appSystem(size: 11, weight: .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(nativeSecondaryLabel)
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 10, weight: .medium))
                            .foregroundStyle(nativeTertiaryLabel)
                    }
                    .frame(width: trailingColumnWidth, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, rowHorizontalPadding)
                .padding(.vertical, rowVerticalPadding)
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

            self.quickRowsDivider

            HStack(spacing: MenuBarLayoutTokens.hDense) {
                self.quickIcon(symbol: "network", foreground: nativeInfo, background: nativeInfo.opacity(0.14))
                Text(tr("ui.quick.system_proxy"))
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundStyle(nativePrimaryLabel)
                Spacer(minLength: 0)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { appState.isSystemProxyEnabled },
                        set: { value in
                            Task { await appState.toggleSystemProxy(value) }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(appState.isProxySyncing)
                        .frame(width: trailingColumnWidth, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)

            self.quickRowsDivider

            HStack(spacing: MenuBarLayoutTokens.hDense) {
                self.quickIcon(
                    symbol: "shield.lefthalf.filled",
                    foreground: nativePositive,
                    background: nativePositive.opacity(0.14))
                Text(tr("ui.quick.tun_mode"))
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundStyle(nativePrimaryLabel)
                Spacer(minLength: 0)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { appState.isTunEnabled },
                        set: { value in
                            Task { await appState.toggleTunMode(value) }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!appState.isTunToggleEnabled)
                        .frame(width: trailingColumnWidth, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)

            self.quickRowsDivider

            Button {
                appState.copyProxyCommand()
            } label: {
                HStack(spacing: MenuBarLayoutTokens.hDense) {
                    self.quickIcon(
                        symbol: "terminal",
                        foreground: nativeWarning,
                        background: nativeWarning.opacity(0.14))
                    Text(tr("ui.quick.copy_terminal"))
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundStyle(nativePrimaryLabel)
                    Spacer(minLength: 0)
                    Image(systemName: "doc.on.doc")
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundStyle(hoveringCopyRow ? nativeSecondaryLabel : nativeTertiaryLabel.opacity(0.6))
                        .frame(width: trailingColumnWidth, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, rowHorizontalPadding)
                .padding(.vertical, rowVerticalPadding)
            }
            .buttonStyle(.plain)
            .onHover { hoveringCopyRow = $0 }
        }
    }

    var quickRowsDivider: some View {
        EmptyView()
    }

    func quickIcon(symbol: String, foreground: Color, background: Color) -> some View {
        RoundedRectangle(cornerRadius: MenuBarLayoutTokens.iconCornerRadius, style: .continuous)
            .fill(background)
            .frame(
                width: MenuBarLayoutTokens.rowLeadingIconSize,
                height: MenuBarLayoutTokens.rowLeadingIconSize)
            .overlay {
                Image(systemName: symbol)
                    .font(.appSystem(size: 12, weight: .semibold))
                    .foregroundStyle(foreground)
            }
    }
}
