import Foundation

struct GCalendarInfo {
    let id: String
    let summary: String
    let primary: Bool
    let backgroundColor: String?
}

/// Thin read-only wrapper over Google Calendar API v3.
/// Google expands recurrence for us (`singleEvents=true`), and — unlike the
/// .ics export — returns each event's `colorId`, which is where the colours live.
enum GoogleCalendarAPI {

    private static let base = "https://www.googleapis.com/calendar/v3"

    // MARK: Calendar list

    private struct CalendarListResponse: Decodable {
        struct Item: Decodable {
            let id: String
            let summary: String?
            let primary: Bool?
            let backgroundColor: String?
            let accessRole: String?
        }
        let items: [Item]?
    }

    static func calendarList(token: String, done: @escaping (Result<[GCalendarInfo], Error>) -> Void) {
        get("\(base)/users/me/calendarList?minAccessRole=reader&fields=items(id,summary,primary,backgroundColor,accessRole)",
            token: token, as: CalendarListResponse.self) { result in
            done(result.map { resp in
                (resp.items ?? []).map {
                    GCalendarInfo(id: $0.id,
                                  summary: $0.summary ?? $0.id,
                                  primary: $0.primary ?? false,
                                  backgroundColor: $0.backgroundColor)
                }
            })
        }
    }

    // MARK: Colour palette

    private struct ColorsResponse: Decodable {
        struct Entry: Decodable { let background: String?; let foreground: String? }
        let event: [String: Entry]?
        let calendar: [String: Entry]?
    }

    /// colorId → background hex, e.g. "6" → "#ffb878"
    static func eventPalette(token: String, done: @escaping (Result<[String: String], Error>) -> Void) {
        get("\(base)/colors", token: token, as: ColorsResponse.self) { result in
            done(result.map { resp in
                var map: [String: String] = [:]
                for (k, v) in resp.event ?? [:] { if let bg = v.background { map[k] = bg } }
                return map
            })
        }
    }

    // MARK: Events

    private struct EventsResponse: Decodable {
        struct When: Decodable { let date: String?; let dateTime: String?; let timeZone: String? }
        struct Item: Decodable {
            let summary: String?
            let status: String?
            let colorId: String?
            let start: When?
            let end: When?
            let transparency: String?
        }
        let items: [Item]?
    }

    /// Events overlapping [from, to), recurrence already expanded by Google.
    /// `palette` maps colorId → hex; `fallbackColor` is the calendar's own colour.
    static func events(calendarID: String,
                       token: String,
                       from: Date,
                       to: Date,
                       palette: [String: String],
                       fallbackColor: String?,
                       done: @escaping (Result<[CalEvent], Error>) -> Void) {

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let idEncoded = calendarID.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? calendarID

        var comps = URLComponents(string: "\(base)/calendars/\(idEncoded)/events")!
        comps.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: iso.string(from: from)),
            URLQueryItem(name: "timeMax", value: iso.string(from: to)),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "fields", value: "items(summary,status,colorId,transparency,start,end)")
        ]
        guard let url = comps.url else {
            done(.failure(APIError.message("Couldn't build the events URL.")))
            return
        }

        get(url.absoluteString, token: token, as: EventsResponse.self) { result in
            done(result.map { resp in
                (resp.items ?? []).compactMap { item -> CalEvent? in
                    if (item.status ?? "confirmed").lowercased() == "cancelled" { return nil }
                    guard let s = item.start, let e = item.end else { return nil }

                    let hex = item.colorId.flatMap { palette[$0] } ?? fallbackColor

                    if let sd = s.dateTime, let ed = e.dateTime,
                       let start = parseDateTime(sd), let end = parseDateTime(ed) {
                        return CalEvent(title: item.summary ?? "(no title)",
                                        start: start, end: end, isAllDay: false, colorHex: hex)
                    }
                    if let sDay = s.date, let eDay = e.date,
                       let start = parseDay(sDay, s.timeZone), let end = parseDay(eDay, e.timeZone) {
                        return CalEvent(title: item.summary ?? "(no title)",
                                        start: start, end: end, isAllDay: true, colorHex: hex)
                    }
                    return nil
                }
            })
        }
    }

    // MARK: - Plumbing

    enum APIError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    private static func get<T: Decodable>(_ urlString: String,
                                          token: String,
                                          as type: T.Type,
                                          done: @escaping (Result<T, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            done(.failure(APIError.message("Bad request URL."))); return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 25

        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error { done(.failure(error)); return }
                guard let data else { done(.failure(APIError.message("Empty response."))); return }

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let detail = (try? JSONSerialization.jsonObject(with: data))
                        .flatMap { ($0 as? [String: Any])?["error"] as? [String: Any] }
                        .flatMap { $0["message"] as? String }
                    done(.failure(APIError.message("Google API \(http.statusCode): \(detail ?? "request failed")")))
                    return
                }
                do {
                    done(.success(try JSONDecoder().decode(T.self, from: data)))
                } catch {
                    done(.failure(APIError.message("Couldn't read Google's response.")))
                }
            }
        }.resume()
    }

    private static func parseDateTime(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    private static func parseDay(_ s: String, _ tzID: String?) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = tzID.flatMap { TimeZone(identifier: $0) } ?? Config.displayTimeZone
        return f.date(from: s)
    }
}
