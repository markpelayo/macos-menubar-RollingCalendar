import AppKit

/// A single row of the imported CSV: "when an event's title contains this
/// keyword, paint its block this colour".
struct KeywordRule {
    let category: String
    let colorName: String
    let colorHex: String
    let keyword: String
    /// Lower-cased, punctuation flattened to spaces — what matching runs on.
    let normalized: String

    var wordCount: Int { normalized.split(separator: " ").count }
    var color: NSColor? { NSColor(hexString: colorHex) }
}

/// Keyword-driven colouring.
///
/// The important part is precedence. "meal" and "meal prep" would both match
/// "Meal prep for the week", so the longer phrase has to win, otherwise a
/// two-word rule could never be reached. Rules are therefore sorted by word
/// count first and matched in that order, and separators are normalised so
/// "meal prep", "meal-prep" and "meal_prep" are all the same keyword.
enum KeywordRules {

    private static let rulesKey = "keywordRules"
    private static let sourceKey = "keywordRulesSource"
    private static var cache: [KeywordRule]?

    // MARK: Stored rules

    /// Already in match order: longest phrase first.
    static var rules: [KeywordRule] {
        if let cache { return cache }
        let raw = UserDefaults.standard.array(forKey: rulesKey) as? [[String: String]] ?? []
        let list = raw.compactMap { d -> KeywordRule? in
            guard let keyword = d["keyword"], let hex = d["hex"] else { return nil }
            return KeywordRule(category: d["category"] ?? "",
                               colorName: d["name"] ?? "",
                               colorHex: hex,
                               keyword: keyword,
                               normalized: normalize(keyword))
        }
        cache = list
        return list
    }

    /// File the rules came from, for the menu.
    static var sourceName: String? { UserDefaults.standard.string(forKey: sourceKey) }

    static let sampleSourceName = "the built-in sample"

    /// True when the rules are the ones a fresh launch would have seeded, so
    /// "everything is at its defaults" can be asked as one question.
    static var isSample: Bool { sourceName == sampleSourceName }

    static func save(_ list: [KeywordRule], from source: String) {
        UserDefaults.standard.set(prioritised(list).map {
            ["category": $0.category, "name": $0.colorName, "hex": $0.colorHex, "keyword": $0.keyword]
        }, forKey: rulesKey)
        UserDefaults.standard.set(source, forKey: sourceKey)
        cache = nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: rulesKey)
        UserDefaults.standard.removeObject(forKey: sourceKey)
        cache = nil
    }

    /// On the very first launch, start with the sample rules so the app looks
    /// configured rather than uniformly grey. Only once — after that, cleared
    /// stays cleared, which is the whole point of the Clear command.
    static func seedSampleRulesIfFirstRun() {
        let seeded = "keywordRulesSeeded"
        guard !UserDefaults.standard.bool(forKey: seeded) else { return }
        UserDefaults.standard.set(true, forKey: seeded)
        guard rules.isEmpty else { return }
        let result = parse(csv: sampleCSV)
        guard result.problem == nil, !result.rules.isEmpty else { return }
        save(result.rules, from: sampleSourceName)
    }

    /// Categories in the order they first appear, for the menu.
    static var categories: [(name: String, colorHex: String, count: Int)] {
        var order: [String] = []
        var byName: [String: (hex: String, count: Int)] = [:]
        for rule in rules {
            if byName[rule.category] == nil {
                order.append(rule.category)
                byName[rule.category] = (rule.colorHex, 0)
            }
            byName[rule.category]?.count += 1
        }
        return order.compactMap { name in
            guard let e = byName[name] else { return nil }
            return (name, e.hex, e.count)
        }
    }

    // MARK: Matching

    /// Everything that isn't a letter or digit becomes a space, so "Meal-Prep",
    /// "meal prep" and "Focus Work | Learn (2H)" all reduce to plain words.
    static func normalize(_ text: String) -> String {
        let flattened = text.lowercased().map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        }
        return String(flattened).split(separator: " ").joined(separator: " ")
    }

    /// Longest phrase first; ties broken by length, then by file order.
    static func prioritised(_ list: [KeywordRule]) -> [KeywordRule] {
        list.enumerated().sorted { a, b in
            if a.element.wordCount != b.element.wordCount {
                return a.element.wordCount > b.element.wordCount
            }
            if a.element.normalized.count != b.element.normalized.count {
                return a.element.normalized.count > b.element.normalized.count
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// First rule whose keyword appears in the title as whole words.
    static func rule(for title: String) -> KeywordRule? {
        let haystack = " " + normalize(title) + " "
        return rules.first { !$0.normalized.isEmpty && haystack.contains(" \($0.normalized) ") }
    }

    /// Whole-word test, used for things like finding the day's anchor block.
    static func title(_ title: String, contains keyword: String) -> Bool {
        let needle = normalize(keyword)
        guard !needle.isEmpty else { return false }
        return (" " + normalize(title) + " ").contains(" \(needle) ")
    }

    /// Repaint events whose titles match a rule. Events with no match keep
    /// whatever colour they already had.
    static func apply(to events: [CalEvent]) -> [CalEvent] {
        guard !rules.isEmpty else { return events }
        return events.map { event in
            guard let match = rule(for: event.title) else { return event }
            var copy = event
            copy.colorHex = match.colorHex
            copy.category = match.category.isEmpty ? nil : match.category
            return copy
        }
    }

    // MARK: The built-in sample

    /// A working set of rules, so colours are one click away — and the very same
    /// text can be saved out as a CSV to edit and re-import.
    static let sampleCSV = """
    category,color (color name or hex),keyword
    Focus Work | Learn,blue,focus
    Focus Work | Learn,blue,work
    Focus Work | Learn,blue,learn
    Focus Work | Learn,blue,deep tasks
    Focus Work | Learn,blue,writing
    Focus Work | Learn,blue,coding
    Focus Work | Learn,blue,project creation
    Meetings | Urgency,red,meeting
    Meetings | Urgency,red,deadline
    Meetings | Urgency,red,call
    Meetings | Urgency,red,calls
    Meetings | Urgency,red,sync
    Meetings | Urgency,red,planning
    Meetings | Urgency,red,syncs
    Meetings | Urgency,red,client syncs
    Meetings | Urgency,red,standup
    Meetings | Urgency,red,interview
    Meetings | Urgency,red,high-priority deadlines
    Meetings | Urgency,red,training
    Health | Rest,green,sleep
    Health | Rest,green,meal
    Health | Rest,green,nap
    Health | Rest,green,lunch
    Health | Rest,green,exercise
    Health | Rest,green,me-time
    Health | Rest,green,gym sessions
    Health | Rest,green,walks
    Health | Rest,green,mental breaks
    Admin | Errands,yellow,email clearing
    Admin | Errands,yellow,update
    Admin | Errands,yellow,to-do list
    Admin | Errands,yellow,minor chores
    Personal | Growth,purple,lecture
    Personal | Growth,purple,meal prep
    Personal | Growth,purple,family time
    Personal | Growth,purple,reading
    Personal | Growth,purple,self development
    Personal | Growth,purple,personal development
    Personal | Growth,purple,church
    Travel | Buffers,teal,commute
    Travel | Buffers,teal,buffer
    Travel | Buffers,teal,out of office
    """

    // MARK: CSV import

    struct ImportResult {
        var rules: [KeywordRule] = []
        var skippedRows = 0
        var duplicates: [String] = []
        /// Colour values that were neither a hex nor a name we know.
        var unknownColours: [String] = []
        var problem: String?
        /// What the parser actually saw — shown when an import fails, so the
        /// reason is visible rather than guessable.
        var diagnostics: String = ""
    }

    /// Columns are found by name where possible, and worked out from the data
    /// where not — so header wording, column order, a missing header row and
    /// Excel's habit of re-saving with semicolons or tabs are all survivable.
    static func parse(csv rawText: String) -> ImportResult {
        var result = ImportResult()

        // Swift Characters are grapheme clusters, and "\r\n" is *one* of them —
        // so iterating a CRLF file never yields a bare "\n" to break rows on.
        // Flattening line endings first is what makes the rest of this work.
        let text = normalizeLineEndings(rawText)
        let delimiter = detectDelimiter(text)
        let allRows = parseRows(text, delimiter: delimiter)
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = allRows.first else {
            result.problem = "That file has no rows in it."
            return result
        }

        func column(_ prefixes: [String]) -> Int? {
            header.firstIndex {
                let name = normalize($0)
                return prefixes.contains { name.hasPrefix($0) }
            }
        }
        // A column mentioning "hex" wins, so an older file with separate name
        // and hex columns still takes the hex. Otherwise any colour column.
        var colourCol = header.firstIndex { normalize($0).contains("hex") }
            ?? column(["color", "colour"])
        var keywordCol = column(["keyword", "term", "phrase"])
        var categoryCol = column(["category", "group"])

        // If neither was named, row one is probably data, not a header.
        let hasHeader = colourCol != nil || keywordCol != nil
        let rows = hasHeader ? Array(allRows.dropFirst()) : allRows

        if colourCol == nil || keywordCol == nil {
            let guessed = inferColumns(rows)
            colourCol = colourCol ?? guessed.colour
            keywordCol = keywordCol ?? guessed.keyword
            categoryCol = categoryCol ?? guessed.category
        }

        result.diagnostics = describe(delimiter: delimiter, header: header,
                                      firstRow: rows.first, colour: colourCol,
                                      keyword: keywordCol, category: categoryCol)

        guard let keywordCol, let colourCol, keywordCol != colourCol else {
            result.problem = "Couldn't work out which column is which. Give it a header row with "
                + "“keyword” and “color” columns, or make sure one column holds colours "
                + "(#28CD41 or a name like green).\n\n" + result.diagnostics
            return result
        }

        var seen = Set<String>()
        for row in rows {
            func field(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let keyword = field(keywordCol)
            let colour = field(colourCol)
            // Files often use blank rows as spacers between categories.
            if keyword.isEmpty, colour.isEmpty { continue }
            guard !keyword.isEmpty, let hex = resolveColour(colour) else {
                if !keyword.isEmpty || !colour.isEmpty {
                    result.skippedRows += 1
                    if !colour.isEmpty, NSColor(hexString: colour) == nil,
                       result.unknownColours.count < 6, !result.unknownColours.contains(colour) {
                        result.unknownColours.append(colour)
                    }
                }
                continue
            }
            let normalized = normalize(keyword)
            guard !normalized.isEmpty else { result.skippedRows += 1; continue }
            guard seen.insert(normalized).inserted else {
                result.duplicates.append(keyword)
                continue
            }
            result.rules.append(KeywordRule(category: field(categoryCol),
                                            colorName: colour,
                                            colorHex: hex,
                                            keyword: keyword,
                                            normalized: normalized))
        }

        if result.rules.isEmpty, result.problem == nil {
            result.problem = "Found the columns, but no row had both a keyword and a usable colour."
                + (result.unknownColours.isEmpty ? ""
                   : "\n\nThese weren't recognised as colours: "
                     + result.unknownColours.prefix(4).joined(separator: ", "))
                + "\n\n" + result.diagnostics
        }
        result.rules = prioritised(result.rules)
        return result
    }

    // MARK: Working out the shape of the file

    /// CRLF (Windows and Excel) and lone CR (very old Mac files) both become LF,
    /// so downstream code only ever has one line ending to think about.
    private static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Excel writes semicolons or tabs depending on locale, so don't assume commas.
    private static func detectDelimiter(_ text: String) -> Character {
        let sample = text.split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: true)
            .prefix(4).joined(separator: "\n")
        let counts: [(Character, Int)] = [
            (",", sample.filter { $0 == "," }.count),
            (";", sample.filter { $0 == ";" }.count),
            ("\t", sample.filter { $0 == "\t" }.count)
        ]
        return counts.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? ","
    }

    /// No usable header? Work out the columns from the values: the colour column
    /// is whichever one holds colours, and the keyword column is the wordiest of
    /// what's left.
    private static func inferColumns(_ rows: [[String]]) -> (colour: Int?, keyword: Int?, category: Int?) {
        let width = rows.prefix(20).map(\.count).max() ?? 0
        guard width > 1 else { return (nil, nil, nil) }
        let sample = Array(rows.prefix(20))

        func value(_ row: [String], _ i: Int) -> String {
            i < row.count ? row[i].trimmingCharacters(in: .whitespaces) : ""
        }

        var colourScore = [Int](repeating: 0, count: width)
        var distinct = [Set<String>](repeating: [], count: width)
        var wordiness = [Int](repeating: 0, count: width)
        for row in sample {
            for i in 0..<width {
                let v = value(row, i)
                guard !v.isEmpty else { continue }
                if resolveColour(v) != nil { colourScore[i] += 1 }
                distinct[i].insert(normalize(v))
                wordiness[i] += normalize(v).split(separator: " ").count
            }
        }
        let colour = colourScore.indices.max { colourScore[$0] < colourScore[$1] }
            .flatMap { colourScore[$0] > 0 ? $0 : nil }

        // Keywords vary the most; categories repeat.
        let others = (0..<width).filter { $0 != colour }
        let keyword = others.max { distinct[$0].count < distinct[$1].count }
        let category = others.filter { $0 != keyword }
            .min { distinct[$0].count < distinct[$1].count }
        return (colour, keyword, category)
    }

    private static func describe(delimiter: Character, header: [String], firstRow: [String]?,
                                 colour: Int?, keyword: Int?, category: Int?) -> String {
        let names = ["comma": ",", "semicolon": ";", "tab": "\t"]
        let delimiterName = names.first { $0.value == String(delimiter) }?.key ?? "comma"
        func line(_ label: String, _ index: Int?) -> String {
            guard let index else { return "\(label): not found" }
            let name = index < header.count ? header[index] : "column \(index + 1)"
            return "\(label): column \(index + 1) (\(name))"
        }
        var lines = ["Read as \(delimiterName)-separated, \(header.count) columns.",
                     line("keyword", keyword),
                     line("color", colour),
                     line("category", category)]
        if let firstRow {
            lines.append("First data row: " + firstRow.prefix(4).joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    /// One colour column, holding either a hex or a name. Returns the hex to
    /// store, or nil if it's neither.
    static func resolveColour(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if NSColor(hexString: text) != nil {
            return text.hasPrefix("#") ? text.uppercased() : "#" + text.uppercased()
        }
        return namedColour(text)
    }

    /// Plain colour names, mapped to macOS's own system colours. Blue is blue,
    /// black is black — no house palette reinterpreting what you asked for.
    static func namedColour(_ name: String) -> String? {
        switch normalize(name) {
        case "red": return "#FF3B30"
        case "orange": return "#FF9500"
        case "yellow": return "#FFCC00"
        case "green": return "#28CD41"
        case "mint": return "#00C7BE"
        case "teal": return "#30B0C7"
        case "cyan", "aqua": return "#32ADE6"
        case "blue": return "#007AFF"
        case "indigo": return "#5856D6"
        case "purple", "violet": return "#AF52DE"
        case "pink", "magenta", "fuchsia": return "#FF2D55"
        case "brown": return "#A2845E"
        case "gray", "grey": return "#8E8E93"
        case "light gray", "light grey", "lightgray", "lightgrey", "silver": return "#C7C7CC"
        case "dark gray", "dark grey", "darkgray", "darkgrey", "charcoal": return "#48484A"
        case "black": return "#000000"
        case "white": return "#FFFFFF"
        default: return nil
        }
    }

    /// Minimal RFC 4180: quoted fields and doubled quotes. Expects line endings
    /// already flattened to LF by `normalizeLineEndings`.
    private static func parseRows(_ rawText: String, delimiter: Character = ",") -> [[String]] {
        let text = normalizeLineEndings(rawText)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.replacingOccurrences(of: "\u{FEFF}", with: "").makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else {
                    field.append(ch)
                }
                continue
            }
            switch ch {
            case "\"": inQuotes = true
            case delimiter: endField()
            case "\n": endRow()
            case "\r": break            // CRLF: the \n does the work
            default: field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
