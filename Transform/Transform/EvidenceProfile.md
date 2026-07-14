# Transform Evidence Profile

Version: `hypertrophy_v1_6`
Last updated: `July 14, 2026`
Scope: `General hypertrophy-oriented bodybuilding programming for healthy adults using a fully equipped commercial gym`

This file is the programming contract for the workout generator. The goal is not to pretend the literature gives one perfect answer for every client. The goal is to make the app's assumptions explicit, versioned, reviewable, and adjustable.

## Source base
- ACSM 2026 Position Stand / umbrella review: Currier BS, D'Souza AC, Fiatarone Singh MAF, et al. "Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews." Med Sci Sports Exerc. 2026;58(4):851-872. DOI: `10.1249/MSS.0000000000003897`
- Broad hypertrophy literature on weekly volume, frequency, exercise selection, effort, rest intervals, and progression
- Lower-confidence deload/taper evidence and expert consensus for resistance training fatigue management

## Confidence scale
- `High`: broad directional agreement across strong reviews or large evidence summaries
- `Moderate`: strong practical support, but exact numeric prescriptions still depend on context
- `Low-Moderate`: useful coach-facing guidance with some evidence support, but less directly settled in the literature
- `Low`: mainly pragmatic coaching structure where the literature is sparse or indirect

## Rule table

| ID | Topic | Current rule | Confidence | Rationale |
| --- | --- | --- | --- | --- |
| `BASE-001` | Baseline whole-body frequency | Programs should expose all major muscle groups to resistance training at least `2` days/week across the weekly plan | High | The ACSM 2026 position stand and public-facing summary both support training all major muscle groups on two or more days per week as a core healthy-adult prescription anchor |
| `FREQ-001` | Weekly frequency by priority | High priority muscles default to `2` targeted exposures/week; medium and low default to `1` targeted exposures/week, while the full plan should still satisfy `BASE-001` | Moderate | The ACSM review supports at least two weekly exposures at the whole-program level, but exact targeted frequency for specialization remains more context-sensitive and is still mediated by total weekly volume and recoverability |
| `SLOT-001` | Targeted exercise slots by priority | High priority areas default to `3` targeted exercise slots/week; medium `2`; low `1` | Moderate | This gives the generator a concrete way to distribute emphasis without forcing all stimulus into one session |
| `VOL-001` | Weekly direct sets by priority | High priority areas target roughly `8-12` direct sets/week; medium `5-8`; low `3-5`, then adjust for volume/direct-work bias | Moderate | The ACSM umbrella review strengthens the case that hypertrophy is enhanced by higher weekly volume, citing `>=10` sets/week as a useful anchor, but exact set targets still vary by muscle group, training age, and exercise choice |
| `MAINT-001` | Non-priority maintenance ceiling | Muscle groups outside the blueprint's priority list are maintenance work capped at roughly `10` direct sets/week (`8` when recovery or nutrition adherence is constrained); zero weekly direct sets for a major muscle group violates `BASE-001` and must be surfaced | Low-Moderate | Priority-only volume policing let non-priority volume grow unbounded (~98 weekly sets in a deficit) while hamstrings received zero sets undetected; a maintenance band of roughly 6-10 sets preserves tissue without stealing recovery from priorities, though the exact ceiling is a pragmatic coaching number rather than a settled literature value |
| `CONC-001` | Focus-day concentration allowance | Priority muscles may concentrate a larger share of weekly direct sets into a designated focus day than a simple even split would allow, but should still avoid putting essentially the entire weekly stimulus into one session | Low-Moderate | Real hypertrophy specialization often uses emphasis days rather than perfectly flat distribution; the validator should catch reckless piling-on, not reject every legitimate focus session |
| `VOL-002` | Weighted stimulus accounting | Direct work counts fully; indirect work is credited partially through weighted stimulus bonuses | Low-Moderate | This is a pragmatic approximation so the system can recognize that compounds contribute to multiple areas without pretending all stimulus is equal |
| `STR-001` | Strength-oriented loading anchor | Strength-focused anchor lifts should generally bias heavier loading, full ROM, multiple sets, and early-session placement | Moderate | The ACSM umbrella review found voluntary strength was enhanced by heavier loads (`>=80% 1RM`), complete range of motion, `2-3` sets, early-session placement, and `>=2` sessions/week |
| `ORD-001` | Exercise order | Anchor compounds stay first, secondary compounds follow, accessories after, core last unless the day is explicitly core-biased | Moderate | The ACSM umbrella review strengthens the case for early-session placement for strength outcomes, while progression tracking and fatigue management still support stable session order in practice |
| `SPEC-001` | Focus-day exercise specificity | A specialization day should be built around at least one prime hypertrophy movement for the target area; support, corrective, or scapular-control drills can complement the session but should not masquerade as the main growth slot | Low-Moderate | This is mostly biomechanics- and coaching-driven logic rather than a neat RCT rule, but it is important if the app is going to claim muscle-specific emphasis honestly |
| `CONT-001` | Week-to-week continuity | Comparable sessions should retain at least `1` anchor lift across weeks when the session style remains comparable | Moderate | Reliable progression needs repeatable anchors, but the program must still be free to rotate accessories |
| `REST-001` | Rest intervals by role | Anchor compounds: roughly `120-180s`; secondary compounds: about `90-120s`; most accessories: about `60-90s`; core/support drills: about `45-60s` | Low-Moderate | The ACSM umbrella review did not find rest interval duration to consistently impact primary outcomes in healthy adults, so the app should use role-based ranges instead of pretending one exact number is the evidence-based answer for every lift |
| `ECC-001` | Eccentric overload bias | Eccentric overload can be used selectively to increase hypertrophy stimulus for priority muscles when exercise tolerance and technique allow | Low-Moderate | The ACSM umbrella review reported that hypertrophy was enhanced by eccentric overload, but implementation details remain less standardized than broad volume/frequency guidance |
| `PROG-001` | Mesocycle progression | Week 1 establishes anchors, Week 2 adds volume/progression, Week 3 pushes hard sets while accessories bias toward `10-15` reps, Week 4 deloads while preserving movement continuity | Low-Moderate | This is a practical hypertrophy mesocycle template, not a universal law; the higher accessory rep bias in Week 3 shifts fatigue toward local/metabolic stress instead of piling more systemic loading onto the mesocycle peak |
| `DEL-001` | Deload strategy | Deload reduces fatigue primarily through lower hard-set exposure while keeping session identity and technical practice intact | Low-Moderate | Deload evidence in resistance training is weaker and less standardized than basic hypertrophy dose-response evidence; volume reduction is usually the least disruptive lever |
| `FAT-001` | Session fatigue caps | Different session styles have different fatigue ceilings; lower-body sessions tolerate more systemic fatigue than arms sessions | Low-Moderate | This helps prevent the generator from stacking too many high-cost lifts into one day |
| `REC-001` | Local recovery spacing | When possible, the weekly layout should avoid stacking two shoulder-intensive emphasis days back-to-back if a less-overlapping session can separate them | Low-Moderate | This is a recoverability and session-quality rule rather than a hard law, but it keeps the generator from creating obviously muddy upper-body sequencing |
| `SIMP-001` | Advanced-method restraint | The generator should not assume that failure training, complex periodization, special equipment, exotic set structures, or time-under-tension manipulation are necessary for strong outcomes | Moderate | The ACSM umbrella review found these variables did not consistently affect primary outcomes in healthy adults, so the app should treat them as optional refinements rather than core drivers |
| `TEMPO-001` | Explicit tempo prescription | Every generated exercise should carry an explicit four-part tempo, but the app should use broad role-aware defaults rather than overclaiming that one exact cadence is hypertrophy-optimal | Low | The ACSM umbrella review did not find time under tension to consistently impact outcomes. Tempo remains useful in Transform mainly as an execution-standardization and auditing tool, not as a high-confidence primary adaptation lever |

## Operational notes

### Deterministic dosage ownership
- The pre-selected exercise menu owns both exercise identity and working-set dosage before any
  AI request. Priority targets are allocated first; every non-priority movement then spends from
  the applicable major-muscle maintenance budget, including every group credited by shared-primary
  metadata.
- Recovery-tight maintenance groups are limited to at most four meaningful exercise identities
  under the 8-set ceiling. Fallback and AI output consume the same prescription; neither creates
  a separate role-default set budget or repairs maintenance volume after generation.

### Directional evidence vs exact numbers
The literature is stronger on directional principles than on one exact bodybuilding template. For example:
- higher weekly volume tends to support hypertrophy better than very low volume
- repeated weekly exposure is often useful
- exercise order matters for performance and progression
- heavy loading helps strength outcomes
- many advanced methods are optional rather than mandatory

The literature is weaker on exact app-ready numbers like:
- the perfect direct set target for every muscle in every client
- the exact percentage cut for all deload weeks
- the exact fatigue cap for each day style
- the exact tempo prescription that maximizes hypertrophy
- the exact rest interval that must be used for all exercises

That is why this profile marks some rules as `Moderate` or `Low-Moderate` instead of overstating certainty.

## ACSM 2026 Takeaways That Matter Here

The most useful upgrades from the 2026 ACSM position stand for Transform are:
- `BASE-001`: all major muscle groups should be trained at least 2 days/week at the program level
- `VOL-001`: hypertrophy responds to higher weekly volume, with `>=10` sets/week being a practical anchor for muscle-growth planning
- `STR-001`: strength work benefits from heavier loading, full ROM, multiple sets, and early-session placement
- `SIMP-001`: the app should not oversell advanced methods, because training to failure, equipment type, set structure, time under tension, and periodization did not consistently change primary outcomes in the reviewed healthy-adult evidence

The most important caution from the paper is that few RT prescription variables changed primary adaptations consistently. That means Transform should lean harder on the big rocks:
- consistency
- sufficient weekly volume
- sensible exercise selection
- progressive overload
- recoverability

and be more humble about:
- exact tempo rules
- exact rest prescriptions
- claims that a specific mesocycle structure is "the evidence-based answer"

### Deload caution
Transform should not treat deload prescriptions as settled science. Deload logic should be conservative, explicit, and easy to revise. If future testing shows the app's deload weeks are too harsh or too mild, `DEL-001` should be updated and the code should be revised to match the new profile version.

### Change management
When a training rule changes:
1. update this file first
2. bump the version string
3. update the generator logic that references the affected rule IDs
4. note the behavioral impact in code review or release notes
