# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-08-21

### Added

- **Several lead times at once.** *Alert Me Before* is a set rather than a choice: 1, 5 and 10
  minutes, plus any custom value, as many as you like. Each block is announced once per lead time —
  ten minutes to start wrapping up, one minute to actually move — all sharing the same sound or
  voice, with only the spoken number changing.
- **Premium Voices** submenu listing Apple's neural voices for American, British and Australian
  English whether or not they're installed: the ones you have are selectable, the rest show their
  download size and open Manage Voices, since a voice nobody knows exists is a voice nobody
  downloads.
- **Custom Sound…** copies an AIFF, WAV, MP3 or M4A into `~/Library/Sounds`, so the alert sound isn't
  limited to the fourteen macOS ships.

### Changed

- **Multi-select rows no longer close the menu.** Lead times and categories are custom views that
  handle the click themselves, so a set can be built in one visit; sibling rows re-read their state
  and the parent rows rewrite their titles in place. Single choices — a sound, a voice — still close,
  since each plays a sample as it's picked.
- **One alert style, not two.** Choosing a sound switches the voice off and vice versa, enforced in
  the settings rather than the menu, so a chime and a sentence can never compete for the same moment.
- The whole alert configuration is shown on the parent item — *Time Block Alerts: 10m, 1m | Voice —
  Daniel* — and each row inside carries its own value, with **Off** living in the submenu rather than
  as a separate checkbox.
- An alert more than 30 seconds late is marked done rather than announced. Launching mid-window or
  waking from sleep no longer produces a burst of catch-up alerts claiming the wrong number of
  minutes.
- Siri and *System Voice* are no longer offered: macOS reserves the Siri voices, and they can't be
  named by an app or inherited from the System Voice setting — the synthesiser substitutes a default
  instead.

### Fixed

- **Opening the menu had become slow.** Submenus are built eagerly by AppKit, and the alert rows were
  calling `AVSpeechSynthesisVoice.speechVoices()` around twenty times per click — each call
  enumerating every installed voice — plus several hundred filesystem checks for the sound list. Both
  lists are now built once and cached, and invalidated only when a voice or sound could have changed.
- A voice whose name already carries its tier no longer reads *Ava (Premium) (Premium, US)*.

## [1.1.0] — 2026-08-21

### Added

- **Time Block Alerts** — a system sound, the block name spoken aloud, or both, a chosen time before
  a block starts. Off by default. Lead times are a set rather than a choice — 1, 5 and 10 minutes plus
  a custom value; the sound is any of the fourteen macOS ships; speech is `AVSpeechSynthesizer` with
  Daniel, Samantha and Zarvox, plus any Enhanced or Premium voice you've downloaded. Sound and speech are exclusive — choosing one silences the other — and the whole
  configuration is shown on the parent menu item, e.g. *Time Block Alerts: 5m | Voice — Daniel*.
  Siri isn't offered: macOS reserves those voices, and an app can neither name one nor inherit it from
  the System Voice setting — the synthesiser substitutes a default instead. Alerts can be limited to chosen categories, fire once
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

[1.2.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.2.0
[1.1.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.1.0
[1.0.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.0.0
