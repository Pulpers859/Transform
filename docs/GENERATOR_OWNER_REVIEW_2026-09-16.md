# Owner generation review and lower-focus correction

## Evidence boundary

Reviewed the owner's September 16 `1-text.txt` attachment: final JSON, locked menu,
blueprint and request log. The attachment does not identify its build commit.
These are observations of that generation, not proof that current source still
produces every issue. Raw personal analysis/history is not copied into the repo.

## Workout observations (JSON parsed and counted)

| Training day | Exercise slots | Sets |
| --- | ---: | ---: |
| 1 Upper | 6 | 17 |
| 2 Lower | 6 | 19 |
| 4 Push | 6 | 16 |
| 5 Pull | 6 | 16 |
| 6 Arms/Delts | 6 | 13 |

- Fly is present: day 1 Cable Fly, three sets, with low-to-high coaching.
  This resolves the absence question for this generation, not the catalog-asymmetry
  follow-up. Weekly chest work is fifteen pressing sets plus three fly sets.
- Push starts with four presses totaling twelve sets. This is a candidate for a
  complete-plan economy review, not proof that twelve sets cannot produce growth.
- Pull contains six vertical-pull sets and two rowing sets. The warning arithmetic
  is correct; the warning's claim about what a token row cannot accomplish is a
  coaching heuristic, not a measured outcome for this owner.
- Arms contains V-Bar and Rope pressdowns, two sets each. These match the locked
  menu, as do all exercise names/order/sets above. Replay against current planning
  is needed before attributing them to a still-active defect.
- Upper starts with lateral raises before its machine press; Lower starts with
  knee raises before leg press. These are concrete cases for the owner's newly
  chosen compound-first ordering policy, not claims that this order is unsafe.
- Barbell progression context says 105 to 110 lb, consistent with the recent
  five-pound-step correction. This does not verify every exercise's UI.
- Recovery text explicitly retains standing-context caution without fresh sleep
  logs. Keep this as a positive case when reconciling the recovery contract.

The two September 16 AI requests started four seconds apart and both succeeded.
Current `WorkoutGeneratorService.parallelCandidates` requests two candidates;
`candidateCacheStagger` is four seconds and the task group submits the same body
twice before scoring. Attribution of this historical pair to that path is
reasoned, not reproduced, because no build/parent-generation identifier is present.
There is no evidence here of an accidental double tap. No paid calls were made
for this review.

## Bounded lower-focus correction

Only the lower-focus classification below is changed in this batch. None of the
workout-selection observations above is claimed fixed by this change.

Earliest cause: `focusStimulusKind` expands both the query and metadata through
`stimulusAreaAliases`. Distinct lower muscles then intersect through shared
`Posterior Chain` or `Quads/Glutes` labels. An isolated Windows executable using
the shipping classifier and alias function with controlled metadata reproduced
four wrong prime results: thrust to hamstrings, curl to glutes, extension to
glutes, and Romanian-deadlift metadata to glutes.

Alternatives considered:

- A thrust-only exception leaves the other reproduced false credits.
- A global change also affects unrelated upper-body behavior and repeats the
  broad scope of the rejected earlier experiment.
- Selected: only named hamstring/glute/quad focus uses query aliases against raw
  declared primary/secondary metadata, matching the direction of `directSetCredit`.
  Existing upper-body switch precedence and shared aliases are unchanged.

Residual scope: the rest of the classifier still uses its existing symmetric
aliases. This is not a universal repair of arbitrary muscle-label relationships.
The remaining regions require their own reproducible counterexamples and complete
plan checks before changing them. Broad composite metadata such as Trap Bar
Deadlift's primary Posterior Chain intentionally retains the current contract;
the catalog regression table includes this case rather than silently redesigning it.

The second review requested changes. Its substring-collision concern was addressed
by routing this branch with whole-phrase matching, not `contains("quad")`. Its
scope/metadata concerns are explicitly bounded above; real catalog integration
and complete plans still require CI. An independent source review checked the
catalog expectations; mixed upper/lower query precedence controls were added.
Neither review nor the local probe is represented as full-suite approval.

The same isolated executable then returned secondary/none/none/secondary.
`FocusCreditBoundaryTests` converts the strict known failure to a normal assertion
and adds catalog and query-variant regression coverage. Explicit composite catalog
metadata retains its existing meaning; no exercise names, history keys or
persistence paths change. No mandatory hinge is introduced.

Validation before remote execution: Windows Swift toolchain smoke passed; both
edited Swift files parsed; isolated four-case before/after probe executed. These
do not prove full-plan quality. Full macOS tests, app build and complete baseline
comparison must be checked after push, including any changed lower-body exercise
choices, dose, crowding and warnings. Device behavior remains separate.

## Follow-up acceptance

### First remote execution: 490e09b

App run `35087806541` logged BUILD SUCCEEDED. Generator run `35087806537`
executed 721 tests and failed the live-crowding test's three setup assertions:
the new Lower day had six slots before relocation, not seven, so there was no
eligible placement or crowded transition. This is a red suite, not approval.
Complete comparison against d319e9a: twelve week objects unchanged, eight changed
(the shoulder and lumbar personas). The independent two-set checker passed all
twenty weeks. Priority direct-set totals remained unchanged in those eight weeks.

Changed workout tradeoffs: the shoulder persona retains curls and glute/quad
coverage but loses its RDL and no longer needs core relocation. The lumbar
persona redistributes its twelve hamstring sets toward two RDL appearances and
smaller curl doses. No new validator findings appeared; the existing deload row
warning remains. Neither validator output nor modeled budgets proves individual
tolerability of that redistribution.

Follow-on regression work separates live non-crowded planning from a reconstructed
historical crowded complete-menu fixture. The latter reverses the recorded core
relocation in the d319e9a synthetic week, uses an explicit integer-seven quad budget
to preserve budget pressure, and explicit empty lock/history test inputs. It must
earn exact allocation/admission before the existing relocation checks run. It is
not an exact captured historical blueprint/context object. Execution pending.

Replay this owner's five-day constrained-recovery shape without copying private
analysis text into fixtures. Record pressdown/core finalization decisions, chest
sets per session and six-to-two pull balance. Do not require an extra fly, a hinge,
or equal pulling sets just to make a test pass. Preserve the chosen budgets and
compare whole weeks before accepting a substitution.
