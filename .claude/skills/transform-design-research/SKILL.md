---
name: transform-design-research
description: Research, design, implement, and review substantial Transform UI or UX changes using focused product references and native iOS guidance. Use automatically for screen redesigns, new user flows, onboarding, dashboards, progress or analytics experiences, navigation changes, design-system decisions, accessibility reviews, or requests to make the app feel clearer, more polished, premium, cohesive, or distinctly native. Do not use for tiny copy, spacing, or isolated bug fixes unless broader design judgment is required.
---

# Transform Design Research

Use this skill to turn external design inspiration into a coherent, accessible, native Transform experience rather than copying screenshots or web components.

## Workflow

1. Define the design problem before browsing:
   - user goal
   - current friction
   - screen or flow boundary
   - information that must remain prominent
   - existing Transform patterns worth preserving
2. Inspect the current implementation (and screenshots from the owner's device, when available) before proposing a replacement.
3. Choose only the sources that answer the current question. Read `references/source-guide.md`.
4. Gather 3-5 relevant references total. Prefer real iOS screens and complete flows over disconnected visual fragments.
5. Write a compact design brief before coding:
   - observed patterns
   - principles worth borrowing
   - patterns rejected and why
   - proposed hierarchy, interaction model, and visual direction
   - accessibility and Dynamic Type considerations
6. Implement directly with existing Transform patterns: `DesignSystem.swift` tokens (`TFColor`, `TFTypography`, `TFHaptics`), native SwiftUI controls and navigation, and the app's established component conventions. (Older docs referenced external `swiftui-*` helper skills; those were Builder.io-sourced and are retired — do not look for them.)
7. Validate what the environment allows: reread the diff against the design brief, smoke-check syntax (`swiftc -parse <file>` on Windows), and confirm token usage. Then hand off to the owner for the real validation — build in Xcode, run on the physical iPhone. Never suggest or wait on the iOS Simulator; the owner intentionally does not use it. List the states worth checking on device: normal, loading, empty, error, selected, disabled, reduced motion, Dynamic Type.
8. Compare the result against the design brief and the existing app. Refine obvious hierarchy, legibility, interaction, or consistency problems before handoff.

## Source Roles

- Use Refero first for real iOS screens, product flows, and interaction sequencing.
- Use UI UX Pro Max selectively for visual vocabulary, palette, typography, style exploration, and anti-pattern prompts.
- Use UX Components for component anatomy, behavior, states, accessibility, and pattern comparisons.
- Use 21st.dev only for web work or occasional motion and visual inspiration. Never translate React or Tailwind code directly into SwiftUI.

## Rules

- Treat references as evidence and inspiration, not templates to copy.
- Keep Transform recognizable. Preserve strong existing product language unless the task explicitly calls for a new direction.
- Prefer native controls, navigation, gestures, semantics, and accessibility behavior over a visually novel imitation.
- Do not let a generated web design system dictate SwiftUI architecture.
- Do not use Google Fonts, CSS breakpoints, hover behavior, Play Store conventions, or web-only layout advice for the native iOS app.
- Do not invoke every source for every task. A focused design question may need only Refero and Apple-native implementation guidance.
- Do not add visual complexity without improving comprehension, confidence, or task completion.
- Distinguish research findings from subjective design judgment.
- Keep routine fixes routine; this workflow should not turn a one-line UI correction into a research project.

## Expected Output

For a substantial design task, leave behind:

1. a short design brief
2. the implemented native UI
3. whatever validation the environment allowed (diff review, syntax smoke check) stated honestly
4. a concise note describing what changed, what was validated versus what needs the owner's on-device check, and any remaining design risk

## Provenance

- Last verified: 2026-07-05 against commit `0a68ce9`. Design tokens confirmed in `Transform/Transform/DesignSystem.swift`. The formerly referenced `swiftui-*` skills are retired (owner-confirmed 2026-07-05; they came from the Builder.io skills evaluation, see `docs/AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md`). External design sources (Refero, UI UX Pro Max, UX Components, 21st.dev) remain session-dependent — verify availability at use time.
- See `docs/AGENT_RESOURCE_DECISIONS.md` for the resource decisions of record.
