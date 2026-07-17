# Transform_clean Project Workflow

This file is the Transform-specific workflow reference for the repo at `C:\Dev\Transform_clean`.

## Identity
- Repo root: `C:\Dev\Transform_clean`
- App container folder: `C:\Dev\Transform_clean\Transform`
- Main Swift source tree: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`
- GitHub remote: `https://github.com/Pulpers859/Transform.git`
- Stable branch: `main`
- Default working branch: `main`

## Current Standing Snapshot (last verified 2026-07-17)

- **Repository:** `main` is synchronized with `origin/main` at `5a77c06`; the local tracked Swift tree contains 56 files.
- **Generator:** the recent zero-direct-set incident was traced to the locked preselected-menu planner omitting a baseline muscle group. The fix is in menu planning: baseline coverage is enforced, feasible replacement passes protect the existing menu, and a repeated append-only final repair pass closes any remaining legal gap. This is a root-cause planning fix, not workout trimming or warning demotion.
- **Automated proof:** Generator Tests run `29554714005` and Swift/Xcode run `29554714003` passed on `5a77c06`; the generator target executed 26 XCTest cases, including four deterministic nutrition stress tests. Live workflow run `29555834641` passed both selected live contracts, with workout and nutrition each succeeding on the first Anthropic attempt.
- **Nutrition audit:** target safety resolution is shared by prompt, validator, and fallback; meal/template calories and all macro sums are checked; meal order, substitutions, grocery quality, source provenance, and fallback transitions are covered. New generation makes one 7-day request and does not automatically generate Weeks 2–4. The live troubleshooting workflow now has independent workout and nutrition switches, so nutrition-only validation does not invoke the workout generator.
- **Still unproven:** the Windows agent cannot build the iOS app; CI does not prove SwiftData/UI behavior; deterministic fixtures do not prove every profile; the latest Claude second audit was incomplete due session limits. The owner's physical-iPhone build and real generation remain the final runtime check.

When this snapshot is used, verify the current commit and workflow runs first. Report evidence separately as code/tests, bounded live workflow, or physical-device validation.

## Why This Structure Matters
This repo is not a flat app root.
- The Git repo root is `Transform_clean`
- The actual app lives inside the nested `Transform\Transform` tree
- A new agent must understand that distinction before editing files or making assumptions about the project layout

## Required Working Assumptions
- Treat `C:\Dev\Transform_clean` as the source-of-truth repo.
- Treat `C:\Dev\Transform_clean\Transform\Transform` as the main app target for SwiftUI, generator logic, persistence, and evidence-profile work.
- Ignore older copies unless explicitly asked:
  - `C:\Dev\Transform`
  - `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Transform`
- Sync from GitHub first when the repo is clean.
- Keep routine work on `main`.
- Commit directly to `main` and push to `origin/main` after completed changes.

## Product Constitution
Transform is not a generic fitness toy. It should behave like a careful hybrid of:
1. a senior iOS / Swift / SwiftUI / SwiftData app
2. an evidence-informed hypertrophy coaching system

### Product priorities
1. Workout quality
2. Evidence-informed programming integrity
3. Robustness and silent-bug prevention
4. Validator correctness
5. Reducing wasted AI / API usage
6. Maintainable architecture

## Personal Baseline Context
- This build is intentionally used as a personal app.
- Keep generic fallback defaults neutral in code when practical, but it is acceptable to seed Patrick's editable analysis profile into local app settings at startup as a one-time baseline.
- Do not silently turn that personal baseline back into generic hardcoded prompt defaults.

### Non-negotiables
- Fix root causes, not cosmetic symptoms.
- Do not dumb down training output just to satisfy a rigid validator.
- If the validator is wrong, improve the validator.
- Keep evidence/profile logic, metadata logic, blueprint logic, validation logic, and fallback logic in sync.
- Do not silently tolerate brittle fallbacks, stale prompt assumptions, or naming drift that fragments progression tracking.
- Distinguish evidence-backed guidance from heuristic choices.
- Preserve the app's existing style and user-facing experience unless a change is explicitly requested.

## Repo / Git Workflow
### Before normal work
1. `git fetch --prune`
2. if the working tree is clean, `git pull --ff-only`
3. confirm current branch is `main`
4. inspect `git st` and `git diff` before editing

### Everyday flow
```powershell
git fetch --prune
git pull --ff-only
git st
git diff
git add .
git commit -m "Describe the change"
git push
```

### Promotion flow
Routine work does not use a promotion branch. Commit directly to `main` and push fast-forward changes to `origin/main`.

## PowerShell / Local Environment
- Do not globally pin every PowerShell session to the repo.
- Use a dedicated project shortcut instead.
- The shortcut should open in `C:\Dev\Transform_clean`.
- Avoid brittle launch arguments for paths with apostrophes.

## Secrets / Credential Handling
- Do not treat repo-tracked files as a safe place for live credentials.
- The Anthropic API key is entered in-app and stored in iOS Keychain. Build-time key injection has been removed.
- Do not reintroduce build-time key fallbacks (xcconfig, Secrets.plist, Info.plist key).
- Before first push of a new app, run a secret scan.

## Engineering / Architecture Expectations
- Respect the split `WorkoutGeneratorService` architecture.
- Keep the following aligned:
  - prompt/request construction
  - parsing/sanitization
  - metadata/evidence mapping
  - training intent / blueprint generation
  - validator logic
  - fallback generation / repair
  - UI state / persistence / backup behavior
- When a file becomes a maintenance risk, refactor carefully instead of layering more ad hoc logic into it.

## Fragile Areas To Audit Repeatedly
- workout-generator quality vs validator outcome
- fallback underdelivery relative to blueprint targets
- metadata aliasing / muscle-target drift
- weight-history continuity caused by naming variation
- source badges and summaries drifting from actual generation path
- async SwiftUI task ownership and state updates after dismissal
- save / rollback / backup consistency
- stale decoded analysis or stale cached data reuse
- API-credit waste from doomed retries or overly rigid acceptance logic

## Known Workout Generator Failure Modes (May 2026 Postmortem)

### 1. App crash during sanitization — duplicate key in exerciseNameAliasCache
**Symptom**: App closes silently during Week 1 generation. Diagnostics stage reads "sanitize d1/7.e1/6 name" or similar. Elapsed time ~100-113 seconds.
**Root cause**: `Dictionary(uniqueKeysWithValues:)` in `exerciseNameAliasCache` (MetadataProfiles.swift) crashes with a fatal error when two entries normalize to the same key. Example: "Band Pull Aparts" and "Band Pull-Aparts" both normalize to "band pull aparts" because `normalizedExerciseNameKey` strips hyphens.
**Fix**: Use a safe dict-building loop (`var dict = [String: String](); for (key, value) in entries { dict[normalizedExerciseNameKey(key)] = value }`) instead of `Dictionary(uniqueKeysWithValues:)`. Also check `exerciseMetadataCatalogCache` for the same pattern.
**How to detect**: If the app crashes (not an error message, but the app literally closes) during generation, check UserDefaults crash breadcrumbs via `WorkoutGenerationDiagnostics.consumeUnexpectedTerminationMessage()`. If the stage mentions "sanitize" and a specific exercise position, suspect a `Dictionary(uniqueKeysWithValues:)` crash in a lazy cache.

### 2. Parse error "Procedural fallback generated an invalid Week 1 program" — blueprint target misses
**Symptom**: Error message with "missed its direct-set target", "missed its frequency target", or "undershot its weighted stimulus target" for specific muscle groups.
**Root cause (validation too strict)**: The validator had ~40 quality-related checks as hard failures. Near-misses in blueprint targets (e.g., 11/12.5 direct sets = 88%) rejected the entire output. Both AI attempts and the procedural fallback would fail, leaving the user with an error.
**Root cause (fallback can't meet targets)**: The procedural fallback repair loop (`repairedProceduralDays` in FallbackCore.swift) could only bump set counts on exercises that already existed on a day. It could not inject new exercises onto days that lacked coverage for an under-served priority. Example: Posterior Deltoids needs 2-day frequency but only 1 Pull day had a Face Pull — the repair loop couldn't spread rear delt work to a second day.
**Fix**:
  - `isHeuristicValidationIssue` (ParsingValidation.swift): expanded to cover all quality/near-miss issues as warnings. Only structural integrity checks (empty fields, wrong day counts, invalid ranges) remain as hard failures.
  - `injectAccessoryExercise` (FallbackCore.swift): new function that injects exercises from the priority's accessory catalog when a candidate day has zero matching exercises. Checks `exerciseMatchesDayStyle` to avoid injecting Pull exercises onto Push days.
  - `repairCandidateDayNumbersExpanded` (FallbackCore.swift): when frequency target is unmet, expands candidate days beyond focus/support to include any style-compatible training day.
**How to detect**: If the error says "Procedural fallback generated an invalid Week 1 program", check the specific issues listed. If they are all quality/near-miss issues (not structural), the fix is in `isHeuristicValidationIssue`. If a specific muscle group is severely under-served (< 70% of target), the fix is in the repair loop's injection and candidate day expansion logic.

## Agent Working Style
- Inspect current code before assuming prior context is still accurate.
- Make direct changes when the path is clear.
- After each fix, do another harsh adjacent-risk pass.
- If something cannot be fully validated in the current environment, say exactly what was and was not validated.
- On Windows, use the Swift sanity check for smoke validation when possible.
- On macOS, prefer real Xcode builds. Runtime validation belongs on the owner's physical iPhone; do not suggest or wait on the iOS Simulator.

## Recommended Repo-Local Companion Files
- `docs/2_PROJECT_HANDOFF.md` (handoff docs live in the `docs/` folder)
- `CLAUDE.md` in the app source tree when app-specific product rules need to live close to the code
- `EvidenceProfile.md` as the programming contract for workout generation
