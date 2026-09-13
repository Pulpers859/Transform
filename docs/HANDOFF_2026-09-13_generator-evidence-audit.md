# Handoff — Generator evidence audit (2026-09-13)

Branch `main`. Everything below was verified by reading source or by measuring CI output; where it
was not, it says so. Read `CLAUDE.md` first — its top section ("Evidence Before Sentence") was
added during this session after two overstatements, and it binds you.

## 1. Where the repo is right now

| Commit | What | CI |
| --- | --- | --- |
| `1170b41` | CLAUDE.md rule + `docs/CLAUDE_GLOBAL_RULE.md` | GREEN (both workflows) |
| `3687172` | VOL-001 + MAINT-001 numbers raised/cut | RED — **reverted** |
| `9a94751` | Revert of `3687172`; tree byte-identical to `1170b41` | not separately run |
| `b8d9cbe` | Re-land of the safe subset + `tools/check_evidence_profile.py` | RED (2 tests) |
| `53163c5` | FAT-001 linear fatigue model + re-derived caps | RED (same 2 tests) |
| HEAD | repairs those 2 tests | **unverified — needs a CI run** |

**The last commit has NOT been through CI.** Check
`https://github.com/Pulpers859/Transform/actions` for the `Generator Tests` run on HEAD before
trusting anything. The `Swift` workflow (real `xcodebuild`) was GREEN on `3687172` and `b8d9cbe`,
so the app compiles; the failures are test expectations, not build breaks.

The two tests that failed, both in `GeneratorBalanceFixTests.swift`, and why each was the TEST's
premise rather than a code defect:
- `testTheFloorDropsWhenRecoveryIsConstrained` probed with 3 sets against a floor of 4. The floor
  moved to 3, so a 3-set probe no longer sits below it. Repaired to probe at 2.
- `testABalancePassWillNotPushADayPastItsFatigueCap` computed its expected fatigue at `sets: 1`
  while `seededDayFitsItsBudgets` projects at `minimumSetFloor`. Under the old STEP model those
  were the same number; under the linear model they are not. Repaired to derive from
  `minimumSetFloor`.

## 2. What landed and is defensible

- **FAT-001 is now linear**: `fatigueContribution` = `fatigueCost * sets`. It used to charge full
  cost at set one, nothing for sets 2-3, double at 4, triple at 5. Measured from the real
  constants: one unchanged full day cost `16 / 29 / 35 / 13` across weeks 1-4 against a Push cap of
  19, and `18 / 30 / 34 / 12` against a Lower cap of 22 — **every session style busted its cap in
  weeks 2 and 3**, the weeks PROG-001 exists to add volume in.
- **Caps re-derived, not scaled**: Push/Pull/Upper 48, Legs/Lower 48, Arms 34, plus
  `maxSessionPriorityFatigue` 18 -> 41, the `+4`/`+1` offsets -> `+9`/`+2`, `maxDailyFatigueThreshold`'s
  bare `13` -> `30` and `?? 18` -> `?? 41`, and five test fatigue caps.
- **HARD LOWER BOUND you must not violate**: `seededDayFitsItsBudgets` decides whether a day may
  take another movement by projecting the WHOLE day at `minimumSetFloor`. In the linear unit an
  anchor alone projects `3 x 3 = 9` and a full day projects 29-30. A cap below that makes a
  full-size day unbuildable, days collapse to 4-5 movements, and the validator then hard-fails the
  5-8 rule. `tools/check_evidence_profile.py` fails the build on this.
- **MAINT-001 floor 4.0 -> 3.0** (tight 3.0 -> 2.0). It was unreachable by construction: `canAddSet`
  caps a non-prime movement at its role default, 3 for an accessory/secondary/core movement in
  week 1, so a group covered by one such movement could never reach 4. Bickel 2011 independently
  puts the measured retention dose at ~3 weekly sets.
- **`weeklyDirectSetTarget` clamps to its band.** Unclamped it returned 12.5 against a documented
  8-12 band.
- **Version string `v1_8` -> `v1_9`.** It is printed into the AI prompt via `blueprintContext`, so
  the app was misreporting its own contract to the model.
- **`tools/check_evidence_profile.py` + `test_check_evidence_profile.py` + a CI step.**
  `EvidenceProfile.md` is the programming contract and nothing compiles it. The checker fails the
  build on doc/code drift, a band needing more slots than VAR-001 allows, the three
  `maintenanceCeiling` declarations drifting apart, a floor raised above what one movement can
  deliver, stale owner-facing prose, a cap below the full-day projection, and a silent revert of
  the linear model. Eight pinned attacks; all eight caught.

## 3. THE BIND — read before touching volume

Three things cannot all hold. This is arithmetic, measured, not opinion:

1. non-priority muscles get only ~3-6 weekly sets,
2. the week has 5 training days each carrying at least 5 exercises (`+ParsingValidation.swift`
   ~1300 — under 5 is a hard failure the procedural fallback also consumes),
3. every prescribed movement gets >= 2 sets.

5 days x 5 exercises is ~25 slots across 10 major muscle groups, so small muscles hold 4-5 slots.
Give such a muscle a 5-set budget and you get five movements at one set each.

**Measured proof**: cutting the maintenance ceiling 10 -> 6 (tight 8 -> 5) took single-set movements
from **1 of 30 (3%) to 9 of 30 (31%)** on the regression fixture. One day came out as five
movements at one set each. That is commit `3687172`, reverted in `9a94751`. The weekly VOLUME was
correct; the DISTRIBUTION was junk.

**Root cause, verified**: `maintenanceSlotBudgetsAreFeasible` (`+ExerciseSelection.swift` ~1573)
counts **distinct exercise NAMES** (`distinctNames` Set, ~1624-1633) while the budget is spent per
**EXPOSURE**. Biceps had 2 distinct names — exactly at the gate's limit — but 4 exposures. The gate
cannot see this shape. `maintenanceSlots` (~2936) counts real exposures; the two functions disagree
about what a "slot" is, and the one guarding the budget is the one that undercounts.

**Do not naively fix this by counting exposures.** It has been tried and reverted. See
`ResidueMuscleDoseTests.swift` ~218-250, which records three failed attempts verbatim, including
commit `a33fde4` (reverted `82ae1f9`). Recorded failure mode: the gate runs per candidate while
days are built in order, so a weekly budget enforced greedily is spent by the early days — day 6
was refused the work its own plan called for and delivered zero direct sets to its stated focus.
That file also warns, correctly, that **a green CI run is not evidence here** — the fixture-snapshot
artifact is what distinguishes them. The untried remedy it names is distributing exposures across
days at menu-construction time rather than checking a running total.

## 4. Parked, with reasons — do not re-derive and re-break

- **VOL-001 raise High 8-12 -> 12-16, Medium 5-8 -> 8-12.** Baz-Valle 2022 (J Hum Kinet 81:199-210,
  verified against the abstract) recommends 12-20 weekly sets for trained adults; ACSM 2026's
  `>=10` is the threshold where hypertrophy is ENHANCED, a floor not a target. Today's High midpoint
  of 10 equals the maintenance CEILING, so a specialized muscle and an ignored one can receive the
  same volume. **Blocked on the bind in section 3** — raising priority volume first moves sets onto
  movements that are already too thinly dosed. Upper bounds are pinned by this app's own
  arithmetic, not the literature: slots are `max(tierDefault, ceil(setTarget / 4))` and
  `maximumUsefulVariationCount` caps distinct exercises at 4/3/2, so 16/12/8 are the largest
  fundable targets.
- **MAINT-001 ceiling 10 -> 6.** Same block. Note the tradeoff is real and not a free win: Bickel's
  one-THIRD dose (~9 sets/wk) produced ADDITIONAL hypertrophy in young adults, so cutting
  maintenance trades growth in non-priority muscles for growth in priority ones. That is the right
  trade for a specialization app, but it IS a trade.

## 5. Known defects NOT fixed

- **Trim order cuts the main lift first.** `volumeReductionPriority`
  (`+ExerciseSelection.swift` ~834-876) trims the highest scorer; a non-focus anchor scores ~42
  against ~31 for an accessory, so a Romanian deadlift is cut before calf raises when a day is over
  cap. A focus-direct anchor gets `-10` and is protected, so this bites non-focus compounds.
  Pre-existing; the linear model makes it bite LESS (week-3 Push was 84% over cap, now 27%).
  The anchor is where week-to-week progression is tracked, so this is the wrong order.
- **BASE-001's "2 days/week" is enforced as 2 SLOTS, not 2 days.**
  `enforceMaintenanceExposureBreadth` (`+ExerciseSelection.swift` ~2956) counts slots and steers the
  second onto a fresh day as a PREFERENCE (`deprioritizedDays`); the comment at ~2966-2976 states
  that counting days would not terminate. Both slots can legally land on one day. This is the only
  rule in `EvidenceProfile.md` rated High confidence.
- **ORD-001 names four ordering bands; the code has three.** `sessionOrderingBand`
  (`+ExerciseSelection.swift` ~63-72) merges `.secondary` and `.accessory` into band 1, so a
  focus-area isolation movement can sort ahead of a secondary compound.
- **STR-001's "2-3 sets" and ">=80% 1RM" are not implemented.** Anchors get 4/5/5/3 sets by week and
  nothing in the generator prescribes load or %1RM. Early-session placement and heavier anchor rep
  ranges ARE implemented.
- **ECC-001 (eccentric overload) has no implementing code at all.** Documented and inert. The rule
  is permissive, so nothing is violated.
- **`max(1, fatigueContribution / 2)`** (`+PriorityIntent.swift` ~515) credits secondary areas by
  integer division. Under the linear model the `max(1, ...)` floor stops being load-bearing for most
  rows. Not wrong, but its shape changed and it was not re-tuned.

## 6. Open decisions nobody has made

A science lane was briefed to DECIDE these and **never returned** — its answers do not exist, so do
not assume any of them:
1. Which of the three constraints in section 3 gives way.
2. Whether non-priority muscles should be held at retention at all, given Bickel's higher dose grew
   muscle and the sets are being performed anyway.
3. Whether priority volume goes to 12-16, and whether TOTAL weekly volume needs its own ceiling.
4. Whether 5 training days is the right default, or 4 fuller days beats 5 thinner ones.
5. The correct trim order when a session is over cap.
6. Whether the mandatory week-4 deload should exist. Coleman 2024 (PeerJ 12:e16777) found no
   benefit and a strength decrement; Pancar 2026 found nothing either way.

**The owner is explicitly not a training expert and does not want to adjudicate these.** Get them
decided by someone who can cite sources, then verify the citations yourself before acting.

## 7. How to verify anything here

There is no Swift toolchain in the cloud container. CI is the compiler.

- `python3 tools/check_evidence_profile.py` and `python3 tools/test_check_evidence_profile.py` run
  locally and are fast.
- The `Generator Tests` workflow uploads three artifacts: `generator-test-log` (the failing
  assertions), `generator-fixture-snapshot` (the ALLOCATED MENU — `Name#sets#target` per day), and
  `user-journey-report`.
- **Use the fixture snapshot as the real judgement.** Diff it against the previous run and count
  movements at one set. A passing test suite did not catch the 3% -> 31% fragmentation; diffing the
  snapshot did. Never re-baseline that fixture without first deciding the new allocation is BETTER.
- Owner validation is Xcode + a physical iPhone. Never suggest the simulator.

## 8. Verified citations used in this work

Each was checked against the actual abstract, not quoted from memory:
- ACSM 2026 position stand — Currier et al., Med Sci Sports Exerc 58(4):851-872, PMID 41843416.
  ">=10 sets/wk" for hypertrophy; "2-3 sets", ">=80% 1RM", ">=2 sessions/wk" for strength.
- Baz-Valle 2022, J Hum Kinet 81:199-210, PMID 35291645. 12-20 weekly sets; quads p=0.19,
  biceps p=0.59, triceps p=0.01.
- Bickel 2011, Med Sci Sports Exerc 43(7):1177-87, PMID 21131862. One-ninth dose preserved
  hypertrophy in the young over 32 weeks; one-third dose ADDED hypertrophy.
- Schoenfeld 2019, Med Sci Sports Exerc 51(1):94-103, PMID 30153194. 5 sets x 7 exercises x 3 d/wk
  (35 sets/session) was the highest-hypertrophy arm in trained men.
- Robinson 2024, Sports Med 54(9):2209-31, PMID 38970765. Hypertrophy improves nearer failure;
  strength CIs contain null. Authors call it exploratory with modest fit.
- Singer 2024, Front Sports Act Living 6:1429789, PMID 39205815. Benefit to rest >60s; no
  appreciable difference beyond 90s.
- Refalo 2023, Sports Med Open 9(1):10, PMID 36752989. Velocity loss -8% / -13% / -25% at
  3-RIR / 1-RIR / failure — a LINEAR relationship, and the only place "linear" attaches to measured
  fatigue.

Two claims that did NOT survive checking, recorded so they are not repeated: a lane asserted
maintenance volume above ~3 sets "buys retention 3 sets already bought" (Bickel says the higher dose
grew MORE), and a lane cited Knowles 2018 for a hypertrophy claim it does not make (it is about
acute performance).
