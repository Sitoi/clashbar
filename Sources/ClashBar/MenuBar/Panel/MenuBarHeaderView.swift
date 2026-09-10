import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct MenuBarHeaderView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var remoteMachineStore: RemoteMachineStore
    @Binding var showRemoteMachineManager: Bool
    @Environment(\.openURL) private var openURL

    var headerLogoSize: CGFloat {
        40
    }

    var body: some View {
        self.topHeader
    }

    var topHeader: some View {
        HStack(alignment: .center, spacing: T.space8) {
            HStack(alignment: .top, spacing: T.space8) {
                Button {
                    guard let url = URL(string: "https://github.com/Sitoi/ClashBar") else { return }
                    self.openURL(url)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                            .fill(nativeControlFill.opacity(T.Opacity.solid))
                            .overlay {
                                RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                                    .stroke(
                                        nativeControlBorder.opacity(T.Opacity.solid),
                                        lineWidth: T.stroke)
                            }

                        if let brandImage = BrandIcon.image {
                            Image(nsImage: brandImage)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: self.headerLogoSize, height: self.headerLogoSize)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .renderingMode(.template)
                                .symbolRenderingMode(.monochrome)
                                .resizable()
                                .scaledToFit()
                                .frame(width: self.headerLogoSize, height: self.headerLogoSize)
                                .foregroundStyle(nativeAccent)
                        }
                    }
                    .frame(width: self.headerLogoSize, height: self.headerLogoSize)
                }
                .buttonStyle(.plain)
                .help(self.tr("ui.action.open_project_homepage"))
                .accessibilityLabel(self.tr("ui.action.open_project_homepage"))

                VStack(alignment: .leading, spacing: T.space2) {
                    Text("ClashBar")
                        .font(.app(size: T.FontSize.title3, weight: .semibold))
                        .foregroundStyle(nativePrimaryLabel)

                    HStack(spacing: T.space6) {
                        self.headerConnectionControl
                        self.headerControllerWebUIButton
                        if self.appViewModel.isExternalControllerWildcardIPv4 {
                            self.headerControllerWarningIcon
                        }
                    }
                }
            }

            Spacer(minLength: T.space6)

            HStack(spacing: T.space6) {
                self.compactTopIcon(
                    self.appViewModel.isPinned ? "pin.fill" : "pin",
                    label: self.appViewModel.isPinned ? self.tr("ui.action.unpin") : self.tr("ui.action.pin"),
                    toneOverride: self.appViewModel.isPinned ? nativeInfo : nativeTertiaryLabel)
                {
                    self.appViewModel.togglePinned()
                }

                self.compactTopIcon(
                    "arrow.clockwise",
                    label: self.appViewModel.primaryCoreActionLabel,
                    toneOverride: nativeInfo)
                {
                    await self.appViewModel.performPrimaryCoreAction()
                }
                .disabled(self.appViewModel.isRemoteTarget || !self.appViewModel.isPrimaryCoreActionEnabled)
                .opacity((self.appViewModel.isRemoteTarget || !self.appViewModel.isPrimaryCoreActionEnabled) ? 1 * 0.6 :
                    1)

                self.compactTopIcon(
                    self.appViewModel.isRuntimeRunning ? "stop.circle" : "play.circle",
                    label: self.appViewModel.isRuntimeRunning ? self.tr("ui.action.stop") : self
                        .tr("app.primary.start"),
                    toneOverride: self.appViewModel.isRuntimeRunning ? nativeWarning : nativePositive)
                {
                    if self.appViewModel.isRuntimeRunning {
                        await self.appViewModel.stopCore()
                    } else {
                        await self.appViewModel.startCore(trigger: .manual)
                    }
                }
                .disabled(self.appViewModel.isRemoteTarget || self.appViewModel.isCoreActionProcessing)
                .opacity((self.appViewModel.isRemoteTarget || self.appViewModel.isCoreActionProcessing) ? 0.6 : 1)

                self.compactTopIcon("power", label: self.tr("ui.action.quit"), warning: true) {
                    await self.appViewModel.quitApp()
                }
            }
        }
        .padding(.vertical, T.space8)
        .sheet(isPresented: self.$showRemoteMachineManager) {
            RemoteMachineManagerView(
                store: self.remoteMachineStore,
                localControllerDisplay: self.appViewModel.localExternalControllerDisplay)
        }
    }

    var headerConnectionControl: some View {
        AttachedPopoverMenu(
            expandAnchor: false,
            onWillPresent: {
                self.remoteMachineStore.checkAllConnectivity()
            },
            label: { _ in
                HStack(spacing: T.space6) {
                    if self.remoteMachineStore.isSwitchingTarget {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .fill(self.headerConnectionStatusTint)
                            .frame(width: 8, height: 8)
                    }

                    Text(self.headerConnectionDisplayText)
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(nativePrimaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(nativeTertiaryLabel)
                }
                .contentShape(Rectangle())
            },
            content: { dismiss in
                self.headerPopoverSection(self.tr("ui.machine.local_label"))
                AttachedPopoverMenuItem(
                    title: self.tr("ui.machine.local"),
                    leadingSymbol: "desktopcomputer",
                    leadingTint: self.nativeInfo.opacity(T.Opacity.solid),
                    selected: self.remoteMachineStore.activeTarget.isLocal,
                    selectionIndicatorPlacement: .trailing)
                {
                    dismiss()
                    guard !self.remoteMachineStore.activeTarget.isLocal else { return }
                    Task { @MainActor in
                        await self.remoteMachineStore.switchToTarget(.local)
                    }
                }

                if !self.remoteMachineStore.machines.isEmpty {
                    AttachedPopoverMenuDivider()
                    self.headerPopoverSection(self.tr("ui.machine.remote_label"))
                }

                ForEach(self.remoteMachineStore.machines) { machine in
                    let status = self.remoteMachineStore.statusFor(machine.id)
                    let isSelected = self.remoteMachineStore.activeTargetID == machine.id
                    AttachedPopoverMenuItem(
                        title: machine.name,
                        leadingSymbol: "network",
                        leadingTint: self.machineStatusTint(status),
                        selected: isSelected,
                        selectionIndicatorPlacement: .trailing)
                    {
                        dismiss()
                        guard !isSelected else { return }
                        Task { @MainActor in
                            await self.remoteMachineStore.switchToTarget(.remote(machine))
                        }
                    }
                    .disabled(!status.isConnected && !isSelected)
                }

                AttachedPopoverMenuDivider()
                AttachedPopoverMenuItem(
                    title: self.tr("ui.machine.manage"),
                    leadingSymbol: "slider.horizontal.3",
                    leadingTint: self.nativeSecondaryLabel)
                {
                    dismiss()
                    self.showRemoteMachineManager = true
                }
            })
            .disabled(self.remoteMachineStore.isSwitchingTarget)
    }

    var headerControllerWarningIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.app(size: T.FontSize.caption, weight: .semibold))
            .foregroundStyle(nativeWarning)
            .help("external-controller is 0.0.0.0 and can be accessed from your LAN.")
            .accessibilityLabel("Warning: external-controller is bound to 0.0.0.0")
    }

    var headerControllerWebUIButton: some View {
        Button {
            self.appViewModel.openControllerWebUI()
        } label: {
            Image(systemName: "safari")
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(self.nativeSecondaryLabel)
        }
        .buttonStyle(.plain)
        .help("Open WebUI")
        .accessibilityLabel("Open WebUI")
        .disabled(self.remoteMachineStore.isSwitchingTarget)
        .opacity(self.remoteMachineStore.isSwitchingTarget ? 0.6 : 1)
    }

    func headerPopoverSection(_ title: String) -> some View {
        Text(title)
            .font(.app(size: T.FontSize.caption, weight: .bold))
            .foregroundStyle(nativeTertiaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, T.space6)
            .padding(.top, T.space2)
            .padding(.bottom, T.space1)
            .textCase(.uppercase)
    }

    var machineSwitcherStatus: MachineConnectionStatus? {
        guard case let .remote(machine) = remoteMachineStore.activeTarget else { return nil }
        return self.remoteMachineStore.statusFor(machine.id)
    }

    var headerConnectionDisplayText: String {
        self.appViewModel.externalControllerDisplay
    }

    var headerConnectionStatusTint: Color {
        if let status = self.machineSwitcherStatus {
            return self.machineStatusTint(status)
        }
        return self.statusColor
    }
}
