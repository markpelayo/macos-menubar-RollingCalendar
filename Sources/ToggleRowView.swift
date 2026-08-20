import AppKit

/// A menu row that toggles something and **leaves the menu open**.
///
/// AppKit closes a menu as soon as an ordinary `NSMenuItem` is clicked, which is
/// right for a choice and wrong for a set: turning on three lead times would mean
/// three trips through the menu. A custom view handles the click itself, so
/// nothing is dismissed — the tick just changes under the pointer.
///
/// Rows in the same menu are kept in step with each other: switching a category
/// on changes what "All Categories" should read, so after every click each
/// sibling re-reads its own state.
final class ToggleRowView: NSView {

    /// Flips the setting. Called on click; the row then re-reads `isOnNow`.
    var onToggle: (() -> Void)?
    /// The current state, asked for rather than remembered, so a row can never
    /// disagree with the setting behind it.
    var isOnNow: (() -> Bool)?
    /// Anything outside this menu that shows the same setting — parent item
    /// titles, mostly.
    var onChanged: (() -> Void)?

    private let title: String
    private var isOn: Bool
    private var isHovered = false

    private static let rowHeight: CGFloat = 22
    private static let textInset: CGFloat = 21     // room for the checkmark
    private static let trailingPadding: CGFloat = 26

    init(title: String, isOn: Bool, toolTip: String? = nil) {
        self.title = title
        self.isOn = isOn
        let width = max(200, Self.textInset + Self.width(of: title) + Self.trailingPadding)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        self.toolTip = toolTip
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func width(of title: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        return ceil(NSAttributedString(string: title, attributes: attrs).size().width)
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

        if isOn {
            let tick = NSAttributedString(string: "✓", attributes: [
                .font: font, .foregroundColor: ink
            ])
            tick.draw(at: NSPoint(x: 9, y: (bounds.height - tick.size().height) / 2))
        }

        let text = NSAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: ink
        ])
        text.draw(at: NSPoint(x: Self.textInset, y: (bounds.height - text.size().height) / 2))
    }

    // MARK: Clicks

    /// Deliberately no `cancelTracking()`: that's the whole point of this view.
    override func mouseUp(with event: NSEvent) {
        onToggle?()
        refreshSiblings()
        onChanged?()
    }

    /// Re-read the setting and redraw.
    func refreshState() {
        guard let isOnNow else { return }
        let now = isOnNow()
        guard now != isOn else { return }
        isOn = now
        needsDisplay = true
    }

    private func refreshSiblings() {
        guard let items = enclosingMenuItem?.menu?.items else { refreshState(); return }
        for case let row as ToggleRowView in items.compactMap({ $0.view }) {
            row.refreshState()
        }
    }
}
