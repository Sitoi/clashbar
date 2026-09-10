import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

private struct SettingsSelectionRowConfiguration<Option: Hashable> {
    let title: String
    let symbol: String
    let valueText: String
    let options: [Option]
    let optionTitle: (Option) -> String
    let isSelected: (Option) -> Bool
    let onSelect: (Option) -> Void
}

typealias SystemTabView = SettingsTabView

struct SettingsTabView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var proxyStore: ProxyStore
    @State private var isExceptionsExpanded = false

    func settingsCardHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: T.space6) {
            Image(systemName: symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
            Text(title)
                .font(.app(size: T.FontSize.body, weight: .bold))
                .foregroundStyle(nativeTertiaryLabel)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
        .menuRowPadding(vertical: T.space2)
    }

    func settingsRowLabel(symbol: String, title: String) -> some View {
        HStack(spacing: T.space6) {
            Image(systemName: symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
                .frame(width: 14, alignment: .center)
            Text(title)
                .font(.app(size: T.FontSize.body, weight: .medium))
                .foregroundStyle(nativePrimaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    func settingsToggleRow(
        _ title: String,
        symbol: String,
        isOn: Binding<Bool>,
        isDisabled: Bool = false) -> some View
    {
        HStack(spacing: T.space8) {
            self.settingsRowLabel(symbol: symbol, title: title)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isDisabled)
        }
        .menuRowPadding(vertical: T.space4)
    }

    func settingsMenuRow(
        _ title: String,
        symbol: String,
        valueText: String,
        controlWidth: CGFloat? = nil,
        popoverWidth: CGFloat? = nil,
        @ViewBuilder options: @escaping (_ dismiss: @escaping () -> Void) -> some View) -> some View
    {
        let resolvedControlWidth = controlWidth ?? self.settingsMenuControlWidth

        return HStack(spacing: T.space8) {
            self.settingsRowLabel(symbol: symbol, title: title)
                .layoutPriority(1)
            Spacer(minLength: 0)
            AttachedPopoverMenu(width: popoverWidth ?? resolvedControlWidth) { _ in
                HStack(spacing: T.space2) {
                    Text(valueText)
                        .foregroundStyle(nativeSecondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(nativeTertiaryLabel)
                }
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .trailing)
            } content: { dismiss in
                options(dismiss)
            }
            .frame(width: resolvedControlWidth, alignment: .trailing)
            .appBorderedButtonStyle()
            .controlSize(.small)
        }
        .menuRowPadding(vertical: T.space4)
    }

    private func settingsSelectionRow(
        _ configuration: SettingsSelectionRowConfiguration<some Hashable>) -> some View
    {
        self.settingsMenuRow(
            configuration.title,
            symbol: configuration.symbol,
            valueText: configuration.valueText)
        { dismiss in
            ForEach(configuration.options, id: \.self) { option in
                AttachedPopoverMenuItem(
                    title: configuration.optionTitle(option),
                    selected: configuration.isSelected(option))
                {
                    configuration.onSelect(option)
                    dismiss()
                }
            }
        }
    }

    func settingsPortFieldRow(_ title: String, symbol: String, text: Binding<String>) -> some View {
        HStack(spacing: T.space8) {
            self.settingsRowLabel(symbol: symbol, title: title)
                .layoutPriority(1)

            Spacer(minLength: 0)

            TextField(self.tr("ui.placeholder.port"), text: text)
                .textFieldStyle(.roundedBorder)
                .font(.app(size: T.FontSize.body, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)
                .multilineTextAlignment(.trailing)
                .frame(width: self.settingsPortFieldWidth, alignment: .trailing)
                .onChange(of: text.wrappedValue) { _ in
                    self.settingsStore.scheduleProxyPortsAutoSaveIfNeeded()
                }
                .onSubmit {
                    Task { await self.settingsStore.applyProxyPorts(autoSaved: true) }
                }
        }
    }

    func systemProxyExceptionBinding(id: EditableSystemProxyException.ID) -> Binding<String> {
        Binding(
            get: {
                self.proxyStore.systemProxyExceptions.first(where: { $0.id == id })?.value ?? ""
            },
            set: { value in
                guard let index = self.proxyStore.systemProxyExceptions.firstIndex(where: { $0.id == id }) else {
                    return
                }
                self.proxyStore.systemProxyExceptions[index].value = value
            })
    }

    func systemProxyExceptionRow(_ exception: EditableSystemProxyException) -> some View {
        HStack(spacing: T.space4) {
            TextField(
                self.tr("ui.placeholder.system_proxy_exception"),
                text: self.systemProxyExceptionBinding(id: exception.id))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.app(size: T.FontSize.body, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)

            Button {
                self.proxyStore.removeSystemProxyExceptionDraft(id: exception.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(nativeCritical.opacity(T.Opacity.solid))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(self.tr("ui.action.remove_exception"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func maintenanceActionButton(_ title: String, symbol: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label {
                Text(title)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            } icon: {
                Image(systemName: symbol)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .appBorderedButtonStyle()
        .controlSize(.small)
        .disabled(!self.maintenanceActionEnabled)
        .opacity(self.maintenanceActionEnabled ? 1 : 0.62)
    }

    func settingsFeedbackBanner(text: String, color: Color, symbol: String) -> some View {
        HStack(spacing: T.space6) {
            Image(systemName: symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(color)

            Text(text)
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .foregroundStyle(nativePrimaryLabel)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .menuRowPadding(vertical: T.space4)
        .background {
            RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                .fill(nativeControlFill)
                .overlay {
                    RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                        .stroke(color.opacity(0.26), lineWidth: T.stroke)
                }
                .shadow(
                    color: self.nativeShadow.opacity(T.Shadow.standard.opacity),
                    radius: T.Shadow.standard.radius,
                    x: T.Shadow.standard.x,
                    y: T.Shadow.standard.y)
        }
    }

    func statusBarModeLabel(_ mode: StatusBarDisplayMode) -> String {
        switch mode {
        case .iconAndSpeed:
            self.tr("ui.settings.display_mode.icon_and_speed")
        case .iconOnly:
            self.tr("ui.settings.display_mode.icon_only")
        case .speedOnly:
            self.tr("ui.settings.display_mode.speed_only")
        }
    }

    func appearanceModeLabel(_ mode: AppAppearanceMode) -> String {
        switch mode {
        case .system:
            self.tr("ui.settings.appearance.system")
        case .light:
            self.tr("ui.settings.appearance.light")
        case .dark:
            self.tr("ui.settings.appearance.dark")
        }
    }

    var settingsMenuControlWidth: CGFloat {
        let contentWidth = T.panelWidth - (T.space8 * 2)
        return min(152, max(118, contentWidth * 0.43))
    }

    var settingsPortFieldWidth: CGFloat {
        let contentWidth = T.panelWidth - (T.space8 * 2)
        return min(108, max(92, contentWidth * 0.30))
    }

    var maintenanceActionEnabled: Bool {
        self.appViewModel.isRemoteTarget || self.appViewModel.processManager.isRunning || self.appViewModel.statusText
            .lowercased() == "running"
    }

    var geoUpdateActionEnabled: Bool {
        self.appViewModel.isRuntimeRunning && !self.appViewModel.isGeoUpdateInFlight
    }

    var geoUpdateFeedbackSymbol: String? {
        switch self.appViewModel.geoUpdateState {
        case .idle, .updating:
            nil
        case .succeeded:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var geoUpdateFeedbackColor: Color {
        switch self.appViewModel.geoUpdateState {
        case .succeeded:
            nativePositive.opacity(T.Opacity.solid)
        case .failed:
            nativeCritical.opacity(T.Opacity.solid)
        default:
            nativeSecondaryLabel
        }
    }

    var isSystemProxyExceptionsSyncing: Bool {
        self.settingsStore.settingsSyncingKey == "system-proxy-exceptions"
    }

    var settingsFeedbackState: (message: String, color: Color, symbol: String)? {
        if let error = self.settingsStore.settingsErrorMessage.trimmedNonEmpty {
            return (error, nativeCritical.opacity(T.Opacity.solid), "exclamationmark.triangle.fill")
        }
        if let launchError = self.appViewModel.launchAtLoginErrorMessage.trimmedNonEmpty {
            return (launchError, nativeWarning.opacity(T.Opacity.solid), "exclamationmark.circle.fill")
        }
        if let saved = self.settingsStore.settingsSavedMessage.trimmedNonEmpty {
            return (saved, nativePositive.opacity(T.Opacity.solid), "checkmark.circle.fill")
        }
        return nil
    }

    func editableCoreSettingBinding(_ setting: EditableBooleanSetting) -> Binding<Bool> {
        Binding(
            get: { self.settingsStore.editableSettings[keyPath: setting.keyPath] },
            set: { value in
                Task { await self.settingsStore.applyEditableCoreSetting(setting, to: value) }
            })
    }

    var body: some View {
        let isRemote = self.appViewModel.isRemoteTarget
        let proxyPortFields: [(titleKey: String, symbol: String, text: Binding<String>)] = [
            ("ui.settings.port.port", "network", self.$settingsStore.editableSettings.port),
            ("ui.settings.port.socks", "wave.3.right", self.$settingsStore.editableSettings.socksPort),
            ("ui.settings.port.mixed", "arrow.triangle.merge", self.$settingsStore.editableSettings.mixedPort),
            ("ui.settings.port.redir", "arrowshape.turn.up.right", self.$settingsStore.editableSettings.redirPort),
            ("ui.settings.port.tproxy", "shield.lefthalf.filled", self.$settingsStore.editableSettings.tproxyPort),
        ]
        let localOnlyItems: [(id: String, title: String, symbol: String, isOn: Binding<Bool>)] = [
            (
                "launch-at-login",
                tr("ui.settings.launch_at_login"),
                "person.crop.circle.badge.checkmark",
                Binding(
                    get: { self.appViewModel.launchAtLoginEnabled },
                    set: { self.appViewModel.applyLaunchAtLogin($0) })),
            (
                "auto-start-core",
                tr("ui.settings.auto_start_core"),
                "power.circle",
                Binding(
                    get: { self.appViewModel.autoStartCore },
                    set: { self.appViewModel.autoStartCore = $0 })),
        ]
        let coreToggleItems: [(id: String, title: String, symbol: String, isOn: Binding<Bool>)] = [
            (
                EditableBooleanSetting.allowLan.id,
                self.tr("ui.settings.allow_lan"),
                "network",
                self.editableCoreSettingBinding(.allowLan)),
            (
                EditableBooleanSetting.ipv6.id,
                self.tr("ui.settings.ipv6"),
                "globe",
                self.editableCoreSettingBinding(.ipv6)),
            (
                EditableBooleanSetting.tcpConcurrent.id,
                self.tr("ui.settings.tcp_concurrent"),
                "point.3.connected.trianglepath.dotted",
                self.editableCoreSettingBinding(.tcpConcurrent)),
        ]
        let maintenanceActions: [(titleKey: String, symbol: String, action: @MainActor () async -> Void)] = [
            (
                "ui.action.flush_fakeip_cache",
                "externaldrive.badge.minus",
                { await self.appViewModel.flushFakeIPCache() }),
            (
                "ui.action.flush_dns_cache",
                "network.badge.shield.half.filled",
                { await self.appViewModel.flushDNSCache() }),
        ]
        let selectedLogLevel = self.settingsStore.editableSettings.logLevel
        let systemProxyExceptionsTitle = isRemote
            ? "\(tr("ui.section.system_proxy_exceptions")) (\(tr("ui.machine.local_label")))"
            : self.tr("ui.section.system_proxy_exceptions")

        return VStack(alignment: .leading, spacing: T.space6) {
            VStack(spacing: 0) {
                self.settingsCardHeader(
                    isRemote ? self.tr("ui.section.local_app_settings") : self.tr("ui.section.basic_settings"),
                    symbol: "slider.horizontal.3")
                ForEach(localOnlyItems, id: \.id) { item in
                    self.settingsToggleRow(
                        isRemote ? "\(item.title) (\(self.tr("ui.machine.local_label")))" : item.title,
                        symbol: item.symbol,
                        isOn: item.isOn)
                }
                self.settingsSelectionRow(.init(
                    title: self.tr("ui.settings.menu_bar_style"),
                    symbol: "menubar.rectangle",
                    valueText: self.statusBarModeLabel(self.appViewModel.statusBarDisplayMode),
                    options: StatusBarDisplayMode.allCases,
                    optionTitle: self.statusBarModeLabel,
                    isSelected: { self.appViewModel.statusBarDisplayMode == $0 },
                    onSelect: { self.appViewModel.statusBarDisplayMode = $0 }))
                self.settingsSelectionRow(.init(
                    title: self.tr("ui.settings.language"),
                    symbol: "character.book.closed",
                    valueText: self.appViewModel.uiLanguage == .zhHans ? self.tr("ui.language.zh_hans") : self
                        .tr("ui.language.en"),
                    options: AppLanguage.allCases,
                    optionTitle: { $0 == .zhHans ? self.tr("ui.language.zh_hans") : self.tr("ui.language.en") },
                    isSelected: { self.appViewModel.uiLanguage == $0 },
                    onSelect: self.appViewModel.setUILanguage))
                self.settingsSelectionRow(.init(
                    title: self.tr("ui.settings.appearance"),
                    symbol: "circle.lefthalf.filled",
                    valueText: self.appearanceModeLabel(self.appViewModel.appearanceMode),
                    options: AppAppearanceMode.allCases,
                    optionTitle: self.appearanceModeLabel,
                    isSelected: { self.appViewModel.appearanceMode == $0 },
                    onSelect: self.appViewModel.setAppearanceMode))
                self.settingsSelectionRow(.init(
                    title: self.tr("ui.settings.log_level"),
                    symbol: "text.alignleft",
                    valueText: selectedLogLevel,
                    options: ConfigLogLevel.allCases,
                    optionTitle: \.rawValue,
                    isSelected: { selectedLogLevel.caseInsensitiveCompare($0.rawValue) == .orderedSame },
                    onSelect: { level in
                        Task { await self.settingsStore.applyLogLevel(level) }
                    }))
                Button {
                    self.isExceptionsExpanded.toggle()
                } label: {
                    HStack(spacing: T.space8) {
                        self.settingsRowLabel(
                            symbol: "arrowshape.turn.up.right.circle",
                            title: systemProxyExceptionsTitle)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        HStack(spacing: T.space2) {
                            let count = self.proxyStore.systemProxyExceptions.count
                            if count > 0 {
                                Text("\(count)")
                                    .foregroundStyle(nativeSecondaryLabel)
                                    .lineLimit(1)
                            }
                            Image(systemName: "chevron.right")
                                .font(.app(size: T.FontSize.caption, weight: .semibold))
                                .foregroundStyle(nativeTertiaryLabel)
                                .rotationEffect(.degrees(self.isExceptionsExpanded ? 90 : 0))
                        }
                        .font(.app(size: T.FontSize.caption, weight: .medium))
                    }
                    .menuRowPadding(vertical: T.space4)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: T.space4) {
                    Text(self.tr("ui.settings.system_proxy_exceptions_hint"))
                        .font(.app(size: T.FontSize.caption, weight: .regular))
                        .foregroundStyle(nativeSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    if self.proxyStore.systemProxyExceptions.isEmpty {
                        Text(self.tr("ui.settings.system_proxy_exceptions_empty"))
                            .font(.app(size: T.FontSize.body, weight: .regular))
                            .foregroundStyle(nativeSecondaryLabel)
                    } else {
                        VStack(alignment: .leading, spacing: T.space4) {
                            ForEach(self.proxyStore.systemProxyExceptions) { item in
                                self.systemProxyExceptionRow(item)
                            }
                        }
                    }

                    HStack(spacing: T.space4) {
                        TextField(
                            self.tr("ui.placeholder.system_proxy_exception"),
                            text: self.$proxyStore.systemProxyNewException)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .font(.app(size: T.FontSize.body, weight: .regular))
                            .foregroundStyle(nativePrimaryLabel)
                            .onSubmit {
                                self.proxyStore.addSystemProxyExceptionDraft()
                            }

                        Button(self.tr("ui.action.add_exception")) {
                            self.proxyStore.addSystemProxyExceptionDraft()
                        }
                        .appBorderedButtonStyle()
                        .controlSize(.small)
                        .disabled(!self.proxyStore.canAddSystemProxyException || self
                            .isSystemProxyExceptionsSyncing)
                    }

                    HStack(spacing: T.space4) {
                        Button {
                            self.proxyStore.restoreDefaultSystemProxyExceptionsDraft()
                        } label: {
                            Label(self.tr("ui.action.restore_defaults"), systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .appBorderedButtonStyle()
                        .controlSize(.small)
                        .disabled(self.isSystemProxyExceptionsSyncing)

                        Button {
                            Task { await self.proxyStore.saveSystemProxyExceptions() }
                        } label: {
                            Label(self.tr("ui.action.save_exceptions"), systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .appBorderedButtonStyle()
                        .controlSize(.small)
                        .disabled(self.isSystemProxyExceptionsSyncing)
                    }
                }
                .menuRowPadding(vertical: T.space4)
                .frame(maxHeight: self.isExceptionsExpanded ? .infinity : 0, alignment: .top)
                .clipped()
                .opacity(self.isExceptionsExpanded ? 1 : 0)
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.80), value: self.isExceptionsExpanded)

            VStack(spacing: 0) {
                self.settingsCardHeader(
                    isRemote ? self.tr("ui.section.core_settings_remote") : self.tr("ui.section.core_settings"),
                    symbol: "gearshape.2")
                ForEach(coreToggleItems, id: \.id) { item in
                    self.settingsToggleRow(
                        item.title,
                        symbol: item.symbol,
                        isOn: item.isOn,
                        isDisabled: self.settingsStore.isCoreSettingSyncing)
                }
            }

            VStack(spacing: 0) {
                self.settingsCardHeader(
                    self.tr("ui.section.proxy_ports"),
                    symbol: "point.3.connected.trianglepath.dotted")

                VStack(alignment: .leading, spacing: T.space4) {
                    ForEach(proxyPortFields, id: \.titleKey) { item in
                        self.settingsPortFieldRow(
                            self.tr(item.titleKey),
                            symbol: item.symbol,
                            text: item.text)
                    }
                }
                .menuRowPadding(vertical: T.space4)
            }

            VStack(spacing: 0) {
                self.settingsCardHeader(
                    self.tr("ui.section.maintenance"),
                    symbol: "wrench.and.screwdriver")

                VStack(alignment: .leading, spacing: T.space4) {
                    HStack(spacing: T.space6) {
                        ForEach(maintenanceActions, id: \.titleKey) { item in
                            self.maintenanceActionButton(self.tr(item.titleKey), symbol: item.symbol) {
                                await item.action()
                            }
                        }
                    }

                    HStack(spacing: T.space6) {
                        Button {
                            Task { await self.appViewModel.upgradeGeo() }
                        } label: {
                            HStack(spacing: T.space4) {
                                Group {
                                    if self.appViewModel.isGeoUpdateInFlight {
                                        ProgressView()
                                            .controlSize(.mini)
                                    } else if let symbol = self.geoUpdateFeedbackSymbol {
                                        Image(systemName: symbol)
                                            .foregroundStyle(self.geoUpdateFeedbackColor)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                }
                                .frame(width: 16, height: 16) // 固定图标位，切换 spinner 时按钮不变高
                                Text(self.tr("ui.action.update_geo_database"))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .appBorderedButtonStyle()
                        .controlSize(.small)
                        .disabled(!self.geoUpdateActionEnabled)
                        .opacity(self.geoUpdateActionEnabled ? 1 : 0.62)

                        Button {
                            self.appViewModel.showCoreDirectoryInFinder()
                        } label: {
                            Label(self.tr("ui.action.open_core_directory"), systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .appBorderedButtonStyle()
                        .controlSize(.small)
                    }
                }
                .menuRowPadding(vertical: T.space4)
            }
        }
        .overlay(alignment: .top) {
            if let feedback = settingsFeedbackState {
                self.settingsFeedbackBanner(
                    text: feedback.message,
                    color: feedback.color,
                    symbol: feedback.symbol)
            }
        }
    }
}
