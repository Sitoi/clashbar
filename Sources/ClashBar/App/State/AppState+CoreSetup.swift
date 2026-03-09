import AppKit
import Foundation

@MainActor
extension AppState {
    func hasInstalledManagedMihomoCore() -> Bool {
        FileManager.default.fileExists(atPath: workingDirectoryManager.managedMihomoBinaryURL.path)
    }

    func shouldDeferAutoStartForMissingManagedCore() -> Bool {
        !bundlesMihomoCore && !hasInstalledManagedMihomoCore()
    }

    func coreErrorMessage(_ error: Error) -> String {
        if let binaryResolutionError = error as? MihomoBinaryResolutionError {
            switch binaryResolutionError {
            case let .binaryNotFound(expectedDirectory):
                return tr("app.core.error.binary_not_found", expectedDirectory)
            }
        }

        return error.localizedDescription
    }

    func presentInitialNoCoreSetupGuideIfNeeded() {
        guard shouldPresentInitialNoCoreSetupGuide() else { return }
        guard !didPresentInitialNoCoreSetupGuide else { return }

        didPresentInitialNoCoreSetupGuide = true
        defaults.set(true, forKey: initialNoCoreSetupGuideShownKey)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = tr("app.core.setup_required.title")
        alert.informativeText = tr("app.core.setup_required.message", workingDirectoryManager.coreDirectoryURL.path)
        alert.addButton(withTitle: tr("ui.action.open_core_directory"))
        alert.addButton(withTitle: tr("ui.action.ok"))
        self.prepareModalWindowPresentation()
        self.configureModalWindow(alert.window)

        if alert.runModal() == .alertFirstButtonReturn {
            self.showCoreDirectoryInFinder()
        }
    }

    func shouldPresentInitialNoCoreSetupGuide() -> Bool {
        guard shouldDeferAutoStartForMissingManagedCore() else { return false }
        guard !defaults.bool(forKey: initialNoCoreSetupGuideShownKey) else { return false }
        return true
    }
}
