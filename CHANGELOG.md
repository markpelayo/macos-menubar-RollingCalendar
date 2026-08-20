# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-08-21

### Added

- **Time Block Alerts** — a system sound, the block name spoken aloud, or both, a chosen time before
  a block starts. Off by default. The lead time is 1 minute, 5 minutes or a custom value; the sound
  is any of the fourteen macOS ships, or one of your own copied into `~/Library/Sounds` by
  **Custom Sound…**; speech is `AVSpeechSynthesizer` with Daniel, Samantha and Zarvox always
  available, plus any Enhanced or Premium voice you've downloaded, which is where natural-sounding
  speech comes from. Sound and speech are exclusive — choosing one silences the other — and the whole
  configuration is shown on the parent menu item, e.g. *Time Block Alerts: 5m | Voice — Daniel*.
  Siri is offered where macOS exposes it and marked *reserved by macOS* where it doesn't, alongside a
  **System Voice** option that names no voice and so follows whatever Spoken Content is set to. Alerts can be limited to chosen categories, fire once
  per block, and skip all-day events. A Notification Center banner is posted too where macOS allows
  it, as a bonus rather than the mechanism.
- **Run at Startup** — off, on, or on after a wait of 5 to 60 seconds. Off by default, since putting
  something into a login sequence is the user's call, and the wait is theirs to pick. It installs a
  LaunchAgent rather than a Login Item, so the delay lives in the job:
  launchd runs a short-lived shell that sleeps and then replaces itself with the app, leaving nothing
  extra running. It warns once if the app is somewhere it's likely to move from, and repairs the path
  at launch if it has.

### Changed

- The dropdown's **Updated / Refresh Now** moved down beside the calendar it refreshes, rather than
  sitting under the day's blocks.
- The menu's own documentation caught up: the hand-drawn SVG is gone, replaced by annotated
  screenshots of the real menu.

## [1.0.0] — 2026-08-19

First public release.

### Added

- Menu bar strip that draws the day as a horizontal timeline with **now fixed at the centre**, so
  blocks drift leftward as time passes instead of you hunting for the current one.
- **Capsules in your own colours**, outlined and separated by a 1 pt gap, with the past lightened
  and the block in progress fading from the left as it elapses.
- **Gutter labels** — the block you're in with its countdown on the left, what's next with its
  length on the right. The countdown turns red and bold for the final two minutes.
- **Labels that size themselves** to the event name, up to 360 pt (about 47 characters). Past that
  the name is shortened; the countdown and the overlap badge are never cut.
- **Overlaps flagged, not stacked** — the strip stays one row and shows `🔴(n)`, on the right while
  the clash is still ahead and on the left once it's live. The dropdown spells it out as
  `🔴(n) Overlapped`.
- **Dropdown day list** reading `time • duration • name • category` with a colour chip, every column
  on a measured tab stop, running anchor to anchor (`sleep` by default) rather than midnight to
  midnight so a late evening reads as one day.
- **Keyword Colors** — colour blocks by what they're called. Import a CSV of
  `keyword,color,category` rules, load the bundled 37-keyword sample, save it out to edit in a
  spreadsheet, or clear it. Longest phrase wins, matching is whole-word and punctuation-insensitive,
  and anything unmatched stays a neutral grey so it's visibly unclassified.
- **Saved Calendars** — public iCalendar feeds kept as named profiles you can switch between,
  rename, or remove. Embed links, `newembed` links, `.ics` URLs, secret addresses, `webcal://`, a
  bare calendar address and `file://` paths are all accepted and normalised to a feed URL.
- **Demo Mode** — a realistic time-blocked day generated in the app, including deliberate overlaps,
  so the strip works before any calendar is connected. It supplies times and names only; colour
  still comes from your keyword rules.
- **Debug Time** — move the whole app to any moment to see how a given hour will look. The header
  reads *simulated* and the strip carries a bold `(❗Simulated❗)` marker so a frozen clock is never
  mistaken for the real one.
- Adjustable **Time Range** (±5 minutes to ±2 hours), **Timeline Width** (100–450 pt in 50 pt
  steps), per-part **Labels** toggles and **Label Length**, all persisted, with **Restore Defaults**
  greyed out until something actually changes.
- `build.sh` to produce an `LSUIElement` app bundle from source with `swiftc` — no Xcode project,
  no SwiftPM, no dependencies.

### Distribution

- Installed by building from source: `./build.sh`. No binary is published, because notarising a Mac
  app requires a paid Apple Developer account and macOS blocks downloaded apps that aren't
  notarised. Building locally sidesteps that and lets you verify the app matches the source.

### Notes on behaviour

- The calendar is re-read every five minutes; the strip redraws every second. ⌘R fetches
  immediately.
- Reading is one-way. The app never writes to your calendar, and no credentials are involved — a
  public feed URL is the whole of the configuration.
- Nothing leaves the machine except the request for the feed itself. Preferences live in
  `UserDefaults` under `io.github.macos-menubar-rollingcalendar`.
- Recurring events are handled for a common subset of RFC 5545 — `RRULE` with `FREQ`, `INTERVAL`,
  `COUNT`, `UNTIL`, `BYDAY`, plus `EXDATE` and `RECURRENCE-ID` overrides.

[1.1.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.1.0
[1.0.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.0.0
