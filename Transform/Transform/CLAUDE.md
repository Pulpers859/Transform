# Transform Project Instructions

## Project Purpose
Transform is a native iOS app for body analysis, workout programming, training execution, nutrition tracking, progress tracking, and durable user data handling.

The app is not a generic fitness toy. It should behave like a careful hybrid of:
- a senior iOS / Swift / SwiftUI / SwiftData app
- an evidence-informed hypertrophy coaching system

## Product Priorities
Order matters:
1. Workout quality
2. Evidence-informed programming integrity
3. Robustness and silent-bug prevention
4. Validator correctness
5. Reducing wasted AI / API usage
6. Maintainable architecture

## Non-Negotiables
- Fix root causes, not cosmetic symptoms.
- Do not dumb down training output just to satisfy a rigid validator.
- If the validator is wrong, improve the validator.
- Keep evidence/profile logic, metadata logic, blueprint logic, validation logic, and fallback logic in sync.
- Do not silently tolerate brittle fallbacks, stale prompt assumptions, or naming drift that fragments progression tracking.
- Do not silently overwrite or revert unrelated changes.
- Distinguish evidence-backed guidance from heuristic choices.
- Preserve the app's existing style and user-facing experience unless a change is explicitly requested.

## Architecture Expectations
- Respect the split `WorkoutGeneratorService` architecture. Do not collapse it back into one giant file.
- Prefer small targeted fixes inside the correct layer:
  - prompt/request construction
  - parsing/sanitization
  - metadata and evidence profile mapping
  - training intent / blueprint generation
  - validation
  - fallback generation and repair
  - UI state / persistence / backup
- When a file becomes a maintenance risk, refactor carefully instead of layering more ad hoc logic into it.

## Workout Generator Standards
- A validator-clean week is not automatically a good week.
- Prime hypertrophy work must not be replaced in practice by corrective or support work masquerading as direct volume.
- Exercise naming should be canonical enough to preserve progression tracking.
- Support or scapular-control work should not be over-credited as main hypertrophy stimulus.
- Focus-day structure should feel like real programming, not a checklist assembled to satisfy metadata.
- Fallback output must be safe, coherent, and close enough to useful coaching to avoid feeling like a degraded emergency mode.

## Known Failure Modes To Guard Against
- AI output passes schema but gives mediocre coaching.
- Validator over-credits support work or under-credits good hypertrophy work.
- Metadata aliasing inflates or fragments focus demand.
- Fallback silently underdelivers blueprint targets.
- Prompt wording and validator policy drift apart.
- Program summaries or source badges drift from actual generation source.
- Exercise naming variation breaks weight-history continuity.
- Retry behavior burns API credits on obviously doomed attempts.

## Body Analysis Standards
- Never silently hardcode one person's profile into generic prompts or fallback defaults.
- For this personal-use build, a one-time baseline seed into editable app settings is acceptable when it preserves user control and does not masquerade as generic multi-user behavior.
- Analysis should shape training, but vague lifestyle assumptions should not be smuggled in as facts.
- Postural and injury notes must influence exercise selection and warm-up guidance when relevant.

## Persistence And Safety Standards
- Protect save / rollback / backup consistency.
- Avoid stale decoded analysis rework.
- Be careful with SwiftUI task ownership, cancellation, and state updates around async flows.
- Prefer explicit data-flow fixes over patching UI symptoms.

## Review Standards
When reviewing work, prioritize:
1. shipping bugs
2. coaching-quality regressions
3. validator / fallback mismatches
4. silent failure risk
5. API-credit waste
6. maintainability problems that are likely to compound

Findings should come first, ordered by severity, with file references. Summaries are secondary.

## Working Style
- Inspect current code before assuming prior context.
- Make direct changes when the path is clear.
- After each fix, do another harsh adjacent-risk pass.
- If you cannot validate something fully, say exactly what was and was not validated.
- On Windows, use the Swift sanity check for smoke validation when possible. On macOS, prefer real Xcode or simulator validation.

## Files Usually Relevant For Core AI / Training Work
- `ClaudeService.swift`
- `AnthropicClient.swift`
- `WorkoutGeneratorService.swift`
- `WorkoutGeneratorService+Requests.swift`
- `WorkoutGeneratorService+ParsingValidation.swift`
- `WorkoutGeneratorService+MetadataProfiles.swift`
- `WorkoutGeneratorService+PriorityIntent.swift`
- `WorkoutGeneratorService+TrainingIntentBlueprint.swift`
- `WorkoutGeneratorService+ExerciseSelection.swift`
- `WorkoutGeneratorService+FallbackCore.swift`
- `WorkoutGeneratorLabView.swift`
- `WorkoutGeneratorDebugModels.swift`
- `EvidenceProfile.md`

## Default Decision Rule
If a proposed AI-workflow or automation feature improves repeatability, reduces regressions, or cuts waste without hiding behavior, it is good.
If it mainly makes the setup look advanced while increasing indirection, it is bad.
