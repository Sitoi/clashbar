import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

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
        if let error = appState.settingsErrorMessage.trimmedNonEmpty {
            return (error, nativeCritical.opacity(T.Opacity.solid), "exclamationmark.triangle.fill")
        }

        if let launchError = appState.launchAtLoginErrorMessage.trimmedNonEmpty {
            return (launchError, nativeWarning.opacity(T.Opacity.solid), "exclamationmark.circle.fill")
        }

        if let saved = appState.settingsSavedMessage.trimmedNonEmpty {
            return (saved, nativePositive.opacity(T.Opacity.solid), "checkmark.circle.fill")
        }

        return nil
    }

    func editableCoreSettingBinding(_ setting: AppState.EditableCoreSetting) -> Binding<Bool> {
        Binding(
            get: { self.appState.boolValue(for: setting) },
            set: { value in
                Task { await self.appState.applyEditableCoreSetting(setting, to: value) }
            })
    }

    var systemTabBody: some View {
        let proxyPortFields: [(titleKey: String, symbol: String, text: Binding<String>)] = [
            ("ui.settings.port.port", "network", $appState.settingsPort),
            ("ui.settings.port.socks", "wave.3.right", $appState.settingsSocksPort),
            ("ui.settings.port.mixed", "arrow.triangle.merge", $appState.settingsMixedPort),
            ("ui.settings.port.redir", "arrowshape.turn.up.right", $appState.settingsRedirPort),
            ("ui.settings.port.tproxy", "shield.lefthalf.filled", $appState.settingsTProxyPort),
        ]
        let toggleItems: [(id: String, title: String, symbol: String, isOn: Binding<Bool>)] = [
            (
                "launch-at-login",
                tr("ui.settings.launch_at_login"),
                "person.crop.circle.badge.checkmark",
                Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.applyLaunchAtLogin($0) })),
            (
                "auto-start-core",
                tr("ui.settings.auto_start_core"),
                "power.circle",
                Binding(
                    get: { appState.autoStartCoreEnabled },
                    set: { appState.autoStartCoreEnabled = $0 })),
            (
                "auto-core-network-recovery",
                tr("ui.settings.auto_core_network_recovery"),
                "network.badge.shield.half.filled",
                Binding(
                    get: { appState.autoManageCoreOnNetworkChangeEnabled },
                    set: { appState.autoManageCoreOnNetworkChangeEnabled = $0 })),
            (
                AppState.EditableCoreSetting.allowLan.id,
                tr("ui.settings.allow_lan"),
                "network",
                self.editableCoreSettingBinding(.allowLan)),
            (
                AppState.EditableCoreSetting.ipv6.id,
                tr("ui.settings.ipv6"),
                "globe",
                self.editableCoreSettingBinding(.ipv6)),
            (
                AppState.EditableCoreSetting.tcpConcurrent.id,
                tr("ui.settings.tcp_concurrent"),
                "point.3.connected.trianglepath.dotted",
                self.editableCoreSettingBinding(.tcpConcurrent)),
        ]
        let maintenanceActions: [(titleKey: String, symbol: String, action: @MainActor () async -> Void)] = [
            ("ui.action.flush_fakeip_cache", "externaldrive.badge.minus", { await appState.flushFakeIPCache() }),
            ("ui.action.flush_dns_cache", "network.badge.shield.half.filled", { await appState.flushDNSCache() }),
        ]
        let selectedLogLevel = appState.stringValue(for: .logLevel)

        return VStack(alignment: .leading, spacing: T.space6) {
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
                ForEach(toggleItems, id: \.id) { item in
                    settingsToggleRow(item.title, symbol: item.symbol, isOn: item.isOn)
                }
                settingsSelectionRow(
                    tr("ui.settings.menu_bar_style"),
                    symbol: "menubar.rectangle",
                    valueText: statusBarModeLabel(appState.statusBarDisplayMode),
                    options: StatusBarDisplayMode.allCases,
                    optionTitle: self.statusBarModeLabel,
                    isSelected: { appState.statusBarDisplayMode == $0 },
                    onSelect: { appState.statusBarDisplayMode = $0 })
                settingsSelectionRow(
                    tr("ui.settings.language"),
                    symbol: "character.book.closed",
                    valueText: appState.uiLanguage == .zhHans ? tr("ui.language.zh_hans") : tr("ui.language.en"),
                    options: AppLanguage.allCases,
                    optionTitle: { $0 == .zhHans ? tr("ui.language.zh_hans") : tr("ui.language.en") },
                    isSelected: { appState.uiLanguage == $0 },
                    onSelect: appState.setUILanguage)
                settingsSelectionRow(
                    tr("ui.settings.appearance"),
                    symbol: "circle.lefthalf.filled",
                    valueText: appearanceModeLabel(appState.appearanceMode),
                    options: AppAppearanceMode.allCases,
                    optionTitle: self.appearanceModeLabel,
                    isSelected: { appState.appearanceMode == $0 },
                    onSelect: appState.setAppearanceMode)
                settingsSelectionRow(
                    tr("ui.settings.log_level"),
                    symbol: "text.alignleft",
                    valueText: selectedLogLevel,
                    options: ConfigLogLevel.allCases,
                    optionTitle: \.rawValue,
                    isSelected: { selectedLogLevel.caseInsensitiveCompare($0.rawValue) == .orderedSame },
                    onSelect: { level in
                        Task { await appState.applyEditableCoreSetting(.logLevel, to: level.rawValue) }
                    })
            }

            VStack(spacing: 0) {
                settingsCardHeader(
                    tr("ui.section.proxy_ports"),
                    symbol: "point.3.connected.trianglepath.dotted")

                VStack(alignment: .leading, spacing: T.space4) {
                    ForEach(proxyPortFields, id: \.titleKey) { item in
                        settingsPortFieldRow(
                            tr(item.titleKey),
                            symbol: item.symbol,
                            text: item.text)
                    }
                }
                .menuRowPadding(vertical: T.space4)
            }

            VStack(spacing: 0) {
                settingsCardHeader(
                    tr("ui.section.maintenance"),
                    symbol: "wrench.and.screwdriver")

                VStack(alignment: .leading, spacing: T.space4) {
                    HStack(spacing: T.space6) {
                        ForEach(maintenanceActions, id: \.titleKey) { item in
                            maintenanceActionButton(tr(item.titleKey), symbol: item.symbol) {
                                await item.action()
                            }
                        }
                    }

                    HStack(spacing: T.space6) {
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
                .menuRowPadding(vertical: T.space4)
            }
        }
    }
}
