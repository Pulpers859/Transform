# Transform Skill Library

Index, trigger matrix, onboarding order, and maintenance protocol for the repo-local skills in `.claude/skills/`. This library is a capability-transfer system: it exists so a future agent (or weaker model) can maintain Transform at the owner's standard without rediscovering everything.

Last full library review: 2026-07-05 against commit `0a68ce9`.

## Inventory

| Skill | One-liner | Invocation |
| --- | --- | --- |
| `transform-handoff` | Repo orientation: source-of-truth paths, stale-main check, branch policy, validation reality. | Auto at session start |
| `transform-context-compact` | Minimal context loading, low-token handoffs, resuming old threads. | Auto when resuming/compacting |
| `transform-generator-audit` | Generator/validator/fallback quality review; menu-locked contract; retry-waste checks. | Auto for generator work |
| `transform-data-safety` | Guard rails for exercise naming, canonical keys, progression history, persistence, backups. | Auto for data-path edits |
| `transform-failure-archaeology` | Past incidents with commit references; do-not-refight doctrine. | Auto before reverts/simplifications of odd behavior |
| `transform-ci-triage` | GitHub Actions / Xcode build failures; workflow-vs-project mismatch. | Auto for CI failures |
| `transform-design-research` | Substantial UI/UX work: reference research, native design brief, token-based implementation. | Auto for substantial design work |
| `transform-parallel-audit` | Bounded lanes + recaps for broad multi-subsystem investigations. | Auto for broad audits |

## Onboarding order (new agent, zero context)

1. Root `CLAUDE.md` (or `AGENTS.md` for non-Claude agents) — always.
2. `transform-handoff` — verify repo state before any edit.
3. The one skill matching the task (see trigger matrix).
4. Only then: task files. Deeper docs (`docs/2_PROJECT_HANDOFF.md`, `docs/3_TRANSFORM_CLEAN_HANDOFF.md`, `Transform/Transform/EvidenceProfile.md`) only when the task truly depends on them.

## Trigger matrix

| If the task sounds like… | Use | Not |
| --- | --- | --- |
| "Get oriented / start a session / prepare a handoff" | handoff | context-compact (that's for token pressure, not first orientation) |
| "Pick up where the last session left off", "keep this light" | context-compact | handoff alone |
| "Workout came out wrong / validator rejected / retries burning credits / review this generator diff" | generator-audit | data-safety (unless persistence touched) |
| "Rename exercises / change key matching / edit backups / migrate models / archive-delete behavior" | data-safety | generator-audit alone |
| "Why is this code so weird? Let me simplify/revert it" | failure-archaeology FIRST | jumping straight to the edit |
| "Lost data / weights disappeared / history broken" | data-safety + failure-archaeology | — |
| "GitHub Actions failed / xcodebuild error / scheme missing" | ci-triage | generator-audit |
| "Redesign this screen / new flow / make it feel premium" | design-research | — (tiny copy/spacing fixes skip it) |
| "Audit everything that changed this month / multi-subsystem review" | parallel-audit + relevant siblings | one giant sweep |

Sibling-conflict rules:
- Generator naming drift is `generator-audit`; the moment stored data, keys, or backups are edited, `data-safety` leads.
- `failure-archaeology` is read-first context, never a substitute for reading current code.
- More than one skill can apply; prefer the smallest combination.

## Non-negotiables the library must never route around

- `origin/main` is source of truth; verify sync before editing; never force-push (see `transform-handoff`).
- Commit and push completed work in the same task unless told otherwise; main-only, no side branches or PRs.
- Workout quality and evidence-informed programming integrity outrank validator convenience.
- Validation source of truth is the owner's physical-iPhone build. Never suggest the iOS Simulator.
- Data-path edits require a migration story and must not weaken integrity/backup guards.

## Maintenance protocol

- **Provenance**: every SKILL.md carries a "Last verified" commit and re-verification commands. When a skill's claims are found stale, fix the skill in the same commit as the code change that outdated it.
- **Drift check (run when a skill feels wrong, or ~monthly during active development)**:
  - `git ls-files "*.swift" | wc -l` vs the count in handoff docs
  - `rg -n "func canonicalLookupKey|enum ExerciseWeightStore|func normalizePerformanceLogs|enum DataIntegrityMonitor" Transform/Transform` vs `transform-data-safety`
  - read `.github/workflows/swift.yml` vs `transform-ci-triage/references/ci-map.md`
  - `git log --oneline -20` vs `transform-generator-audit` "recent areas" and the incident log
- **Adding a skill**: only for a recurring task class with real repo-specific judgment. Required sections: trigger-rich frontmatter description, When to use, When NOT to use, Procedure, Common traps, Related skills, Provenance. Add an `agents/openai.yaml` for non-Claude agents, a row here, and a line in `CLAUDE.md`/`AGENTS.md` Repo Skills.
- **New incidents**: real data loss, destroyed-work near misses, or multi-commit bug arcs get an entry in `transform-failure-archaeology/references/incident-log.md` as part of the fix commit.
- **Retiring a skill**: delete the folder, remove its rows/lines here and in `CLAUDE.md`/`AGENTS.md`, and note the retirement in the incident log if it encoded doctrine.
- **Honesty rule**: unverified claims are marked as such, here or in `_uncertainty_register.md` — never silently upgraded to fact.
