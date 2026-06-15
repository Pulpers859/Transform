# Transform Claude Code Memory

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

## Minimal Working Rules
- Work from this repo, not the stale copies.
- If the repo is clean, run `git fetch --prune` and `git pull --ff-only` before normal edits.
- Push completed repo changes unless the user says not to.
- Do not leave completed repo changes local-only at handoff time.
- If only part of the work is complete, either commit and push the finished subset or explicitly tell the user what is still intentionally local and why.
- Treat local secrets/config files as local-only unless the user explicitly asks to commit them.
- Fix root causes, not cosmetic symptoms.
- Keep workout quality and evidence-informed programming integrity ahead of validator convenience.
- Respect the split `WorkoutGeneratorService` architecture.

## Context Discipline
- Read this file first, then only the one repo skill and files needed for the task.
- Do not load all handoff docs by default.
- Prefer targeted searches and small file reads over broad repo sweeps.
- Use `.claude/skills/transform-context-compact` when reviving old work or preparing a handoff.
- Use `repomix` only for external full-repo handoffs, not normal local work.

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
- Implement the resulting direction through the smallest matching SwiftUI, Liquid Glass, refactor, performance, and simulator skills.

## Skill-First Workflow
- In this repo, treat the repo-local skills as the default operating path, not an optional extra.
- Use the matching repo skill automatically when the task clearly fits, unless the user explicitly overrides that choice.
- At the start of a fresh session in `C:\Dev\Transform_clean`, first apply `transform-handoff` unless the task is already deep in a single known file.
- If resuming prior work, long threads, generator investigations, or mixed context, apply `transform-context-compact` before broader repo exploration.
- For broad reviews, mixed evidence gathering, architecture tradeoff work, or repo investigations likely to sprawl, apply `transform-parallel-audit`.
- For substantial UI/UX design, redesign, new-flow, or visual-system work, automatically apply `transform-design-research`.
- For generator, validator, blueprint, fallback, retry, or API-cost work, automatically apply `transform-generator-audit`.
- For GitHub Actions, Xcode build, scheme, workflow, or local-vs-CI mismatch work, automatically apply `transform-ci-triage`.
- If more than one repo skill could apply, prefer the smallest combination that fits the task instead of loading everything.
- Do not wait for the user to explicitly name these skills when the task clearly matches them.
- If the user explicitly names a repo skill, follow that request unless it conflicts with a higher-priority instruction.

## Repo Skills
- `transform-handoff`: repo orientation, stale-copy warnings, branch workflow, hotspots.
- `transform-parallel-audit`: bounded parallel or sequential evidence gathering with compact recaps and final synthesis.
- `transform-design-research`: focused product-reference research, native iOS design synthesis, implementation, and simulator review.
- `transform-generator-audit`: workout generator, validator, fallback, prompt drift, retry waste.
- `transform-ci-triage`: GitHub Actions, Xcode build mismatch, workflow drift.
- `transform-context-compact`: compact summaries, selective context loading, low-token handoffs.

## Read Deeper Only When Needed
- `docs/2_PROJECT_HANDOFF.md`
- `docs/3_TRANSFORM_CLEAN_HANDOFF.md`
- `docs/EXTERNAL_AGENT_RECONCILIATION.md`
- `CLAUDE.md`
- `EvidenceProfile.md`

## Validation Reality
- Windows is fine for git, file inspection, and framework-light Swift smoke checks.
- Real iOS build and simulator validation is best on macOS/Xcode.
