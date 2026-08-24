# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.1] — 2026-08-24

### Added

- **Reset Everything…**, in its own block above Quit. A factory reset: every setting forgotten, the
  LaunchAgent deleted, saved calendars removed and Demo Mode restored, exactly as on a first launch.
  It confirms first, itemising what will go, with **Cancel** as the default button — Return shouldn't
  be the fast path to a wipe. It clears the whole preference domain rather than a list of keys, so a
  setting added later can't be left behind. Distinct from the appearance-only **Restore Defaults**,
  which is unchanged.

### Changed

- **The calendar block moved up**, to sit directly under Debug Time and above the day's blocks. Which
  calendar is being read belongs next to what it produced, rather than at the far end of the menu.
- **The day's blocks no longer dismiss the menu when clicked.** They're something to read, not
  something to press, and losing the whole menu to a stray click while reading a list of sixty was a
  poor trade for a click that had nothing to do. They still highlight under the pointer, which is
  what makes a long list followable — but faintly rather than in full selection blue, since the text
  is already carrying meaning in its colours: dim for past, bold for now, a chip per category.

- The project is no longer labelled *in development*. It's in daily use, and what it deliberately
  doesn't do is listed under Known limitations instead — now including that it only ever reads a
  calendar, that Siri's voice can't be used for spoken alerts, and that a failed refresh keeps the
  last good day for half an hour.

### Fixed

- The README claimed **only today is loaded**; four days are (yesterday through the day after
  tomorrow), so the sleep-to-sleep cycle can find both of its boundaries.
- It still advised checking for a **purple tint** that was removed several versions ago, two lines
  after saying nothing is tinted.
- The bundled sample is **41 keywords**, not 37, in both the README and the changelog; the changelog
  also had the CSV's column order backwards.
- `examples/README.md` pointed at a **Choose Calendar** menu that hasn't existed since calendars
  became named profiles.
- **Quit**, **Debug Time** and the **Updated** row were missing from the Configuration table, which
  reads as a complete list of the menu; the Keyword Colors sketch omitted **Use Sample Colors** and
  **Save Sample CSV…**; and the first-run case, where *Add Calendar…* sits at the top level rather
  than inside a submenu, went unmentioned.
- Midday's chime is **about 80 seconds**, not 70; there are five menu formatters, not four; two shell
  scripts, not one; and **CAF** belongs in the list of sound formats the importer accepts.
- The colour wheel in `docs/` is now shown in the Keyword Colors section rather than sitting unused.

## [1.4.0] — 2026-08-24

### Added

- **The menu opens with the project.** `macos-menubar-RollingCalendar 1.4.0 · by markpelayo`, drawn
  dim like the captions around it and clickable like the commands below it — a plain menu item can be
  one or the other but not both, so it's a small custom row. The version is read from the bundle
  rather than written into the source, so it always describes the build you're running.
- **Sound Hours** — one schedule that both Time Block Alerts and the Westminster Chime ask before
  making any noise, in its own block above them in the menu. Windows are a set rather than a choice,
  so a split day (8 AM–1 PM and 7 PM–10 PM) is one setting; a window may run past midnight; **Off**
  silences both features without disturbing how either is configured; **All day** is an explicit
  choice so "no limit" can't be confused with "nothing set". The default is **11:30 AM – 4:30 AM**.
- Custom windows are typed in whatever form comes naturally — `8`, `8am`, `6:30 PM`, `18:30`, `1830`,
  `11.30pm` — and are added to the existing windows rather than replacing them.
- **Custom chime volume.** The Westminster Chime's four steps are joined by any percentage you like,
  1 to 100, added and selected from **Add Custom…** and kept in the list with an ✕. Deleting the one
  in use falls back to the nearest step, zero is refused — silence is what Off is for — and the rows
  stay open so two volumes can be compared without reopening the menu.
- **An ✕ on every row you created**, in Sound Hours, on custom lead times and on custom chime volumes:
  switching one off and deleting it are different intentions, and a list you keep adding to needs a way
  back down. Removal leaves the menu open, and the row dims rather than vanishing under the pointer.

### Fixed

- **A hostile or broken feed can no longer crash the app.** An absurd `DURATION` reached an
  `Int(_: Double)` conversion that traps rather than saturating, so a single bad event took the menu
  down when it was opened; durations are now bounded and the countdown clamps before converting. Out
  of range dates, a year-one recurrence and a NaN debug offset are all refused rather than trusted,
  and the iCalendar parser has no force unwraps left.
- **The chime survives a change of audio device.** Switching to headphones or Bluetooth tears down
  the audio engine's node graph; playing into the wreckage of one raises an exception Swift can't
  catch. The graph is now rebuilt on the next chime.
- **A stale fetch can't overwrite a fresh one.** Every fetch takes a ticket, so a request left over
  from before sleep — or from the calendar you just switched away from — is discarded when it lands.
- **A network blip no longer blanks the day.** The last good events are kept for half an hour, so the
  dropdown and the alerts survive a captive portal; the strip still shows the error.
- Alerts watch the whole day rather than the dropdown's sleep-to-sleep cycle, so a late evening block
  is no longer left unannounced.
- Clicking through the volume rows no longer queues a full render per click: a superseded one is
  cancelled before it costs anything.
- A `.ics` file on a network volume is read off the main thread; a sound is held until it finishes
  playing rather than being collected mid-chime; the chime is no longer silenced twice over when the
  clocks go back.
- **Tooltips no longer cover the submenu they belong to.** Hovering Time Block Alerts, Sound Hours,
  Westminster Chime — or Alert Sound, Voice Sound, Categories, Run at Startup — popped a description
  over the very options it was describing. Every row that opens a submenu now says what it needs to in
  its own title, which it already did.
- Row buttons — the ✕ on a custom row, the pencil and ✕ on a saved calendar — sat wherever that row's
  own text ended, which could be halfway across a menu made wider by a longer item or a footnote.
  Custom rows are now stretched to the menu's real width, so every button lines up on the right edge.

### Changed

- The sound features now sit in their own section below **Saved Calendars**: Sound Hours, then Time
  Block Alerts, then Westminster Chime.
- *Test Alert Now* and *Hear It* deliberately ignore Sound Hours: a preview you asked for should
  never be refused because of the hour.
- Outside the window the alert check still runs and a silent Notification Center banner can still be
  posted — only the sound and the speech are withheld. The Time Block Alerts and Westminster Chime
  rows read **· quiet now** while they're waiting, rather than looking armed and staying silent.

## [1.3.1] — 2026-08-22

Internal only: no new features, nothing moved in the menu, no settings changed.

### Changed

- **Fewer allocations on the one-second tick.** The gutter labels were composed
  twice per second — once to size the menu bar item, once to draw it — building
  attributed strings and measuring text each time. They're now composed once and
  kept until the second, the events, the settings or the appearance change.
- **iCalendar dates are parsed by hand** rather than through `DateFormatter`. A
  feed with a few hundred events was building an ICU formatter for every
  DTSTART, DTEND, EXDATE and UNTIL in the file, several times an hour. Accepted
  and rejected forms are unchanged, and out-of-range fields — month 13, 30
  February — are still refused rather than quietly rolled forward.
- `Calendar` and the menu's `DateFormatter`s are built once instead of per
  call; the alert settings are read once per tick instead of once per event; the
  announced-blocks set is pruned by age instead of being emptied wholesale.
- The wake observer is now released, and the timers invalidated and the audio
  engine stopped, on quit.

### Fixed

- The set of already-announced blocks was emptied wholesale once it passed a
  thousand entries, which could let a block be announced a second time. It's now
  pruned by age, so an entry is only dropped once its block can no longer come
  due.
- iCalendar dates with an out-of-range field — month 13, 30 February — were
  refused by the old `DateFormatter` and are refused by the hand-rolled parser
  too, rather than being rolled forward into a plausible-looking wrong date.
- The wake-from-sleep observer was registered and its token thrown away. It's
  now released on quit, along with invalidating both timers and stopping the
  audio engine.

## [1.3.0] — 2026-08-21

### Added

- **Westminster Chime** — the tune Big Ben plays, on the hour or every quarter, with the hour counted
  out on the great bell afterwards. Off by default. It follows the real mechanism: five four-note
  changes on the quarter bells, change 1 at quarter past, 2 and 3 at half past, 4, 5 and 1 at quarter
  to, and 2, 3, 4, 5 on the hour before the strikes, counted on a twelve-hour clock.
- The bells are **synthesised, not sampled** — additive synthesis of a bell's inharmonic partials, so
  nothing is bundled and nothing is downloaded, and the 1793 tune is well out of copyright. Volume is
  adjustable, the hour count can be switched off, and each quarter can be previewed from **Hear It**.
- A quarter rings once and only within five seconds of its moment, so waking a sleeping Mac doesn't
  set the bells off for a quarter it slept through. Audio is rendered off the main thread and the
  buffer and the audio hardware are both released when the last note dies away.

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
  `category,color,keyword` rules, load the bundled 41-keyword sample, save it out to edit in a
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

[1.4.1]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.4.1
[1.4.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.4.0
[1.3.1]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.3.1
[1.3.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.3.0
[1.2.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.2.0
[1.1.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.1.0
[1.0.0]: https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/tag/v1.0.0
