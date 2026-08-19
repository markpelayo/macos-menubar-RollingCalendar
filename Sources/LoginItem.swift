import AppKit
import Foundation

/// Launching at login, as a LaunchAgent rather than a Login Item.
///
/// A plist in `~/Library/LaunchAgents` is read by launchd when you log in, which
/// is what makes the delay possible: the wait lives in the job itself. launchd
/// runs a short-lived `/bin/sh` that sleeps and then *replaces itself* with the
/// app, so once the wait is over nothing extra is left running — the shell is
/// gone, and launchd is watching the app rather than a wrapper.
enum LoginItem {

    /// Matches the bundle identifier, so the agent is recognisable in
    /// `launchctl list` and in System Settings › Login Items.
    static let label = "io.github.macos-menubar-rollingcalendar"

    /// The waits offered in the menu, in seconds.
    static let delayChoices = [5, 10, 15, 20, 30, 60]

    /// Off until you ask for it. Installing something into a login sequence is
    /// the user's call, not the app's — nothing is written to
    /// `~/Library/LaunchAgents` unless you switch it on.
    static let defaultEnabled = false

    /// What `delay` reads before a wait has ever been chosen. Nothing in the
    /// menu is marked with it — the wait is the user's to pick.
    static let defaultDelay = 20

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "runAtStartup") as? Bool ?? defaultEnabled
    }

    /// Seconds to wait after login. Zero means launch immediately.
    static var delay: Int {
        UserDefaults.standard.object(forKey: "startupDelay") as? Int ?? defaultDelay
    }

    /// What the menu item itself reads, so the current setting is visible
    /// without opening the submenu.
    static var menuTitle: String {
        guard isEnabled else { return "Run at Startup: Off" }
        return delay > 0 ? "Run at Startup: After \(delay) s" : "Run at Startup: On"
    }

    // MARK: - Where things live

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// The binary inside the running bundle, so the agent starts exactly the
    /// copy of the app it was installed from.
    private static var executablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    }

    /// A bundle outside /Applications works, but the agent breaks the moment
    /// that folder is renamed, moved or deleted — worth saying once.
    static var isInApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// The command the installed agent runs, or nil when there is no agent.
    /// Used to notice that the app has moved since it was installed.
    private static var installedCommand: String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization
                  .propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return nil }
        return arguments.last
    }

    // MARK: - Changing the setting

    /// Records the choice and makes the agent on disk match it.
    static func apply(enabled: Bool, delay seconds: Int) {
        let d = UserDefaults.standard
        d.set(enabled, forKey: "runAtStartup")
        d.set(seconds, forKey: "startupDelay")
        if enabled { install(delay: seconds) } else { remove() }
    }

    /// Run at every launch, to repair an agent still pointing at a copy of the
    /// app that has since moved. It never installs one on its own: an untouched
    /// setting means the question hasn't been asked yet, and the answer is no.
    static func syncOnLaunch() {
        guard isEnabled else {
            if isInstalled { remove() }        // switched off, or never on
            return
        }
        if !isInstalled || installedCommand?.contains(executablePath) != true {
            install(delay: delay)
        }
    }

    // MARK: - The agent itself

    private static func install(delay seconds: Int) {
        let exec = executablePath
        let arguments: [String]
        if seconds > 0 {
            // Single-quoted for the shell, with any quote in the path escaped
            // the long way round, since a bundle can live anywhere.
            let quoted = "'" + exec.replacingOccurrences(of: "'", with: "'\\''") + "'"
            arguments = ["/bin/sh", "-c", "sleep \(seconds); exec \(quoted)"]
        } else {
            arguments = [exec]
        }

        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            // Interactive, not Background: a background job sits in a low
            // priority band macOS is free to defer, which quietly turns "no
            // delay" into "some unpredictable delay".
            "ProcessType": "Interactive",
            // Only in a logged-in desktop session — there is no menu bar to
            // draw into anywhere else.
            "LimitLoadToSessionType": "Aqua"
        ]

        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: job, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            NSLog("Rolling Calendar: could not write the login agent — \(error)")
        }
        // Deliberately not loaded here. launchd reads the folder at login, and
        // bootstrapping a RunAtLoad job now would start a second copy of the app
        // on top of the one you are clicking in.
    }

    private static func remove() {
        // Harmless when it was never loaded, which is the usual case.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        try? FileManager.default.removeItem(at: plistURL)
    }
}
