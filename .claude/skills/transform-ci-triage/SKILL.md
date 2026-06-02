---
name: transform-ci-triage
description: Triage Transform GitHub Actions failures, Xcode build issues, missing-scheme problems, and workflow drift between the real iOS project layout and CI. Use when Swift or Xcode checks fail on GitHub, when PR workflows do the wrong kind of build, or when local success and CI behavior disagree.
---

# Transform CI Triage

Use this skill to debug Transform CI with the assumption that the repo is an Xcode iOS app first, not a Swift Package, and that many failures come from workflow/project mismatch rather than app code.

## Workflow

1. Confirm the source-of-truth repo is `C:\Dev\Transform_clean`.
2. Read `references/ci-map.md`.
3. Inspect the failing workflow, run, and logs before editing any YAML.
4. Classify the failure before fixing it:
   - workflow is building the wrong thing
   - Xcode project path or target is wrong
   - scheme/shared-scheme problem
   - signing / destination problem
   - app compile error
   - test-only failure
5. Prefer the smallest reliable fix:
   - align CI with the actual Xcode project
   - avoid forcing the repo into SwiftPM just to satisfy stock templates
   - keep checks build-only if test infrastructure is not ready
6. After fixing CI, explain whether the failure was:
   - workflow configuration
   - project configuration
   - actual code regression

## Rules

- Treat GitHub logs as the source of truth for the failing step.
- Keep the workflow minimal and boring unless the user explicitly wants more automation.
- Prefer `xcodebuild` against the real project/target over fake generic Swift workflows.
- If tests are flaky because schemes are not shared or infrastructure is missing, say that plainly.
- Distinguish "CI is wrong" from "the app code is wrong."

## Common Uses

- "Why does GitHub Actions fail every push?"
- "Fix this Swift/Xcode CI error from my PR."
- "Make the workflow match the real Transform project."
- "Check whether this build failure is from workflow drift or app code."

## References

- Read `references/ci-map.md` for workflow paths, project layout, and triage checklists.
