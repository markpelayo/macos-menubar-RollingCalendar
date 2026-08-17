import Foundation

/// Turns whatever calendar link a person pastes into a fetchable iCal feed URL.
///
/// Accepts:
///   • Google embed links   …/calendar/embed?src=you@gmail.com&ctz=Europe/London
///   • Google newembed links …/calendar/u/0/newembed?src=you@gmail.com&ctz=…
///   • Direct .ics URLs     …/calendar/ical/you%40gmail.com/public/basic.ics
///   • webcal:// links
///   • A bare calendar address (you@gmail.com, or a …@group.calendar.google.com id)
enum CalendarSource {

    static func toICS(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if s.lowercased().hasPrefix("webcal://") {
            s = "https://" + s.dropFirst("webcal://".count)
        }

        // Already a feed.
        if s.lowercased().hasSuffix(".ics") { return s }

        // Embed / newembed / any URL carrying ?src=
        if let src = queryValue("src", in: s) {
            return feedURL(forCalendarID: src)
        }

        // Bare calendar address.
        if !s.contains("://"), !s.contains("/"), s.contains("@") {
            return feedURL(forCalendarID: s)
        }

        // Some other http(s) URL — try it verbatim.
        if s.lowercased().hasPrefix("http") { return s }

        return nil
    }

    /// `ctz=Europe/London` → TimeZone, when the link carries one.
    static func timeZone(from input: String) -> TimeZone? {
        guard let ctz = queryValue("ctz", in: input) else { return nil }
        return TimeZone(identifier: ctz)
    }

    /// Human-readable name of the calendar, for the menu.
    static func label(for input: String) -> String {
        if let src = queryValue("src", in: input) { return src }
        if !input.contains("://"), input.contains("@") { return input }
        if let range = input.range(of: "/calendar/ical/"),
           let end = input.range(of: "/", range: range.upperBound..<input.endIndex) {
            let raw = String(input[range.upperBound..<end.lowerBound])
            return raw.removingPercentEncoding ?? raw
        }
        return input
    }

    /// Validates without hitting the network. Returns nil if it looks usable.
    static func problem(with input: String) -> String? {
        guard let ics = toICS(input) else {
            return "That doesn't look like a calendar link. Paste a Google Calendar embed link, a public .ics URL, or a calendar address like you@gmail.com."
        }
        guard let url = URL(string: ics), let scheme = url.scheme?.lowercased() else {
            return "Couldn't turn that into a valid URL."
        }
        if scheme == "file" {
            return FileManager.default.fileExists(atPath: url.path)
                ? nil : "No file at \(url.path)"
        }
        guard scheme.hasPrefix("http"), url.host != nil else {
            return "Couldn't turn that into a valid URL."
        }
        return nil
    }

    // MARK: - Helpers

    private static func feedURL(forCalendarID id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
        return "https://calendar.google.com/calendar/ical/\(encoded)/public/basic.ics"
    }

    private static func queryValue(_ name: String, in urlString: String) -> String? {
        guard let q = urlString.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, kv[0].lowercased() == name.lowercased() else { continue }
            let value = kv[1].replacingOccurrences(of: "+", with: " ")
            let decoded = value.removingPercentEncoding ?? value
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }
}
