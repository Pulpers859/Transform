---
name: transform-generator-audit
description: Audit the Transform workout generator, validator, and fallback pipeline for quality drift, blueprint misses, prompt/validator mismatch, retry waste, and API-cost regressions. Use when debugging workout generation, reviewing generator-related code changes, analyzing Generator Workshop or Validator Workshop output, or checking whether a workout is genuinely good rather than merely schema-valid.
---

# Transform Generator Audit

Use this skill to review the Transform workout-generation stack with the app's real priorities: workout quality first, evidence-informed programming integrity second, then validator correctness, silent-failure risk, API waste, and maintainability.

## Workflow

1. Confirm the source-of-truth repo is `C:\Dev\Transform_clean` and the app source root is `C:\Dev\Transform_clean\Transform\Transform`.
2. Read `references/audit-map.md` before making assumptions.
3. Collect the raw artifact first:
   - Generator Workshop dump
   - validator issues
   - final JSON payload
   - screenshots
   - failing commit or diff
4. Map the symptom to the correct layer before proposing fixes:
   - prompt/request construction
   - parsing/sanitization
   - metadata/evidence mapping
   - training intent / blueprint generation
   - validator policy
   - fallback generation / repair
   - UI/debug reporting
5. Separate structural failures from heuristic quality issues.
   - Structural failures: invalid shape, empty fields, bad day counts, invalid ranges, crashes, broken persistence.
   - Heuristic quality issues: filler work, blueprint drift, over-volume, under-stimulating focus days, prompt/validator mismatch.
6. Review findings in this order:
   - shipping bugs or crash risk
   - coaching-quality regressions
   - validator/fallback mismatch
   - silent failure risk
   - wasted retries / wasted cost
   - maintainability concerns likely to compound

## Rules

- Do not dumb down output just to satisfy a rigid validator.
- If the validator is wrong, improve the validator.
- Preserve the split `WorkoutGeneratorService` architecture.
- Fix the right layer instead of piling logic into one file.
- Distinguish evidence-backed conclusions from heuristic judgments.
- Treat validator-clean output as insufficient proof of programming quality.
- Prefer findings first when reviewing; summary second.

## Common Uses

- "Review this Generator Workshop dump and tell me what is actually wrong."
- "Audit whether the validator is rejecting good programming or letting bad output through."
- "Check whether this retry loop is wasting Anthropic calls."
- "Review this generator PR for blueprint drift or fallback regressions."

## References

- Read `references/audit-map.md` for file hotspots, failure patterns, and current audit questions.
- When a task depends on the programming contract, read `Transform/Transform/EvidenceProfile.md`.
- When a task depends on current repo operating rules, read `2_PROJECT_HANDOFF.md` and `3_TRANSFORM_CLEAN_HANDOFF.md`.
