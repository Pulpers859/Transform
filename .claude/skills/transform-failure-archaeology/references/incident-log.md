# Transform Incident Log

Format per incident: symptom → root cause → fix → doctrine ("do not re-fight"). Entries cite commits and files. Narratives describe the past; verify against current code before acting on details.

## INC-1: Stale-local-`main` near-destruction of origin/main

- **Symptom**: A cloud/remote-execution container started work on a local `main` that was an UNRELATED history — no merge-base with `origin/main`, different layout, missing source files. Committing and force-pushing from it would have destroyed the real repo history. The owner describes this class of failure as "it gets my data lost."
- **Root cause**: Remote containers can materialize a stale snapshot as `main`; nothing forced agents to verify local `main` == `origin/main` before editing.
- **Fix**: Guardrails written into `CLAUDE.md` / `AGENTS.md` ("origin/main Is Source Of Truth" section) and agent docs (commit `04454bf`).
- **Doctrine**: Before any edit/commit: `git fetch --prune`, `git rev-list --left-right --count origin/main...main` must be `0 0`, `git merge-base main origin/main` must be non-empty, and `Transform/Transform/WorkoutGeneratorService.swift` must exist. Never force-push `origin/main`. If diverged: `git checkout -B main origin/main` and re-verify before editing.

## INC-2: Exercise progression data loss from canonical key stemming (fixed 2026-06, commit `d67f6d6`)

- **Symptom**: All logged exercise weights and reps silently disappeared for the owner.
- **Root cause**: `canonicalLookupKey()` (now at `Transform/Transform/WorkoutModels.swift:343`) used naive plural stripping (`hasSuffix("s")`), corrupting keys for words ending in "ss" ("press" → "pres") and mismatching singular/plural pairs ("presses" → "presse" vs "press" → "pres"). The canonical key is the single point of truth matching progression data across program regenerations — when keys drift, history orphans silently.
- **Fix**: Corrected stemming; added `normalizePerformanceLogs` (`WorkoutModels.swift:713`) as a startup re-keying pass for stale records after algorithm changes; added `DataIntegrityMonitor` (`TransformApp.swift:129`) and a backup data-drop guard in `DataBackupManager.swift` (commits `d67f6d6`, `83d4f43`).
- **Doctrine**: Never change canonical-key or exercise-name-normalization logic without (a) testing press/presses, raise/raises, crunch/crunches, fly/flies, and (b) a migration/normalization path for existing records. Do not weaken `DataIntegrityMonitor` or the backup data-drop guard. See `transform-data-safety`.
- **Addendum 2026-07-06**: A second stemming split survived the 2026-06 fix: singulars ending in 'e' never converged with their plural — "raises" → "rais" via the `-es` rule but "raise" stayed "raise" (also lunge/lunges, bridge/bridges, squeeze/squeezes; verified by running the algorithm off-device). Fixed by stripping a trailing 'e' from every stem (>3 chars) so both forms land on the same key; the startup normalizers (`normalizePerformanceLogs` + `normalizeAndConsolidate`, run every launch from `TransformApp`) re-derive stored keys from names, so existing data self-heals and previously split summaries consolidate on next launch. Doctrine unchanged, plus: when testing pairs, always include at least one e-ending word (raise/raises) and actually EXECUTE the algorithm — mental tracing missed this for three weeks.

## INC-3: Free-form AI exercise selection → menu-locked generation (arc `9071ef5` → `0a68ce9`)

- **Symptom**: AI-chosen exercise names drifted between generations (breaking weight-history continuity), duplicated exercises across days, and focus-exercise selection failed silently.
- **Root cause**: The AI prompt freely selected exercises; naming and selection were nondeterministic.
- **Fix arc** (in order): metadata-driven focus injection to fix silent selection failures (`f88b1ba`); deterministic exercise menus locked before the AI call (`9071ef5`); stale selection instructions stripped from prompts (`2544e70`); cross-day duplication, anchor eviction, and menu-locked validation fixes (`16fdd01`, `d07a67e`); fallback wired to the pre-selected menu instead of building its own (`cd22591`); menu-locked repair boosts sets without injecting or removing exercises (`55836f8`); `rebalanceDirectSets` overcounting and repair-overshoot fix (`edb99f1`).
- **Doctrine**: Do not reintroduce free-form AI exercise selection. In menu-locked mode, repair adjusts set counts on menu exercises — it must not inject or remove exercises. Fallback consumes the same pre-selected menu the AI got. Prompt text about exercise selection must stay consistent with the locked-menu reality.

## INC-4: Fallback silently under-delivering blueprint targets (documented in `docs/3_TRANSFORM_CLEAN_HANDOFF.md`; superseded in part by INC-3)

- **Symptom**: "Procedural fallback generated an invalid Week 1 program" — fallback could not meet frequency/direct-set targets for under-served priority muscles.
- **Root cause**: The repair loop (`repairedProceduralDays` in `WorkoutGeneratorService+FallbackCore.swift`) could only bump sets on exercises already present on a day; it could not spread work to days lacking coverage.
- **Fix**: `isHeuristicValidationIssue` (ParsingValidation) expanded so only structural failures hard-fail; `injectAccessoryExercise` and expanded candidate days added to the repair loop.
- **Doctrine**: Distinguish structural failures (invalid shape, empty fields, bad day counts) from heuristic quality issues (warnings). NOTE: menu-locked mode (INC-3) later constrained injection — check current `FallbackCore` behavior before assuming injection is allowed.

## INC-5: Retry loop burning API credits on heuristic-only issues (arc `ec09e64`, `723dd03`, `4ab06f3`)

- **Symptom**: Regeneration retries spent Anthropic API calls on issues that were quality nits, not structural failures.
- **Root cause**: Validator severity tiering didn't separate "retry-worthy" from "warn-and-accept."
- **Fix**: Heuristic issue tiering with correction-loop acceptance; generic session-note validator plus a polishing safety net for AI output.
- **Doctrine**: A retry must be justified by a structural failure. Heuristic-quality issues get fixed in sanitization, validator policy, or accepted with warnings — not by re-billing the API. Do not dumb down output to satisfy a rigid validator; if the validator is wrong, fix the validator.

## INC-6: Program deletion vs archiving policy (arc `5a24463` → `0a68ce9`)

- **Symptom / evolution**: Programs were first deleted on re-generation (losing skip/pain history), then archived to preserve that history (`5a24463`), then refined: *empty* programs (no logged data) are deleted instead of archived (`0a68ce9`).
- **Doctrine**: Archiving exists to feed skip/pain/substitution history into future programming (`3446560`, `a9564e6`). Do not "simplify" to always-delete (loses history) or always-archive (accumulates empty junk). The empty/non-empty distinction is intentional.

## INC-7: Design-token and haptics centralization (arc `867d1fd` → `1653482`, completed 2026-06-14)

- **Symptom**: Hardcoded colors, fonts, and scattered haptics made the UI inconsistent and unauditable.
- **Fix arc**: Design system introduced (`867d1fd`), token migration across view files (`1dbcea3`, `e3e6cf0`, `2368200`), haptics centralized into `TFHaptics` and color tokens unified (`02ccb86`), VoiceOver chart summaries and radius-drift fixes (`1653482`). 526+ token uses; tokens live in `Transform/Transform/DesignSystem.swift`.
- **Doctrine**: New UI code uses `TFColor` / `TFTypography` / `TFHaptics` tokens, not raw `Color(...)`, system fonts, or ad hoc `UIImpactFeedbackGenerator` calls.

## Candidate entries (unverified details — confirm before citing)

- Uniform prescription cleanup in sanitization and prompt-caching/model-ID changes in the Anthropic request path are mentioned in `transform-generator-audit` references as recent-change risks, but no incident narrative is recorded for them.
