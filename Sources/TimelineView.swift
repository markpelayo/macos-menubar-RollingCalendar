import AppKit

/// The rolling timeline drawn inside the menu bar.
///
/// Layout, left to right — always a single row:
///
///     🔴(2) Vendor Call (59m)  ─ past │ future ─  (2h15) Deep Work 🔴(2)
///                                       │
///                                 red "now" line
///
/// Time flows right-to-left: the past is on the left, the future on the right,
/// so blocks slide leftward past the fixed centre line. The blocks themselves
/// carry no text — the names live in the gutters, in full, and the item widens
/// to fit them. There are no tick marks: only past, now and future.
final class TimelineView: NSView {

    /// Total visible span, centred on now. 30 min => 15 min each side.
    var windowSeconds: TimeInterval { Config.windowMinutes * 60 }

    var events: [CalEvent] = [] {
        didSet { generation += 1; needsDisplay = true }
    }

    /// Set when the calendar could not be loaded, so we can show a hint.
    var errorMessage: String? {
        didSet { generation += 1; needsDisplay = true }
    }

    /// Bumped whenever anything the labels depend on changes, so the cache below
    /// knows its answer is stale.
    private var generation = 0

    /// How long before a block ends the left label starts shouting.
    static var urgentThreshold: TimeInterval { Config.urgentSeconds }

    override var isFlipped: Bool { false }

    /// Let clicks fall through to the status bar button so the menu still opens.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - What the gutters say

    private struct Gutters {
        /// Attributed rather than plain, so one run can be bold — the simulated
        /// marker — while the rest of the label stays at normal weight.
        var left: NSAttributedString?
        var right: NSAttributedString?
        var leftWidth: CGFloat = 0
        var rightWidth: CGFloat = 0
    }

    /// One run of a gutter label.
    private struct Segment {
        let text: String
        var bold = false
        /// Only the event name may be shortened; badges and times never are.
        var truncatable = false
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// A zero-length event — a reminder pinned to an instant — has no width to
    /// draw, but it's still something on your calendar, so for counting and
    /// labelling we treat it as occupying a nominal minute.
    private static func span(_ e: CalEvent) -> (start: Date, end: Date) {
        (e.start, max(e.end, e.start.addingTimeInterval(60)))
    }

    private static func overlaps(_ a: CalEvent, _ b: CalEvent) -> Bool {
        let x = span(a), y = span(b)
        return x.end > y.start && x.start < y.end
    }

    /// The labels are wanted twice per tick — once to size the menu bar item,
    /// once to draw it — and composing them means building attributed strings and
    /// measuring text. Once per second is enough, so the answer is kept until the
    /// second, the events, the settings or the appearance change.
    private struct GutterKey: Equatable {
        let second: Int
        let generation: Int
        let dark: Bool
        let settings: Int
    }

    private var cachedGutters: (key: GutterKey, value: Gutters)?

    /// A fingerprint of exactly what the labels read — including the font size,
    /// since the text is measured as well as composed. Nothing else in `Config`
    /// belongs here: a value that doesn't reach a label can't make one stale.
    private static var settingsFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(Config.maxLabelWidth)
        hasher.combine(Config.titleFontSize)
        hasher.combine(Config.showNowName)
        hasher.combine(Config.showNowTimeLeft)
        hasher.combine(Config.showNextName)
        hasher.combine(Config.showNextDuration)
        hasher.combine(Config.isSimulating)
        hasher.combine(Config.urgentSeconds)
        return hasher.finalize()
    }

    private func gutters(now: Date) -> Gutters {
        // `Clock.now` carries a user-set offset; clamping keeps the conversion
        // total even if the stored value is nonsense.
        let raw = now.timeIntervalSince1970
        let stamp = raw.isFinite ? min(max(raw, -1e12), 1e12) : 0
        let key = GutterKey(second: Int(stamp),
                            generation: generation,
                            dark: isDarkAppearance,
                            settings: Self.settingsFingerprint)
        if let cached = cachedGutters, cached.key == key { return cached.value }
        let fresh = composeGutters(now: now)
        cachedGutters = (key, fresh)
        return fresh
    }

    private func composeGutters(now: Date) -> Gutters {
        var g = Gutters()
        let timed = events.filter { !$0.isAllDay }
        let running = timed.filter { let s = Self.span($0); return s.start <= now && s.end > now }
        let upcoming = timed.filter { $0.start > now }
        // Reminders count towards the warnings, but a "(0s)" label helps nobody,
        // so only real blocks are eligible to headline a gutter.
        let runningBlocks = running.filter { $0.end > $0.start }
        let upcomingBlocks = upcoming.filter { $0.end > $0.start }

        let cap = Config.maxLabelWidth
        let current = Self.pickChained(from: runningBlocks, all: timed, preferSoonestEnd: true)
        // Said in words rather than by tinting anything — the whole point of
        // simulating a time is to see the real colours at that time. It's the
        // only bold run in the label, so it reads as an annotation.
        let marker = Config.isSimulating ? "(❗Simulated❗)" : ""
        let normalInk: NSColor = isDarkAppearance ? .white : .black

        if let current {
            let remaining = current.end.timeIntervalSince(now)
            // Red and bold for the last two minutes — colour alone was easy to
            // miss at a glance.
            let urgent = remaining <= Self.urgentThreshold
            // 🔴 means "two things want you right now". It counts only what is
            // genuinely concurrent, so a reminder that fires and finishes in the
            // same instant raises the flag briefly and then lets it go, rather
            // than nagging for the rest of a long block.
            let clash = running.count
            g.left = Self.compose([
                Segment(text: marker, bold: true),
                Segment(text: clash > 1 ? "🔴(\(clash))" : ""),
                Segment(text: Config.showNowName ? current.title : "", truncatable: true),
                Segment(text: Config.showNowTimeLeft ? "(\(Self.format(remaining)))" : "")
            ], cap: cap, color: urgent ? .systemRed : normalInk,
               baseBold: urgent, alignment: .right)
        } else if Config.isSimulating {
            // Nothing running, but still say we're pretending.
            g.left = Self.compose([Segment(text: marker, bold: true)],
                                  cap: cap, color: normalInk, baseBold: false, alignment: .right)
        }

        if let next = Self.pickChained(from: upcomingBlocks, all: timed, preferSoonestEnd: false) {
            // On the right, 🔴 flags a collision that hasn't reached now yet.
            // The block you're already in counts as a participant, so a meeting
            // dropped into the middle of an all-day block is flagged before it
            // arrives. Once the collision crosses the now line it stops being
            // counted here and the left gutter picks it up instead.
            var colliding = upcoming.filter { Self.overlaps($0, next) }
            if let current, Self.overlaps(current, next) { colliding.append(current) }
            let clash = colliding.count
            g.right = Self.compose([
                // How long that block runs for.
                Segment(text: Config.showNextDuration
                        ? "(\(Self.format(next.end.timeIntervalSince(next.start))))" : ""),
                Segment(text: Config.showNextName ? next.title : "", truncatable: true),
                Segment(text: clash > 1 ? "🔴(\(clash))" : "")
            ], cap: cap, color: normalInk, baseBold: false, alignment: .left)
        }

        if let l = g.left { g.leftWidth = min(ceil(l.size().width) + 1, cap) }
        if let r = g.right { g.rightWidth = min(ceil(r.size().width) + 1, cap) }
        return g
    }

    /// Joins segments with single spaces into one label. Only the truncatable
    /// segment is shortened to respect `cap`, so badges, markers and countdowns
    /// are never sacrificed to a long event name.
    ///
    ///   left:   (❗Simulated❗) 🔴(2) Some Very Long Meet… (5m)
    ///   right:  (16h) Some Very Long Meet… 🔴(2)
    private static func compose(_ segments: [Segment], cap: CGFloat, color: NSColor,
                                baseBold: Bool, alignment: NSTextAlignment) -> NSAttributedString? {
        let parts = segments.filter { !$0.text.isEmpty }
        guard !parts.isEmpty else { return nil }

        // Everything that can't shrink, plus the spaces between segments.
        let fixedWidth = parts
            .filter { !$0.truncatable }
            .reduce(CGFloat(0)) { $0 + width(of: $1.text, bold: $1.bold || baseBold) }
        let spacing = width(of: String(repeating: " ", count: max(parts.count - 1, 0)),
                            bold: baseBold)

        var final: [Segment] = []
        for segment in parts {
            guard segment.truncatable else { final.append(segment); continue }
            let shown = fitted(segment.text, into: cap - fixedWidth - spacing,
                               bold: segment.bold || baseBold)
            if !shown.isEmpty {
                final.append(Segment(text: shown, bold: segment.bold))
            }
        }
        guard !final.isEmpty else { return nil }

        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping     // already fitted above

        let out = NSMutableAttributedString()
        for (index, segment) in final.enumerated() {
            if index > 0 {
                out.append(NSAttributedString(string: " ", attributes: [
                    .font: labelFont(bold: baseBold),
                    .foregroundColor: color,
                    .paragraphStyle: style
                ]))
            }
            out.append(NSAttributedString(string: segment.text, attributes: [
                .font: labelFont(bold: segment.bold || baseBold),
                .foregroundColor: color,
                .paragraphStyle: style
            ]))
        }
        return out
    }

    /// Trim a name to fit, with an ellipsis. Returns "" if there's no room worth using.
    private static func fitted(_ text: String, into available: CGFloat,
                               bold: Bool = false) -> String {
        guard available > 12 else { return "" }
        let full = width(of: text, bold: bold)
        if full <= available { return text }

        // Start from a proportional guess rather than trimming one glyph at a time.
        let ratio = Double(available / max(full, 1))
        var chars = Array(text.prefix(max(1, Int(Double(text.count) * ratio))))
        while !chars.isEmpty,
              width(of: String(chars).trimmingCharacters(in: .whitespaces) + "…", bold: bold) > available {
            chars.removeLast()
        }
        while chars.count < text.count,
              width(of: String(text.prefix(chars.count + 1)).trimmingCharacters(in: .whitespaces) + "…",
                    bold: bold) <= available {
            chars.append(text[text.index(text.startIndex, offsetBy: chars.count)])
        }
        let trimmed = String(chars).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : trimmed + "…"
    }

    /// Breathing room between a label and the timeline. There is deliberately
    /// none on the outer edges — macOS already pads status items, and adding our
    /// own leaves a visible gap before the first character and after the last.
    private static let innerGap: CGFloat = 8

    /// Width the status item needs so both names fit in full.
    func desiredWidth() -> CGFloat {
        let g = gutters(now: Clock.now)
        var w = Config.timelineWidth
        if g.leftWidth > 0 { w += g.leftWidth + Self.innerGap }
        if g.rightWidth > 0 { w += g.rightWidth + Self.innerGap }
        return ceil(w)
    }

    /// Which block a gutter should name.
    ///
    /// Time comes first: on the left, whatever ends soonest — that's the
    /// deadline that matters; on the right, whatever starts soonest. Only when
    /// two candidates tie exactly does chain position decide it, preferring the
    /// block that belongs to a back-to-back run (its start meets another's end
    /// and its end meets another's start). That's the time-blocked backbone; a
    /// meeting dropped on top of it chains to nothing, so the backbone keeps the
    /// label and the interloper is what the 🔴 is telling you about.
    static func pickChained(from candidates: [CalEvent], all: [CalEvent],
                            preferSoonestEnd: Bool) -> CalEvent? {
        guard candidates.count > 1 else { return candidates.first }
        let tolerance: TimeInterval = 60

        func meets(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) <= tolerance }

        func score(_ ev: CalEvent) -> Int {
            var s = 0
            if all.contains(where: { $0.start != ev.start && meets($0.end, ev.start) }) { s += 2 }
            if all.contains(where: { $0.start != ev.start && meets($0.start, ev.end) }) { s += 2 }
            return s
        }

        return candidates.min { a, b in
            // Nearest in time wins — a far-off block must never outrank one
            // that's about to happen, however well it chains.
            if preferSoonestEnd, a.end != b.end { return a.end < b.end }
            if !preferSoonestEnd, a.start != b.start { return a.start < b.start }
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }                       // then better-chained
            let da = a.end.timeIntervalSince(a.start), db = b.end.timeIntervalSince(b.start)
            if da != db { return da < db }                       // then shorter
            return a.title < b.title                             // stable
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let now = Clock.now

        if let msg = errorMessage {
            drawLabel(msg, in: bounds, color: .systemRed, alignment: .center)
            return
        }

        let g = gutters(now: now)
        let gap = Self.innerGap
        // Labels sit flush with the outer edges; the gap is only between a
        // label and the timeline.
        let leftGutter = g.leftWidth > 0 ? g.leftWidth + gap : 0
        let rightGutter = g.rightWidth > 0 ? g.rightWidth + gap : 0
        let strip = CGRect(x: bounds.minX + leftGutter,
                           y: bounds.minY,
                           width: max(bounds.width - leftGutter - rightGutter, 1),
                           height: bounds.height)

        // --- Gutters --- colours and weights are already baked into the text
        if let text = g.left {
            draw(text, in: CGRect(x: bounds.minX, y: bounds.minY,
                                  width: g.leftWidth, height: bounds.height))
        }
        if let text = g.right {
            draw(text, in: CGRect(x: strip.maxX + gap, y: bounds.minY,
                                  width: g.rightWidth, height: bounds.height))
        }

        // --- Timeline ---
        let half = windowSeconds / 2
        let windowStart = now.addingTimeInterval(-half)
        let windowEnd = now.addingTimeInterval(half)
        let pxPerSec = strip.width / CGFloat(windowSeconds)
        func x(_ d: Date) -> CGFloat {
            strip.midX + CGFloat(d.timeIntervalSince(now)) * pxPerSec
        }

        ctx.saveGState()
        ctx.clip(to: strip)

        let track = strip.insetBy(dx: 0, dy: 2)
        let nowX = strip.midX

        // Zero-length events (reminders) have no extent in time, so drawing them
        // would put a stray sliver between the two real blocks they sit between.
        // They still count towards the 🔴 warnings and appear in the dropdown.
        // Longest first, so a shorter concurrent block stays visible on top.
        let visible = events
            .filter { !$0.isAllDay && $0.end > $0.start && $0.intersects(windowStart, windowEnd) }
            .sorted { $0.end.timeIntervalSince($0.start) > $1.end.timeIntervalSince($1.start) }

        for ev in visible {
            let x0 = max(x(ev.start), strip.minX - 12)
            let x1 = min(x(ev.end), strip.maxX + 12)
            let full = max(x1 - x0, 3)

            // Cosmetic separation only — the block's time span is untouched.
            let trim = min(Config.blockGap / 2, full * 0.2)
            let rect = CGRect(x: x0 + trim, y: track.minY,
                              width: max(full - trim * 2, 3), height: track.height)

            // Capsule ends, or a fixed radius if one is configured.
            let radius = Config.blockCornerRadius > 0
                ? min(Config.blockCornerRadius, min(rect.height, rect.width) / 2)
                : min(rect.height, rect.width) / 2
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

            // No keyword rule and no colour from the calendar: neutral grey, so
            // "not classified yet" is obvious rather than masquerading as green.
            let base = ev.color ?? Config.unmatchedColour
            // Fully opaque, so the colour drawn is exactly the colour asked for
            // — at 95% the menu bar behind it shifted every hue slightly.
            let future = Config.solidBlocks ? base
                                            : base.withAlphaComponent(isDark ? 0.32 : 0.24)
            // Elapsed time reads paler, so a block visibly fades as it passes now.
            let past = (base.highlight(withLevel: isDark ? 0.45 : 0.6) ?? base)
                .withAlphaComponent(Config.solidBlocks ? 1.0 : (isDark ? 0.18 : 0.14))

            future.setFill()
            path.fill()

            // Repaint just the part left of the now line in the paler tone.
            if rect.minX < nowX {
                ctx.saveGState()
                path.addClip()
                ctx.clip(to: CGRect(x: rect.minX, y: rect.minY,
                                    width: min(nowX, rect.maxX) - rect.minX,
                                    height: rect.height))
                past.setFill()
                ctx.fill(rect)
                ctx.restoreGState()
            }

            // Outline, so neighbouring blocks stay distinct against the bar.
            // It fades at the now line too, matching the fill.
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                       xRadius: radius, yRadius: radius)
            outline.lineWidth = 1
            let inkFuture = NSColor.black.withAlphaComponent(0.6)
            let inkPast = NSColor.black.withAlphaComponent(0.25)

            if rect.minX < nowX {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: rect.minX - 1, y: rect.minY - 1,
                                    width: min(nowX, rect.maxX) - rect.minX + 1,
                                    height: rect.height + 2))
                inkPast.setStroke()
                outline.stroke()
                ctx.restoreGState()
            }
            if rect.maxX > nowX {
                let from = max(nowX, rect.minX)
                ctx.saveGState()
                ctx.clip(to: CGRect(x: from, y: rect.minY - 1,
                                    width: rect.maxX - from + 1, height: rect.height + 2))
                inkFuture.setStroke()
                outline.stroke()
                ctx.restoreGState()
            }
        }

        // --- Now line, drawn last so it stays on top ---
        // A faint halo either side lifts it off the coloured blocks; without it
        // the red can disappear against a warm-toned capsule.
        let lineWidth = Config.nowLineWidth
        let centre = round(nowX)
        (isDark ? NSColor.black : NSColor.white).withAlphaComponent(0.5).setFill()
        ctx.fill(CGRect(x: centre - lineWidth / 2 - 1, y: strip.minY,
                        width: lineWidth + 2, height: strip.height))
        NSColor.systemRed.setFill()
        ctx.fill(CGRect(x: centre - lineWidth / 2, y: strip.minY,
                        width: lineWidth, height: strip.height))

        ctx.restoreGState()
    }

    // MARK: - Text

    /// The menu bar's own font, optionally bolded for the final countdown.
    private static func labelFont(bold: Bool) -> NSFont {
        let base = NSFont.menuBarFont(ofSize: Config.titleFontSize)
        return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }

    private static func attributes(_ color: NSColor, _ alignment: NSTextAlignment,
                                   bold: Bool = false) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        return [
            .font: labelFont(bold: bold),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
    }

    /// Measured in the same weight it will be drawn in — bold is wider, and the
    /// gutter is sized from this, so a mismatch would clip the name.
    static func width(of s: String, bold: Bool = false) -> CGFloat {
        ceil(NSAttributedString(string: s, attributes: attributes(.black, .left, bold: bold))
                .size().width) + 1
    }

    /// Draws a pre-built label, vertically centred. Alignment and colour come
    /// from the string's own attributes.
    private func draw(_ text: NSAttributedString, in rect: CGRect) {
        guard rect.width > 2 else { return }
        let h = text.size().height
        text.draw(with: CGRect(x: rect.minX, y: rect.midY - h / 2,
                               width: rect.width, height: h),
                  options: [.usesLineFragmentOrigin])
    }

    /// Plain single-weight label, used for the error message.
    private func drawLabel(_ s: String, in rect: CGRect, color: NSColor,
                           alignment: NSTextAlignment, bold: Bool = false) {
        guard rect.width > 2 else { return }
        let attributed = NSAttributedString(string: s,
                                            attributes: Self.attributes(color, alignment, bold: bold))
        let h = attributed.size().height
        attributed.draw(with: CGRect(x: rect.minX, y: rect.midY - h / 2,
                                     width: rect.width, height: h),
                        options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
    }

    /// "1h05", "1h", "12m", "45s" — compact enough for the menu bar.
    /// A feed can say anything, and `Int(_: Double)` traps rather than saturating,
    /// so the clamp happens in `Double` before the conversion. Ten years is well
    /// past anything a countdown can usefully say.
    private static let longestLabelledSpan: TimeInterval = 315_360_000

    static func format(_ seconds: TimeInterval) -> String {
        // NaN survives min/max, so it's refused outright rather than clamped.
        guard seconds.isFinite else { return "0s" }
        // Round up, so it only reads 0 once the block has actually ended.
        let bounded = min(max(seconds.rounded(.up), 0), longestLabelledSpan)
        let total = Int(bounded)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? String(format: "%ldh%02ld", hours, minutes) : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}

// MARK: - Colour helpers

extension CalEvent {
    /// The block's colour, if a keyword rule gave it one.
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

}
