# Device generator evidence audit — 2026-09-14

## Evidence boundary

Reviewed the owner's attached console/workshop export. It contains requests from
September 8, 11 and 14; the final JSON belongs to the latest reported generation.
The owner identifies the build as preceding `97b7589`; the export does not identify
an exact Git SHA. Source comparison used local/remote `97b7589`. Do not call the
entire attachment a single run or infer an exact installed build from its filename.
The private analysis/profile and raw export are not copied into this repository.

Parsed final JSON: five training days, 31 exercise appearances, 79 working sets,
zero prescriptions below two sets. The workshop reports live AI success, no fallback,
and two accepted warnings. This is device generation evidence, not proof of a
completed workout, symptom tolerance, persistence correctness or every profile.

## Findings and acceptance work

1. **Confirmed existing pulling-dose gap.** The complete week has Pull-Up3,
   Lat Pulldown3 and Chest-Supported Row2: six vertical versus two horizontal sets.
   `enforceHorizontalPullCoverage` stops when any horizontal pull exists;
   `validateBackPatternBalance` checks dose (vertical >=4 and rows*2 < vertical).
   Earliest gap: menu coverage protects presence, not sufficient rowing dose.
   Add an allocation regression with these appearances and preserve useful back
   work, priorities and limits. Do not globally ban pull-ups plus pulldowns.

2. **Confirmed existing crowding observation, not proof an arbitrary slot is filler.**
   Lower day contains seven movements and 21 sets: RDL3, Leg Press3, Leg Curl3,
   Leg Extension3, Calf Raise3, Pull-Through2, Knee Raise4. The warning alone does
   not establish which movement can be removed without losing coverage/dose.
   Evaluate substitution, redistribution and removal against the complete week.

3. **New lexical coverage gap in same-session handle duplication.** The arms day
   contains Rope Triceps Pressdown2 and V-Bar Pressdown2. Both have primary Triceps
   and pattern Pressdown. `gripVariantStem` removes rope, producing
   `triceps pressdown`, but its single-generic-word protection retains `v bar`
   rather than reducing that name to `pressdown`. Thus `isGripVariantDuplicate`
   misses the pair. This chain is source-verified, not yet executed as a Swift
   regression. Add both pair orderings plus overhead-extension/pressdown and curl
   controls. Use a planning-only family identity; do not change persisted names
   or globally remove the single-word protection.

4. **Shoulder adaptation check needs an adversarial test; this export does not
   prove an unsafe exercise.** A machine shoulder press remains, with a specific
   symptom-limited ROM cue. Current shoulder-press validation also accepts generic
   day warm-up keywords as sufficient adaptation, and accepts a neutral-grip cue
   even when that grip is named in the pain report. Test a reproduced provocative
   movement with an unrelated warm-up and with a contradictory grip instruction.
   Do not equate a warm-up keyword with demonstrated tolerance, or automatically
   diagnose/ban all presses from a narrowly described symptom.

5. **Recovery contract mismatch, deliberate implementation.** The export labels
   recovery constrained via profile/check-in context without fresh sleep logs.
   `programCalibrationProfile` explicitly implements that fallback, and
   `RecoveryModulationTests` explicitly protects it. SLEEP-001 instead says missing
   logs apply no adjustment. Resolve the policy/documentation disagreement before
   altering behavior; this is not evidence that the fallback was accidentally added.

6. **Ordering contract mismatch, not established programming harm.** The locked
   Upper menu places lateral-raise accessories before secondary machine presses.
   `sessionOrderingBand` deliberately groups secondary/accessory work together,
   allowing focus ranking to lead within that group. ORD-001 describes separate
   secondary-before-accessory ordering. Decide which contract is intended; retain
   anchor protection and do not claim focus-first isolation is inherently wrong.

## Findings not supported by this export

- The two September 14 requests are consistent with `parallelCandidates == 2`
  and the four-second cache stagger. Both succeed, with the second reporting cache
  reads. This is intentional candidate selection, not evidence of an accidental
  duplicate button action or repair retry. Its extra output cost remains a product
  tradeoff, not a newly diagnosed transport defect.
- The September 8 transport timeouts are historical, not a failure of the latest run.
- This profile's blueprint prints whole direct-set targets (10, 10, 6). It does not
  add a new fractional-target reproduction; keep the existing 7.5-versus-7 fixtures.
- No new one-set regression is present. The latest minimum-dose fix still needs its
  own device verification; do not attribute this earlier device result to it.

## Research boundaries

- [ACSM 2026 overview of reviews](https://pubmed.ncbi.nlm.nih.gov/41843416/)
  supports progressive resistance training and higher weekly volume for hypertrophy.
  Its general findings do not establish this app's exact crowding cutoff or a unique
  correct vertical-to-horizontal ratio. Treat those as explicit programming heuristics,
  not biological laws. In particular, fewer row sets is not zero rowing stimulus.
- [2025 rotator-cuff clinical practice guideline](https://doi.org/10.2519/jospt.2025.13182)
  supports assessed, individualized active rehabilitation. It does not diagnose this
  user's shoulder from a workout log or certify a machine press from a warm-up phrase.

## Work order

Keep the existing crowding/pulling/fractional-target roadmap. Fold the pressdown-family
regression into candidate-redundancy work; investigate the shoulder false-clear path
before changing shoulder filtering. Reconcile recovery and ordering contracts as
separate policy items. Every implemented fix still needs an adversarial regression,
the complete generated-week comparison, and explicit reporting of remaining findings.
No production behavior was changed by this audit.
