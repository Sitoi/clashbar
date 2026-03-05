import SwiftUI

extension MenuBarRoot {
    func settingsCardHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: MenuBarLayoutTokens.hDense) {
            Image(systemName: symbol)
                .font(.appSystem(size: 10, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
            Text(title)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundStyle(nativeTertiaryLabel)
                .tracking(0.8)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
        .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 1)
    }

    var settingsDivider: some View {
        EmptyView()
    }

    func settingsRowLabel(symbol: String, title: String) -> some View {
        HStack(spacing: MenuBarLayoutTokens.hDense) {
            Image(systemName: symbol)
                .font(.appSystem(size: 11, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
                .frame(width: 14, alignment: .center)
            Text(title)
                .font(.appSystem(size: 12, weight: .medium))
                .foregroundStyle(nativePrimaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    func settingsToggleRow(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            self.settingsRowLabel(symbol: symbol, title: title)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
    }

    func settingsMenuRow(
        _ title: String,
        symbol: String,
        valueText: String,
        controlWidth: CGFloat? = nil,
        popoverWidth: CGFloat? = nil,
        @ViewBuilder options: @escaping (_ dismiss: @escaping () -> Void) -> some View) -> some View
    {
        let resolvedControlWidth = controlWidth ?? settingsMenuControlWidth

        return HStack(spacing: 10) {
            self.settingsRowLabel(symbol: symbol, title: title)
                .layoutPriority(1)
            Spacer(minLength: 0)
            AttachedPopoverMenu(width: popoverWidth ?? resolvedControlWidth) {
                HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
                    Text(valueText)
                        .foregroundStyle(nativeSecondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 10, weight: .semibold))
                        .foregroundStyle(nativeTertiaryLabel)
                }
                .font(.appSystem(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .trailing)
            } content: { dismiss in
                options(dismiss)
            }
            .frame(width: resolvedControlWidth, alignment: .trailing)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
    }

    func settingsPortFieldRow(_ title: String, symbol: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            self.settingsRowLabel(symbol: symbol, title: title)
                .layoutPriority(1)

            Spacer(minLength: 0)

            TextField(tr("ui.placeholder.port"), text: text)
                .textFieldStyle(.roundedBorder)
                .font(.appMonospaced(size: 12, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)
                .multilineTextAlignment(.trailing)
                .frame(width: settingsPortFieldWidth, alignment: .trailing)
                .onChange(of: text.wrappedValue) { _ in
                    appState.scheduleProxyPortsAutoSaveIfNeeded()
                }
                .onSubmit {
                    Task { await appState.applyProxyPorts(autoSaved: true) }
                }
        }
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
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!maintenanceActionEnabled)
        .opacity(maintenanceActionEnabled ? 1 : 0.62)
    }

    func settingsFeedbackBanner(text: String, color: Color, symbol: String) -> some View {
        HStack(spacing: MenuBarLayoutTokens.hDense) {
            Image(systemName: symbol)
                .font(.appSystem(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text(text)
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundStyle(nativePrimaryLabel)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
        .overlay {
            RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cardCornerRadius, style: .continuous)
                .stroke(color.opacity(0.26), lineWidth: 0.7)
        }
    }

    func statusBarModeLabel(_ mode: StatusBarDisplayMode) -> String {
        switch mode {
        case .iconAndSpeed:
            tr("ui.settings.display_mode.icon_and_speed")
        case .iconOnly:
            tr("ui.settings.display_mode.icon_only")
        case .speedOnly:
            tr("ui.settings.display_mode.speed_only")
        }
    }

    func appearanceModeLabel(_ mode: AppAppearanceMode) -> String {
        switch mode {
        case .system:
            tr("ui.settings.appearance.system")
        case .light:
            tr("ui.settings.appearance.light")
        case .dark:
            tr("ui.settings.appearance.dark")
        }
    }
}
