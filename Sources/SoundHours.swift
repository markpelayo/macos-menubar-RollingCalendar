import Foundation

/// When the app is allowed to make a noise at all.
///
/// Time Block Alerts and the Westminster Chime each decide *what* to sound;
/// this decides *whether*, and both ask it first. One schedule rather than two,
/// because "don't wake me at 3 a.m." is a single thought and it would be a poor
/// arrangement to have to express it twice.
///
/// A window may run past midnight — 11:30 AM to 4:30 AM is the default — and
/// several windows may be open at once, so a working day split by a long evening
/// away from the desk is one setting rather than a compromise.
///
/// Previews are exempt: *Test Alert Now* and *Hear It* are things you asked for
/// on purpose, and refusing them because of the hour would look like a bug.
enum SoundHours {

    /// A window, as minutes from midnight. `end` at or before `start` means it
    /// runs past midnight into the next day.
    struct Window: Equatable {
        let start: Int
        let end: Int

        var wrapsMidnight: Bool { end <= start }

        /// Both ends included: a window labelled "6:00 AM – 11:00 PM" should
        /// allow the eleven o'clock strike, and "11:30 AM – 4:30 AM" the 4:30
        /// quarter. An exclusive end would silence the one minute the label
        /// names.
        func contains(minutes: Int) -> Bool {
            wrapsMidnight ? (minutes >= start || minutes <= end)
                          : (minutes >= start && minutes <= end)
        }

        /// "11:30 AM – 4:30 AM"
        var title: String {
            "\(SoundHours.clock(start)) – \(SoundHours.clock(end))"
        }

        /// "1130-0430", which is what's stored.
        var encoded: String {
            String(format: "%04d-%04d", (start / 60) * 100 + start % 60,
                   (end / 60) * 100 + end % 60)
        }

        static func decode(_ text: String) -> Window? {
            let halves = text.split(separator: "-")
            guard halves.count == 2,
                  let from = Int(halves[0]), let to = Int(halves[1]),
                  let start = SoundHours.minutes(fromHHMM: from),
                  let end = SoundHours.minutes(fromHHMM: to) else { return nil }
            return Window(start: start, end: end)
        }
    }

    /// Whole days, for the "no limit" case.
    static let allDay = Window(start: 0, end: 0)

    /// The two obvious shapes of a day. Anything else comes from Add Custom…
    static let presets: [Window] = [
        Window(start: 11 * 60 + 30, end: 4 * 60 + 30),   // 11:30 AM – 4:30 AM
        Window(start: 6 * 60, end: 23 * 60)              // 6:00 AM – 11:00 PM
    ]

    /// Late morning to the small hours: the default, because someone who wants a
    /// chime marking the day usually doesn't want one marking the night.
    static let defaultWindows = [presets[0]]

    // MARK: - Settings

    /// Off silences both the alerts and the chime, whatever their own settings
    /// say — a single switch to stop the app making noise.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundHoursOn") as? Bool ?? true
    }

    static var windows: [Window] {
        guard let stored = UserDefaults.standard.stringArray(forKey: "soundHours") else {
            return defaultWindows
        }
        return stored.compactMap(Window.decode)
    }

    static func setWindows(_ list: [Window]) {
        var unique: [Window] = []
        for window in list where !unique.contains(window) { unique.append(window) }
        let sorted = unique.sorted { $0.start < $1.start }
        UserDefaults.standard.set(sorted.map { $0.encoded }, forKey: "soundHours")
        // No windows means no sound, which is what Off means — so say Off rather
        // than leaving a ticked row above two features that can never fire.
        UserDefaults.standard.set(!sorted.isEmpty, forKey: "soundHoursOn")
    }

    /// One click adds or removes a window, so several can be open at once.
    ///
    /// While Off, every row reads as unticked, so a click has to mean "turn this
    /// on" — otherwise clicking the window you want would delete it.
    static func toggle(_ window: Window) {
        guard isEnabled else {
            setWindows(windows.contains(window) ? windows : windows + [window])
            return
        }
        var current = windows
        if let index = current.firstIndex(of: window) {
            current.remove(at: index)
        } else {
            current.append(window)
        }
        setWindows(current)
    }

    /// Insert-only, for the Add Custom… dialog: typing a window you already have
    /// should leave you with it, not without it.
    static func add(_ window: Window) {
        guard !isEnabled || !windows.contains(window) else { return }
        setWindows(windows + [window])
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: "soundHoursOn")
    }

    /// Back on, with the default window if the set was emptied.
    static func enable() {
        UserDefaults.standard.set(true, forKey: "soundHoursOn")
        if windows.isEmpty { setWindows(defaultWindows) }
    }

    /// True when a sound could happen at some hour — the state the ✓ on the menu
    /// row reflects.
    static var isArmed: Bool { isEnabled && !windows.isEmpty }

    // MARK: - The question everything else asks

    /// True when a sound is allowed right now. Both `Alerts.check` and
    /// `Westminster.check` call this before anything else.
    static func allows(_ date: Date) -> Bool {
        guard isEnabled else { return false }
        let list = windows
        guard !list.isEmpty else { return false }
        if list.contains(allDay) { return true }

        let parts = Config.calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return false }
        let now = hour * 60 + minute
        return list.contains { $0.contains(minutes: now) }
    }

    // MARK: - How it reads in the menu

    static var menuTitle: String {
        let list = windows
        guard isEnabled, !list.isEmpty else { return "Sound Hours: Off" }
        if list.contains(allDay) { return "Sound Hours: all day" }
        if list.count == 1 { return "Sound Hours: \(list[0].title)" }
        return "Sound Hours: \(list.count) windows"
    }

    /// "11:30 AM", from minutes since midnight.
    static func clock(_ minutes: Int) -> String {
        let normalised = ((minutes % 1440) + 1440) % 1440
        let hour24 = normalised / 60
        let minute = normalised % 60
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour, minute, suffix)
    }

    private static func minutes(fromHHMM value: Int) -> Int? {
        let hour = value / 100
        let minute = value % 100
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    // MARK: - Reading what someone typed

    /// Accepts what people actually type: "6", "6am", "6:30 PM", "18:30",
    /// "1830", "11.30pm". Returns minutes from midnight.
    static func parse(_ raw: String) -> Int? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        var isPM: Bool?
        for marker in ["a.m.", "p.m.", "am", "pm"] where text.hasSuffix(marker) {
            isPM = marker.hasPrefix("p")
            text = String(text.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        let digits = text.replacingOccurrences(of: ".", with: ":")
        var hour: Int
        var minute = 0

        if digits.contains(":") {
            let halves = digits.split(separator: ":")
            guard halves.count == 2, let h = Int(halves[0]), let m = Int(halves[1]) else {
                return nil
            }
            hour = h
            minute = m
        } else if let value = Int(digits) {
            // "1830" is half past six; "18" is six o'clock.
            if digits.count > 2 {
                hour = value / 100
                minute = value % 100
            } else {
                hour = value
            }
        } else {
            return nil
        }

        if let isPM {
            guard (1...12).contains(hour) else { return nil }
            if isPM, hour != 12 { hour += 12 }
            if !isPM, hour == 12 { hour = 0 }     // 12 AM is midnight
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}
