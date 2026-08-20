import AppKit
import UniformTypeIdentifiers

// MARK: - Configuration

enum Config {
    /// Example of what the feed-mode field accepts. Shown as placeholder text
    /// only — there is no calendar baked into the app.
    static let examplePlaceholder =
        "https://calendar.google.com/calendar/u/0/embed?src=you@gmail.com&ctz=Europe/London"

    private static let calendarKey = "calendarURL"

    /// The calendar link the user entered, if any.
    static var calendarInput: String? {
        UserDefaults.standard.string(forKey: calendarKey)
            ?? UserDefaults.standard.string(forKey: "icsURL")   // legacy key
    }

    static var hasCalendarInput: Bool { calendarInput != nil }

    /// The resolved iCal feed used in .ics mode, if one is configured.
    static var icsURL: String? {
        guard let input = calendarInput else { return nil }
        return CalendarSource.toICS(input)
    }

    static func setCalendar(_ input: String?) {
        let d = UserDefaults.standard
        d.removeObject(forKey: "icsURL")
        if let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            d.set(input.trimmingCharacters(in: .whitespacesAndNewlines), forKey: calendarKey)
        } else {
            d.removeObject(forKey: calendarKey)
        }
    }

    // MARK: Saved calendars (feed mode)

    /// A named calendar link, so several can be kept and switched between.
    struct CalendarProfile {
        var name: String
        var link: String
    }

    private static let profilesKey = "calendarProfiles"
    private static let activeProfileKey = "activeCalendarProfile"

    static var profiles: [CalendarProfile] {
        let raw = UserDefaults.standard.array(forKey: profilesKey) as? [[String: String]] ?? []
        return raw.compactMap {
            guard let name = $0["name"], let link = $0["link"] else { return nil }
            return CalendarProfile(name: name, link: link)
        }
    }

    static func setProfiles(_ list: [CalendarProfile]) {
        UserDefaults.standard.set(list.map { ["name": $0.name, "link": $0.link] }, forKey: profilesKey)
    }

    /// Which saved calendar is in use, if the current link came from one.
    static var activeProfileName: String? {
        UserDefaults.standard.string(forKey: activeProfileKey)
    }

    /// What to call the current calendar in the menu.
    static var calendarDisplayName: String? {
        if let name = activeProfileName { return name }
        guard let input = calendarInput else { return nil }
        return CalendarSource.label(for: input)
    }

    static func activate(_ profile: CalendarProfile) {
        setCalendar(profile.link)
        UserDefaults.standard.set(profile.name, forKey: activeProfileKey)
    }

    /// Adds (or updates, if the name is reused) and switches to it.
    static func addProfile(name: String, link: String) {
        var list = profiles.filter { $0.name != name }
        list.append(CalendarProfile(name: name, link: link))
        setProfiles(list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        activate(CalendarProfile(name: name, link: link))
    }

    static func renameProfile(_ old: String, to newName: String) {
        setProfiles(profiles.map {
            $0.name == old ? CalendarProfile(name: newName, link: $0.link) : $0
        })
        if activeProfileName == old {
            UserDefaults.standard.set(newName, forKey: activeProfileKey)
        }
    }

    /// Removes a saved calendar, moving to another one if the active was removed.
    static func removeProfile(named name: String) {
        let remaining = profiles.filter { $0.name != name }
        setProfiles(remaining)
        guard activeProfileName == name else { return }
        UserDefaults.standard.removeObject(forKey: activeProfileKey)
        if let next = remaining.first {
            activate(next)
        } else {
            setCalendar(nil)
        }
    }

    /// A link saved before profiles existed becomes a profile, so nothing is
    /// silently lost and it shows up in the list like any other.
    static func adoptLegacyCalendarIfNeeded() {
        guard profiles.isEmpty, let input = calendarInput else { return }
        addProfile(name: CalendarSource.label(for: input), link: input)
    }

    // MARK: Appearance

    // Factory settings, and what "Restore Defaults" puts back.
    static let defaultWindowMinutes = 120.0   // ± 1 hour
    static let defaultTimelineWidth = 250.0

    /// Total visible span in minutes, centred on now (120 = 1 h each side).
    static var windowMinutes: Double {
        let v = UserDefaults.standard.double(forKey: "windowMinutes")
        return v > 0 ? v : defaultWindowMinutes
    }

    static func setWindowMinutes(_ m: Double) {
        UserDefaults.standard.set(m, forKey: "windowMinutes")
    }

    /// Width of the timeline itself, in points. The gutters are sized to their
    /// text, so the status item's total is this plus both labels.
    static var timelineWidth: CGFloat {
        let v = UserDefaults.standard.double(forKey: "timelineWidth")
        return v > 0 ? CGFloat(min(max(v, 50), 900)) : CGFloat(defaultTimelineWidth)
    }

    static func setTimelineWidth(_ w: Double) {
        UserDefaults.standard.set(w, forKey: "timelineWidth")
    }

    /// Selectable widths: 100 pt up to 450 pt, in 50 pt steps.
    static let timelineWidthChoices: [Double] = Array(stride(from: 100.0, through: 450.0, by: 50.0))

    /// How wide one minute is at the current settings — what actually decides
    /// how big a block looks.
    static var pointsPerMinute: Double {
        Double(timelineWidth) / max(windowMinutes, 1)
    }

    // MARK: Labels

    /// What the two gutters show. All four are toggled from the menu.
    static var showNowName: Bool { flag("showNowName") }
    static var showNowTimeLeft: Bool { flag("showNowTimeLeft") }
    static var showNextName: Bool { flag("showNextName") }
    static var showNextDuration: Bool { flag("showNextDuration") }

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func toggle(_ key: String) {
        UserDefaults.standard.set(!flag(key), forKey: key)
    }

    private static let labelKeys = ["showNowName", "showNowTimeLeft", "showNextName", "showNextDuration"]

    /// True when range, width and all four labels are already at factory settings,
    /// which is when "Restore Defaults" has nothing to do.
    static var isAppearanceDefault: Bool {
        abs(windowMinutes - defaultWindowMinutes) < 0.01
            && abs(Double(timelineWidth) - defaultTimelineWidth) < 0.01
            && abs(Double(maxLabelWidth) - defaultMaxLabelWidth) < 0.01
            && labelKeys.allSatisfy { flag($0) }
    }

    /// Back to ± 1 hour, 250 pt timeline, 360 pt labels, every label switched on.
    static func restoreAppearanceDefaults() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "windowMinutes")
        d.removeObject(forKey: "timelineWidth")
        d.removeObject(forKey: "maxLabelWidth")
        for key in labelKeys { d.removeObject(forKey: key) }
    }

    /// Ceiling on each gutter, so one absurdly long event title can't swallow
    /// the whole menu bar. Labels still size themselves to their content; this
    /// is only the point at which the name starts being shortened.
    static let defaultMaxLabelWidth = 360.0

    static var maxLabelWidth: CGFloat {
        let v = UserDefaults.standard.double(forKey: "maxLabelWidth")
        return v > 0 ? CGFloat(v) : CGFloat(defaultMaxLabelWidth)
    }

    static func setMaxLabelWidth(_ w: Double) {
        UserDefaults.standard.set(w, forKey: "maxLabelWidth")
    }

    static let maxLabelWidthChoices: [Double] = [100, 140, 180, 240, 300, 360, 480]

    /// Visual separation between neighbouring blocks, in points. Cosmetic only —
    /// it never changes an event's time or position.
    static var blockGap: CGFloat {
        let v = UserDefaults.standard.double(forKey: "blockGap")
        return v > 0 ? CGFloat(v) : 1.0
    }

    /// How many seconds before a block ends the left label turns red and bold.
    static var urgentSeconds: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "urgentSeconds")
        return v > 0 ? v : 120
    }

    /// The block that marks the start of your day in the dropdown. Everything
    /// from this block to the next one is listed, so a night shift reads as one
    /// stretch instead of being cut at midnight.
    static var dayAnchorKeyword: String {
        let v = UserDefaults.standard.string(forKey: "dayAnchorKeyword")
        return (v?.isEmpty == false) ? v! : "sleep"
    }

    /// Colour for a block that matched no keyword rule and carries no colour of
    /// its own. Deliberately neutral — an unclassified event mustn't look like a
    /// category, which is exactly what a green default did.
    static var unmatchedColour: NSColor {
        if let hex = UserDefaults.standard.string(forKey: "unmatchedColor"),
           let colour = NSColor(hexString: hex) {
            return colour
        }
        return NSColor(hexString: "#8E8E93") ?? .systemGray
    }

    /// Thickness of the red "now" line, in points.
    static var nowLineWidth: CGFloat {
        let v = UserDefaults.standard.double(forKey: "nowLineWidth")
        return v > 0 ? CGFloat(v) : 4
    }

    /// Corner radius of a block. 0 (the default) means capsule ends — a radius
    /// of half the block's height.
    static var blockCornerRadius: CGFloat {
        CGFloat(max(UserDefaults.standard.double(forKey: "blockCornerRadius"), 0))
    }

    /// The size macOS uses for menu bar labels — matches other menu bar widgets.
    static var menuBarFontSize: CGFloat { NSFont.menuBarFont(ofSize: 0).pointSize }

    /// Point size of the event titles inside blocks.
    static var titleFontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: "titleFontSize")
        return v > 0 ? CGFloat(v) : menuBarFontSize
    }


    /// Synthetic 15-minute test blocks instead of a real calendar.
    /// On by default until a real calendar is set up, so a fresh install shows
    /// something working straight away.
    static var demoMode: Bool {
        if let explicit = UserDefaults.standard.object(forKey: "demoMode") as? Bool {
            return explicit
        }
        return !hasCalendarInput
    }

    static func setDemoMode(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "demoMode")
    }

    /// Filled blocks, like a calendar's day view (vs. translucent tint).
    static var solidBlocks: Bool {
        UserDefaults.standard.object(forKey: "solidBlocks") as? Bool ?? true
    }

    /// Event times use the `ctz=` time zone from the calendar link when
    /// present, otherwise the Mac's own time zone.
    static var displayTimeZone: TimeZone {
        guard let input = calendarInput else { return .current }
        return CalendarSource.timeZone(from: input) ?? .current
    }

    // MARK: Debug time

    /// Seconds added to the real clock. 0 means "use the real time".
    static var debugOffset: TimeInterval {
        UserDefaults.standard.double(forKey: "debugOffset")
    }

    static var isSimulating: Bool { debugOffset != 0 }

    /// Stored as an offset rather than an absolute date, so the simulated clock
    /// keeps running instead of standing still.
    static func setDebugTime(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSinceNow, forKey: "debugOffset")
    }

    static func clearDebugTime() {
        UserDefaults.standard.removeObject(forKey: "debugOffset")
    }

    static let redrawInterval: TimeInterval = 1       // slide the strip / tick the countdown
    static let refetchInterval: TimeInterval = 300    // re-read the calendar
}

// MARK: - Clock

/// Everything that asks "what time is it?" goes through here, so the whole app
/// can be moved to a different moment for testing. The offset is applied to the
/// real clock rather than freezing it, so a simulated day still advances —
/// blocks keep sliding and countdowns keep ticking.
enum Clock {
    static var now: Date { Date().addingTimeInterval(Config.debugOffset) }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let timeline = TimelineView()
    private let menu = NSMenu()
    private var redrawTimer: Timer?
    private var fetchTimer: Timer?
    private var lastFetch: Date?
    /// What the dropdown lists — one sleep-to-sleep cycle, not one calendar day.
    private var menuEvents: [CalEvent] = []

    /// The alert rows whose titles depend on the settings below them. Held onto
    /// so a toggle can update them without closing and rebuilding the menu.
    private weak var alertsRootItem: NSMenuItem?
    private weak var alertLeadItem: NSMenuItem?
    private weak var alertSoundItem: NSMenuItem?
    private weak var alertVoiceItem: NSMenuItem?
    private weak var alertCategoryItem: NSMenuItem?
    private weak var alertTestItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Width is recomputed from the label text on every tick — see resize().
        statusItem = NSStatusBar.system.statusItem(withLength: Config.timelineWidth)

        guard let button = statusItem.button else { return }
        timeline.frame = button.bounds
        timeline.autoresizingMask = [.width, .height]
        button.addSubview(timeline)

        menu.delegate = self
        // We enable/disable items ourselves, so AppKit doesn't grey out the
        // event rows (which would wash out their colour swatches).
        menu.autoenablesItems = false
        statusItem.menu = menu

        redrawTimer = Timer.scheduledTimer(withTimeInterval: Config.redrawInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.resize()
            self.timeline.needsDisplay = true
            // Same tick as the redraw: the clock is already being read, and a
            // second's resolution is plenty for a warning measured in minutes.
            Alerts.check(self.menuEvents, now: Clock.now)
        }
        fetchTimer = Timer.scheduledTimer(withTimeInterval: Config.refetchInterval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
        RunLoop.main.add(redrawTimer!, forMode: .common)
        RunLoop.main.add(fetchTimer!, forMode: .common)

        installEditMenu()
        Config.adoptLegacyCalendarIfNeeded()
        KeywordRules.seedSampleRulesIfFirstRun()
        LoginItem.syncOnLaunch()

        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.fetch()
            // Cheap insurance: a voice or sound may have been added while asleep.
            Alerts.refreshVoices()
            Alerts.refreshSounds()
        }

        fetch()
    }

    /// A menu bar app has no menu bar of its own, so the standard editing
    /// shortcuts have nothing to route through and ⌘V does nothing in a text
    /// field. Installing an Edit menu — never displayed anywhere — restores
    /// cut, copy, paste, select all and undo in every dialog.
    private func installEditMenu() {
        let mainMenu = NSMenu()

        // macOS expects the first item to be the application menu.
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        mainMenu.addItem(editItem)

        // Undo and redo are UndoManager actions with no Swift method to point
        // #selector at, so those two stay as string selectors.
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        // Named on NSText, but dispatched down the responder chain to whichever
        // field is focused.
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    /// Grow or shrink the status item so both event names fit without
    /// truncating. Only touched when it actually changes, since resizing a
    /// status item forces a menu bar relayout.
    private func resize() {
        let wanted = timeline.desiredWidth()
        if abs(statusItem.length - wanted) > 1 {
            statusItem.length = wanted
        }
    }

    // MARK: - Fetching

    private func fetch() {
        if Config.demoMode {
            loadDemoEvents()
        } else {
            fetchFromICS()
        }
    }

    /// What to fetch. Wider than today, because the dropdown lists a whole
    /// sleep-to-sleep cycle and that can reach well into tomorrow — or start
    /// yesterday morning, on a night shift.
    private func dayBounds() -> (dayStart: Date, dayEnd: Date, from: Date, to: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Config.displayTimeZone
        let now = Clock.now
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let from = cal.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart.addingTimeInterval(-86400)
        let to = cal.date(byAdding: .day, value: 2, to: dayStart) ?? dayEnd.addingTimeInterval(86400)
        return (dayStart, dayEnd, from, to)
    }

    /// The dropdown's list: everything from the anchor block that opened the
    /// current cycle through to the next one, so you see the shape of the whole
    /// day in one go. Falls back to the calendar day when no anchor exists.
    private func cycleEvents(_ all: [CalEvent], now: Date) -> [CalEvent] {
        let bounds = dayBounds()
        let sorted = all.sorted { $0.start < $1.start }

        /// Used whenever there's no anchor to work from: today so far, plus a
        /// rolling 24 hours. Never "today only" — that hides everything after
        /// midnight even while the strip is already showing it.
        func rolling() -> [CalEvent] {
            let ahead = now.addingTimeInterval(24 * 3600)
            return sorted.filter { $0.end > bounds.dayStart && $0.start <= ahead }
        }

        let anchors = sorted.filter {
            KeywordRules.title($0.title, contains: Config.dayAnchorKeyword)
        }
        guard !anchors.isEmpty else { return rolling() }

        // A sleep split into back-to-back chunks is still one sleep, so merge
        // adjacent anchor blocks into runs before picking the boundaries.
        var runs: [(start: Date, end: Date)] = []
        for anchor in anchors {
            if let last = runs.last, anchor.start <= last.end.addingTimeInterval(1800) {
                runs[runs.count - 1].end = max(last.end, anchor.end)
            } else {
                runs.append((anchor.start, anchor.end))
            }
        }

        // The run that opened the cycle we're in. If the day's anchor hasn't
        // happened yet, roll instead of starting the list in the future.
        guard let opener = runs.last(where: { $0.start <= now }) else { return rolling() }
        let closer = runs.first { $0.start > opener.start }
        let cutoff = closer?.start ?? bounds.to

        return sorted.filter { $0.start >= opener.start && $0.start <= cutoff }
    }

    // MARK: Demo blocks

    private func loadDemoEvents() {
        let bounds = dayBounds()
        let all = KeywordRules.apply(to: DemoData.events(around: Clock.now,
                                                         timeZone: Config.displayTimeZone))
        timeline.errorMessage = nil
        timeline.events = all.filter { $0.intersects(bounds.from, bounds.to) }
        menuEvents = cycleEvents(all, now: Clock.now)
        lastFetch = Date()
    }

    // MARK: The calendar feed

    private func fetchFromICS() {
        guard let ics = Config.icsURL, let url = URL(string: ics) else {
            showFailure("No calendar yet — click to set one up")
            return
        }

        // A local .ics file (handy for testing) — read it directly.
        if url.isFileURL {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard text.contains("BEGIN:VCALENDAR") else {
                    showFailure("That file isn't iCalendar")
                    return
                }
                timeline.errorMessage = nil
                applyICS(text)
            } catch {
                showFailure("Can't read file: \(error.localizedDescription)")
            }
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.showFailure("Calendar unreachable (\(error.localizedDescription))")
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    self.showFailure("Calendar HTTP \(http.statusCode) — is the feed public?")
                    return
                }
                guard let data, let text = String(data: data, encoding: .utf8),
                      text.contains("BEGIN:VCALENDAR") else {
                    self.showFailure("Feed is not valid iCalendar")
                    return
                }
                self.timeline.errorMessage = nil
                self.applyICS(text)
            }
        }.resume()
    }

    private func applyICS(_ ics: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Config.displayTimeZone
        let today = Clock.now
        // Yesterday through the day after tomorrow, so the dropdown's
        // sleep-to-sleep cycle can always find both of its anchors.
        let days = [-1, 0, 1, 2].compactMap { cal.date(byAdding: .day, value: $0, to: today) }

        let all = KeywordRules.apply(to: ICS.events(from: ics, days: days, calendar: cal))
        let bounds = dayBounds()

        timeline.events = all.filter { $0.intersects(bounds.from, bounds.to) }
        menuEvents = cycleEvents(all, now: Clock.now)
        lastFetch = Date()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        // Zero-padded hours, so every row's time column is the same width.
        df.dateFormat = "hh:mm a"
        df.timeZone = Config.displayTimeZone

        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .full
        dayFormatter.timeZone = Config.displayTimeZone
        addInfo(dayFormatter.string(from: Clock.now)
                    + (Config.isSimulating ? "   ·   simulated" : ""), to: menu)

        // --- Debug time ---
        if Config.isSimulating {
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX")
            stamp.dateFormat = "MMM d, h:mm:ss a"
            stamp.timeZone = Config.displayTimeZone
            let item = add("⏱ Debug Time: \(stamp.string(from: Clock.now))…",
                           #selector(pickDebugTime), to: menu)
            item.toolTip = "Pretending it's this moment. The simulated clock keeps running."
            add("Reset to Current Time", #selector(resetDebugTime), to: menu)
        } else {
            let item = add("Debug Time…", #selector(pickDebugTime), to: menu)
            item.toolTip = "Jump the app to any date and time to see how the strip looks then"
        }

        menu.addItem(.separator())

        // --- The day's blocks, one anchor-to-anchor cycle ---
        if let msg = timeline.errorMessage {
            addInfo(msg, to: menu)
        } else if menuEvents.isEmpty {
            addInfo("Nothing scheduled", to: menu)
        } else {
            let now = Clock.now
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = Config.displayTimeZone
            let dayBreak = DateFormatter()
            dayBreak.dateFormat = "EEEE, MMMM d"
            dayBreak.timeZone = Config.displayTimeZone

            // The cycle spans two dates, so mark where one day becomes the next
            // — otherwise today's 4:30 AM and tomorrow's look identical.
            var lastDay: Date?
            let today = cal.startOfDay(for: now)
            var shown = 0
            // Columns sized once, from the whole list.
            let layout = Self.rowLayout(menuEvents, df)

            for ev in menuEvents {
                if shown >= 60 {
                    addInfo("… and \(menuEvents.count - shown) more", to: menu)
                    break
                }
                let day = cal.startOfDay(for: ev.start)
                if day != lastDay, lastDay != nil || day != today {
                    addInfo(dayBreak.string(from: day), to: menu)
                }
                lastDay = day

                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.attributedTitle = Self.eventRow(
                    ev, now: now, formatter: df, layout: layout,
                    overlaps: Self.overlapCount(ev, in: menuEvents))
                menu.addItem(item)
                shown += 1
            }
        }

        menu.addItem(.separator())

        // --- Appearance ---
        let range = NSMenuItem(title: "Time Range", action: nil, keyEquivalent: "")
        range.submenu = timeRangeMenu()
        menu.addItem(range)

        let width = NSMenuItem(title: "Timeline Width", action: nil, keyEquivalent: "")
        width.submenu = timelineWidthMenu()
        menu.addItem(width)

        let labels = NSMenuItem(title: "Labels", action: nil, keyEquivalent: "")
        labels.submenu = labelsMenu()
        menu.addItem(labels)

        let length = NSMenuItem(title: "Label Length", action: nil, keyEquivalent: "")
        length.submenu = labelLengthMenu()
        menu.addItem(length)

        let keywords = NSMenuItem(title: "Keyword Colors", action: nil, keyEquivalent: "")
        keywords.submenu = keywordColoursMenu()
        menu.addItem(keywords)

        let restore = add("Restore Defaults", #selector(restoreDefaults), to: menu)
        restore.isEnabled = !Config.isAppearanceDefault
        restore.toolTip = restore.isEnabled
            ? "Back to ± 1 hour, a 250 pt timeline, 360 pt labels and all labels on"
            : "Already at the default settings"

        menu.addItem(.separator())

        // --- Which source is live ---
        if Config.demoMode {
            addInfo("Calendar: demo blocks (test data)", to: menu)
        } else if let name = Config.calendarDisplayName {
            addInfo("Calendar: \(name)", to: menu)
        } else {
            addInfo("No calendar set up yet", to: menu)
        }

        // Demo toggle stays reachable in every state.
        let demoItem = add("Demo Mode", #selector(toggleDemoMode), to: menu)
        demoItem.state = Config.demoMode ? .on : .off
        demoItem.toolTip = "Synthetic 15-minute blocks, to check the strip moves correctly"

        if Config.profiles.isEmpty {
            add("Add Calendar…", #selector(addCalendarProfile), to: menu)
        } else {
            let saved = NSMenuItem(title: "Saved Calendars", action: nil, keyEquivalent: "")
            saved.submenu = savedCalendarsMenu()
            // Ticked when a saved calendar is what's actually being read, so it
            // reads as the counterpart to Demo Mode above it.
            saved.state = (!Config.demoMode && Config.hasCalendarInput) ? .on : .off
            menu.addItem(saved)
        }

        let alerts = NSMenuItem(title: Alerts.summary, action: nil, keyEquivalent: "")
        alertsRootItem = alerts
        alerts.submenu = alertsMenu()
        // Ticked only when an alert could actually happen: a lead time, and at
        // least one of sound or speech.
        alerts.state = Alerts.isEnabled ? .on : .off
        alerts.toolTip = Alerts.isEnabled
            ? "\(Alerts.leadSummary) before a block starts"
            : "Off — choose when to be told, then how"
        menu.addItem(alerts)

        menu.addItem(.separator())

        // --- Reading the feed ---
        // Kept next to the calendar it refreshes, rather than up with the day.
        if let lastFetch {
            df.dateFormat = "h:mm:ss a"
            addInfo("Updated \(df.string(from: lastFetch))", to: menu)
        }
        add("Refresh Now", #selector(refreshNow), to: menu, key: "r")

        // --- Launching at login ---
        // Its own block: nothing to do with refreshing the feed above it.
        menu.addItem(.separator())
        let startup = NSMenuItem(title: LoginItem.menuTitle, action: nil, keyEquivalent: "")
        startup.submenu = startupMenu()
        // Ticked whenever it will launch at login, delay or not, so the state
        // reads at a glance the way Demo Mode and Saved Calendars do.
        startup.state = LoginItem.isEnabled ? .on : .off
        startup.toolTip = LoginItem.isInApplications
            ? "Launch when you log in, as a LaunchAgent"
            : "Points at the app where it is now — moving the folder will break it"
        menu.addItem(startup)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// A heads-up before a block starts. Deliberately staged: the lead time
    /// comes first, then how it announces itself, and only then which categories
    /// it applies to — each step greyed out until the one above it is answered.
    private func alertsMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        // --- 1. when ---
        let when = NSMenuItem(title: "Alert Me Before: \(Alerts.leadSummary)",
                              action: nil, keyEquivalent: "")
        when.submenu = alertLeadMenu()
        alertLeadItem = when
        sub.addItem(when)

        // --- 2. how ---
        sub.addItem(.separator())
        let sound = NSMenuItem(
            title: "Alert Sound: \(Alerts.playsSound ? Alerts.soundName : "Off")",
            action: nil, keyEquivalent: "")
        sound.submenu = alertSoundMenu()
        alertSoundItem = sound
        sound.isEnabled = Alerts.hasLead
        sound.toolTip = Alerts.hasLead ? "Choosing a sound plays it" : "Choose a lead time first"
        sub.addItem(sound)

        let voice = NSMenuItem(title: "Voice Sound: \(Alerts.voiceLabel)",
                               action: nil, keyEquivalent: "")
        voice.submenu = alertVoiceMenu()
        alertVoiceItem = voice
        voice.isEnabled = Alerts.hasLead
        voice.toolTip = Alerts.hasLead
            ? "Says “\(Alerts.leadPhrase(Alerts.leads.min() ?? 60)) before Focus Work”"
            : "Choose a lead time first"
        sub.addItem(voice)

        // --- 3. which blocks ---
        sub.addItem(.separator())
        let categories = NSMenuItem(title: Alerts.isEveryCategory
                                        ? "Categories: all"
                                        : "Categories: \(Alerts.selectedCategories.count) selected",
                                    action: nil, keyEquivalent: "")
        categories.submenu = alertCategoryMenu()
        alertCategoryItem = categories
        categories.isEnabled = Alerts.isEnabled
        categories.toolTip = Alerts.isEnabled
            ? "Only blocks in these categories are announced"
            : "Choose a lead time and a sound or voice first"
        sub.addItem(categories)

        sub.addItem(.separator())
        let test = NSMenuItem(title: "Test Alert Now", action: #selector(testAlert), keyEquivalent: "")
        test.target = self
        test.isEnabled = Alerts.isEnabled
        alertTestItem = test
        sub.addItem(test)
        return sub
    }

    /// Repaints the rows that summarise the alert settings. Called after a toggle
    /// that deliberately left the menu open, so what's on screen keeps up without
    /// the menu being rebuilt underneath the pointer.
    private func refreshAlertTitles() {
        alertsRootItem?.title = Alerts.summary
        alertsRootItem?.state = Alerts.isEnabled ? .on : .off
        alertLeadItem?.title = "Alert Me Before: \(Alerts.leadSummary)"

        alertSoundItem?.title = "Alert Sound: \(Alerts.playsSound ? Alerts.soundName : "Off")"
        alertSoundItem?.isEnabled = Alerts.hasLead
        alertVoiceItem?.title = "Voice Sound: \(Alerts.voiceLabel)"
        alertVoiceItem?.isEnabled = Alerts.hasLead

        alertCategoryItem?.title = Alerts.isEveryCategory
            ? "Categories: all"
            : "Categories: \(Alerts.selectedCategories.count) selected"
        alertCategoryItem?.isEnabled = Alerts.isEnabled
        alertTestItem?.isEnabled = Alerts.isEnabled
    }

    /// A row that toggles without dismissing the menu.
    private func toggleRow(_ title: String, isOn: @escaping () -> Bool,
                           toolTip: String? = nil, toggle: @escaping () -> Void) -> NSMenuItem {
        let view = ToggleRowView(title: title, isOn: isOn(), toolTip: toolTip)
        view.isOnNow = isOn
        view.onToggle = toggle
        view.onChanged = { [weak self] in self?.refreshAlertTitles() }
        let item = NSMenuItem()
        item.view = view
        return item
    }

    /// How long before a block starts — as many as you like. Each row is a
    /// toggle, so ten minutes to wrap up and one minute to actually move can both
    /// be on; they share the one sound or voice, and only the number spoken
    /// changes.
    private func alertLeadMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        // Every row here stays open when clicked — arming three lead times
        // shouldn't mean three trips through the menu.
        sub.addItem(toggleRow("Off", isOn: { Alerts.leads.isEmpty },
                              toolTip: "Nothing will sound") {
            Alerts.clearLeads()
        })
        sub.addItem(.separator())

        let presets = Alerts.leadPresets.map { $0.seconds }
        for preset in Alerts.leadPresets {
            let seconds = preset.seconds
            sub.addItem(toggleRow(preset.title, isOn: { Alerts.leads.contains(seconds) }) {
                Alerts.toggleLead(seconds)
                if Alerts.hasLead { Alerts.requestNotificationPermissionIfNeeded() }
            })
        }

        // Whatever you've added yourself sits alongside the presets, rather than
        // hidden behind the row that created it.
        let customs = Alerts.leads.filter { !presets.contains($0) }
        if !customs.isEmpty {
            sub.addItem(.separator())
            for seconds in customs {
                sub.addItem(toggleRow("\(Alerts.leadPhrase(seconds)) before",
                                      isOn: { Alerts.leads.contains(seconds) },
                                      toolTip: "Your own lead time — click to remove it") {
                    Alerts.toggleLead(seconds)
                })
            }
        }

        sub.addItem(.separator())
        add("Add Custom…", #selector(pickCustomAlertLead), to: sub)
        addNote("Click as many as you like — the menu stays open", to: sub)
        return sub
    }

    /// Off, then every sound macOS ships, then anything you've added yourself.
    /// Picking one plays it, so you can hear it before committing.
    private func alertSoundMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        let off = NSMenuItem(title: "Off", action: #selector(chooseAlertSound(_:)), keyEquivalent: "")
        off.target = self
        off.representedObject = ""
        off.state = Alerts.playsSound ? .off : .on
        sub.addItem(off)
        sub.addItem(.separator())

        let all = Alerts.sounds
        let systemSounds = all.filter { !Alerts.isCustomSound($0) }
        let yours = all.filter { Alerts.isCustomSound($0) }

        for name in systemSounds {
            let item = NSMenuItem(title: name, action: #selector(chooseAlertSound(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = (Alerts.playsSound && Alerts.soundName == name) ? .on : .off
            sub.addItem(item)
        }

        if !yours.isEmpty {
            sub.addItem(.separator())
            for name in yours {
                let item = NSMenuItem(title: name, action: #selector(chooseAlertSound(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = name
                item.state = (Alerts.playsSound && Alerts.soundName == name) ? .on : .off
                item.toolTip = "Your own sound, from ~/Library/Sounds"
                sub.addItem(item)
            }
        }

        sub.addItem(.separator())
        add("Custom Sound…", #selector(importAlertSound), to: sub)
        addNote("macOS ships \(systemSounds.count); add your own for more", to: sub)
        return sub
    }

    /// Off, the three voices every Mac has, then any Enhanced or Premium voice
    /// the user has downloaded — those are the natural-sounding ones, and they
    /// only exist if they've been fetched, so they're discovered rather than
    /// assumed. Choosing any of them silences the alert sound: one alert, one
    /// way of announcing itself.
    ///
    /// Siri isn't here: macOS won't let an app use those voices, directly or by
    /// inheriting the System Voice setting.
    private func alertVoiceMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        let off = NSMenuItem(title: "Off", action: #selector(chooseAlertVoice(_:)), keyEquivalent: "")
        off.target = self
        off.representedObject = ""
        off.state = Alerts.speaks ? .off : .on
        sub.addItem(off)
        sub.addItem(.separator())

        for option in Alerts.voiceOptions {
            guard let name = Alerts.voiceName(for: option) else {
                let missing = NSMenuItem(title: "\(option.label) — not installed",
                                         action: nil, keyEquivalent: "")
                missing.isEnabled = false
                sub.addItem(missing)
                continue
            }
            let item = NSMenuItem(title: "\(option.label) — \(name)",
                                  action: #selector(chooseAlertVoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.key
            item.state = (Alerts.speaks && Alerts.voiceKey == option.key) ? .on : .off
            sub.addItem(item)
        }

        // Premium voices get their own submenu, listed whether or not they're
        // installed: a voice nobody knows exists is a voice nobody downloads.
        sub.addItem(.separator())
        let premium = NSMenuItem(title: "Premium Voices", action: nil, keyEquivalent: "")
        premium.submenu = premiumVoiceMenu()
        premium.toolTip = "Apple's neural voices — a free download, far more natural than the "
            + "voices that ship with macOS"
        sub.addItem(premium)

        // Anything Enhanced or Premium that's installed but not in that
        // catalogue, so nothing on this Mac is hidden.
        let others = Alerts.otherNaturalVoices
        if !others.isEmpty {
            sub.addItem(.separator())
            for voice in others {
                let item = NSMenuItem(title: voice.label, action: #selector(chooseAlertVoice(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = voice.key
                item.state = (Alerts.speaks && Alerts.voiceKey == voice.key) ? .on : .off
                sub.addItem(item)
            }
        }
        return sub
    }

    /// The Premium catalogue for American, British and Australian English.
    /// Installed voices are selectable; the rest say what they'd cost to
    /// download and open Manage Voices when clicked, since the point of listing
    /// them is that you can't choose what you don't know about.
    private func premiumVoiceMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        var lastAccent = ""
        for entry in Alerts.premiumCatalogue {
            if entry.accent != lastAccent {
                if !lastAccent.isEmpty { sub.addItem(.separator()) }
                let header = NSMenuItem(title: entry.accent, action: nil, keyEquivalent: "")
                header.isEnabled = false
                sub.addItem(header)
                lastAccent = entry.accent
            }

            if let installed = Alerts.installedPremium(entry) {
                let key = Alerts.key(for: installed)
                let item = NSMenuItem(title: "\(entry.name) — installed",
                                      action: #selector(chooseAlertVoice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = key
                item.state = (Alerts.speaks && Alerts.voiceKey == key) ? .on : .off
                item.toolTip = "Choosing it speaks a sample"
                sub.addItem(item)
            } else {
                let item = NSMenuItem(title: "\(entry.name) — download, \(entry.size)",
                                      action: #selector(openVoiceSettings), keyEquivalent: "")
                item.target = self
                item.toolTip = "Not on this Mac yet. Opens Manage Voices, where you can download "
                    + "\(entry.name) — it appears here once it's installed."
                sub.addItem(item)
            }
        }

        sub.addItem(.separator())
        add("Manage Voices…", #selector(openVoiceSettings), to: sub)
        addNote("Download in System Settings, then pick it here", to: sub)
        return sub
    }

    /// Which categories get announced. "All" is stored as an empty selection, so
    /// adding a category to your CSV doesn't quietly leave it out.
    private func alertCategoryMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        sub.addItem(toggleRow("All Categories", isOn: { Alerts.isEveryCategory }) {
            Alerts.selectAllCategories()
            Alerts.forgetAnnounced()
        })
        sub.addItem(.separator())

        var names = KeywordRules.categories.map { $0.name }
        names.append(Alerts.uncategorized)
        for name in names {
            sub.addItem(toggleRow(name, isOn: {
                Alerts.isEveryCategory || Alerts.selectedCategories.contains(name)
            }) {
                Alerts.toggleCategory(name)
                Alerts.forgetAnnounced()
            })
        }

        addNote("Click as many as you like — the menu stays open", to: sub)
        return sub
    }

    /// Off, on, or on after a wait. The wait keeps the app out of the crowd of
    /// things all starting at once when you log in.
    private func startupMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        let off = NSMenuItem(title: "Off", action: #selector(chooseStartup(_:)), keyEquivalent: "")
        off.target = self
        off.representedObject = -1
        off.state = LoginItem.isEnabled ? .off : .on
        sub.addItem(off)

        let on = NSMenuItem(title: "On", action: #selector(chooseStartup(_:)), keyEquivalent: "")
        on.target = self
        on.representedObject = 0
        on.state = (LoginItem.isEnabled && LoginItem.delay == 0) ? .on : .off
        on.toolTip = "Launch as soon as you log in"
        sub.addItem(on)

        let header = NSMenuItem(title: "Delay for:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        sub.addItem(header)

        for seconds in LoginItem.delayChoices {
            let item = NSMenuItem(title: "\(seconds) s",
                                  action: #selector(chooseStartup(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = (LoginItem.isEnabled && LoginItem.delay == seconds) ? .on : .off
            sub.addItem(item)
        }
        return sub
    }

    /// How much time is visible, as ± either side of now.
    private func timeRangeMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let presets: [(String, Double)] = [
            ("± 5 minutes", 10), ("± 10 minutes", 20), ("± 15 minutes", 30),
            ("± 30 minutes", 60), ("± 1 hour", 120), ("± 2 hours", 240)
        ]
        for (title, minutes) in presets {
            let item = NSMenuItem(title: title, action: #selector(chooseTimeRange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.state = abs(Config.windowMinutes - minutes) < 0.01 ? .on : .off
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let note = NSMenuItem(title: "A wider range shows more, at a smaller size",
                              action: nil, keyEquivalent: "")
        note.isEnabled = false
        sub.addItem(note)
        return sub
    }

    /// How much menu bar the timeline occupies, smallest to largest.
    private func timelineWidthMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let choices = Config.timelineWidthChoices

        for (index, width) in choices.enumerated() {
            var title = "\(Int(width)) pt"
            if index == 0 { title += "  —  smallest" }
            if index == choices.count - 1 { title += "  —  largest" }

            let item = NSMenuItem(title: title, action: #selector(chooseTimelineWidth(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = width
            item.state = abs(Double(Config.timelineWidth) - width) < 0.01 ? .on : .off
            let blockWidth = Int((width / max(Config.windowMinutes, 1)) * 15)
            item.toolTip = "A 15-minute block would be \(blockWidth) pt wide at the current time range"
            sub.addItem(item)
        }

        sub.addItem(.separator())
        let note = NSMenuItem(
            title: "Now: a 15-minute block is \(Int(Config.pointsPerMinute * 15)) pt wide",
            action: nil, keyEquivalent: "")
        note.isEnabled = false
        sub.addItem(note)
        return sub
    }

    /// Imported keyword → color rules, grouped by the CSV's category column.
    private func keywordColoursMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        func info(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
        }

        let rules = KeywordRules.rules

        /// The colour a block gets when nothing matches — worth showing either
        /// way, so grey on the strip is recognisable rather than a mystery.
        func addUncategorized() {
            let item = NSMenuItem(title: "Uncategorized  ·  no keyword match",
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.swatch(Config.unmatchedColour)
            item.toolTip = "Events that match no keyword and carry no colour of their own. "
                + "Change it with:  defaults write io.github.macos-menubar-rollingcalendar "
                + "unmatchedColor \"#RRGGBB\""
            sub.addItem(item)
        }

        if rules.isEmpty {
            info("No keyword colors imported")
            info("CSV columns: category, color, keyword")
            sub.addItem(.separator())
            addUncategorized()
        } else {
            let source = KeywordRules.sourceName ?? "a CSV"
            info("\(rules.count) keyword\(rules.count == 1 ? "" : "s") from \(source)")
            sub.addItem(.separator())
            for category in KeywordRules.categories {
                let title = category.name.isEmpty ? "(no category)" : category.name
                let item = NSMenuItem(title: "\(title)  ·  \(category.count)",
                                      action: nil, keyEquivalent: "")
                item.isEnabled = false
                if let color = NSColor(hexString: category.colorHex) {
                    item.image = Self.swatch(color)
                }
                item.toolTip = KeywordRules.rules
                    .filter { $0.category == category.name }
                    .map(\.keyword).joined(separator: ", ")
                sub.addItem(item)
            }
            sub.addItem(.separator())
            addUncategorized()
        }

        sub.addItem(.separator())
        let importItem = NSMenuItem(title: rules.isEmpty ? "Import CSV…" : "Import Another CSV…",
                                    action: #selector(importKeywordCSV), keyEquivalent: "")
        importItem.target = self
        sub.addItem(importItem)

        // A working set in one click, and the same rules saveable as a CSV to
        // edit — so nobody has to invent a colour scheme from nothing.
        let useSample = NSMenuItem(title: "Use Sample Colors",
                                   action: #selector(loadSampleKeywords), keyEquivalent: "")
        useSample.target = self
        useSample.toolTip = "Apply a ready-made set covering focus, meetings, health, "
            + "admin, personal and travel"
        sub.addItem(useSample)

        let saveSample = NSMenuItem(title: "Save Sample CSV…",
                                    action: #selector(saveSampleKeywordCSV), keyEquivalent: "")
        saveSample.target = self
        saveSample.toolTip = "Write the sample out as a CSV you can edit, then import"
        sub.addItem(saveSample)

        if !rules.isEmpty {
            let clear = NSMenuItem(title: "Clear Keyword Colors",
                                   action: #selector(clearKeywordCSV), keyEquivalent: "")
            clear.target = self
            sub.addItem(clear)
        }
        return sub
    }

    /// Saved calendar links, one per line, plus the housekeeping actions.
    private func savedCalendarsMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        // In Demo Mode the saved calendars aren't being read, so none is ticked.
        let active = Config.demoMode ? nil : Config.activeProfileName
        for profile in Config.profiles {
            let row = CalendarRowView(title: profile.name, isActive: profile.name == active)
            let name = profile.name
            row.onSelect = { [weak self] in self?.activateProfile(named: name) }
            row.onRename = { [weak self] in self?.renameProfile(named: name) }
            row.onRemove = { [weak self] in self?.confirmRemoveProfile(named: name) }

            let item = NSMenuItem()
            item.view = row
            item.toolTip = profile.link
            sub.addItem(item)
        }

        sub.addItem(.separator())
        let add = NSMenuItem(title: "Add Calendar…", action: #selector(addCalendarProfile),
                             keyEquivalent: "")
        add.target = self
        sub.addItem(add)
        return sub
    }

    /// How long an event name may get before it's shortened with an ellipsis.
    /// Each option is annotated with the character count it works out to, since
    /// points aren't much use for judging that by eye.
    private func labelLengthMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        // Average character width in the actual menu bar font, so the estimates
        // track the font size rather than being guesses.
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz "
        let perChar = max(TimelineView.width(of: alphabet) / CGFloat(alphabet.count), 1)
        let sample = "Quarterly Planning Review"

        for width in Config.maxLabelWidthChoices {
            let characters = Int((CGFloat(width) / perChar).rounded())
            var title = "\(Int(width)) pt  —  about \(characters) characters"
            if abs(width - Config.defaultMaxLabelWidth) < 0.01 { title += "  (default)" }

            let item = NSMenuItem(title: title, action: #selector(chooseLabelLength(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = width
            item.state = abs(Double(Config.maxLabelWidth) - width) < 0.01 ? .on : .off
            item.toolTip = characters >= sample.count
                ? "“\(sample)” fits"
                : "“\(sample)” would show as “\(String(sample.prefix(max(characters - 1, 1))))…”"
            sub.addItem(item)
        }

        sub.addItem(.separator())
        let note = NSMenuItem(title: "Longer names are shortened; the time and 🔴 are never cut",
                              action: nil, keyEquivalent: "")
        note.isEnabled = false
        sub.addItem(note)
        return sub
    }

    /// What the text either side of the timeline shows.
    private func labelsMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        func header(_ t: String) {
            let item = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
        }
        func toggle(_ title: String, _ key: String, _ on: Bool) {
            let item = NSMenuItem(title: title, action: #selector(toggleLabel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = on ? .on : .off
            item.indentationLevel = 1
            sub.addItem(item)
        }

        header("Left — happening now")
        toggle("Block name", "showNowName", Config.showNowName)
        toggle("Time left", "showNowTimeLeft", Config.showNowTimeLeft)
        sub.addItem(.separator())
        header("Right — up next")
        toggle("Block name", "showNextName", Config.showNextName)
        toggle("How long it runs", "showNextDuration", Config.showNextDuration)
        sub.addItem(.separator())
        let note = NSMenuItem(title: "Overlap warnings always show", action: nil, keyEquivalent: "")
        note.isEnabled = false
        sub.addItem(note)
        return sub
    }

    // MARK: Menu helpers

    private func addInfo(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    /// A dim, unclickable line of explanation at the foot of a submenu.
    private func addNote(_ text: String, to menu: NSMenu) {
        menu.addItem(.separator())
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    /// One dropdown row:
    ///
    ///     ▶︎ 11:00 PM – 12:00 AM  •  ZD Chat+Email  •  ◼︎ Focus Work | Learn
    ///
    /// The colour chip sits inline after the name rather than as the item's
    /// image, which would pin it to the far left.
    /// Width of a string in a given font, for laying out the columns.
    private static func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: s, attributes: [.font: font]).size().width)
    }

    private static var menuRowFont: NSFont { NSFont.menuFont(ofSize: 0) }
    /// Tabular figures, so 04:30 lines up under 11:30 — SF's default digits are
    /// proportional and "1" is narrower than the rest.
    private static var menuRowMono: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: menuRowFont.pointSize, weight: .regular)
    }

    private static func rowTime(_ ev: CalEvent, _ formatter: DateFormatter) -> String {
        ev.isAllDay
            ? "All day"
            : "\(formatter.string(from: ev.start)) – \(formatter.string(from: ev.end))"
    }

    private static func rowLength(_ ev: CalEvent) -> String {
        ev.isAllDay ? "" : TimelineView.format(ev.end.timeIntervalSince(ev.start))
    }

    /// Tab stops sized to the widest time and duration in the list. Padding with
    /// spaces can't do this: "7h" and "30m" have the same character count only
    /// by accident, and `m` is wider than `h`, so the columns still drift.
    private static func rowLayout(_ events: [CalEvent],
                                  _ formatter: DateFormatter) -> NSParagraphStyle {
        let font = menuRowFont, mono = menuRowMono
        let marker = textWidth("▶︎ ", font)
        let bullet = textWidth("•", font)
        let gap: CGFloat = 7
        let times = events.map { textWidth(rowTime($0, formatter), mono) }.max() ?? 0
        let lengths = events.map { textWidth(rowLength($0), mono) }.max() ?? 0

        let t1 = marker + gap                 // time
        let t2 = t1 + times + gap             // •
        let t3 = t2 + bullet + gap            // duration
        let t4 = t3 + lengths + gap           // •
        let t5 = t4 + bullet + gap            // name

        let style = NSMutableParagraphStyle()
        style.tabStops = [t1, t2, t3, t4, t5].map {
            NSTextTab(textAlignment: .left, location: $0)
        }
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    /// How many blocks share time with this one, counting itself. Zero-length
    /// reminders get a nominal minute, matching the strip's rule.
    private static func overlapCount(_ ev: CalEvent, in list: [CalEvent]) -> Int {
        let end = max(ev.end, ev.start.addingTimeInterval(60))
        return list.filter { other in
            let otherEnd = max(other.end, other.start.addingTimeInterval(60))
            return otherEnd > ev.start && other.start < end
        }.count
    }

    private static func eventRow(_ ev: CalEvent, now: Date, formatter: DateFormatter,
                                 layout: NSParagraphStyle,
                                 overlaps: Int = 1) -> NSAttributedString {
        let font = menuRowFont, mono = menuRowMono
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)

        let isNow = ev.start <= now && ev.end > now
        let isPast = ev.end <= now
        let ink: NSColor = isPast ? .tertiaryLabelColor : .labelColor
        let dim: NSColor = isPast ? .tertiaryLabelColor : .secondaryLabelColor

        let row = NSMutableAttributedString()
        func text(_ s: String, _ colour: NSColor, _ typeface: NSFont) {
            row.append(NSAttributedString(string: s, attributes: [
                .font: typeface, .foregroundColor: colour, .paragraphStyle: layout
            ]))
        }

        // Every field starts at a tab stop, so the columns line up exactly.
        text(isNow ? "▶︎" : "", ink, font)
        text("\t", dim, font)
        text(rowTime(ev, formatter), dim, mono)
        text("\t", dim, font)
        text("•", dim, font)
        text("\t", dim, font)
        text(rowLength(ev), dim, mono)
        text("\t", dim, font)
        text("•", dim, font)
        text("\t", dim, font)
        text(ev.title, ink, isNow ? bold : font)

        // Category, with its colour as an inline chip.
        let category = ev.category ?? "Uncategorized"
        let colour = ev.color ?? Config.unmatchedColour
        text("  •  ", dim, font)
        let chip = NSTextAttachment()
        chip.image = swatch(colour)
        // Centre the square on the text's optical middle — half the cap height —
        // rather than sitting it on the baseline, which reads a pixel low.
        let size: CGFloat = 10
        chip.bounds = CGRect(x: 0, y: (font.capHeight - size) / 2, width: size, height: size)
        row.append(NSAttributedString(string: " ", attributes: [
            .font: font, .paragraphStyle: layout
        ]))
        row.append(NSAttributedString(attachment: chip))
        text(" \(category)", dim, font)

        // Only when this block actually shares time with another. Spelled out
        // here, unlike on the strip — the dropdown has room to say what it means.
        if overlaps > 1 {
            text("  •  🔴(\(overlaps)) Overlapped", dim, font)
        }

        return row
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 2.5, yRadius: 2.5).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - Actions

    @objc private func refreshNow() { fetch() }

    /// Minutes, because that's how you think about a lead time — decimals allowed
    /// for the half-minute case.
    @objc private func pickCustomAlertLead() {
        menu.cancelTracking()
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add a Lead Time"
        alert.informativeText = "How long before a block starts should it sound? Minutes, from "
            + "0.25 to 120. It's added to the ones already chosen rather than replacing them."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = "3"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let minutes = Double(text), minutes > 0 else { return }
        Alerts.toggleLead(Int((min(max(minutes, 0.25), 120) * 60).rounded()))
        Alerts.requestNotificationPermissionIfNeeded()
    }

    /// An empty string means Off; anything else is a sound name.
    @objc private func chooseAlertSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        guard !name.isEmpty else {
            Alerts.setPlaysSound(false)
            return
        }
        // Picking a sound turns the voice off, and vice versa.
        Alerts.chooseSound(name)
        Alerts.play(name)
        Alerts.requestNotificationPermissionIfNeeded()
    }

    /// Copies a sound of your own into ~/Library/Sounds, where macOS can find it
    /// by name from then on.
    @objc private func importAlertSound() {
        menu.cancelTracking()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Choose an Alert Sound"
        panel.prompt = "Use Sound"
        // Anything NSSound can open. `audio` alone would also allow formats it
        // can't play, and a sound that copies in but stays silent is worse than
        // one that's refused up front.
        panel.allowedContentTypes = [.aiff, .wav, .mp3, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = .modalPanel
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let result = Alerts.importSound(from: url)
        if let name = result.name {
            Alerts.play(name)
            Alerts.requestNotificationPermissionIfNeeded()
        } else if let problem = result.problem {
            let alert = NSAlert()
            alert.messageText = "Couldn't use that sound"
            alert.informativeText = problem
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// An empty string means Off; anything else is a voice key.
    @objc private func chooseAlertVoice(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        guard !key.isEmpty else {
            Alerts.setSpeaks(false)
            return
        }
        Alerts.chooseVoice(key)
        Alerts.test()
        Alerts.requestNotificationPermissionIfNeeded()
    }

    /// Straight to the pane where Apple's natural voices are downloaded.
    @objc private func openVoiceSettings() {
        guard let url = Alerts.voiceSettingsURL else { return }
        // Whatever is downloaded there should show up next time the menu opens.
        Alerts.refreshVoices()
        NSWorkspace.shared.open(url)
    }

    @objc private func testAlert() { Alerts.test() }

    /// -1 is off, 0 is launch immediately, anything else is a wait in seconds.
    @objc private func chooseStartup(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        let enabled = value >= 0
        LoginItem.apply(enabled: enabled, delay: max(value, 0))
        if enabled && !LoginItem.isInApplications { warnAboutAppLocation() }
    }

    /// Said once, when it's turned on from somewhere the app is likely to move
    /// from — the Downloads folder, or the build directory it was made in.
    private func warnAboutAppLocation() {
        menu.cancelTracking()
        let alert = NSAlert()
        alert.messageText = "Launching from its current folder"
        alert.informativeText = """
        The login item points at the app where it is now:

        \(Bundle.main.bundleURL.path)

        Moving, renaming or deleting that folder will stop it launching. Copy the app to
        /Applications and choose Run at Startup again to point it there.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func chooseTimeRange(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Double else { return }
        Config.setWindowMinutes(minutes)
        redrawNow()
    }

    @objc private func chooseTimelineWidth(_ sender: NSMenuItem) {
        guard let width = sender.representedObject as? Double else { return }
        Config.setTimelineWidth(width)
        redrawNow()
    }

    @objc private func restoreDefaults() {
        Config.restoreAppearanceDefaults()
        redrawNow()
    }

    // MARK: Debug time

    @objc private func pickDebugTime() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Debug Time"
        alert.informativeText = """
            Move the app to any moment, so you can see how the strip looks then \
            without waiting for it — handy for checking overlaps, long blocks and \
            the ends of the day.

            The simulated clock keeps running from the moment you pick, so blocks \
            still slide and countdowns still tick. Events are re-fetched for the \
            simulated date.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Simulate")
        alert.addButton(withTitle: "Use Current Time")
        alert.addButton(withTitle: "Cancel")

        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        picker.timeZone = Config.displayTimeZone
        picker.dateValue = Clock.now
        alert.accessoryView = picker
        alert.window.initialFirstResponder = picker

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Config.setDebugTime(picker.dateValue)
        case .alertSecondButtonReturn:
            Config.clearDebugTime()
        default:
            return   // cancelled: leave whatever was set alone
        }
        // The simulated date may be a different day, so reload rather than redraw.
        reloadAfterSourceChange()
    }

    @objc private func resetDebugTime() {
        Config.clearDebugTime()
        reloadAfterSourceChange()
    }

    @objc private func chooseLabelLength(_ sender: NSMenuItem) {
        guard let width = sender.representedObject as? Double else { return }
        Config.setMaxLabelWidth(width)
        redrawNow()
    }

    @objc private func toggleLabel(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Config.toggle(key)
        redrawNow()
    }

    /// Appearance changed — resize and repaint, no refetch needed.
    private func redrawNow() {
        resize()
        timeline.needsDisplay = true
    }

    @objc private func toggleDemoMode() {
        Config.setDemoMode(!Config.demoMode)
        reloadAfterSourceChange()
    }

    /// Right-aligned caption for a form field in a dialog.
    private static func fieldLabel(_ text: String, y: CGFloat, width: CGFloat = 88) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 0, y: y, width: width, height: 16)
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    // MARK: Keyword colors

    @objc private func importKeywordCSV() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Import Keyword Colors"
        panel.message = "Choose a CSV with category, color and keyword columns. "
            + "Colour can be a hex (#28CD41) or a name (green)."
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // A menu bar app isn't the active app when the panel opens, so it comes
        // up behind, unfocused, and wherever it was last left. Position it
        // explicitly and hand it the keyboard.
        panel.level = .modalPanel
        if let screen = NSScreen.main {
            let size = NSSize(width: 720, height: 460)
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                                  y: frame.midY - size.height / 2,
                                  width: size.width, height: size.height),
                           display: false)
        }
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Excel often writes Latin-1 rather than UTF-8.
            guard let fallback = try? String(contentsOf: url, encoding: .isoLatin1) else {
                showError("Couldn't read that file", error.localizedDescription)
                return
            }
            text = fallback
        }

        let result = KeywordRules.parse(csv: text)
        if let problem = result.problem {
            showError("Couldn't import \(url.lastPathComponent)", problem)
            return
        }
        KeywordRules.save(result.rules, from: url.lastPathComponent)

        // Tell them what actually landed, including anything ignored.
        var notes: [String] = []
        let categories = KeywordRules.categories.count
        notes.append("\(result.rules.count) keywords across \(categories) "
                     + "categor\(categories == 1 ? "y" : "ies").")
        if result.skippedRows > 0 {
            notes.append("\(result.skippedRows) row\(result.skippedRows == 1 ? "" : "s") skipped "
                         + "(missing keyword or unreadable colour).")
        }
        if !result.duplicates.isEmpty {
            notes.append("Repeated keywords kept once: \(result.duplicates.prefix(4).joined(separator: ", "))"
                         + (result.duplicates.count > 4 ? "…" : "") + ".")
        }
        if !result.unknownColours.isEmpty {
            notes.append("\nNot recognised as a colour — use a hex like #28CD41, or a name such as "
                         + "blue, teal, amber:\n• "
                         + result.unknownColours.prefix(5).joined(separator: "\n• "))
        }
        let longest = result.rules.first.map { "\($0.keyword)" } ?? "—"
        notes.append("\nLongest phrase wins a tie, so “\(longest)” is checked before any single word.")

        showError("Imported \(url.lastPathComponent)", notes.joined(separator: " "))
        reloadAfterSourceChange()
    }

    @objc private func clearKeywordCSV() {
        KeywordRules.clear()
        reloadAfterSourceChange()
    }

    /// Apply the built-in sample rules straight away.
    @objc private func loadSampleKeywords() {
        let result = KeywordRules.parse(csv: KeywordRules.sampleCSV)
        guard result.problem == nil, !result.rules.isEmpty else {
            showError("Couldn't load the sample", result.problem ?? "No rules in the sample.")
            return
        }
        KeywordRules.save(result.rules, from: "the built-in sample")
        reloadAfterSourceChange()

        let categories = KeywordRules.categories.count
        showError("Sample colors applied",
                  "\(result.rules.count) keywords across \(categories) categories. "
                  + "Use “Save Sample CSV…” if you'd like to edit them and import your own.")
    }

    /// Write the sample out so it can be edited in a spreadsheet and re-imported.
    @objc private func saveSampleKeywordCSV() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "Save Sample Keyword Colors"
        panel.message = "Edit this in any spreadsheet, then bring it back with Import CSV…"
        panel.nameFieldStringValue = "keyword-colors.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        // Same treatment as the open panel: a menu bar app's panels arrive
        // behind and unfocused otherwise.
        panel.level = .modalPanel
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            // Trailing newline, so appending a row in a text editor behaves.
            try (KeywordRules.sampleCSV + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showError("Couldn't save the sample", error.localizedDescription)
        }
    }

    // MARK: Saved calendars

    private func activateProfile(named name: String) {
        guard let profile = Config.profiles.first(where: { $0.name == name }) else { return }
        Config.activate(profile)
        Config.setDemoMode(false)   // a real calendar wins over test data
        reloadAfterSourceChange()
    }

    @objc private func addCalendarProfile() {
        NSApp.activate(ignoringOtherApps: true)
        var prefillName = ""
        var prefillLink = ""

        while true {
            let alert = NSAlert()
            alert.messageText = "Add Calendar"
            alert.informativeText = """
                Give it a name you'll recognise in the menu, then paste any of these:
                  •  a Google Calendar embed link (…/embed?src=… or …/newembed?src=…)
                  •  a public iCal feed URL ending in .ics
                  •  a webcal:// link
                  •  a calendar address, e.g. you@gmail.com
                  •  a local file, e.g. file:///path/to/test.ics

                Feeds carry no colour information — use Keyword Colors to colour
                blocks by what they're called.
                """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            let container = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: 66))
            let nameField = NSTextField(frame: NSRect(x: 62, y: 38, width: 408, height: 24))
            nameField.placeholderString = "Work"
            nameField.stringValue = prefillName
            let linkField = NSTextField(frame: NSRect(x: 62, y: 4, width: 408, height: 24))
            linkField.placeholderString = Config.examplePlaceholder
            linkField.lineBreakMode = .byTruncatingTail
            linkField.stringValue = prefillLink
            container.addSubview(Self.fieldLabel("Name", y: 42, width: 58))
            container.addSubview(nameField)
            container.addSubview(Self.fieldLabel("Link", y: 8, width: 58))
            container.addSubview(linkField)
            alert.accessoryView = container
            alert.window.initialFirstResponder = nameField

            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let link = linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty, !link.isEmpty { name = CalendarSource.label(for: link) }

            var problem: String?
            if link.isEmpty {
                problem = "Paste a calendar link."
            } else if name.isEmpty {
                problem = "Give this calendar a name."
            } else {
                problem = CalendarSource.problem(with: link)
            }

            if let problem {
                let retry = NSAlert()
                retry.alertStyle = .warning
                retry.messageText = "Can't save that calendar"
                retry.informativeText = problem
                retry.addButton(withTitle: "Try Again")
                retry.addButton(withTitle: "Cancel")
                guard retry.runModal() == .alertFirstButtonReturn else { return }
                prefillName = name          // keep what they typed so they can correct it
                prefillLink = link
                continue
            }

            Config.addProfile(name: name, link: link)
            Config.setDemoMode(false)
            reloadAfterSourceChange()
            return
        }
    }

    /// Pencil icon on a row.
    private func renameProfile(named current: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Rename Calendar"
        alert.informativeText = "What should “\(current)” be called?"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != current else { return }
        Config.renameProfile(current, to: name)
    }

    /// ✕ icon on a row — always confirms first.
    private func confirmRemoveProfile(named name: String) {
        NSApp.activate(ignoringOtherApps: true)
        let isActive = Config.activeProfileName == name
        let isLast = Config.profiles.count == 1

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove “\(name)”?"
        if isLast {
            alert.informativeText = "This is your only saved calendar, so nothing will be shown "
                + "until you add another. Only the saved link is forgotten — your calendar itself "
                + "is untouched."
        } else if isActive {
            alert.informativeText = "It's the one in use, so the next saved calendar will take "
                + "over. Only the saved link is forgotten — your calendar itself is untouched."
        } else {
            alert.informativeText = "Only the saved link is forgotten — your calendar itself is "
                + "untouched."
        }
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Config.removeProfile(named: name)
        reloadAfterSourceChange()
    }

    // MARK: Shared

    /// Show a fetch failure on the strip, and drop stale events so the menu
    /// doesn't keep listing a schedule we can no longer verify.
    private func showFailure(_ message: String) {
        timeline.events = []
        menuEvents = []
        timeline.errorMessage = message
    }

    private func showError(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Source changed: clear what we have and reload from scratch.
    private func reloadAfterSourceChange() {
        menuEvents = []
        timeline.events = []
        timeline.errorMessage = nil
        lastFetch = nil
        fetch()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
