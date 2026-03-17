import AppKit
import Combine
import SwiftUI

private struct StatusItemRenderKey: Equatable {
    let mode: StatusBarDisplayMode
    let symbolName: String?
    let speedLines: MenuBarSpeedLines?
    let isRunning: Bool
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private struct StatusItemPopoverRootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var popoverLayoutModel: PopoverLayoutModel

    var body: some View {
        MenuBarRoot()
            .environmentObject(self.appState)
            .environmentObject(self.appState.connectionsStore)
            .environmentObject(self.popoverLayoutModel)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let panel: FloatingPanel
    private let statusContentView: StatusItemContentView
    private let popoverLayoutModel = PopoverLayoutModel()
    private let popoverFallbackMaxHeight: CGFloat = 640
    private let popoverScreenPadding: CGFloat = 10
    private let panelTopSpacing: CGFloat = 0
    private let panelHorizontalPadding: CGFloat = MenuBarLayoutTokens.space8

    private var changeCancellable: AnyCancellable?
    private var layoutCancellable: AnyCancellable?
    private var refreshWorkItem: DispatchWorkItem?
    private var pendingDisplay: MenuBarDisplay?
    private var pendingRenderKey: StatusItemRenderKey?
    private var lastDisplayRefreshAt: Date = .distantPast
    private var lastRenderedKey: StatusItemRenderKey?
    private var globalEventMonitor: Any?
    private var screenParametersObserver: Any?
    private var lockedPanelOriginX: CGFloat?
    private var popoverHostingController: NSHostingController<StatusItemPopoverRootView>?
    private var panelStabilizationTask: Task<Void, Never>?
    private var isAnimatingPanelTransition = false

    private let iconOnlyRefreshInterval: TimeInterval = 0.12
    // Status-item snapshotting is expensive on macOS when traffic text changes frequently.
    private let speedDisplayRefreshInterval: TimeInterval = 1.0
    private static let popoverContentWidth: CGFloat = MenuBarLayoutTokens.panelWidth
    private let panelOpenAnimationDuration: TimeInterval = 0.16
    private let panelCloseAnimationDuration: TimeInterval = 0.12
    private let panelOpenAnimationDelayNanoseconds: UInt64 = 18_000_000

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.popoverContentWidth,
                height: self.popoverLayoutModel.resolvedPanelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true)
        self.statusContentView = StatusItemContentView(frame: .zero)

        super.init()

        self.configurePanel()
        self.configureStatusItem()
        self.bindAppState()
        self.bindPopoverLayout()
        self.observeScreenParameterChanges()
        self.refreshPopoverMaximumHeight()
        self.refreshDisplayNow()
    }

    func shutdown() {
        self.refreshWorkItem?.cancel()
        self.pendingDisplay = nil
        self.pendingRenderKey = nil
        self.panelStabilizationTask?.cancel()
        self.panelStabilizationTask = nil
        self.changeCancellable?.cancel()
        self.layoutCancellable?.cancel()
        self.stopGlobalMonitor()
        self.stopObservingScreenParameters()
        self.unloadPopoverContent()
        self.appState.setPanelVisibility(false)
        NSStatusBar.system.removeStatusItem(self.statusItem)
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        guard !self.isAnimatingPanelTransition else { return }

        if self.panel.isVisible {
            self.closePopover(nil)
            return
        }

        self.ensurePopoverContent()
        self.refreshPopoverMaximumHeight()
        self.applyPopoverSize(
            preferredHeight: self.popoverLayoutModel.resolvedPanelHeight,
            preserveHorizontalPosition: false)
        self.animateOpenPopover(relativeTo: button)
    }

    @objc
    private func closePopover(_ sender: Any?) {
        guard !self.isAnimatingPanelTransition else { return }
        guard self.panel.isVisible else {
            self.lockedPanelOriginX = nil
            self.panelStabilizationTask?.cancel()
            self.panelStabilizationTask = nil
            self.stopGlobalMonitor()
            self.unloadPopoverContent()
            self.appState.setPanelVisibility(false)
            return
        }

        self.animateClosePopover()
    }

    private func configurePanel() {
        self.panel.isReleasedWhenClosed = false
        self.panel.isOpaque = false
        self.panel.backgroundColor = .clear
        self.panel.hasShadow = true
        self.panel.acceptsMouseMovedEvents = true
        self.panel.becomesKeyOnlyIfNeeded = false
        self.panel.hidesOnDeactivate = false
        self.panel.level = .statusBar
        self.panel.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
        self.panel.contentViewController = nil
    }

    private func ensurePopoverContent() {
        if self.popoverHostingController == nil {
            let hc = NSHostingController(rootView: self.popoverRootView)
            hc.sizingOptions = [.standardBounds]
            self.popoverHostingController = hc
        } else {
            self.popoverHostingController?.rootView = self.popoverRootView
        }
        self.panel.contentViewController = self.popoverHostingController
        self.suppressPanelScrollIndicators()
    }

    private func unloadPopoverContent() {
        self.panel.contentViewController = nil
        self.popoverHostingController = nil
    }

    private var popoverRootView: StatusItemPopoverRootView {
        StatusItemPopoverRootView(
            appState: self.appState,
            popoverLayoutModel: self.popoverLayoutModel)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.target = self
        button.action = #selector(self.togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        self.statusContentView.frame = button.bounds
        self.statusContentView.autoresizingMask = [.width, .height]
        button.addSubview(self.statusContentView)
    }

    private func bindAppState() {
        self.changeCancellable = self.appState.$menuBarDisplaySnapshot
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] display in
                self?.scheduleRefresh(display: display)
            }
    }

    private func bindPopoverLayout() {
        self.layoutCancellable = self.popoverLayoutModel.$resolvedPanelHeight
            .receive(on: RunLoop.main)
            .sink { [weak self] preferredHeight in
                self?.applyPopoverSize(preferredHeight: preferredHeight, preserveHorizontalPosition: true)
            }
    }

    private func scheduleRefresh(display: MenuBarDisplay) {
        let renderKey = self.renderKey(for: display)
        guard renderKey != self.lastRenderedKey else { return }
        self.pendingDisplay = display
        self.pendingRenderKey = renderKey
        self.flushScheduledRefreshIfNeeded()
    }

    private func refreshDisplayNow() {
        self.refreshWorkItem?.cancel()
        self.refreshWorkItem = nil
        self.pendingDisplay = nil
        self.pendingRenderKey = nil
        let display = self.appState.menuBarDisplaySnapshot
        self.refreshDisplay(display, renderKey: self.renderKey(for: display))
        self.lastDisplayRefreshAt = Date()
    }

    private func refreshDisplay(_ display: MenuBarDisplay, renderKey: StatusItemRenderKey) {
        guard renderKey != self.lastRenderedKey else { return }

        self.statusContentView.apply(display: display)
        let requiredWidth = self.statusContentView.requiredWidth
        if abs(self.statusItem.length - requiredWidth) > 0.5 {
            self.statusItem.length = requiredWidth
        }
        self.lastRenderedKey = renderKey
    }

    private func flushScheduledRefreshIfNeeded() {
        guard let pendingDisplay, let pendingRenderKey else { return }

        let refreshInterval = self.refreshInterval(for: pendingDisplay)
        let elapsed = Date().timeIntervalSince(self.lastDisplayRefreshAt)

        if elapsed >= refreshInterval {
            self.refreshWorkItem?.cancel()
            self.refreshWorkItem = nil
            self.pendingDisplay = nil
            self.pendingRenderKey = nil
            self.refreshDisplay(pendingDisplay, renderKey: pendingRenderKey)
            self.lastDisplayRefreshAt = Date()
            return
        }

        guard self.refreshWorkItem == nil else { return }
        let remainingDelay = max(0.01, refreshInterval - elapsed)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshWorkItem = nil
            guard let nextDisplay = self.pendingDisplay, let nextRenderKey = self.pendingRenderKey else { return }
            self.pendingDisplay = nil
            self.pendingRenderKey = nil
            self.refreshDisplay(nextDisplay, renderKey: nextRenderKey)
            self.lastDisplayRefreshAt = Date()
            self.flushScheduledRefreshIfNeeded()
        }
        self.refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay, execute: work)
    }

    private func refreshInterval(for display: MenuBarDisplay) -> TimeInterval {
        switch display.mode {
        case .iconOnly:
            self.iconOnlyRefreshInterval
        case .iconAndSpeed, .speedOnly:
            self.speedDisplayRefreshInterval
        }
    }

    private func renderKey(for display: MenuBarDisplay) -> StatusItemRenderKey {
        let shouldTrackSymbol = !self.statusContentView.usesBrandIcon
        let symbolName = shouldTrackSymbol ? display.symbolName : nil
        switch display.mode {
        case .iconOnly:
            return StatusItemRenderKey(
                mode: .iconOnly,
                symbolName: symbolName,
                speedLines: nil,
                isRunning: display.isRunning)
        case .iconAndSpeed:
            return StatusItemRenderKey(
                mode: .iconAndSpeed,
                symbolName: symbolName,
                speedLines: display.speedLines,
                isRunning: display.isRunning)
        case .speedOnly:
            return StatusItemRenderKey(
                mode: .speedOnly,
                symbolName: nil,
                speedLines: display.speedLines,
                isRunning: display.isRunning)
        }
    }

    private func startGlobalMonitor() {
        self.stopGlobalMonitor()
        self.globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
        ]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover(nil)
            }
        }
    }

    private func stopGlobalMonitor() {
        guard let globalEventMonitor else { return }
        NSEvent.removeMonitor(globalEventMonitor)
        self.globalEventMonitor = nil
    }

    private func observeScreenParameterChanges() {
        self.screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor in
                self?.refreshPopoverMaximumHeight()
            }
        }
    }

    private func stopObservingScreenParameters() {
        guard let screenParametersObserver else { return }
        NotificationCenter.default.removeObserver(screenParametersObserver)
        self.screenParametersObserver = nil
    }

    private func refreshPopoverMaximumHeight() {
        let maximumHeight = self.computeMaximumPopoverHeight()
        self.popoverLayoutModel.updateMaximumPanelHeight(maximumHeight)
    }

    private func computeMaximumPopoverHeight() -> CGFloat {
        guard let anchorContext = self.resolvedStatusItemAnchorContext(for: statusItem.button) else {
            return self.popoverFallbackMaxHeight
        }

        return anchorContext.maximumHeightBelowMenuBar(
            screenPadding: self.popoverScreenPadding,
            verticalSpacing: self.panelTopSpacing)
    }

    private func applyPopoverSize(preferredHeight: CGFloat, preserveHorizontalPosition: Bool) {
        let targetSize = NSSize(width: Self.popoverContentWidth, height: preferredHeight)

        let widthChanged = abs(panel.frame.width - targetSize.width) > 0.5
        let heightChanged = abs(panel.frame.height - targetSize.height) > 0.5
        guard widthChanged || heightChanged else { return }

        if self.panel.isVisible,
           let origin = resolvedPanelOrigin(
               for: statusItem.button,
               panelSize: targetSize,
               preserveHorizontalPosition: preserveHorizontalPosition)
        {
            let frame = NSRect(origin: origin, size: targetSize)
            self.panel.setFrame(frame, display: true, animate: false)
            self.suppressPanelScrollIndicators()
            return
        }

        var newFrame = self.panel.frame
        newFrame.size = targetSize
        self.panel.setFrame(newFrame, display: true, animate: false)
        self.suppressPanelScrollIndicators()
    }

    private func schedulePanelStabilizationPasses(for button: NSStatusBarButton) {
        self.panelStabilizationTask?.cancel()
        self.panelStabilizationTask = Task { @MainActor [weak self, weak button] in
            for pass in 0..<11 {
                try? await Task.sleep(nanoseconds: pass == 0 ? 16_000_000 : 40_000_000)

                guard
                    let self,
                    let button,
                    self.panel.isVisible
                else {
                    return
                }

                if pass < 3 {
                    self.refreshPopoverMaximumHeight()
                    self.placePanelRelativeToStatusButton(button, preserveHorizontalPosition: true)
                }

                self.suppressPanelScrollIndicators()
            }
        }
    }

    private func suppressPanelScrollIndicators() {
        ScrollIndicatorPolicy.suppressRecursively(in: self.panel.contentView)
    }

    private func animateOpenPopover(relativeTo button: NSStatusBarButton) {
        guard let finalOrigin = self.resolvedPanelOrigin(
            for: button,
            panelSize: self.panel.frame.size,
            preserveHorizontalPosition: false)
        else {
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            self.startGlobalMonitor()
            self.appState.setPanelVisibility(true)
            return
        }

        self.isAnimatingPanelTransition = true

        let finalFrame = NSRect(origin: finalOrigin, size: self.panel.frame.size)
        self.panel.alphaValue = 0
        self.panel.setFrame(finalFrame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        self.panel.makeKeyAndOrderFront(nil)
        self.placePanelRelativeToStatusButton(button, preserveHorizontalPosition: true)
        self.suppressPanelScrollIndicators()
        self.startGlobalMonitor()

        Task { @MainActor [weak self, weak button] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.panelOpenAnimationDelayNanoseconds)
            guard self.panel.isVisible else {
                self.isAnimatingPanelTransition = false
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = self.panelOpenAnimationDuration
                context.allowsImplicitAnimation = true
                self.panel.animator().alphaValue = 1
            } completionHandler: { [weak self, weak button] in
                Task { @MainActor [weak self, weak button] in
                    guard let self else { return }
                    self.isAnimatingPanelTransition = false
                    self.panel.alphaValue = 1
                    self.appState.setPanelVisibility(true)
                    if let button {
                        self.placePanelRelativeToStatusButton(button, preserveHorizontalPosition: true)
                        self.schedulePanelStabilizationPasses(for: button)
                    }
                    self.suppressPanelScrollIndicators()
                }
            }
        }
    }

    private func animateClosePopover() {
        self.isAnimatingPanelTransition = true
        self.panelStabilizationTask?.cancel()
        self.panelStabilizationTask = nil
        self.stopGlobalMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = self.panelCloseAnimationDuration
            context.allowsImplicitAnimation = true
            self.panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.isAnimatingPanelTransition = false
                self.lockedPanelOriginX = nil
                self.unloadPopoverContent()
                self.appState.setPanelVisibility(false)
            }
        }
    }

    private func placePanelRelativeToStatusButton(_ button: NSStatusBarButton?, preserveHorizontalPosition: Bool) {
        guard let origin = resolvedPanelOrigin(
            for: button,
            panelSize: panel.frame.size,
            preserveHorizontalPosition: preserveHorizontalPosition)
        else {
            return
        }
        self.panel.setFrameOrigin(origin)
    }

    private func resolvedPanelOrigin(
        for button: NSStatusBarButton?,
        panelSize: NSSize,
        preserveHorizontalPosition: Bool) -> NSPoint?
    {
        guard let anchorContext = self.resolvedStatusItemAnchorContext(for: button) else { return nil }

        let placement = anchorContext.menuBarDropdownPlacement(
            panelSize: panelSize,
            options: MenuBarDropdownPlacementOptions(
                horizontalPadding: self.panelHorizontalPadding,
                verticalSpacing: self.panelTopSpacing,
                screenPadding: self.popoverScreenPadding,
                lockedOriginX: self.lockedPanelOriginX,
                preserveHorizontalPosition: preserveHorizontalPosition))

        self.lockedPanelOriginX = placement.lockedOriginX

        return placement.frame.origin
    }

    private func resolvedStatusItemAnchorContext(for button: NSStatusBarButton?) -> PanelAnchorContext? {
        PanelAnchorContext.resolve(for: button)
    }
}
