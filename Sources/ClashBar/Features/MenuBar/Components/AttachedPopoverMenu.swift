import AppKit
import SwiftUI

struct AttachedPopoverMenu<Label: View, Content: View>: View {
    let width: CGFloat?
    let maxHeight: CGFloat?
    let onWillPresent: (() -> Void)?
    let label: () -> Label
    let content: (_ dismiss: @escaping () -> Void) -> Content

    @State private var isAnchorHovered = false
    @State private var suppressAutoOpen = false
    @State private var shouldBuildPopoverContent = false

    init(
        width: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        onWillPresent: (() -> Void)? = nil,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder content: @escaping (_ dismiss: @escaping () -> Void) -> Content)
    {
        self.width = width
        self.maxHeight = maxHeight
        self.onWillPresent = onWillPresent
        self.label = label
        self.content = content
    }

    var body: some View {
        self.label()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                self.requestOpen()
                self.suppressAutoOpen = false
                self.isAnchorHovered = true
            }
            .onHover { hovering in
                if hovering, !self.suppressAutoOpen {
                    self.requestOpen()
                }
                self.isAnchorHovered = hovering
                if !hovering {
                    self.suppressAutoOpen = false
                }
            }
            .background(
                SideAttachedPopoverHost(
                    anchorHovered: self.$isAnchorHovered,
                    suppressAutoOpen: self.$suppressAutoOpen,
                    width: self.width,
                    maxHeight: self.maxHeight,
                    onVisibilityChanged: { visible in
                        self.shouldBuildPopoverContent = visible
                    },
                    content: self.popoverContent))
    }

    var popoverContent: AnyView {
        guard self.shouldBuildPopoverContent else {
            return AnyView(EmptyView())
        }

        return AnyView(
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    self.content {
                        self.dismissPopover()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .forceHiddenScrollIndicators()
            .frame(width: self.width, alignment: .leading)
            .frame(maxHeight: self.maxHeight)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cardCornerRadius, style: .continuous)
                    .fill(.regularMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cardCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.46), lineWidth: 0.65)
            }
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.20), radius: 12, x: 0, y: 6))
    }

    private func requestOpen() {
        self.onWillPresent?()
        self.shouldBuildPopoverContent = true
    }

    private func dismissPopover() {
        self.shouldBuildPopoverContent = false
        self.suppressAutoOpen = true
        self.isAnchorHovered = false
    }
}

struct AttachedPopoverMenuItem: View {
    let title: String
    var selected: Bool = false
    var destructive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            self.action()
        } label: {
            HStack(spacing: MenuBarLayoutTokens.hDense) {
                Image(systemName: "checkmark")
                    .font(.appSystem(size: 10, weight: .semibold))
                    .opacity(self.selected ? 1 : 0)
                    .frame(width: 12, alignment: .center)
                Text(self.title)
                    .font(.appSystem(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(self.itemForeground)
            .padding(.horizontal, MenuBarLayoutTokens.hDense)
            .padding(.vertical, MenuBarLayoutTokens.vDense + 1)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(self.itemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { self.isHovered = $0 }
    }

    private var itemForeground: Color {
        if self.isHovered {
            return Color(nsColor: .selectedMenuItemTextColor)
        }
        return self.destructive ? .red : .primary
    }

    private var itemBackground: Color {
        self.isHovered ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}

struct AttachedPopoverMenuDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 2)
    }
}

@MainActor
private struct SideAttachedPopoverHost: NSViewRepresentable {
    @Binding var anchorHovered: Bool
    @Binding var suppressAutoOpen: Bool
    let width: CGFloat?
    let maxHeight: CGFloat?
    let onVisibilityChanged: ((Bool) -> Void)?
    let content: AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(
            anchorHovered: self.$anchorHovered,
            suppressAutoOpen: self.$suppressAutoOpen,
            onVisibilityChanged: self.onVisibilityChanged)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorHovered = self.$anchorHovered
        context.coordinator.suppressAutoOpen = self.$suppressAutoOpen
        context.coordinator.width = self.width
        context.coordinator.maxHeight = self.maxHeight
        context.coordinator.onVisibilityChanged = self.onVisibilityChanged
        context.coordinator.hostingController.rootView = self.content
        context.coordinator.sync(anchorView: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.closeNow()
    }

    @MainActor
    final class Coordinator: NSObject {
        private static var activeCoordinator: Coordinator?

        private enum HorizontalAttachmentSide {
            case left
            case right
        }

        var anchorHovered: Binding<Bool>
        var suppressAutoOpen: Binding<Bool>
        var width: CGFloat?
        var maxHeight: CGFloat?
        var onVisibilityChanged: ((Bool) -> Void)?

        let panel: SideAttachedMenuPanel
        let hostingController: NSHostingController<AnyView>

        private weak var anchorView: NSView?
        private weak var hostWindow: NSWindow?
        private var panelTrackingArea: NSTrackingArea?
        private var panelHovering = false
        private var localMouseMonitor: Any?
        private var closeWorkItem: DispatchWorkItem?
        private var attachmentSide: HorizontalAttachmentSide = .right
        private let bridgeVerticalPadding: CGFloat = 14
        private let edgeOverlap: CGFloat = 1
        private let closeDebounce: TimeInterval = 0.10
        private var reportedVisible = false

        init(
            anchorHovered: Binding<Bool>,
            suppressAutoOpen: Binding<Bool>,
            onVisibilityChanged: ((Bool) -> Void)?)
        {
            self.anchorHovered = anchorHovered
            self.suppressAutoOpen = suppressAutoOpen
            self.onVisibilityChanged = onVisibilityChanged
            self.hostingController = NSHostingController(rootView: AnyView(EmptyView()))
            self.panel = SideAttachedMenuPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true)

            super.init()

            self.panel.isReleasedWhenClosed = false
            self.panel.isOpaque = false
            self.panel.backgroundColor = .clear
            self.panel.hasShadow = true
            self.panel.hidesOnDeactivate = true
            self.panel.level = .statusBar
            self.panel.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
            self.panel.contentViewController = self.hostingController
            self.panel.acceptsMouseMovedEvents = true

            self.installTrackingAreaIfNeeded()
        }

        func sync(anchorView: NSView) {
            self.anchorView = anchorView
            self.hostWindow = anchorView.window
            self.installTrackingAreaIfNeeded()

            let shouldShow = self.anchorHovered.wrappedValue && !self.suppressAutoOpen.wrappedValue
            if shouldShow {
                self.cancelPendingClose()
                self.showOrUpdate()
                return
            }

            if self.suppressAutoOpen.wrappedValue {
                self.closeNow()
            } else {
                self.evaluateAndCloseIfNeeded()
            }
        }

        private func showOrUpdate() {
            guard
                let anchorView,
                let hostWindow
            else { return }

            // Keep attached panel appearance in sync with host window to avoid light surfaces in Dark Mode.
            self.panel.appearance = hostWindow.effectiveAppearance
            self.hostingController.view.appearance = hostWindow.effectiveAppearance

            let fitting = self.hostingController.view.fittingSize
            let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let anchorRectOnScreen = hostWindow.convertToScreen(anchorRectInWindow)
            let visibleFrame = hostWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            guard visibleFrame != .zero else { return }

            let contentWidth = fitting.width
            let panelWidth = min(max(1, contentWidth), visibleFrame.width - 8)

            let contentHeight: CGFloat = if let maxHeight {
                min(fitting.height, maxHeight + 16)
            } else {
                fitting.height
            }
            let panelHeight = min(max(40, contentHeight), visibleFrame.height - 12)

            let rightAvailable = max(0, visibleFrame.maxX - hostWindow.frame.maxX)
            let leftAvailable = max(0, hostWindow.frame.minX - visibleFrame.minX)
            let minimumUsableWidth = panelWidth

            let showRight: Bool = if rightAvailable >= minimumUsableWidth {
                true
            } else if leftAvailable >= minimumUsableWidth {
                false
            } else {
                rightAvailable >= leftAvailable
            }
            self.attachmentSide = showRight ? .right : .left

            let sideAvailable = showRight ? rightAvailable : leftAvailable
            let resolvedPanelWidth = max(1, min(panelWidth, sideAvailable))
            let panelSize = NSSize(width: resolvedPanelWidth, height: panelHeight)

            let rawOriginX = showRight
                ? hostWindow.frame.maxX - self.edgeOverlap
                : hostWindow.frame.minX - panelSize.width + self.edgeOverlap
            let minX = visibleFrame.minX
            let maxX = visibleFrame.maxX - panelSize.width
            let originX = max(minX, min(rawOriginX, maxX))

            let desiredY = anchorRectOnScreen.midY - panelSize.height / 2
            let minY = visibleFrame.minY + 6
            let maxY = visibleFrame.maxY - panelSize.height - 6
            let originY = max(minY, min(desiredY, maxY))

            self.panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize), display: true)
            self.ensureExclusiveVisibility()

            if !self.panel.isVisible {
                self.panel.orderFront(nil)
            }
            self.reportVisibility(true)
            self.startLocalMouseMonitorIfNeeded()
        }

        private func evaluateAndCloseIfNeeded() {
            guard self.panel.isVisible else {
                self.cancelPendingClose()
                self.stopLocalMouseMonitor()
                return
            }
            if self.panelHovering {
                self.cancelPendingClose()
                return
            }
            let mouse = NSEvent.mouseLocation
            if self.isMouseInActiveArea(mouse) {
                self.cancelPendingClose()
                return
            }
            self.scheduleClose()
        }

        func closeNow() {
            self.cancelPendingClose()
            self.stopLocalMouseMonitor()
            if self.panel.isVisible {
                self.panel.orderOut(nil)
            }
            self.hostingController.rootView = AnyView(EmptyView())
            self.panelHovering = false
            self.reportVisibility(false)
            if Self.activeCoordinator === self {
                Self.activeCoordinator = nil
            }
        }

        private func reportVisibility(_ visible: Bool) {
            guard self.reportedVisible != visible else { return }
            self.reportedVisible = visible
            guard let onVisibilityChanged else { return }
            DispatchQueue.main.async {
                onVisibilityChanged(visible)
            }
        }

        private func ensureExclusiveVisibility() {
            if let active = Self.activeCoordinator, active !== self {
                active.anchorHovered.wrappedValue = false
                active.closeNow()
            }
            Self.activeCoordinator = self
        }

        private func scheduleClose() {
            guard self.closeWorkItem == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.closeWorkItem = nil

                guard self.panel.isVisible else { return }
                if self.panelHovering { return }

                let mouse = NSEvent.mouseLocation
                if self.isMouseInActiveArea(mouse) { return }

                self.closeNow()
            }
            self.closeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.closeDebounce, execute: work)
        }

        private func cancelPendingClose() {
            self.closeWorkItem?.cancel()
            self.closeWorkItem = nil
        }

        private func startLocalMouseMonitorIfNeeded() {
            guard self.localMouseMonitor == nil else { return }
            self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged])
            { [weak self] event in
                self?.evaluateAndCloseIfNeeded()
                return event
            }
        }

        private func stopLocalMouseMonitor() {
            guard let localMouseMonitor else { return }
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        private func isMouseInActiveArea(_ point: NSPoint) -> Bool {
            guard let rects = activityRects() else { return false }
            return rects.trigger.contains(point) || rects.panel.contains(point) || rects.bridge.contains(point)
        }

        private func activityRects() -> (trigger: NSRect, panel: NSRect, bridge: NSRect)? {
            guard self.panel.isVisible else { return nil }
            guard let anchorView, let hostWindow else { return nil }

            let triggerRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let triggerRect = hostWindow.convertToScreen(triggerRectInWindow)
            let panelRect = self.panel.frame

            let bridgeMinY = min(triggerRect.minY - self.bridgeVerticalPadding, panelRect.minY)
            let bridgeMaxY = max(triggerRect.maxY + self.bridgeVerticalPadding, panelRect.maxY)
            let bridgeHeight = max(0, bridgeMaxY - bridgeMinY)

            let bridgeRect: NSRect
            switch self.attachmentSide {
            case .right:
                let bridgeX = triggerRect.maxX
                let bridgeWidth = max(0, panelRect.minX - triggerRect.maxX)
                bridgeRect = NSRect(x: bridgeX, y: bridgeMinY, width: bridgeWidth, height: bridgeHeight)
            case .left:
                let bridgeX = panelRect.maxX
                let bridgeWidth = max(0, triggerRect.minX - panelRect.maxX)
                bridgeRect = NSRect(x: bridgeX, y: bridgeMinY, width: bridgeWidth, height: bridgeHeight)
            }

            return (triggerRect, panelRect, bridgeRect)
        }

        private func installTrackingAreaIfNeeded() {
            let view = self.hostingController.view
            if let panelTrackingArea {
                view.removeTrackingArea(panelTrackingArea)
            }
            let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
            let tracking = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            view.addTrackingArea(tracking)
            panelTrackingArea = tracking
        }

        @objc(mouseEntered:)
        func mouseEntered(_ event: NSEvent) {
            self.panelHovering = true
            self.cancelPendingClose()
        }

        @objc(mouseExited:)
        func mouseExited(_ event: NSEvent) {
            self.panelHovering = false
            self.evaluateAndCloseIfNeeded()
        }
    }
}

@MainActor
private final class SideAttachedMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
