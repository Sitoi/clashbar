import AppKit

enum PanelAttachmentSide: Equatable {
    case left
    case right
}

struct PanelPlacement: Equatable {
    let frame: CGRect
    let lockedOriginX: CGFloat?
    let attachmentSide: PanelAttachmentSide?
}

struct PanelAnchorContext {
    let visibleFrame: CGRect
    let anchorFrameOnScreen: CGRect
    let hostWindowFrame: CGRect?

    @MainActor
    static func resolve(for anchorView: NSView?) -> PanelAnchorContext? {
        guard
            let anchorView,
            let hostWindow = anchorView.window
        else {
            return nil
        }

        let screen = hostWindow.screen ?? NSScreen.main
        guard let screen else { return nil }

        let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorFrameOnScreen = hostWindow.convertToScreen(anchorFrameInWindow)

        return PanelAnchorContext(
            visibleFrame: screen.visibleFrame,
            anchorFrameOnScreen: anchorFrameOnScreen,
            hostWindowFrame: hostWindow.frame)
    }

    var statusBarBottomY: CGFloat {
        self.visibleFrame.maxY
    }

    func maximumHeightBelowMenuBar(screenPadding: CGFloat, verticalSpacing: CGFloat) -> CGFloat {
        let availableHeightBelowStatusBar = self.statusBarBottomY - self.visibleFrame.minY - screenPadding -
            verticalSpacing
        let visibleHeight = self.visibleFrame.height - screenPadding

        return max(1, min(availableHeightBelowStatusBar, visibleHeight).rounded(.down))
    }

    func menuBarDropdownPlacement(
        panelSize: CGSize,
        horizontalPadding: CGFloat,
        verticalSpacing: CGFloat,
        screenPadding: CGFloat,
        lockedOriginX: CGFloat?,
        preserveHorizontalPosition: Bool)
        -> PanelPlacement
    {
        let minX = self.visibleFrame.minX + horizontalPadding
        let maxX = self.visibleFrame.maxX - horizontalPadding - panelSize.width

        let centeredX = self.anchorFrameOnScreen.midX - panelSize.width / 2
        let stableX = preserveHorizontalPosition ? (lockedOriginX ?? centeredX) : centeredX
        let clampedX = min(max(stableX, minX), maxX)

        let anchorTopY = self.statusBarBottomY - verticalSpacing
        let minY = self.visibleFrame.minY + screenPadding
        let clampedY = max(minY, anchorTopY - panelSize.height)

        return PanelPlacement(
            frame: CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize),
            lockedOriginX: clampedX,
            attachmentSide: nil)
    }

    func sideAttachedPlacement(
        contentSize: CGSize,
        preferredWidth: CGFloat?,
        maximumHeight: CGFloat?,
        screenPadding: CGFloat,
        edgeOverlap: CGFloat)
        -> PanelPlacement?
    {
        guard let hostWindowFrame else { return nil }

        let contentWidth = preferredWidth ?? contentSize.width
        let panelWidth = min(max(1, contentWidth), self.visibleFrame.width - (screenPadding * 2))

        let preferredHeight: CGFloat = if let maximumHeight {
            min(contentSize.height, maximumHeight + (screenPadding * 2))
        } else {
            contentSize.height
        }
        let panelHeight = min(max(40, preferredHeight), self.visibleFrame.height - (screenPadding * 2))

        let rightAvailable = max(0, self.visibleFrame.maxX - hostWindowFrame.maxX)
        let leftAvailable = max(0, hostWindowFrame.minX - self.visibleFrame.minX)

        let attachmentSide: PanelAttachmentSide = if rightAvailable >= panelWidth {
            .right
        } else if leftAvailable >= panelWidth {
            .left
        } else {
            rightAvailable >= leftAvailable ? .right : .left
        }

        let sideAvailable = attachmentSide == .right ? rightAvailable : leftAvailable
        let resolvedPanelWidth = max(1, min(panelWidth, sideAvailable))
        let panelSize = CGSize(width: resolvedPanelWidth, height: panelHeight)

        let rawOriginX: CGFloat = switch attachmentSide {
        case .right:
            hostWindowFrame.maxX - edgeOverlap
        case .left:
            hostWindowFrame.minX - panelSize.width + edgeOverlap
        }
        let minX = self.visibleFrame.minX + screenPadding
        let maxX = self.visibleFrame.maxX - screenPadding - panelSize.width
        let clampedX = max(minX, min(rawOriginX, maxX))

        let desiredY = self.anchorFrameOnScreen.midY - panelSize.height / 2
        let minY = self.visibleFrame.minY + screenPadding
        let maxY = self.visibleFrame.maxY - screenPadding - panelSize.height
        let clampedY = max(minY, min(desiredY, maxY))

        return PanelPlacement(
            frame: CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize),
            lockedOriginX: nil,
            attachmentSide: attachmentSide)
    }
}
