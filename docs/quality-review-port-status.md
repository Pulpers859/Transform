# Quality Review (PR #2) — Port Status

PR #2 ("App-wide quality review") was written against an **older, flattened**
copy of the codebase. Its fixes were audited one by one against the current
`dev`-based `main`. This file records what was ported, what was already present,
and what remains as follow-up — so the PR branch can be deleted without losing
the findings.

> Note: all ports below were validated by reading + cross-file checks only —
> **not compiled** (no Xcode in the porting environment). Build before relying on them.

## Ported to `main`

- **AI client / parsing**
  - `extractJSON` no longer strips ``` fences blindly (corrupted JSON string
    values); uses a proper escape state machine.
  - Photo encode last-resort respects the 5 MB API cap.
  - Honor server `retry-after` header (cap 30s) on retryable statuses.
  - `BodyAnalysisResult` logs malformed-but-present `macroTargets` /
    `structuredTrainingIntent` instead of silently dropping to fallback.
- **Workout**
  - Disable Delete Program while generating; re-validate program exists after
    the await in `generateNextWeek`.
  - Un-completing a day clears its exercises (no instant re-complete); rollback
    snapshot keyed per object.
  - Rest timer wall-clock anchored (survives lock + fullscreen cover).
  - `decodePreviousWeekSummary` inspects payload keys first (fixes weeks 3-4
    boilerplate progression context).
  - `validateBlueprint` logs empty-intent skips; Generator Lab doesn't re-enable
    Run after cancel.
  - Double-save guard on exercise set logging.
- **Nutrition**
  - Stop cancelling in-flight paid generation on tab switch.
  - `macroTargetLine` fallback uses configured targets, not fixed numbers.
  - Macro estimator uses `extractJSON`; estimate clamped to Save ranges;
    `MacroEstimate` tolerates decimal calories.
  - Per-week source badge (AI Coach / Recovery Engine).
- **Persistence / safety / UI**
  - Backup restore acquires security-scoped access (import from Files/iCloud
    works on device).
  - Suppress automatic backups on the in-memory fallback store.
  - Backup filename uses fixed POSIX/Gregorian locale.
  - Confirm before Restore Defaults.

## Already present in the live app (no action)

- Current model IDs (`claude-opus-4-8` / `claude-sonnet-4-6`).
- `temperature` param and assistant-prefill already removed.
- `max_tokens` truncation already surfaced distinctly (as `parseError`).
- Blank analysis defaults (the Emergency-medicine profile is the sanctioned
  personal-use baseline seed per `CLAUDE.md`).
- Nutrition numeric validation (declared vs meal-sum) already present.
- Macro upper-bound clamps already covered by `BodyAnalysisValidator`.
- Equipment tokens no longer stripped from canonical keys.
- Measurements reachable via a Dashboard NavigationLink (a 5th tab is not added).
- Food-memory search already filters at the store level.

## Deferred — recommended follow-up (needs a build / careful implementation)

Ordered roughly by value:

1. **Nutrition generation error control-flow.** Rethrow cancellation, throw on
   terminal errors, retry only recoverable structured-output failures
   (`NutritionGeneratorService`); view refuses to replace a saved AI protocol
   with fallback output; honest warning haptic; incremental per-week
   persistence (`NutritionView`). Prevents a failed regeneration silently
   overwriting a good saved protocol. Interdependent; needs the recoverability
   predicate matched and a build.
2. **Validator support-credit.** `.support`-grade exercises should earn
   weighted-stimulus credit only, not direct-set credit
   (`WorkoutGeneratorService+PriorityIntent` `directSetCredit` +
   `buildWeekStimulusReport`). High coaching-quality value but changes validator
   credit at 4 sites and will re-flag some weeks — verify generator output.
3. **Backup dedupe keys floor to whole seconds** (`DataBackupManager`). Prevents
   import-into-non-empty-store from duplicating entries (ISO8601 truncates
   sub-seconds). Must update every dedupeKey site, including ones PR #2 missed
   (sleep, performance logs).
4. **AddMeasurementSheet same-day edit-in-place.** Prevents hidden duplicate
   measurement entries. Save-path rewrite that must preserve live-only fields
   (calf measurements, timing flags).
5. **Debounced automatic backup** + `prettyPrinted` flag + `writeAutomaticBackupNow`
   + Restore Auto-Backup UI (`DataBackupManager`, `DashboardView`, `ContentView`).
   Removes per-checkbox main-thread JSON serialization of photo blobs.
   Interdependent threading change.
6. **Decimal-comma locale parsing** (`UserNumberParser` helper) wired into the
   input sheets and settings. Low impact for `.`-decimal locales.
7. **Exercise canonical-key token aliases** (`db`→`dumbbell`, etc.) in
   `WorkoutModels.canonicalLookupKey`. Improves weight-history continuity;
   changes canonical keys (migration consideration).
8. **AddWeightSheet touch-tracking sync guard** — don't discard typed input when
   the date changes. Minor UX.

## Intentionally not ported

- Shift-work persona de-hardcoding: the live app has a first-class shift-work
  nutrition mode + the sanctioned personal-use baseline seed; the wording is
  intentional product surface, not a smuggled assumption.
- Client-timeout retry: the live app deliberately never retries a client-side
  timeout (stricter cost control); PR #2 retried once. Left as the live choice.
