# Barbell increments, coaching disclosure, and chest selection

## Implemented scope

- Owner clarified bilateral barbell increases must be 5 lb total. `incrementLbs`
  now distinguishes explicit barbell/BB, EZ/trap/Smith bars and the canonical
  Back/Front Squat names from cable stacks and one-ended landmine/T-bar equipment.
  Existing singular disambiguation aliases are resolved for calculation only.
  Names, history keys, stored weights and migrations are not changed.
- Up/down and cross-prescription translation share the increment policy.
  A reduction cannot increase a historical load below the new minimum step.
  The prompt now acknowledges when no smaller step is available, matching the
  card's existing easier-variation fallback. These are suggested total loads in
  pounds, not per-side plate prescriptions or a guarantee of a particular bar's
  empty weight. Unknown custom names still use the existing 2.5 lb default.
- Coaching/lightbulb prose is moved into the existing initially closed Details
  section; live weight recommendations and logging warnings remain visible.
  Filtered full coaching remains available, not the stale raw progression prose.

## Review: chest flies

Verified against `exerciseCatalog(for:)` in `+FallbackCore`: Push's base list
contains chest presses but no fly, whereas Upper includes Cable Fly.
`orderedExerciseCatalog` sorts that style list; `enforceFocusExerciseCoverage`
injects accessories only while muscle-level coverage is deficient. Presses can
satisfy that coverage without a fly. The broader metadata/priority catalogs do
contain cable/dumbbell flies and Pec Deck. There is no reviewed press/fly diversity
requirement. Historical intent and the cause of the owner's exact current plan
have not been established; his latest full-week snapshot is needed.

This is a candidate-pool limitation to investigate, not proof of inadequate chest
growth. Bench press training increased pectoralis major size in a controlled
10-week study: https://doi.org/10.1016/j.jbmt.2024.07.054. The acute bench/fly
comparison https://jssm.org/volume19/iss4/cap/jssm-19-645.pdf measured activation,
not longitudinal hypertrophy or chest width. Neither supports promising a unique
"width" benefit from flies.

### Added follow-up (not implemented)

Evaluate fly-for-redundant-press alternatives in complete plans, not extra
appearances appended after budgeting. Obtain the owner's full-week snapshot;
check equipment, symptoms, retained exercises, priorities, direct/indirect volume,
continuity and the relevant day ceiling. Include a targeted Push/chest profile
and compare all baseline weeks before adopting any candidate-pool change.
No exercise-selection, set-budget, six-exercise ceiling, or paid-generation policy
is changed in this batch.

## Evidence and limits

- `BarbellIncrementTests` adds equipment-boundary, up/down, legacy-load and
  translation coverage; old Barbell Row expectations deliberately change.
- Local Windows Swift smoke and per-edited-file syntax checks passed. An executed
  Foundation-only probe of extracted shipping increment/translation functions
  produced 100 -> 105 for incline barbell, preserved the cable 70 -> 72.5 step,
  and produced an 85 lb translated load on the test prescription. This is not
  execution of the full app or complete XCTest suite.
- Independent read-only review caught missed Smith bars (included) and the
  prompt's equal-load-as-reduction wording (corrected). Broader legacy catalog
  aliases that never pass through the canonical generator name resolver remain
  a bounded custom/legacy-name uncertainty, not a verified current-device defect.
- Full CI execution and physical-iPhone disclosure/history behavior still need
  verification at this checkpoint. Do not read this document as device approval.

### Second-review reconciliation

Claude's completed packet review returned REQUEST CHANGES, not approval.
The missing prompt-wording regression was addressed by extracting the production
cue branch into `reductionPromptCue` and asserting both no-lower-step and actual
reduction text. Its concern about unseen alias code was checked against the real
`ExerciseNameDisambiguation` source; the new increment tests exercise that resolver
transitively and fail if those aliases stop producing the required increment.
Its proposed broad matching for arbitrary qualified squat names was not adopted:
the reviewed current catalog contains canonical Back/Front Squat, and broad name
matching can misclassify custom cable/machine variants. Unknown names are an
explicit limitation, not a claim of universal equipment inference. Future
equipment configuration would be preferable to an expanding guess list.
The cited papers were opened/read by the main agent; no medical or special-width
claim was inferred from acute activation. Deleted UI helper references were
searched across the source/tests; full build and owner-device checks remain
distinct from syntax proof. The review did not include the later roadmap link
or this reconciliation paragraph.
