# PROJECT_HANDOFF.md

## Project Identity
- Project name: `Transform`
- Project type: `Native iOS app (SwiftUI / SwiftData) with AI-assisted body analysis, workout generation, training execution, nutrition planning, and progress tracking`
- Source-of-truth repo path: `C:\Dev\Transform_clean`
- Actual app source root: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`
- Stale or older copies to ignore unless explicitly asked:
  - `C:\Dev\Transform`
  - `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Transform`
- Primary target for normal work if multiple surfaces exist: `The native iOS app and its AI/training logic under Transform\Transform`
- GitHub intent/status: `remote attached`
- GitHub remote: `https://github.com/Pulpers859/Transform.git`

## Repo State
- Stable branch: `main`
- Working branch: `dev`
- Expected default branch for normal work: `dev`
- Sync-first rule: `Before normal work, fetch from the remote first. If the working tree is clean and the active branch tracks the expected upstream, pull with --ff-only before editing. If local changes exist, fetch and reconcile instead of blindly pulling.`

## PowerShell / Terminal Standard
- Do not globally pin every PowerShell session to this project.
- A dedicated shortcut should exist:
  - `Transform PowerShell`
- That shortcut should open directly in the source-of-truth repo path.
- Avoid fragile startup command strings if the path contains apostrophes or quoting hazards.

## How The Agent Should Operate
- Inspect before assuming.
- Work in the source-of-truth repo only.
- Sync from GitHub before normal work so the local repo is not stale.
- Fix root causes, not surface symptoms.
- Be honest and direct.
- Prefer architecture/data-flow fixes over hacks.
- Do not use brittle hardcoded special cases or band-aid fixes unless you explicitly explain why a deeper fix is not practical.
- Be proactive: inspect, diagnose, edit code directly, verify, and then audit nearby weaknesses.
- Do not stop at the first fix if adjacent code is obviously fragile.
- Tell me clearly what is evidence-backed, proven, inferred, or heuristic.
- If validation or review logic is too rigid and rejects good programming/coaching output, improve the rule when appropriate instead of dumbing down the product.
- Do not silently tolerate poor architecture if it is now a maintenance risk.
- Handle Git operations when appropriate.
- Keep normal work on `dev`, not `main`.
- Before editing on an existing repo, run a fetch and check ahead/behind state; if clean, pull the tracked branch with `--ff-only`.
- Audit adjacent risks after making fixes.
- Run the checks that are realistically available in the current environment.
- Clearly distinguish evidence-backed logic from heuristics.
- Treat secrets as local-only by default whenever possible. The current presence of `Secrets.plist` should be treated as a risk surface, not permission to commit live keys casually.

## Product Priorities
Order matters:
1. Workout quality
2. Evidence-informed programming integrity
3. Robustness and silent-bug prevention
4. Validator correctness
5. Reducing wasted AI / API usage
6. Maintainable architecture

## Transform-Specific Non-Negotiables
- Fix root causes, not cosmetic symptoms.
- Do not dumb down training output just to satisfy a rigid validator.
- If the validator is wrong, improve the validator.
- Keep evidence/profile logic, metadata logic, blueprint logic, validation logic, and fallback logic in sync.
- Do not silently tolerate brittle fallbacks, stale prompt assumptions, or naming drift that fragments progression tracking.
- Do not silently overwrite or revert unrelated changes.
- Distinguish evidence-backed guidance from heuristic choices.
- Preserve the app's existing style and user-facing experience unless a change is explicitly requested.

## Architecture Expectations
- Respect the split `WorkoutGeneratorService` architecture. Do not collapse it back into one giant file.
- Prefer small targeted fixes inside the correct layer:
  - prompt/request construction
  - parsing/sanitization
  - metadata and evidence profile mapping
  - training intent / blueprint generation
  - validation
  - fallback generation and repair
  - UI state / persistence / backup
- When a file becomes a maintenance risk, refactor carefully instead of layering more ad hoc logic into it.

## Known Failure Modes To Guard Against
- AI output passes schema but gives mediocre coaching.
- Validator over-credits support work or under-credits good hypertrophy work.
- Metadata aliasing inflates or fragments focus demand.
- Fallback silently underdelivers blueprint targets.
- Prompt wording and validator policy drift apart.
- Program summaries or source badges drift from actual generation source.
- Exercise naming variation breaks weight-history continuity.
- Retry behavior burns API credits on obviously doomed attempts.
- SwiftUI async flows write state after the relevant view has disappeared.
- Save/rollback/backup behavior drifts and leaves the UI out of sync with persistence.

## Files Usually Relevant For Core AI / Training Work
- `Transform/Transform/CLAUDE.md`
- `Transform/Transform/ClaudeService.swift`
- `Transform/Transform/AnthropicClient.swift`
- `Transform/Transform/WorkoutGeneratorService.swift`
- `Transform/Transform/WorkoutGeneratorService+Requests.swift`
- `Transform/Transform/WorkoutGeneratorService+ParsingValidation.swift`
- `Transform/Transform/WorkoutGeneratorService+MetadataProfiles.swift`
- `Transform/Transform/WorkoutGeneratorService+PriorityIntent.swift`
- `Transform/Transform/WorkoutGeneratorService+TrainingIntentBlueprint.swift`
- `Transform/Transform/WorkoutGeneratorService+ExerciseSelection.swift`
- `Transform/Transform/WorkoutGeneratorService+FallbackCore.swift`
- `Transform/Transform/WorkoutGeneratorService+FocusCoachingContext.swift`
- `Transform/Transform/WorkoutGeneratorLabView.swift`
- `Transform/Transform/WorkoutGeneratorDebugModels.swift`
- `Transform/Transform/EvidenceProfile.md`
- `Transform/Transform/WorkoutModels.swift`
- `Transform/Transform/WorkoutView.swift`
- `Transform/Transform/WorkoutDayDetailView.swift`
- `Transform/Transform/NutritionView.swift`
- `Transform/Transform/BodyAnalysisView.swift`
- `Transform/Transform/DataBackupManager.swift`
- `Transform/Transform/Models.swift`

## Runtime Environments That Matter
- iOS Simulator
- iPhone device testing when needed
- Windows Swift smoke validation for framework-light code paths
- Git/GitHub-backed local development on Windows

## What The User Wants By Default
- The user describes the problem in chat.
- The agent syncs from the tracked remote branch first so local files are current before investigation or edits.
- The agent investigates directly.
- The agent makes code changes directly.
- The agent audits adjacent risks.
- The agent runs local checks where possible.
- The agent handles Git steps when appropriate.
- The user should not need to babysit PowerShell, Git, or GitHub for normal work.

## Before Starting Any New Task
The agent should confirm:
1. current repo path
2. actual app source root
3. current branch
4. repo status cleanliness
5. remote configuration
6. whether the local branch is behind the remote and needs fetch/pull
7. whether stale copies exist elsewhere
8. whether the active folder is truly the source of truth

## Git / Release Notes
- Preferred everyday flow:
  - `git fetch --prune`
  - `git pull --ff-only`
  - `git st`
  - `git diff`
  - `git add .`
  - `git commit -m "..."`
  - `git push`
- Preferred promotion flow from `dev` to `main`:
  - `git checkout main`
  - `git pull --ff-only`
  - `git merge --ff-only dev`
  - `git push`
  - `git checkout dev`

## Project-Specific Instructions For The Next Agent
```text
Project: Transform
Active repo path: C:\Dev\Transform_clean
Actual app source root: C:\Dev\Transform_clean\Transform\Transform
Xcode project: C:\Dev\Transform_clean\Transform\Transform.xcodeproj
GitHub remote: https://github.com/Pulpers859/Transform.git
Stable branch: main
Working branch: dev

Important:
- Treat `C:\Dev\Transform_clean` as the source-of-truth repo root.
- The actual app and most Swift files live under `Transform\Transform`; do not confuse the repo wrapper with the app source tree.
- Do not work in stale copies unless explicitly asked.
- Use the standard workflow: sync first when clean, investigate directly, fix root causes, audit adjacent risks, run checks, and handle Git when appropriate.
- Protect workout quality and evidence-informed programming integrity over merely making validation go green.
- Respect the split `WorkoutGeneratorService` architecture and keep generator, evidence, validator, fallback, and UI/persistence behavior aligned.
```
