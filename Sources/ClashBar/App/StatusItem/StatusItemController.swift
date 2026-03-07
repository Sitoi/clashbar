import AppKit
import Combine
import SwiftUI

private struct StatusItemRenderKey: Equatable {
    let mode: StatusBarDisplayMode
    let symbolName: String?
    let speedLines: MenuBarSpeedLines?
}

@MainActor
final class PopoverLayoutModel: ObservableObject {
    @Published var maxPanelHeight: CGFloat
    @Published var preferredPanelHeight: CGFloat

    init(maxPanelHeight: CGFloat = 640, preferredPanelHeight: CGFloat = 600) {
        self.maxPanelHeight = maxPanelHeight
        self.preferredPanelHeight = preferredPanelHeight
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
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
    private let popoverMinimumHeight: CGFloat = 280
    private let popoverScreenPadding: CGFloat = 10
    private let panelTopSpacing: CGFloat = 6
    private let panelHorizontalPadding: CGFloat = MenuBarLayoutTokens.hPage

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
    private var popoverHostingController: NSHostingController<AnyView>?
    private var scrollIndicatorSuppressionTask: Task<Void, Never>?

    private let iconOnlyRefreshInterval: TimeInterval = 0.12
    // Status-item snapshotting is expensive on macOS when traffic text changes frequently.
    private let speedDisplayRefreshInterval: TimeInterval = 1.0
    private static let popoverContentWidth: CGFloat = MenuBarLayoutTokens.panelWidth

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.popoverContentWidth,
                height: self.popoverLayoutModel.preferredPanelHeight),
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
        self.scrollIndicatorSuppressionTask?.cancel()
        self.scrollIndicatorSuppressionTask = nil
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

        if self.panel.isVisible {
            self.closePopover(nil)
            return
        }

        self.ensurePopoverContent()
        self.refreshPopoverMaximumHeight()
        self.applyPopoverSize(
            preferredHeight: self.popoverLayoutModel.preferredPanelHeight,
            preserveHorizontalPosition: false)
        self.placePanelRelativeToStatusButton(button, preserveHorizontalPosition: false)
        NSApp.activate(ignoringOtherApps: true)
        self.panel.makeKeyAndOrderFront(nil)
        self.scheduleScrollIndicatorSuppressionPasses()
        self.startGlobalMonitor()
        self.appState.setPanelVisibility(true)
    }

    @objc
    private func closePopover(_ sender: Any?) {
        self.panel.orderOut(sender)
        self.lockedPanelOriginX = nil
        self.scrollIndicatorSuppressionTask?.cancel()
        self.scrollIndicatorSuppressionTask = nil
        self.stopGlobalMonitor()
        self.unloadPopoverContent()
        self.appState.setPanelVisibility(false)
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
            self.popoverHostingController = NSHostingController(rootView: self.makePopoverRootView())
        } else {
            self.popoverHostingController?.rootView = self.makePopoverRootView()
        }
        self.panel.contentViewController = self.popoverHostingController
        self.suppressPanelScrollIndicators()
    }

    private func unloadPopoverContent() {
        self.panel.contentViewController = nil
        self.popoverHostingController = nil
    }

    private func makePopoverRootView() -> AnyView {
        AnyView(
            MenuBarRoot()
                .environmentObject(self.appState)
                .environmentObject(self.popoverLayoutModel))
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
        self.layoutCancellable = self.popoverLayoutModel.$preferredPanelHeight
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
            // Keep icon-only status item visually stable regardless of runtime state symbol changes.
            return StatusItemRenderKey(mode: .iconOnly, symbolName: symbolName, speedLines: nil)
        case .iconAndSpeed:
            // In icon+speed mode, icon stays fixed; only speed text drives refresh.
            return StatusItemRenderKey(mode: .iconAndSpeed, symbolName: symbolName, speedLines: display.speedLines)
        case .speedOnly:
            return StatusItemRenderKey(mode: .speedOnly, symbolName: nil, speedLines: display.speedLines)
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
        if abs(self.popoverLayoutModel.maxPanelHeight - maximumHeight) > 0.5 {
            self.popoverLayoutModel.maxPanelHeight = maximumHeight
        }
    }

    private func computeMaximumPopoverHeight() -> CGFloat {
        guard
            let button = statusItem.button,
            let buttonWindow = button.window
        else {
            return self.popoverFallbackMaxHeight
        }

        let screen = buttonWindow.screen ?? NSScreen.main
        guard let screen else { return self.popoverFallbackMaxHeight }

        let visibleFrame = screen.visibleFrame
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        let availableHeightBelowButton = buttonFrameOnScreen.minY - visibleFrame.minY - self.popoverScreenPadding - self
            .panelTopSpacing
        let visibleHeight = visibleFrame.height - self.popoverScreenPadding
        let maximumHeight = min(availableHeightBelowButton, visibleHeight)

        return max(1, maximumHeight.rounded(.down))
    }

    private func applyPopoverSize(preferredHeight: CGFloat, preserveHorizontalPosition: Bool) {
        let maximumHeight = max(1, popoverLayoutModel.maxPanelHeight)
        let minimumHeight = min(popoverMinimumHeight, maximumHeight)
        let clampedHeight = min(
            maximumHeight,
            max(minimumHeight, min(preferredHeight, maximumHeight)).rounded(.up))
        let targetSize = NSSize(width: Self.popoverContentWidth, height: clampedHeight)

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

    private func scheduleScrollIndicatorSuppressionPasses() {
        self.scrollIndicatorSuppressionTask?.cancel()
        self.scrollIndicatorSuppressionTask = Task { @MainActor [weak self] in
            for _ in 0..<12 {
                guard let self else { return }
                self.suppressPanelScrollIndicators()
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
    }

    private func suppressPanelScrollIndicators() {
        ScrollIndicatorPolicy.suppressRecursively(in: self.panel.contentView)
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
        guard
            let button,
            let buttonWindow = button.window
        else {
            return nil
        }

        let screen = buttonWindow.screen ?? NSScreen.main
        guard let screen else { return nil }

        let visibleFrame = screen.visibleFrame
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        let panelWidth = panelSize.width
        let panelHeight = panelSize.height
        let minX = visibleFrame.minX + self.panelHorizontalPadding
        let maxX = visibleFrame.maxX - self.panelHorizontalPadding - panelWidth

        let centeredX = buttonFrameOnScreen.midX - panelWidth / 2
        let lockedX = self.lockedPanelOriginX ?? centeredX
        let targetX = preserveHorizontalPosition ? lockedX : centeredX
        let clampedX = min(max(targetX, minX), maxX)

        if !preserveHorizontalPosition || self.lockedPanelOriginX == nil {
            self.lockedPanelOriginX = clampedX
        }

        let topY = buttonFrameOnScreen.minY - self.panelTopSpacing
        let minY = visibleFrame.minY + self.popoverScreenPadding
        let targetY = max(minY, topY - panelHeight)

        return NSPoint(x: clampedX, y: targetY)
    }
}
