import Foundation

/// Synthetic 15-minute blocks, generated in-app.
///
/// This exists so the strip can be tested without depending on Google at all —
/// no import, no OAuth, no public feed. Blocks are exactly 15 minutes,
/// back-to-back with no overlaps and no gaps, aligned to :00/:15/:30/:45,
/// and coloured from Google Calendar's own palette.
enum DemoData {

    /// Google Calendar's event colours (colorId 1…11).
    private static let palette: [String: String] = [
        "Lavender": "#7986cb", "Sage": "#33b679", "Grape": "#8e24aa",
        "Flamingo": "#e67c73", "Banana": "#f6c026", "Tangerine": "#f5511d",
        "Peacock": "#039be5", "Graphite": "#616161", "Blueberry": "#3f51b5",
        "Basil": "#0b8043", "Tomato": "#d60000"
    ]

    private struct Slot {
        let title: String
        let colorName: String
    }

    /// A plausible day, so the strip looks like a real schedule.
    private static func slot(localMinute: Int) -> Slot {
        let hour = localMinute / 60
        let minute = localMinute % 60
        switch hour {
        case 0..<6:
            return Slot(title: "Sleep", colorName: "Blueberry")
        case 6:
            return Slot(title: "Breakfast", colorName: "Basil")
        case 7..<12:
            let titles = ["Focus Work", "Deep Work", "Email triage", "Code review", "Standup"]
            return Slot(title: titles[(hour - 7) % titles.count], colorName: "Peacock")
        case 12:
            return Slot(title: "Lunch", colorName: "Basil")
        case 13..<15:
            let titles = ["Focus Work", "Customer call", "Write docs", "Ticket cleanup"]
            return Slot(title: titles[(hour - 13) % titles.count], colorName: "Peacock")
        case 15:
            return minute < 30
                ? Slot(title: "Afternoon break", colorName: "Banana")
                : Slot(title: "Deep Work", colorName: "Peacock")
        case 16..<18:
            let titles = ["1:1 sync", "Roadmap review"]
            return Slot(title: titles[(hour - 16) % titles.count], colorName: "Tangerine")
        case 18:
            return Slot(title: "Dinner", colorName: "Basil")
        case 19:
            return Slot(title: "Me Time", colorName: "Banana")
        case 20..<22:
            return Slot(title: "Evening project", colorName: "Grape")
        case 22:
            return minute < 30
                ? Slot(title: "Snack", colorName: "Flamingo")
                : Slot(title: "Wind down", colorName: "Lavender")
        default:
            return Slot(title: "Wind down", colorName: "Lavender")
        }
    }

    /// 15-minute blocks covering the given day, plus the day either side so the
    /// strip never runs out of blocks at its edges.
    static func events(around date: Date, timeZone: TimeZone) -> [CalEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        var out: [CalEvent] = []
        for dayOffset in -1...1 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let midnight = cal.startOfDay(for: day)
            for i in 0..<96 {
                let localMinute = i * 15
                let start = midnight.addingTimeInterval(Double(localMinute) * 60)
                let end = start.addingTimeInterval(15 * 60)
                let s = slot(localMinute: localMinute)
                let hh = localMinute / 60, mm = localMinute % 60
                out.append(CalEvent(
                    title: String(format: "%@ %02d:%02d (15M)", s.title, hh, mm),
                    start: start,
                    end: end,
                    isAllDay: false,
                    colorHex: palette[s.colorName]
                ))
            }
        }
        return out.sorted { $0.start < $1.start }
    }
}
