# Transform Context Compact Map

## Goal

Use the smallest context that still lets Claude act correctly.

## Default load order

1. `CLAUDE.md`
2. One relevant repo skill:
   - orientation -> `transform-handoff`
   - generator -> `transform-generator-audit`
   - CI -> `transform-ci-triage`
3. Only then open task-specific files.
4. Read heavier docs only if the task truly depends on them:
   - `docs/2_PROJECT_HANDOFF.md`
   - `docs/3_TRANSFORM_CLEAN_HANDOFF.md`
   - `Transform/Transform/CLAUDE.md`
   - `Transform/Transform/EvidenceProfile.md`

## Compact working summary

Keep working state to 5-8 bullets:

1. repo/app root
2. current branch and clean/dirty state
3. files likely involved
4. what was validated vs not validated
5. open risks or assumptions

## Token-saving rules

- Prefer targeted `rg` searches and precise reads over loading large files end to end.
- Do not re-read the handoff docs unless branch state, architecture assumptions, or task scope changed.
- Summarize long workshop dumps into issue lists before diving into code.
- Avoid copying full logs into the prompt when a few relevant lines explain the failure.
- Use `repomix` only for external handoffs or cross-model reviews.

## Escalate to deeper context only when

- the source-of-truth repo is unclear
- the task touches generator/validator/fallback policy
- the CI failure log is ambiguous
- a prior handoff is stale or contradictory
