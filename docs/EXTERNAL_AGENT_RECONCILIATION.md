# External Agent Reconciliation

## Purpose

Use this note when more than one AI agent, machine, terminal session, or conversation may have modified the same repository.

The goal is to prevent a common failure mode:

- an agent sees a clean or mostly clean local tree
- assumes the latest visible diff is the whole story
- misses earlier outside-agent edits that were claimed, partially landed, or later overwritten

## Standing Rule

If outside agent work is mentioned, do not make sync claims or new edit decisions until that work has been reconciled against the repository.

## Required Reconciliation Pass

Before new edits, rebases, resets, merges, or "everything is in sync" statements:

1. Inspect the outside artifact when available.
   - transcript
   - chat export
   - commit list
   - screenshot
   - claimed fix summary
2. Compare three sources explicitly:
   - what the outside agent claimed to change
   - what exists now in local files and local git history
   - what exists now on `origin/main`
3. Classify each claimed fix as one of:
   - `present`
   - `missing`
   - `partially landed`
   - `overwritten`
4. Only after that comparison, decide whether to:
   - pull
   - rebase
   - merge
   - patch missing work
   - leave newer work intact

## What to Tell the User

Use plain language. Say which claimed fixes are still present, which are missing, and whether the current branch already contains them.

Do not say "the repo is synced" if external agent work has not been checked against current files and git history.

## Reusable Instruction Text for Other Agents

Use this exact text when onboarding another agent or asking it to update its instruction files:

```text
If I mention prior work by another AI agent, another machine, another terminal, or another conversation, do not assume the current diff or latest visible commit tells the full story.

Before making new edits, rebases, resets, merges, or sync claims, perform an external-agent reconciliation pass:
1. Inspect any outside artifact I provide, such as a transcript, chat export, screenshot, commit list, or claimed fix summary.
2. Compare what that agent claimed to change against:
   - the current local files
   - the local git history
   - the current main branch on GitHub
3. Tell me plainly whether each claimed change is present, missing, partially landed, or overwritten.
4. Only after that comparison should you decide whether to pull, rebase, merge, patch missing work, or leave newer work intact.

Do not tell me the repo is fully assessed or in sync until this reconciliation step is complete whenever outside agent work is part of the context.
```

## Short Request You Can Paste in Chat

```text
Before doing anything else, reconcile prior outside-agent work against this repo. Read the attached transcript or summary, compare every claimed fix against local files, local git history, and GitHub main, then tell me what is present, missing, partially landed, or overwritten before making any sync or edit decisions.
```
