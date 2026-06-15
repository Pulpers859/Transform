# UI/UX Playbook Portable Starter Kit

## Purpose

Use this kit to roll the `AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md` workflow into another app with minimal friction.

This package is meant to help another agent:

- evaluate external UI/UX repos, libraries, design systems, and reference sites consistently
- stay neutral about style until it understands the actual app
- choose the smallest useful toolset instead of adopting everything

The kit is intentionally app-agnostic. It should transfer the evaluation method, not Transform's specific UI conclusions.

## What to Copy Into Another App

For the lightest useful setup, copy these into the target repo:

1. `docs/AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md`
2. `docs/templates/UI_UX_PLAYBOOK_AGENTS_SNIPPET.txt`
3. `docs/templates/UI_UX_PLAYBOOK_AGENT_REQUEST.txt`

For the stronger setup, also copy:

4. `docs/templates/ui-ux-resource-eval/SKILL.md`

Optional:

5. `docs/EXTERNAL_AGENT_RECONCILIATION.md` if that repo often has multiple agents or machines touching the same work

## Recommended Rollout Levels

### Level 1: Docs Only

Best when:

- the app only occasionally needs outside UI/UX evaluation
- you want minimal setup
- you mainly hand the playbook to agents manually

Install:

- add `docs/AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md`
- paste the request from `UI_UX_PLAYBOOK_AGENT_REQUEST.txt` when needed

### Level 2: Docs Plus AGENTS Trigger

Best when:

- the app regularly evaluates design systems, component libraries, or inspiration sources
- you want the behavior to activate without re-explaining it each time

Install:

- add the playbook to `docs/`
- paste `UI_UX_PLAYBOOK_AGENTS_SNIPPET.txt` into that repo's `AGENTS.md`

### Level 3: Docs Plus AGENTS Trigger Plus Local Skill

Best when:

- the app frequently has design-system or tooling decisions
- multiple agents may touch the same repo
- you want a more explicit automatic workflow

Install:

- add the playbook to `docs/`
- paste the AGENTS snippet into `AGENTS.md`
- create a repo-local skill from `docs/templates/ui-ux-resource-eval/SKILL.md`

This is the most reliable setup for repeated use.

## Suggested Target Repo Structure

```text
your-app/
├── AGENTS.md
├── docs/
│   ├── AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md
│   └── EXTERNAL_AGENT_RECONCILIATION.md            optional
└── .claude/
    └── skills/
        └── ui-ux-resource-eval/
            └── SKILL.md                            optional
```

If the repo uses a different skill system, adapt the skill file to that system's format but keep the same behavior.

## Installation Order

1. Copy `AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md` into the target repo's `docs/` folder.
2. Add the AGENTS snippet so the repo knows when to use the playbook.
3. If the app often makes UI/UX tooling decisions, add the small local skill.
4. If multiple agents or machines commonly touch the repo, also add the external-agent reconciliation note.

## What the AGENTS Snippet Should Do

The AGENTS snippet should make four things clear:

1. Read the playbook before evaluating external UI/UX resources.
2. Use the `Adopt / Adapt / Reference / Skip` process.
3. Do not trigger this workflow for ordinary small UI fixes.
4. Inspect the actual app first instead of inheriting conclusions from another project.

## What the Local Skill Should Do

The local skill should stay small. It should:

- trigger on UI/UX resource evaluation tasks
- point the agent to the playbook
- require app inspection before recommendations
- require `Adopt / Adapt / Reference / Skip` outcomes
- require the smallest non-overlapping recommendation set
- avoid turning routine styling fixes into a research project

## Good Trigger Cases

Use the playbook and optional skill when the task is about:

- design-system decisions
- component library selection
- visual reference sources
- choosing whether a UI/UX repo or website should influence the app
- redesign planning
- design-tooling comparison

## Bad Trigger Cases

Do not trigger the full workflow for:

- one-off spacing fixes
- small color tweaks
- isolated visual bug fixes
- copy changes
- ordinary component implementation when the design-system decision is already made

## Recommended Prompting Pattern

When asking another agent to use this setup, give it:

1. the app itself
2. the playbook path
3. the external resources to evaluate
4. any known constraints such as platform, framework, or brand requirements

Use the request file in `docs/templates/UI_UX_PLAYBOOK_AGENT_REQUEST.txt` as the default starting point.

## Best Practice

Treat this as a decision framework, not as a style engine.

The best outcome is not "this app now looks like Transform."
The best outcome is "this app now has the right UI/UX research process for its own product and platform."
