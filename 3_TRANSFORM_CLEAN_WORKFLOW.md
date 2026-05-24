# Transform_clean Project Workflow

This file is the Transform-specific workflow reference for the repo at `C:\Dev\Transform_clean`.

## Identity
- Repo root: `C:\Dev\Transform_clean`
- App container folder: `C:\Dev\Transform_clean\Transform`
- Main Swift source tree: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`
- GitHub remote: `https://github.com/Pulpers859/Transform.git`
- Stable branch: `main`
- Default working branch: `dev`

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
- Keep routine work on `dev`.
- Do not commit directly to `main`.

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
3. confirm current branch is `dev`
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

### Promote finished work to main
```powershell
git checkout main
git pull --ff-only
git merge --ff-only dev
git push
git checkout dev
```

## PowerShell / Local Environment
- Do not globally pin every PowerShell session to the repo.
- Use a dedicated project shortcut instead.
- The shortcut should open in `C:\Dev\Transform_clean`.
- Avoid brittle launch arguments for paths with apostrophes.

## Secrets / Credential Handling
- Do not treat tracked files as a safe place for live credentials.
- `Transform\Transform\Secrets.plist` currently exists and should be treated carefully.
- Prefer example files plus ignored real local secret/config files whenever practical.
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

## Agent Working Style
- Inspect current code before assuming prior context is still accurate.
- Make direct changes when the path is clear.
- After each fix, do another harsh adjacent-risk pass.
- If something cannot be fully validated in the current environment, say exactly what was and was not validated.
- On Windows, use the Swift sanity check for smoke validation when possible.
- On macOS, prefer real Xcode or simulator validation.

## Recommended Repo-Local Companion Files
- `PROJECT_HANDOFF.md` in the repo root
- `CLAUDE.md` in the app source tree when app-specific product rules need to live close to the code
- `EvidenceProfile.md` as the programming contract for workout generation
