import AppKit

@MainActor
final class ClashBarAppDelegate: NSObject, NSApplicationDelegate {
    let appViewModel = AppViewModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let image = BrandIcon.image {
            NSApp.applicationIconImage = image
        }
        NSApp.setActivationPolicy(.accessory)
        self.appViewModel.start()
        self.statusItemController = StatusItemController(appViewModel: self.appViewModel)
        self.appViewModel.presentInitialNoCoreSetupGuideIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        self.appViewModel.handleApplicationDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.appViewModel.shutdownForTermination()
        self.statusItemController?.shutdown()
        self.statusItemController = nil
    }

    func showSettingsPanel() {
        self.statusItemController?.presentPopover(tab: .system)
    }
}
