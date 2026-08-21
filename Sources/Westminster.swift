import AppKit
import AVFoundation

/// The Westminster Quarters — the tune people mean by "Big Ben" — synthesised
/// rather than sampled.
///
/// **How the real thing works.** Four quarter bells play a set of five
/// four-note changes, and the Great Bell (the one actually named Big Ben)
/// strikes the hour afterwards:
///
/// | Time | Changes played |
/// |---|---|
/// | quarter past | 1 |
/// | half past | 2, 3 |
/// | quarter to | 4, 5, 1 |
/// | on the hour | 2, 3, 4, 5, then the hour struck |
///
/// The quarter bells are G♯, F♯, E and B; the hour bell is a low E. The hour is
/// struck on a twelve-hour count, so one o'clock is one blow and midday is
/// twelve. That's the whole mechanism: chime the quarter, and on the hour chime
/// all five changes' worth and then count the hour out.
///
/// **Why synthesised.** A recording of Big Ben is someone's copyright, and
/// bundling audio into an app that's built from source is a nuisance besides.
/// The tune itself dates from 1793 and is long out of copyright, so the bells
/// are built here out of sine partials: a bell is a fundamental plus a stack of
/// inharmonic overtones — the hum, the tierce a minor third above, the quint,
/// the nominal — each decaying at its own rate. It won't be mistaken for the
/// real Elizabeth Tower, but it is unmistakably the tune.
enum Westminster {

    // MARK: - Settings

    enum Mode: String {
        case off, hourly, quarterly

        var title: String {
            switch self {
            case .off: return "Off"
            case .hourly: return "On the hour"
            case .quarterly: return "Every quarter hour"
            }
        }
    }

    static var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: "chimeMode") ?? "") ?? .off
    }

    static func setMode(_ mode: Mode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "chimeMode")
    }

    /// Whether the hour is counted out after the hour's chime. Off leaves just
    /// the tune, which is shorter and less imposing at midnight.
    static var strikesHour: Bool {
        UserDefaults.standard.object(forKey: "chimeStrikesHour") as? Bool ?? true
    }

    static func setStrikesHour(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "chimeStrikesHour")
    }

    static let volumeChoices: [Float] = [0.25, 0.5, 0.75, 1.0]

    static var volume: Float {
        let stored = UserDefaults.standard.float(forKey: "chimeVolume")
        return stored > 0 ? stored : 0.6
    }

    static func setVolume(_ value: Float) {
        UserDefaults.standard.set(value, forKey: "chimeVolume")
        player.volume = value
    }

    static var menuTitle: String { "Westminster Chime: \(mode.title)" }

    // MARK: - The tune

    /// Which quarter is being rung.
    enum Quarter: CaseIterable {
        case quarterPast, halfPast, quarterTo, hour

        /// The changes played, by the numbering used everywhere this tune is
        /// described.
        var changes: [Int] {
            switch self {
            case .quarterPast: return [1]
            case .halfPast: return [2, 3]
            case .quarterTo: return [4, 5, 1]
            case .hour: return [2, 3, 4, 5]
            }
        }

        var title: String {
            switch self {
            case .quarterPast: return "Quarter past"
            case .halfPast: return "Half past"
            case .quarterTo: return "Quarter to"
            case .hour: return "The hour"
            }
        }
    }

    /// The four quarter bells, in E major, plus the hour bell an octave and a bit
    /// below. Frequencies rather than note names, because that's what the
    /// oscillator wants.
    private static let bell: [String: Double] = [
        "G#": 415.30,   // G♯4
        "F#": 369.99,   // F♯4
        "E": 329.63,    // E4
        "B": 246.94,    // B3
        "hour": 164.81  // E3 — the Great Bell
    ]

    /// The five changes. Everything the tune does is a rearrangement of these
    /// four notes.
    private static let changes: [Int: [String]] = [
        1: ["G#", "F#", "E", "B"],
        2: ["E", "G#", "F#", "B"],
        3: ["E", "F#", "G#", "E"],
        4: ["G#", "E", "F#", "B"],
        5: ["B", "F#", "G#", "E"]
    ]

    // Timing, in seconds. The real clock is a little slower than this; these are
    // chosen so that noon doesn't run to two minutes.
    private static let noteGap = 1.2
    private static let changeGap = 0.6
    private static let beforeStrikes = 2.5
    private static let strikeGap = 4.0
    private static let noteDecay = 3.6
    private static let strikeDecay = 6.5

    // MARK: - Ringing

    /// Rings a quarter. `hour` is the twelve-hour count used for the strikes and
    /// is ignored except on the hour.
    static func ring(_ quarter: Quarter, hour: Int = 12, strikes: Bool? = nil) {
        let counting = (strikes ?? strikesHour) && quarter == .hour
        let count = counting ? max(1, min(12, hour)) : 0

        renderQueue.async {
            guard let buffer = render(quarter, strikes: count) else { return }
            DispatchQueue.main.async { playBuffer(buffer) }
        }
    }

    /// Called on the app's one-second tick. Rings once per quarter, and only
    /// within a few seconds of it — waking a sleeping Mac at twenty past
    /// shouldn't set the bells off for the quarter it slept through.
    static func check(now: Date) {
        let mode = self.mode
        guard mode != .off else { return }

        let parts = Config.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: now)
        guard let minute = parts.minute, minute % 15 == 0,
              let hour = parts.hour, let second = parts.second else { return }
        guard mode == .quarterly || minute == 0 else { return }

        let stamp = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)-\(hour)-\(minute)"
        guard stamp != lastRung else { return }
        lastRung = stamp
        guard second <= 5 else { return }   // too late to be the right time

        let quarter: Quarter
        switch minute {
        case 15: quarter = .quarterPast
        case 30: quarter = .halfPast
        case 45: quarter = .quarterTo
        default: quarter = .hour
        }
        ring(quarter, hour: hour % 12 == 0 ? 12 : hour % 12)
    }

    static func stop() {
        player.stop()
        if engine.isRunning { engine.pause() }
    }

    static var isRinging: Bool { player.isPlaying }

    private static var lastRung = ""

    // MARK: - Synthesis

    private static let sampleRate = 22050.0
    private static let renderQueue = DispatchQueue(label: "rollingcalendar.chime", qos: .utility)
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var engineWired = false

    /// A struck bell: a fundamental with inharmonic partials above it, each
    /// fading at its own rate. The hum is below the note, the tierce a minor
    /// third above — which is what gives a bell its faintly minor colour.
    /// Ratio, relative loudness, decay.
    private static let partials: [(ratio: Double, amplitude: Double, decay: Double)] = [
        (0.5, 0.35, 4.0), (1.0, 1.00, 3.2), (1.19, 0.55, 2.4), (1.5, 0.32, 1.9),
        (2.0, 0.42, 1.6), (2.51, 0.18, 1.1), (3.01, 0.14, 0.9), (4.1, 0.08, 0.6)
    ]

    /// One note at a time, mixed into a single buffer. A whole sequence is a few
    /// megabytes at most, held only while it rings.
    private static func render(_ quarter: Quarter, strikes: Int) -> AVAudioPCMBuffer? {
        var notes: [(start: Double, frequency: Double, length: Double)] = []
        var cursor = 0.0

        for change in quarter.changes {
            for name in changes[change] ?? [] {
                notes.append((cursor, bell[name] ?? 329.63, noteDecay))
                cursor += noteGap
            }
            cursor += changeGap
        }

        if strikes > 0 {
            cursor += beforeStrikes
            for _ in 0..<strikes {
                notes.append((cursor, bell["hour"] ?? 164.81, strikeDecay))
                cursor += strikeGap
            }
        }

        let seconds = cursor + strikeDecay + 0.5
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(seconds * sampleRate)),
              let samples = buffer.floatChannelData?[0] else { return nil }

        let total = Int(seconds * sampleRate)
        buffer.frameLength = AVAudioFrameCount(total)
        for i in 0..<total { samples[i] = 0 }

        for note in notes {
            let offset = Int(note.start * sampleRate)
            let length = Int(note.length * sampleRate)
            let scale = note.length / noteDecay      // strikes ring longer
            for i in 0..<length {
                let index = offset + i
                guard index < total else { break }
                let t = Double(i) / sampleRate
                var value = 0.0
                for partial in partials {
                    value += partial.amplitude
                        * exp(-t / (partial.decay * scale))
                        * sin(2 * .pi * note.frequency * partial.ratio * t)
                }
                // A few milliseconds of attack, so the note doesn't start with a
                // click.
                let attack = min(1.0, t / 0.004)
                samples[index] += Float(value * attack * 0.16)
            }
        }
        return buffer
    }

    private static func playBuffer(_ buffer: AVAudioPCMBuffer) {
        if !engineWired {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            engineWired = true
        }
        if !engine.isRunning {
            do { try engine.start() } catch {
                NSLog("Rolling Calendar: no audio engine for the chime — \(error)")
                return
            }
        }

        player.stop()               // a new quarter supersedes one still ringing
        player.volume = volume
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            DispatchQueue.main.async {
                // Let go of the audio hardware once the last note has died away.
                if !player.isPlaying, engine.isRunning { engine.pause() }
            }
        }
        player.play()
    }
}
