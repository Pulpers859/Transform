# Transform Claude Code Memory

## Evidence Before Sentence (READ FIRST — OUTRANKS EVERY OTHER RULE IN THIS FILE)

The owner's standing instruction, in his words: **never make findings or claims without double
checking what you are saying.** Overstatement is not a style problem here. It sends him down false
paths, costs him hours, and burns tokens re-doing work that should not have been started. He has
raised this more than once. Raising it again is a failure.

This rule is PERMANENT, has NO exceptions, and binds every agent, subagent, lane, and reviewer
spawned from this repo. Put it in their brief verbatim.

### The order is: check, then speak. Never speak, then check.
Two real failures from one session, both the same shape:
- Wrote "a four-day week cannot give two priority muscles a full dose and still give every other
  muscle four sets — that is arithmetic." Nothing had been computed. When actually computed, the
  week had ~94 sets of capacity against a ~52-set requirement. The claim was not merely wrong, it
  was presented as a mathematical certainty and it redirected the whole investigation.
- Wrote "I have now disproved my own claim. Let me verify the numbers before I retract it." The
  verdict and the admission that it was unverified sat in the SAME sentence.

So: **a message may contain a verdict, or a statement that you are about to check something. Never
both about the same claim.** If the evidence does not exist yet, the only honest sentence is "I am
checking X" — with no hint of which way it will land.

### Banned openings (each one is a verdict shipped ahead of its evidence)
Do not write any of these unless the check is ALREADY DONE and you can name its output:
- "I've now confirmed / disproved / verified …" followed by the work that confirms it
- "This is definitely / clearly / obviously …"
- "That is just arithmetic" / "that is structural" / "that is physics"
- "There are N bugs" before N has been counted from a list you can produce
- "This is the root cause" before the causal chain has been read end to end
- Any number — a count, a percentage, a capacity, a threshold — that was estimated rather than
  computed from source or measured from output

### Every claim carries its evidence grade
When stating a finding, the grade is part of the finding, not an optional footnote:
- **Verified** — name the file and line you read, the script you ran and its output, or the CI run
  you confirmed actually executed. No name, no "verified".
- **Reasoned, not reproduced** — you followed the logic but did not observe it. Say exactly this
  phrase. It is fully acceptable to report; it is not acceptable to leave unlabeled.
- **Guess** — say "I am guessing". Usually the right move instead is to go check.

### Quantitative claims
Any sentence containing a number about this codebase's behavior must be produced by reading the
constant, running a script that parses the constant out of the source, or measuring real output.
Never by mental estimate. Scripting it costs a minute; being wrong costs the owner an afternoon.

### Retractions
When you are wrong, correct it in one plain sentence, say what is true instead, and continue. Do
not narrate the mistake, tally past mistakes, or apologise repeatedly — that is its own kind of
waste. The one thing that must never happen is the same overstatement shipped twice.

## Start Here
- Source-of-truth repo root: `C:\Dev\Transform_clean`
- Current working branch: `main`
- Use the files in this repo root as the active source tree unless the user explicitly says otherwise.
- Ignore stale copies unless the user explicitly asks:
  - `C:\Dev\Transform`
  - `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Transform`

## Never Assume — Verify, Then State (HIGHEST PRIORITY, APPLIES TO EVERY AGENT)
- This rule outranks speed, brevity, and every other instruction in this file except the
  data-safety and `origin/main` rules. It is permanent and has no exceptions.
- **Do not state anything about this codebase you have not just verified.** Not from memory, not
  from an earlier turn in the same conversation, not from a plausible inference, not from a code
  comment, and not from another agent's report. Open the file and read the actual lines first.
- If you have not verified it, you must either verify it before speaking or label it explicitly:
  "I have not checked this." Never present an inference as a finding.
- Applies verbatim to EVERY subagent, lane, reviewer, and audit spawned from this repo. Put this
  rule in their brief. Their findings are unverified claims until the spawning agent has checked
  them against the code — verify before acting on them, and say which parts you verified.
- Concrete failures this rule exists to prevent — all real, all from one session:
  - Asserted a validator finding lived in `menuLockedDemotionPatterns` from a line number seen in
    an earlier grep, without re-checking which array that line fell inside after intervening edits
    shifted it. It was in `correctionWorthyIssuePatterns`. The wrong belief went into a code
    comment AND a test, and CI caught it.
  - Wrote a bodyweight-movement list "from general knowledge" instead of reading
    `WorkoutGeneratorService+MetadataProfiles.swift`, and missed real catalogue entries.
  - Told the owner generation produced a 4-week plan. It produces one week per call.
  - Told the owner a load-translation feature was live in the app when the only caller built a
    prompt string. It did nothing.
  - Reported four fixes as "the fixes" while five more audited, confirmed items sat unworked.
  - Subagents reported a deliberate, documented design choice as a bug, and a correct progression
    cue as a defect. Both would have caused real regressions if applied unverified.
  - Wrote a source comment claiming a new Generator Lab card sat OUTSIDE the `if let report`
    block. It was inside `resultsCard(_ report:)`. That is not a cosmetic slip: the card is a
    network log whose entire purpose is explaining a run that FAILED and therefore produced no
    report, so the placement hid it in exactly the case it exists for.
  - Wrote two initialisers in a new test from memory — `BodyAnalysisResult` and
    `SleepRecoveryState`. Both had wrong labels. The correct ones were sitting in
    `RecoveryModulationTests`, which constructs the same types.
  - Claimed a new out-of-range `targetRIR` check guarded against bad model output. It cannot: the
    decoder clamps that field to 0...5 and drops junk to nil before the validator ever runs. The
    branch is unreachable from every producer that exists. An auditor caught the overstatement.
- **The failure is always the same shape: something was easy to look up and got typed from memory
  instead.** Every instance above took under a minute to verify and was wrong. There is no
  category of claim about this repo cheap enough to skip checking.
- Note which of these CI can and cannot catch. Wrong initialiser labels and wrong types fail the
  build, so they cost a cycle and are recoverable. Wrong claims in COMMENTS, COMMIT MESSAGES and
  MESSAGES TO THE OWNER compile perfectly and ship — they are the dangerous half, and the only
  defence is reading before writing. Treat a sentence about behaviour as seriously as code.
- Practical discipline:
  - NEVER type an initialiser, method signature, enum case, or field label from memory. Grep the
    declaration, or copy a working call from an existing test, every time.
  - Before writing a comment that says where code sits or what scope it runs in, read the
    enclosing declaration. `awk 'NR<=LINE && /^    func /{n=NR;l=$0} END{print n": "l}' FILE`
    answers it in one command.
  - Before claiming a new guard protects against something, find the code path that would reach
    it. If an earlier layer already handles that input, say so instead of claiming the credit.
  - Line numbers go stale the moment anything above them changes. Re-grep; never reuse a line
    number across edits.
  - Before claiming a value, behavior, or wiring, read it — and prefer generating strings and
    numbers from the source (script them out) over retyping them.
  - Before claiming something is fixed, name the evidence: the test that covers it, the CI run
    that went green, or the code path you read end to end.
  - When you cannot verify (no toolchain, no access), say exactly that and say what would verify
    it. "Correct-by-inspection" is a claim about what you read, not a substitute for reading it.
  - A green check is not evidence on its own. Confirm the work actually ran.

## A Claim About Behavior Needs A Test, Not A Sentence (COMPANION TO "NEVER ASSUME")
- "Never Assume" says verify before you speak. This says what verification has to LOOK like, and
  it exists because roughly half the errors in this repo are sentences, not code. A wrong
  initialiser fails the build and costs one cycle. A wrong sentence in a comment, a commit
  message, or a message to the owner compiles perfectly and ships, and the only reader who could
  have caught it is the one being misled by it.
- Scope: code comments, doc comments, commit messages, PR bodies, and every message to the owner.
- Three kinds of sentence, three different obligations:
  - **A claim about what the code DOES.** Name the test that pins it, or do not write the
    sentence. "This gate refuses a set once the day is over its fatigue cap" is a claim. If no
    test covers it, either write the test or write the sentence with "not covered by a test" in
    it. Both are acceptable. Asserting it bare is not.
  - **A claim about WHY something exists, or what happened before.** History is allowed without a
    test, but it must read as history and must not smuggle in a claim about current behavior. The
    failure to watch for: a history paragraph that was true when written and false one commit
    later. In this repo one such paragraph said the joint-stress rules "do not consult
    `hasShoulderRisk` at all" while a comment in the same tree said the opposite, because the
    rule had changed underneath it.
  - **A claim that a change FIXES something.** Name the evidence: the test, the CI run that went
    green and was confirmed to have executed, or the code path read end to end.
- The cheap discipline, in order: before writing a sentence about behavior, ask whether a test
  names it. If yes, cite it. If no, write the test, or label the sentence. There is no fourth
  option.
- Watch specifically for a comment that JUSTIFIES a design with an example. An example is a claim
  and it is the easiest thing in this file to get wrong, because it feels like illustration rather
  than assertion. Real instance: a comment justified an override by saying
  "Behind-the-Neck Lat Pulldown matches the list", which it did not, because the list held spaced
  keywords and the name held hyphens. The design was right; the example was invented.
- Where the tests go. Do not add a bespoke test built from the one example that inspired a rule —
  that is the blind spot, not a cure for it. Extend the existing tables:
  - `Tests/TransformGeneratorCoreTests/ShoulderReportCorpusTests.swift` — report shapes crossed
    with movements, for anything reading the lifter's injury note.
  - `tools/check_shoulder_families.py` and `tools/check_validator_patterns.py` — structural
    invariants that no Swift test can express, each with its own self-test of pinned attacks.

## An Audit Delivers A Failing Test, Not A Paragraph
- Audits and review lanes do find real defects here; four rounds in one session each found real
  ones. The weak link is what comes back. A finding arrives as prose, the spawning agent decides
  whether to believe it, and the spawning agent is the author. A paragraph can be argued with. A
  red test cannot.
- So the deliverable for any finding that claims a behavior is wrong is, in order of preference:
  1. A test committed to the repo that FAILS on the current code. The spawning agent must see it
     red before writing a fix and green after. Do not "fix" first and add the test afterwards:
     a test written after the fix proves the fix compiles, not that the bug existed.
  2. When it cannot be expressed as a test — a prompt-shape problem, a cost problem, an
     owner-facing wording problem — the exact file and line, the exact input, and the exact
     output that is wrong, so it can be checked in under a minute without re-deriving anything.
- A finding that is neither is still worth reporting and must be LABELED "reasoned, not
  reproduced" in the audit output, in the commit message, and in the message to the owner. That
  label is not a formality: this session shipped a slot-placement fix that no test drives end to
  end, and saying so plainly is the difference between a known gap and a false claim of coverage.
- The same rule binds the spawning agent. A subagent's finding is an unverified claim until it is
  checked against the code; a subagent's failing test is checked by running it. Prefer the second.
- Never weaken a rule to make a test pass, and never write a test that asserts current behavior
  just to make a finding go away. If the fix is genuinely not worth making, say so and leave the
  finding reported.

## Branch Policy
- Use `main` as the only working branch for this repository.
- Commit directly to `main` and push directly to `origin/main`.
- After completing code, config, docs, workflow, or instruction changes, stage them, commit them, and push them to `origin/main` in the same task unless the user explicitly says not to.
- Do not create, switch to, suggest, or use side branches, feature branches, PR branches, or a `dev` branch.
- Do not open or suggest pull requests for routine work in this repository.
- Only use a non-`main` branch or a PR workflow if the user explicitly asks for it in that specific task.
- For risky, creative, or parallel agent work, use a detached sandbox worktree via `tools/New-AgentSandbox.ps1`; do not create side branches or commit/push from the sandbox. See `docs/agent-sandbox-workflow.md`.

## origin/main Is Source Of Truth — Stale-Local-`main` Trap (READ BEFORE ANY COMMIT)
- `origin/main` is the canonical, authoritative tree. The remote always wins over a local snapshot.
- Cloud / remote-execution containers have shipped a STALE local `main` that is an UNRELATED history: no shared merge-base with `origin/main`, a different file layout, and missing source files. Committing onto it and pushing would be rejected — or, if force-pushed, would DESTROY the real `origin/main` history. This has actually happened in this repo; the user describes it as "it gets my data lost."
- Before editing, ALWAYS confirm local `main` really matches `origin/main`:
  - `git fetch --prune`
  - `git rev-list --left-right --count origin/main...main` — expect `0   0`; any large "behind" count or divergence is a red flag.
  - `git merge-base main origin/main` — EMPTY output means UNRELATED histories = the local `main` is a stale/junk snapshot, NOT your real tree.
  - Sanity-check the tree: the app source must exist (e.g. `Transform/Transform/WorkoutGeneratorService.swift`) and the tracked Swift file count should look right (`git ls-files "*.swift" | wc -l` — **118** on 2026-09-11, and it only grows), not a smaller different layout. Treat anything under ~100 as the stale-snapshot smell, not the exact number: this figure said 49 for months while the real tree held 118, so an agent following it literally would have read a CORRECT tree as the junk one. If you update it, run the command first.
- If local `main` is behind, diverged, or unrelated: do NOT commit on it. Re-point onto the real tree first with `git checkout -B main origin/main`, re-verify the source is present, THEN make changes.
- NEVER `git push --force` / `--force-with-lease` to `origin/main`. Push clean fast-forwards only. If a push is non-fast-forward, STOP and reconcile — never overwrite the remote.
- After pushing, confirm it was a fast-forward (`old..new`), not a forced replacement, and that the prior `origin/main` commits are still ancestors.

## Minimal Working Rules
- Work from this repo, not the stale copies.
- Use the shared authenticated GitHub route in `C:\Dev\_Workflow\GITHUB_SYNC_RUNBOOK.md` for every fetch, pull, push, and remote verification. Codex is authorized to run these network Git commands directly from its ordinary terminal, the same as an authenticated Claude Code desktop session.
- GitHub Desktop remains available as an alternative. Whichever route is used, it may run the exact `git fetch --prune`, `git pull --ff-only`, and `git push origin main` commands. Do not treat a GitHub Desktop UI-capture failure as a reason to leave a completed commit unpublished.
- Before running network Git, verify `C:\Dev\Transform_clean`, `main`, the `origin` URL, and a clean/intentional working tree. If the tree is clean, refresh it with fetch then fast-forward-only pull before normal edits. Never force-push, and never overwrite a non-fast-forward remote without reconciling first.
- Push completed repo changes unless the user says not to.
- Do not leave completed repo changes local-only at handoff time.
- If only part of the work is complete, either commit and push the finished subset or explicitly tell the user what is still intentionally local and why.
- Treat local secrets/config files as local-only unless the user explicitly asks to commit them.
- Fix root causes, not cosmetic symptoms.
- Before committing substantial generator changes, stage the intended files and run
  `tools/Invoke-GeneratorSecondAudit.ps1` so the tracked/staged diff receives an independent,
  no-tools Claude Code review. Resolve material
  findings before push. If Claude is unavailable or out of usage credits, say so explicitly and
  perform a separate adversarial audit; never represent an incomplete Claude run as approval.
- Keep workout quality and evidence-informed programming integrity ahead of validator convenience.
- Respect the split `WorkoutGeneratorService` architecture.

## How To Explain Things To The Owner
- The owner is not a programmer. Write every summary, finding, and status update in plain
  everyday language — assume a smart 10-year-old is reading it.
- Say what was broken, what it meant for the app or for him while it was broken, and what is
  different now. Lead with the effect a person would notice, not the mechanism.
- Avoid jargon. If a technical term is genuinely unavoidable, define it in the same sentence in
  ordinary words. Never use these unexplained: race condition, cache, dictionary iteration,
  determinism, refactor, main thread/actor, prefix, regex, validator disposition, O(n), etc.
- Prefer short sentences and everyday comparisons over precise vocabulary. "The app asked the
  same question 30 times instead of once" beats "redundant O(n·m) recomputation".
- Plain language is about VOCABULARY, never about softening the truth. Do not hide or downplay
  a bug's severity, a risk, or something that was not finished or not tested. If the news is
  bad, say it plainly in simple words.
- Keep exact identifiers exact when he may need them: file names, branch names, commands to
  run, and menu items in Xcode. Do not "simplify" those into something that will not work.
- A short list of "what this means for you" is better than a description of how the code works.
  He cares about the app's behavior, his data, and his money (API spend), not the internals.
- This applies to chat summaries and reports. Code comments and commit messages stay technical
  for future maintainers.
- THIS RULE IS PERMANENT AND HAS NO EXCEPTIONS. It applies to every message, including short
  replies, status updates, mid-task asides, and answers to follow-up questions — not just to
  end-of-task summaries. He has had to ask for it more than once; asking again is a failure.

## Never Hand Him A Task Without The Answer
- Do not tell him to "go check" something (CI, a dashboard, a log, a screen) and stop there.
  Go look yourself first with the tools available, then tell him what it says.
- The GitHub Actions results are readable from here via the `mcp__github__*` tools: list the
  workflow runs, read the job logs, download artifacts. Do that instead of delegating it.
- If he must do something himself because no tool here can reach it, then in the same message say:
  the exact place to look, the exact thing to look for, what a good result looks like, what a bad
  result looks like, and what you will do about each. Never assume he knows where a green
  check-mark lives or what it covers.
- Naming a workflow, a file, or a test is not an explanation. Say what it actually proves in
  ordinary words ("this one really builds the app, so it proves the code isn't broken").
- A green check-mark is not automatically good news. Confirm the run actually did work — that
  tests were discovered and executed — before reporting it as a pass.

## Context Discipline
- Read this file first, then only the one repo skill and files needed for the task.
- Do not load all handoff docs by default.
- Prefer targeted searches and small file reads over broad repo sweeps.
- Use `.claude/skills/transform-context-compact` when reviving old work or preparing a handoff.
- Use `repomix` only for external full-repo handoffs, not normal local work.
- Use `docs/agent-sandbox-workflow.md` before isolated AI-agent experiments.

## External Agent Reconciliation
- If the user mentions prior work by another agent today, another machine, another terminal, or another conversation, do not assume the current diff or latest local commit tells the full story.
- Before new edits, rebases, resets, or sync decisions, reconcile external-agent work against the current repo state.
- Ask for or inspect the outside artifact when available, such as a transcript, chat export, commit list, screenshot, or claimed fix summary.
- Compare three things explicitly:
  - what the outside agent claimed to change
  - what exists now in local files and local git history
  - what exists now on `origin/main`
- Report the result in plain terms: present, missing, partially landed, or overwritten.
- If overlap exists, preserve the newer or safer behavior intentionally rather than assuming the most recent diff is the whole truth.
- Do not say the repo is fully assessed or in sync until this reconciliation step is complete when external agent work is part of the context.

## Parallel Audit and Recap
- For broad audits or multi-subsystem tasks, split the work into 2-4 bounded lanes instead of one giant repo sweep.
- Keep one primary agent or session responsible for scoping, synthesis, and final judgment.
- Use parallel helpers only for bounded evidence gathering when the tool supports it; otherwise run the same lanes sequentially.
- Give each lane a narrow question, a small file or artifact scope, and a clear stop condition.
- After each wave, write a quick recap in 4-6 bullets covering what was checked, what was found, what is still uncertain, and the next best move.
- When context, logs, or diffs start ballooning, checkpoint and resume from the recap instead of dragging all raw material forward.
- Use `.claude/skills/transform-parallel-audit` when a task spans multiple subsystems or risks context sprawl.

## Design Research
- For substantial UI or UX work, automatically apply `transform-design-research` before implementation.
- Trigger it for screen redesigns, new flows, onboarding, dashboards, progress or analytics experiences, navigation changes, design-system decisions, accessibility reviews, or requests for a clearer, more polished, premium, cohesive, or native feel.
- Do not invoke the full research workflow for tiny copy, spacing, or isolated visual bug fixes unless they expose a broader design problem.
- Use external references to extract principles, not to copy screens or import web conventions into SwiftUI.
- Implement the resulting direction directly with native SwiftUI and the app's `DesignSystem.swift` tokens; validation is the owner's device build, never the simulator.

## Skill-First Workflow
- In this repo, treat the repo-local skills as the default operating path, not an optional extra.
- Use the matching repo skill automatically when the task clearly fits, unless the user explicitly overrides that choice.
- At the start of a fresh session in `C:\Dev\Transform_clean`, first apply `transform-handoff` unless the task is already deep in a single known file.
- If resuming prior work, long threads, generator investigations, or mixed context, apply `transform-context-compact` before broader repo exploration.
- For broad reviews, mixed evidence gathering, architecture tradeoff work, or repo investigations likely to sprawl, apply `transform-parallel-audit`.
- For substantial UI/UX design, redesign, new-flow, or visual-system work, automatically apply `transform-design-research`.
- For generator, validator, blueprint, fallback, retry, or API-cost work, automatically apply `transform-generator-audit`.
- For GitHub Actions, Xcode build, scheme, workflow, or local-vs-CI mismatch work, automatically apply `transform-ci-triage`.
- Before re-designing, reverting, or "simplifying" behavior that looks odd (archiving rules, canonical keys, menu-locked generation, backup logic), automatically apply `transform-failure-archaeology` — the odd behavior may be a scar from a past incident.
- For any change touching exercise naming, canonical keys, progression/weight history, persistence, migration, or backup code, automatically apply `transform-data-safety`.
- If more than one repo skill could apply, prefer the smallest combination that fits the task instead of loading everything.
- Do not wait for the user to explicitly name these skills when the task clearly matches them.
- If the user explicitly names a repo skill, follow that request unless it conflicts with a higher-priority instruction.

## Repo Skills
- `transform-handoff`: repo orientation, stale-copy warnings, branch workflow, hotspots.
- `transform-parallel-audit`: bounded parallel or sequential evidence gathering with compact recaps and final synthesis.
- `transform-design-research`: focused product-reference research, native iOS design synthesis, implementation, and owner device-validation handoff.
- `transform-generator-audit`: workout generator, validator, fallback, prompt drift, retry waste.
- `transform-ci-triage`: GitHub Actions, Xcode build mismatch, workflow drift.
- `transform-context-compact`: compact summaries, selective context loading, low-token handoffs.
- `transform-failure-archaeology`: past incidents, root causes, and do-not-refight doctrine with commit references.
- `transform-data-safety`: guard rails for exercise naming, progression continuity, persistence, and backup code paths.
- Full index, trigger matrix, and maintenance protocol: `.claude/skills/README.md`.

## Read Deeper Only When Needed
- `docs/2_PROJECT_HANDOFF.md`
- `docs/3_TRANSFORM_CLEAN_HANDOFF.md`
- `docs/EXTERNAL_AGENT_RECONCILIATION.md`
- `Transform/Transform/CLAUDE.md`
- `Transform/Transform/EvidenceProfile.md`

## Validation Reality
- Windows / Linux / cloud containers are fine for git, file inspection, and framework-light Swift smoke checks. They CANNOT build this iOS app (no Xcode), so agents in those environments must make changes that are correct-by-inspection and compile-safe, then hand off to the owner for the real build.
- The owner's validation workflow is: build in Xcode and run on a physical iPhone. This is the source of truth for "does it work."
- Do NOT suggest, recommend, or wait on the iOS Simulator. The owner intentionally does not use it (slow to load, and it can't exercise haptics, the camera/body-analysis flow, or true on-device feel). Device testing is the correct and preferred path — treat it as such, not as a fallback.
- When an agent cannot compile, say exactly that ("I can't build here; this is correct-by-inspection — build & run on your iPhone to confirm") instead of pointing at the simulator.
