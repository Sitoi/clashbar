import AppKit

@MainActor
extension AppViewModel {
    func prepareModalWindowPresentation() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func configureModalWindow(_ window: NSWindow) {
        window.level = .statusBar
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    @discardableResult
    func runModalAlert(
        style: NSAlert.Style,
        message: String,
        informative: String,
        buttons: [String],
        configure: ((NSAlert) -> Void)? = nil) -> NSApplication.ModalResponse
    {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = informative
        for title in buttons {
            alert.addButton(withTitle: title)
        }
        configure?(alert)
        self.prepareModalWindowPresentation()
        self.configureModalWindow(alert.window)
        return alert.runModal()
    }
}

@MainActor
extension AppViewModel {
    func presentCoreFailureAlert(
        title: String,
        message: String,
        dedupeKey: String,
        style: NSAlert.Style = .warning)
    {
        let now = Date()
        if self.lastCoreFailureAlertKey == dedupeKey,
           let lastAt = self.lastCoreFailureAlertAt,
           now.timeIntervalSince(lastAt) < self.coreFailureAlertThrottleInterval
        {
            return
        }

        self.lastCoreFailureAlertKey = dedupeKey
        self.lastCoreFailureAlertAt = now

        self.runModalAlert(
            style: style,
            message: title,
            informative: message,
            buttons: [tr("ui.action.ok")])
    }

    func presentConfigValidationFailedAlert(fileName: String, details: String) {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        var informativeParts = [tr("app.config.validation_failed.message", fileName)]
        if Self.validationFailureLooksGeoRelated(trimmedDetails) {
            informativeParts.append(tr("app.config.validation_failed.hint.geo"))
        }
        informativeParts.append(tr("app.config.validation_failed.hint.common"))

        let response = self.runModalAlert(
            style: .critical,
            message: tr("app.config.validation_failed.title"),
            informative: informativeParts.joined(separator: "\n\n"),
            buttons: [tr("ui.action.ok"), tr("ui.action.copy_details")])
        { alert in
            alert.setScrollableDetails(trimmedDetails.isEmpty ? self.tr("ui.common.unknown") : trimmedDetails)
        }

        if response == .alertSecondButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(trimmedDetails, forType: .string)
        }
    }

    private static let geoKeywords: Set<String> = [
        "geoip", "geosite", "mmdb", "geox-url", "geodata",
        "country.mmdb", "geosite.dat", "geoip.dat", ".metadb", "geolite", "asn",
    ]

    private static func validationFailureLooksGeoRelated(_ details: String) -> Bool {
        let lower = details.lowercased()
        return self.geoKeywords.contains { lower.contains($0) }
    }

    func presentInitialNoCoreSetupGuideIfNeeded() {
        guard self.shouldPresentInitialNoCoreSetupGuide() else { return }
        guard !didPresentInitialNoCoreSetupGuide else { return }

        didPresentInitialNoCoreSetupGuide = true
        defaults.set(true, forKey: initialNoCoreSetupGuideShownKey)

        let response = self.runModalAlert(
            style: .informational,
            message: tr("app.core.setup_required.title"),
            informative: tr("app.core.setup_required.message", workingDirectoryManager.coreDirectoryURL.path),
            buttons: [tr("ui.action.open_core_directory"), tr("ui.action.ok")])
        if response == .alertFirstButtonReturn {
            self.showCoreDirectoryInFinder()
        }
    }

    func shouldPresentInitialNoCoreSetupGuide() -> Bool {
        guard self.shouldDeferAutoStartForMissingManagedCore() else { return false }
        guard !defaults.bool(forKey: initialNoCoreSetupGuideShownKey) else { return false }
        return true
    }
}
