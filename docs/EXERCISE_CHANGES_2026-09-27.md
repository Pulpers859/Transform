# Pain review and real exercise replacements

## Scope and design

- Pain skips remain historical facts. Explicit review changes future exclusion, not stored logs. No timer declares recovery. Still painful/not sure remain excluded; resolved allows selection. Avoid-until-changed can only be released in Exercise Preferences, not incidentally by generation review. Profile/analysis injury guidance remains separate.
- Week 1, next week and start-over require explicit temporary-pain review before starting a generation task. Cancel does not generate. Exercise Preferences is also accessible without spending API credits.
- Options > Replace exercise offers catalog-known alternatives with the same primary regions, movement pattern, role/class, and no increased modeled shoulder/systemic/fatigue score. These are conservative product heuristics, not clinical clearance or proof of biomechanical equivalence.
- A replacement requires the owner to confirm equipment availability. No duplicate key may occur in a day. Recorded original sets/names/loads are never renamed; the new card gets remaining sets and its own load history. Original cards become visible replacement-history segments, not extra active slots. Finished historical sessions are not rewritten.
- Just today leaves future preferences unchanged. Prefer in future is an editable selection preference, not a guarantee or an unconditional swap. Pain/equipment filters and normal complete-plan allocation still apply. Original program JSON remains the planned-week reference.
- Native sheet: choose replacement, choose scope, confirm available equipment, then commit. Cancel is nonmutating. Pain/preferences form stages edits until Save. Empty/no-compatible/error states are explicit. Use native controls for Dynamic Type and accessibility; no new design system.

## Research and incident constraints

The exercise-evidence reviewer used [ACSM's 2026 guidance](https://acsm.org/resistance-training-guidelines-update-2026/) for equipment flexibility in healthy adults and [AAOS shoulder guidance](https://www.orthoinfo.org/recovery/rotator-cuff-and-shoulder-conditioning-program/) for not ignoring exercise pain. Neither establishes that a proposed replacement is safe for this person's symptoms.

Interface references: Apple [sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [pickers](https://developer.apple.com/design/human-interface-guidelines/pickers), and [undo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo). Borrowed focused modal tasks and explicit save/cancel; rejected chained alerts for multi-field decisions.

INC-2/INC-6 constrain implementation: do not re-key performance history or erase archived skip records. Catalog aliases expand restriction matching only. SwiftData additions are default-empty strings; backup additions are optional. The actual backup Codable shape is tested outside the UI file.

## Internal demo/regression scenarios

Tests exercise real policy and in-memory SwiftData transactions, not screenshots:

1. Temporary pain -> not sure stays excluded -> explicit resolved releases -> new report excludes again.
2. Persistent avoid plus new temporary pain: resolving the temporary report does not remove persistent avoid.
3. Empty review choice cannot authorize generation; legacy pain requires review.
4. Dumbbell lateral raise 3 planned sets, 1 logged -> unchanged dumbbell log plus 2 machine sets. Separate 20 lb dumbbell / 45 lb machine histories remain separate.
5. No logged sets -> transfer all 3; all 3 completed -> refuse extra work.
6. Shoulder press/rear-delt fly are not lateral-raise replacements; compatible curl/press examples are tested.
7. Duplicate, cycle, already-logged destination, archived/past session and pain-excluded candidate are refused.
8. Final equipment skip -> replacement -> day reopens; original equipment reason remains available to recurrence aggregation.
9. Reopen a replaced day -> complete visible work -> historical segment cannot strand completion.
10. Prefer machine after painful dumbbell -> preference survives source exclusion; excluded machine still cannot win.
11. Save failure restores original card/order/preferences and inserts no durable replacement.
12. Old backup decodes with no invented resolution; new fields survive encode/decode.

Windows syntax checks cannot prove SwiftData migration, actual sheet presentation, or device persistence. macOS CI must execute these tests and compile the app; physical iPhone checks remain required. No paid generation is needed for the interaction checks.

## Device checklist

1. Options > Replace on an unstarted lateral raise: choose machine, confirm available, leave future preference off. Cancel once (nothing changes), then replace. Confirm remaining sets and machine's own history.
2. On a separate day, log one of three original sets, then replace. Confirm two new sets and the unchanged original in Replacement history; reopen the app and recheck.
3. Record a pain skip. Open Exercise Preferences: not sure retains exclusion; resolved retains the historical skip but releases future exclusion. Restore the truthful status after testing.
4. Open generation with an unresolved temporary flag: review appears first. Cancel without spending generation credits.
5. Save a future replacement preference, verify it in Exercise Preferences, then clear it and Save if it was only a test.
6. Complete and reopen a swapped day; finishing all active cards must finish the day. Check large text for clipped controls.

## Known boundaries

- New replacements of already-rated or past sessions are refused. This is not a history-editing feature.
- A replacement's identical rep/rest/tempo prescription is a conservative slot-preserving default, not individually optimized coaching.
- Regional pain in analysis can still influence selection after one exercise flag is resolved; resolving an exercise flag does not declare all related movements safe.
- General recurring-skip prose still has broader historical scope than the equipment preference window; this change only removes explicitly resolved pain from it.
