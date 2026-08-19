import AppKit

/// One row in the Saved Calendars submenu: the name, plus a pencil to rename it
/// and an ✕ to remove it.
///
/// A plain `NSMenuItem` can't hold buttons, so the row is a custom view. That
/// means highlighting and clicks are ours to handle — hence the tracking area
/// and the explicit `cancelTracking()` before running an action, which closes
/// the menu the way a normal item would.
final class CalendarRowView: NSView {

    var onSelect: (() -> Void)?
    var onRename: (() -> Void)?
    var onRemove: (() -> Void)?

    private let title: String
    private let isActive: Bool
    private var isHovered = false
    private let renameButton = NSButton()
    private let removeButton = NSButton()

    private static let rowHeight: CGFloat = 22
    private static let buttonSize: CGFloat = 17
    private static let textInset: CGFloat = 21     // room for the checkmark
    /// Everything either side of the name: checkmark, both buttons, padding.
    private static let chrome: CGFloat = textInset + buttonSize * 2 + 24

    init(title: String, isActive: Bool) {
        self.title = title
        self.isActive = isActive
        // Wide enough for the name and both buttons, so nothing is clipped.
        let width = max(220, CalendarRowView.chrome + CalendarRowView.width(of: title))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: CalendarRowView.rowHeight))

        setUp(renameButton, symbol: "pencil", fallback: "✎",
              tip: "Rename this calendar", action: #selector(renameTapped))
        setUp(removeButton, symbol: "xmark", fallback: "✕",
              tip: "Remove this calendar", action: #selector(removeTapped))
        addSubview(renameButton)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func width(of title: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        return ceil(NSAttributedString(string: title, attributes: attrs).size().width)
    }

    private func setUp(_ button: NSButton, symbol: String, fallback: String,
                       tip: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.target = self
        button.action = action
        button.toolTip = tip
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = fallback          // very old systems: text stand-in
            button.font = NSFont.menuFont(ofSize: 0)
        }
        button.contentTintColor = .secondaryLabelColor
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let size = Self.buttonSize
        let y = (bounds.height - size) / 2
        removeButton.frame = NSRect(x: bounds.maxX - size - 10, y: y, width: size, height: size)
        renameButton.frame = NSRect(x: removeButton.frame.minX - size - 4, y: y, width: size, height: size)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        let tint: NSColor = hovered ? .selectedMenuItemTextColor : .secondaryLabelColor
        renameButton.contentTintColor = tint
        removeButton.contentTintColor = tint
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0),
                         xRadius: 4, yRadius: 4).fill()
        }

        let ink: NSColor = isHovered ? .selectedMenuItemTextColor : .labelColor
        let font = NSFont.menuFont(ofSize: 0)

        // A checkmark, matching every other selected item in the menu. Only the
        // calendar actually being read gets one — in Demo Mode nothing is.
        if isActive {
            let tick = NSAttributedString(string: "✓", attributes: [
                .font: NSFont.menuFont(ofSize: 0), .foregroundColor: ink
            ])
            tick.draw(at: NSPoint(x: 9, y: (bounds.height - tick.size().height) / 2))
        }

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: ink, .paragraphStyle: style
        ])
        let available = renameButton.frame.minX - Self.textInset - 6
        text.draw(with: NSRect(x: Self.textInset, y: (bounds.height - text.size().height) / 2,
                               width: max(available, 10), height: text.size().height),
                  options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
    }

    // MARK: Clicks

    override func mouseUp(with event: NSEvent) {
        dismissMenu()
        onSelect?()
    }

    @objc private func renameTapped() {
        dismissMenu()
        onRename?()
    }

    @objc private func removeTapped() {
        dismissMenu()
        onRemove?()
    }

    /// Close the menu first, then act — otherwise a modal dialog opens behind
    /// the still-tracking menu.
    private func dismissMenu() {
        enclosingMenuItem?.menu?.cancelTracking()
    }
}
