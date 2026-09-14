# Generator planner refactor: evidence and acceptance

## Active roadmap and audit checkpoints (2026-09-13)

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

This slice does NOT unify weekly/session tolerances, capacity assumptions, fatigue
checks or candidate selection. It does not remove the legacy path or fix the backlog.
Acceptance requires unchanged full exported days, priorities and findings across
the current twenty-week matrix, plus the historical snapshot. Helper parity alone
cannot prove unchanged generator output. Existing fractional-ceiling and late-focus
integration tests remain unchanged.

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
