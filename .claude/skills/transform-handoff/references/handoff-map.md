# Transform Handoff Map

## Canonical paths

- Repo root: `C:\Dev\Transform_clean`
- App source root: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`
- GitHub remote: `https://github.com/Pulpers859/Transform.git`

## Stale copies to call out

- `C:\Dev\Transform`
- `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Transform`

## Default branch expectations

- Stable branch: `main`
- Working branch: `main`
- Normal flow:
  - `git fetch --prune`
  - if clean, `git pull --ff-only`
  - inspect status/diff
  - make changes
  - validate what is realistic
  - `git add` the completed changes
  - `git commit` the completed changes
  - `git push origin main` unless told not to

## CRITICAL: verify local `main` == `origin/main` before committing

- `origin/main` is the source of truth. Cloud / remote-execution containers have shipped a STALE
  local `main` on an UNRELATED history (no merge-base, different layout, missing files). Committing
  on it and force-pushing would WIPE the real `origin/main` — the user calls this "it gets my data lost."
- Before any edit/commit, run:
  - `git rev-list --left-right --count origin/main...main` (expect `0   0`)
  - `git merge-base main origin/main` (EMPTY = unrelated histories = stale junk local `main`)
- If stale/diverged/unrelated: `git checkout -B main origin/main`, confirm app source exists
  (`Transform/Transform/Transform/WorkoutGeneratorService.swift`, ~49 Swift files), THEN edit.
- NEVER force-push `origin/main`. Fast-forward pushes only; if rejected, stop and reconcile.

## Product priorities

1. Workout quality
2. Evidence-informed programming integrity
3. Robustness and silent-bug prevention
4. Validator correctness
5. Reducing wasted AI / API usage
6. Maintainable architecture

## Common hotspots

- workout generator / validator / fallback alignment
- weight-history continuity from exercise naming
- async SwiftUI state and persistence drift
- backup / rollback consistency
- GitHub Actions workflow drift from the real Xcode project

## Good orientation summary

When starting a Transform task, summarize:

1. repo root
2. app source root
3. Xcode project path
4. current branch / repo status
5. remote sync state
6. stale-copy warning
7. likely risk areas for the task
8. validation limits in the current environment
