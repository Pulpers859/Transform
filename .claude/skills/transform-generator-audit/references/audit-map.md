# Transform Generator Audit Map

## Source-of-truth paths

- Repo root: `C:\Dev\Transform_clean`
- App source root: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`

## Read first

- `docs/2_PROJECT_HANDOFF.md`
- `docs/3_TRANSFORM_CLEAN_HANDOFF.md`
- `Transform/Transform/CLAUDE.md`
- `Transform/Transform/EvidenceProfile.md`

## Primary code hotspots

- `WorkoutGeneratorService.swift`
- `WorkoutGeneratorService+Requests.swift`
- `WorkoutGeneratorService+ParsingValidation.swift`
- `WorkoutGeneratorService+MetadataProfiles.swift`
- `WorkoutGeneratorService+PriorityIntent.swift`
- `WorkoutGeneratorService+TrainingIntentBlueprint.swift`
- `WorkoutGeneratorService+ExerciseSelection.swift`
- `WorkoutGeneratorService+FallbackCore.swift`
- `WorkoutGeneratorService+FocusCoachingContext.swift`
- `WorkoutGeneratorService+PlanningTypes.swift`
- `WorkoutGenerationDiagnostics.swift`
- `WorkoutGeneratorLabView.swift`
- `WorkoutGeneratorDebugModels.swift`
- `WorkoutModels.swift`
- `AnthropicClient.swift`
- `ClaudeService.swift`

## Menu-locked generation contract (as of commit `0a68ce9`)

- Exercise selection is deterministic: the app builds a locked exercise menu BEFORE the AI call
  (`9071ef5`); the AI fills sets/reps/coaching around it. Do not reintroduce free-form AI
  exercise selection or prompt text implying the AI chooses exercises (`2544e70` removed it).
- Fallback consumes the same pre-selected menu instead of building its own (`cd22591`).
- Menu-locked repair boosts set counts on existing menu exercises only — it must not inject or
  remove exercises (`55836f8`); watch `rebalanceDirectSets` overcounting/overshoot (`edb99f1`).
- Empty programs are deleted on re-generation; programs with logged data are archived to preserve
  skip/pain history for future programming (`5a24463`, `0a68ce9`).
- Retries are for structural failures only; heuristic quality issues are warnings handled by
  sanitization/validator policy, not re-billed API calls (`ec09e64`, `4ab06f3`).

## Audit questions

1. Is the output actually good programming, or just validator-clean?
2. Is a priority muscle receiving prime hypertrophy work or fake credit from support/corrective drills?
3. Is the validator catching the right issue and classifying it in the right severity tier?
4. Is the retry loop spending API calls on problems that should be fixed in sanitization or validator policy?
5. Is fallback safely useful, or silently underdelivering blueprint targets?
6. Is naming drift going to break continuity or weight-history tracking?

## Current known failure patterns

- Prompt wording and validator policy drift apart.
- Validator over-credits support work or under-credits direct hypertrophy stimulus.
- Metadata aliasing fragments focus demand.
- Fallback misses frequency/direct-set targets without obvious UI explanation.
- Retry behavior burns credits on heuristic-only issues.
- Sanitization regressions can cause silent crashes or hide root causes.

## Recent areas of change worth double-checking

- Menu-locked fallback repair (set boosting without injection) and direct-set rebalancing
- Pain-driven exercise avoidance, equipment deprioritization, accessory variation cycling (`a9564e6`)
- Heuristic issue tiering and correction-loop acceptance behavior
- Over-volume detection and validator warning policy
- Uniform prescription cleanup in sanitization
- Prompt caching and model-ID changes in Anthropic request paths
- Canonical exercise key handling for progression continuity (see `transform-data-safety`)

## Provenance

- Last verified: 2026-07-05 against commit `0a68ce9`. All hotspot files confirmed present.
- Re-verify hotspots: `git ls-files "Transform/Transform/WorkoutGenerator*"`; recent arcs: `git log --oneline -20`.
