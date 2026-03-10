import AppKit
import SwiftUI

@main
struct ClashBarApp: App {
    @NSApplicationDelegateAdaptor(ClashBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandMenu("Core") {
                Button(self.appDelegate.appState.primaryCoreActionLabel) {
                    Task { await self.appDelegate.appState.performPrimaryCoreAction() }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                .disabled(!self.appDelegate.appState.isPrimaryCoreActionEnabled)

                Button(self.tr("ui.action.stop")) {
                    Task { await self.appDelegate.appState.stopCore() }
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(self.appDelegate.appState.isCoreActionProcessing)

                Divider()

                Button(self.appDelegate.appState.isTunEnabled ? self.tr("ui.action.disable_tun") : self
                    .tr("ui.action.enable_tun"))
                {
                    let toggled = !self.appDelegate.appState.isTunEnabled
                    Task { await self.appDelegate.appState.toggleTunMode(toggled) }
                }
                .keyboardShortcut("T", modifiers: [.command, .option])
                .disabled(!self.appDelegate.appState.isTunToggleEnabled)
            }

            CommandMenu("Panel") {
                Button(self.tr("ui.tab.proxy")) {
                    self.appDelegate.appState.setActiveMenuTab(.proxy)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button(self.tr("ui.tab.rules")) {
                    self.appDelegate.appState.setActiveMenuTab(.rules)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button(self.tr("ui.tab.activity")) {
                    self.appDelegate.appState.setActiveMenuTab(.activity)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button(self.tr("ui.tab.logs")) {
                    self.appDelegate.appState.setActiveMenuTab(.logs)
                }
                .keyboardShortcut("4", modifiers: [.command, .option])

                Button(self.tr("ui.tab.system")) {
                    self.appDelegate.appState.setActiveMenuTab(.system)
                }
                .keyboardShortcut("5", modifiers: [.command, .option])

                Button(self.tr("ui.tab.system")) {
                    self.appDelegate.appState.setActiveMenuTab(.system)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Actions") {
                Button(self.tr("ui.action.refresh")) {
                    Task { await self.appDelegate.appState.refreshActiveTab() }
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])

                Button(self.tr("ui.quick.copy_terminal")) {
                    self.appDelegate.appState.copyProxyCommand()
                }
                .keyboardShortcut("C", modifiers: [.command, .option, .shift])

                Button(self.tr("ui.action.copy_all_logs")) {
                    self.appDelegate.appState.copyAllLogs()
                }
                .keyboardShortcut("L", modifiers: [.command, .option, .shift])

                Button(self.tr("ui.action.clear_all_logs")) {
                    self.appDelegate.appState.clearAllLogs()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .option, .shift])
                .disabled(self.appDelegate.appState.errorLogs.isEmpty)
            }
        }
    }

    private func tr(_ key: String) -> String {
        L10n.t(key, language: self.appDelegate.appState.uiLanguage)
    }
}

@MainActor
final class ClashBarAppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let image = BrandIcon.image {
            NSApp.applicationIconImage = image
        }
        NSApp.setActivationPolicy(.accessory)
        self.statusItemController = StatusItemController(appState: self.appState)
        self.appState.presentInitialNoCoreSetupGuideIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.appState.shutdownForTermination()
        self.statusItemController?.shutdown()
        self.statusItemController = nil
    }
}
