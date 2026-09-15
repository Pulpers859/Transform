# Generator planner refactor: evidence and acceptance

## Active roadmap and audit checkpoints (2026-09-13)

### Bounded candidate search and reservation outcomes (2026-09-15)

The optional pressdown trial now has a deterministic, bounded catalog search. It
uses captured history, style and focus, tries later redundant slots first, and returns
the first qualified fixed-dose proposal. No live caller adopts proposals in this
checkpoint. Exhausting the finite candidate list, reaching the trial budget, and
invalid context are distinct outcomes; none proves universal plan infeasibility.

The allocator also returns the chosen role-floor reservation outcome through an
optional observer and the planner baseline: admitted, infeasible, search-limited,
or deload policy. Admission is not evidence that every final dose target was met.
Default appearance search remains 512 states. Nonpositive state budgets now report
search exhaustion rather than falsely claiming candidate-pool infeasibility.

Regression coverage includes observer parity, chosen-outcome publication, protected
conflicts, deload, deterministic/history-filtered candidate order, exact search-budget
boundaries, and full-week search reporting. Windows smoke and syntax checks passed;
a standalone execution also checked the framework-free solver's budget boundaries.
Full generator and app CI evidence is pending. Stage 3 remains open.

Independent review identified and prompted the zero-budget correction and additional
non-vacuous/boundary assertions. Before live adoption, final ordering, fresh allocation
receipts, chosen-plan diagnostics and strict requalification against the original
baseline must be proved. A rejected first proposal does not exhaust later alternatives.
The revised Claude review approved with follow-ups. The proposal-only search deliberately
does not require admission, so synthetic/diagnostic trials remain possible; live optional
adoption must require an admitted original and final allocation. The outcome enum has
the three cases used by the exhaustive switch; CI must still type-check the integration.
Windows commands were `swift-sanity-check` and `swiftc -parse` per changed Swift file;
the executed standalone driver is `.agents/appearance-boundary-main.swift` (ignored).

### Combined pressdown-improvement trial (2026-09-15; code `a257920`)

`evaluatePressdownSubstitutionTrial` combines the planner-context eligibility checks,
complete-plan dose comparison, then a narrow objective: fewer excess exact Rope/Cable/
V-Bar pressdown appearances in one day, with no day's excess increasing. Excess is
`max(0, count - 1)`, so changing one handle for another or removing a lone pressdown
does not establish improvement. Three appearances reduced to two is partial improvement,
not resolution. The result reports the day and before/after excess, or the first refusal.

This is an optional quality trial for loading weeks only, not a safety replacement
fallback or a claim of universally better programming. It does not select candidates,
mutate menus, adopt a replacement, or alter names/history keys. INC-9 constrains this
work: do not reintroduce an early greedy family rejection. Exact catalog identity is
intentional; aliases/unilateral movements are not silently classified as equivalent.

The nine complete-week trials now exercise this combined decision. Synthetic tests
isolate objective scope, non-improvements, eligibility and fixed-dose role-floor
refusals, partial improvement, and unsupported weeks. Windows smoke/syntax checks
passed; executable evidence is recorded below. The original product findings and
Stage 3 remain open until actual decision/adoption behavior is proved.

Independent source review found no blocker. Claude approved with follow-ups about
shape safety, family-list ownership and future adoption claims. The existing preflight
checks equal day/slot counts before dose/objective access; the combined test now drives
empty, shortened and extra-day candidates. Production objective membership has one
owner; the repeated set in the journey test is an independent fixture selector, not
another production classifier. INC-2/INC-9 references were checked. Neither source
review replaces executable CI or proves a user-visible workout improvement.

Verified code-checkpoint evidence:

- Generator run `35022266350` passed all 681 tests, with both new test methods present
  in the execution log. iOS run `35022266326` logged `BUILD SUCCEEDED`.
- Nine full-week trials preserve dose; six qualify with excess `1 -> 0` on zero-based
  day index 6, while three are rejected by catalog eligibility. These are independent
  alternative trials, not six changes adopted into a program.
- All 20 complete exported week objects and the historical fixture snapshot exactly
  match `4a84efc`. Artifacts: `.agents/substitution-objective-a257920/` (ignored).
- No live AI or physical-iPhone validation was performed. Actual generated workout
  selection is unchanged; this does not resolve the shipped duplicate.

Next bounded step: candidate enumeration and deterministic selection using the combined
decision, including a tested unchanged-baseline result when no candidate qualifies.
Prove candidate search and any later live integration separately; do not bypass history
provenance or reinterpret optional-quality refusal as a safety-replacement fallback.

### Complete-candidate selection checks (2026-09-15; code `4a84efc`)

The non-adopting planner-context preflight now checks complete-day prime counts and
whole-week anatomical variation budgets using existing policy helpers. It refuses
inherited violations too: unchanged warning totals do not establish that a complete
candidate fits. This is deliberately conservative and may reject a neutral local
improvement until the separate baseline problem is resolved.

The snapshot carries the builder's actual optional focus intents. Preference scoring
is compared only where the builder used it, with focus rank preceding score. A new
relative equipment preference refuses switching from a non-skipped exercise to one
marked equipment-skipped; it does not ban skipped exercises globally or reject moving
between two skipped options. This is conservative substitution policy, not a rewrite
of the existing catalog filter or its accessory rotation.

Regression cases cover repeated old identities elsewhere in the week, replacement at
the prime cap, inherited excess after a non-prime swap, relative equipment history,
and recovery/focus-dependent scoring. Full-week trials also verify captured focus
intent. Windows smoke/syntax checks passed; code-checkpoint evidence is recorded below.
No production caller adopts substitutions. An explicit improvement objective, actual
history provenance at live adoption, broader selection review and end-to-end adoption
proof remain open. Stage 3 and the product-quality backlog are not complete.

Claude's packet review requested changes: verify no live pain/equipment replacement
caller can silently keep unsuitable work after an unrelated limit rejection, cover
inherited weekly variation excess, and clarify rank/count claims. Caller search found
only tests plus the internal overload delegation. Added inherited-week coverage and
planned-context focus-downgrade coverage; removed a redundant rank rejection already
owned by structural preflight and renamed the complete-day test. Future safety-driven
replacement orchestration must handle a rejected candidate without retaining painful
work. The review was a request for changes, not an unconditional approval.
An independent agent reviewed the final revisions and found no remaining blocking
issue by inspection; its review did not execute tests.

Verified code-checkpoint evidence:

- Generator run `35020198425` passed all 679 tests; the log confirms execution of all
  five new selection/whole-candidate cases.
- iOS run `35020198428` passed with `BUILD SUCCEEDED` in its log.
- All 20 complete exported week objects and the historical snapshot exactly match
  `0f66781`. Artifacts: `.agents/substitution-selection-4a84efc/` (ignored).
- Nine trials preserve dose: six pass the expanded preflight, three fail the style
  catalog check. These results still do not authorize automatic adoption.
- No live AI or physical-iPhone test was run.

Next: define and test a concrete improvement objective, then combine it with the dose
and eligibility gates in a bounded decision path. Keep safety-driven replacement
failure handling explicit and separate from optional quality improvements. Do not
claim crowding, rowing balance or fractional targets resolved by these checks.

### Planner-bound substitution context (2026-09-15; code `0f66781`)

The menu builder now returns an internal baseline containing its allocated menus,
blueprint/week, actual ordering locks, surviving retained identities and supplied
exercise history. The existing menu API delegates to that builder without selecting
or adopting any substitutions. Full-week trial preflights use this context instead
of reconstructed zero locks and empty history. A separate real-builder pain-history
test checks that captured pain exclusions reach the preflight.

Independent source audit identified that ordering locks and retained identities are
not interchangeable: focus days can retain exercises with zero prefix lock, and
earlier repair passes can replace a locked position. The snapshot records surviving
retained identities separately; substitution refusal for those identities is a new,
conservative, non-adopting guard, not a claim that upstream repairs preserve them all.
Tests cover moved retained identities and real-builder unlocked focus retention.

This connects continuity/pain context, not full selection-policy acceptance. Equipment
preferences, broader injury/selection review, prime-slot/variation checks, improvement
objective and adoption remain open. Stage 3 and the outstanding quality findings are
not complete. Windows smoke and per-file syntax checks passed. No device or live-AI
result is claimed.
The Claude packet audit approved with follow-ups. Its missing-initializer question
was resolved by inspecting the existing `SubstitutionPainExclusions(history:)`;
CI subsequently compiled and executed it. The new context-returning builder requires an explicit
history argument (including explicit nil for no-history fixtures). The legacy menu
API retains its existing optional default. Any future live adoption path must verify
that actual history was supplied; this snapshot alone does not prove that provenance.

Verified code-checkpoint evidence:
- Generator run `35017061354` passed all 674 tests, including the new retained-identity
  and real-builder pain-history tests and the complete-week trials.
- iOS run `35017061363` passed with `BUILD SUCCEEDED` in the log.
- All 20 complete exported week objects and the historical fixture snapshot are
  identical to `e328643`. No observed workout change is being claimed as an improvement.
- Nine trials still preserve dose; six pass structural preflight and three fail the
  exact style-catalog check. Weeks 2/3 now carry actual nonzero ordering locks.
- Local artifacts: `.agents/substitution-context-0f66781/` (ignored). Full selection
  eligibility and adoption remain untested; the report summary uses that broader sense.

Next bounded step: evaluate remaining selection preferences and whole-week variation/
prime-slot constraints against this captured baseline, then define an explicit
improvement criterion. Do not enable automatic replacements from preflight alone.

Starting checkpoint: `b187f51`. This is a staged plan, not a claim that every
finding below is a code defect or that the architectural work is complete.

1. Pin each unresolved finding to an input and actual output; add a failing
   behavioral test before changing its owner. Keep heuristic policy questions separate.
2. Share per-appearance credit, coverage, maintenance membership and dose-floor
   accounting between floor reservation and optional funding. Preserve policy first.
3. Reconcile remaining limit ownership and explicit infeasible/search-limit results.
   Compare bounded replacement/relocation with rebuilding the candidate menu. Do not
   mistake an exhausted search for proof that the user's requirements are impossible.
4. Resolve the remaining workout-quality findings individually at their earliest cause.
5. Review volume bands and whole-set rounding separately, with before/after evidence
   and an explicit owner decision for changed product tradeoffs.
6. Retire superseded repair paths only after tracing callers and replaying original cases.
7. Verify the integrated app on the owner's physical iPhone, including saved workouts
   and exercise-history continuity. No headless result proves these runtime behaviors.

### Acceptance backlog

The [September 14 device audit](GENERATOR_DEVICE_AUDIT_2026-09-14.md) adds an actual
rope/V-bar pressdown family gap, a shoulder-adaptation test gap, and two policy/doc
reconciliation items (recovery fallback and secondary/accessory ordering). It confirms
the existing crowding and rowing-dose findings; it does not add a fractional-target
case. Keep the raw personal device export local rather than committing it as a fixture.

Inputs are the five personas in `UserJourneySimulationTests` and the historical
`five-maintenance-errors.json` fixture. The downloaded `b187f51` JSON and fixture
snapshot were inspected locally; they live in ignored evidence storage, not in this doc.
The rows are reproducible observations to investigate, not endorsements of warning wording.

| Finding | Pinned observation at starting checkpoint | Acceptance work still required |
| --- | --- | --- |
| Glute shortfall | Shoulder-beginner loading weeks report 2 sets vs floor 3, one movement | Trace the refusing budget before adding a movement; test actual credited sets |
| Crowded lower session | Same persona reports crowded days 2, 9 and 16 | Review actual selection and warning premise; preserve useful dose and coverage |
| Redundant priority work | Lumbar persona week 1 reports four prime hamstring movements against two planned slots on day 4 | Trace selection/metadata and test the agreed redundancy rule |
| Rowing imbalance | Lumbar persona deload reports 7 vertical vs 3 rowing sets; historical snapshot has 6 vs 2 | Independently count movement-pattern doses and resolve without losing back coverage |
| Fractional targets | Export retains raw 7.5 targets with 7 delivered in affected cases | Decide rounding and reconcile all limits during policy work, not this extraction |
| Unresolved candidate pool | `JointAppearancePlanningTests.testOverfullEarlyArmsDayCannotSpendLateFocusReservation` pins conflict with every slot locked | Replace legacy allocation only with an explicit, tested outcome contract |

### Rejected pressdown early-gate experiment (2026-09-15)

`b97254f` recognized Rope/Cable/V-Bar Pressdown as one same-session handle family.
Its classifier passed canonical/alias, identity, and unilateral checks, but applying
it to the early greedy selection gate was unsafe. The implementation and its new
tests were withdrawn; the prior production/test tree is restored. The duplicate
finding remains OPEN. No snapshot or validator expectation was weakened.

Generator run `34960426158` executed 660 tests and failed five test cases (14
assertion failures). App run `34960426125` built successfully. Raw exports show:

- Historical fixture: day 6 lost all lateral-delt focus work; triceps spread over
  four distinct movements at two sets each. This was not merely snapshot drift.
- Lumbar persona loading weeks: three press appearances per week fell below their
  three-set role floor. Reservation reported infeasible Chest maintenance/residue
  and used the legacy allocator. Weekly sets fell by 3, 2, and 2 respectively.
- All 20 synthetic weeks retained their exported priority summaries and appearance
  counts, and none had one-set prescriptions. Those checks alone MISSED the defects.

Source trace: early candidate rejection advances through the catalog before
whole-week feasibility. Short-menu rescue may relax dose gates; protected anchors
can then make reservation infeasible. Final artifacts do not establish exactly
which intermediate pass inserted each replacement; add a targeted trace before
claiming that precise causal chain.

Next: retain the narrow classifier concept, but evaluate a bounded, fully allocated
alternative against the known baseline before materializing the locked menu. Require
preserved focus-day work, priority delivery, role floors, coverage and all budgets;
reject unsafe alternatives explicitly. Do not repeat unconditional early gating.
Row dose and crowding should use the same complete-plan acceptance boundary;
fractional rounding remains a separate policy decision.

The first classifier also wrongly assumed metadata lookup resolves aliases.
Review corrected that to explicit catalog-alias lookup, avoiding broad heuristics
that erase unknown unilateral qualifiers. The final packet-only Claude run returned
no substantive review and is NOT approval. Independent source review found no local
classifier defect, but CI correctly rejected the integrated behavior. The detached
`pressdown-family` sandbox and ignored `.agents/pressdown-b97254f` artifacts retain
the experiment locally; commit `b97254f` preserves its exact code in history.

Withdrawal verification at `e624745`: generator run `34961588332` passed with
656 executed tests; app run `34961588274` passed. All 20 complete exported week
objects and the historical snapshot match the `97b7589` baseline exactly. Source,
tests and package configuration match `b830807`; only the audit documentation
differs. This proves restoration, not resolution of the original duplicate.

### Dose-comparison boundary (2026-09-15)

`compareAllocatedDoseOnly` extracts the existing dose checks from the minimum-dose
candidate gate. Its result distinguishes the first rejection (calendar shape,
fatigue, role dose, weekly/session priority, maintenance ceiling/loss) from dose
preservation with or without a maintenance-minimum improvement. Indices in rejection
values are zero-based; this is not an exhaustive finding list or malformed-input validator.

The production minimum-dose caller still requires the exact per-slot exercise name,
target, role, pattern and count, plus a genuine minimum improvement. No substitutions
are activated. Existing tolerances and check order remain unchanged. Tests distinguish
weekly from per-day loss, weighted-only credit, role floors/ceilings, maintenance volume
beyond its minimum, and dose preservation from permission to change identities/counts.

This is a prerequisite, NOT complete-plan approval: a later substitution caller must
also enforce catalog/pain eligibility, locked identities, rest/day shape, movement and
prime-focus quality, coverage and its specific improvement objective. Do not treat the
dose-only `dosePreserved` result as a valid or improved workout. Rejection detail is
currently consumed by regression tests; the existing production caller still returns
a Boolean, so no new diagnostic detail is exposed in app reports yet. Wire that detail
when integrating candidate alternatives without publishing rejected candidates' receipts.
Acceptance for this extraction
requires unchanged complete exported week objects and historical snapshot in CI.

Verified code checkpoint `f4104d8`: generator run `34991998580` passed with 663
executed tests; app run `34991998575` logged BUILD SUCCEEDED. All 20 complete week
objects and the historical snapshot match restored checkpoint `e624745` exactly.
Windows smoke and per-file syntax checks passed. External review approved with
follow-ups: dose-only naming was strengthened, both calendar-shape branches are
tested, and report consumption remains explicitly deferred as described above.

### Bounded substitution trial (test-only)

`testBoundedPressdownSubstitutionsAgainstCompleteBaselineWeeks` explores one
pressdown replacement at a time in complete generated loading weeks. Its bounded
alternatives are Overhead Cable Triceps Extension and Cable Kickback, each tried
independently only if absent from the session. It only attempts sessions containing
multiple exact catalog pressdown names. Other slots, sets and days stay fixed.
Each trial starts again from the original baseline, never from a previous trial.
The test exports complete baseline/candidate prescriptions and the dose result,
requires actual trials (including the prior lumbar-persona case) and at least one dose-preserving
alternative, checks zero-set rejection, and checks that the existing minimum-dose
gate does not adopt these alternatives. This proves existence, not universal success;
the independent identity-mutation unit tests remain necessary to isolate that lock.
The existing `fullMesocycle` helper uses network-free procedural generation, not paid AI.

This is an arithmetic experiment, not an eligibility or adoption policy. It does not
establish that overhead work is suitable for a particular pain report, preserve retained
history slots through a new selection path, or prove that the replacement improves
movement quality. No production generator code changes. The historical snapshot and
complete exported weeks must remain unchanged.

Verified at `3440f08`: generator run `34999523904` executed 664 tests and passed;
app run `34999523916` logged BUILD SUCCEEDED. The `bounded-substitution-trials`
artifact records nine trials, all dose-preserving: six alternatives across the
back-focus persona's loading weeks and three Cable Kickback alternatives across
the lumbar-persona loading weeks. Each baseline also passed dose comparison with
itself. This is not a recommendation of those exercises for pain. All 20 complete
exported week objects and the historical snapshot match `f4104d8` exactly.

Separate Claude packet reviews approved with follow-ups. The trial was hardened
to assert equality with the delivered procedural exercises/targets/sets, retain
lumbar-case coverage, and export evidence instead of relying on captured stdout.
The next bounded step is an eligibility and retained-slot gate using the existing
catalog/history/pain rules, plus movement/focus-quality checks. Only after those
checks and an explicit duplicate-reduction objective pass should any trial be
eligible for adoption. Do not turn the dose-only result into production approval,
or reintroduce the rejected early catalog-selection gate. Crowding, pulling balance,
fractional targets and the original duplicate in delivered workouts remain open.

### Fixed-dose substitution preflight

`preflightFixedDoseSubstitution` adds a non-adopting check for exactly one changed
slot with all set counts and calendar dimensions preserved. It requires explicit,
in-range prefix locks and rejects nonempty rest days. `isProtectedAppearance`
shares the existing anchor/first-slot/Lower-secondary/prefix protection rule with
appearance reservation; the new preflight additionally checks the old canonical
role so a misleading stored role cannot bypass protection.

`SubstitutionPreflightTests` cover exact style-catalog membership, replacement
metadata, canonical pain-history exclusion, the existing reported-shoulder concern
check, same-session duplicates and pattern caps, loss of patterns on the changed day,
and downgrade of allocation/day-focus quality. The additional per-slot major-group
coverage guard is defensive and currently unisolated by a natural catalog regression
case; independent source review is not execution proof of that rejection branch.
Equipment skips remain preferences rather than new bans. The full-week trial
artifact now reports `PREFLIGHT_NO_HISTORY` separately from dose preservation.
Its explicit zero locks and empty pain history are synthetic, NOT production
continuity/history proof. No caller adopts a replacement or changes a locked menu.

Limits: this trusts the generated baseline (including old pattern metadata); it is
not a general malformed-input or medical-suitability validator. The catalog pool is
deliberately limited to the day's exact style catalog, without rescue/focus-pool
expansion. General injury review, selection preferences, prime-slot upper bounds,
cross-day variation, actual retained-context wiring, whole-plan dose comparison and
an explicit improvement objective still precede adoption. Prefix locks are not all
retained identities on focus days. Relocation and set redistribution are out of scope.
Independent source review found and prompted isolation of the allocation-quality
test; Windows syntax checks passed.

The staged review also prompted typed `SubstitutionPainExclusions` inputs: display
names are canonicalized once, while the existing history context's keys are consumed
without re-stemming. Both routes have exclusion tests. Pattern preservation is
conservative and local to the changed day; another day cannot hide a lost pattern.
That restriction is not proof that every original pattern is essential. Full-week
trial assertions now distinguish structural eligibility from exact-catalog refusal,
still under explicit synthetic no-history/no-prefix conditions. The SwiftPM test
target discovers files by directory; executed-test evidence is required after push.

Verified checkpoint `e328643`: generator run `35004726577` passed with 672 executed
tests, including all eight `SubstitutionPreflightTests`; app run `35004726723`
logged BUILD SUCCEEDED. All 20 complete exported week objects and the historical
snapshot are identical to `3440f08`. Of the nine dose-preserving trial swaps, six
passed the synthetic no-history preflight and three failed exact catalog membership:
the lumbar persona's Push catalog does not include Cable Kickback. This is not proof
the exercise is unsuitable, only that this deliberately narrow candidate source
cannot authorize it. The trial report's eligibility disclaimer refers to full
eligibility/adoption, not the limited structural checks now separately reported.

Stage 3 remains in progress. Real selection/retained-history context, preference and
injury review beyond these guards, upper slot/variation constraints and a complete
accept/reject decision with an improvement objective remain before production
substitutions. No original workout-quality finding is closed by this preflight.

### Shared-cost extraction slice

`WorkoutGeneratorService+SetAccounting.swift` centralizes per-appearance direct
and weighted credit, quality ranking, canonical role floor, raw muscle coverage,
and filtered maintenance/residue membership. Both reservation and allocation call it.
`WeeklySetAccountingTests` compares those values with canonical APIs, including
priority combinations, weighted-only work, repeated appearances and mismatched stored roles.

Raw coverage must remain separate from maintenance debit: priority-paid work can
still cover a muscle even when excluded from that group's residue. This distinction
was specifically checked by the `budget_contract_review` read-only agent, then
checked against source by the main agent; this is distinct from the later
packet-only Claude review. Neither review executed the Swift tests.

That credit-extraction slice did not unify weekly/session tolerances, capacity
assumptions, fatigue checks or candidate selection. It did not remove the legacy path or fix the backlog.
Acceptance requires unchanged full exported days, priorities and findings across
the current twenty-week matrix, plus the historical snapshot. Helper parity alone
cannot prove unchanged generator output. Existing fractional-ceiling and late-focus
integration tests remain unchanged.

### Shared-limit and refusal-evidence slice (2026-09-14)

Starting checkpoint: `6332487`; its full twenty-week JSON and historical snapshot
matched `b187f51`. Its executed suite contained 644 tests and the app build passed.

`WorkoutSetBudgetPolicy` now owns normal/floor weekly ceilings, maintenance ceilings
and focus-cap selection. `setBudgetLimits(for:)` supplies those values, normalized
focus matches and blueprint fatigue caps to reservation and funding. The prior
comparison allowances remain intentionally different: reservation uses the solver's
0.001 tolerance; funding adds 0.01 to maintenance/session caps, already includes
0.01 in the normal weekly ceiling, and adds nothing to its floor-repair weekly ceiling.
`SetBudgetPolicyTests` covers the policy matrix and distinct reservation/funding boundary.

The allocator's Boolean funding gate now delegates to `nextSetRejection`, preserving
its check order: role, maintenance, credited weekly priorities, day existence,
fatigue, then credited session priorities. An optional `setFundingReport` requests
one final-state observation per returned appearance. This is the SAME gate used to
fund sets, not a separately reimplemented diagnostic rule. Receipts contain the first
blocking budget, subject, projected amount and applied limit. A nil rejection means
the next set passes budgets, not that the funding objectives require buying it.

The observations describe a hypothetical next set at the FINAL allocation state;
they are not a chronological record of earlier refusals, an exhaustive list of
blockers, or proof that replacement/reallocation cannot solve the week. Their
zero-based indices refer to the RETURNED menu, after admission removals. There is
no new public arbitrary-index evaluator or new malformed-input guarantee.

The standalone check is intentionally not a SwiftPM executable product; it compiles
the production policy file directly for Windows validation:

```powershell
swiftc Transform/Transform/WorkoutSetBudgetPolicy.swift tools/check_set_budget_policy.swift -o .agents/set-budget-policy-check.exe
& .agents/set-budget-policy-check.exe
```

`UserJourneySimulationTests` adds `nextSetFunding` to the raw JSON and checks ordered
receipt locations, identity and dose against returned menus. The late-focus admission
regression also compares reporting enabled/disabled after a candidate is removed.
The known glute-shortfall diagnostic test is explicitly a reproduction of an OPEN
problem: it expects the actual gate to refuse the next lunge set at Quads 8 vs 7.51.
It must be revised when that shortfall is genuinely fixed; it is not a dose-acceptance rule.

Validation for this slice requires the complete old evidence to remain identical
after removing ONLY the newly added `nextSetFunding` field, plus an identical
historical snapshot. Full app/Swift CI execution and downloaded artifact comparison
are required before claiming this acceptance gate passed. Local syntax checks and
the standalone `tools/check_set_budget_policy.swift` numerical/Codable checks do not
establish app behavior. The optional report is not wired into app UI or paid requests.

Alternatives considered: collecting every blocker would require evaluating later
checks even after the decision is known; a separate diagnostic evaluator could drift
from funding. The first-blocker receipt keeps the existing short-circuit order.
It still constructs small rejection values on failed funding checks, so unchanged
runtime performance is not claimed from source inspection. Compare output first;
measure performance separately before changing the search or retry strategy.

Still open: candidate-builder gates, allocation-specific capacity assumptions,
replacement/relocation planning, legacy conflict handling, all quality findings,
volume policy and device validation. No rule band, deload behavior, warning severity,
exercise naming key or saved-data format is intentionally changed here.

### Audit cadence

- Before each fix: reproduce the failure and challenge its proposed cause.
- After the first implementation: separate adversarial review; turn credible findings
  into tests or exact reproducible examples and revise the implementation.
- Before committing substantial generator changes: independent staged-diff review
  using `tools/Invoke-GeneratorSecondAudit.ps1`; disclose unavailable reviewers.
- After pushing: verify tests actually ran, inspect build logs and compare raw workouts.
- At each stage boundary: revisit every open finding, record proven/failing/untested
  status, and compare a credible alternative before expanding the design.

Use the existing Swift harness, Python evidence checker, Git history and targeted
read-only reviewers. No paid AI generation is needed for the accounting slice.
Research and `EvidenceProfile.md` govern the later policy review; no research claim
is established by these software tests.

Baseline source commit: `d9e73d7`. This is a staged refactor, not a claim that
the generator is fixed. Policy retuning and deload changes are not part of the
evidence-export step.

## Evidence first

`UserJourneySimulationTests` exports the actual procedural days for five synthetic
personas over four weeks, along with their synthetic analysis and blueprint priority
targets. It uses the shared locked-menu prescription, but does not exercise paid AI,
actual training logs, persistence/UI integration, or a physical iPhone.

The `user-journey-evidence` CI artifact contains raw JSON and independently counted
metrics. The existing text report now shows exercise-level prescriptions too.
Counts by displayed muscle target are label sums, NOT biological stimulus credits.
Do not treat them as the validator's fractional direct/indirect accounting.
The exported priority targets are context for review; this first observer does NOT
check their attainment, meaningful frequency, pain exclusions, or fatigue budgets.
Those need explicit planner regression coverage rather than a naive label join.
The five-persona count is deliberately pinned independently: adding/removing a
Swift persona requires reviewing the observer's expected matrix too. Deriving
the expected count from the artifact itself would fail to detect lost evidence.

Run from the repository root after downloading the artifact:

```powershell
python tools/test_audit_workout_evidence.py
python tools/audit_workout_evidence.py <artifact-directory>/user-journey-evidence.json
python tools/audit_workout_evidence.py <artifact-directory>/user-journey-evidence.json --require-min-sets 2
```

The last command is an explicit product acceptance gate and is expected to FAIL
on the baseline: the arms persona still has one-set prescriptions. A green main
workflow does not override that result. The initial workflow validates evidence
integrity, not acceptance of the current workout quality. Promote this gate to
mandatory CI only with the planner change that genuinely satisfies it. Two sets
is a chosen product floor, not a claim that one set cannot produce adaptation.

## Planned implementation boundaries

1. Keep complete before/after evidence. Do not blindly update expected snapshots.
2. At menu construction, jointly fund exercise appearances and doses across the
   whole week. Do not spend a later focus day's budget greedily on an earlier day.
3. Preserve anchors, meaningful priority exposures, baseline coverage, pain/history
   exclusions, style/pattern constraints, and the common locked-menu prescription.
   If constraints conflict, expose the conflict rather than claiming compliance.
4. Retune volume policy separately, following the owner's handoff decisions and
   distinguishing chosen numbers from research-supported directions.
5. Retire superseded repair logic only after tracing all callers and pinning the
   original failure cases. The older fallback trim is not the normal locked-menu path.

For each structural change, compare all twenty generated weeks, reproduce every
original finding independently where possible, and obtain a separate adversarial
review. Include missing stimulus, excessive volume, empty/overcrowded sessions,
priority frequency, continuity, and known one-set cases; passing the two-set gate
alone is insufficient. No naming-key, saved-history, or persistence migration is
authorized by this refactor. Final integration proof remains the owner's iPhone.

## Current state

### Muscle-dose minimum reservation

After successful loading-week appearance admission, retain the existing priority-first
plan as a baseline. If a covered non-priority group is below MAINT-001's minimum,
construct a second plan that attempts those deficient groups' minimum (3 normally, 2 when constrained)
before priority funding. Accept only when at least one maintenance deficit improves,
no non-priority group's direct work falls, priority direct/weighted delivery and meaningful frequency do not fall,
including each day's priority direct/weighted work (not only weekly totals),
and role floors/ceilings, session/fatigue/weekly budgets and exact menu identity hold.
Prioritized groups/residue and deloads are exempt from the minimum. Every minimum
addition uses the existing normal funding gate, with no floor-overshoot mode.
Missing or blocked minima produce `minimum dose unresolved` diagnostics; they do not
add an exercise, change validator severity, or trigger a paid retry.

The baseline `f0e3f97` shoulder-beginner week delivered Glutes2 and Quads7, with the
next lunge set refused at Quads8 > 7.51. The regression now requires Glutes3 with the
same seven lower-day appearances and Leg Press 2 instead of 3. The full matrix also
checks all non-priority minimums alongside its existing priority volume/frequency
and fatigue assertions. CI and before/after raw evidence remain required acceptance
checks; passing a local syntax check does not prove this allocation.

The initial unconditional minimum-first approach was rejected: the five-exercise
Core target4/fatigue12 regression shows it displaces Core4 with Core2. Plan comparison
keeps the existing result in that conflict; the test executes both candidates.
Only the chosen plan's diagnostics/receipts are published. Second allocation is
conditional on a covered minimum deficit; performance must be measured, not assumed.

This is plan comparison, not a universal feasibility guarantee. It does not
solve competing minima by search, candidate replacement, crowded days, fractional
targets or pulling imbalance. Adding a new exercise was rejected for this slice:
the reproduced failure is a set-budget conflict on an already crowded day. A general
simultaneous-dose solver remains an alternative if conflicts survive this stage.

- Evidence export/checker implemented.
- Provisional loading-week admission now reserves role floors across the whole
  candidate week before optional set funding. It uses actual per-appearance costs,
  shared priority/maintenance ledgers, daily fatigue and direct-set caps. A bounded
  search chooses a subset; it does not place new exercises or move them across days.
- Required coverage, focus days, anchors and retained prefixes constrain admission.
  Existing candidate-pool gaps are not repaired by this step. Independent maximum
  capacity is only a necessary condition for priority targets, not a sufficient one.
- If no subset is found, or the search limit is reached, the legacy allocation is
  retained with an `APPEARANCE PLANNING CONFLICT` console diagnostic. This is an
  explicit remaining limitation, not a universal feasibility guarantee. Diagnostics
  are captured per week in the JSON evidence artifact, but not yet surfaced in the app UI.
- Deload allocation policy is unchanged. Volume retuning and retirement of legacy
  repair logic remain pending. Loading-week role floors, whole-set priority targets,
  meaningful frequency and actual daily fatigue are now regression assertions.
- The standalone Windows solver checks run with:
  `swiftc Transform/Transform/WorkoutAppearancePlanner.swift tools/check_workout_appearance_planner.swift -o <temporary-executable>`.
  Executing that binary does not test app metadata or the complete generator.
- Windows checks are syntax/toolchain checks only; macOS CI executes Swift tests.

### First integration evidence (`d0179bf`)

The app build passed. The generator run executed 638 tests, but failed on the stale
captured snapshot and an incorrect new exact-target assertion: nine loading-week
cases delivered seven sets against a 7.5 target. All exercise names, sets and targets
for the first four personas (16 weeks) matched the prior artifact exactly. These
were existing fractional budget gaps, not new losses of priority work.

`directSetCredit` awards zero or one credit per whole set; the normal allocator
also uses the target as a ceiling. The corrected observer requires the largest
integer not exceeding that ceiling, explicitly checks unit-credit semantics, and
exports the raw target, delivered credit and fractional shortfall. Seven against
eight still fails. This is not proof of biological adequacy or nonregression from
earlier above-target output; before/after comparison remains separate.

Fractional-target handling is intentionally preserved to isolate this architectural
change from the separately agreed volume-policy work. Pinning today's ceiling does
not endorse rounding down as optimal or permanent. Choosing rounded whole-set
blueprint targets (up, nearest, or down), and reconciling their session caps, remains
a policy decision for that later step; no such choice is being smuggled into this fix.

Independent raw-prescription arithmetic counted zero one-set prescriptions in all
20 weeks (baseline six). Arms loading weeks retained their total sets with one fewer
appearance each; all other exercise/set/target signatures, including all five deloads,
were unchanged. The older recovery-tight fixture lost only its one-set lateral-raise
appearance: its rowing imbalance remains. The beginner's glute-volume/crowded-lower
warnings and lumbar persona's other reported warnings also remain. This step does
not claim those findings are resolved.
