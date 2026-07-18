# Automated Testing Handoff

This repository is configured by `.swift-automation.json` using schema version 1.

## Repository Contract

- App: Transform
- Project type: hybrid
- Platform: ios
- Workflow mode: existing
- Default branch: main
- Physical device required for final product validation: True

## Workflows

- `.github/workflows/generator-tests.yml`
- `.github/workflows/swift.yml`
- `.github/workflows/generator-troubleshooting.yml`

## Live AI Surfaces

- `workout-generation`: input `run_live_workout`, job `live-workout-contract`, declared maximum 1 HTTP call(s); enforcement evidence: The live workout contract calls AnthropicClient.sendStructuredRequest with attemptLimit 1.
- `nutrition-generation`: input `run_live_nutrition`, job `live-nutrition-contract`, declared maximum 3 HTTP call(s); enforcement evidence: NutritionGeneratorService production generation is capped at the initial request plus bounded correction and retry paths.

## Commands And Secrets

- Swift package: `swift test --enable-xctest --parallel`
- Xcode: `xcodebuild -project Transform.xcodeproj -target Transform build`
- Deterministic prerequisite: `swift test --enable-xctest --filter TransformGeneratorCoreTests.GeneratorTroubleshootingTests/testFiveMaintenanceErrorFixtureStaysResolved`
- workout-generation: `swift test --enable-xctest --filter TransformGeneratorCoreTests.GeneratorTroubleshootingTests/testLiveWeekOneStructuredContract`
- nutrition-generation: `swift test --enable-xctest --filter TransformGeneratorCoreTests.NutritionGeneratorStressTests/testLiveNutritionWeekOneStructuredContract`

- Required provider secret: `ANTHROPIC_API_KEY` exposed only as `TRANSFORM_HEADLESS_ANTHROPIC_API_KEY`.

`swift.yml` is a generic iOS Simulator compile check. It cancels obsolete deterministic runs and,
on failure, uploads both the raw Xcode log and the structured `.xcresult` bundle. It does not boot
or test a simulator runtime; physical-iPhone validation remains required for app behavior.

## Evidence Checkpoint

- Repository commit when this handoff was rendered: `1ac5cbaafae3772b2a37a5425b5b07f9d8201f04`
- Local profile validation: passed.
- Latest GitHub Actions result, observed HTTP-call count, and physical-device result: not recorded by the installer; verify and update after execution.

Live jobs are manual, require the exact confirmation phrase, and depend on the deterministic prerequisite. `maxHttpCalls` is a declared budget and is only enforced when the feature harness reads `SWIFT_AUTOMATION_MAX_HTTP_CALLS` or independently caps attempts. Artifacts must be redacted and must never contain API keys or private user media.

## Agent Instructions

1. Read `.swift-automation.json` before changing workflows.
2. Run deterministic tests before any paid API workflow.
3. Keep every paid feature in its independently mapped existing job.
4. Never print or persist secret values.
5. Report what CI proves separately from what still needs Xcode on a physical Apple device.
