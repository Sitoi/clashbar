import AppKit
import MihomoKit
import SwiftUI

@main
struct ClashBarApp: App {
    @NSApplicationDelegateAdaptor(ClashBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                AppCommands(session: self.appDelegate.appViewModel, appDelegate: self.appDelegate)
            }
    }
}

/// Menu commands have to live in a `Commands` type that observes the session. `App` itself has
/// no observation, so building them inline froze every `.disabled(...)` and label at their
/// launch-time values — the core always looked stopped and ⌘E stayed permanently disabled.
private struct AppCommands: Commands {
    @ObservedObject var session: AppViewModel
    let appDelegate: ClashBarAppDelegate

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(self.tr("ui.tab.system")) {
                self.appDelegate.showSettingsPanel()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu(self.tr("ui.menu.quick")) {
            Button(self.tr("ui.quick.system_proxy")) {
                Task {
                    let target = !self.session.proxyStore.isSystemProxyEnabled
                    await self.session.proxyStore.toggleSystemProxy(target)
                    guard self.session.proxyStore.isSystemProxyEnabled == target else { return }
                    self.showBanner(
                        symbol: "network",
                        title: self.tr("ui.quick.system_proxy"),
                        detail: self.tr(target ? "log.system_proxy.enabled" : "log.system_proxy.disabled"))
                }
            }
            .keyboardShortcut("s", modifiers: .command)

            Button(self.session.settingsStore.editableSettings.tunEnabled ? self.tr("ui.action.disable_tun") : self
                .tr("ui.action.enable_tun"))
            {
                Task {
                    let target = !self.session.settingsStore.editableSettings.tunEnabled
                    await self.session.proxyStore.toggleTunMode(target)
                    guard self.session.settingsStore.editableSettings.tunEnabled == target else { return }
                    self.showBanner(
                        symbol: "point.3.connected.trianglepath.dotted",
                        title: self.tr("ui.quick.tun_mode"),
                        detail: self.tr(target ? "log.tun.enabled" : "log.tun.disabled"))
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!self.session.isTunToggleEnabled)

            Divider()

            ForEach(Self.modeShortcuts, id: \.mode) { entry in
                Button(self.tr(entry.key)) {
                    Task {
                        await self.session.switchMode(to: entry.mode)
                        guard self.session.settingsStore.editableSettings.mode == entry.mode else { return }
                        self.showBanner(
                            symbol: entry.symbol,
                            title: self.tr("ui.banner.mode.title"),
                            detail: self.tr(entry.key))
                    }
                }
                .keyboardShortcut(entry.shortcut, modifiers: [.control, .command])
                .disabled(!self.session.isModeSwitchEnabled)
            }

            Divider()

            // ponytail: KeyEquivalent folds the shift needed to type the character into the
            // shortcut, so an uppercase "R" here silently means ⌘⇧R. Keep every letter lowercase.
            Button(self.tr("ui.quick.copy_terminal")) { self.session.copyLocalProxyCommand() }
                .keyboardShortcut("c", modifiers: .command)

            Button(self.tr("ui.quick.copy_terminal_current_endpoint")) {
                self.session.copyManagedEndpointProxyCommand()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Divider()

            Button(self.session.primaryCoreActionLabel) {
                let title = self.session.primaryCoreActionLabel
                let symbol = self.session.primaryCoreActionIconName
                Task {
                    await self.session.performPrimaryCoreAction()
                    guard self.session.isRuntimeRunning else { return }
                    self.showBanner(
                        symbol: symbol,
                        title: title,
                        detail: self.session.configurationStore.selectedConfigName)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!self.session.isPrimaryCoreActionEnabled || self.session.isRemoteTarget)

            Button(self.tr("ui.action.stop")) {
                Task {
                    await self.session.stopCore()
                    guard !self.session.isRuntimeRunning else { return }
                    self.showBanner(
                        symbol: "stop.fill",
                        title: self.tr("ui.action.stop"),
                        detail: self.session.configurationStore.selectedConfigName)
                }
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(self.session.isRemoteTarget || self.session.isCoreActionProcessing)
        }

        CommandMenu("Panel") {
            ForEach(Self.panelShortcuts, id: \.tab) { entry in
                Button(self.tr(entry.key)) { self.session.setActiveMenuTab(entry.tab) }
                    .keyboardShortcut(entry.shortcut, modifiers: [.command, .option])
            }
            Button(self.tr("ui.tab.system")) { self.session.setActiveMenuTab(.system) }
                .keyboardShortcut("5", modifiers: [.command, .option])
        }
    }

    private static let modeShortcuts: [(mode: CoreMode, key: String, symbol: String, shortcut: KeyEquivalent)] = [
        (.rule, "ui.mode.rule", "shield.lefthalf.filled", "1"),
        (.global, "ui.mode.global", "globe", "2"),
        (.direct, "ui.mode.direct", "bolt.fill", "3"),
    ]

    /// Menu-bar shortcuts fire with no window on screen, so every one of them confirms itself the
    /// way ⌘C already did — otherwise a working shortcut looks like a dead key.
    @MainActor
    private func showBanner(symbol: String, title: String, detail: String) {
        self.session.statusItemBanner = StatusItemBanner(
            symbolName: symbol,
            title: title,
            primaryDetail: detail,
            secondaryDetail: nil)
    }

    private static let panelShortcuts: [(tab: RootTab, key: String, shortcut: KeyEquivalent)] = [
        (.proxy, "ui.tab.proxy", "1"),
        (.rules, "ui.tab.rules", "2"),
        (.connections, "ui.tab.connections", "3"),
        (.logs, "ui.tab.logs", "4"),
    ]

    private func tr(_ key: String) -> String {
        L10n.t(key, language: self.session.uiLanguage)
    }
}
