# Apple Health Sleep Import

## Why this exists

The 3-tap quick log reconstructs *when you slept* from *when you opened the app*. Log at
10:38 AM and wake time is recorded as 10:38 AM — the "human as clock" flaw behind the
wake-time skew. The structural fix is to read a real slept interval from a sensor source
instead of from app-open time.

Apple's own Sleep feature (Sleep Schedule / Sleep Focus) records dated in-bed / asleep
intervals to HealthKit **with no Apple Watch required** — the iPhone is the sensor. And
`SleepEntry` was already interval-based (`resolvedStartDate` / `resolvedEndDate`), so
importing is an input-source swap, not a rewrite: every downstream consumer (trend
builder, recovery modulation, dashboard rings) is untouched.

## Architecture

| Layer | File | Built where | Tested |
| --- | --- | --- | --- |
| Pure reconcile core (coalesce, plausibility, never-overwrite-manual) | `SleepHealthImportCore.swift` | Foundation-only, in the SwiftPM harness | `SleepHealthImportCoreTests` |
| HealthKit I/O (query, map samples, apply to SwiftData) | `SleepHealthKitService.swift` | iOS only (`#if canImport(HealthKit)`) | correct-by-inspection + device |
| Model tag | `SleepEntry.source` (`.manual` / `.healthKit`) | app | — |
| Settings screen | `SettingsSleepImportView.swift` | app | device |
| Foreground auto-sync (throttled 15 min) | `DashboardView.autoImportSleepIfEnabled()` | app | device |

All the decision logic — the part most likely to be wrong — is in the Foundation-only
core behind the headless test harness. The HealthKit file only does I/O.

### The rules the core enforces

- **Coalescing.** HealthKit returns fragmented per-stage rows; segments within 60 min
  merge into one night. When any "asleep" segments exist for a night the interval is the
  asleep extent (trimming lie-awake in-bed time); otherwise it falls back to the in-bed
  extent (iPhone-only schedule data).
- **Plausibility.** A cluster shorter than 2.5 h (a 2 a.m. phone check, an afternoon nap)
  is never recorded as a main sleep, so noise can't fake a short night and suppress
  training. A genuine on-call short night of ~3 h is above the floor and is kept. Spans
  over 16 h are treated as overlapping-source noise and skipped.
- **One main sleep per wake-day** — the longest plausible cluster ending that day.
- **Never overwrite a manual log.** A night you logged by hand always wins; the importer
  only fills days you left blank. Re-syncing updates the importer's own row in place
  (idempotent), so nothing duplicates. Editing an imported night in the full editor
  promotes it to `.manual`, locking your correction against future syncs.

Unrated imported nights (quality 0) are excluded from the quality average and the
quality/duration mismatch check in `SleepAggregationCore`, so an import never drags
recovery around on quality it doesn't actually have.

## Owner setup — required one-time Xcode step

The code, the `NSHealthShareUsageDescription`, and `Transform.entitlements`
(`com.apple.developer.healthkit`) are committed. HealthKit also has to be turned on for
the App ID, and that part lives in the signing portal, which only Xcode can do:

1. Open the project → **Transform** target → **Signing & Capabilities**.
2. Click **+ Capability** and add **HealthKit**. (Leave "Clinical Health Records" off.)
   Xcode registers the capability on the App ID and confirms the entitlement file. If it
   offers to create its own entitlements file, point it at the committed
   `Transform/Transform.entitlements` instead of adding a second one.
3. Build and run on your iPhone.

## Testing on device

1. In the Health app: **Browse → Sleep → set up a Sleep Schedule** if you haven't. Let it
   record at least one night (or add a sample night by hand in Health).
2. In Transform: **Settings → Sleep Source → Import from Apple Health**. Approve the
   permission sheet.
3. It imports the recent window immediately; "Sync Now" repeats it, and returning to the
   dashboard re-syncs (throttled to once per 15 min).
4. Confirm the imported night appears in sleep history and the dashboard, and that a night
   you had already logged by hand is untouched.

## Honest limitations

- **Requires the system Sleep feature to be set up.** No Sleep Schedule = no data to
  import; the screen says so rather than inventing a night.
- **iPhone-only data is "time in bed," not sleep stages.** It's a real recorded interval —
  a large upgrade over app-open time — but coarser than a watch. If a watch is ever worn,
  its asleep segments are preferred automatically.
- **HealthKit hides whether read access was granted.** A completed sync with zero nights
  can mean "no data" or "access declined"; the UI copy is worded to cover both.
- **Read-only.** Transform never writes sleep back to Apple Health.
