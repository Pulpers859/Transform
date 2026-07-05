# Transform CI Map

## Project layout

- Repo root: `C:\Dev\Transform_clean`
- App folder: `C:\Dev\Transform_clean\Transform`
- Main source tree: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`

## Current workflows

- `.github/workflows/swift.yml` — builds the iOS app target with `xcodebuild`, not `swift build`.
  Verified content (2026-07-05): checkout@v5, `xcodebuild -project Transform.xcodeproj -target Transform
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator'
  CODE_SIGNING_ALLOWED=NO build`, working-directory `Transform`, build-only, no tests.
- `.github/workflows/claude.yml` — also present; not part of build triage.
- Note: the `iphonesimulator` SDK/destination here is a compile target for CI only. It does not
  contradict the repo's no-simulator validation policy — nobody boots a simulator; the owner
  validates on a physical iPhone. Do not "fix" CI by removing it.

## Current CI realities

- Transform is not a Swift Package at the repo root.
- A stock SwiftPM GitHub Actions template is wrong for this repo.
- The project currently has targets:
  - `Transform`
  - `TransformTests`
  - `TransformUITests`
- There is not currently a tracked shared scheme at `Transform.xcodeproj/xcshareddata/xcschemes/Transform.xcscheme`.
- Because of that, minimal CI should stay build-focused unless scheme sharing/test infrastructure is intentionally added.

## Triage checklist

1. Read the failing run and identify the exact failing command.
2. Decide whether the failure is from workflow mismatch, project configuration, or app code.
3. Check workflow path, working directory, target/scheme, destination, and signing flags.
4. Prefer:
   - `xcodebuild -project Transform.xcodeproj -target Transform ... build`
   over generic `swift build`.
5. If the failure mentions `Package.swift`, the workflow is almost certainly wrong.
6. If the failure mentions a scheme, check whether a shared scheme is committed.
7. If the failure is a compile error, inspect the referenced Swift file and line before changing CI.

## Good defaults

- Use `actions/checkout@v5`
- Use `CODE_SIGNING_ALLOWED=NO` for CI builds
- Use an iOS Simulator destination for app builds (compile target only; see note above)
- Keep the workflow boring unless a stronger need appears

## Provenance

- Last verified: 2026-07-05 against commit `0a68ce9` (workflow contents read; no shared
  `.xcscheme` tracked — confirmed via `git ls-files "*.xcscheme"` returning nothing).
- Re-verify: read `.github/workflows/swift.yml`; `git ls-files "*.xcscheme"`.
