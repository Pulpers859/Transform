---
name: transform-failure-archaeology
description: Recall Transform's past incidents, root causes, dead ends, and the doctrine that came out of them, with commit references. Use before reverting, re-designing, or "simplifying" behavior that looks odd or over-engineered (archiving rules, canonical exercise keys, menu-locked generation, backup guards, validator tiering), when a bug resembles a past failure, when asking "why is the code like this", or before repeating an experiment that may already have been tried and rejected.
---

# Transform Failure Archaeology

Use this skill to avoid re-fighting battles this repo has already fought. Code that looks odd, redundant, or over-defensive is often a scar from a real incident. Check the incident log before "cleaning it up."

## When to use

- You are about to revert, redesign, or simplify behavior you did not write and do not fully understand.
- A bug report resembles something that sounds historical (lost weights, duplicate exercises across days, fallback under-delivering, validator burning retries).
- The user asks "why does the app do X?" and X looks intentional but undocumented.
- You are proposing an approach and want to check it was not already tried and abandoned.

## When NOT to use

- Routine feature work in code with no incident history.
- Pure orientation (use `transform-handoff`) or generator quality review (use `transform-generator-audit`).
- Do not use the incident log as a substitute for reading current code — incidents describe the past; the current source is the present.

## Procedure

1. Read `references/incident-log.md`.
2. Match the current task against the incidents and their "do not re-fight" doctrine.
3. If the task touches a scarred area, verify the scar still exists in current code (`git log --oneline -10 -- <file>` and a targeted read) before relying on the log's description.
4. State explicitly in your output which incident(s) constrain the current change, or state that none apply.
5. If you discover a new incident worth recording (real data loss, a destroyed-work near miss, a multi-commit bug arc), append it to `references/incident-log.md` in the same format as part of the fix commit.

## Evidence rules

- Every incident entry cites commits, files, or docs. If you add an entry, do the same.
- Incident narratives are point-in-time. When they conflict with current code, current code wins — and the log should be updated.

## Common traps this prevents

- "This plural-stripping helper looks naive, let me rewrite it" → last rewrite of canonical key logic silently lost all logged exercise weights.
- "Archiving old programs seems wasteful, just delete them" → archiving preserves skip/pain history across mesocycles; only *empty* programs are deleted, deliberately.
- "Let the AI pick exercises, it's more flexible" → free-form AI selection was removed on purpose after naming drift and silent selection failures.
- "The local main looks fine, just commit" → a cloud container once shipped an unrelated-history local `main`; committing on it risks destroying `origin/main`.

## Related skills

- `transform-data-safety` — forward-looking guard rails for the data paths these incidents scarred.
- `transform-generator-audit` — generator/validator review with current hotspots.
- `transform-handoff` — repo orientation and the stale-main check itself.

## Provenance

- Last verified: 2026-07-05 against commit `0a68ce9` (all cited commits confirmed in `git log`; all cited symbols confirmed at the listed files).
- Re-verify volatile claims: `git log --oneline -20`, `git log --oneline -10 -- <file>`, and targeted reads of the cited symbols.
