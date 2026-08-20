import AppKit
import AVFoundation
import Foundation
import UserNotifications

/// A heads-up shortly before a block starts: a system sound, the block name
/// spoken aloud, or both.
///
/// Nothing here is on by default. An alert needs three things to happen at all —
/// a lead time, at least one way of announcing itself, and a category that's
/// been left switched on — and `isEnabled` is the single test for the first two.
enum Alerts {

    // MARK: - When

    /// Lead time in seconds. Zero is off, which is where everyone starts.
    static var lead: Int { UserDefaults.standard.integer(forKey: "alertLead") }

    /// The two obvious choices; anything else comes from Custom…
    static let leadPresets: [(title: String, seconds: Int)] = [
        ("1 minute before", 60),
        ("5 minutes before", 300)
    ]

    static func setLead(_ seconds: Int) {
        UserDefaults.standard.set(max(0, seconds), forKey: "alertLead")
        fired.removeAll()   // a new lead time means nothing counts as announced
    }

    /// "1 minute", "5 minutes", "90 seconds" — used in the menu and spoken aloud,
    /// so the two can never disagree.
    static func leadPhrase(_ seconds: Int = Alerts.lead) -> String {
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    // MARK: - How

    static var playsSound: Bool { UserDefaults.standard.bool(forKey: "alertSound") }
    static var speaks: Bool { UserDefaults.standard.bool(forKey: "alertSpeech") }

    static func setPlaysSound(_ on: Bool) { UserDefaults.standard.set(on, forKey: "alertSound") }
    static func setSpeaks(_ on: Bool) { UserDefaults.standard.set(on, forKey: "alertSpeech") }

    /// Ten of the sounds macOS already ships in /System/Library/Sounds, quietest
    /// first. Nothing is bundled with the app, and a name that no longer exists
    /// simply falls back to the system beep.
    static let sounds = [
        "Tink", "Pop", "Bottle", "Blow", "Purr",
        "Ping", "Glass", "Sosumi", "Submarine", "Hero"
    ]

    static let defaultSound = "Ping"

    static var soundName: String {
        UserDefaults.standard.string(forKey: "alertSoundName") ?? defaultSound
    }

    static func setSoundName(_ name: String) {
        UserDefaults.standard.set(name, forKey: "alertSoundName")
    }

    // MARK: - Voices

    /// Four voices: American and British, male and female. Each is resolved by
    /// name first, then by language and gender, so a Mac missing one particular
    /// voice still speaks in the right accent rather than falling silent.
    struct Voice {
        let key: String
        let title: String
        let language: String
        let gender: AVSpeechSynthesisVoiceGender
        /// Preferred identifiers, best first.
        let identifiers: [String]
    }

    static let voices: [Voice] = [
        Voice(key: "en-US-female", title: "American · female", language: "en-US", gender: .female,
              identifiers: ["com.apple.voice.compact.en-US.Samantha",
                            "com.apple.speech.synthesis.voice.samantha"]),
        Voice(key: "en-US-male", title: "American · male", language: "en-US", gender: .male,
              identifiers: ["com.apple.speech.synthesis.voice.Alex",
                            "com.apple.voice.compact.en-US.Aaron"]),
        Voice(key: "en-GB-female", title: "British · female", language: "en-GB", gender: .female,
              identifiers: ["com.apple.voice.compact.en-GB.Serena",
                            "com.apple.voice.compact.en-GB.Kate"]),
        Voice(key: "en-GB-male", title: "British · male", language: "en-GB", gender: .male,
              identifiers: ["com.apple.voice.compact.en-GB.Daniel",
                            "com.apple.voice.compact.en-GB.Oliver"])
    ]

    static let defaultVoiceKey = "en-US-female"

    static var voiceKey: String {
        UserDefaults.standard.string(forKey: "alertVoice") ?? defaultVoiceKey
    }

    static func setVoiceKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "alertVoice")
    }

    static var voiceTitle: String {
        voices.first { $0.key == voiceKey }?.title ?? "System voice"
    }

    /// The best available match for the chosen voice, or nil to let the system
    /// pick its own.
    private static func resolvedVoice() -> AVSpeechSynthesisVoice? {
        guard let wanted = voices.first(where: { $0.key == voiceKey }) ?? voices.first else {
            return nil
        }
        for identifier in wanted.identifiers {
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) { return voice }
        }
        let installed = AVSpeechSynthesisVoice.speechVoices()
        if let match = installed.first(where: {
            $0.language == wanted.language && $0.gender == wanted.gender
        }) { return match }
        // Right accent, any gender, before giving up on the accent entirely.
        if let match = installed.first(where: { $0.language == wanted.language }) { return match }
        return AVSpeechSynthesisVoice(language: wanted.language)
    }

    /// True when an alert can actually happen: a lead time, and at least one way
    /// of announcing itself. Categories only narrow it down from here.
    static var isEnabled: Bool { lead > 0 && (playsSound || speaks) }

    // MARK: - Which categories

    /// Empty means every category, including blocks that matched no rule. Storing
    /// it that way keeps "all" true as you add categories to your CSV.
    static var selectedCategories: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "alertCategories") ?? [])
    }

    /// The bucket a block with no matching rule falls into.
    static let uncategorized = "Uncategorized"

    static var isEveryCategory: Bool { selectedCategories.isEmpty }

    static func selectAllCategories() {
        UserDefaults.standard.removeObject(forKey: "alertCategories")
    }

    static func toggleCategory(_ name: String) {
        var chosen = selectedCategories
        if chosen.isEmpty {
            // Coming from "all", the first click means "only everything but this".
            chosen = Set(KeywordRules.categories.map { $0.name } + [uncategorized])
        }
        if chosen.contains(name) { chosen.remove(name) } else { chosen.insert(name) }
        let all = Set(KeywordRules.categories.map { $0.name } + [uncategorized])
        if chosen == all || chosen.isEmpty {
            selectAllCategories()      // back to "all", rather than an empty list
        } else {
            UserDefaults.standard.set(Array(chosen).sorted(), forKey: "alertCategories")
        }
    }

    static func includes(_ event: CalEvent) -> Bool {
        let chosen = selectedCategories
        guard !chosen.isEmpty else { return true }
        return chosen.contains(event.category ?? uncategorized)
    }

    // MARK: - Firing

    /// Blocks already announced, so a one-second tick doesn't announce the same
    /// one sixty times. Keyed by start time and title, and forgotten on relaunch.
    private static var fired = Set<String>()
    private static let synthesizer = AVSpeechSynthesizer()
    private static var askedForNotifications = false

    private static func key(_ event: CalEvent) -> String {
        "\(Int(event.start.timeIntervalSince1970))|\(event.title)"
    }

    /// Called every tick. Announces anything whose start is now within the lead
    /// time, once, and only for categories still switched on.
    static func check(_ events: [CalEvent], now: Date) {
        guard isEnabled else { return }
        let window = TimeInterval(lead)

        var due: [CalEvent] = []
        for event in events where !event.isAllDay {
            let seconds = event.start.timeIntervalSince(now)
            guard seconds > 0, seconds <= window else { continue }
            guard includes(event) else { continue }
            guard !fired.contains(key(event)) else { continue }
            due.append(event)
        }
        guard !due.isEmpty else { return }

        for event in due { fired.insert(key(event)) }
        if fired.count > 500 { fired.removeAll() }   // a long uptime, not a leak

        announce(due.map { spokenName($0) })
    }

    /// Everything before the first pipe: "Focus Work | Learn" is spoken as
    /// "Focus Work", since a bar reads aloud as an awkward pause.
    private static func spokenName(_ event: CalEvent) -> String {
        let head = event.title.split(separator: "|").first.map(String.init) ?? event.title
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? event.title : trimmed
    }

    /// Sound first, then speech: a chime under a sentence makes both harder to
    /// make out.
    private static func announce(_ names: [String]) {
        let phrase = "\(leadPhrase()) before \(list(names))"

        if playsSound { play(soundName) }

        if speaks {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = resolvedVoice()
            // A beat after the chime, so the two don't overlap.
            utterance.preUtteranceDelay = playsSound ? 0.9 : 0
            synthesizer.speak(utterance)
        }

        postBanner(title: "Starting in \(leadPhrase())", body: list(names))
    }

    /// "A", "A and B", "A, B and C" — spoken, so no Oxford comma.
    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    static func play(_ name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.stop()          // in case it's still ringing from a preview
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    /// A Notification Center banner *if* the system allows it. This app is built
    /// locally rather than notarised, so permission may simply never be granted —
    /// which is why the sound and the speech are the real mechanism and this is a
    /// silent bonus.
    private static func postBanner(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let centre = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        centre.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            centre.add(request, withCompletionHandler: nil)
        }
    }

    /// Asked for once, when alerts are first switched on. A refusal costs
    /// nothing: the sound and the speech don't depend on it.
    static func requestNotificationPermissionIfNeeded() {
        guard !askedForNotifications, Bundle.main.bundleIdentifier != nil else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// "Test Alert Now" — exactly what a real alert does, on a made-up block.
    static func test() {
        let saidLead = lead > 0 ? leadPhrase() : "1 minute"
        let phrase = "\(saidLead) before Focus Work"
        if playsSound { play(soundName) }
        if speaks {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = resolvedVoice()
            utterance.preUtteranceDelay = playsSound ? 0.9 : 0
            synthesizer.speak(utterance)
        }
        if !playsSound && !speaks { NSSound.beep() }
    }

    /// Called when the lead time or the categories change, so a block that was
    /// skipped a moment ago can still be announced under the new settings.
    static func forgetAnnounced() { fired.removeAll() }
}
