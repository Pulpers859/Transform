# Transform CI Map

## Project layout

- Repo root: `C:\Dev\Transform_clean`
- App folder: `C:\Dev\Transform_clean\Transform`
- Main source tree: `C:\Dev\Transform_clean\Transform\Transform`
- Xcode project: `C:\Dev\Transform_clean\Transform\Transform.xcodeproj`

## Current workflow

- Workflow file in repo: `C:\Dev\Transform_clean\.github\workflows\swift.yml`
- Current intent: build the iOS app target with `xcodebuild`, not `swift build`

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
- Use an iOS Simulator destination for app builds
- Keep the workflow boring unless a stronger need appears
