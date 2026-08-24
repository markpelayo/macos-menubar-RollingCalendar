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

    /// Set on a row the user created — a custom lead time, a custom window — to
    /// give it an ✕. Switching a row off and deleting it are different
    /// intentions: one is "not today", the other is "I typed this by mistake, and
    /// the list is getting long".
    var onRemove: (() -> Void)? {
        didSet { updateRemoveButton() }
    }

    private let title: String
    private var isOn: Bool
    private var isHovered = false
    private let removeButton = NSButton()

    private static let rowHeight: CGFloat = 22
    private static let textInset: CGFloat = 21     // room for the checkmark
    private static let trailingPadding: CGFloat = 26
    private static let buttonSize: CGFloat = 17

    init(title: String, isOn: Bool, toolTip: String? = nil) {
        self.title = title
        self.isOn = isOn
        // Room for an ✕ whether or not this row has one, so rows in the same
        // menu line up.
        let width = max(200, Self.textInset + Self.width(of: title)
                             + Self.trailingPadding + Self.buttonSize + 10)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        self.toolTip = toolTip

        removeButton.isBordered = false
        removeButton.bezelStyle = .inline
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.toolTip = "Remove this one"
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove") {
            removeButton.image = image
            removeButton.imagePosition = .imageOnly
        } else {
            removeButton.title = "✕"
            removeButton.font = NSFont.menuFont(ofSize: 0)
        }
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.isHidden = true
        addSubview(removeButton)
    }

    private func updateRemoveButton() {
        removeButton.isHidden = onRemove == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = Self.buttonSize
        removeButton.frame = NSRect(x: bounds.maxX - size - 10,
                                    y: (bounds.height - size) / 2,
                                    width: size, height: size)
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
        removeButton.contentTintColor = hovered ? .selectedMenuItemTextColor : .secondaryLabelColor
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

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: ink, .paragraphStyle: style
        ])
        // Stop short of the ✕ when there is one, so a long label can't run under
        // it.
        let limit = (onRemove == nil ? bounds.maxX : removeButton.frame.minX - 6) - Self.textInset
        text.draw(with: NSRect(x: Self.textInset, y: (bounds.height - text.size().height) / 2,
                               width: max(limit, 10), height: text.size().height),
                  options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
    }

    // MARK: Clicks

    /// Deliberately no `cancelTracking()`: that's the whole point of this view.
    override func mouseUp(with event: NSEvent) {
        onToggle?()
        refreshSiblings()
        onChanged?()
    }

    /// Removal keeps the menu open too — deleting three stale windows shouldn't
    /// mean three trips through the menu either. The row is left in place until
    /// the menu is reopened, so it dims rather than vanishing under the pointer.
    @objc private func removeTapped() {
        onRemove?()
        isOn = false
        onRemove = nil
        removeButton.isHidden = true
        alphaValue = 0.45
        needsDisplay = true
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
