import AppKit

/// The first row of the menu: what this is, which version, and whose it is —
/// opening the project page when clicked.
///
/// Drawn dim, like the informational rows it sits above, because it's a caption
/// rather than a command. A plain `NSMenuItem` can be one or the other but not
/// both: dimming it means disabling it, and a disabled item can't be clicked. A
/// small custom view gets both, and picks up the standard highlight on hover so
/// it still behaves like something you can press.
final class ProjectRowView: NSView {

    var onOpen: (() -> Void)?

    private let text: String
    private var isHovered = false

    private static let rowHeight: CGFloat = 22
    private static let textInset: CGFloat = 21     // aligned with the ticked rows
    private static let trailingPadding: CGFloat = 26

    init(text: String) {
        self.text = text
        let width = Self.textInset + Self.width(of: text) + Self.trailingPadding
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 200), height: Self.rowHeight))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func width(of text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        return ceil(NSAttributedString(string: text, attributes: attrs).size().width)
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

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0),
                         xRadius: 4, yRadius: 4).fill()
        }

        // Dim at rest, legible when highlighted — the same two states every
        // other row in the menu has.
        let ink: NSColor = isHovered ? .selectedMenuItemTextColor : .secondaryLabelColor
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: ink,
            .paragraphStyle: style
        ])
        label.draw(with: NSRect(x: Self.textInset,
                                y: (bounds.height - label.size().height) / 2,
                                width: max(bounds.width - Self.textInset - 8, 10),
                                height: label.size().height),
                   options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
    }

    // MARK: Clicks

    /// Closes the menu first, the way an ordinary item would, then opens the
    /// page — leaving a menu tracking behind a newly focused browser looks like
    /// a bug.
    override func mouseUp(with event: NSEvent) {
        enclosingMenuItem?.menu?.cancelTracking()
        onOpen?()
    }
}
