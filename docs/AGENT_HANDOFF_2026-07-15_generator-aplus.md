# Agent Handoff — Generator "A+" Work (2026-07-15)

**Audience:** the next AI agent (or future me) picking up the "make this generator
A+, faithfully working every time" effort. Read this top to bottom before touching
the generator. It is written to hand you the *what*, the *why*, and the *judgment*,
so you can continue with the same success instead of re-deriving everything.

**Owner's standing instruction:** *"I want this generator to be A+, faithfully
working every time. Be completely and brutally honest with me all the time."*
Honor both halves — the quality bar **and** the honesty. Do not soften bad news,
do not claim "verified" for something you only reasoned about, and do not dumb down
training output to satisfy a rigid validator. If the validator is wrong, fix the
validator.

---

## 0. TL;DR — where things stand right now

| Item | Status |
|---|---|
| **Roadmap #2 — headless test harness** | ✅ Built, green on CI, ~10s runtime. The generator now has automated regression coverage for the first time. |
| **Slowness bug** (harness caught it) | ✅ Fixed & CI-verified. Menu phase **~195,000 ms → ~2,000 ms in debug (~95×)**, output numerically identical. |
| **Over-generation bug** (harness caught it) | ✅ Fixed and CI-verified with a sub-region-aware variation policy. All five original legacy combinations run instead of being skipped. |
| **Roadmap #1 — unify credit ledger + generation-time invariant** | ✅ Fixed and CI-verified. Direct sets require primary metadata, each exercise counts once per priority, and allocation asserts equality with validator recomputation. |
| **Phone-free troubleshooting workflow** | ✅ Added and CI-verified. A versioned failure-class fixture pins the allocated menu and validator verdict; a manual live Anthropic contract check is bounded to one HTTP attempt; Claude Code can independently review credential-scanned diffs with no tools. |
| **Roadmap #3 — effort governance + autoregulation loop** | 🟢 Implemented and macOS-CI green; physical-device confirmation remains. Set records now preserve optional RIR, and two corroborating exercise-specific sessions can conservatively override a rep-ceiling load increase to protect recovery. |

**Current troubleshooting checkpoint:** `a768604` on `main`; the shared per-set progression decision, latest-performance-log coverage, optional per-set RIR capture, exercise-specific effort governance, Generator Tests, and full Xcode build are green. The latest billed live contract check passed on `015c3e0`; that headless fixture does not execute the SwiftData-backed `WorkoutView` wiring.

**If you do one thing next:** verify the RIR field and the resulting exercise-specific recovery verdict on the physical device; do not assume completed reps reveal RIR when the field is blank.

---

## 1. The mission and the roadmap

The owner asked a "council of expert agents" for the next 3 steps toward an A+
generator, explicitly assuming the obvious answers were too weak. The three that
survived, in the owner's chosen build order:

1. **Unify the credit ledger + add a generation-time self-consistency invariant.**
   The generator had *five* divergent ways of counting "direct sets" credited to a
   muscle. Different passes (allocation vs validation vs feasibility) could disagree,
   which is exactly how "required weekly volume outran achievable volume" bugs hid.
   Fix: one canonical credit function, and a runtime assertion at generation time
   that the allocator's coverage equals the validator's recomputed report. **(#1)**

2. **Stand up a headless macOS test harness.** End the era of shipping generator
   changes "correct-by-inspection" with no automated verification. Compile the pure
   planning core off-device and run it with `swift test`. **(#2 — DONE)**

3. **Govern effort (RIR/proximity-to-failure) and close the
   performance→prescription autoregulation loop.** Use actual logged performance
   (did you hit the prescribed reps/weight?) to drive progression via
   double-progression. **(#3)**

**Owner's build order:** #2 first, then #1, then #3. #2 and #1 are done. The harness then
*immediately* caught two real bugs (slowness + over-generation), so we detoured to
fix those before #1 — which is correct: a harness that surfaces a bug you then
ignore is theater.

**Note on #3 (owner asked about this directly):** effort/RIR cannot be fully
captured from logged data alone — hitting your prescribed reps tells you about
*progression readiness* (the double-progression trigger) but not *proximity to
failure* (you could hit the reps at RIR 4 or RIR 0). So #3 leans primarily on
existing performance data for the autoregulation loop, and treats explicit effort
as a secondary signal to be added, not the foundation.

---

## 2. What I built today — #2, the headless test harness

### 2.1 The core idea

The iOS app is validated by building in Xcode and running on the owner's physical
iPhone — that is the source of truth for "does it work," and **the simulator is off
the table** (owner's explicit, correct preference). But the generator's *pure
planning logic* — `trainingIntentPlan → programBlueprint → preSelectedExerciseMenu →
validatedProceduralWeekOneProgram` — is ordinary Swift. It needs no iPhone, no
simulator, no network. So it can be compiled and tested on any Mac / GitHub `macos`
runner. That is the entire leverage of the harness: **cover the deterministic core
without needing the device.**

### 2.2 The mechanism (and why it's safe)

- **`Package.swift`** (repo root) — an SPM package that compiles the **real app
  source files in place** (no copies — single source of truth) via an explicit
  `sources` whitelist. Library target is named **`Transform`** (so module-qualified
  refs like `Transform.formatWeight` resolve). Test target
  `TransformGeneratorCoreTests`. Platform `.macOS(.v14)` because SwiftData `@Model`
  types require macOS 14+.
- **`Tests/TransformGeneratorCoreTests/DeterministicGenerationTests.swift`** — the
  tests. `@MainActor` to tolerate actor isolation on the generator surface.
- **`.github/workflows/generator-tests.yml`** — `swift test --parallel` on
  `macos-latest`, `timeout-minutes: 12` so a future runaway can't wall CI.
- **`docs/generator-test-harness.md`** — the living design/usage doc for the harness.

**The one code change outside the package** was making `ClaudeService` compile
off-device. Every generator file is an `extension ClaudeService`, and the base type
imports `UIKit` for the body-analysis photo path (`UIImage`). So `import UIKit`, the
`AnalysisPhoto` struct, and the two `analyzeBody(...)` methods are wrapped in
`#if canImport(UIKit)`. **On the iPhone build `canImport(UIKit)` is true → this is
completely inert, zero behavior change.** On macOS the photo path compiles out and
the core builds. A companion `HarnessShims.swift` supplies `formatWeight` under
`#if !canImport(UIKit)` (the real one lives in the UIKit/SwiftUI `DesignSystem.swift`,
excluded from the package) — so it exists only in the macOS build and never
duplicate-symbols the app.

**Guiding principle for this pattern:** every cross-platform guard is written so the
**device build is unchanged** and only the *test* build sees the shim/compile-out.
If you add to the harness, preserve that invariant religiously — the harness must
never be able to change what ships to the phone.

### 2.3 Convergence — it took 6 CI rounds, and that's the lesson

The harness was authored in a **Linux container with no Swift compiler**, so the
source-dependency closure could only be *guessed* by inspection and then confirmed
by the macOS CI compiler. Each red run named one missing type; I added exactly that
file and re-ran. In order:

1. `WorkoutGenerationDiagnostics` missing; `os_proc_available_memory` unavailable on
   macOS → added the file; platform-guarded the memory call with
   `#if os(iOS) || os(tvOS) || os(watchOS)` (it's `API_UNAVAILABLE(macos)`).
2. `Models.swift` dragged in unrelated types (SleepShiftType, AdaptiveMacroOverride)
   → **removed** Models.swift; nothing in the closure needed it.
3. `AnthropicClient` needed `AppLifecycleSnapshot`; `Config` needed
   `AdaptiveMacroOverride` → added `AppLifecycleMonitor.swift` + `AdaptiveInsights.swift`.
4. `Transform.formatWeight` couldn't resolve (target was mis-named) → renamed target
   to `Transform`, added `HarnessShims.swift`.

**Wisdom for the next agent:** when you cannot compile locally, treat CI as your
compiler and converge **one honest error at a time**. Do not batch-guess five files
at once — you'll mask which one actually mattered and drag in junk (that's exactly
how Models.swift got in and had to come back out). Expect one or two rounds; if
you're on round six, something structural is wrong (here: the transitive UIKit
coupling), so step back and fix the structure, not the symptom.

---

## 3. What I built today — the slowness fix

### 3.1 How the harness earned its keep on day one

On its **first green build**, the harness didn't just pass — it exposed that
generation took **~90 s per program** and the legacy path over-generated wildly.
That is the whole point of #2: a bug that used to surface only as "the generation
felt slow on my phone" is now a measurable number in CI.

### 3.2 Finding the hotspot (measure, don't guess)

I added temporary `PHASE-TIMING` prints around each of the four phases (commits
`67109f0`/`102fa85`, since removed). **100% of the cost was in
`preSelectedExerciseMenu → allocateWeeklySetPrescription`.** Not persistence, not
validation, not the AI path (there is none in this path). Measuring first meant I
fixed the right 5% of the code instead of "optimizing" the innocent 95%.

> Aside: `swift test --parallel` swallows stdout of *passing* tests, so the timing
> prints were invisible until I temporarily ran sequential `swift test`. If you ever
> need to see prints from green tests, run sequentially, then restore `--parallel`.

### 3.3 The root cause

`allocateWeeklySetPrescription` calls `canAddSet` thousands of times. Every call
rescanned *every day × exercise × priority* and, for each, **rebuilt a full
`WorkoutExerciseResponse`** (rep/tempo/rest string formatting, etc.) purely to feed
`stimulusCredit`. But `stimulusCredit` only needs the exercise's **name, muscle
target, and set count** — the expensive string-built fields were pure waste. For
hard-to-fund small muscles the funding loops ran their full 80–160 iterations
without converging, so that O(P×D×E×buildResponse) scan ran over and over.

### 3.4 The fix (commit `afde434`) — and why it's provably identical

Key insight: **`stimulusCredit` is exactly linear in set count, and exercise
identity is fixed during allocation.** Branch selection inside `stimulusCredit`
depends only on the exercise and the area, never on the set count — every branch is
`per-exercise-factor × sets`. So I precompute, once per (day, exercise), each
exercise's **unit** direct-set and weighted-stimulus credit (i.e. credit for a
single set) plus its focus/quality classification and which maintenance groups it
targets:

```
struct ExerciseAccounting {
    var unitDirect:   [Double]  // per priority-allocation index
    var unitWeighted: [Double]
    var qualityScore: [Int]     // prime 30 / secondary 20 / support 10 / none 0
    var groupTargets: [Bool]    // per maintenance-group index
}
```

Then the ledger sums become cheap multiply-adds:
`Double(prescribedSets + extra) * accounting[d][e].unitDirect[allocIndex]` — no
response object is built inside the hot loop. Because credit is linear in sets, the
multiply-add is **numerically the same value** the old rebuild-and-sum produced.

**Result (CI-verified, run #9):** menu phase **194,641 ms → 2,055 ms** in debug
(~95×; sub-second in release on device), **all tests still green**, suite ~10.6 s.
Then `6e11e9c` removed the timing instrumentation and restored `--parallel`.

**Honesty note I gave the owner:** part of the slowness was amplified by my *own*
earlier "Part A" feasibility fix. I said so plainly. The harness is what made that
visible — which is the argument for #2 in one sentence.

### 3.5 The wisdom in this fix

- **Measure before optimizing.** The timing prints paid for themselves instantly.
- **Optimize by removing work, not by micro-tuning.** The win was "stop building an
  object you don't need," not a faster loop.
- **When you change hot math, prove equivalence, don't assert it.** The linearity
  argument is *why* the speedup can't change output — and the green tests confirm it.
- **Leave the code readable.** The precompute block is documented and the old
  `response()` helper is retained where it's still legitimately needed (canAddSet's
  fatigue/session checks). Speed that obscures intent is a net loss on this project.

---

## 4. How to run and verify (for the next agent on a Mac)

```sh
# from repo root, on macOS 14+ with Xcode/Swift toolchain
swift test                 # sequential — shows prints from passing tests
swift test --parallel      # what CI runs
```

CI: `.github/workflows/generator-tests.yml` runs on every push/PR to `main`. It is
**separate** from `swift.yml` (which builds the full iOS app target). Green here
means the deterministic core's regressions are covered; it does **not** replace the
owner's device build for "does the app work."

**Linux/Windows/cloud containers (like the one this was built in) cannot build the
iOS app and cannot run `swift test` against this package** (no Swift for macOS
targets). In those environments your job is **correct-by-inspection** changes plus
CI to compile them. Say exactly that to the owner — never point at the simulator.

---

## 5. The two input paths — internalize this or you'll chase ghosts

The generator is driven two ways and they behave **very differently**:

- **STRUCTURED path** — the analysis carries a `structuredTrainingIntent` (2–3
  balanced priorities with day/exercise targets). **This is what the real AI produces
  and what the owner's real generations go through.** The tests assert this path
  works. This is the path that matters for shipping quality.
- **LEGACY path** — the analysis carries only `priorityMuscles` strings, no
  structured intent. `trainingIntentPlan(from:)` falls back to a weaker builder. This
  path historically over-generated and was slow for concentrated priorities; both
  failure classes now have active regressions.

The tests cover both the production **structured** path and the concentrated **legacy** path.
`testLegacyPriorityMusclesPathRobustness` runs all five original combinations and is no longer
skipped. **Do not "fix" a failure by switching a test to the legacy path
or vice-versa without knowing which path you're on** — they are genuinely different
code and a green light on one says nothing about the other.

---

## 6. Roadmap status and the next build

### 6.1 DONE: over-generation cap (task #9)

**The bug:** concentrated priorities produce far too many *distinct* exercises for a
single muscle in a single week (Arms **21 vs validator cap 4**, Back 11 vs 4). It
lives in the **menu-build** passes (`enforceBaselineMuscleCoverage` +
`enforcePriorityDirectSetFeasibility`), **not** allocation. It's now purely a
*quality* problem (the slowness that used to ride with it is fixed).

**Why it's genuinely bad (not just a validator complaint) — and the owner and I
explicitly aligned on this:**

- Hypertrophy needs **progressive overload on repeated lifts**; 21 bicep movements
  = ~1 set each, nothing to progress or even track. Double-progression (the app's
  autoregulation basis, and the foundation of roadmap #3) becomes impossible.
- Volume spread across 20 movements is **junk volume** — no exercise crosses the
  ~2–4 hard-sets threshold that actually drives adaptation.
- It kills the **skill/loading ramp** (you get strong at a movement only if it recurs).

**The agreed design principle:** *wide catalog, narrow weekly prescription.* The
exercise **database must stay fully broad** — breadth is what lets the generator
*tailor* selection to equipment/patterns/priorities, and variety belongs **across
weeks/mesocycles** (rotation), not crammed into one week. The cap constrains only
**how many distinct exercises land in one week for one muscle**, not what the
generator knows.

**Build it sub-region-aware, not as a blunt count.** A flat "4 per area" is wrong
for genuinely multi-region groups: **Back** legitimately spans lats vs upper-back vs
lower-back across different planes; give each real sub-region its own small
allowance (e.g. 4 for lats *and* 4 for upper back) rather than one flat number that
either starves a big group or bloats a small one. For a truly single-target muscle
(biceps, lateral delts) a low flat cap (~3–4/week) is right.

**Implemented outcome:** menu selection and feasibility share a primary-target,
sub-region-aware variation budget. Back width and upper/mid-back are separate buckets;
small single-target areas use tighter caps. Once a bucket is full, compatible established
movements can recur across days (including `Lower`/`Legs` label boundaries) instead of
creating more identities or emitting a short menu. The legacy matrix and structured-path
variation assertions both run in CI.

### 6.2 DONE: roadmap #1 — unify credit ledger + generation-time invariant

The former counters now delegate to one rule: direct sets require an intersection
between the requested priority aliases and the exercise's declared **primary** metadata.
Focus heuristics and secondary metadata can add weighted stimulus but never direct sets.
`WeekStimulusReport` retains per-exercise entries so broad areas count each exercise once
instead of summing duplicate metadata buckets. After allocation,
`allocationLedgerConsistencyIssues` compares allocator totals with validator recomputation;
a runtime assertion and dedicated harness test fail on any divergence.

### 6.3 IN PROGRESS: roadmap #3 — effort governance + autoregulation loop

Close the performance→prescription loop using logged performance (hit prescribed
reps/weight → double-progression advance). The app now centralizes that decision and
feeds the same per-set evidence to the generation verdict path; deterministic tests now
cover mixed-set, failed-set, legacy-summary, latest-usable-log, and repeated-effort-signal
cases. Existing session feedback now produces a conservative, deterministic governance
signal for next-week generation. Explicit per-set RIR is now an optional, backward-compatible
field on each logged set, and the shared progression engine uses two complete, exercise-specific
RIR sessions before it can emit a recovery-protection verdict. Missing or partial RIR remains
insufficient evidence, so legacy logs retain the rep/load-only behavior (see §1 note — logged
reps alone can't see proximity-to-failure).

---

## 7. Landmines — do not relearn these the hard way

- **Repo is `main`-only.** Commit directly to `main`, push to `origin/main`,
  **fast-forward only. NEVER `git push --force`/`--force-with-lease` to `origin/main`.**
  Before committing, verify `git rev-list --left-right --count origin/main...main`
  is `0 0` and `git merge-base main origin/main` is **non-empty** — an empty
  merge-base means you're on a **stale/unrelated local `main`** (a documented past
  incident that "gets my data lost"). Re-point with
  `git checkout -B main origin/main` before doing anything. Sanity-check the tree
  exists (e.g. `Transform/Transform/WorkoutGeneratorService.swift`; ~49 tracked
  `.swift` files).
- **Never suggest the iOS Simulator.** Owner validates on a physical iPhone by
  choice (haptics, camera/body-analysis, true on-device feel). When you can't build,
  say "correct-by-inspection — build & run on your iPhone to confirm."
- **Cross-platform guards must keep the device build byte-for-byte unchanged.**
  `canImport(UIKit)` is true on device → all harness guards are inert there. If you
  add a shim, gate it `#if !canImport(UIKit)` so it can't collide with the app.
- **`PersonalProfileSeed` in `Config.swift` holds real owner data on purpose.** It is
  **not** a security bug to "fix." Leave it.
- **Product priority order** (when trade-offs collide): (1) workout quality,
  (2) evidence-informed integrity, (3) robustness / silent-bug prevention,
  (4) validator correctness, (5) reduce API waste, (6) maintainable architecture.
  **Do not dumb down training output to satisfy a rigid validator — improve the
  validator.**
- **Respect the split `WorkoutGeneratorService` architecture** (~11 `extension
  ClaudeService` files). Don't collapse it.
- **Do not put the model identifier in commits/PRs/code/docs.** Chat only.
- **Measure before optimizing; prove equivalence when you change hot math.** (See §3.)

---

## 8. File map (what changed / matters today)

| File | Role |
|---|---|
| `Package.swift` | SPM harness manifest (target `Transform`, explicit `sources`). |
| `Tests/TransformGeneratorCoreTests/DeterministicGenerationTests.swift` | Structured and legacy generation regressions, variation policy, canonical credit semantics, complete-menu checks, and allocator/validator consistency. |
| `.github/workflows/generator-tests.yml` | `swift test --parallel` on macOS, 12-min cap. |
| `docs/generator-test-harness.md` | Harness design/usage (living doc). |
| `Transform/Transform/HarnessShims.swift` | `formatWeight` shim, `#if !canImport(UIKit)` only. |
| `Transform/Transform/ClaudeService.swift` | 3 `#if canImport(UIKit)` guards (photo path). Inert on device. |
| `Transform/Transform/WorkoutGeneratorService.swift` | `availableMemoryMB()` platform-guarded off macOS. |
| `Transform/Transform/WorkoutGeneratorService+ExerciseSelection.swift` | Precomputed allocation ledger, weekly variation enforcement, compatible established-exercise reuse, and the allocation/validator consistency assertion. |
| `Transform/Transform/WorkoutGeneratorService+PriorityIntent.swift` | Canonical direct/weighted credit semantics and per-exercise validator coverage recomputation. |

**Key commits:** `afde434` (perf fix), `c686eac` through `fc4749c` (variation policy,
feasibility fixes, diagnostics), and `1f412b6` (canonical ledger and cross-style reuse).
All are on `main`; the final implementation checkpoint passed both workflows.

---

## 9. One-paragraph orientation for a cold-start agent

Read `CLAUDE.md` (root) first, then this file, then
`docs/generator-test-harness.md`. The generator's deterministic core is covered by a
headless macOS `swift test` harness (roadmap #2, done). It caught a ~95× slowness bug,
legacy over-generation, short late-week menus, and disagreement between allocation and
validation. The variation policy and canonical direct-set ledger are now implemented and
CI-green (roadmap #1, done). Roadmap #3 is implemented in code: the shared per-set
performance→prescription decision path, conservative session-level effort governance, optional
per-set RIR capture, and exercise-specific multi-session effort signal are in place. The
remaining proof is macOS CI plus the owner's physical-device persistence and generation run.
Commit to `main`, fast-forward only, never force-push, never suggest the simulator,
and be brutally honest with the owner — that's the job.
