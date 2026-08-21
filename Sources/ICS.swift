import Foundation

// MARK: - Model

struct CalEvent {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// Hex background for the block, e.g. "#28CD41". Feeds carry no colour, so
    /// this is filled in by a matching keyword rule — otherwise it stays nil and
    /// the block draws in the neutral "uncategorized" colour.
    var colorHex: String? = nil
    /// Category from the keyword rule that matched, for the dropdown.
    var category: String? = nil

    func intersects(_ from: Date, _ to: Date) -> Bool {
        return end > from && start < to
    }
}

// MARK: - Parser

/// Minimal but practical iCalendar (RFC 5545) parser.
/// Supports: line unfolding, TZID / UTC / floating times, DTEND or DURATION,
/// all-day events, EXDATE, RECURRENCE-ID overrides, and a useful subset of
/// RRULE (FREQ=DAILY|WEEKLY|MONTHLY|YEARLY, INTERVAL, BYDAY, BYMONTHDAY,
/// UNTIL, COUNT) expanded for a single target day.
enum ICS {

    private struct RawEvent {
        var summary: String = ""
        var start: Date?
        var end: Date?
        var isAllDay = false
        var tz: TimeZone = .current
        var rrule: [String: String] = [:]
        var hasRRule = false
        var exdates: [Date] = []
        var recurrenceID: Date?
        var uid: String = ""
        var cancelled = false
    }

    // MARK: Public entry point

    /// Returns every occurrence that overlaps `days` (each element treated as a calendar day).
    static func events(from text: String, days: [Date], calendar: Calendar) -> [CalEvent] {
        let raws = parseRawEvents(text)

        // RECURRENCE-ID overrides, keyed by uid + original start.
        var overrides: [String: RawEvent] = [:]
        for r in raws where r.recurrenceID != nil {
            overrides[key(r.uid, r.recurrenceID!)] = r
        }

        var out: [CalEvent] = []
        for raw in raws {
            guard !raw.cancelled, raw.recurrenceID == nil, let start = raw.start else { continue }
            let end = raw.end ?? start.addingTimeInterval(raw.isAllDay ? 86400 : 1800)

            if !raw.hasRRule {
                out.append(CalEvent(title: raw.summary, start: start, end: end, isAllDay: raw.isAllDay))
                continue
            }

            for day in days {
                guard let occStart = occurrence(of: raw, start: start, on: day, calendar: calendar) else { continue }
                if raw.exdates.contains(where: { abs($0.timeIntervalSince(occStart)) < 60 }) { continue }
                if let ov = overrides[key(raw.uid, occStart)] {
                    guard !ov.cancelled, let s = ov.start else { continue }
                    let e = ov.end ?? s.addingTimeInterval(end.timeIntervalSince(start))
                    out.append(CalEvent(title: ov.summary, start: s, end: e, isAllDay: ov.isAllDay))
                } else {
                    let duration = end.timeIntervalSince(start)
                    out.append(CalEvent(title: raw.summary, start: occStart,
                                        end: occStart.addingTimeInterval(duration),
                                        isAllDay: raw.isAllDay))
                }
            }
        }

        // De-duplicate identical occurrences produced by overlapping day windows.
        var seen = Set<String>()
        return out.filter { e in
            let k = "\(e.title)|\(e.start.timeIntervalSince1970)|\(e.end.timeIntervalSince1970)"
            return seen.insert(k).inserted
        }.sorted { $0.start < $1.start }
    }

    private static func key(_ uid: String, _ date: Date) -> String {
        "\(uid)@\(Int(date.timeIntervalSince1970))"
    }

    // MARK: Line-level parsing

    private static func unfold(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(String(line))
            }
        }
        return lines
    }

    private static func parseRawEvents(_ text: String) -> [RawEvent] {
        var result: [RawEvent] = []
        var current: RawEvent?
        var durationString: String?

        for line in unfold(text) {
            if line.hasPrefix("BEGIN:VEVENT") {
                current = RawEvent()
                durationString = nil
                continue
            }
            if line.hasPrefix("END:VEVENT") {
                if var ev = current {
                    if ev.end == nil, let s = ev.start, let d = durationString,
                       let secs = parseDuration(d) {
                        ev.end = s.addingTimeInterval(secs)
                    }
                    result.append(ev)
                }
                current = nil
                continue
            }
            guard current != nil else { continue }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let nameAndParams = String(line[line.startIndex..<colon])
            let value = String(line[line.index(after: colon)...])
            var parts = nameAndParams.split(separator: ";").map(String.init)
            guard let name = parts.first?.uppercased() else { continue }
            parts.removeFirst()
            var params: [String: String] = [:]
            for p in parts {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }

            switch name {
            case "SUMMARY":
                current!.summary = unescape(value)
            case "STATUS":
                if value.uppercased() == "CANCELLED" { current!.cancelled = true }
            case "UID":
                current!.uid = value
            case "DTSTART":
                if let (d, allDay, tz) = parseDate(value, params) {
                    current!.start = d
                    current!.isAllDay = allDay
                    current!.tz = tz
                }
            case "DTEND":
                if let (d, _, _) = parseDate(value, params) { current!.end = d }
            case "DURATION":
                durationString = value
            case "RECURRENCE-ID":
                if let (d, _, _) = parseDate(value, params) { current!.recurrenceID = d }
            case "EXDATE":
                for piece in value.split(separator: ",").map(String.init) {
                    if let (d, _, _) = parseDate(piece, params) { current!.exdates.append(d) }
                }
            case "RRULE":
                current!.hasRRule = true
                for p in value.split(separator: ";") {
                    let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                    if kv.count == 2 { current!.rrule[kv[0].uppercased()] = kv[1] }
                }
            default:
                break
            }
        }
        return result
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Calendars are expensive to build and a feed uses only a handful of time
    /// zones, so they're kept. Parsing happens on the main thread — this is
    /// reached from the fetch completion, which hops back to main first — so no
    /// locking is needed.
    private static var calendars: [String: Calendar] = [:]
    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    private static func calendar(for zone: TimeZone) -> Calendar {
        if let cached = calendars[zone.identifier] { return cached }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        calendars[zone.identifier] = cal
        return cal
    }

    /// Digits at a fixed offset, e.g. the month out of "20260819T134500".
    private static func number(_ digits: [UInt8], _ start: Int, _ length: Int) -> Int? {
        guard start + length <= digits.count else { return nil }
        var value = 0
        for i in start..<(start + length) {
            let digit = Int(digits[i]) - 48        // "0"
            guard (0...9).contains(digit) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    /// Returns (date, isAllDay, timezone).
    ///
    /// Deliberately hand-rolled rather than `DateFormatter`: an iCalendar stamp
    /// is a fixed run of digits, and a feed with a few hundred events would
    /// otherwise build a formatter — an ICU object — for every DTSTART, DTEND,
    /// EXDATE and UNTIL in the file, several times an hour.
    private static func parseDate(_ value: String, _ params: [String: String]) -> (Date, Bool, TimeZone)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        var tz = TimeZone.current
        if let id = params["TZID"], let t = TimeZone(identifier: id) { tz = t }

        let isUTC = v.hasSuffix("Z")
        let core = isUTC ? String(v.dropLast()) : v
        let digits = Array(core.utf8)

        // Date only: an all-day event, taken at midnight in its own zone. The
        // eight-digit test is on the value as written — "20260819Z" is not a
        // date-only value — matching what the format string used to accept.
        let dateOnly = params["VALUE"]?.uppercased() == "DATE" || (!isUTC && digits.count == 8)
        if dateOnly {
            guard let date = date(from: digits, timed: false, zone: tz) else { return nil }
            return (date, true, tz)
        }

        let zone = isUTC ? utc : tz
        guard let date = date(from: digits, timed: true, zone: zone) else { return nil }
        return (date, false, zone)
    }

    /// `yyyyMMdd`, optionally followed by `THHmmss`.
    ///
    /// A trailing tail is ignored rather than rejected, because that is what
    /// `DateFormatter` did with a fixed format string, and some feeds append
    /// things the format never mentioned. Out-of-range fields *are* rejected,
    /// though: `Calendar` would happily read month 13 as next January, where the
    /// formatter returned nothing, and a silently shifted block is worse than a
    /// missing one.
    private static func date(from digits: [UInt8], timed: Bool, zone: TimeZone) -> Date? {
        guard let year = number(digits, 0, 4),
              let month = number(digits, 4, 2),
              let day = number(digits, 6, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day

        if timed {
            guard digits.count >= 15, digits[8] == UInt8(ascii: "T"),
                  let hour = number(digits, 9, 2),
                  let minute = number(digits, 11, 2),
                  let second = number(digits, 13, 2),
                  (0...23).contains(hour), (0...59).contains(minute),
                  // 59, not 60: the formatter rejected a leap second, and
                  // letting one roll into the next minute would then trip the
                  // round-trip check below anyway.
                  (0...59).contains(second) else { return nil }
            parts.hour = hour
            parts.minute = minute
            parts.second = second
        }

        let cal = calendar(for: zone)
        guard let date = cal.date(from: parts) else { return nil }
        // 30 February normalises to 1 or 2 March rather than failing, so the
        // answer is read back and checked.
        let check = cal.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    /// ISO 8601 duration, e.g. PT1H30M, P1D, PT45M
    private static func parseDuration(_ s: String) -> TimeInterval? {
        var total: Double = 0
        var number = ""
        var inTime = false
        var sawP = false
        for ch in s.uppercased() {
            switch ch {
            case "P": sawP = true
            case "T": inTime = true
            case "-": return nil
            case "0"..."9": number.append(ch)
            default:
                guard let n = Double(number) else { return nil }
                number = ""
                switch ch {
                case "W": total += n * 604800
                case "D": total += n * 86400
                case "H": total += n * 3600
                case "M": total += inTime ? n * 60 : n * 2_592_000
                case "S": total += n
                default: return nil
                }
            }
        }
        return sawP ? total : nil
    }

    // MARK: Recurrence

    private static let weekdayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    /// If the rule produces an occurrence on `day`, return its start date.
    private static func occurrence(of raw: RawEvent, start: Date, on day: Date, calendar: Calendar) -> Date? {
        var cal = calendar
        cal.timeZone = raw.tz

        let startDay = cal.startOfDay(for: start)
        let targetDay = cal.startOfDay(for: day)
        if targetDay < startDay { return nil }

        let rule = raw.rrule
        let freq = (rule["FREQ"] ?? "DAILY").uppercased()
        let interval = max(1, Int(rule["INTERVAL"] ?? "1") ?? 1)

        // UNTIL
        if let untilStr = rule["UNTIL"], let (until, _, _) = parseDate(untilStr, [:]) {
            if targetDay > until { return nil }
        }

        let byDay: [Int] = (rule["BYDAY"] ?? "").split(separator: ",").compactMap {
            let code = String($0).suffix(2).uppercased()
            return weekdayCodes[String(code)]
        }
        let byMonthDay: [Int] = (rule["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }

        let dayDiff = cal.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
        var occurrenceIndex = 0
        var matches = false

        switch freq {
        case "DAILY":
            matches = dayDiff % interval == 0
            if matches, !byDay.isEmpty {
                matches = byDay.contains(cal.component(.weekday, from: targetDay))
            }
            occurrenceIndex = dayDiff / max(interval, 1)

        case "WEEKLY":
            let ws1 = startOfWeek(startDay, cal), ws2 = startOfWeek(targetDay, cal)
            let weekDiff = (cal.dateComponents([.day], from: ws1, to: ws2).day ?? 0) / 7
            guard weekDiff % interval == 0 else { return nil }
            let targetWeekday = cal.component(.weekday, from: targetDay)
            if byDay.isEmpty {
                matches = targetWeekday == cal.component(.weekday, from: startDay)
            } else {
                matches = byDay.contains(targetWeekday)
            }
            occurrenceIndex = (weekDiff / max(interval, 1)) * max(byDay.count, 1)

        case "MONTHLY":
            let monthDiff = cal.dateComponents([.month], from: startDay, to: targetDay).month ?? 0
            guard monthDiff % interval == 0 else { return nil }
            let targetDom = cal.component(.day, from: targetDay)
            if !byMonthDay.isEmpty {
                matches = byMonthDay.contains(targetDom)
            } else if !byDay.isEmpty {
                // nth weekday of month, e.g. 2TU / -1FR
                matches = matchesNthWeekday(rule["BYDAY"] ?? "", targetDay, cal)
            } else {
                matches = targetDom == cal.component(.day, from: startDay)
            }
            occurrenceIndex = monthDiff / max(interval, 1)

        case "YEARLY":
            let yearDiff = cal.dateComponents([.year], from: startDay, to: targetDay).year ?? 0
            guard yearDiff % interval == 0 else { return nil }
            matches = cal.component(.month, from: targetDay) == cal.component(.month, from: startDay)
                && cal.component(.day, from: targetDay) == cal.component(.day, from: startDay)
            occurrenceIndex = yearDiff / max(interval, 1)

        default:
            return nil
        }

        guard matches else { return nil }
        if let countStr = rule["COUNT"], let count = Int(countStr), occurrenceIndex >= count { return nil }

        // Re-apply the original time-of-day on the target date.
        let t = cal.dateComponents([.hour, .minute, .second], from: start)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: t.second ?? 0, of: targetDay)
    }

    private static func startOfWeek(_ d: Date, _ cal: Calendar) -> Date {
        let weekday = cal.component(.weekday, from: d)
        return cal.date(byAdding: .day, value: -(weekday - 1), to: cal.startOfDay(for: d))!
    }

    private static func matchesNthWeekday(_ byDay: String, _ target: Date, _ cal: Calendar) -> Bool {
        let targetWeekday = cal.component(.weekday, from: target)
        let dom = cal.component(.day, from: target)
        let range = cal.range(of: .day, in: .month, for: target)?.count ?? 30
        for token in byDay.split(separator: ",") {
            let s = String(token).uppercased()
            let code = String(s.suffix(2))
            guard let wd = weekdayCodes[code], wd == targetWeekday else { continue }
            let nStr = String(s.dropLast(2))
            guard let n = Int(nStr) else { return true }  // plain weekday, every week
            if n > 0 {
                if (dom - 1) / 7 + 1 == n { return true }
            } else {
                let fromEnd = (range - dom) / 7 + 1
                if fromEnd == -n { return true }
            }
        }
        return false
    }
}
