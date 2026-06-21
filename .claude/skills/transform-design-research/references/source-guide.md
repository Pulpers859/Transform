# Design Research Source Guide

## Refero

URL: https://refero.design/

Use for:
- real product screens
- native iOS flows
- onboarding and conversion sequences
- dashboards, progress views, settings, and account flows
- understanding how information changes across multiple screens

Prefer a few closely related references over a large mood board.

## UI UX Pro Max

URL: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill

Use for:
- visual style vocabulary
- color and typography exploration
- design-system prompts
- common UI anti-pattern checks

Treat its SwiftUI and platform advice as secondary. Explicitly constrain research to a native iOS fitness product, and reject CSS, hover, web breakpoint, Google Font, or app-store landing-page output.

## UX Components

URLs:
- https://www.ux-components.com/components
- https://www.ux-components.com/design-systems.html

Use for:
- component behavior and anatomy
- state coverage
- accessibility considerations
- comparing established interaction patterns

Use Apple conventions as the final authority for native implementation.

## 21st.dev

URL: https://21st.dev/community/components

Use for:
- Transform web experiences
- occasional motion, composition, or visual inspiration

Do not copy React, Tailwind, browser interaction, or marketing-page conventions into SwiftUI.

## Taste-Skill

Secondary, principles-only source. Confirm the exact GitHub URL before deeper use
(see `docs/AGENT_RESOURCE_DECISIONS.md`).

Use for:
- general design-quality principles: hierarchy, spacing, typographic scale, restraint
- a sanity check against generic AI-built layout

Treat it as the weakest authority here. These taste packs are web-oriented
(React/Tailwind/HTML/CSS), so extract principles only and reject any CSS, hover,
breakpoint, font, or web-layout specifics. Apple conventions and the rules in this
skill remain the final authority for native implementation. Never let it drive
SwiftUI structure.

## Selection Heuristic

- New or redesigned iOS flow: Refero plus Apple-native skills.
- Visual-direction exploration: Refero plus UI UX Pro Max.
- Component behavior or state question: UX Components plus Apple-native skills.
- Web page or future marketing site: 21st.dev plus the web implementation skills.
- General "does this feel premium / not generic" gut check: Taste-Skill principles only, never as an authority.
- Small UI bug: skip external research unless the symptom reveals a larger design problem.
