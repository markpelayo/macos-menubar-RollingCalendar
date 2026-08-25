# macos-menubar-RollingCalendar

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](#quick-start)
[![Release: v1.6.0](https://img.shields.io/badge/release-v1.6.0-brightgreen)](https://github.com/markpelayo/macos-menubar-RollingCalendar/releases/latest)

A macOS menu bar app that draws today's calendar as a horizontal timeline scrolling past a fixed "now" marker. Instead of asking *what time is my next thing*, you glance up and see where you are.

It's in daily use, and [v1.6.0](CHANGELOG.md) is the current release. What it deliberately doesn't do is listed under [Known limitations](#known-limitations).

## The UI

![Rolling Calendar running in the macOS menu bar](docs/ui-strip.png)

Time flows right-to-left. The red line is fixed at the centre and always marks now, so blocks drift leftward as the day passes. There are no tick marks or gridlines — just past, now and future.

- **Left label** — the block you're in and how much of it is left, e.g. `Deep Work (5m)`. It turns **red and bold** for the final two minutes, so the ending registers peripherally rather than needing to be read (`urgentSeconds` changes the threshold), and can be set to **flash** from further out — see [Ending Soon Flash](#ending-soon-flash)
- **Right label** — what's next and how long that block runs for, e.g. `(16h) Out of office`
- **Labels size themselves to the name** — the menu bar item grows and shrinks as event names change, up to `maxLabelWidth` (360 pt by default, about 47 characters). Past that the *name* is shortened with an ellipsis; the countdown and the warning badge are never cut, since a truncated countdown would be useless. The capsules carry no text, as it would only repeat the labels
- **Coloured capsules** — your events in their real colours, outlined so neighbours stay distinct, separated by a 1 pt gap. Anything with no colour and no matching keyword is neutral grey, so unclassified events are obvious
- **Overlaps: shortest on top** — a 45-minute meeting inside a 1-hour block stays visible rather than hiding underneath it
- **Past is paler** — the same colour, lightened once it's behind the line, with a lighter outline to match. A block in progress fades from the left as it elapses, so you can see how far through it you are
- **Double-booking is flagged, not stacked** — the strip stays one row, and the badge's *side* tells you when the clash is. On the **right** it hasn't reached now yet: `(1h) Vendor Call 🔴(2)`. On the **left** it's live: `🔴(2) Vendor Call (59m)` — two things want you right this second. A clash appears on the right, crosses to the left as it reaches the now line, and clears when it's over. Open the dropdown, where each affected row spells it out as `🔴(2) Overlapped`
- **Window** — ±1 hour across 250 pt by default, plus however much the two labels need. Both are adjustable from the menu

The strip is deliberately small — it lives in the menu bar and is meant to be read at a glance, not studied.

Clicking it opens the day's blocks, and everything else lives in that menu. The first row names the app, the version it's actually running — read from the bundle, so it can't disagree with the binary — and opens the [project page](https://github.com/markpelayo/macos-menubar-RollingCalendar):

```
macos-menubar-RollingCalendar 1.6.0  ·  by markpelayo
```

![A map of the whole menu, top to bottom](docs/ui-menu-map.png)

The map above is the menu as it is built today; the walkthrough below takes it a block at a time, top to bottom.

### 1 · The date line

The day, the week and the source in one caption, dimmer than the rows beneath it but at the same size — it's context rather than content, and still has to be readable at a glance:

```
Week 35  ·  Monday  ·  August 24, 2026  ·  Demo Calendar (test data)  ·  ❗Simulated❗
```

The week number is **ISO 8601**, so "Week 35" means the same thing to anyone reading it rather than depending on where they live. The last part names whichever calendar is being read — a saved calendar by name, the Demo Calendar, or *No calendar yet* when a saved calendar has been removed and the demo is off — which is why there's no longer a separate *Calendar:* row. The red **❗Simulated❗** appears only when Debug Time has moved the clock, matching the marker on the strip.

### 2 · The day's blocks

![The day list, with current blocks, colour chips and overlap badges annotated](docs/ui-menu-day.png)

The rows are something to read, not something to press: a click does nothing and the menu stays open, and the row under the pointer picks up a soft yellow highlight so a list of sixty stays followable.

### 3 · Where the calendar comes from

This block sits between the day's blocks and the strip settings, and holds everything about *what* the blocks are: **Demo Calendar** and **Saved Calendars ▸** decide where they come from (see [Connecting your calendar](#connecting-your-calendar)), **Keyword Colors ▸** what colour each one is, and **Ending Soon Flash ▸** how loudly the one you're in announces that it's nearly over.

### 4 · The strip itself

**Time Range**, **Timeline Width**, **Labels**, **Label Length** and **Restore Strip Settings**: geometry, and nothing else — how much time is visible, how much menu bar it takes, and how long a name may get.

### 5 · Freshness and Refresh Now

**Refresh Now (⌘R)** re-reads the feed immediately rather than waiting for the five-minute timer, and says so: the row reads **Refreshing…** and greys out while the request is in flight, and the line above it reads **Updated just now** for the first minute afterwards. That line is relative — *just now*, *3 minutes ago*, then the clock time past an hour — because the question it answers is "is what I'm looking at current?", and a bare timestamp leaves you doing the arithmetic.

**What it can and can't do.** It guarantees the app re-downloads the feed, bypassing any local cache. It can't make Google republish: a public `.ics` is regenerated on Google's own schedule, often minutes and sometimes hours after you edit an event. If a change isn't showing, the app already has the newest file being served — the delay is upstream. Left alone, the app re-reads every **five minutes**, and also at launch and on waking from sleep.

## Quick start

```bash
git clone <your-fork-url> rolling-calendar
cd rolling-calendar
chmod +x build.sh
./build.sh
open build/RollingCalendar.app
```

Needs macOS 13+ and Xcode Command Line Tools (`xcode-select --install`) for `swiftc`. No packages, no dependencies, no Xcode project — two shell scripts and fourteen Swift files.

**It starts in Demo Calendar**, showing a realistic time-blocked day, so you can see it working before connecting anything. Click the strip → **Demo Calendar** to turn that off once you've set up a real calendar.

To keep it: `cp -R build/RollingCalendar.app /Applications/`. To start it at login: **System Settings → General → Login Items → +**, then pick RollingCalendar.

> **No download link, on purpose.** Apple charges $99/year for the Developer ID needed to notarise an app, and macOS blocks downloaded apps that aren't notarised. Rather than hand you a binary you have to fight your own operating system to open, this project asks you to build it — which is also the only way to be certain the app matches the source you can read here.

### Uninstalling

```bash
pkill -f RollingCalendar.app
rm -rf /Applications/RollingCalendar.app
defaults delete io.github.macos-menubar-rollingcalendar   # forget settings
```

## Connecting your calendar

Nothing is baked into the app — it ships with no calendar configured, and reads a **public iCalendar feed**. Colour comes from [keyword rules](#keyword-colors) rather than from the calendar, so a feed is all it needs.

Feed calendars are saved as **named profiles**, so you can keep several and switch with one click:

```
Saved Calendars ▸
    ✓ Work            ✏️  ✕
      Personal        ✏️  ✕
      Team on-call    ✏️  ✕
      ─────────────────────
      Add Calendar…
```

A tick marks the calendar actually being read — nothing is ticked in Demo Calendar, and **Saved Calendars** itself is ticked whenever a saved calendar is live. Click a row to switch to it. The **pencil** renames it, the **✕** removes it after a confirmation that spells out what happens — whether it's the one in use, or your last one. Only the saved link is ever forgotten; your actual calendar is untouched.

Before the first calendar is saved there is no submenu to open — the menu shows a plain **Add Calendar…** instead, and *Saved Calendars ▸* appears once you have one.

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

**HTTP 404 means the calendar isn't public.** Either share it publicly (Google Calendar → Settings and sharing → *Access permissions* → **Make available to public**), or use the **Secret address in iCal format** under *Integrate calendar*.

A `ctz=` parameter in the link sets the time zone used for event times; otherwise the Mac's own time zone is used.

## The dropdown list

Rows read `time • duration • name • category`, with the category's colour as an inline chip, plus `🔴(n) Overlapped` when a block shares time with others:

```
▶︎ 04:30 AM – 11:30 AM  •  7h     •  Sleep               •  ◼︎ Health | Rest
   11:30 AM – 12:00 PM  •  30m    •  Stretching          •  ◼︎ Health | Rest
   12:30 PM – 02:30 PM  •  2h     •  Focus Work | Learn  •  ◼︎ Focus Work | Learn
   03:00 PM – 03:30 PM  •  30m    •  Weekly Planning     •  ◼︎ Meetings | Urgency  •  🔴(2) Overlapped
   03:00 PM – 03:20 PM  •  20m    •  Client Call         •  ◼︎ Meetings | Urgency  •  🔴(2) Overlapped
   ─── Thursday, August 20 ───
   04:30 AM – 11:30 AM  •  7h     •  Sleep               •  ◼︎ Health | Rest
```

![One row broken down: start–end, duration, block name, colour chip with category, overlap badge](docs/ui-menu-row.png)

The rows are for reading: they highlight under the pointer so a long list stays followable, but a click does nothing rather than closing the menu. The highlight is **yellow rather than the system's selection blue** — blue means *selected*, and nothing here can be selected, so borrowing it would promise something the row can't deliver. It's a highlighter marking your place. Light mode gets a proper highlighter yellow behind dark text; dark mode a much fainter wash, since the text there is near-white and a solid band would drown it. The actionable rows elsewhere in the menu keep the blue, where the promise is true.

Every column lines up exactly, which takes three things: hours are zero-padded; times and durations use **tabular figures**, since SF's default digits are proportional and `1` is narrower than the rest; and each field sits on a **tab stop** measured from the widest time and duration in the list.

Tab stops rather than padding with spaces, because padding by character count doesn't align proportional text — `7h` and `30m` are 2 and 3 characters, and `m` is 4 pt wider than `h`, so the separator after them drifts by up to 4 pt however many spaces you add. Tab stops position by point.

**The list runs anchor to anchor, not midnight to midnight.** It starts at the block that opened your current day and ends at the next one, so a night shift reads as a single stretch instead of being severed at midnight — and you see the whole shape of the day rather than a pile of past events and two future ones.

The anchor defaults to any block whose title contains **`sleep`**. Consecutive anchor blocks merge into one run, so a sleep split into 15-minute chunks still counts as a single boundary.

If a day has no anchor — or the day's anchor hasn't happened yet — it falls back to **today plus a rolling 24 hours** rather than the calendar day, so there's always a future to see. A day-only fallback would hide everything past midnight even while the strip was already showing it.

```bash
# anchor the day on something else
defaults write io.github.macos-menubar-rollingcalendar dayAnchorKeyword "wake"
```

A date separator marks where one day becomes the next, since otherwise today's 4:30 AM and tomorrow's look identical. Long cycles are capped at 60 rows with an "… and N more" line.

## Keyword colors

Colour blocks by what they're *called*, rather than by which calendar they came from.

![The colour wheel the sample palette is drawn from, with hex codes](docs/palette-wheel.png)

*(The same wheel as [SVG](docs/palette-wheel.svg), if you want to edit it.)*

**The fastest start is Keyword Colors ▸ Use Sample Colors** — 42 keywords across six categories, applied instantly. **Save Sample CSV…** writes that same set out as a file you can edit in a spreadsheet and bring back with **Import CSV…**, so you're never starting from a blank sheet.

The format is three columns:

```csv
category,color (color name or hex),keyword
Focus Work | Learn,#286DCD,focus
Health | Rest,green,meal
Personal | Growth,purple,meal prep
Travel | Buffers,#7A7A7A,commute
```

| Column | Used for |
|---|---|
| `category` | Grouping in the menu — not matched against |
| `color` | The colour drawn. **A hex or a name** — `#28CD41`, `28CD41` and `green` all work |
| `keyword` | Matched against the event's title |

One colour column, not two — a separate name and hex only invites them to disagree.

Names map to macOS's own system colours — blue is blue, black is black, nothing reinterpreted:

`red` `orange` `yellow` `green` `mint` `teal` `cyan` `blue` `indigo` `purple` `pink` `brown` `gray` `light gray` `dark gray` `black` `white`

Blocks are drawn at full opacity, so a hex renders as exactly that hex.

The importer is deliberately forgiving, because spreadsheets aren't:

- **Any delimiter** — comma, semicolon or tab. Excel picks one based on your locale, so it isn't assumed
- **Any column order**, and header wording it can't match is fine — `color (color name or hex)` works
- **No header row at all** — the colour column is found by looking for values that *are* colours, and the keyword column by which one varies most
- **Legacy files** with separate `color_name` and `color_hex` columns still import, taking the hex
- Blank spacer rows, quoted fields, CRLF endings, and Latin-1 files from Excel

Anything that's neither a hex nor a known name is skipped and named in the summary. If an import fails outright, the error shows what the parser actually saw — delimiter, which column it took for what, and the first data row — so the fix is visible rather than guesswork. There's a working example in [`examples/keyword-colors.csv`](examples/keyword-colors.csv).

### How a keyword is matched

**Longer phrases win.** Rules are sorted by word count before matching, so a two-word keyword is always tested before a single word. Given both `meal` (green) and `meal prep` (purple):

| Event title | Colour | Matched |
|---|---|---|
| `Meal prep for the week` | 🟣 purple | `meal prep` |
| `meal-prep` | 🟣 purple | `meal prep` |
| `Meal_Prep` | 🟣 purple | `meal prep` |
| `Lunch` | 🟢 green | `lunch` |
| `Prep the meal` | 🟢 green | `meal` |
| `Oatmeal breakfast` | — | nothing: `meal` isn't a whole word here |

**Separators don't matter.** Both the title and the keyword have every non-alphanumeric character flattened to a space, so `meal prep`, `meal-prep` and `meal_prep` are one keyword, and a title like `Focus Work | Learn (2H)` matches `focus` cleanly.

**Whole words only.** `meal` matches "Prep the meal" but not "Oatmeal", which stops short keywords colouring things by accident.

Matching is case-insensitive. Repeated keywords are kept once. Clearing the rules puts everything back.

### Uncategorized blocks

Anything with no match keeps whatever colour it already had — its Google colour, or **neutral grey `#8E8E93`** if it has none. Grey therefore means "no rule covers this yet", which is a useful prompt to add a keyword rather than a colour choice.

The **Keyword Colors** submenu lists it below your categories with its swatch, so grey on the strip is recognisable rather than a mystery:

```
23 keywords from calendar colors.csv
──────────────────────────────────
🟦  Travel | Buffers  ·  3
🟨  Admin | Errands  ·  3
🟪  Personal | Growth  ·  2
🟩  Health | Rest  ·  6
🟥  Meetings | Urgency  ·  5
🟦  Focus Work | Learn  ·  4
──────────────────────────────────
⬜  Uncategorized  ·  no keyword match
──────────────────────────────────
Use Sample Colors
    Save Sample CSV…
    Import Another CSV…
Clear Keyword Colors
```

Keep grey reserved for this: if a category also uses grey, "unclassified" stops being readable at a glance. `unmatchedColor` in defaults changes it if you'd rather grey were free for a category.

## Ending Soon Flash

Steady red says *this is nearly over*. A flash says *stop now* — so it's **off by default**, and you choose how early it starts:

```
Ending Soon Flash: Off ▸
                        Off                    ✓
                        ─────────────────────
                        1 min before the end
                        2 min before the end
                        5 min before the end
                        ─────────────────────
                        Add Custom…
```

The name of the block you're in goes **bold** and alternates between red and its usual colour **once a second**, from the point you chose right through to the end. The weight changes once, when the window opens, and then holds — the blink is colour only, so the label can't jitter and the strip can't resize between blinks.

**Add Custom…** takes any number of minutes from 0.25 to 60, so seven minutes or ninety seconds are as available as the three presets. It replaces what's set rather than adding to it — unlike alert lead times, this is one answer, not a set — and the window you typed appears in the list alongside the presets, ticked, so the setting is never invisible.

It doesn't replace the steady warning, it starts earlier and does more: without it the label still turns red and bold on its own for the final two minutes, and both use the same red rather than inventing a second one.

**Why it's off unless you ask.** Something blinking in your menu bar is a demand for attention, and a demand you didn't ask for is just a distraction — for a strip designed to be glanceable, that's the wrong default. The row sits with the calendar because it's about the blocks rather than the geometry, but it's still the strip's own warning, so **Restore Strip Settings** switches it off again.

There's no extra timer behind it: the strip already recomposes its labels once a second, so the blink rides that tick and costs nothing while it's off.

## Debug Time

Under the date at the top of the dropdown, **Debug Time…** moves the app to any moment — pick a date and time and the strip renders as if it were then. Useful for checking how a crowded afternoon, an overlap, or the end of the day looks without waiting for it.

The simulated clock **keeps running** from the point you pick, so blocks still slide and countdowns still tick; it isn't frozen. Events are re-fetched for the simulated date, so you can jump to another day entirely.

While it's active the left label gains a marker: `(❗Simulated❗) 🔴(2) Out of office (22m)`. Only the marker is bold — the rest of the label keeps its normal weight, so it reads as an annotation rather than changing the label itself. The date line also ends with a red **❗Simulated❗** and the menu shows the pretend time.

**Nothing is tinted, washed or dimmed.** The point of jumping to another time is to see the real colours at that time, so the strip is drawn exactly as it would be for real. **Reset to Current Time** puts it back, and the picker has a **Use Current Time** button.

The offset survives a relaunch, which is what you want mid-testing. If the strip ever looks wrong, check the left label for the `(❗Simulated❗)` marker first.

## Testing without a calendar

**Demo Calendar** (strip → *Demo Calendar*) generates a plausible day in-app: sleep, focus blocks, meals, a nap, an evening shift that runs past midnight, and two deliberate collisions — a double-booked call at 15:00, and a stretch at 16:15 where an interview and a standup both land inside a focus block, so the 🔴 badges have something to report.

It supplies only what a calendar would — **times and names, never colours**. Colour comes from the same [keyword rules](#keyword-colors) as a real feed, so **Clear Keyword Colors** turns the demo grey exactly as it would turn your calendar grey. On a first launch the sample rules are applied once, so it looks configured out of the box.

Because it starts and ends on sleep, it also exercises the dropdown's [sleep-to-sleep cycle](#the-dropdown-list).

The [`examples/`](examples/) folder has importable `.ics` files built on the same grid. They use floating local times, so they land on correct quarter-hours in any time zone. See [examples/README.md](examples/README.md).

## Sound Hours

Both the alerts and the chime ask one question before making any noise: *am I allowed to, at this hour?* **Sound Hours** is that answer, and it sits above them both in the menu, because "don't wake me at 3 a.m." is a single thought and shouldn't have to be expressed twice.

```
✓ Sound Hours: 11:30 AM – 4:30 AM ▸   Off
                                      ───────────────────
                                    ✓ 11:30 AM – 4:30 AM
                                      6:00 AM – 11:00 PM
                                      All day
                                      ───────────────────
                                    ✓ 8:00 AM – 1:00 PM      ← your own
                                    ✓ 7:00 PM – 10:00 PM
                                      Add Custom…
```

- **11:30 AM – 4:30 AM** is the default. A window may run **past midnight** — that one is seventeen hours, not a mistake — and the wrap is handled rather than clamped at midnight.
- **Windows are a set**, so a day split by an evening away from the desk is one setting: 8 AM–1 PM *and* 7 PM–10 PM, both ticked, nothing in between. **Add Custom…** appends rather than replacing, and your own windows sit alongside the presets. Each carries an **✕**, because switching a window off and being rid of it are different intentions — and a list you keep adding to needs a way back down. Custom lead times in Time Block Alerts have the same ✕.
- **Off** silences the alerts and the chime whatever their own settings say — one switch to stop the app making noise, without losing how you had them configured. It's two-way: clicking it again brings the schedule back, with the default window if you'd emptied the set. Clicking a window while Off turns it *on* rather than deleting it, since every row reads as unticked in that state.
- **All day** is an explicit choice rather than the absence of one, so "no limit" and "nothing set" can't be confused. Switching off the last window is the same as Off, and says so, rather than leaving a ticked row above two features that can never fire.
- **Both ends are included.** A window labelled 6:00 AM – 11:00 PM rings the eleven o'clock strike; an exclusive end would have silenced the very minute the label names.
- Rows here don't dismiss the menu, the same as the lead times and categories.

**Previews are exempt.** *Test Alert Now* and *Hear It* are things you asked for on purpose; refusing them because of the hour would look like a bug. Everything that fires on its own respects the schedule.

**Only the noise is withheld.** Outside the window the alert check still runs, so its bookkeeping stays straight and a silent Notification Center banner can still appear — a schedule called Sound Hours shouldn't take away something that makes no sound. The chime has nothing to show, so it simply doesn't run. The two rows below also say **· quiet now** while they're waiting, so a ticked feature that can't currently make a noise admits it.

Times are read the way people type them: `8`, `8am`, `6:30 PM`, `18:30`, `1830`, `11.30pm`.

## Time Block Alerts

A heads-up shortly before a block starts — a system sound, the name spoken aloud, or both. Off until you set it up, and the menu is deliberately staged: **when**, then **how**, then **which blocks**. Each step stays greyed out until the one above it is answered, and the parent item is ticked only once an alert could actually happen.

```
✓ Time Block Alerts: 10m, at start | Voice — British · male — Daniel ▸
                        Alert Me: 10 minutes, when it starts ▸
                                                       Off
                                                       When it starts       ✓
                                                       1 minute before
                                                       5 minutes before
                                                       10 minutes before    ✓
                                                       Add Custom…
                        ─────────────────────────────
                        Alert Sound: Off ▸             Off · 14 system sounds · your own · Custom Sound…
                        Voice Sound: British · male — Daniel ▸
                                                       Off
                                                       British · male — Daniel
                                                       American · female — Samantha
                                                       Robot — Zarvox
                                                       Premium Voices ▸   American
                                                                            Ava — installed
                                                                            Zoe — download, ≈430 MB
                                                                          British
                                                                            Jamie — installed
                                                                            Serena — download, ≈180 MB
                                                                          Australian
                                                                            Karen — download, ≈185 MB
                                                                            Lee — download, ≈165 MB
                                                                            Matilda — download, ≈115 MB
                                                                          Manage Voices…
                        ─────────────────────────────
                        Categories: all ▸              All Categories, then one row per category
                        ─────────────────────────────
                        Test Alert Now
```

**Lead times are a set, not a choice.** Every row in *Alert Me* is a toggle, so ten minutes to start wrapping up and one minute to actually move can both be armed; **Add Custom…** adds another rather than replacing what's there, and custom values sit alongside the presets where you can click them off again. They all share the one sound or voice — only the number spoken changes. **Off** clears the lot.

**Those rows, and the category rows, don't dismiss the menu.** AppKit closes a menu the moment an ordinary item is clicked, which is right for a choice and wrong for a set — arming three lead times would otherwise mean three trips through the menu. They're custom views that handle the click themselves: the tick changes under the pointer, sibling rows re-read their own state, and the parent rows above rewrite their titles in place.

Each block is announced once *per lead time*, and an alert that's more than 30 seconds late — the app was launched mid-window, or the Mac was asleep — is marked done rather than announced, since saying "10 minutes before" with three minutes left is simply wrong. When two lead times land in the same second, the nearer number is the one spoken.

**The parent item carries the whole configuration** — `Time Block Alerts: 10m, 1m | Voice — British · male — Daniel`, longest lead time first, with `| 3 categories` appended when it isn't every category — so the setup is readable from the main menu without opening anything. Each row inside does the same for its own setting, and **Off** lives inside each submenu rather than as a separate checkbox: one control per decision.

**Sound and speech are exclusive.** Choosing a sound switches the voice off, choosing a voice switches the sound off. One alert, one way of announcing itself — a chime under a sentence makes both harder to make out, and having to remember which of two checkboxes is on is worse than seeing one answer on the parent item.

**The sounds are the ones macOS already ships** in `/System/Library/Sounds` — fourteen, quietest first, which is all Apple provides. Choosing one plays it. **Custom Sound…** copies an AIFF, WAV, CAF, M4A, AAC or MP3 into `~/Library/Sounds`, where `NSSound` can find it by name from then on; it appears in its own group below the system ones, and anything already in that folder is picked up automatically. A file macOS can't actually open is refused rather than copied in and left silent.

**When it starts** is a lead time of zero: the alert lands as the block begins rather than ahead of it — *"Focus Work, starting now"* rather than *"5 minutes before Focus Work"*. It's why the row above is called *Alert Me* rather than *Alert Me Before*, which that option would have contradicted. It fires within half a minute of the start; later than that the moment has passed, and it's skipped rather than announced late.

**Speech** is `AVSpeechSynthesizer` — no network, no permission prompt. It says *"5 minutes before Focus Work"*, taking the lead time from your own setting so the two can't disagree, and reading only the part of the name before the first `|`, since a bar reads aloud as an awkward pause. Two blocks starting together are announced in one sentence rather than talking over each other.

Three voices are always offered, because every Mac has them: **Daniel** (British), **Samantha** (American) and **Zarvox** (robot, the nearest thing macOS ships to a synthetic assistant). Each row shows the voice that will actually speak, and reads *not installed* rather than being selectable if the Mac hasn't got it.

Those three are *compact* voices, which is why they sound clipped. **Apple's Premium voices are the fix** — the same `AVSpeechSynthesizer`, neural rather than concatenative, and genuinely natural. They're a free download rather than something an app can bundle, so **Premium Voices ▸** lists the catalogue for the three accents worth having whether or not you've got them:

| Accent | Voices |
|---|---|
| American | Ava, Zoe |
| British | Jamie, Serena |
| Australian | Karen, Lee, Matilda |

A voice you have reads **— installed** and is selectable, which speaks a sample. One you don't reads **— download, ≈180 MB** and opens *Manage Voices* when clicked, because a voice nobody knows exists is a voice nobody downloads. It appears as installed next time the menu opens. Anything Enhanced or Premium that's installed but *not* in that list — a downloaded Enhanced Samantha, another locale — is listed separately, so nothing on your Mac is hidden by my choice of catalogue.

Indian, Irish and South African English Premium voices exist too, and are reachable through *Manage Voices*; they're left out of the menu only to keep it short. Sizes are what System Settings reports and drift between macOS releases, so they're shown as approximate.

**Siri is not offered, and can't be.** Those voices are reserved for Siri and for Spoken Content: `AVSpeechSynthesisVoice.speechVoices()` doesn't return them to an app, there's no API to name one, and making one the **System Voice** doesn't help either — asking the synthesiser to speak without naming a voice gets a default substituted rather than the Siri voice the system is set to. Tested with *System voice: Siri (Voice 2)*, the app still spoke in a compact voice. An entry that quietly says the right words in the wrong voice is worse than no entry, so every voice listed here is one you'll actually hear.

Nothing called Jarvis exists as a macOS voice either; *Robot — Zarvox* is the nearest thing shipped. If you want natural speech, **Ava (Premium)** is the recommendation: download it once, pick it by name, and there's no ambiguity about what comes out.

**Categories** narrow it further — announce meetings but not focus blocks, say. *All Categories* is stored as an empty selection rather than a list of every name, so a category added to your CSV later is included rather than quietly left out. Blocks that matched no rule are covered by the **Uncategorized** row.

The check runs on the same one-second tick as the redraw, and each block is remembered by start time, name **and lead time** until the app quits. Changing the lead times or the categories forgets that, so a block skipped a moment ago can still be announced under the new settings. All-day events never trigger an alert.

A Notification Center **banner** is also posted, if macOS has granted permission. It's a bonus rather than the mechanism: this app is built locally rather than notarised, so that permission may never be granted — the sound and the speech don't depend on it.

## Westminster Chime

The tune people mean by "Big Ben", on your own Mac's clock. It's separate from Time Block Alerts on purpose: it marks the hour, not your calendar, and doesn't care what's in it.

```
✓ Westminster Chime: Every quarter hour ▸
                        Off
                        On the hour
                      ✓ Every quarter hour
                        ─────────────────
                      ✓ Strike the Hour Count
                        Volume: 50% ▸        25% · 50% · 75% · 100%
                                             35% ✕     ← your own
                                             Add Custom…
                        ─────────────────
                        Hear It ▸            Quarter past · Half past · Quarter to · The hour
                        Stop Ringing
```

**What the real clock does.** Four quarter bells play five four-note *changes* — rearrangements of the same four notes, G♯, F♯, E and B — and the Great Bell, the one actually named Big Ben, strikes the hour afterwards:

| Time | Changes played |
|---|---|
| Quarter past | 1 |
| Half past | 2, 3 |
| Quarter to | 4, 5, 1 |
| On the hour | 2, 3, 4, 5 — then the hour struck |

The hour is counted on a twelve-hour clock, so one o'clock is one blow and midday is twelve. That's exactly what this does, including the count.

**It's synthesised, not sampled.** A recording of Big Ben is someone's copyright; the tune, written in 1793, is not. So the bells are built out of sine partials — a bell is a fundamental plus a stack of inharmonic overtones, the hum below it and the tierce a minor third above, each fading at its own rate. Nothing is bundled with the app and nothing is downloaded. It won't be mistaken for the Elizabeth Tower, but it is unmistakably the tune.

**Volume** is the four obvious steps plus anything you add, since "50% is too much and 25% too little" is a real complaint a fixed list can't answer. **Add Custom…** takes a percentage from 1 to 100, selects it and keeps it in the list with an **✕**; deleting the one in use falls back to the nearest step rather than leaving the chime at a volume no row admits to. Zero isn't allowed — silence is what *Off* and Sound Hours are for. Picking any of them plays a sample, and the rows stay open so two can be compared.

Timing is a little brisker than the real clock — notes 1.2 s apart, strikes 4 s — so midday takes about 80 seconds rather than two minutes. **Strike the Hour Count** off leaves just the tune, which is a good deal less imposing at midnight. The audio is rendered on a background thread when the quarter comes round, played through `AVAudioEngine`, and released when the last note dies away; the hardware is let go with it.

A quarter rings once, and only within five seconds of its moment — waking a sleeping Mac at twenty past shouldn't set the bells off for the quarter it slept through.

## Restore Defaults

At the bottom of the menu, in its own block above Quit — where rare and destructive things belong, well away from anything pressed often. The strip-only reset higher up the menu is now called **Restore Strip Settings**, so each name states its own scope. This one keeps the ellipsis, because it is the gentler-sounding name and much the heavier action: the promise of a dialog is doing real work.

```
Restore everything to defaults?

  •  The strip: ± 1 hour across 250 pt, all labels on
  •  Keyword colours: back to the built-in sample
  •  Sounds: alerts off, chime off, Sound Hours off
  •  Run at Startup: off, and the login item removed
  •  Debug Time: cleared
  •  2 saved calendars: removed, leaving Demo Calendar
```

**Greyed out when there's nothing to restore**, the same courtesy *Restore Strip Settings* pays. That's asked of each feature in turn — the strip, the calendar, the colours, the alerts, the chime, Sound Hours, Run at Startup, Debug Time — rather than by checking whether any preferences are stored: a first launch writes keys of its own, so "nothing stored" and "nothing changed" aren't the same question.

It removes the whole preference domain rather than a list of keys, so a setting added in some later version can't be left behind by an out-of-date list, and it deletes the LaunchAgent explicitly — that's a file rather than a preference, and would otherwise go on launching an app that has forgotten it asked. **Cancel is the default button**, since Return should not be the fast path to a wipe.

**Sound Hours ends up Off too**, so the gate doesn't read as armed above two features that are silent. The first alert or chime you switch on afterwards opens the default window again — being silenced by a schedule you never set would look like the alert was broken. Switching the schedule Off yourself is respected from then on.

**Your calendars themselves are untouched.** Only the links saved here are forgotten; nothing is ever written to a calendar. You'll be back in Demo Calendar, exactly as on a first launch.

## Run at Startup

**Off until you ask for it** — putting something into your login sequence is your call, so nothing is written to `~/Library/LaunchAgents` until you switch it on. A wait is worth choosing: at login the Mac is starting everything at once, and the strip isn't what you need in the first few seconds of that. It sits in its own block below Refresh Now, ticked whenever it will launch at login — with or without a wait. The item shows the current setting, so *Run at Startup: After 20 s* tells you where you stand without opening the submenu:

```
Run at Startup: After 20 s ▸    Off
                                On
                                Delay for:
                                  5 s
                                  10 s
                                  15 s
                                  20 s
                                  30 s
                                  60 s
```

It's a **LaunchAgent**, not a Login Item, which is what makes the wait possible — the delay lives in the job itself. launchd runs a short-lived `/bin/sh` that sleeps and then *replaces itself* with the app, so once the wait is over nothing extra is left running:

```xml
<key>ProgramArguments</key>
<array>
  <string>/bin/sh</string>
  <string>-c</string>
  <string>sleep 20; exec '/Applications/RollingCalendar.app/Contents/MacOS/RollingCalendar'</string>
</array>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Interactive</string>
```

`ProcessType` is `Interactive` rather than `Background` deliberately: a background job sits in a low-priority band macOS is free to defer, which quietly turns "no delay" into "some unpredictable delay".

The agent lives at `~/Library/LaunchAgents/io.github.macos-menubar-rollingcalendar.plist` and points at the app **where it was when you switched it on** — so if the app isn't in `/Applications`, you're told once, since moving that folder afterwards would break it. The app re-checks at every launch and repairs the path if it has moved. Removing it is the menu's *Off*, or:

```bash
launchctl bootout gui/$UID/io.github.macos-menubar-rollingcalendar
rm ~/Library/LaunchAgents/io.github.macos-menubar-rollingcalendar.plist
```

## Configuration

Most of it is in the menu — click the strip:

| Menu | What it does |
|---|---|
| **Debug Time… / Reset to Current Time** | Move the whole app to another moment, and back — see [Debug Time](#debug-time) |
| **Demo Calendar** | A generated day, so the strip works before any calendar is connected |
| **Saved Calendars ▸** | Public feeds kept as named profiles: switch, rename, remove |
| **Add Calendar…** | Takes the place of *Saved Calendars ▸* until the first calendar is saved |
| **Keyword Colors ▸** | Import a CSV of keyword → colour rules, load the bundled sample, save it out to edit, or clear it |
| **Ending Soon Flash ▸** | The current block's name goes bold and blinks red as it nears its end: off, 1 / 2 / 5 min, or a custom 0.25–60 min (**off** by default) |
| **Time Range ▸** | How much time is visible: ±5 min through ±2 hours (default ±1 hour) |
| **Timeline Width ▸** | How much menu bar the timeline takes: 100 pt to 450 pt in 50 pt steps (default 250 pt) |
| **Labels ▸** | Four toggles: block name and time left on the left, block name and duration on the right (all on by default) |
| **Label Length ▸** | How long an event name may get before it's shortened: 100 pt to 480 pt, each annotated with the character count it works out to (default 360 pt, about 47 characters) |
| **Restore Strip Settings** | The strip only: back to ±1 hour, 250 pt timeline, 360 pt labels, all labels on, no flash. Greyed out when nothing has been changed |
| **Sound Hours ▸** | The hours in which the alerts and the chime may sound — several windows, midnight wrap allowed (default 11:30 AM – 4:30 AM) |
| **Time Block Alerts ▸** | A sound or the block name spoken, as a block starts or at one or more lead times before it, for the categories you choose (**off** by default) |
| **Westminster Chime ▸** | The hour, or every quarter, on synthesised bells — with the hour counted out (**off** by default) |
| **Updated …** | How fresh the day is: *Not read yet*, *just now*, *3 minutes ago*, or the clock time once it's older than an hour — and **Refreshing…** while a request is in flight |
| **Refresh Now (⌘R)** | Re-reads the feed immediately instead of waiting for the five-minute timer. Reads **Refreshing…** and greys out while a request is in flight |
| **Run at Startup ▸** | Off, on, or on after a wait of 5–60 s (**off** by default) |
| **Restore Defaults…** | A factory reset, confirmed first: every setting forgotten, saved calendars removed, back to Demo Calendar. Greyed out when everything already is at its defaults |
| **Quit (⌘Q)** | Leaves nothing behind: no helper, and no login item unless you added one |

The first row of the menu — `macos-menubar-RollingCalendar 1.6.0 · by markpelayo` — opens the [project page](https://github.com/markpelayo/macos-menubar-RollingCalendar). The version is read from the app bundle, so it always names the build you're running.

The two are independent: **range** decides how much time you see, **width** decides how much space it gets. Together they set how big a block looks — at the default ±1 hour across 250 pt, a 15-minute block is about 31 pt wide; narrow the range to ±15 minutes at the same width and it grows to 125 pt. Each width option's tooltip does that arithmetic for you, and the note at the foot of the menu shows the current result.

The rest is user defaults, read at launch. Change `io.github.macos-menubar-rollingcalendar` if you edit `BUNDLE_ID` in `build.sh`.

```bash
# thickness of the red now line, points (default 4)
defaults write io.github.macos-menubar-rollingcalendar nowLineWidth -float 6

# how long before a block ends the left label goes red and bold, seconds (default 120)
defaults write io.github.macos-menubar-rollingcalendar urgentSeconds -float 300

# colour for events matching no keyword and carrying none of their own (default #8E8E93)
defaults write io.github.macos-menubar-rollingcalendar unmatchedColor "#C7C7CC"

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

Four days are loaded — yesterday through the day after tomorrow — so the sleep-to-sleep cycle can always find both of its boundaries; only the ± window is drawn on the strip, though events straddling midnight still render at the window edges. The calendar is re-fetched every 5 minutes and on wake; the strip redraws every second.

## How it's built

| File | Purpose |
|---|---|
| `Sources/main.swift` | Config, `NSStatusItem`, menu, dialogs, fetch/redraw timers |
| `Sources/TimelineView.swift` | All drawing: capsules, now line, gutter labels, overlap badges |
| `Sources/ICS.swift` | iCalendar parser, recurrence expansion (RRULE, EXDATE, overrides) |
| `Sources/CalendarSource.swift` | Normalizes any pasted calendar link into a feed URL |
| `Sources/CalendarRowView.swift` | Saved-calendar menu row with inline rename and remove buttons |
| `Sources/KeywordRules.swift` | CSV import, keyword matching and longest-phrase precedence |
| `Sources/Alerts.swift` | Lead times, alert sounds, speech voices and the category filter |
| `Sources/Westminster.swift` | The quarter chime and hour strikes, synthesised from sine partials |
| `Sources/SoundHours.swift` | The one schedule both the alerts and the chime ask before sounding |
| `Sources/LoginItem.swift` | The LaunchAgent behind Run at Startup |
| `Sources/ToggleRowView.swift` | Menu rows that toggle without dismissing the menu |
| `Sources/ProjectRowView.swift` | The dim, clickable first row that opens the project page |
| `Sources/EventRowView.swift` | A day-list row: highlights on hover, ignores the click |
| `Sources/DemoData.swift` | A realistic time-blocked day for Demo Calendar, overlaps included |
| `build.sh` | Compiles and packages the `.app` (LSUIElement, ad-hoc signed) |
| `examples/` | Importable 15-minute test calendars |
| `docs/` | UI diagrams and screenshots |
| `release-notes.sh` | Prints one version's changelog section, for a release body |
| `DISCLAIMER.md` | No-warranty and liability notice |

No storyboards, no `.xcodeproj`, no SwiftPM manifest. `swiftc` is invoked directly and the bundle is assembled by hand, so the whole build is readable in one file.

### What it costs to run

The strip redraws once a second and the feed is re-read every five minutes; nothing else is scheduled. A few things are deliberately computed once and kept, because they were being rebuilt far more often than they change:

| Kept | Rebuilt when |
|---|---|
| The gutter labels | the second, the events, the settings or light/dark mode change |
| The `Calendar` | the time zone changes |
| The six menu `DateFormatter`s | never — they're created at launch |
| The list of installed voices | a voice is downloaded, or the Mac wakes |
| The list of alert sounds | one is imported, or the Mac wakes |
| The Sound Hours windows | one is added, removed or switched |

iCalendar dates are parsed by hand rather than through `DateFormatter`, since a feed with a few hundred events would otherwise build an ICU formatter for every `DTSTART`, `DTEND`, `EXDATE` and `UNTIL` in the file, several times an hour.

Non-recurring events are filtered to the days on screen as they're parsed, so a calendar with years of history costs no more to refresh than one with a week in it.

Together that's tens of kilobytes held, against roughly 25–60 MB resident for any AppKit menu bar app — most of which is shared framework pages. Downloaded voices are not part of it: their audio lives on disk and is loaded by macOS's own speech process, never this one. The chime's audio buffer — a few megabytes for a noon strike — is freed when the last note fades, and a chime superseded before it sounds is cancelled before it's rendered at all.

**Nothing is trusted that comes from outside.** A feed can say anything, so durations are bounded, out-of-range dates refused and every parse total — the iCalendar parser has no force unwraps. On quit the wake observer is released, both timers invalidated and the audio engine stopped.

## Known limitations

- **The local ICS parser handles a practical subset of RFC 5545.** `FREQ=DAILY/WEEKLY/MONTHLY/YEARLY` with `INTERVAL`, `BYDAY`, `BYMONTHDAY`, `UNTIL`, `COUNT`, plus `EXDATE` and `RECURRENCE-ID` overrides. `COUNT` truncation is approximate for `WEEKLY` with multiple `BYDAY` values.
- **All-day events** appear in the dropdown but not on the strip.
- **Feeds carry no colour of their own**, so blocks are coloured by keyword rules or shown as uncategorized grey.
- **Google's feed cache** means an edit can take a while to reach the app — minutes to hours, and not under the app's control.
- **Single day only.** No multi-day view, no scrolling back.
- **A failed refresh keeps the last good day** for half an hour — the strip shows the error, while the dropdown and the alerts carry on from what was last read. After that it's cleared, since by then it really is unknown.
- **Reading only.** Blocks are added and edited in your calendar, never here — see [Privacy](#privacy).
- **Siri's voice can't be used** for spoken alerts. macOS reserves it; the Premium voices are the answer.

## Privacy

Your calendar data never leaves your machine. The app fetches the feed URL you provide and nothing else — no accounts, no sign-in, no analytics, no telemetry, no third-party services. Events are held in memory only and are never written to disk.

What is stored locally: your settings, saved calendar links and imported keyword rules, all in `~/Library/Preferences/io.github.macos-menubar-rollingcalendar.plist`. No credentials, because there are none to store.

## Disclaimer

**This software is provided free of charge, "as is", without warranty or support of any kind, and is used entirely at your own risk.** It is a glanceable indicator, not a calendar, reminder or timekeeping system — its alerts and chime must not be relied upon as a notification system, and calendar data it shows may be stale, incomplete or absent. It must not be relied upon where inaccuracy, delay or failure could cause loss or harm. If you use a public iCalendar feed, you alone are responsible for what you make public. To the maximum extent permitted by law the author accepts no liability of any kind arising from its use, including missed appointments, disclosure of calendar data, or damage to any machine, system or data.

Not affiliated with, endorsed or supported by Google LLC.

Full terms: [DISCLAIMER.md](DISCLAIMER.md) and the [MIT Licence](LICENSE).

## Contributing

Issues and pull requests are welcome. Keep it dependency-free and keep the idle cost near zero.

## Releases

Versions are tagged and described in [CHANGELOG.md](CHANGELOG.md), which is the only copy of the
notes — `./release-notes.sh 1.6.0` prints one version's section for a release body. The same notes appear on the
[releases page](https://github.com/markpelayo/macos-menubar-RollingCalendar/releases). Each release
carries source only — no app bundle, for the notarisation reason above — so installing a given
version means checking out its tag and running `./build.sh`:

```bash
git checkout v1.6.0
./build.sh
```

## License

MIT © Mark Pelayo — see [LICENSE](LICENSE).
