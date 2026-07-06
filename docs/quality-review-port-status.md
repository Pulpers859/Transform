# Quality Review (PR #2) — Port Status

PR #2 ("App-wide quality review") was written against an **older, flattened**
copy of the codebase. Its fixes were audited one by one against the current
current `main`. This file records what was ported, what was already present,
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
  - Nutrition regeneration preserves an existing saved AI protocol if the new
    run degrades to Recovery Engine fallback output.
  - Validator stimulus accounting separates support/corrective stimulus from
    direct-set target coverage.
  - Backup dedupe keys floor dated records to whole seconds to avoid duplicate
    imports from sub-second timestamp differences.
  - Add Measurement updates an existing same-day measurement instead of creating
    a hidden duplicate.

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

1. **Nutrition generation error control-flow, remaining hardening.** The view now
   refuses to replace a saved AI protocol with Recovery Engine fallback output,
   but `NutritionGeneratorService` still needs a recoverability predicate so it
   throws on terminal API errors and retries only structured-output failures.
   Incremental per-week persistence also remains build-worthy follow-up.
2. **Debounced automatic backup** + `prettyPrinted` flag + `writeAutomaticBackupNow`
   + Restore Auto-Backup UI (`DataBackupManager`, `DashboardView`, `ContentView`).
   Removes per-checkbox main-thread JSON serialization of photo blobs.
   Interdependent threading change.
3. **Decimal-comma locale parsing** (`UserNumberParser` helper) wired into the
   input sheets and settings. Low impact for `.`-decimal locales.
4. **Exercise canonical-key token aliases** (`db`→`dumbbell`, etc.) in
   `WorkoutModels.canonicalLookupKey`. Improves weight-history continuity;
   changes canonical keys (migration consideration).
5. **AddWeightSheet touch-tracking sync guard** — don't discard typed input when
   the date changes. Minor UX.

## Intentionally not ported

- Shift-work persona de-hardcoding: the live app has a first-class shift-work
  nutrition mode + the sanctioned personal-use baseline seed; the wording is
  intentional product surface, not a smuggled assumption.
- Client-timeout retry: the live app deliberately never retries a client-side
  timeout (stricter cost control); PR #2 retried once. Left as the live choice.
