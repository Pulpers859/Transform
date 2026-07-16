---
name: transform-handoff
description: Orient Claude Code to the real Transform repo, source-of-truth paths, stale-copy traps, branch workflow, and release-risk hotspots. Use at the start of a Transform task, when preparing a handoff summary, or when a session needs to rebuild the project's operating rules before editing.
---

# Transform Handoff

Use this skill to rebuild the minimum correct context for Transform before coding or handing work to another session.

## Workflow

1. Confirm the source-of-truth repo, app source root, Xcode project path, current branch, repo cleanliness, remote config, and ahead/behind state.
2. Read `references/handoff-map.md`.
3. Explicitly call out stale copies if they appear in the task context.
4. State the repo's working assumptions before proceeding:
   - work from `C:\Dev\Transform_clean`
   - app source is under `Transform/Transform`
   - normal work stays on `main`
   - sync first when clean
   - commit and push completed work to `origin/main` unless the user says not to
5. Summarize risks in the order that matters for this app:
   - workout quality
   - evidence/programming integrity
   - robustness / silent failure risk
   - validator correctness
   - API waste
   - maintainability
6. Read the current-standing snapshot in `docs/3_TRANSFORM_CLEAN_HANDOFF.md` or the linked dated generator handoff. Treat it as dated evidence: verify the commit and workflow status before repeating it as current.

## Handoff Format

When preparing a handoff or orientation note, include:

1. repo root
2. actual app source root
3. Xcode project path
4. current branch and status
5. remote sync state
6. stale-copy warnings
7. likely hotspots for the current task
8. what was validated vs not validated

## Rules

- Never treat the Desktop copy as source of truth unless the user explicitly says so.
- Do not leave completed repo changes local-only when ending a task unless the user explicitly asks for that.
- Do not collapse the split workout-generator architecture back into one file.
- Preserve the personal-use baseline context without smuggling it into generic hardcoded prompt defaults.
- Be explicit about evidence-backed logic versus heuristic choices.
- When preparing a status update, separate three claims: proven by code/tests, proven by a bounded live workflow, and still requiring the owner's physical-iPhone validation.

## When NOT to use

- Deep in a single known file with fresh context already established — do not re-orient mid-task.
- Incident history questions ("why is the code like this") — use `transform-failure-archaeology`.
- Token-budget pressure on a resumed thread — use `transform-context-compact` first.

## References

- Read `references/handoff-map.md` first.
- Use `repomix` only when an external full-repo handoff is actually needed.

## Provenance

- Last verified: 2026-07-16 against commit `9fb4df0` (paths, remote, branch sync, Swift file count, and current generator evidence checked).
- Re-verify: `git ls-files "*.swift" | wc -l`, `git remote -v`, and existence of `Transform/Transform/WorkoutGeneratorService.swift`.
