import SwiftUI

extension MenuBarRoot {
    var settingsMenuControlWidth: CGFloat {
        min(152, max(118, contentWidth * 0.43))
    }

    var settingsPortFieldWidth: CGFloat {
        min(108, max(92, contentWidth * 0.30))
    }

    var maintenanceActionEnabled: Bool {
        appState.processManager.isRunning || appState.statusText.lowercased() == "running"
    }

    var portAutoSaving: Bool {
        appState.settingsSyncingKey == "ports-auto" || appState.settingsSyncingKey == "ports"
    }

    var settingsFeedbackState: (message: String, color: Color, symbol: String)? {
        if let error = appState.settingsErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty
        {
            return (error, nativeCritical.opacity(0.92), "exclamationmark.triangle.fill")
        }

        if let launchError = appState.launchAtLoginErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !launchError.isEmpty
        {
            return (launchError, nativeWarning.opacity(0.92), "exclamationmark.circle.fill")
        }

        if let saved = appState.settingsSavedMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty
        {
            return (saved, nativePositive.opacity(0.92), "checkmark.circle.fill")
        }

        return nil
    }

    var systemTabBody: some View {
        let proxyPortFields: [(titleKey: String, symbol: String, text: Binding<String>)] = [
            ("ui.settings.port.port", "network", $appState.settingsPort),
            ("ui.settings.port.socks", "wave.3.right", $appState.settingsSocksPort),
            ("ui.settings.port.mixed", "arrow.triangle.merge", $appState.settingsMixedPort),
            ("ui.settings.port.redir", "arrowshape.turn.up.right", $appState.settingsRedirPort),
            ("ui.settings.port.tproxy", "shield.lefthalf.filled", $appState.settingsTProxyPort),
        ]
        let maintenanceActions: [(titleKey: String, symbol: String, action: @MainActor () async -> Void)] = [
            ("ui.action.flush_fakeip_cache", "externaldrive.badge.minus", { await appState.flushFakeIPCache() }),
            ("ui.action.flush_dns_cache", "network.badge.shield.half.filled", { await appState.flushDNSCache() }),
        ]

        return VStack(alignment: .leading, spacing: MenuBarLayoutTokens.sectionGap) {
            if let feedback = settingsFeedbackState {
                settingsFeedbackBanner(
                    text: feedback.message,
                    color: feedback.color,
                    symbol: feedback.symbol)
            }

            VStack(spacing: 0) {
                settingsCardHeader(
                    tr("ui.section.basic_settings"),
                    symbol: "slider.horizontal.3")
                settingsDivider
                settingsToggleRow(
                    tr("ui.settings.auto_start_core"),
                    symbol: "power.circle",
                    isOn: Binding(
                        get: { appState.autoStartCoreEnabled },
                        set: { appState.autoStartCoreEnabled = $0 }))
                settingsDivider
                settingsToggleRow(
                    tr("ui.settings.auto_core_network_recovery"),
                    symbol: "network.badge.shield.half.filled",
                    isOn: Binding(
                        get: { appState.autoManageCoreOnNetworkChangeEnabled },
                        set: { appState.autoManageCoreOnNetworkChangeEnabled = $0 }))
                settingsDivider
                settingsToggleRow(
                    tr("ui.settings.launch_at_login"),
                    symbol: "person.crop.circle.badge.checkmark",
                    isOn: Binding(
                        get: { appState.launchAtLoginEnabled },
                        set: { appState.applyLaunchAtLogin($0) }))
                settingsDivider
                settingsMenuRow(
                    tr("ui.settings.menu_bar_style"),
                    symbol: "menubar.rectangle",
                    valueText: statusBarModeLabel(appState.statusBarDisplayMode))
                { dismiss in
                    ForEach(StatusBarDisplayMode.allCases) { mode in
                        AttachedPopoverMenuItem(
                            title: statusBarModeLabel(mode),
                            selected: appState.statusBarDisplayMode == mode)
                        {
                            appState.statusBarDisplayMode = mode
                            dismiss()
                        }
                    }
                }
                settingsDivider
                settingsMenuRow(
                    tr("ui.settings.language"),
                    symbol: "character.book.closed",
                    valueText: appState.uiLanguage == .zhHans ? tr("ui.language.zh_hans") : tr(
                        "ui.language.en"))
                { dismiss in
                    AttachedPopoverMenuItem(
                        title: tr("ui.language.zh_hans"),
                        selected: appState.uiLanguage == .zhHans)
                    {
                        appState.setUILanguage(.zhHans)
                        dismiss()
                    }
                    AttachedPopoverMenuItem(
                        title: tr("ui.language.en"),
                        selected: appState.uiLanguage == .en)
                    {
                        appState.setUILanguage(.en)
                        dismiss()
                    }
                }
                settingsDivider
                settingsMenuRow(
                    tr("ui.settings.appearance"),
                    symbol: "circle.lefthalf.filled",
                    valueText: appearanceModeLabel(appState.appearanceMode))
                { dismiss in
                    ForEach(AppAppearanceMode.allCases) { mode in
                        AttachedPopoverMenuItem(
                            title: appearanceModeLabel(mode),
                            selected: appState.appearanceMode == mode)
                        {
                            appState.setAppearanceMode(mode)
                            dismiss()
                        }
                    }
                }
                settingsDivider
                settingsToggleRow(
                    tr("ui.settings.allow_lan"),
                    symbol: "network",
                    isOn: Binding(
                        get: { appState.settingsAllowLan },
                        set: { value in Task { await appState.applySettingAllowLan(value) } }))
                settingsDivider
                settingsToggleRow(
                    tr("ui.settings.ipv6"),
                    symbol: "globe",
                    isOn: Binding(
                        get: { appState.settingsIPv6 },
                        set: { value in Task { await appState.applySettingIPv6(value) } }))
                settingsDivider
                settingsToggleRow(
                    tr("ui.settings.unified_delay"),
                    symbol: "gauge.with.dots.needle.50percent",
                    isOn: Binding(
                        get: { appState.settingsUnifiedDelay },
                        set: { value in Task { await appState.applySettingUnifiedDelay(value) } }))
                settingsDivider
                settingsToggleRow(
                    tr("ui.settings.tun_mode"),
                    symbol: "shield.lefthalf.filled",
                    isOn: Binding(
                        get: { appState.isTunEnabled },
                        set: { value in Task { await appState.applySettingTunMode(value) } }))
                    .disabled(!appState.isTunToggleEnabled)
                settingsDivider
                settingsMenuRow(
                    tr("ui.settings.log_level"),
                    symbol: "text.alignleft",
                    valueText: appState.settingsLogLevel)
                { dismiss in
                    ForEach(ConfigLogLevel.allCases, id: \.rawValue) { level in
                        AttachedPopoverMenuItem(
                            title: level.rawValue,
                            selected: appState.settingsLogLevel
                                .caseInsensitiveCompare(level.rawValue) == .orderedSame)
                        {
                            dismiss()
                            Task { await appState.applySettingLogLevel(level.rawValue) }
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                settingsCardHeader(
                    tr("ui.section.proxy_ports"),
                    symbol: "point.3.connected.trianglepath.dotted")
                settingsDivider

                VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense + 2) {
                    HStack(spacing: MenuBarLayoutTokens.hDense) {
                        Text(tr("ui.settings.ports_auto_save_hint"))
                            .font(.appSystem(size: 11, weight: .regular))
                            .foregroundStyle(nativeSecondaryLabel)

                        Spacer(minLength: 0)

                        if self.portAutoSaving {
                            HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text(tr("ui.settings.ports_auto_saving"))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(nativeSecondaryLabel)
                            }
                        }
                    }

                    ForEach(proxyPortFields, id: \.titleKey) { item in
                        settingsPortFieldRow(
                            tr(item.titleKey),
                            symbol: item.symbol,
                            text: item.text)
                    }
                }
                .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
            }

            VStack(spacing: 0) {
                settingsCardHeader(
                    tr("ui.section.maintenance"),
                    symbol: "wrench.and.screwdriver")
                settingsDivider

                VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense + 2) {
                    HStack(spacing: MenuBarLayoutTokens.hDense) {
                        ForEach(maintenanceActions, id: \.titleKey) { item in
                            maintenanceActionButton(tr(item.titleKey), symbol: item.symbol) {
                                await item.action()
                            }
                        }
                    }

                    HStack(spacing: MenuBarLayoutTokens.hDense) {
                        Button {
                            appState.showCoreDirectoryInFinder()
                        } label: {
                            Label(tr("ui.action.open_core_directory"), systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
            }
        }
    }
}
