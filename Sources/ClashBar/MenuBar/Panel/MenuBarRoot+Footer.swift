import MihomoKit
import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

extension MenuBarRootView {
    private static let mihomoRepositoryURL = URL(string: "https://github.com/MetaCubeX/mihomo")

    var footerBar: some View {
        let mihomoSymbol = "cpu"

        return VStack(spacing: 0) {
            HStack(spacing: T.space6) {
                HStack(spacing: T.space6) {
                    self.footerInfo(
                        tr("ui.footer.core_mihomo", self.footerMihomoVersionText),
                        url: Self.mihomoRepositoryURL,
                        iconSystemName: mihomoSymbol)

                    self.footerCoreUpgradeControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                self.footerVersionInfo
                    .fixedSize(horizontal: true, vertical: false)
            }
            .menuRowPadding(vertical: T.space2)
            .background(self.footerSurfaceBackground)
        }
    }

    var footerSurfaceBackground: some View {
        self.nativeControlSurface()
    }

    var footerMihomoVersionText: String {
        let version = self.appViewModel.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.first?.isNumber == true else { return version }
        return "v\(version)"
    }

    @ViewBuilder
    func footerInfo(_ text: String, url: URL?, iconSystemName: String? = nil) -> some View {
        if let url {
            Link(destination: url) {
                self.footerInfoLabel(text, iconSystemName: iconSystemName)
            }
            .buttonStyle(.plain)
        } else {
            self.footerInfoLabel(text, iconSystemName: iconSystemName)
        }
    }

    func footerInfoLabel(_ text: String, iconSystemName: String?) -> some View {
        HStack(spacing: T.space4) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.app(size: T.FontSize.caption, weight: .semibold))
                    .foregroundStyle(self.nativeSecondaryLabel)
            }

            Text(text)
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .foregroundStyle(self.nativeSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(T.minimumScale)
                .allowsTightening(true)
        }
        .help(text)
    }

    var footerCoreUpgradeControl: some View {
        self.compactAsyncIconButton(
            symbol: self.footerCoreUpgradeButtonSymbolName ?? "arrow.down.circle",
            label: self.footerCoreUpgradeButtonTitle,
            tint: self.footerCoreUpgradeButtonTint,
            baseTint: self.nativeSecondaryLabel,
            isLoading: self.appViewModel.isCoreUpgradeInFlight,
            size: 18,
            fontSize: T.FontSize.caption,
            hierarchicalSymbol: true)
        {
            await self.appViewModel.upgradeCore()
        }
        .disabled(!self.isFooterCoreUpgradeEnabled)
        .help(self.footerCoreUpgradeButtonHelp)
    }

    var isFooterCoreUpgradeEnabled: Bool {
        self.appViewModel.isRuntimeRunning && !self.appViewModel.isCoreUpgradeInFlight
    }

    var footerCoreUpgradeButtonTitle: String {
        switch self.appViewModel.coreUpgradeState {
        case .idle:
            tr("ui.action.upgrade_core")
        case .running:
            tr("ui.footer.core_upgrade.running")
        case .succeeded:
            tr("ui.footer.core_upgrade.success")
        case .alreadyLatest:
            tr("ui.footer.core_upgrade.latest")
        case .failed:
            tr("ui.footer.core_upgrade.failed")
        }
    }

    var footerCoreUpgradeButtonSymbolName: String? {
        switch self.appViewModel.coreUpgradeState {
        case .idle:
            "arrow.down.circle"
        case .running:
            nil
        case .succeeded:
            "checkmark.circle.fill"
        case .alreadyLatest:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var footerCoreUpgradeButtonTint: Color {
        switch self.appViewModel.coreUpgradeState {
        case .idle, .running:
            self.nativeAccent.opacity(T.Opacity.solid)
        case .succeeded, .alreadyLatest:
            self.nativePositive.opacity(T.Opacity.solid)
        case .failed:
            self.nativeCritical.opacity(T.Opacity.solid)
        }
    }

    var footerCoreUpgradeButtonHelp: String {
        if !self.appViewModel.isRuntimeRunning {
            return tr("ui.footer.core_upgrade.help.disabled")
        }

        switch self.appViewModel.coreUpgradeState {
        case .idle:
            return tr("ui.footer.core_upgrade.help")
        case .running:
            return tr("ui.footer.core_upgrade.help.running")
        case .succeeded:
            return tr("ui.footer.core_upgrade.help.success")
        case let .alreadyLatest(version):
            if let version, !version.isEmpty {
                return tr("ui.footer.core_upgrade.help.latest_version", version)
            }
            return tr("ui.footer.core_upgrade.help.latest")
        case let .failed(message):
            return tr("ui.footer.core_upgrade.help.failed", message)
        }
    }

    @ViewBuilder
    var footerVersionInfo: some View {
        if let update = self.appViewModel.availableAppUpdate {
            Link(destination: update.releaseURL) {
                self.footerVersionBadge(
                    text: tr("ui.footer.version", update.displayVersion),
                    symbol: "arrow.down.circle.fill",
                    tint: self.nativeAccent.opacity(T.Opacity.solid),
                    emphasized: true)
            }
            .buttonStyle(.plain)
            .help(tr("ui.footer.version_update_help", update.displayVersion))
            .accessibilityLabel(tr(
                "ui.footer.version_update_accessibility",
                self.appViewModel.currentAppVersionText,
                update.displayVersion))
        } else {
            if let releaseIndexURL = self.appViewModel.appReleaseIndexURL {
                Link(destination: releaseIndexURL) {
                    self.footerVersionBadge(
                        text: tr("ui.footer.version", self.appViewModel.currentAppVersionText),
                        symbol: nil,
                        tint: self.nativeSecondaryLabel,
                        emphasized: false)
                }
                .buttonStyle(.plain)
                .help(tr("ui.footer.version", self.appViewModel.currentAppVersionText))
            } else {
                self.footerVersionBadge(
                    text: tr("ui.footer.version", self.appViewModel.currentAppVersionText),
                    symbol: nil,
                    tint: self.nativeSecondaryLabel,
                    emphasized: false)
            }
        }
    }

    func footerVersionBadge(text: String, symbol: String?, tint: Color, emphasized: Bool) -> some View {
        HStack(spacing: T.space4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.app(size: T.FontSize.caption, weight: .semibold))
            }

            Text(text)
                .font(.app(
                    size: T.FontSize.caption,
                    weight: emphasized ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(T.minimumScale)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, T.space6)
        .padding(.vertical, T.space2)
    }
}
