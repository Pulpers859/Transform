# Uncertainty Register

Honest accounting of what the 2026-07-05 skill-library review did and did not verify. Status language: `verified` (checked directly this pass), `unverified` (asserted somewhere but not checked), `stale-risk` (was true, likely to drift), `owner-confirmation-needed`.

## Verified this pass (2026-07-05, commit `0a68ce9`)

- Repo layout, remote, branch sync; exactly 49 tracked Swift files; app source at `Transform/Transform/` (NOT the triple-nested path older docs cited — now fixed).
- `swiftc -parse` works on this Windows machine (Swift 6.3.1) as a syntax-only smoke check.
- `.github/workflows/swift.yml` contents; no tracked shared `.xcscheme`.
- Data-safety symbols and locations: `canonicalLookupKey` (WorkoutModels.swift:343), `ExerciseWeightStore` (:622), `normalizePerformanceLogs` (:713), `DataIntegrityMonitor` (TransformApp.swift:129).
- All commit hashes cited in the incident log exist in `git log`.

## Unverified / not checked

- **Incident narratives beyond commit messages**: ~~not re-read line-by-line~~ **UPDATED 2026-07-06**: the full generator audit read `FallbackCore`, `ParsingValidation`, `ExerciseSelection` (menu path), `WorkoutGeneratorService`, `Requests`, `AnthropicClient`, `WorkoutModels`, `DataBackupManager` (backup/restore/counts), and the workout UI line-by-line. INC-3–INC-6 mechanism descriptions matched the code as of commit `6283053`.
- **`repairedProceduralDays` / `injectAccessoryExercise` / `isHeuristicValidationIssue` / `rebalanceDirectSets`**: behavior under menu-locked mode read line-by-line 2026-07-06 and consistent with the incident log (no injection/removal when menu-locked; set-boost with focus-budget trim; overshoot budget respected).
- **Not line-by-line audited 2026-07-06**: `WorkoutGeneratorLabView` (debug tool), `MetadataProfiles` (data tables; spot-checked `exerciseMatchesDayStyle`), `TrainingIntentBlueprint`/`PriorityIntent` beyond blueprint invariants (7 day plans, 4-6 training days verified), non-workout views.
- **RESOLVED 2026-07-05**: the four `swiftui-*` skills (`swiftui-ui-patterns`, `swiftui-liquid-glass`, `swiftui-view-refactor`, `swiftui-performance-audit`) are retired — owner confirmed they no longer exist anywhere. They originated from the Builder.io skills evaluation (`docs/AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md`). All references removed from `transform-design-research`, `CLAUDE.md`, and `AGENTS.md`.
- **External design sources** (Refero, UI UX Pro Max, UX Components, 21st.dev): availability is session-dependent; not tested this pass.
- **`.github/workflows/claude.yml`**: existence verified; contents/purpose not reviewed.
- **`repomix` availability** on this machine: referenced in docs, not tested.
- **Design-token count "526+"** (memory note, 2026-06-14): not re-counted. `stale-risk`.
- **EvidenceProfile.md rule table**: read in part (through the rule table and operational notes); tail of file (~last sections) skimmed only.

## Deliberately omitted (not gaps)

- No "research-frontier" or "hardest-problem-campaign" skills (from the source methodology): the current hardest problems are already encoded as live audit questions in `transform-generator-audit`; a separate campaign doc would go stale fast in a solo repo.
- No per-skill `evals/trigger_eval.json` files (methodology suggests 20+ scenarios per skill): compressed into the README trigger matrix. Revisit if skill mis-triggering is actually observed.
- No separate architecture-contract skill: the split-generator contract lives in `Transform/Transform/CLAUDE.md` and `transform-generator-audit`, which are always loaded for relevant work.

## Standing invariants to re-check when citing this register

- Swift file count (currently 49) drifts with normal work — always re-run `git ls-files "*.swift" | wc -l`.
- Line numbers in `transform-data-safety` drift — always re-grep before citing.
