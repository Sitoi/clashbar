import AppKit

final class StatusItemContentView: NSView {
    private enum BrandStatusIconTheme: Hashable {
        case light
        case dark
    }

    // Keep a 1pt optical inset to stabilize status-item width across icon/text mode switches.
    private let statusItemHorizontalPadding: CGFloat = MenuBarLayoutTokens.space1
    private let iconSize: CGFloat = 24
    private let brandIconRenderSize: CGFloat = 24
    private let symbolPointSize: CGFloat = 20
    private let iconTextSpacing: CGFloat = 1
    private let textContainerWidth: CGFloat = 42
    private let textLineHeight: CGFloat = 11

    private let iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = NSColor.labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = true
        return imageView
    }()

    private var currentDisplay: MenuBarDisplay?
    private var cachedUpLine: String = ""
    private var cachedDownLine: String = ""
    private lazy var runBrandStatusIconImages: [BrandStatusIconTheme: NSImage] = Self.makeBrandStatusIconImages(
        source: BrandIcon.runImage, size: brandIconRenderSize)
    private lazy var sleepBrandStatusIconImages: [BrandStatusIconTheme: NSImage] = Self.makeBrandStatusIconImages(
        source: BrandIcon.sleepImage, size: brandIconRenderSize)
    private static let brandIconRenderScales: [CGFloat] = [1, 2, 3]
    private static let speedTextAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingHead
        return [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }()

    var usesBrandIcon: Bool {
        self.runBrandStatusIconImages.isEmpty == false || self.sleepBrandStatusIconImages.isEmpty == false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        self.addSubview(self.iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.refreshBrandIconForCurrentAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.refreshBrandIconForCurrentAppearance()
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
            speedLines: nil,
            isRunning: false)
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
        let previousMode = self.currentDisplay?.mode
        let previousSymbolName = self.currentDisplay?.symbolName
        let previousIconHidden = self.iconView.isHidden
        let previousUpLine = self.cachedUpLine
        let previousDownLine = self.cachedDownLine

        self.currentDisplay = display
        self.cachedUpLine = display.speedLines?.up ?? ""
        self.cachedDownLine = display.speedLines?.down ?? ""

        let shouldShowIcon = display.mode != .speedOnly
        if shouldShowIcon, let brandIcon = self.brandStatusIconImage(isRunning: display.isRunning) {
            if self.iconView.image !== brandIcon {
                self.iconView.image = brandIcon
            }
            // Brand icon is pre-rendered into menu-bar monochrome variants.
            self.iconView.contentTintColor = nil
        } else if let symbolName = display.symbolName {
            if self.iconView.image == nil ||
                previousSymbolName != symbolName ||
                self.currentDisplay?.mode != previousMode
            {
                let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ClashBar")
                let config = NSImage.SymbolConfiguration(pointSize: self.symbolPointSize, weight: .semibold)
                self.iconView.image = image?.withSymbolConfiguration(config)
            }
            self.iconView.contentTintColor = NSColor.labelColor
        } else {
            self.iconView.image = nil
            self.iconView.contentTintColor = nil
        }

        switch display.mode {
        case .iconOnly:
            self.iconView.isHidden = false
        case .iconAndSpeed:
            self.iconView.isHidden = false
        case .speedOnly:
            self.iconView.isHidden = true
        }

        let modeChanged = previousMode != display.mode
        let iconVisibilityChanged = previousIconHidden != self.iconView.isHidden
        let speedTextChanged = previousUpLine != self.cachedUpLine || previousDownLine != self.cachedDownLine

        if modeChanged || iconVisibilityChanged {
            self.needsLayout = true
        }
        if modeChanged || speedTextChanged {
            self.needsDisplay = true
        }
        if modeChanged {
            self.invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()

        let totalHeight = bounds.height
        let centerY = floor(totalHeight / 2)
        let iconOriginX = floor(self.statusItemHorizontalPadding)

        if self.iconView.isHidden == false {
            self.iconView.frame = CGRect(
                x: iconOriginX,
                y: floor(centerY - self.iconSize / 2),
                width: self.iconSize,
                height: self.iconSize)
        } else {
            self.iconView.frame = .zero
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let display = self.currentDisplay else { return }
        guard display.mode != .iconOnly else { return }

        let originX = floor(
            self.statusItemHorizontalPadding +
                (display.mode == .iconAndSpeed ? (self.iconSize + self.iconTextSpacing) : 0))
        let centerY = floor(self.bounds.height / 2)
        let stackHeight = self.textLineHeight * 2
        let stackOriginY = floor(centerY - stackHeight / 2)

        let upRect = CGRect(
            x: originX,
            y: floor(stackOriginY + self.textLineHeight),
            width: self.textContainerWidth,
            height: self.textLineHeight)
        let downRect = CGRect(
            x: originX,
            y: stackOriginY,
            width: self.textContainerWidth,
            height: self.textLineHeight)

        if !dirtyRect.intersects(upRect), !dirtyRect.intersects(downRect) {
            return
        }

        (self.cachedUpLine as NSString).draw(
            in: upRect,
            withAttributes: Self.speedTextAttributes)
        (self.cachedDownLine as NSString).draw(
            in: downRect,
            withAttributes: Self.speedTextAttributes)
    }

    private func brandStatusIconImage(isRunning: Bool) -> NSImage? {
        let images = isRunning ? self.runBrandStatusIconImages : self.sleepBrandStatusIconImages
        guard images.isEmpty == false else { return nil }
        let theme = Self.brandStatusIconTheme(for: self.effectiveAppearance)
        return images[theme] ?? images.values.first
    }

    private func refreshBrandIconForCurrentAppearance() {
        guard self.currentDisplay?.mode != .speedOnly else { return }
        let isRunning = self.currentDisplay?.isRunning ?? false
        guard let image = self.brandStatusIconImage(isRunning: isRunning) else { return }
        guard self.iconView.image !== image || self.iconView.contentTintColor != nil else { return }
        self.iconView.image = image
        self.iconView.contentTintColor = nil
        self.iconView.needsDisplay = true
        self.needsDisplay = true
    }

    private static func makeBrandStatusIconImages(source: NSImage?, size: CGFloat) -> [BrandStatusIconTheme: NSImage] {
        guard let source else { return [:] }
        let targetSize = NSSize(width: size, height: size)
        var images: [BrandStatusIconTheme: NSImage] = [:]

        for theme in [BrandStatusIconTheme.light, .dark] {
            let rendered = NSImage(size: targetSize)
            let color = self.brandStatusIconColor(for: theme)

            for scale in Self.brandIconRenderScales {
                guard let representation = self.makeBrandStatusIconRepresentation(
                    source: source,
                    pointSize: targetSize,
                    scale: scale,
                    color: color)
                else {
                    continue
                }
                rendered.addRepresentation(representation)
            }

            guard rendered.representations.isEmpty == false else { continue }
            rendered.isTemplate = true
            images[theme] = rendered
        }

        return images
    }

    private static func makeBrandStatusIconRepresentation(
        source: NSImage,
        pointSize: NSSize,
        scale: CGFloat,
        color: NSColor) -> NSBitmapImageRep?
    {
        let pixelWidth = max(1, Int((pointSize.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((pointSize.height * scale).rounded(.up)))

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        else {
            return nil
        }

        representation.size = pointSize

        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: pointSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil)
        context.cgContext.setBlendMode(.sourceIn)
        context.cgContext.setFillColor((color.usingColorSpace(.deviceRGB) ?? color).cgColor)
        context.cgContext.fill(CGRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    private static func brandStatusIconTheme(for appearance: NSAppearance) -> BrandStatusIconTheme {
        let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        switch match {
        case .some(.darkAqua), .some(.vibrantDark):
            return BrandStatusIconTheme.dark
        default:
            return BrandStatusIconTheme.light
        }
    }

    private static func brandStatusIconColor(for theme: BrandStatusIconTheme) -> NSColor {
        let appearanceName: NSAppearance.Name = switch theme {
        case .light:
            .aqua
        case .dark:
            .darkAqua
        }

        if let appearance = NSAppearance(named: appearanceName) {
            var resolved = NSColor.labelColor
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? NSColor.labelColor
            }
            return resolved
        }
        return NSColor.labelColor
    }
}
