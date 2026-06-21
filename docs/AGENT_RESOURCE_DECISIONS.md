# Agent Resource Decisions (Transform)

## Purpose

This is a decision record. It applies `docs/AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md`
to a batch of nine external GitHub repositories and records, for the **Transform iOS
app only**, whether each should be `Adopt`, `Adapt`, `Reference`, or `Skip`.

It exists so future sessions do not re-litigate this evaluation, accidentally install
overlapping tooling, or inherit conclusions that were really about a different project.

## Scope note (read first)

- **Transform only.** An earlier pass evaluated these repos partly for a separate
  "Procedures" project. Procedures does not exist in this repo. The content-ingestion
  repos (MarkItDown, Open-Notebook) ranked highly *only* because of Procedures and
  drop sharply for Transform.
- **None of these nine are runtime code.** Nothing here ships into the iOS app as
  Swift. They are dev-time or content-time tooling. They cannot directly move
  Transform's top priorities (workout quality, evidence integrity, validator
  correctness, API efficiency); their value is indirect.
- **You already own the strongest equivalents.** `transform-design-research`,
  `transform-generator-audit`, `transform-context-compact`, `transform-parallel-audit`,
  and the resource-eval playbook already cover most of what these repos offer.
  The main risk is overlap and maintenance, not tool quality. Per the playbook,
  "installing everything is not a neutral decision."

## Decisions

| # | Repo | Outcome | Where it lives |
| --- | --- | --- | --- |
| 6 | Last30Days-Skill | Reference (on-demand) | Market/competitor research; this doc |
| 4 | Taste-Skill | Reference / Adapt | Design principles only; `transform-design-research` source guide |
| 3 | PM-Skills | Adapt (templates only) | Cherry-pick a PRD/prioritization template; this doc |
| 8 | Headroom | Skip now, revisit | Reconsider only if generator-audit sessions get expensive |
| 2 | MarkItDown | Reference (occasional) | Only if ingesting a training-science PDF into the evidence profile |
| 1 | Open-Notebook | Skip | High maintenance; overlaps EvidenceProfile.md and existing workflow |
| 5 | Container / Second-Brain | Skip | Overlaps CLAUDE.md + repo skills context system |
| 7 | Agent-Reach | Skip | Redundant with #6 and existing web search |
| 9 | Career-Ops | Skip | Personal, not product |

## Kept resources and when to activate them

### Last30Days-Skill — Reference (on-demand)

The single most Transform-relevant repo in this batch, because it provides a
capability the existing skills do not: *current* market and competitor sentiment.

- Activate for: competitor research (Fitbod, Future, Whoop, Hevy, etc.), feature-gap
  scans, and direction-setting on what to build next.
- Do **not** use it as a medical/training-evidence source. `EvidenceProfile.md` and
  evidence-informed programming integrity govern that. Social sentiment is not evidence.
- Keep it on-demand. Do not install it as permanent agent context.

### Taste-Skill — Reference / Adapt (design principles only)

Design quality is genuinely relevant to Transform (body-analysis flow, dashboards,
progress views, premium-native goal). But two constraints make it subordinate, not an
authority:

1. These taste packs are web-oriented (React/Tailwind/HTML/CSS). The design-research
   skill's rule holds: do not let web conventions dictate native SwiftUI behavior.
2. `transform-design-research` already does focused product-reference research for
   native iOS and remains the implementation authority.

Use it to mine general principles (hierarchy, spacing, restraint, typographic scale)
only. It is wired into `transform-design-research/references/source-guide.md` as a
secondary, principles-only source. See that file for the activation rules.

### PM-Skills — Adapt (templates only)

Transform is a mature personal app with strong existing product discipline (priority
ordering, "premium/simple not bloated" instinct, this playbook). PM-Skills is worth a
single cherry-pick: one PRD/prioritization template to keep future feature decisions
honest. Do not install the whole skill pack; you would half-use it.

## Skipped resources and why

- **MarkItDown / Open-Notebook (#2/#1):** content-ingestion tools. Only touch Transform
  if you start formally ingesting training-science papers into the evidence profile —
  occasional at most, not worth standing up infrastructure. MarkItDown stays a
  reference-only local utility; Open-Notebook's self-hosted stack is too much
  maintenance for the marginal Transform benefit.
- **Headroom (#8):** token/context compression. The most architecturally relevant skip
  — generator/validator work pulls in many large split files plus Workshop logs. But
  you are solo and already have `transform-context-compact`. Premature until
  generator-audit sessions are genuinely expensive. Revisit then.
- **Container / Second-Brain (#5):** overlaps the CLAUDE.md + repo-skills context system.
- **Agent-Reach (#7):** redundant with Last30Days and existing web search; brittle.
- **Career-Ops (#9):** personal, zero product relevance.

## Open verification item

The five generically named repos (Taste-Skill, PM-Skills, Last30Days-Skill, Agent-Reach,
Career-Ops, Headroom, Container/Second-Brain) were judged on *described function*, not on
inspected source. Before any deeper integration than "reference on demand," confirm the
exact GitHub URL, maintenance status, license, and platform assumptions for each. Update
this record if a repo's real contents change the decision.
