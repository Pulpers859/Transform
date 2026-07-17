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

- `workout-generation`: bounded workout generation contract, declared maximum 1 HTTP call(s). See the listed workflow for its actual job ID.
- `nutrition-generation`: bounded one-week nutrition generation contract, declared maximum 3 HTTP call(s). See the listed workflow for its actual job ID.

Live jobs are manual, require the exact confirmation phrase, and depend on the deterministic prerequisite. `maxHttpCalls` is a declared budget and is only enforced when the feature harness reads and honors `SWIFT_AUTOMATION_MAX_HTTP_CALLS`. Artifacts must be redacted and must never contain API keys or private user media.

## Agent Instructions

1. Read `.swift-automation.json` before changing workflows.
2. Run deterministic tests before any paid API workflow.
3. Keep each paid feature in its own `run_live_<surface>` job.
4. Never print or persist secret values.
5. Report what CI proves separately from what still needs Xcode on a physical Apple device.
