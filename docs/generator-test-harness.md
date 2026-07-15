# Generator Test Harness

Headless, network-free regression coverage for Transform's deterministic
workout-generation core. This is step #2 of the "A+ generator" roadmap: it ends the era
of shipping generator changes "correct-by-inspection" with no automated verification.

## Why

The iOS app is validated by building in Xcode and running on a physical iPhone — the source
of truth for "does it work." But the generator's *pure planning logic* (menu-lock → weekly
set allocation → validation → procedural fallback) is ordinary Swift that does **not** need
an iPhone, a simulator, or the network to run. Until now it had zero automated tests, so a
whole class of bugs (the "required vs achievable weekly volume" drift) could recur silently
and only surface as a failed generation on device.

This package compiles **only** that core plus its model dependencies and exercises it with
plain `swift test` on any Mac or a GitHub `macos` runner.

## What it is

- **`Package.swift`** (repo root) — an SPM package with one library target,
  `Transform`, that compiles the **real app source files in place** (no copies,
  single source of truth) and one test target, `TransformGeneratorCoreTests`.
- **`Tests/TransformGeneratorCoreTests/`** — the tests.
- **`.github/workflows/generator-tests.yml`** — runs `swift test` on `macos-latest`.

The Xcode app target (`Transform/Transform.xcodeproj`) is **not touched**. The project uses
Xcode 16 synchronized folders, so no `project.pbxproj` changes are involved.

### The one code change outside the package

`ClaudeService.swift`'s body-analysis photo path uses `UIKit` (`UIImage`), which does not
exist on macOS. Since every generator file is an `extension ClaudeService`, the base type
must compile off-device. The `AnalysisPhoto` struct, the two `analyzeBody(...)` entry
points, and `import UIKit` are wrapped in `#if canImport(UIKit)`. On iOS/device builds
`canImport(UIKit)` is **true**, so this is completely inert — no behavior change. On macOS
the photo path compiles out and the generator core builds.

## Running it

```sh
# from the repo root
swift test
```

macOS 14+ is required (SwiftData `@Model` types).

## First-run: finalizing the source closure

The `sources` list in `Package.swift` is the deterministic-generator dependency closure as
determined by inspection. Swift's transitive type resolution can only be confirmed by a
compiler, and this harness was authored in a Linux container without one. The **first**
`swift build` on a Mac may report:

```
error: cannot find type 'SomeType' in scope
```

Fix: add the file under `Transform/Transform/` that defines `SomeType` to the `sources`
array in `Package.swift`. Every candidate file is Foundation / SwiftData / SwiftUI only
(no UIKit), so adding it is safe. Repeat until the build is clean — expect one or two
rounds, not a rewrite. If SPM complains about unhandled resource files in the target path,
add them to an `exclude:` list on the target.

## Two input paths (this matters)

The generator can be driven two ways, and they behave very differently:

- **Structured path** — the analysis carries a `structuredTrainingIntent` (2-3 balanced
  priorities with day/exercise targets). This is what the AI produces in normal use and what
  the owner's real generations go through. The tests assert this path works.
- **Legacy path** — the analysis carries only `priorityMuscles` strings.
  `trainingIntentPlan(from:)` falls back to a weaker builder.

### Regression: legacy-path over-generation

On its first green build the harness caught a real bug: on the **legacy path**, concentrated
priorities produced up to **~20 reported exercise variations for one area** and took about 90
seconds per generation. The performance issue was fixed by precomputing set-credit accounting.
The variation issue had two causes: the validator mixed secondary-stimulus compounds into the
variation count, while menu selection and feasibility passes preferred or required unused
movements across days. The regression now has a shared primary-target, sub-region-aware weekly
variation policy and `testLegacyPriorityMusclesPathRobustness` runs instead of being skipped.

The re-enabled legacy matrix then exposed a deeper accounting defect: allocation treated
secondary/focus matches as fractional direct sets, while validation counted declared primary
metadata. Broad multi-primary areas could also be double-counted. Direct volume now has one rule:
an exercise's declared primary metadata must intersect the requested priority aliases, and each
exercise is counted once per priority. Secondary work remains weighted stimulus. A planning-time
assertion and harness test require allocator totals to equal validator recomputation. Compatible
established exercises can also repeat across labels such as `Lower` and `Legs`, avoiding short
late-week menus without inflating exercise variation.

## What the current tests cover

`DeterministicGenerationTests` runs the full network-free chain
(`trainingIntentPlan → programBlueprint → preSelectedExerciseMenu →
validatedProceduralWeekOneProgram`) and asserts:

1. **`testUpperChestLateralDeltReproductionDoesNotHardFail`** — faithful reproduction of the
   reported bug via the **structured** path: Upper Chest + Lateral Deltoids must not throw.
2. **`testRealisticStructuredIntentsGenerate`** — a few realistic structured intents (back,
   arms, legs) must all generate. This is where "works every time" starts to become provable.
3. **`testGeneratedProgramIsStructurallyComplete`** — a produced week has 7 days, at least
   one training day, a name, and no empty training days.
4. **`testStructuredPlansRespectWeeklyVariationBudgets`** — production-like structured Back
   and Arms plans must remain inside the weekly variation policy.
5. **`testBroadBackVariationBudgetIsSubregionAware`** — four lat and four upper/mid-back
   movements fit separate buckets, while a fifth lat movement is rejected.
6. **`testLegacyPriorityMusclesPathRobustness`** — the concentrated legacy combinations from
   the original failing sweep must produce complete locked menus, generate, and remain inside
   variation budgets.
7. **`testDirectSetCreditRequiresPrimaryMetadataMatch`** — secondary/focus heuristics can add
   weighted stimulus but cannot masquerade as direct priority volume.
8. **`testAllocatedMenusMatchValidatorStimulusLedger`** — allocator and validator totals must
   remain identical for the historically failing concentrated priorities.

The CI job has a 12-minute timeout so a future runaway cannot wall the pipeline.

## Where it's going

- **Golden fixtures** — freeze `(analysis, blueprint) → allocated menu + validator verdict`
  snapshots for the cases that have bitten us (recovery-tight, zero-hamstring, multi-primary
  lower body) so silent output drift fails CI.
- **Effort governance and autoregulation (roadmap #3)** — connect logged performance to the
  next prescription through double progression, with explicit RIR as a separate signal rather
  than inferring proximity to failure from completed reps alone.
