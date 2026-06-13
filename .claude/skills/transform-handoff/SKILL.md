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
   - push completed work unless the user says not to
5. Summarize risks in the order that matters for this app:
   - workout quality
   - evidence/programming integrity
   - robustness / silent failure risk
   - validator correctness
   - API waste
   - maintainability

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
- Do not collapse the split workout-generator architecture back into one file.
- Preserve the personal-use baseline context without smuggling it into generic hardcoded prompt defaults.
- Be explicit about evidence-backed logic versus heuristic choices.

## References

- Read `references/handoff-map.md` first.
- Use `repomix` only when an external full-repo handoff is actually needed.
