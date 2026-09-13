# Generator planner refactor: evidence and acceptance

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
  repair logic remain pending. Loading-week role floors, delivered priority targets,
  meaningful frequency and actual daily fatigue are now regression assertions.
- The standalone Windows solver checks run with:
  `swiftc Transform/Transform/WorkoutAppearancePlanner.swift tools/check_workout_appearance_planner.swift -o <temporary-executable>`.
  Executing that binary does not test app metadata or the complete generator.
- Windows checks are syntax/toolchain checks only; macOS CI executes Swift tests.
