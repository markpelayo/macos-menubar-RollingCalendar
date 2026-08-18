import AppKit

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

    // MARK: Google mode

    /// Which Google calendar to read. "primary" is the account's own calendar —
    /// the one named after you in Google Calendar's sidebar.
    static var googleCalendarID: String {
        UserDefaults.standard.string(forKey: "googleCalendarID") ?? "primary"
    }

    static var googleCalendarName: String {
        UserDefaults.standard.string(forKey: "googleCalendarName") ?? "Primary calendar"
    }

    static func setGoogleCalendar(id: String, name: String) {
        UserDefaults.standard.set(id, forKey: "googleCalendarID")
        UserDefaults.standard.set(name, forKey: "googleCalendarName")
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

    /// Back to ± 1 hour, 250 pt timeline, 300 pt labels, every label switched on.
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
    static let defaultMaxLabelWidth = 300.0

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
        return !hasCalendarInput && !GoogleAuth.shared.isSignedIn
    }

    static func setDemoMode(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "demoMode")
    }

    /// Filled blocks like Google Calendar's day view (vs. translucent tint).
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
    private var todaysEvents: [CalEvent] = []

    // Google mode caches
    private var googleCalendars: [GCalendarInfo] = []
    private var eventPalette: [String: String] = [:]

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
            self?.resize()
            self?.timeline.needsDisplay = true
        }
        fetchTimer = Timer.scheduledTimer(withTimeInterval: Config.refetchInterval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
        RunLoop.main.add(redrawTimer!, forMode: .common)
        RunLoop.main.add(fetchTimer!, forMode: .common)

        installEditMenu()
        Config.adoptLegacyCalendarIfNeeded()

        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.fetch() }

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
        } else if GoogleAuth.shared.isSignedIn {
            fetchFromGoogle()
        } else {
            fetchFromICS()
        }
    }

    /// The window we ask for: today, plus a margin so blocks that straddle
    /// midnight still render at the edges of the strip.
    private func dayBounds() -> (dayStart: Date, dayEnd: Date, from: Date, to: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Config.displayTimeZone
        let now = Clock.now
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        // Overshoot the day so blocks straddling midnight still render, and so
        // the "next up" label can see past the end of the visible window.
        let margin = max(Config.windowMinutes * 60, 3600)
        return (dayStart, dayEnd, dayStart.addingTimeInterval(-margin), dayEnd.addingTimeInterval(margin))
    }

    // MARK: Demo blocks

    private func loadDemoEvents() {
        let bounds = dayBounds()
        let all = DemoData.events(around: Clock.now, timeZone: Config.displayTimeZone)
        timeline.errorMessage = nil
        timeline.events = all.filter { $0.intersects(bounds.from, bounds.to) }
        todaysEvents = all.filter { $0.intersects(bounds.dayStart, bounds.dayEnd) }
        lastFetch = Date()
    }

    // MARK: Google

    private func fetchFromGoogle() {
        GoogleAuth.shared.withAccessToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.showFailure(error)
            case .success(let token):
                self.loadGoogleMetadata(token: token) {
                    self.loadGoogleEvents(token: token)
                }
            }
        }
    }

    /// Colour palette + calendar list, fetched once and reused.
    private func loadGoogleMetadata(token: String, then: @escaping () -> Void) {
        let group = DispatchGroup()

        if eventPalette.isEmpty {
            group.enter()
            GoogleCalendarAPI.eventPalette(token: token) { [weak self] result in
                if case .success(let map) = result { self?.eventPalette = map }
                group.leave()
            }
        }
        if googleCalendars.isEmpty {
            group.enter()
            GoogleCalendarAPI.calendarList(token: token) { [weak self] result in
                if case .success(let list) = result { self?.googleCalendars = list }
                group.leave()
            }
        }
        group.notify(queue: .main, execute: then)
    }

    private func selectedGoogleCalendar() -> GCalendarInfo? {
        let id = Config.googleCalendarID
        if id == "primary" { return googleCalendars.first(where: { $0.primary }) }
        return googleCalendars.first(where: { $0.id == id })
    }

    private func loadGoogleEvents(token: String) {
        let bounds = dayBounds()
        let fallback = selectedGoogleCalendar()?.backgroundColor

        GoogleCalendarAPI.events(calendarID: Config.googleCalendarID,
                                 token: token,
                                 from: bounds.from,
                                 to: bounds.to,
                                 palette: eventPalette,
                                 fallbackColor: fallback) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.showFailure(error)
            case .success(let events):
                self.timeline.errorMessage = nil
                self.timeline.events = events
                self.todaysEvents = events.filter { $0.intersects(bounds.dayStart, bounds.dayEnd) }
                self.lastFetch = Date()
                // Keep the display name in step with what Google calls it.
                if let cal = self.selectedGoogleCalendar(), cal.summary != Config.googleCalendarName {
                    Config.setGoogleCalendar(id: Config.googleCalendarID, name: cal.summary)
                }
            }
        }
    }

    // MARK: Public .ics feed (used when not signed in)

    private func fetchFromICS() {
        guard let ics = Config.icsURL, let url = URL(string: ics) else {
            timeline.errorMessage = "No calendar yet — click to set one up"
            return
        }

        // A local .ics file (handy for testing) — read it directly.
        if url.isFileURL {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard text.contains("BEGIN:VCALENDAR") else {
                    timeline.errorMessage = "That file isn't iCalendar"
                    return
                }
                timeline.errorMessage = nil
                applyICS(text)
            } catch {
                timeline.errorMessage = "Can't read file: \(error.localizedDescription)"
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
                    self.timeline.errorMessage = "Calendar unreachable (\(error.localizedDescription))"
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    self.timeline.errorMessage = "Calendar HTTP \(http.statusCode) — sign in with Google, or make the feed public"
                    return
                }
                guard let data, let text = String(data: data, encoding: .utf8),
                      text.contains("BEGIN:VCALENDAR") else {
                    self.timeline.errorMessage = "Feed is not valid iCalendar"
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
        let days = [-1, 0, 1].compactMap { cal.date(byAdding: .day, value: $0, to: today) }

        let all = ICS.events(from: ics, days: days, calendar: cal)
        let bounds = dayBounds()

        timeline.events = all.filter { $0.intersects(bounds.from, bounds.to) }
        todaysEvents = all.filter { $0.intersects(bounds.dayStart, bounds.dayEnd) }
        lastFetch = Date()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "h:mm a"
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

        // --- Today's events ---
        if let msg = timeline.errorMessage {
            addInfo(msg, to: menu)
        } else if todaysEvents.isEmpty {
            addInfo("No events today", to: menu)
        } else {
            let now = Clock.now
            for ev in todaysEvents {
                let time = ev.isAllDay ? "All day" : "\(df.string(from: ev.start)) – \(df.string(from: ev.end))"
                let item = NSMenuItem(title: "\(time)   \(ev.title)", action: nil, keyEquivalent: "")
                let isNow = ev.start <= now && ev.end > now
                var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
                if ev.end <= now {
                    attrs[.foregroundColor] = NSColor.tertiaryLabelColor
                }
                item.attributedTitle = NSAttributedString(
                    string: isNow ? "▶︎ \(time)   \(ev.title)" : "\(time)   \(ev.title)",
                    attributes: attrs)
                // A colour swatch matching the block on the strip.
                if let color = ev.color {
                    item.image = Self.swatch(color)
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        if let lastFetch {
            df.dateFormat = "h:mm:ss a"
            addInfo("Updated \(df.string(from: lastFetch))", to: menu)
        }
        add("Refresh Now", #selector(refreshNow), to: menu, key: "r")
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

        let restore = add("Restore Defaults", #selector(restoreDefaults), to: menu)
        restore.isEnabled = !Config.isAppearanceDefault
        restore.toolTip = restore.isEnabled
            ? "Back to ± 1 hour, a 250 pt timeline, 300 pt labels and all labels on"
            : "Already at the default settings"

        menu.addItem(.separator())

        // --- Which source is live ---
        if Config.demoMode {
            addInfo("Calendar: demo blocks (test data)", to: menu)
        } else if GoogleAuth.shared.isSignedIn {
            addInfo("Calendar: \(Config.googleCalendarName)", to: menu)
            let picker = NSMenuItem(title: "Choose Calendar", action: nil, keyEquivalent: "")
            picker.submenu = calendarPickerMenu()
            menu.addItem(picker)
        } else if let name = Config.calendarDisplayName {
            addInfo("Calendar: \(name) (public feed)", to: menu)
        } else {
            addInfo("No calendar set up yet", to: menu)
        }

        // Demo toggle stays reachable in every state.
        let demoItem = add("Demo Mode", #selector(toggleDemoMode), to: menu)
        demoItem.state = Config.demoMode ? .on : .off
        demoItem.toolTip = "Synthetic 15-minute blocks, to check the strip moves correctly"

        // --- Setup, also reachable in every state (including demo mode) ---
        if GoogleAuth.shared.isSignedIn {
            add("Google Sign-In Setup…", #selector(setUpGoogle), to: menu)
            add("Sign Out of Google", #selector(signOutOfGoogle), to: menu)
        } else {
            if GoogleAuth.shared.isConfigured {
                add("Sign in with Google…", #selector(signInToGoogle), to: menu)
                add("Google Sign-In Setup…", #selector(setUpGoogle), to: menu)
            } else {
                add("Set Up Google Sign-In…  (for colours)", #selector(setUpGoogle), to: menu)
            }
            if Config.profiles.isEmpty {
                add("Add Calendar…", #selector(addCalendarProfile), to: menu)
            } else {
                let saved = NSMenuItem(title: "Saved Calendars", action: nil, keyEquivalent: "")
                saved.submenu = savedCalendarsMenu()
                menu.addItem(saved)
            }
            if Config.hasCalendarInput {
                add("Copy Feed URL", #selector(copyFeedURL), to: menu)
            }
        }
        add("Open Google Calendar", #selector(openCalendar), to: menu)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    /// Saved calendar links, one per line, plus the housekeeping actions.
    private func savedCalendarsMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        let active = Config.activeProfileName
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

    private func calendarPickerMenu() -> NSMenu {
        let sub = NSMenu()
        if googleCalendars.isEmpty {
            let item = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
            return sub
        }
        let selected = Config.googleCalendarID
        for cal in googleCalendars.sorted(by: { ($0.primary ? 0 : 1, $0.summary) < ($1.primary ? 0 : 1, $1.summary) }) {
            let item = NSMenuItem(title: cal.summary, action: #selector(chooseCalendar(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = cal.id
            item.state = (cal.id == selected || (selected == "primary" && cal.primary)) ? .on : .off
            if let hex = cal.backgroundColor, let color = NSColor(hexString: hex) {
                item.image = Self.swatch(color)
            }
            sub.addItem(item)
        }
        return sub
    }

    // MARK: Menu helpers

    private func addInfo(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
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

    @objc private func openCalendar() {
        let input = Config.calendarInput ?? ""
        let target = (input.lowercased().hasPrefix("http") && input.contains("calendar.google.com"))
            ? input
            : "https://calendar.google.com/calendar/r/day"
        if let url = URL(string: target.replacingOccurrences(of: " ", with: "%20")) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func copyFeedURL() {
        guard let ics = Config.icsURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ics, forType: .string)
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

    @objc private func chooseCalendar(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Config.setGoogleCalendar(id: id, name: sender.title)
        reloadAfterSourceChange()
    }

    // MARK: Google sign-in

    @objc private func signInToGoogle() {
        NSApp.activate(ignoringOtherApps: true)
        GoogleAuth.shared.signIn { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.googleCalendars = []
                self.eventPalette = [:]
                Config.setDemoMode(false)   // real calendar wins over test data
                self.reloadAfterSourceChange()
            case .failure(let error):
                self.showError("Couldn't sign in", error.localizedDescription)
            }
        }
    }

    @objc private func signOutOfGoogle() {
        GoogleAuth.shared.signOut()
        googleCalendars = []
        eventPalette = [:]
        // Don't carry a calendar selection over to whatever account signs in next.
        Config.setGoogleCalendar(id: "primary", name: "Primary calendar")
        reloadAfterSourceChange()
    }

    @objc private func setUpGoogle() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Google Sign-In Setup"
        alert.informativeText = """
            Google requires each app to be registered, so this is a one-time step.

            1.  console.cloud.google.com  →  create (or pick) a project
            2.  APIs & Services → Library → enable “Google Calendar API”
            3.  APIs & Services → OAuth consent screen → External →
                 add your own address under Test users
            4.  Credentials → Create credentials → OAuth client ID →
                 Application type: Desktop app
            5.  Paste the Client ID and Client secret below

            Your password is never seen by this app — you sign in on Google's own page.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save & Sign In")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 66))
        let idLabel = Self.fieldLabel("Client ID", y: 42)
        let idField = NSTextField(frame: NSRect(x: 92, y: 38, width: 368, height: 24))
        idField.placeholderString = "1234-abcd.apps.googleusercontent.com"
        idField.stringValue = GoogleAuth.shared.clientID ?? ""

        let secretLabel = Self.fieldLabel("Client secret", y: 8)
        let secretField = NSTextField(frame: NSRect(x: 92, y: 4, width: 368, height: 24))
        secretField.placeholderString = "GOCSPX-… (from the same credential)"
        secretField.stringValue = GoogleAuth.shared.clientSecret ?? ""

        container.addSubview(idLabel)
        container.addSubview(idField)
        container.addSubview(secretLabel)
        container.addSubview(secretField)
        alert.accessoryView = container
        alert.window.initialFirstResponder = idField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let id = idField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            GoogleAuth.shared.forgetClient()
            reloadAfterSourceChange()
            return
        }
        GoogleAuth.shared.setClient(id: id, secret: secretField.stringValue)
        signInToGoogle()
    }

    private static func fieldLabel(_ text: String, y: CGFloat, width: CGFloat = 88) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 0, y: y, width: width, height: 16)
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
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

                Public feeds carry no colour information. Sign in with Google instead
                if you want each block in its Google Calendar colour.
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
    private func showFailure(_ error: Error) {
        timeline.events = []
        todaysEvents = []
        timeline.errorMessage = error.localizedDescription
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
        todaysEvents = []
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
