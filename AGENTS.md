# Transform Agent Instructions

## Start Here
- Source-of-truth repo root: `C:\Dev\Transform_clean`
- Current working branch: `main`
- Use the files in this repo root as the active source tree unless the user explicitly says otherwise.
- Ignore stale copies unless the user explicitly asks:
  - `C:\Dev\Transform`
  - `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Transform`

## Branch Policy
- Use `main` as the only working branch for this repository.
- Commit directly to `main` and push directly to `origin/main`.
- After completing code, config, docs, workflow, or instruction changes, stage them, commit them, and push them to `origin/main` in the same task unless the user explicitly says not to.
- Do not create, switch to, suggest, or use side branches, feature branches, PR branches, or a `dev` branch.
- Do not open or suggest pull requests for routine work in this repository.
- Only use a non-`main` branch or a PR workflow if the user explicitly asks for it in that specific task.
- For risky, creative, or parallel agent work, use a detached sandbox worktree via `tools/New-AgentSandbox.ps1`; do not create side branches or commit/push from the sandbox. See `docs/agent-sandbox-workflow.md`.

## origin/main Is Source Of Truth — Stale-Local-`main` Trap (READ BEFORE ANY COMMIT)
- `origin/main` is the canonical, authoritative tree. The remote always wins over a local snapshot.
- Cloud / remote-execution containers have shipped a STALE local `main` that is an UNRELATED history: no shared merge-base with `origin/main`, a different file layout, and missing source files. Committing onto it and pushing would be rejected — or, if force-pushed, would DESTROY the real `origin/main` history. This has actually happened in this repo; the user describes it as "it gets my data lost."
- Before editing, ALWAYS confirm local `main` really matches `origin/main`:
  - `git fetch --prune`
  - `git rev-list --left-right --count origin/main...main` — expect `0   0`; any large "behind" count or divergence is a red flag.
  - `git merge-base main origin/main` — EMPTY output means UNRELATED histories = the local `main` is a stale/junk snapshot, NOT your real tree.
  - Sanity-check the tree: the app source must exist (e.g. `Transform/Transform/WorkoutGeneratorService.swift`) and the tracked Swift file count should look right (`git ls-files "*.swift" | wc -l` — currently 49), not a smaller different layout.
- If local `main` is behind, diverged, or unrelated: do NOT commit on it. Re-point onto the real tree first with `git checkout -B main origin/main`, re-verify the source is present, THEN make changes.
- NEVER `git push --force` / `--force-with-lease` to `origin/main`. Push clean fast-forwards only. If a push is non-fast-forward, STOP and reconcile — never overwrite the remote.
- After pushing, confirm it was a fast-forward (`old..new`), not a forced replacement, and that the prior `origin/main` commits are still ancestors.

## Minimal Working Rules
- Work from this repo, not the stale copies.
- If the repo is clean, run `git fetch --prune` and `git pull --ff-only` before normal edits.
- Push completed repo changes unless the user says not to.
- Do not leave completed repo changes local-only at handoff time.
- If only part of the work is complete, either commit and push the finished subset or explicitly tell the user what is still intentionally local and why.
- Preserve user changes unless the user explicitly asks otherwise.
- Fix root causes, not cosmetic symptoms.
- For generator or validator incidents, map the failure to its earliest deterministic cause
  before editing. Post-generation trimming, warning demotion, fallback acceptance, or retry
  changes are containment measures unless the planning layer is shown to be correct.
- Do not claim a batch of generator findings is fixed because one shared warning disappeared.
  Re-run or arithmetically reproduce every reported finding, and state separately what is
  proven by code/tests versus what still requires the owner's physical-iPhone generation.
- Before committing substantial generator changes, stage the intended files and run
  `tools/Invoke-GeneratorSecondAudit.ps1` so the tracked/staged diff receives an independent,
  no-tools Claude Code review. Resolve material
  findings before push. If Claude is unavailable or out of usage credits, say so explicitly and
  perform a separate adversarial audit; never represent an incomplete Claude run as approval.
- Keep workout quality and evidence-informed programming integrity ahead of validator convenience.
- Respect the split `WorkoutGeneratorService` architecture.

## Context Discipline
- Read this file first, then only the one repo skill and files needed for the task.
- Do not load all handoff docs by default.
- Prefer targeted searches and small file reads over broad repo sweeps.
- Use `.claude/skills/transform-context-compact` when reviving old work or preparing a handoff.
- Use `repomix` only for external full-repo handoffs, not normal local work.
- Use `docs/agent-sandbox-workflow.md` before isolated AI-agent experiments.

## External Agent Reconciliation
- If the user mentions prior work by another agent today, another machine, another terminal, or another conversation, do not assume the current diff or latest local commit tells the full story.
- Before new edits, rebases, resets, or sync decisions, reconcile external-agent work against the current repo state.
- Ask for or inspect the outside artifact when available, such as a transcript, chat export, commit list, screenshot, or claimed fix summary.
- Compare three things explicitly:
  - what the outside agent claimed to change
  - what exists now in local files and local git history
  - what exists now on `origin/main`
- Report the result in plain terms: present, missing, partially landed, or overwritten.
- If overlap exists, preserve the newer or safer behavior intentionally rather than assuming the most recent diff is the whole truth.
- Do not say the repo is fully assessed or in sync until this reconciliation step is complete when external agent work is part of the context.

## Parallel Audit and Recap
- For broad audits or multi-subsystem tasks, split the work into 2-4 bounded lanes instead of one giant repo sweep.
- Keep one primary agent or session responsible for scoping, synthesis, and final judgment.
- Use parallel helpers only for bounded evidence gathering when the tool supports it; otherwise run the same lanes sequentially.
- Give each lane a narrow question, a small file or artifact scope, and a clear stop condition.
- After each wave, write a quick recap in 4-6 bullets covering what was checked, what was found, what is still uncertain, and the next best move.
- When context, logs, or diffs start ballooning, checkpoint and resume from the recap instead of dragging all raw material forward.
- Use `.claude/skills/transform-parallel-audit` when a task spans multiple subsystems or risks context sprawl.

## Design Research
- For substantial UI or UX work, automatically apply `transform-design-research` before implementation.
- Trigger it for screen redesigns, new flows, onboarding, dashboards, progress or analytics experiences, navigation changes, design-system decisions, accessibility reviews, or requests for a clearer, more polished, premium, cohesive, or native feel.
- Do not invoke the full research workflow for tiny copy, spacing, or isolated visual bug fixes unless they expose a broader design problem.
- Use external references to extract principles, not to copy screens or import web conventions into SwiftUI.
- Implement the resulting direction directly with native SwiftUI and the app's `DesignSystem.swift` tokens; validation is the owner's device build, never the simulator.

## Skill-First Workflow
- In this repo, treat the repo-local skills as the default operating path, not an optional extra.
- Use the matching repo skill automatically when the task clearly fits, unless the user explicitly overrides that choice.
- At the start of a fresh session in `C:\Dev\Transform_clean`, first apply `transform-handoff` unless the task is already deep in a single known file.
- If resuming prior work, long threads, generator investigations, or mixed context, apply `transform-context-compact` before broader repo exploration.
- For broad reviews, mixed evidence gathering, architecture tradeoff work, or repo investigations likely to sprawl, apply `transform-parallel-audit`.
- For substantial UI/UX design, redesign, new-flow, or visual-system work, automatically apply `transform-design-research`.
- For generator, validator, blueprint, fallback, retry, or API-cost work, automatically apply `transform-generator-audit`.
- For GitHub Actions, Xcode build, scheme, workflow, or local-vs-CI mismatch work, automatically apply `transform-ci-triage`.
- Before re-designing, reverting, or "simplifying" behavior that looks odd (archiving rules, canonical keys, menu-locked generation, backup logic), automatically apply `transform-failure-archaeology` — the odd behavior may be a scar from a past incident.
- For any change touching exercise naming, canonical keys, progression/weight history, persistence, migration, or backup code, automatically apply `transform-data-safety`.
- If more than one repo skill could apply, prefer the smallest combination that fits the task instead of loading everything.
- Do not wait for the user to explicitly name these skills when the task clearly matches them.
- If the user explicitly names a repo skill, follow that request unless it conflicts with a higher-priority instruction.

## Repo Skills
- `transform-handoff`: repo orientation, stale-copy warnings, branch workflow, hotspots.
- `transform-parallel-audit`: bounded parallel or sequential evidence gathering with compact recaps and final synthesis.
- `transform-design-research`: focused product-reference research, native iOS design synthesis, implementation, and owner device-validation handoff.
- `transform-generator-audit`: workout generator, validator, fallback, prompt drift, retry waste.
- `transform-ci-triage`: GitHub Actions, Xcode build mismatch, workflow drift.
- `transform-context-compact`: compact summaries, selective context loading, low-token handoffs.
- `transform-failure-archaeology`: past incidents, root causes, and do-not-refight doctrine with commit references.
- `transform-data-safety`: guard rails for exercise naming, progression continuity, persistence, and backup code paths.
- Full index, trigger matrix, and maintenance protocol: `.claude/skills/README.md`.

## Read Deeper Only When Needed
- `docs/2_PROJECT_HANDOFF.md`
- `docs/3_TRANSFORM_CLEAN_HANDOFF.md`
- `docs/EXTERNAL_AGENT_RECONCILIATION.md`
- `Transform/Transform/CLAUDE.md`
- `Transform/Transform/EvidenceProfile.md`

## Validation Reality
- Windows / Linux / cloud containers are fine for git, file inspection, and framework-light Swift smoke checks. They CANNOT build this iOS app (no Xcode), so agents in those environments must make changes that are correct-by-inspection and compile-safe, then hand off to the owner for the real build.
- The owner's validation workflow is: build in Xcode and run on a physical iPhone. This is the source of truth for "does it work."
- Do NOT suggest, recommend, or wait on the iOS Simulator. The owner intentionally does not use it (slow to load, and it can't exercise haptics, the camera/body-analysis flow, or true on-device feel). Device testing is the correct and preferred path — treat it as such, not as a fallback.
- When an agent cannot compile, say exactly that ("I can't build here; this is correct-by-inspection — build & run on your iPhone to confirm") instead of pointing at the simulator.
- On Windows, the concrete Swift smoke check is `swiftc -parse <file>` per edited file (syntax-only; it does not type-check imports or cross-file references).
