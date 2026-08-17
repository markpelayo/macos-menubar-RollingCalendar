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

    /// Total visible span in hours, centred on now.
    static var windowHours: Double {
        let v = UserDefaults.standard.double(forKey: "windowHours")
        return v > 0 ? v : 4.0
    }

    /// Pixels of menu bar width per hour.
    static var pixelsPerHour: Double {
        let v = UserDefaults.standard.double(forKey: "pixelsPerHour")
        return v > 0 ? v : 90.0
    }

    static var showTitles: Bool {
        UserDefaults.standard.object(forKey: "showTitles") as? Bool ?? true
    }

    /// Visual separation between neighbouring blocks, in points. Cosmetic only —
    /// it never changes an event's time or position.
    static var blockGap: CGFloat {
        let v = UserDefaults.standard.double(forKey: "blockGap")
        return v > 0 ? CGFloat(v) : 3.0
    }

    /// Width of the left gutter holding the countdown. 0 hides it.
    static var countdownWidth: CGFloat {
        if let v = UserDefaults.standard.object(forKey: "countdownWidth") as? Double {
            return CGFloat(max(v, 0))
        }
        return 54
    }

    /// The size macOS uses for menu bar labels — matches other menu bar widgets.
    static var menuBarFontSize: CGFloat { NSFont.menuBarFont(ofSize: 0).pointSize }

    /// Point size of the event titles inside blocks.
    static var titleFontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: "titleFontSize")
        return v > 0 ? CGFloat(v) : menuBarFontSize
    }

    /// Point size of the countdown in the left gutter.
    static var countdownFontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: "countdownFontSize")
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

    /// Tick marks and event times use the `ctz=` time zone from the calendar
    /// link when present, otherwise the Mac's own time zone.
    static var displayTimeZone: TimeZone {
        guard let input = calendarInput else { return .current }
        return CalendarSource.timeZone(from: input) ?? .current
    }

    static let redrawInterval: TimeInterval = 1       // slide the strip / tick the countdown
    static let refetchInterval: TimeInterval = 300    // re-read the calendar
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
        // Timeline width plus the countdown gutter on the left.
        let width = CGFloat(Config.windowHours * Config.pixelsPerHour) + Config.countdownWidth
        statusItem = NSStatusBar.system.statusItem(withLength: width)

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
            self?.timeline.needsDisplay = true
        }
        fetchTimer = Timer.scheduledTimer(withTimeInterval: Config.refetchInterval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
        RunLoop.main.add(redrawTimer!, forMode: .common)
        RunLoop.main.add(fetchTimer!, forMode: .common)

        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.fetch() }

        fetch()
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
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let margin = Config.windowHours * 3600
        return (dayStart, dayEnd, dayStart.addingTimeInterval(-margin), dayEnd.addingTimeInterval(margin))
    }

    // MARK: Demo blocks

    private func loadDemoEvents() {
        let bounds = dayBounds()
        let all = DemoData.events(around: Date(), timeZone: Config.displayTimeZone)
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
        let today = Date()
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
        addInfo(dayFormatter.string(from: Date()), to: menu)
        menu.addItem(.separator())

        // --- Today's events ---
        if let msg = timeline.errorMessage {
            addInfo(msg, to: menu)
        } else if todaysEvents.isEmpty {
            addInfo("No events today", to: menu)
        } else {
            let now = Date()
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

        // --- Which source is live ---
        if Config.demoMode {
            addInfo("Calendar: demo blocks (test data)", to: menu)
        } else if GoogleAuth.shared.isSignedIn {
            addInfo("Calendar: \(Config.googleCalendarName)", to: menu)
            let picker = NSMenuItem(title: "Choose Calendar", action: nil, keyEquivalent: "")
            picker.submenu = calendarPickerMenu()
            menu.addItem(picker)
        } else if let input = Config.calendarInput {
            addInfo("Calendar: \(CalendarSource.label(for: input)) (public feed)", to: menu)
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
            add(Config.hasCalendarInput ? "Change Calendar…" : "Set Calendar Link…",
                #selector(changeCalendar), to: menu)
            if Config.hasCalendarInput {
                add("Clear Calendar Link", #selector(resetCalendar), to: menu)
                add("Copy Feed URL", #selector(copyFeedURL), to: menu)
            }
        }
        add("Open Google Calendar", #selector(openCalendar), to: menu)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    @objc private func resetCalendar() {
        Config.setCalendar(nil)
        reloadAfterSourceChange()
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

    private static func fieldLabel(_ text: String, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 0, y: y, width: 88, height: 16)
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    // MARK: Public feed editing

    @objc private func changeCalendar() {
        NSApp.activate(ignoringOtherApps: true)
        var prefill = Config.calendarInput ?? ""

        while true {
            let alert = makeCalendarAlert()
            guard let field = alert.accessoryView as? NSTextField else { return }
            field.stringValue = prefill
            alert.window.initialFirstResponder = field

            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let entered = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if entered.isEmpty {
                Config.setCalendar(nil)
                reloadAfterSourceChange()
                return
            }
            if let problem = CalendarSource.problem(with: entered) {
                let retry = NSAlert()
                retry.alertStyle = .warning
                retry.messageText = "Can't use that calendar link"
                retry.informativeText = problem
                retry.addButton(withTitle: "Try Again")
                retry.addButton(withTitle: "Cancel")
                guard retry.runModal() == .alertFirstButtonReturn else { return }
                prefill = entered   // keep what they typed so they can correct it
                continue
            }
            Config.setCalendar(entered)
            Config.setDemoMode(false)   // a real calendar wins over test data
            reloadAfterSourceChange()
            return
        }
    }

    private func makeCalendarAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Change Calendar"
        alert.informativeText = """
            Paste any of these:
              •  a Google Calendar embed link (…/embed?src=… or …/newembed?src=…)
              •  a public iCal feed URL ending in .ics
              •  a webcal:// link
              •  a calendar address, e.g. you@gmail.com
              •  a local file, e.g. file:///Users/you/test.ics

            Public feeds carry no colour information. Sign in with Google instead
            if you want each block in its Google Calendar colour.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.placeholderString = Config.examplePlaceholder
        field.lineBreakMode = .byTruncatingTail
        alert.accessoryView = field
        return alert
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
