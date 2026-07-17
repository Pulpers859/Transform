# Transform Operating Handoff

This is the canonical operating handoff for the repo at `C:\Dev\Transform_clean`. It is the
first long-form document a new agent should read after `AGENTS.md` when the task touches more
than one known file.

## Identity
- Repo root: `C:\Dev\Transform_clean`
- App container folder: `C:\Dev\Transform_clean\Transform`
- Main Swift source tree: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`
- GitHub remote: `https://github.com/Pulpers859/Transform.git`
- Stable branch: `main`
- Default working branch: `main`

## Current Standing Snapshot (refreshed 2026-07-17)

- **Repository:** before this documentation refresh, local `main` and `origin/main` matched at `2711192`, with 57 tracked Swift files. The commit containing this handoff is necessarily newer, so always run the sync checks below instead of treating a hash in prose as permanent truth.
- **Workout generator:** the reported zero-direct-set failure was traced to the locked preselected-menu planner omitting baseline muscle coverage. Coverage is now enforced during menu planning, with a feasible replacement pass and append-only final repair. This is a planning-layer fix, not post-generation trimming or validator weakening.
- **Nutrition generator:** one production run creates one seven-day plan only. It no longer automatically creates Weeks 2-4. Target resolution is shared by prompt, validator, fallback, and source provenance; meal/template macro arithmetic, meal ordering, substitutions, and grocery quality are validated.
- **Automation evidence:** Generator Tests and Swift/Xcode passed on `1353584` (`29556308199`, `29556308102`). Nutrition-only live workflow run `29556415049` passed with `live-workout-contract` explicitly skipped. It made two successful Anthropic calls because the first response required the production correction path before the final response validated.
- **Still unproven:** macOS CI and redacted live fixtures do not prove arbitrary user profiles, iOS Keychain, SwiftData/UI wiring, or coaching quality on a user's real photos. The physical-iPhone build and deliberate owner review remain the release-level proof.

Keep evidence labels separate: deterministic test, bounded live contract, and physical-device
validation are different claims.

## Documentation Hierarchy

Use each document for its actual role so status does not drift across several “current” files.

| Document | Role | When to read it |
|---|---|---|
| `AGENTS.md` | Mandatory repo rules, source-of-truth safeguards, branch policy, and validation limits. | Every session, before edits. |
| `docs/3_TRANSFORM_CLEAN_HANDOFF.md` | Canonical current operating handoff: app map, automation, evidence boundaries, and active risks. | Any cross-cutting task or resumed work. |
| `docs/AGENT_HANDOFF_2026-07-15_generator-aplus.md` | Specialist generator architecture, failure archaeology, and rationale for prior decisions. It is not the canonical current-status document. | Before changing workout or nutrition generation, validation, fallback, or retry behavior. |
| `docs/2_PROJECT_HANDOFF.md` | Broader project background and historical reference. | When additional product or history context is needed. |
| `docs/generator-troubleshooting-workflow.md` | Exact live-workflow inputs, cost limits, and redaction guarantees. | Before dispatching a billed GitHub Actions run. |

## App and Validation Map

| Surface | Shipping path | What can be tested headlessly | What still needs the iPhone |
|---|---|---|---|
| Body analysis | `BodyAnalysisView` -> `BodyAnalysisRunStore` -> UIKit photo preparation -> `ClaudeService.analyzeBody` -> `BodyAnalysisValidator` -> SwiftData session. | Deterministic model/validator fixtures can be added; no meaningful live image contract exists yet. | Camera/photo selection, JPEG preparation, private user-photo handling, result presentation, and session persistence. |
| Workout generation | Analysis -> intent -> blueprint -> locked menu -> allocation -> sanitization/validation -> fallback -> workout persistence. | The Foundation-safe planning core, captured fixture, and gated live structured contract. | SwiftUI flow, SwiftData save/load, real profile quality, and exercise-history continuity. |
| Nutrition generation | Analysis -> reconciled macro targets -> seven-day request -> sanitization/validation -> safe fallback -> nutrition persistence. | Stress matrix plus gated live one-week contract. | SwiftUI flow, persisted plan presentation, and owner judgment of food practicality. |
| App data and UI | SwiftUI, SwiftData, Keychain, backup/rollback, photo and camera integrations. | Narrow framework-free helpers only. | Xcode build and physical-iPhone runtime. |

## GitHub Actions and AI Credential Wiring

`Generator Tests` runs on pushes to `main` and exercises the deterministic Foundation-safe
generator harness. `Swift` builds the actual iOS target on macOS. Neither workflow spends
Anthropic credits.

`Generator Troubleshooting` is manual and starts with a deterministic replay. It then has two
independent optional live jobs:

| Input | Job | Scope and cost boundary |
|---|---|---|
| `run_live_workout=true` | `live-workout-contract` | Workout only. One logical request with one permitted HTTP attempt. |
| `run_live_nutrition=true` | `live-nutrition-contract` | Nutrition only. One seven-day plan; production correction/retry behavior may make up to three HTTP calls. |
| `confirm_api_usage=RUN_LIVE_AI` | Authorizes selected live jobs only. | Never turn on an unrelated generator “for completeness.” |

The repository secret `ANTHROPIC_API_KEY` stays in GitHub and is injected only into the selected
macOS runner as `TRANSFORM_HEADLESS_ANTHROPIC_API_KEY`. It is not an iPhone key and must never be
printed, committed, or pasted into chat. The local `GH_TOKEN` is a separate, repository-scoped
GitHub Actions write token in the owner's Windows user environment. It lets Codex dispatch and
inspect workflows; it does not reveal or replace the Anthropic key.

Live artifacts are intentionally redacted. A green contract proves request/decode/validation
behavior for its synthetic fixture; it does not expose a meal plan or prove subjective coaching
quality.

## Body Analysis Automation Policy

Yes: when body analysis becomes automatable, it must have its own independent
`run_live_bodyanalysis` input and `live-bodyanalysis-contract` job. It must never be bundled with
workout or nutrition, because photo-bearing calls have different privacy, cost, and reliability
risks.

Do **not** add a placeholder job today. The current body-analysis entry point is UIKit-gated,
accepts real image data, sends a freeform vision request, and has no privacy-safe headless fixture
or live-contract test. A no-op checkbox would falsely imply coverage.

Before adding that job, complete all of these:

1. Extract a Foundation-safe request/payload seam while preserving iPhone JPEG resizing and image limits.
2. Add deterministic decode and `BodyAnalysisValidator` fixtures, including malformed macro and training-intent cases.
3. Use only a checked-in, non-personal, rights-cleared synthetic or explicitly consented fixture. Never upload a user's phone photo to GitHub Actions.
4. Create a dedicated redacted artifact that reports contract/validator counts, never images, prompts, raw responses, or personal measurements.
5. Keep physical-iPhone review mandatory for actual-photo quality, camera flow, privacy handling, and SwiftData persistence.

## Working Protocol for Future Agents

1. Work only in `C:\Dev\Transform_clean`; ignore `C:\Dev\Transform` and the OneDrive/Desktop copy unless the owner explicitly redirects you.
2. Run `git fetch --prune`, verify `origin/main...main` is `0 0`, verify a non-empty merge-base, and check the real nested source tree before editing.
3. Fix the earliest deterministic cause. Trimming output, warning demotion, retry changes, and permissive fallback acceptance are containment measures unless the planner/request layer is proven correct.
4. For substantial generator or validator work, stage only intended files, run `tools/Invoke-GeneratorSecondAudit.ps1`, and independently audit the result. An incomplete or timed-out Claude review is not approval.
5. Dispatch billed live jobs only for the requested surface. State the number of actual HTTP calls observed, not merely the logical generation count.
6. Push completed work directly to `main` as a fast-forward. Never force-push. Windows validation is syntax/smoke-level only; use macOS CI and the physical iPhone for their respective claims.

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
- The shipping iPhone Anthropic API key is entered in-app and stored in iOS Keychain. Build-time key injection has been removed.
- The distinct GitHub repository secret named `ANTHROPIC_API_KEY` exists only for explicitly selected headless live-contract jobs. It is injected at runner time and must not become an app build setting.
- The owner's local `GH_TOKEN` can dispatch and inspect GitHub Actions runs. It is not the Anthropic key, must remain local, and must never be pasted into chat or committed.
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
- `AGENTS.md` (mandatory rules, source-of-truth safeguards, and validation limits)
- `docs/AGENT_HANDOFF_2026-07-15_generator-aplus.md` (specialist workout/nutrition architecture and incident history)
- `docs/generator-troubleshooting-workflow.md` (billed live-job controls and redaction guarantees)
- `Transform/Transform/CLAUDE.md` (app-specific product rules close to the source)
- `Transform/Transform/EvidenceProfile.md` (programming contract for workout generation)
