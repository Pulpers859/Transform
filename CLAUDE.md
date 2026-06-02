# Transform Claude Code Memory

## Start Here
- Source-of-truth repo root: `C:\Dev\Transform_clean`
- Actual app source tree: `Transform/Transform`
- Xcode project: `Transform/Transform.xcodeproj`
- Stable branch: `main`
- Default working branch: `dev`
- Ignore stale copies unless the user explicitly asks:
  - `C:\Dev\Transform`
  - `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Transform`

## Minimal Working Rules
- Work from this repo, not the stale copies.
- If the repo is clean, run `git fetch --prune` and `git pull --ff-only` before normal edits.
- Push completed repo changes unless the user says not to.
- Treat `Transform/Transform/Secrets.plist` as local-only and uncommitted.
- Fix root causes, not cosmetic symptoms.
- Keep workout quality and evidence-informed programming integrity ahead of validator convenience.
- Respect the split `WorkoutGeneratorService` architecture.

## Context Discipline
- Read this file first, then only the one repo skill and files needed for the task.
- Do not load all handoff docs by default.
- Prefer targeted searches and small file reads over broad repo sweeps.
- Use `.claude/skills/transform-context-compact` when reviving old work or preparing a handoff.
- Use `repomix` only for external full-repo handoffs, not normal local work.

## Repo Skills
- `transform-handoff`: repo orientation, stale-copy warnings, branch workflow, hotspots.
- `transform-generator-audit`: workout generator, validator, fallback, prompt drift, retry waste.
- `transform-ci-triage`: GitHub Actions, Xcode build mismatch, workflow drift.
- `transform-context-compact`: compact summaries, selective context loading, low-token handoffs.

## Read Deeper Only When Needed
- `2_PROJECT_HANDOFF.md`
- `3_TRANSFORM_CLEAN_HANDOFF.md`
- `Transform/Transform/CLAUDE.md`
- `Transform/Transform/EvidenceProfile.md`

## Validation Reality
- Windows is fine for git, file inspection, and framework-light Swift smoke checks.
- Real iOS build and simulator validation is best on macOS/Xcode.
