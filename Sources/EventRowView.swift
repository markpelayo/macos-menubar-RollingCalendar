import AppKit

/// One block in the day list: something to read, not something to press.
///
/// A plain `NSMenuItem` gives you two choices, and neither is right here.
/// Enabled, it dismisses the whole menu when clicked — an accidental click while
/// reading the list costs you the menu. Disabled, it stops responding to the
/// pointer altogether *and* AppKit washes out the colour swatch that says which
/// category the block belongs to.
///
/// So the row is a view: it highlights under the pointer, because a highlight is
/// genuinely useful for tracking your place in a list of sixty, and it swallows
/// the click, because there is nothing for a click to do.
///
/// The highlight is a soft yellow rather than the system's selection blue, for
/// two reasons. Blue is what macOS uses for *selection*, and nothing here can be
/// selected — borrowing it promises something the row can't deliver, which is the
/// same false note as a click that does nothing. And the text is already carrying
/// meaning in its colours — dim for past, bold for now, a chip per category — so
/// a saturated band behind it fights all three. Yellow reads as a highlighter
/// marking your place, which is exactly what it's for.
///
/// The actionable rows elsewhere in the menu keep the blue, because there the
/// promise is true.
final class EventRowView: NSView {

    private let content: NSAttributedString
    /// Measured once at build time — sixty rows redrawing on every hover is not
    /// the place to re-measure text.
    private let contentSize: NSSize
    private var isHovered = false

    private static let inset: CGFloat = 21
    private static let trailingPadding: CGFloat = 20
    private static let verticalPadding: CGFloat = 3

    /// Measured with `boundingRect` rather than `size()`: every column in this
    /// row sits on a tab stop, and tab stops only resolve against a line
    /// fragment. `size()` would under-measure and the last column would be cut.
    private static func measure(_ content: NSAttributedString) -> NSSize {
        let bounds = content.boundingRect(with: NSSize(width: 4000, height: 0),
                                          options: [.usesLineFragmentOrigin])
        return NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    init(content: NSAttributedString) {
        self.content = content
        let size = Self.measure(content)
        self.contentSize = size
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: size.width + Self.inset + Self.trailingPadding,
                                 height: size.height + Self.verticalPadding * 2))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    // MARK: Drawing

    /// Light mode gets a proper highlighter yellow behind dark text. Dark mode
    /// gets a much fainter wash: the text there is near-white, and anything
    /// approaching a solid yellow would either drown it or force the row to
    /// restyle its own colours — which are carrying meaning of their own.
    private var highlightColour: NSColor {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.systemYellow.withAlphaComponent(dark ? 0.20 : 0.34)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            highlightColour.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0),
                         xRadius: 4, yRadius: 4).fill()
        }
        content.draw(with: NSRect(x: Self.inset,
                                  y: (bounds.height - contentSize.height) / 2,
                                  width: max(bounds.width - Self.inset - 6, 10),
                                  height: contentSize.height),
                     options: [.usesLineFragmentOrigin])
    }

    // MARK: Clicks

    /// Swallowed on purpose. Without this the menu would close, which is a poor
    /// trade for a click that was never going to do anything.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}
