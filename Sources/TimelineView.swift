import AppKit

/// The rolling timeline drawn inside the menu bar.
/// "Now" is a red line at the horizontal centre. Time flows right-to-left:
/// the past is on the left, the future on the right, so event blocks slide left.
final class TimelineView: NSView {

    // Total visible span, centred on now. 4 h => 2 h each side.
    var windowSeconds: TimeInterval = Config.windowHours * 3600

    var events: [CalEvent] = [] {
        didSet { needsDisplay = true }
    }

    /// Set when the feed could not be loaded, so we can show a hint.
    var errorMessage: String? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    /// Let clicks fall through to the status bar button so the menu still opens.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        let hourColor = isDark ? NSColor.white : NSColor.black
        let quarterColor = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.35)
        let nowColor = NSColor.systemRed

        let now = Date()

        // The countdown gets its own gutter on the left; the timeline occupies
        // the rest, so "now" stays centred within the timeline itself.
        let gutter = min(Config.countdownWidth, max(bounds.width - 8, 0))
        let strip = CGRect(x: bounds.minX + gutter, y: bounds.minY,
                           width: max(bounds.width - gutter, 1), height: bounds.height)

        let half = windowSeconds / 2
        let windowStart = now.addingTimeInterval(-half)
        let windowEnd = now.addingTimeInterval(half)
        let pxPerSec = strip.width / CGFloat(windowSeconds)
        func x(_ d: Date) -> CGFloat {
            strip.midX + CGFloat(d.timeIntervalSince(now)) * pxPerSec
        }

        let track = strip.insetBy(dx: 0, dy: 2)

        ctx.saveGState()

        if let msg = errorMessage {
            drawText(msg, in: bounds, color: NSColor.systemRed, centered: true)
            ctx.restoreGState()
            return
        }

        // --- Countdown for the block we're inside, in the left gutter ---
        drawCountdown(now: now, in: CGRect(x: bounds.minX, y: bounds.minY,
                                           width: gutter, height: bounds.height),
                      isDark: isDark)

        ctx.clip(to: strip)

        // --- Tick marks: black on the hour, grey every 15 minutes ---
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Config.displayTimeZone
        if var tick = cal.nextDate(after: windowStart.addingTimeInterval(-900),
                                   matching: DateComponents(minute: 0),
                                   matchingPolicy: .nextTime) {
            tick = tick.addingTimeInterval(-3600)  // start a bit before the window
            while tick < windowEnd {
                let minute = cal.component(.minute, from: tick)
                if tick >= windowStart, minute % 15 == 0 {
                    let isHour = minute == 0
                    let px = round(x(tick))
                    let w: CGFloat = isHour ? 2.0 : 1.0
                    let inset: CGFloat = isHour ? 0 : track.height * 0.22
                    (isHour ? hourColor : quarterColor).setFill()
                    ctx.fill(CGRect(x: px - w / 2, y: track.minY + inset,
                                    width: w, height: track.height - inset * 2))
                }
                tick = tick.addingTimeInterval(900)
            }
        }

        // --- Event blocks ---
        let visible = events.filter { !$0.isAllDay && $0.intersects(windowStart, windowEnd) }
        for ev in visible {
            let x0 = max(x(ev.start), strip.minX - 4)
            let x1 = min(x(ev.end), strip.maxX + 4)
            let full = max(x1 - x0, 3)

            // Purely visual separation — the block's time span is untouched, we
            // just shave a sliver off each edge so neighbours don't merge into
            // one solid bar. Capped so short blocks don't vanish.
            let trim = min(Config.blockGap / 2, full * 0.18)
            // Floor of 3 so the 0.75 pt inset below can't collapse the fill.
            let rect = CGRect(x: x0 + trim, y: track.minY,
                              width: max(full - trim * 2, 3), height: track.height)
            let w = rect.width
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 2, yRadius: 2)

            // Google's own colour for this event, falling back to green.
            let base = ev.color ?? NSColor.systemGreen
            base.withAlphaComponent(Config.solidBlocks ? 0.92 : (isDark ? 0.30 : 0.22)).setFill()
            path.fill()
            base.setStroke()
            path.lineWidth = 1.5
            path.stroke()

            // Only label blocks wide enough to show something meaningful;
            // the threshold scales with the font so bigger text needs more room.
            if Config.showTitles, w > Config.titleFontSize * 2.4 {
                let textRect = rect.insetBy(dx: 4, dy: 0)
                let textColor: NSColor = Config.solidBlocks
                    ? (base.isLight ? NSColor.black : NSColor.white)
                    : (isDark ? NSColor.white : NSColor.black.withAlphaComponent(0.85))
                drawText(ev.title, in: textRect, color: textColor, centered: false)
            }
        }

        // --- Now line (drawn last so it stays on top) ---
        nowColor.setFill()
        let nowX = round(strip.midX)
        ctx.fill(CGRect(x: nowX - 1, y: strip.minY, width: 2, height: strip.height))

        ctx.restoreGState()
    }

    // MARK: Countdown

    /// Time left in the block we're currently inside — or, if we're between
    /// blocks, how long until the next one starts.
    private func drawCountdown(now: Date, in rect: CGRect, isDark: Bool) {
        guard rect.width > 8 else { return }   // gutter hidden
        let timed = events.filter { !$0.isAllDay }
        // If blocks are nested, count down the one ending soonest — that's the
        // deadline that actually matters.
        let current = timed.filter { $0.start <= now && $0.end > now }
            .min(by: { $0.end < $1.end })

        let text: String
        let color: NSColor
        if let current {
            text = Self.format(current.end.timeIntervalSince(now))
            let remaining = current.end.timeIntervalSince(now)
            // Nudge toward red in the last two minutes.
            color = remaining <= 120 ? NSColor.systemRed
                                     : (isDark ? NSColor.white : NSColor.black)
        } else if let next = timed.filter({ $0.start > now }).min(by: { $0.start < $1.start }) {
            text = "in " + Self.format(next.start.timeIntervalSince(now))
            color = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.45)
        } else {
            return
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            // Menu bar font size and regular weight, matching other menu bar
            // widgets; monospaced digits only so the number doesn't jitter.
            .font: NSFont.monospacedDigitSystemFont(ofSize: Config.countdownFontSize, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let h = attributed.size().height
        attributed.draw(with: CGRect(x: rect.minX + 2, y: rect.midY - h / 2,
                                     width: rect.width - 4, height: h),
                        options: [.usesLineFragmentOrigin])
    }

    /// "1h05", "12m", "45s" — compact enough for the menu bar.
    static func format(_ seconds: TimeInterval) -> String {
        // Round up, so it only reads 0 once the block has actually ended.
        let total = max(Int(seconds.rounded(.up)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return String(format: "%dh%02d", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    private func drawText(_ s: String, in rect: CGRect, color: NSColor, centered: Bool) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = centered ? .center : .left
        let attrs: [NSAttributedString.Key: Any] = [
            // Same font macOS uses for menu bar labels.
            .font: NSFont.menuBarFont(ofSize: Config.titleFontSize),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let attributed = NSAttributedString(string: s, attributes: attrs)
        let h = attributed.size().height
        let r = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        attributed.draw(with: r, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
    }
}

// MARK: - Colour helpers

extension CalEvent {
    /// Google's event colour, if we have one.
    var color: NSColor? {
        guard let colorHex else { return nil }
        return NSColor(hexString: colorHex)
    }
}

extension NSColor {
    /// Accepts "#rrggbb", "rrggbb", "#rgb".
    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255.0,
                  green: CGFloat((v >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(v & 0xFF) / 255.0,
                  alpha: 1.0)
    }

    /// Rough perceptual brightness test, for picking readable label text.
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return true }
        let luma = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luma > 0.6
    }
}
