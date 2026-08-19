import Foundation

/// A realistic time-blocked day, generated in-app.
///
/// This exists so the strip can be tried without any calendar at all — no feed,
/// no import. It supplies only what a calendar would: times and names. Colour
/// comes from the same keyword rules as a real feed, so clearing those turns the
/// demo grey exactly as it would turn a real calendar grey.
enum DemoData {

    /// One block of the template day. Minutes are counted from local midnight,
    /// and `end` may pass 1440 for a block that runs past midnight.
    private struct Block {
        let start: Int
        let end: Int
        let title: String
    }

    /// A day that starts and ends on sleep, so the dropdown's sleep-to-sleep
    /// cycle has something real to anchor to. Names are chosen to match the
    /// keywords in `KeywordRules.sampleCSV`.
    ///
    /// Two deliberate collisions, because a schedule without them wouldn't show
    /// what the ⚠ badges are for: a double-booked call at 15:00, and a
    /// three-deep stretch at 16:15 where an interview and a standup both land
    /// inside a focus block.
    private static let day: [Block] = [
        Block(start:  270, end:  690, title: "Sleep"),
        Block(start:  690, end:  720, title: "Stretching | Exercise | Breakfast"),
        Block(start:  720, end:  750, title: "Read Tasks | Make a TO-DO list"),
        Block(start:  750, end:  870, title: "Focus Work | Learn"),
        Block(start:  870, end:  900, title: "Update tasks | Update the TO-DO list"),

        // 15:00 — two calls booked over each other.
        Block(start:  900, end:  930, title: "Team Sync | Weekly Planning"),
        Block(start:  900, end:  920, title: "Client Call | Acme Renewal"),

        // 15:30–17:00 focus, with an interview and a standup dropped inside it.
        Block(start:  930, end: 1020, title: "Focus Work | Learn"),
        Block(start:  960, end:  990, title: "Interview | Candidate Screen"),
        Block(start:  975, end:  990, title: "Standup | Team Check-in"),

        Block(start: 1020, end: 1050, title: "Power Nap"),
        Block(start: 1050, end: 1080, title: "Lunch"),
        Block(start: 1080, end: 1140, title: "Finalising Work | Learn"),
        Block(start: 1140, end: 1200, title: "Me Time | Exercise | Bath | Rest"),
        Block(start: 1200, end: 1230, title: "Reading | Self Development"),
        Block(start: 1230, end: 1680, title: "Corporate Work")
    ]

    /// The template repeated across yesterday, today and the next two days, so
    /// neither the strip nor the dropdown's cycle runs out of blocks.
    static func events(around date: Date, timeZone: TimeZone) -> [CalEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        var out: [CalEvent] = []
        for dayOffset in -1...2 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let midnight = cal.startOfDay(for: day)
            for block in Self.day {
                // No colour and no category: keyword rules decide both, just as
                // they do for a real calendar.
                out.append(CalEvent(
                    title: block.title,
                    start: midnight.addingTimeInterval(Double(block.start) * 60),
                    end: midnight.addingTimeInterval(Double(block.end) * 60),
                    isAllDay: false
                ))
            }
        }
        return out.sorted { $0.start < $1.start }
    }
}
