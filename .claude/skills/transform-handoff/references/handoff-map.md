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
