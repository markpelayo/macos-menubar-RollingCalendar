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

    /// Lead times in seconds, longest first. Empty is off, which is where
    /// everyone starts. Several at once is the point: ten minutes to wrap up,
    /// one minute to actually move.
    static var leads: [Int] {
        if let stored = UserDefaults.standard.array(forKey: "alertLeads") as? [Int] {
            return stored.filter { $0 > 0 }.sorted(by: >)
        }
        // Up to 1.1.0 there was one lead time under a different key.
        let legacy = UserDefaults.standard.integer(forKey: "alertLead")
        return legacy > 0 ? [legacy] : []
    }

    /// The three obvious choices; anything else comes from Add Custom…
    static let leadPresets: [(title: String, seconds: Int)] = [
        ("1 minute before", 60),
        ("5 minutes before", 300),
        ("10 minutes before", 600)
    ]

    static func setLeads(_ list: [Int]) {
        let clean = Array(Set(list.filter { $0 > 0 })).sorted(by: >)
        UserDefaults.standard.set(clean, forKey: "alertLeads")
        UserDefaults.standard.removeObject(forKey: "alertLead")
        fired.removeAll()   // a change of lead times means nothing counts as announced
    }

    /// One click adds or removes a lead time, so several can be on at once.
    static func toggleLead(_ seconds: Int) {
        var current = leads
        if let index = current.firstIndex(of: seconds) {
            current.remove(at: index)
        } else {
            current.append(seconds)
        }
        setLeads(current)
    }

    static func clearLeads() { setLeads([]) }

    /// Are alerts armed at all? Kept as a name that reads the same as before.
    static var hasLead: Bool { !leads.isEmpty }

    /// "1 minute", "5 minutes", "90 seconds" — used in the menu and spoken aloud,
    /// so the two can never disagree.
    static func leadPhrase(_ seconds: Int) -> String {
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

    /// Compact form for the summary: "10m", "90s", "2h".
    static func shorthand(_ seconds: Int) -> String {
        if seconds % 3600 == 0 { return "\(seconds / 3600)h" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    /// Every lead time on one line, longest first: "10m, 5m, 1m".
    static var leadShorthand: String {
        leads.map { shorthand($0) }.joined(separator: ", ")
    }

    /// The same, spelled out, for the menu row: "10 minutes, 5 minutes, 1 minute".
    static var leadSummary: String {
        leads.isEmpty ? "Off" : leads.map { leadPhrase($0) }.joined(separator: ", ")
    }

    /// The whole configuration on one line, for the parent menu item:
    /// "Time Block Alerts: 5m | Voice — Daniel".
    static var summary: String {
        guard isEnabled else { return "Time Block Alerts" }
        // `voiceLabel` is enough for the summary; resolving the voice object
        // here would mean a second lookup on every menu click.
        let how = playsSound ? "Sound — \(soundName)" : "Voice — \(voiceLabel)"
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
    static var sounds: [String] { soundList.system + soundList.custom }

    /// Worked out once and kept. Building it means a `NSSound(named:)` probe per
    /// candidate plus two directory scans, and the menu asks for it several times
    /// per click — doing that every time is what makes a menu feel slow.
    private static var soundCache: (system: [String], custom: [String])?

    private static var soundList: (system: [String], custom: [String]) {
        if let soundCache { return soundCache }
        let systemOrder = ["Tink", "Pop", "Bottle", "Blow", "Purr", "Morse",
                           "Ping", "Glass", "Frog", "Funk", "Sosumi",
                           "Submarine", "Hero", "Basso"]
        let system = systemOrder.filter { NSSound(named: NSSound.Name($0)) != nil }
        var extras = Set(customSoundNames)
        extras.subtract(system)
        let list = (system, extras.sorted())
        soundCache = list
        return list
    }

    /// After importing one of your own, or if the folder is edited by hand.
    static func refreshSounds() { soundCache = nil }

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
        refreshSounds()      // the folder just changed
        chooseSound(name)
        return (name, nil)
    }

    /// True for a sound that came from the user rather than from macOS. Answered
    /// from the cached list rather than by touching the disk.
    static func isCustomSound(_ name: String) -> Bool {
        soundList.custom.contains(name)
    }

    // MARK: - Voices

    /// Four accents and genders, plus one robot. Every entry is resolved against
    /// the voices actually installed, so nothing is offered that would stay
    /// silent — a slot with nothing behind it is shown as unavailable instead.
    ///
    /// Siri's own voice is not among them: macOS keeps it private, and
    /// `AVSpeechSynthesisVoice.speechVoices()` never returns it to an app.
    /// `AVSpeechSynthesisVoice.speechVoices()` is not cheap — it enumerates every
    /// installed voice and reads each one's metadata. The menu resolves a dozen
    /// or more voices per click, so the list is fetched once and kept; it only
    /// changes when a voice is downloaded or removed, which is what
    /// `refreshVoices()` is for.
    private static var voiceCache: [AVSpeechSynthesisVoice]?

    static var installedVoices: [AVSpeechSynthesisVoice] {
        if let voiceCache { return voiceCache }
        let list = AVSpeechSynthesisVoice.speechVoices()
        voiceCache = list
        return list
    }

    /// After a trip to Manage Voices, or on waking, in case one was added.
    static func refreshVoices() { voiceCache = nil }

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

    /// Apple's Premium voices for the accents worth offering — American, British
    /// and Australian. They're a download rather than something an app can
    /// bundle, so the catalogue is listed whether or not it's installed: a voice
    /// nobody knows exists is a voice nobody downloads.
    ///
    /// Sizes are what System Settings reports, and shift a little between macOS
    /// releases, so they're shown as approximate.
    struct PremiumVoice {
        let name: String
        let language: String
        let accent: String
        let size: String
    }

    static let premiumCatalogue: [PremiumVoice] = [
        PremiumVoice(name: "Ava", language: "en-US", accent: "American", size: "≈320 MB"),
        PremiumVoice(name: "Zoe", language: "en-US", accent: "American", size: "≈430 MB"),
        PremiumVoice(name: "Jamie", language: "en-GB", accent: "British", size: "≈165 MB"),
        PremiumVoice(name: "Serena", language: "en-GB", accent: "British", size: "≈180 MB"),
        PremiumVoice(name: "Karen", language: "en-AU", accent: "Australian", size: "≈185 MB"),
        PremiumVoice(name: "Lee", language: "en-AU", accent: "Australian", size: "≈165 MB"),
        PremiumVoice(name: "Matilda", language: "en-AU", accent: "Australian", size: "≈115 MB")
    ]

    /// The installed Premium or Enhanced voice behind a catalogue entry, or nil
    /// when it hasn't been downloaded. Compact voices of the same name don't
    /// count — the whole point is the neural one.
    static func installedPremium(_ wanted: PremiumVoice) -> AVSpeechSynthesisVoice? {
        installedVoices.first {
            $0.language == wanted.language
                && $0.quality != .default
                && $0.name.localizedCaseInsensitiveContains(wanted.name)
        }
    }

    static func key(for voice: AVSpeechSynthesisVoice) -> String { "voice:\(voice.identifier)" }

    /// Anything Enhanced or Premium that's installed but *not* in the catalogue
    /// above — a downloaded Enhanced Samantha, or a locale I haven't listed — so
    /// nothing on the Mac is hidden just because it isn't in my list.
    static var otherNaturalVoices: [(key: String, label: String)] {
        let catalogued = Set(premiumCatalogue.compactMap { installedPremium($0)?.identifier })
        return naturalVoices.filter { !catalogued.contains(String($0.key.dropFirst("voice:".count))) }
    }

    /// Every installed Enhanced or Premium English voice.
    static var naturalVoices: [(key: String, label: String)] {
        installedVoices
            .filter { $0.language.hasPrefix("en") && $0.quality != .default }
            .sorted { ($0.name, $0.language) < ($1.name, $1.language) }
            .map { voice in
                let region = voice.language.split(separator: "-").last.map(String.init) ?? ""
                // Some voices already carry their tier in the name — "Ava
                // (Premium)" — so only add it when it isn't there already.
                let tier = voice.quality == .premium ? "Premium" : "Enhanced"
                let name = voice.name.localizedCaseInsensitiveContains(tier)
                    ? voice.name
                    : "\(voice.name) (\(tier))"
                return ("voice:\(voice.identifier)", "\(name) — \(region)")
            }
    }

    // Siri is not offered at all. macOS keeps those voices for Siri and Spoken
    // Content, and the synthesiser substitutes a default one when an app asks —
    // so an app can neither name a Siri voice nor inherit it from the System
    // Voice setting. A menu entry that quietly speaks in something else is worse
    // than no entry, so every voice here is one that will actually be heard.

    /// Where the natural voices are downloaded, for the menu to point at.
    static let voiceSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")

    static let defaultVoiceKey = "en-GB-male"

    static var voiceKey: String {
        let stored = UserDefaults.standard.string(forKey: "alertVoice") ?? defaultVoiceKey
        // "siri" and "system" were offered by 1.1.0 before it turned out macOS
        // won't honour either. Anything unrecognised falls back rather than
        // leaving the alert silent.
        if stored.hasPrefix("voice:") || voiceOptions.contains(where: { $0.key == stored }) {
            return stored
        }
        return defaultVoiceKey
    }

    static func setVoiceKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "alertVoice")
    }

    /// The installed voice behind an option, or nil when the Mac hasn't got one.
    static func installedVoice(for option: VoiceOption) -> AVSpeechSynthesisVoice? {
        let installed = installedVoices

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
    static var isEnabled: Bool { hasLead && (playsSound || speaks) }

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

    /// Takes the chosen set as an argument so a caller looping over events can
    /// read the setting once rather than once per event.
    static func includes(_ event: CalEvent,
                         in chosen: Set<String> = Alerts.selectedCategories) -> Bool {
        chosen.isEmpty || chosen.contains(event.category ?? uncategorized)
    }

    // MARK: - Firing

    /// Blocks already announced, so a one-second tick doesn't announce the same
    /// one sixty times. Keyed by start time, lead time and title; the value is
    /// the block's start, so old entries can be dropped rather than the whole set
    /// being thrown away. Forgotten on relaunch either way.
    private static var fired: [String: Date] = [:]
    private static let synthesizer = AVSpeechSynthesizer()
    private static var askedForNotifications = false

    /// A block is announced once *per lead time*, so 10m, 5m and 1m each get
    /// their turn on the same block.
    private static func key(_ event: CalEvent, _ lead: Int) -> String {
        "\(Int(event.start.timeIntervalSince1970))|\(lead)|\(event.title)"
    }

    /// How late an alert may be and still be worth making. Beyond this the
    /// moment has passed — the app was launched mid-window, or the Mac was
    /// asleep — and announcing "10 minutes before" with three minutes left would
    /// simply be wrong. Those are marked as done, silently.
    private static let catchUpTolerance: TimeInterval = 30

    /// Called every tick. Announces anything whose start is now within the lead
    /// time, once, and only for categories still switched on.
    /// `maySound` is Sound Hours' answer. False still runs the bookkeeping and
    /// still posts a banner — it only withholds the noise, which is the one thing
    /// a schedule called Sound Hours should withhold.
    static func check(_ events: [CalEvent], now: Date, maySound: Bool = true) {
        guard isEnabled else { return }
        let leads = self.leads
        guard let longest = leads.first else { return }
        // Settings are read once per tick rather than once per event: this runs
        // every second, and each read is a trip through UserDefaults.
        let chosen = selectedCategories
        let horizon = TimeInterval(longest)

        var due: [(name: String, lead: Int)] = []
        for event in events where !event.isAllDay {
            let seconds = event.start.timeIntervalSince(now)
            guard seconds > 0, seconds <= horizon else { continue }
            guard includes(event, in: chosen) else { continue }

            for lead in leads where seconds <= TimeInterval(lead) {
                let marker = key(event, lead)
                guard fired[marker] == nil else { continue }
                fired[marker] = event.start
                if TimeInterval(lead) - seconds <= catchUpTolerance {
                    due.append((spokenName(event), lead))
                }
            }
        }
        pruneAnnounced(before: now)
        guard !due.isEmpty else { return }

        // If two lead times land in the same tick — a block 5 minutes out when
        // 5m and 10m are both set, say — the nearer one is the honest number.
        guard let nearest = due.map({ $0.lead }).min() else { return }
        announce(due.filter { $0.lead == nearest }.map { $0.name }, lead: nearest,
                 aloud: maySound)
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
    private static func announce(_ names: [String], lead: Int, aloud: Bool = true) {
        let phrase = "\(leadPhrase(lead)) before \(list(names))"

        if aloud, playsSound { play(soundName) }

        if aloud, speaks {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = resolvedVoice()
            // A beat after the chime, so the two don't overlap.
            utterance.preUtteranceDelay = playsSound ? 0.9 : 0
            synthesizer.speak(utterance)
        }

        postBanner(title: "Starting in \(leadPhrase(lead))", body: list(names))
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

    /// Deliberately a fresh `NSSound` each time rather than a cached one: an
    /// alert is rare, the object is small, and a reused instance has to be
    /// stopped before it can replay — which is unreliable, and a silent alert is
    /// the one failure that matters here.
    static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            NSSound.beep()
            return
        }
        sound.play()
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
        // The nearest lead time, since that's the one you'll hear most often.
        let saidLead = leadPhrase(leads.min() ?? 60)
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

    /// Blocks that started over an hour ago can never come due again. Rebuilding
    /// the dictionary is cheap but this runs on the one-second tick, so it's done
    /// at most once a minute and only when there's something to gain.
    /// Stamped from the real clock, not `Clock.now`: a debug time set a week
    /// ahead and then reset would otherwise leave the throttle in the future and
    /// stop pruning for the rest of the launch.
    private static var lastPrune = Date.distantPast

    private static func pruneAnnounced(before now: Date) {
        // A backstop, in case the throttle below never lets a prune through.
        if fired.count > 5000 { fired.removeAll(); return }

        let realNow = Date()
        guard fired.count > 200, realNow.timeIntervalSince(lastPrune) > 60 else { return }
        lastPrune = realNow
        let cutoff = now.addingTimeInterval(-3600)
        fired = fired.filter { $0.value > cutoff }
    }
}
