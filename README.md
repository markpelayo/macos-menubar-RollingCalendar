# macos-menubar-RollingCalendar

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](#quick-start)
[![Status: in development](https://img.shields.io/badge/status-in%20development-orange)](#known-limitations)

A macOS menu bar app that draws today's calendar as a horizontal timeline scrolling past a fixed "now" marker. Instead of asking *what time is my next thing*, you glance up and see where you are.

> **Status: in development.** Working and usable, but rough edges remain — see [Known limitations](#known-limitations). Behaviour, defaults and stored preferences may change without migration.

## The UI

![Rolling Calendar running in the macOS menu bar](docs/ui-strip.png)

Time flows right-to-left. The red line is fixed at the centre and always marks now, so blocks drift leftward as the day passes. There are no tick marks or gridlines — just past, now and future.

- **Left label** — the block you're in and how much of it is left, e.g. `Deep Work (5m)`, turning red in the final two minutes
- **Right label** — what's next and how long that block runs for, e.g. `(16h) Out of office`
- **Labels size themselves to the name** — the menu bar item grows and shrinks as event names change, up to `maxLabelWidth` (300 pt by default). Past that the *name* is shortened with an ellipsis; the countdown and the warning badge are never cut, since a truncated countdown would be useless. The capsules carry no text, as it would only repeat the labels
- **Coloured capsules** — your events in their real Google Calendar colours, outlined so neighbours stay distinct, separated by a 1 pt gap
- **Past is paler** — the same colour, lightened once it's behind the line, with a lighter outline to match. A block in progress fades from the left as it elapses, so you can see how far through it you are
- **Double-booking is flagged, not stacked** — the strip stays one row, and the badge's *side* tells you when the clash is. On the **right** it hasn't reached now yet: `(1h) Vendor Call 🔴(2)`. On the **left** it's live: `🔴(2) Vendor Call (59m)` — two things want you right this second. A clash appears on the right, crosses to the left as it reaches the now line, and clears when it's over. Open the dropdown for the full list
- **Window** — ±1 hour across 250 pt by default, plus however much the two labels need. Both are adjustable from the menu

The strip is deliberately small — it lives in the menu bar and is meant to be read at a glance, not studied.

Clicking it opens today's schedule, and everything else lives in that menu:

![Rolling Calendar dropdown menu](docs/ui-menu.svg)

## Quick start

```bash
git clone <your-fork-url> rolling-calendar
cd rolling-calendar
chmod +x build.sh
./build.sh
open build/RollingCalendar.app
```

Needs macOS 13+ and Xcode Command Line Tools (`xcode-select --install`) for `swiftc`. No packages, no dependencies, no Xcode project — one shell script and seven Swift files.

**It starts in Demo Mode**, showing synthetic 15-minute blocks, so you can see it working before connecting anything. Click the strip → **Demo Mode** to turn that off once you've set up a real calendar.

To keep it: `cp -R build/RollingCalendar.app /Applications/`. To start it at login: **System Settings → General → Login Items → +**, then pick RollingCalendar.

> **No download link, on purpose.** Apple charges $99/year for the Developer ID needed to notarise an app, and macOS blocks downloaded apps that aren't notarised. Rather than hand you a binary you have to fight your own operating system to open, this project asks you to build it — which is also the only way to be certain the app matches the source you can read here.

### Uninstalling

```bash
pkill -f RollingCalendar.app
rm -rf /Applications/RollingCalendar.app
defaults delete io.github.macos-menubar-rollingcalendar   # forget settings
security delete-generic-password -s io.github.macos-menubar-rollingcalendar   # forget the Google token
```

Also revoke the app's access at [myaccount.google.com/permissions](https://myaccount.google.com/permissions) if you used Google sign-in.

## Connecting your calendar

Two modes. Nothing is baked into the app — it ships with no calendar configured.

| | Google sign-in | Public `.ics` feed |
|---|---|---|
| Event colours | **Yes**, real per-event colours | No — feeds carry none |
| Calendar stays private | Yes | No, must be shared publicly |
| Freshness | Live; ≤5 min | Google's cache lag, can be hours |
| Setup | One-time OAuth client | Paste a link |
| Recurring events | Expanded by Google | Expanded locally |

### Google sign-in (recommended)

Per-event colour exists only in the Google Calendar API — the `.ics` export has no colour field. Google also requires every app to be registered, so there's a one-time setup. You log in on Google's own page; the app never sees your password and asks only for `calendar.readonly`.

1. [console.cloud.google.com](https://console.cloud.google.com) → create or pick a project
2. **APIs & Services → Library** → enable **Google Calendar API**
3. **APIs & Services → OAuth consent screen** → User type **External** → add your own address under **Test users**
4. **Credentials → Create credentials → OAuth client ID** → Application type **Desktop app**
5. In the app: strip → **Set Up Google Sign-In…** → paste the Client ID and secret → **Save & Sign In**

Because the consent screen stays in Testing mode, Google shows an "unverified app" warning — **Advanced → Go to … (unsafe)**. Expected for a personal app; only your listed test users can sign in.

Then **Choose Calendar** lists every calendar on the account with its colour swatch. The one marked primary is your main calendar.

The refresh token is stored in your login Keychain. Colours resolve in this order: the event's own colour override → the calendar's colour → green.

### Public `.ics` feed

Feed calendars are saved as **named profiles**, so you can keep several and switch with one click:

```
Calendar: Work (public feed)
Saved Calendars ▸
    ● Work            ✏️  ✕
      Personal        ✏️  ✕
      Team on-call    ✏️  ✕
      ─────────────────────
      Add Calendar…
Copy Feed URL
```

Click a row to switch to it. The **pencil** renames it, the **✕** removes it after a confirmation that spells out what happens — whether it's the one in use, or your last one. Only the saved link is ever forgotten; your actual calendar is untouched.

**Add Calendar…** asks for a name and a link. A link saved before profiles existed is adopted as a profile automatically, named after its address, so nothing is lost.

The link field accepts any of these — the app works out the feed URL:

| You paste | App uses |
|---|---|
| `…/calendar/embed?src=you@gmail.com&ctz=…` | derived `.ics` feed |
| `…/calendar/u/0/newembed?src=you@gmail.com&ctz=…` | derived `.ics` feed |
| `…/calendar/ical/you%40gmail.com/public/basic.ics` | as-is |
| `…/private-abc123…/basic.ics` (secret address) | as-is |
| `webcal://…` | rewritten to `https://` |
| `you@gmail.com`, `…@group.calendar.google.com` | derived `.ics` feed |
| `file:///path/to/local.ics` | read from disk |

**HTTP 404 means the calendar isn't public.** Either share it publicly (Google Calendar → Settings and sharing → *Access permissions* → **Make available to public**), use the **Secret address in iCal format** under *Integrate calendar*, or sign in with Google instead.

A `ctz=` parameter in the link sets the time zone used for event times; otherwise the Mac's own time zone is used.

## Debug Time

Under the date at the top of the dropdown, **Debug Time…** moves the app to any moment — pick a date and time and the strip renders as if it were then. Useful for checking how a crowded afternoon, an overlap, or the end of the day looks without waiting for it.

The simulated clock **keeps running** from the point you pick, so blocks still slide and countdowns still tick; it isn't frozen. Events are re-fetched for the simulated date, so you can jump to another day entirely.

While it's active the timeline is tinted purple, the date line reads `· simulated`, and the menu shows the pretend time — it can't be left on unnoticed. **Reset to Current Time** puts it back, and the picker itself has a **Use Current Time** button.

The offset survives a relaunch, which is what you want mid-testing. If the strip ever looks wrong, check for the purple tint first.

## Testing without a calendar

**Demo Mode** (strip → *Demo Mode*) generates its own blocks: 96 per day at exactly 15 minutes, no overlaps, no gaps, coloured from Google's palette, titles carrying their start time. Useful for checking the drawing is correct independently of any data source.

The [`examples/`](examples/) folder has importable `.ics` files built on the same grid. They use floating local times, so they land on correct quarter-hours in any time zone. See [examples/README.md](examples/README.md).

## Configuration

Most of it is in the menu — click the strip:

| Menu | What it does |
|---|---|
| **Time Range ▸** | How much time is visible: ±5 min through ±2 hours (default ±1 hour) |
| **Timeline Width ▸** | How much menu bar the timeline takes: 100 pt to 450 pt in 50 pt steps (default 250 pt) |
| **Labels ▸** | Four toggles: block name and time left on the left, block name and duration on the right (all on by default) |
| **Label Length ▸** | How long an event name may get before it's shortened: 100 pt to 480 pt, each annotated with the character count it works out to (default 300 pt) |
| **Restore Defaults** | Back to ±1 hour, 250 pt timeline, 300 pt labels, all labels on. Greyed out when nothing has been changed |

The two are independent: **range** decides how much time you see, **width** decides how much space it gets. Together they set how big a block looks — at the default ±1 hour across 250 pt, a 15-minute block is about 31 pt wide; narrow the range to ±15 minutes at the same width and it grows to 125 pt. Each width option's tooltip does that arithmetic for you, and the note at the foot of the menu shows the current result.

The rest is user defaults, read at launch. Change `io.github.macos-menubar-rollingcalendar` if you edit `BUNDLE_ID` in `build.sh`.

```bash
# thickness of the red now line, points (default 4)
defaults write io.github.macos-menubar-rollingcalendar nowLineWidth -float 6

# translucent tinted blocks instead of solid fills
defaults write io.github.macos-menubar-rollingcalendar solidBlocks -bool false

# gap between blocks, points (default 1)
defaults write io.github.macos-menubar-rollingcalendar blockGap -float 3

# square the capsules off a bit (default 0 = capsule, radius is half the height)
defaults write io.github.macos-menubar-rollingcalendar blockCornerRadius -float 3

# text size; defaults to the system menu bar size
defaults write io.github.macos-menubar-rollingcalendar titleFontSize -float 12
```

Total menu bar width is `timelineWidth` plus whatever the two labels currently need, so it changes through the day as event names change. `maxLabelWidth` is the ceiling on each side.

### Which block gets the label when two overlap

**Time decides first.** The left label names whatever ends soonest — that's the deadline that matters — and the right names whatever starts soonest. So a one-hour meeting inside an all-day block takes the label while it runs, and the all-day block takes it back afterwards.

Only when two candidates tie *exactly* does chain position break it, preferring the block that belongs to a back-to-back run: its start meets another's end and its end meets another's start. That's your time-blocked backbone, and a meeting dropped on top of it chains to nothing, so the backbone keeps the label while 🔴 tells you something extra is sitting on it.

If they're still tied — identical start *and* end, like two trainings both booked 1–2 — geometry can't separate them, and it falls back to shorter-first then alphabetical, purely so the choice is stable rather than flickering. Telling "my own time block" from "a meeting someone sent me" reliably needs the organiser/attendee fields from the Google API, which isn't wired up yet.

Only today is loaded; other days are ignored, though events straddling midnight still render at the window edges. The calendar is re-fetched every 5 minutes and on wake; the strip redraws every second.

## How it's built

| File | Purpose |
|---|---|
| `Sources/main.swift` | Config, `NSStatusItem`, menu, dialogs, fetch/redraw timers |
| `Sources/TimelineView.swift` | All drawing: capsules, now line, gutter labels, overlap badges |
| `Sources/GoogleAuth.swift` | OAuth 2.0, PKCE + loopback redirect, Keychain storage |
| `Sources/GoogleCalendarAPI.swift` | Calendar list, colour palette, events with `colorId` |
| `Sources/ICS.swift` | iCalendar parser, recurrence expansion (RRULE, EXDATE, overrides) |
| `Sources/CalendarSource.swift` | Normalizes any pasted calendar link into a feed URL |
| `Sources/CalendarRowView.swift` | Saved-calendar menu row with inline rename and remove buttons |
| `Sources/DemoData.swift` | Synthetic 15-minute blocks for Demo Mode |
| `build.sh` | Compiles and packages the `.app` (LSUIElement, ad-hoc signed) |
| `examples/` | Importable 15-minute test calendars |
| `docs/` | UI diagrams and screenshots |
| `DISCLAIMER.md` | No-warranty and liability notice |

No storyboards, no `.xcodeproj`, no SwiftPM manifest. `swiftc` is invoked directly and the bundle is assembled by hand, so the whole build is readable in one file.

## Known limitations

- **Ad-hoc signed.** The signing identity changes on every rebuild, so macOS may re-prompt for Keychain access after each build.
- **The OAuth consent screen stays in Testing mode** unless you verify the app with Google, so only accounts you add as test users can sign in.
- **The local ICS parser handles a practical subset of RFC 5545.** `FREQ=DAILY/WEEKLY/MONTHLY/YEARLY` with `INTERVAL`, `BYDAY`, `BYMONTHDAY`, `UNTIL`, `COUNT`, plus `EXDATE` and `RECURRENCE-ID` overrides. `COUNT` truncation is approximate for `WEEKLY` with multiple `BYDAY` values. Google sign-in avoids all of this by expanding recurrence server-side.
- **All-day events** appear in the dropdown but not on the strip.
- **`.ics` feeds carry no colour**, so every block is green in feed mode.
- **Google's feed cache** means feed mode can lag well behind an edit. Sign-in mode is live.
- **The client secret is stored in user defaults**, not the Keychain. It isn't really secret for a desktop OAuth client, but it is plaintext on disk.
- **Single day only.** No multi-day view, no scrolling back.

## Privacy

Your calendar data never leaves your machine. The app talks only to Google (`googleapis.com`, `accounts.google.com`) or to the feed URL you provide, and nothing else — no analytics, no telemetry, no third-party services. Events are held in memory only and are never written to disk.

What is stored locally: your settings and the OAuth client ID/secret in `~/Library/Preferences/io.github.macos-menubar-rollingcalendar.plist`, and the Google refresh token in your login Keychain. The client secret is stored in plain text — it isn't truly secret for a desktop OAuth client, but be aware of it.

During sign-in the app briefly listens on `127.0.0.1` on a random port to catch Google's redirect, then shuts the listener down. Nothing is exposed beyond the loopback interface.

## Disclaimer

**This software is provided free of charge, "as is", without warranty or support of any kind, and is used entirely at your own risk.** It is a glanceable indicator, not a calendar, reminder or timekeeping system — it will never notify you of anything, and calendar data it shows may be stale, incomplete or absent. It must not be relied upon where inaccuracy, delay or failure could cause loss or harm. If you use a public iCalendar feed, you alone are responsible for what you make public. To the maximum extent permitted by law the author accepts no liability of any kind arising from its use, including missed appointments, disclosure of calendar data, or damage to any machine, system or data.

Not affiliated with, endorsed or supported by Google LLC.

Full terms: [DISCLAIMER.md](DISCLAIMER.md) and the [MIT Licence](LICENSE).

## Contributing

Issues and pull requests are welcome. Keep it dependency-free and keep the idle cost near zero.

## License

MIT © Mark Pelayo — see [LICENSE](LICENSE).
