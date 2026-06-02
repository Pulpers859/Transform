---
name: transform-context-compact
description: Keep Claude Code context lean in the Transform repo by rebuilding only the minimum needed project state, choosing the right repo skill, and producing compact handoffs. Use when starting a new Transform thread, resuming older work, preparing a handoff, or when a task risks ballooning context with large docs, logs, or workshop dumps.
---

# Transform Context Compact

Use this skill to reduce token waste without losing critical Transform context.

## Workflow

1. Read `references/compact-map.md`.
2. Start with root `CLAUDE.md` and the current user request only.
3. Load just one deeper repo skill first:
   - `transform-handoff` for orientation
   - `transform-generator-audit` for generator/validator work
   - `transform-ci-triage` for GitHub Actions or Xcode CI
4. Open only the files directly needed for the current task.
5. Summarize state in 5-8 bullets before switching from discovery to editing or before ending the task.

## Rules

- Do not load all handoff docs by default.
- Do not bulk-paste long logs or workshop dumps when a short issue summary will do.
- Prefer targeted searches, line-level reads, and short summaries.
- Reuse prior conclusions only if the underlying files or branch state have not changed.
- Say when a conclusion is evidence-backed versus inferred.

## Common Uses

- "Refresh yourself on Transform before continuing."
- "Pick up where another Claude/Codex session left off."
- "Summarize this session so the next agent does not have to reread everything."
- "Keep this review light on tokens."

## References

- Read `references/compact-map.md`.
