# Workout-day reset

Owner approved clearing one day's saved sets, skip/pain marks, timer and feedback,
while retaining its current exercise choices and other days' history.

## UI

Day screen → top-right ellipsis → Cancel Accidental Start / Reset Workout Day.
Native destructive confirmation names what is cleared; no additional card or input.
Finishing a session with no recorded work offers cancellation instead of feedback.
Reset recreates exercise-card state, discarding unsaved row drafts and rest timers.
Existing exercise preferences and replacement links remain; completed sets on
earlier replacement segments return to the currently selected exercise's budget.

Design references: [Apple alerts](https://developer.apple.com/design/human-interface-guidelines/alerts),
[undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo),
[native menus](https://developer.apple.com/documentation/swiftui/populating-swiftui-menus-with-adaptive-controls).
Keep destructive actions secondary; use explicit confirmation rather than an
ambiguous OK button. Native menu/dialog labels support accessibility and Dynamic Type.

## Data boundary and limitations

No schema, exercise key, backup guard or automatic migration changes. Explicit
user-triggered destructive action only. The current nonarchived program's creation
date and day number scope logs, using the app's existing program-history boundary.
Legacy logs do not contain program IDs: this is not proof of ownership for every
historically hand-edited/imported database. Overlapping old-day timestamps, newer
programs, duplicate days, unscoped recent records, untraceable recent personal bests,
and malformed replacement chains are refused rather than guessed.

Affected latest/best summaries are rebuilt from surviving evidence; unaffected
summary components and legacy history are preserved. One save, rollback on failure,
and refusal of unrelated pending edits. Existing backup data-drop protection stays
enabled: a sufficiently large deliberate reset may preserve the pre-reset backup
instead of writing a new automatic backup. No in-app undo is promised.

## Validation

WorkoutDayResetTests covers empty stale session recovery, replacement availability,
persisted reopening, scoped deletion, feedback/status clearing, weight/BW summaries,
partial and alias replacement budget recovery, repeated reset, rollback,
ambiguous personal bests, overlapping older programs, unscoped legacy records,
and archived/dirty context refusal. Tests require macOS SwiftData CI; Windows parse
checks are syntax-only. Physical-iPhone interaction is still owner validation.

## Owner check after successful CI

1. Open the accidentally started day. Tap … → Cancel Accidental Start and confirm.
   Timer should disappear, no feedback should open, replacement choices should return.
2. On a day with intentionally incorrect test records, tap … → Reset Workout Day.
   Cancel first: nothing changes. Repeat and confirm: the same exercises remain,
   logged sets/statuses/feedback clear, and the day can start again.
3. Close/reopen the app. That day should still be reset; another day's logs and
   genuine previous weight history should still be present. No new generation needed.
