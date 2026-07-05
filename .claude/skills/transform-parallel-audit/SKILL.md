---
name: transform-parallel-audit
description: Break broad Transform investigations into bounded lanes, gather evidence in parallel when available, keep compact recaps between waves, and finish with one integrated judgment. Use when a task spans multiple subsystems, needs tradeoff synthesis, or risks wasting context on large diffs, logs, or handoff material.
---

# Transform Parallel Audit

Use this skill when the work is too broad for a single linear sweep but still needs one coherent final answer.

## Workflow

1. Confirm the source-of-truth repo is `C:\Dev\Transform_clean` and restate the real decision or question in one sentence.
2. Split the work into 2-4 bounded lanes. Good lane types include:
   - code path inspection
   - diff or history review
   - logs, artifacts, or workshop output
   - product or coaching-quality risk check
3. For each lane, define:
   - the narrow question
   - the exact files or artifacts to inspect
   - the evidence needed
   - the stop condition
4. If multiple agents or parallel tools are available, use them only for bounded evidence gathering. If they are not available, run the same lanes sequentially and keep the notes separated.
5. After each lane or wave, write a quick recap in 4-6 bullets:
   - what was checked
   - what was found
   - what is still uncertain
   - the next best move
6. Synthesize only after the evidence passes are done. Final synthesis should separate:
   - evidence-backed findings
   - informed inferences
   - recommended next action

## Rules

- Keep one primary agent or session responsible for scoping, integration, and final judgment.
- Prefer small waves over repo-wide sweeps.
- Stop and checkpoint when context starts ballooning.
- Reuse an earlier recap only if the relevant files, branch state, and artifacts have not changed.
- Do not create fake parallelism. If one careful pass is enough, keep it simple.
- Tool choice is secondary to discipline. This workflow should still work without any special agent framework.
- In Transform, final recommendations should still respect the app's real priority order:
  1. workout quality
  2. evidence-informed programming integrity
  3. robustness and silent-failure prevention
  4. validator correctness
  5. API waste
  6. maintainability

## When NOT to use

- Single-subsystem tasks with an obvious owning file — one careful pass beats fake lanes.
- Tasks already covered end-to-end by one sibling skill (generator-only -> `transform-generator-audit`; CI-only -> `transform-ci-triage`).

## Common Uses

- "Audit a broad set of recent main-branch changes without rereading the whole repo."
- "Compare local behavior, GitHub state, and CI signals, then recommend the next move."
- "Review a mixed generator and UI change set without letting logs or handoff docs take over the context."
- "Prepare a compact handoff after a wide investigation."

## Provenance

- Last verified: 2026-07-05 against commit `0a68ce9`. Availability of parallel subagent tools varies by session; the sequential-lane fallback is always valid.
