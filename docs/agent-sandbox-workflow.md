# Agent Sandbox Workflow

Use a detached agent sandbox when an AI agent needs to explore risky or creative changes without mutating the main checkout.

## Default Rule

Normal work still happens on `main`. This repo remains main-only: do not create side branches, push sandbox commits, or open PRs unless Patrick explicitly asks for that workflow.

For risky experiments, create a detached worktree:

```powershell
.\tools\New-AgentSandbox.ps1 -Name generator-audit
```

Review the sandbox diff, then integrate only selected changes back into the main checkout:

```powershell
git -C C:\Dev\.agent-sandboxes\Transform_clean\generator-audit diff
```

Remove the sandbox when finished:

```powershell
.\tools\Remove-AgentSandbox.ps1 -NameOrPath generator-audit
```

## Use A Sandbox For

- Workout generator, validator, fallback, prompt, or API-cost experiments.
- Broad audits that inspect independent risk areas.
- Comparing alternative implementations before touching `main`.

## Skip A Sandbox For

- Tiny copy changes.
- Narrow bug fixes with an obvious file owner.
- Documentation-only edits that do not change operating rules.

The sandbox is for isolation, not final delivery. Before any final edit or commit, confirm `origin/main...main` is `0 0`, the merge-base exists, and the expected Swift source tree is present. Final validation, commit, and push happen from `C:\Dev\Transform_clean` on `main`.
