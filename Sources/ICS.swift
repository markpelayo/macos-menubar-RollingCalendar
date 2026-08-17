import Foundation

// MARK: - Model

struct CalEvent {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// Hex background from Google (e.g. "#7ae7bf"). Only the API provides this —
    /// .ics feeds carry no colour information, so it stays nil in that mode.
    var colorHex: String? = nil

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

    /// Returns (date, isAllDay, timezone)
    private static func parseDate(_ value: String, _ params: [String: String]) -> (Date, Bool, TimeZone)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        var tz = TimeZone.current
        if let id = params["TZID"], let t = TimeZone(identifier: id) { tz = t }

        if params["VALUE"]?.uppercased() == "DATE" || v.count == 8 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd"
            f.timeZone = tz
            guard let d = f.date(from: v) else { return nil }
            return (d, true, tz)
        }

        let isUTC = v.hasSuffix("Z")
        let core = isUTC ? String(v.dropLast()) : v
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.timeZone = isUTC ? TimeZone(identifier: "UTC")! : tz
        guard let d = f.date(from: core) else { return nil }
        return (d, false, isUTC ? TimeZone(identifier: "UTC")! : tz)
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
