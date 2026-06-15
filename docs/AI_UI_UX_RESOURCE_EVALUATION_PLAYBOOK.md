# AI UI/UX Resource Evaluation Playbook

## Purpose

Use this document when asking an AI agent to evaluate UI/UX repositories, component libraries, design-reference websites, or agent skills for a specific app.

The goal is not to select the most popular resource or reproduce another app's visual style. The goal is to determine which resources improve the current product's usability, identity, implementation quality, and development efficiency.

This playbook is intentionally app-agnostic. Each agent should reach conclusions from the app in front of it rather than inheriting decisions made for another project.

## Resources Under Consideration

- Builder.io agent skills: https://github.com/BuilderIO/skills
- UI UX Pro Max skill: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
- 21st.dev components: https://21st.dev/community/components
- UX Components: https://www.ux-components.com/components
- UX Components design systems: https://www.ux-components.com/design-systems.html
- Refero: https://refero.design/

These resources are trusted inputs. Evaluate them on product fit, platform fit, overlap, maintenance cost, and implementation usefulness rather than treating source trust as a disadvantage.

## Core Principle

Do not begin by asking, "Which resource should we install?"

Begin by asking:

> What design or development problem does this app actually need help solving?

Research should follow the product problem. The product should not be reshaped merely to justify a tool.

## Phase 1: Understand the App

Before evaluating external resources, inspect the app and record:

1. **Product purpose**: What outcome does the app help users achieve?
2. **Primary users**: Who uses it, in what environment, and with what level of expertise?
3. **Critical workflows**: Which three to five tasks must feel effortless?
4. **Platform**: Native iOS, Android, web, desktop, cross-platform, or a combination?
5. **Implementation stack**: SwiftUI, UIKit, React, Next.js, Flutter, another framework, or mixed?
6. **Current maturity**: Prototype, early product, established product, redesign, or design-system consolidation?
7. **Existing identity**: Which visual and interaction patterns are worth preserving?
8. **Current weaknesses**: Navigation, hierarchy, consistency, accessibility, component quality, visual direction, performance, or engineering speed?
9. **Constraints**: Supported OS versions, accessibility requirements, device sizes, team skill, schedule, and technical debt.
10. **Success criteria**: What measurable or observable improvement should result?

Do not recommend a design resource until this context is understood.

## Phase 2: Classify the Need

Identify the dominant need. More than one may apply, but rank them.

| Need | Examples |
| --- | --- |
| Product-flow research | Onboarding, checkout, account setup, creation flows, dashboards |
| Visual-direction research | Color, typography, density, tone, brand expression |
| Component behavior | States, validation, selection, navigation, feedback, accessibility |
| Ready-made implementation | Production components compatible with the app's framework |
| Design-system structure | Tokens, hierarchy, reusable primitives, governance |
| Agent efficiency | Better planning, parallel research, summaries, context management |
| Quality assurance | Responsive behavior, accessibility, performance, empty/error states |

This classification determines which resources deserve attention.

## Phase 3: Understand Each Resource's Role

### Builder.io Skills

Primary role: agent workflow and development-process improvement.

Evaluate for:

- planning and review workflows
- bounded parallel research
- context and usage management
- visual planning or recap artifacts
- compatibility with the project's existing agent instructions

Do not treat it as a UI component library. Adopt individual ideas only when they reduce effort or improve judgment. Avoid installing overlapping skills merely because they are available.

### UI UX Pro Max

Primary role: searchable design intelligence and generated design direction.

Evaluate for:

- visual vocabulary and style exploration
- palette and typography suggestions
- design-system starting points
- anti-pattern reminders
- quality and freshness of guidance for the app's actual platform

Test it with a realistic prompt for the app. Check whether its output correctly recognizes the platform and product type. Reject web conventions when evaluating a native app, and reject native assumptions when evaluating a web product.

Treat generated recommendations as research input, not unquestionable implementation rules.

### 21st.dev

Primary role: browsable, implementation-oriented web component inspiration.

Evaluate for:

- compatibility with the actual web framework
- component quality and maintainability
- responsive behavior
- accessibility
- visual and motion ideas
- cost of adapting a component to the app's design system

For native apps, use it only as selective visual or motion inspiration. React, Tailwind, hover behavior, and browser interaction should not be translated literally into native UI.

### UX Components

Primary role: component education, behavior, states, accessibility, and comparison.

Evaluate for:

- choosing the correct interaction pattern
- understanding component anatomy
- identifying required states
- accessibility considerations
- comparing established design-system approaches

Use it to improve reasoning about components. It may not provide production-ready code for the app's framework.

### Refero

Primary role: real-product screen and flow research.

Evaluate for:

- relevant examples from comparable products
- complete flows rather than isolated screenshots
- information hierarchy
- interaction sequencing
- onboarding, conversion, settings, dashboard, and account patterns

Use a small set of relevant references. Extract principles rather than copying visual surfaces. Screenshots do not reveal implementation architecture, accessibility semantics, or all interaction states.

## Phase 4: Score Fit, Not Popularity

Score each candidate from 0 to 3:

- `0`: Not relevant
- `1`: Minor or occasional value
- `2`: Useful with adaptation
- `3`: Strong direct fit

| Criterion | Question |
| --- | --- |
| Product fit | Does it help the app's most important workflows? |
| Platform fit | Does it understand the target platform and conventions? |
| Stack fit | Can its implementation guidance work with the current technology? |
| Design fit | Can it strengthen the app without erasing its identity? |
| Accessibility | Does it account for semantics, contrast, text scaling, motion, and input needs? |
| State coverage | Does it address loading, empty, error, disabled, selected, and destructive states? |
| Engineering value | Will it reduce implementation time or improve code quality? |
| Maintenance cost | How much adaptation, updating, and instruction overhead will it create? |
| Overlap | Does an existing tool or skill already solve this well? |
| Evidence quality | Are recommendations grounded in real products, established patterns, or current platform guidance? |

Do not rely on the total score alone. A resource with excellent visual inspiration but poor platform fit may be useful for research and unsuitable for implementation.

## Phase 5: Choose an Adoption Level

Assign each resource one outcome:

### Adopt

Install or formally integrate it because it has strong recurring value and fits the stack.

### Adapt

Extract useful concepts, data, or workflows into an app-specific skill or design process. Remove assumptions that do not fit.

### Reference

Use it on demand during relevant tasks without adding it to the repository or permanent agent context.

### Skip

Do not use it because its value is low, redundant, or outweighed by adaptation and maintenance cost.

Installing everything is not a neutral decision. Every permanent tool adds context, overlap, and opportunities for conflicting guidance.

## Phase 6: Produce a Design Research Workflow

When external research is justified, use this sequence:

1. Define the user problem and screen or flow boundary.
2. Inspect the current implementation and running product.
3. Select only the resources relevant to the classified need.
4. Gather three to five strong references, not a giant mood board.
5. Identify repeated principles across the references.
6. Record which patterns should not be used and why.
7. Write a compact design brief covering:
   - user goal
   - information hierarchy
   - interaction model
   - visual direction
   - component and state requirements
   - accessibility requirements
   - platform-specific constraints
8. Implement using the app's native framework and established architecture.
9. Test the real UI at relevant screen sizes and states.
10. Compare the result with the brief and refine before declaring completion.

## Guardrails Against Biased or Generic Results

- Do not assume dark mode, glass effects, gradients, minimalism, maximalism, or any other style is inherently superior.
- Do not preserve the existing style when it is part of the problem.
- Do not discard a strong existing identity merely because external references look newer.
- Do not copy screenshots, branding, proprietary assets, or distinctive product compositions.
- Do not confuse a polished landing page with a usable application interface.
- Do not let a web resource dictate native interaction behavior.
- Do not let a native reference dictate desktop or web behavior.
- Do not optimize visual novelty ahead of comprehension and task completion.
- Do not recommend permanent integration when occasional browser research is enough.
- Separate evidence-backed observations from subjective design preference.

## Required Agent Deliverable

Ask the evaluating agent to return:

1. A brief description of the app and its highest-priority design needs.
2. A candid assessment of every resource.
3. An `Adopt`, `Adapt`, `Reference`, or `Skip` decision for each resource.
4. The specific tasks for which each selected resource should activate.
5. Important limitations based on the app's platform and stack.
6. A recommended combined workflow with minimal overlap.
7. Whether an app-specific agent skill would provide recurring value.
8. A proposed skill outline if creating one is justified.
9. Clear separation between research tools and implementation authorities.

## Ready-to-Paste Request for Another AI Agent

```text
Thoroughly evaluate the UI/UX resources listed below for this specific app. Treat the resources as trusted; do not use source trust as a disadvantage. Be candid about product fit, platform fit, implementation relevance, overlap, maintenance cost, and limitations.

Resources:
- https://github.com/BuilderIO/skills
- https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
- https://21st.dev/community/components
- https://www.ux-components.com/components
- https://www.ux-components.com/design-systems.html
- https://refero.design/

First inspect and understand this app rather than inheriting assumptions from another project. Determine:
- the app's purpose and audience
- its critical workflows
- its target platforms and implementation stack
- its current design maturity and identity
- its most important UI/UX weaknesses
- its accessibility and technical constraints

Then classify our needs, assess each resource, and assign it one outcome: Adopt, Adapt, Reference, or Skip.

Do not install everything by default. Do not assume any particular aesthetic is correct. Do not copy another app's screens or translate web conventions literally into native UI. Distinguish visual research, component-behavior guidance, implementation code, and agent-workflow improvements.

Recommend the smallest combined system that materially improves this app. If a project-specific design-research skill would be valuable, outline its automatic triggers, workflow, source-selection rules, implementation handoff, and validation requirements.

Return evidence-backed findings first, then your recommendation.
```

## Short Version

```text
Evaluate Builder.io Skills, UI UX Pro Max, 21st.dev, UX Components, and Refero for this app without assuming its style or platform. Inspect the product first, identify its actual design needs, and decide whether each resource should be Adopted, Adapted, Referenced, or Skipped. Recommend the smallest non-overlapping workflow, preserve platform-native behavior, and propose an app-specific design-research skill only if it provides recurring value.
```

## Final Decision Standard

The best resource set is not the one with the most components, skills, or inspiration.

It is the smallest set that helps agents understand the product, make better design decisions, implement them correctly for the platform, and validate that users can complete important tasks more easily.
