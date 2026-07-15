# Generator Troubleshooting Workflow

This workflow removes the physical iPhone from most workout-generator debugging while
keeping the limits honest. It does not add OpenAI or ChatGPT to the app.

## What runs without the phone

1. `Generator Tests` runs the complete deterministic planning core on every push:
   training intent, blueprint, locked menu, set allocation, validator, and procedural fallback.
2. `Generator Troubleshooting` can be started manually in GitHub Actions. Its deterministic
   job recreates the privacy-safe priority/recovery conditions behind the historical five
   maintenance-volume errors and uploads the allocated-menu snapshot. It is a failure-class
   regression, not a byte-for-byte replay of the old Workshop bundle.
3. `tools/Invoke-GeneratorSecondAudit.ps1` sends a credential-scanned tracked/staged diff to
   the locally authenticated Claude Code CLI for an independent review. Claude receives no
   tools and cannot inspect the filesystem, edit files, or run commands. The script refuses
   untracked files; stage the intended review files first.

## Optional live Anthropic smoke test

The manual workflow also has an API-billed job. It runs only when both controls are supplied:

- `run_live_ai` is enabled.
- `confirm_api_usage` is exactly `RUN_LIVE_AI`.

The job maps the repository's `ANTHROPIC_API_KEY` GitHub secret to the headless-only
`TRANSFORM_HEADLESS_ANTHROPIC_API_KEY` process variable. That variable is read only when UIKit
is unavailable, so the credential path is compiled out of the iPhone app. The key is never
written to a fixture or artifact.

The live test composes the same production request construction, structured tool call, parsing,
sanitization, locked-menu set prescription, and validator functions used by `generateWeekOne`.
It deliberately sends exactly one logical request with one permitted HTTP attempt. It does not
run parallel candidate scoring, correction, or fallback orchestration. This narrower seam proves
the live contract without allowing a smoke test to expand into as many as nine paid HTTP attempts.
It uses the configured lightweight generation model, so it is not a claim about the production
Week 1 model's output distribution.

The uploaded report uses a synthetic analysis fixture with no personal, photo, medical, or
training-history data. It contains counts and validator findings only: no prompts, raw model
payload, final workout JSON, or credential. A passing live run must return seven days, preserve
five training days, pass the expected validator verdict, and avoid the five historical findings.

## What still requires the physical iPhone

The headless workflow cannot prove the Xcode app target builds, iOS Keychain behavior works,
SwiftUI state and persistence are correct, or the generated program feels right on-device.
Use the physical iPhone for release validation and occasional end-to-end checks, not as the
primary generator debugger.

## Normal agent loop

1. Reproduce a finding with a privacy-safe fixture or captured JSON.
2. Map it to planning, parsing, metadata, validation, fallback, or UI/debug reporting.
3. Fix the earliest deterministic cause and run the generator tests in macOS CI.
4. Stage the intended files, then run `tools/Invoke-GeneratorSecondAudit.ps1` before committing
   substantial generator work.
5. Resolve every material second-audit finding.
6. Use the live manual workflow only when request/model behavior is relevant.
7. Build and run on the physical iPhone before treating a release as fully validated.

## Honest interpretation

- Deterministic green: the covered planning and validation contracts passed.
- Live smoke green: one bounded Anthropic structured request passed the production parsing,
  sanitization, set-prescription, and validator contract.
- Neither result alone proves every future workout is high quality.
- Device green: the actual app built and completed the tested workflow on the owner's iPhone.
