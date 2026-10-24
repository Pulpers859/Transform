# Apple Watch work — parked until the owner has a paid Apple Developer account

Parked by the owner on 2026-10-24. He sideloads through Signulous and has no paid Apple
Developer Program membership. Read this before starting any watch work.

## Shipped (works without a paid account)

- **Rest-over alert** (commits 1f979e9, 97a1276, baa4f47). A local notification mirrors each
  exercise's rest timer. iOS forwards it to a paired Apple Watch when the phone is locked.
  - Rules live in `Transform/Transform/RestEndAlert.swift`: `RestTimerClock` and `RestEndAlerts`.
    Both are headless and pinned by `RestEndAlertTests`, including a seeded 50,000-step random walk.
  - The iOS adapter and the foreground delegate are in `RestEndNotifications.swift`. They are not
    covered by a test.
  - CI on baa4f47: the Swift build and Generator full were both green, and all 9
    RestEndAlertTests ran.
  - On-device result: not reported yet at the time of writing.

## Council findings (2026-10-23). Each finding carries its grade as reported then.

- **Signulous.** It signs uploaded iPhone/iPad .ipa files only. Nothing was found showing it
  installs watchOS apps (guess, based on absence of evidence). One source says Xcode with a
  developer account is the only way to put a custom app on a watch. A full watch app is
  therefore treated as blocked until he has a paid account.
- **Free vs paid tiers** (verified from Apple's capability tables).
  - The free tier has HealthKit, App Groups and Background Modes.
  - The free tier does not have iCloud/CloudKit or push notifications.
  - Free provisioning profiles expire after 7 days.
- **Data path.** App Groups do not span phone and watch (forum-sourced). WatchConnectivity
  `transferUserInfo` is the recommended path. Under it:
  - the phone stays the only writer;
  - the watch sends "log this set" messages, each with a unique ID and the time the set was done.
  - Do NOT use SwiftData+CloudKit. It needs a paid account, and it would change the store that
    holds logged history.
- **Code risks** (verified in code at 72ff325).
  - `SetLoggingService.logSet` replaces a set by its set number. A late watch message would
    silently overwrite numbers already entered on the phone.
  - `logSet` defaults to `on date: .now`.
  - Completing the exercise and starting rest happen in the card's `logSetFromCard`, not in the
    service.
  - The suggested load is built inside the `ExerciseCard` view, not stored anywhere.
- **Live Activity (lock-screen rest timer).** Apple says Live Activities appear in the Watch Smart
  Stack automatically (iOS 18 / watchOS 11+). It needs a Widget Extension target.
  - Avoid App Groups: pass everything through ActivityAttributes/ContentState and count down with
    `Text(timerInterval:)`.
  - Whether Signulous signs an extension correctly is unverified. Settle it with a tiny probe
    extension before building the real thing.
  - Ask the owner how he exports his .ipa.
- **CI.** `swift.yml` builds only `-target Transform -sdk iphonesimulator`. A watch or widget
  target needs its own build step. CI builds with `CODE_SIGNING_ALLOWED=NO`, so signing problems
  surface only on the owner's devices. Have the owner add new targets in Xcode (Add Target)
  rather than an agent hand-editing `project.pbxproj`.

## Suggested order once he has a paid account

1. Lock-screen Live Activity for the rest timer. It also shows on the watch.
2. A watch app as a thin remote: a reps/RIR entry screen, with the weight carried from the phone,
   through WatchConnectivity. Add dedupe-by-ID and no-overwrite rules in the phone's save path,
   with tests first.
