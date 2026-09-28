# Compact set logging

## Design boundary

Keep the existing exercise card, counter, Details disclosure, and set rows. Idle
sets show no performed values. Selecting a row prepares only its suggested load;
reps and optional RIR must be entered. Saved results alone earn a checkmark.
Only one inline row is open for entry. Unfinished drafts survive switching rows
within the current view; they are not durable workout records.

Cross-prescription starting-load estimates use a compact line on the card, with
the explanation and uncertainty under Details. Existing recovery and safety
warnings remain visible. No progression arithmetic, history keys, database
schema, or generator allocation policy changed.

The rest-timer entry follows the same explicit-reps rule. Neither logger moves
past a failed save. Selecting bodyweight does not invent reps. Invalid optional
RIR prevents saving instead of silently dropping the entered value.

## Automated coverage

`SetEntryDraftTests` exercises the shipping draft helper: invalid/nonfinite
values, explicit bodyweight, comma decimals, blank reps, independent drafts,
failed-save retention, successful reset, duplicate submission, and saved-versus-
editing row presentation. The stress case uses 100 drafts and 10 failed retries
per draft. These are logic tests, not SwiftUI gesture or SwiftData failure tests.

Independent review caught and prompted fixes for deload-load precedence and
saved-result visibility when switching away from an unfinished edit.

## Physical-iPhone checks (no paid generation needed)

1. Open Log sets on an existing workout. Unstarted rows must be blank, not
   populated with last session's reps.
2. Tap a set. Only its load may be prepared. Log must remain disabled until
   actual reps are entered. Selecting Bodyweight must not fill reps.
3. Switch rows before saving. The other row must not inherit the first row's
   reps. Returning must preserve the unfinished draft.
4. Log an actually performed set. Confirm the counter and saved checkmark;
   reopen the app to confirm the stored result. Do not log fictional test work.
5. Edit a saved set, switch rows, then return. Its stored result must remain
   visible while the edit is unsaved, and the draft must be retained.
6. Open the full-screen rest timer. New sets need actual reps; stepping between
   sets must not copy prior reps. Check narrow-screen and larger-text usability.

Windows cannot validate SwiftUI layout, keyboard focus, gestures, or on-device
persistence. GitHub's app build supplies type checking; the owner checks runtime.
