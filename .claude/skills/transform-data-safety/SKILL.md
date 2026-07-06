---
name: transform-data-safety
description: Guard rails for editing Transform's exercise naming, canonical keys, progression/weight history, persistence, migration, backup, and archiving code. Use whenever a change touches exercise name matching, ExerciseWeightStore, canonicalLookupKey, performance logs, SwiftData models, program archiving/deletion, DataBackupManager, or startup integrity checks — this is the code where past bugs silently destroyed the owner's logged training data.
---

# Transform Data Safety

Use this skill when a change touches the paths that store, match, migrate, back up, or delete the owner's training data. This is the highest-consequence code in the app: bugs here don't crash — they silently erase months of logged weights, reps, skips, and pain history.

## When to use

- Any edit near exercise naming, normalization, or canonical key logic.
- Any edit to progression/weight-history storage or lookup.
- Any edit to SwiftData model shapes, persistence, migration, or startup normalization.
- Any edit to backup, restore, rollback, archiving, or deletion behavior.
- Reviewing a diff that touches the files below, even incidentally.

## When NOT to use

- Pure generator prompt/validator logic with no persistence contact (use `transform-generator-audit`).
- UI-only changes that read but do not write or re-key stored data.

## Load-bearing code (verified 2026-07-05)

- `Transform/Transform/WorkoutModels.swift:343` — `canonicalLookupKey(_:)`: the single point of truth matching progression data across program regenerations. If "Bench Presses" and "Bench Press" ever key differently, history orphans silently.
- `Transform/Transform/WorkoutModels.swift:622` — `ExerciseWeightStore`: weight/rep history storage and lookup.
- `Transform/Transform/WorkoutModels.swift:713` — `normalizePerformanceLogs(in:)`: startup re-keying pass that repairs stale records after key-algorithm changes. Any canonical-key change MUST be paired with this migration path.
- `Transform/Transform/TransformApp.swift:129` — `DataIntegrityMonitor`: startup integrity checks tracking exercise data counts.
- `Transform/Transform/DataBackupManager.swift` — backups, coalescing, and the data-drop guard (refuses backups that would record a suspicious drop in data).
- `Transform/Transform/PersistenceReporter.swift` — persistence diagnostics.

## Procedure

1. Read the current implementation of every symbol above that the change touches — do not rely on this file's descriptions alone.
2. Classify the change: read-only, additive write, re-keying/migration, or destructive (delete/overwrite/restore). Destructive and re-keying changes get maximum scrutiny.
3. For any naming/keying change, trace the full round trip: generation output name → canonical key → stored record → lookup at display/logging time → survival across a program regeneration.
4. Test stemming edge cases by EXECUTING the algorithm (e.g. a `swift` script replicating `stemForCanonicalKey`), not by mental tracing alone: press/presses, raise/raises, lunge/lunges, bridge/bridges, squeeze/squeezes, crunch/crunches, fly/flies, cross (words ending "ss"). E-ending singulars were a second silent split that mental tracing missed for weeks and one script run caught (2026-07-06; see INC-2 addendum).
5. For model or key changes, confirm a migration path exists (`normalizePerformanceLogs` or equivalent) so existing on-device records are not orphaned.
6. Check the change against `DataIntegrityMonitor` and the backup data-drop guard: would the failure mode be detected, or would it slip through silently?
7. Respect the archiving contract: programs with logged data are archived (skip/pain history feeds future programming); only empty programs are deleted.
8. Smoke check edited files with `swiftc -parse <file>` (syntax-only) when no Xcode is available, and say explicitly that on-device validation by the owner is still required.

## Common traps this prevents

- Rewriting "ugly" stemming and silently orphaning all weight history (this happened — see `transform-failure-archaeology` INC-2).
- Changing a key algorithm without a re-keying migration for records already on the device.
- "Simplifying" archive-vs-delete into one behavior and losing skip/pain history.
- Weakening backup guards or integrity monitoring while refactoring nearby code.
- Treating a data-path change as validated because it parses; only the owner's device run proves persistence behavior.

## Related skills

- `transform-failure-archaeology` — the incidents that created these guard rails.
- `transform-generator-audit` — naming drift from the generator side.

## Provenance

- Last verified: 2026-07-05 against commit `0a68ce9`. Symbol line numbers checked via grep; they will drift — re-verify with `rg -n "func canonicalLookupKey|enum ExerciseWeightStore|func normalizePerformanceLogs|enum DataIntegrityMonitor" Transform/Transform`.
