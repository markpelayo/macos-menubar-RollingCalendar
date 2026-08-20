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

    /// Sound and speech are exclusive: one alert, one way of announcing itself.
    /// Choosing either silences the other, so there's never a chime and a
    /// sentence competing for the same moment.
    static func chooseSound(_ name: String) {
        let d = UserDefaults.standard
        d.set(true, forKey: "alertSound")
        d.set(false, forKey: "alertSpeech")
        d.set(name, forKey: "alertSoundName")
    }

    static func chooseVoice(_ key: String) {
        let d = UserDefaults.standard
        d.set(true, forKey: "alertSpeech")
        d.set(false, forKey: "alertSound")
        d.set(key, forKey: "alertVoice")
    }

    static func setPlaysSound(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "alertSound")
        if on { UserDefaults.standard.set(false, forKey: "alertSpeech") }
    }

    static func setSpeaks(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "alertSpeech")
        if on { UserDefaults.standard.set(false, forKey: "alertSound") }
    }

    /// Compact lead time for the menu bar's own summary: "5m", "90s", "2h".
    static var leadShorthand: String {
        let seconds = lead
        if seconds % 3600 == 0 { return "\(seconds / 3600)h" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    /// The whole configuration on one line, for the parent menu item:
    /// "Time Block Alerts: 5m | Voice — Daniel".
    static var summary: String {
        guard isEnabled else { return "Time Block Alerts" }
        let how = playsSound ? "Sound — \(soundName)" : "Voice — \(voiceShortName)"
        var parts = [leadShorthand, how]
        if !isEveryCategory { parts.append("\(selectedCategories.count) categories") }
        return "Time Block Alerts: " + parts.joined(separator: " | ")
    }

    /// Every sound macOS ships in /System/Library/Sounds, ordered quietest
    /// first, plus anything the user has dropped into `~/Library/Sounds` — which
    /// is also where **Custom Sound…** copies a file to. Nothing is bundled with
    /// the app, and a name that no longer resolves falls back to the system beep.
    ///
    /// The system list is fourteen: that's all Apple provides. The list gets past
    /// that only with sounds you add yourself.
    static var sounds: [String] {
        let systemOrder = ["Tink", "Pop", "Bottle", "Blow", "Purr", "Morse",
                           "Ping", "Glass", "Frog", "Funk", "Sosumi",
                           "Submarine", "Hero", "Basso"]
        var names = systemOrder.filter { NSSound(named: NSSound.Name($0)) != nil }
        var extras = Set(customSoundNames)
        extras.subtract(names)
        return names + extras.sorted()
    }

    /// Where a custom sound is kept, so `NSSound(named:)` can find it by name for
    /// good — the same folder macOS itself scans.
    static var userSoundsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Sounds")
    }

    /// Sound files in ~/Library/Sounds and /Library/Sounds, by bare name.
    private static var customSoundNames: [String] {
        let shared = URL(fileURLWithPath: "/Library/Sounds")
        var found: [String] = []
        for folder in [userSoundsDirectory, shared] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                     includingPropertiesForKeys: nil)) ?? []
            for file in files where !file.lastPathComponent.hasPrefix(".") {
                let name = file.deletingPathExtension().lastPathComponent
                if NSSound(named: NSSound.Name(name)) != nil { found.append(name) }
            }
        }
        return found
    }

    /// Formats NSSound can open. Anything else is refused rather than copied in
    /// and then silently failing to play.
    static let soundFileTypes = ["aiff", "aif", "wav", "caf", "m4a", "mp3", "aac"]

    static let defaultSound = "Ping"

    static var soundName: String {
        UserDefaults.standard.string(forKey: "alertSoundName") ?? defaultSound
    }

    static func setSoundName(_ name: String) {
        UserDefaults.standard.set(name, forKey: "alertSoundName")
    }

    /// Copies a chosen file into ~/Library/Sounds and selects it. Returns the
    /// name it can be played by, or nil with a reason.
    static func importSound(from source: URL) -> (name: String?, problem: String?) {
        guard soundFileTypes.contains(source.pathExtension.lowercased()) else {
            return (nil, "“\(source.lastPathComponent)” isn't an audio file macOS can play as an "
                       + "alert. Try AIFF, WAV, CAF, M4A or MP3.")
        }
        let fm = FileManager.default
        let destination = userSoundsDirectory.appendingPathComponent(source.lastPathComponent)
        do {
            try fm.createDirectory(at: userSoundsDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
        } catch {
            return (nil, "Couldn't copy it into ~/Library/Sounds — \(error.localizedDescription)")
        }
        let name = destination.deletingPathExtension().lastPathComponent
        guard NSSound(named: NSSound.Name(name)) != nil else {
            try? fm.removeItem(at: destination)
            return (nil, "macOS couldn't open “\(source.lastPathComponent)” as a sound.")
        }
        chooseSound(name)
        return (name, nil)
    }

    /// True for a sound that came from the user rather than from macOS, so the
    /// menu can offer to forget it.
    static func isCustomSound(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: userSoundsDirectory.path)
            && soundFileTypes.contains { ext in
                FileManager.default.fileExists(
                    atPath: userSoundsDirectory.appendingPathComponent("\(name).\(ext)").path)
            }
    }

    // MARK: - Voices

    /// Four accents and genders, plus one robot. Every entry is resolved against
    /// the voices actually installed, so nothing is offered that would stay
    /// silent — a slot with nothing behind it is shown as unavailable instead.
    ///
    /// Siri's own voice is not among them: macOS keeps it private, and
    /// `AVSpeechSynthesisVoice.speechVoices()` never returns it to an app.
    struct VoiceOption {
        let key: String
        let label: String
        let language: String?
        let gender: AVSpeechSynthesisVoiceGender?
        /// Preferred voices, best first, matched by name or identifier suffix.
        let preferred: [String]
    }

    /// The three that are always worth offering, because they're installed on
    /// every Mac. Anything more natural has to be downloaded, so it's discovered
    /// rather than assumed — see `naturalVoices`.
    static let voiceOptions: [VoiceOption] = [
        VoiceOption(key: "en-GB-male", label: "British · male", language: "en-GB", gender: .male,
                    preferred: ["Daniel", "Oliver", "Arthur"]),
        VoiceOption(key: "en-US-female", label: "American · female", language: "en-US", gender: .female,
                    preferred: ["Samantha", "Allison", "Susan", "Nicky"]),
        // The closest macOS comes to a Jarvis: a deliberately synthetic voice.
        VoiceOption(key: "robot", label: "Robot", language: nil, gender: nil,
                    preferred: ["Zarvox", "Trinoids", "Ralph", "Fred"])
    ]

    /// Enhanced and Premium English voices the user has downloaded in System
    /// Settings. These are Apple's own neural voices — the same engine, far more
    /// natural than the compact ones above, and nothing to bundle or install
    /// alongside the app. Selected by identifier, so a voice is never confused
    /// with a same-named compact version.
    static var naturalVoices: [(key: String, label: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && $0.quality != .default }
            .sorted { ($0.name, $0.language) < ($1.name, $1.language) }
            .map { voice in
                let tier = voice.quality == .premium ? "Premium" : "Enhanced"
                let region = voice.language.split(separator: "-").last.map(String.init) ?? ""
                return ("voice:\(voice.identifier)", "\(voice.name) (\(tier), \(region))")
            }
    }

    /// Where the natural voices are downloaded, for the menu to point at.
    static let voiceSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")

    static let defaultVoiceKey = "en-GB-male"

    static var voiceKey: String {
        UserDefaults.standard.string(forKey: "alertVoice") ?? defaultVoiceKey
    }

    static func setVoiceKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "alertVoice")
    }

    /// The installed voice behind an option, or nil when the Mac hasn't got one.
    static func installedVoice(for option: VoiceOption) -> AVSpeechSynthesisVoice? {
        let installed = AVSpeechSynthesisVoice.speechVoices()

        for wanted in option.preferred {
            if let match = installed.first(where: {
                $0.name.caseInsensitiveCompare(wanted) == .orderedSame
                    || $0.identifier.hasSuffix(".\(wanted)")
            }) { return match }
        }
        guard let language = option.language else { return nil }
        if let gender = option.gender,
           let match = installed.first(where: { $0.language == language && $0.gender == gender }) {
            return match
        }
        return installed.first { $0.language == language }
    }

    /// The name of the voice that will actually speak, e.g. "Daniel", so the menu
    /// can show what you're getting rather than just the accent.
    static func voiceName(for option: VoiceOption) -> String? {
        installedVoice(for: option)?.name
    }

    static var voiceLabel: String {
        guard speaks else { return "Off" }
        if voiceKey.hasPrefix("voice:") {
            return naturalVoices.first { $0.key == voiceKey }?.label
                ?? resolvedVoice()?.name ?? "System voice"
        }
        guard let option = voiceOptions.first(where: { $0.key == voiceKey }) else {
            return "System voice"
        }
        if let name = voiceName(for: option) { return "\(option.label) — \(name)" }
        return option.label
    }

    /// Just the voice's own name, for the one-line summary on the parent item.
    static var voiceShortName: String {
        resolvedVoice()?.name ?? "system"
    }

    private static func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if voiceKey.hasPrefix("voice:") {
            let identifier = String(voiceKey.dropFirst("voice:".count))
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) { return voice }
        }
        guard let option = voiceOptions.first(where: { $0.key == voiceKey })
                ?? voiceOptions.first else { return nil }
        return installedVoice(for: option)
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
