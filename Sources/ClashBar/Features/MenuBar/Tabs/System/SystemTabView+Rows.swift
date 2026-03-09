import SwiftUI

private typealias T = MenuBarLayoutTokens

extension MenuBarRoot {
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

    func settingsToggleRow(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: T.space8) {
            self.settingsRowLabel(symbol: symbol, title: title)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
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
        let resolvedControlWidth = controlWidth ?? settingsMenuControlWidth

        return HStack(spacing: T.space8) {
            self.settingsRowLabel(symbol: symbol, title: title)
                .layoutPriority(1)
            Spacer(minLength: 0)
            AttachedPopoverMenu(width: popoverWidth ?? resolvedControlWidth) {
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
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .menuRowPadding(vertical: T.space4)
    }

    // swiftlint:disable:next function_parameter_count
    func settingsSelectionRow<Option: Hashable>(
        _ title: String,
        symbol: String,
        valueText: String,
        options: [Option],
        optionTitle: @escaping (Option) -> String,
        isSelected: @escaping (Option) -> Bool,
        onSelect: @escaping (Option) -> Void) -> some View
    {
        self.settingsMenuRow(title, symbol: symbol, valueText: valueText) { dismiss in
            ForEach(options, id: \.self) { option in
                AttachedPopoverMenuItem(
                    title: optionTitle(option),
                    selected: isSelected(option))
                {
                    onSelect(option)
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

            TextField(tr("ui.placeholder.port"), text: text)
                .textFieldStyle(.roundedBorder)
                .font(.app(size: T.FontSize.body, weight: .regular))
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
        .overlay {
            RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                .stroke(color.opacity(0.26), lineWidth: T.stroke)
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
