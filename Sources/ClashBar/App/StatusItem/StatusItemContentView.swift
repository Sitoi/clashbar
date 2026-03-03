import AppKit

final class StatusItemContentView: NSView {
    // Keep a 1pt optical inset to stabilize status-item width across icon/text mode switches.
    private let statusItemHorizontalPadding: CGFloat = MenuBarLayoutTokens.opticalNudge
    private let iconSize: CGFloat = 24
    private let brandIconRenderSize: CGFloat = 18
    private let iconTextSpacing: CGFloat = 1
    private let textContainerWidth: CGFloat = 42
    private let textLineHeight: CGFloat = 11

    private let iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = NSColor.labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = true
        return imageView
    }()

    private let upLabel = StatusItemContentView.makeLineLabel(
        color: NSColor.systemBlue.withAlphaComponent(0.92))
    private let downLabel = StatusItemContentView.makeLineLabel(
        color: NSColor.systemGreen.withAlphaComponent(0.92))

    private var currentDisplay: MenuBarDisplay?
    private lazy var brandStatusIconImage: NSImage? = Self.makeBrandStatusIconImage(size: brandIconRenderSize)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        addSubview(self.iconView)
        addSubview(self.upLabel)
        addSubview(self.downLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var intrinsicContentSize: NSSize {
        CGSize(width: self.requiredWidth, height: NSStatusBar.system.thickness)
    }

    var requiredWidth: CGFloat {
        let display = self.currentDisplay ?? MenuBarDisplay(
            mode: .iconOnly,
            symbolName: "bolt.slash.circle",
            speedLines: nil)
        switch display.mode {
        case .iconOnly:
            return self.statusItemHorizontalPadding * 2 + self.iconSize
        case .iconAndSpeed:
            return self.statusItemHorizontalPadding * 2 + self.iconSize + self.iconTextSpacing + self.textContainerWidth
        case .speedOnly:
            return self.statusItemHorizontalPadding * 2 + self.textContainerWidth
        }
    }

    func apply(display: MenuBarDisplay) {
        self.currentDisplay = display
        self.upLabel.stringValue = display.speedLines?.up ?? ""
        self.downLabel.stringValue = display.speedLines?.down ?? ""

        let shouldShowIcon = display.mode != .speedOnly
        if shouldShowIcon, let brandIcon = brandStatusIconImage {
            self.iconView.image = brandIcon
            self.iconView.contentTintColor = nil
        } else if let symbolName = display.symbolName {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ClashBar")
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            self.iconView.image = image?.withSymbolConfiguration(config)
            self.iconView.contentTintColor = NSColor.labelColor
        } else {
            self.iconView.image = nil
        }

        switch display.mode {
        case .iconOnly:
            self.iconView.isHidden = false
            self.upLabel.isHidden = true
            self.downLabel.isHidden = true
        case .iconAndSpeed:
            self.iconView.isHidden = false
            self.upLabel.isHidden = false
            self.downLabel.isHidden = false
        case .speedOnly:
            self.iconView.isHidden = true
            self.upLabel.isHidden = false
            self.downLabel.isHidden = false
        }

        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()

        let totalHeight = bounds.height
        let centerY = totalHeight / 2
        var cursorX = self.statusItemHorizontalPadding

        if self.iconView.isHidden == false {
            self.iconView.frame = CGRect(
                x: cursorX,
                y: centerY - self.iconSize / 2,
                width: self.iconSize,
                height: self.iconSize)
            cursorX += self.iconSize + self.iconTextSpacing
        } else {
            self.iconView.frame = .zero
        }

        if self.upLabel.isHidden || self.downLabel.isHidden {
            self.upLabel.frame = .zero
            self.downLabel.frame = .zero
            return
        }

        let stackHeight = self.textLineHeight * 2
        let stackOriginY = centerY - stackHeight / 2

        self.upLabel.frame = CGRect(
            x: cursorX,
            y: stackOriginY + self.textLineHeight,
            width: self.textContainerWidth,
            height: self.textLineHeight)
        self.downLabel.frame = CGRect(
            x: cursorX,
            y: stackOriginY,
            width: self.textContainerWidth,
            height: self.textLineHeight)
    }

    private static func makeLineLabel(color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        label.textColor = color
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.cell?.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = true
        return label
    }

    private static func makeBrandStatusIconImage(size: CGFloat) -> NSImage? {
        guard let base = BrandIcon.image?.copy() as? NSImage else { return nil }
        base.size = NSSize(width: size, height: size)
        base.isTemplate = false
        return base
    }
}
