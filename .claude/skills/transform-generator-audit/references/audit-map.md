# Transform Generator Audit Map

## Source-of-truth paths

- Repo root: `C:\Dev\Transform_clean`
- App source root: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`

## Read first

- `2_PROJECT_HANDOFF.md`
- `3_TRANSFORM_CLEAN_HANDOFF.md`
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
- `WorkoutGeneratorLabView.swift`
- `WorkoutGeneratorDebugModels.swift`
- `WorkoutModels.swift`
- `AnthropicClient.swift`
- `ClaudeService.swift`

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

- Heuristic issue tiering and correction-loop acceptance behavior
- Over-volume detection and validator warning policy
- Uniform prescription cleanup in sanitization
- Prompt caching and model-ID changes in Anthropic request paths
- Canonical exercise key handling for progression continuity
