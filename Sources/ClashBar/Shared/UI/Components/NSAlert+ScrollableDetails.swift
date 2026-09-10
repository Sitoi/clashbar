import AppKit

extension NSAlert {
    func setScrollableDetails(
        _ text: String,
        width: CGFloat = 440,
        height: CGFloat = 200,
        maxCharacters: Int = 20000)
    {
        let clipped = text.count > maxCharacters
            ? String(text.prefix(maxCharacters)) + "\n…"
            : text

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.font = .monospacedSystemFont(ofSize: MenuBarLayoutTokens.FontSize.caption, weight: .regular)
        textView.textColor = .labelColor
        textView.string = clipped

        scrollView.documentView = textView
        self.accessoryView = scrollView
    }
}
