# Generator Troubleshooting Workflow

This workflow removes the physical iPhone from most deterministic workout- and
nutrition-generator debugging while keeping the limits honest. It does not add OpenAI or
ChatGPT to the app, and it does not currently automate body analysis.

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

The manual workflow also has independently selectable API-billed jobs. Each runs only when
the selected job's switch and the authorization control are supplied:

- `run_live_workout` enables only the workout contract check.
- `run_live_nutrition` enables only the one-week nutrition contract check.
- `confirm_api_usage` is exactly `RUN_LIVE_AI`.

Leave the other generator switch disabled. Selecting nutrition does not invoke the workout
generator, and selecting workout does not invoke nutrition.

The job maps the repository's `ANTHROPIC_API_KEY` GitHub secret to the headless-only
`TRANSFORM_HEADLESS_ANTHROPIC_API_KEY` process variable. That variable is read only when UIKit
is unavailable, so the credential path is compiled out of the iPhone app. The key is never
written to a fixture or artifact.

The workout contract exercises the production structured request, parsing, sanitization,
locked-menu prescription, and validator seam used by `generateWeekOne`. It deliberately sends
one logical request with one permitted HTTP attempt.

The nutrition contract exercises the production one-week structured request, sanitization, and
nutrition validator seam. It creates only Week 1, never an automatic Weeks 2-4 loop. The two
jobs do not invoke one another or run parallel candidate scoring. They use the configured
lightweight model, so neither is a claim about the full production output distribution or
subjective coaching quality.

Nutrition's production service may issue up to three HTTP calls when a response needs a correction
or recoverable retry. That is still one seven-day generation and does not generate Weeks 2-4. The
nutrition-only run on `1353584` completed with two successful Anthropic calls: the first response
needed correction and the second passed validation. The workout job was skipped.

The uploaded reports use synthetic analysis fixtures with no personal, photo, medical, or
training-history data. They contain counts and validator findings only: no prompts, raw model
payload, final program JSON, or credential. A passing workout run must return seven days,
preserve five training days, pass the expected validator verdict, and avoid the five historical
findings. A passing nutrition run must return a valid AI-sourced Week 1 seven-day plan with no
nutrition validator issues.

## Why Body Analysis Is Not a Live Job Yet

Body analysis must eventually be a separate `run_live_bodyanalysis` selector and dedicated job;
it must never be bundled with workout or nutrition. It is intentionally absent today because the
shipping path is UIKit-gated, consumes real photo data, and has no privacy-safe Foundation-only
live fixture. Adding a no-op switch would create false confidence.

Before it is wired, refactor a Foundation-safe request seam, add deterministic decoder and
validator fixtures, establish a non-personal rights-cleared image fixture, redact every artifact,
and retain physical-iPhone validation for real-photo quality and persistence. Never send a user's
phone photo through GitHub Actions.

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
- Live workout green: the selected structured workout request passed its production contract.
- Live nutrition green: the selected one-week nutrition path passed after zero to two correction
  retries; report the actual observed HTTP-call count.
- Neither result alone proves every future workout, nutrition plan, or body analysis is high quality.
- Device green: the actual app built and completed the tested workflow on the owner's iPhone.
