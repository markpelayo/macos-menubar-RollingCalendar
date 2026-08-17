# Example calendars

Test data on a clean 15-minute grid, for checking that the strip moves and draws correctly.

All three use **floating local times** — no `TZID`, no `Z` suffix, no `VTIMEZONE` block. Per RFC 5545 that means "interpret in local time", so the same file lands on correct quarter-hours wherever you are, and there's no time zone machinery for an importer to mishandle.

| File | Events | Notes |
|---|---|---|
| `15min-blocks-recurring.ics` | 96 | Repeats daily until 2030. Smallest file |
| `15min-blocks-30days.ics` | 2880 | No `RRULE` at all — 30 concrete days from 2025-01-01 |
| `4-events-diagnostic.ics` | 4 | Import smoke test. If this fails, the problem isn't the file |

Every file is validated: exactly 15-minute durations, **0 overlaps, 0 gaps**, all starts on `:00/:15/:30/:45`, CRLF line endings, no line over 75 octets, pure ASCII, unique UIDs, balanced `BEGIN`/`END`.

Titles carry their own start time — `Email triage 09:15 (15M)` — so alignment is self-checking: that block must sit exactly one grey tick right of the 09:00 black line.

## Importing into Google Calendar

**Create a new calendar first.** Thousands of test events are miserable to delete individually and trivial to drop as a whole calendar.

1. Google Calendar → **Other calendars** → **+** → **Create new calendar**
2. Name it something like `ZZ Test Blocks` → **Create**
3. ⚙️ **Settings** → **Import & export** → **Import**
4. Pick the `.ics` file, set *Add to calendar* to `ZZ Test Blocks` → **Import**
5. In the app: strip → **Choose Calendar** → `ZZ Test Blocks`

To clean up: Settings → your test calendar → **Remove calendar** → *Delete*.

### If Google refuses the import

Google's "Oops, we couldn't import this file" is generic and tells you nothing. Try, in order:

1. **`4-events-diagnostic.ics`** — if four events won't import, no file will, and the problem is on Google's side
2. `15min-blocks-30days.ics` — rules out recurrence handling
3. Import into a calendar **you own**; shared or subscribed calendars can't be imported into
4. A different browser or incognito window — extensions do break the import dialog
5. Check the download didn't land as `.ics.txt`
6. Wait and retry; the error is sometimes genuinely transient

Or skip Google entirely: **Demo Mode** generates the same grid inside the app, and pointing **Set Calendar Link…** at `file:///absolute/path/to/15min-blocks-recurring.ics` reads a local file directly (that path exercises the app's own ICS parser, which is a useful A/B against the Google path).

## Adding colour

`.ics` has no colour field, so imported blocks all take the new calendar's colour. To see per-event colouring, open a few events in Google Calendar and assign different colours by hand — those are the `colorId` values the API returns. Requires Google sign-in; feed mode stays green.

## Regenerating

These are generated files. The grid is: 96 slots per day, `slot = index × 15 min`, titles chosen by local hour to resemble a plausible day (sleep overnight, meals, focus blocks, wind-down). Nothing here refers to a real person's schedule.
