import Foundation

/// A validator finding, translated for the person training rather than for the model.
///
/// The raw strings produced in `WorkoutGeneratorService+ParsingValidation.swift` are written as
/// instructions TO CLAUDE. They carry rule IDs ("BASE-001"), internal vocabulary ("weighted
/// stimulus target", "direct-set target", "Pre-Selected Exercise Menu") and imperatives aimed at
/// a generator ("Trim redundant filler instead of stacking volume", "rewrite with an
/// analysis-anchored intent line"). Rendering them verbatim in the Workout tab put engineering
/// diagnostics in a product surface and asked the owner to act on sentences that were never
/// addressed to them.
///
/// Those strings must not change: `validationDisposition` decides retry-vs-warn by matching
/// their substrings, and `correctionTactics` feeds them straight back into the correction
/// prompt. So the translation lives here, at the presentation boundary, and never by editing
/// the validator's own text.
///
/// Matching deliberately uses the same substrings `validationDisposition` keys off, so a
/// validator message that changes shape degrades to the explicitly-unclassified notice instead
/// of silently showing the wrong explanation. That fallback must never reassure: an unmatched
/// finding is one this code could not read, not one it has judged harmless.
struct WorkoutValidatorNotice: Identifiable {

    /// How much the finding should actually intrude on someone about to train.
    enum Severity: Int, Comparable {
        /// The week is sound; this records a trade-off the planner made.
        case tuning = 0
        /// Worth knowing before training, but the week is still safe to run.
        case headsUp = 1
        /// Something the owner should look at — recovery risk, a coverage hole, or advice
        /// that disagrees with their own logged history.
        case attention = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// `var` so a severity upgrade during grouping can carry the existing row's identity
    /// forward. Rebuilding with a fresh UUID re-mounts that row in `ForEach`.
    var id = UUID()
    let severity: Severity
    let headline: String
    let detail: String
    /// Kept so identical findings can be grouped, and so diagnostics can still recover the
    /// original text without it being rendered.
    let rawIssue: String
    /// How many raw findings collapsed into this notice.
    var occurrences: Int = 1

    var displayHeadline: String {
        occurrences > 1 ? "\(headline) (\(occurrences))" : headline
    }
}

extension WorkoutValidatorNotice {

    /// Translate the newline-joined `WorkoutProgram.validatorWarnings` blob into notices,
    /// collapsing repeats (the same complaint about four different exercises is one thing to
    /// tell someone, not four).
    static func notices(fromWarningsText text: String) -> [WorkoutValidatorNotice] {
        let rawIssues = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return notices(from: rawIssues)
    }

    static func notices(from rawIssues: [String]) -> [WorkoutValidatorNotice] {
        var ordered: [WorkoutValidatorNotice] = []
        var indexByHeadline: [String: Int] = [:]

        for issue in rawIssues {
            let notice = translate(issue)
            if let existing = indexByHeadline[notice.headline] {
                ordered[existing].occurrences += 1
                // Keep the highest severity seen for a shared headline.
                if notice.severity > ordered[existing].severity {
                    ordered[existing] = WorkoutValidatorNotice(
                        id: ordered[existing].id,
                        severity: notice.severity,
                        headline: notice.headline,
                        detail: notice.detail,
                        rawIssue: notice.rawIssue,
                        occurrences: ordered[existing].occurrences
                    )
                }
            } else {
                indexByHeadline[notice.headline] = ordered.count
                ordered.append(notice)
            }
        }

        return ordered.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.headline < rhs.headline
        }
    }

    /// Worst severity present, for the collapsed banner label.
    static func summarySeverity(for notices: [WorkoutValidatorNotice]) -> Severity {
        notices.map(\.severity).max() ?? .tuning
    }

    // MARK: - Translation

    // swiftlint:disable:next cyclomatic_complexity
    private static func translate(_ issue: String) -> WorkoutValidatorNotice {
        let subject = quotedSubject(in: issue)
        let ratio = ratioValues(in: issue)
        let day = dayNumber(in: issue)

        func notice(_ severity: Severity, _ headline: String, _ detail: String) -> WorkoutValidatorNotice {
            WorkoutValidatorNotice(
                severity: severity,
                headline: headline,
                detail: detail,
                rawIssue: issue
            )
        }

        // --- Coverage holes and recovery risk: the findings worth interrupting someone for ---

        if issue.contains("receives zero direct sets this week") {
            return notice(
                .attention,
                "\(subject ?? "A muscle group") has no direct work this week",
                "Every major muscle should get at least a light weekly dose, even when it isn't a focus. Consider regenerating, or add a couple of sets yourself."
            )
        }

        if issue.contains("contradicts the app's logged progression verdict") {
            return notice(
                .attention,
                "A coaching note disagrees with your logged history",
                "One exercise's written cue points a different way than the progression suggestion the app calculated from your actual logs. Trust the app's suggestion on the exercise screen."
            )
        }

        if issue.contains("severely overshot its direct-set target") {
            return notice(
                .attention,
                "\(subject ?? "A priority muscle") is carrying far more volume than planned",
                ratio.map {
                    "About \(trim($0.actual)) hard sets against a target of \(trim($0.target)). That is above what the recovery budget supports — cut the least important sets if the week feels crushing."
                } ?? "Weekly volume is well above the planned range. Cut the least important sets if the week feels crushing."
            )
        }

        // Substitution findings name the lift: which one changed is the whole actionable part,
        // and keeping it in the headline also stops two unrelated swaps collapsing into one row.
        if issue.contains("substitution significantly increases shoulder risk") {
            return notice(
                .attention,
                subject.map { "\($0) was swapped for something harder on the shoulder" }
                    ?? "A swapped exercise is harder on the shoulder",
                "The replacement puts more demand on the shoulder than the lift it replaced. Warm up thoroughly, and swap back if it aggravates anything."
            )
        }

        // --- Worth knowing, still safe to train ---

        // Joint-load findings. These reach the banner via the procedural fallback (which
        // reports its own issues unfiltered), so they need real copy even though the AI path
        // would normally spend a correction pass on them.
        if issue.contains("excessive shoulder joint stress")
            || issue.contains("excessive elbow joint stress")
            || issue.contains("excessive lower-back stress")
            || issue.contains("excessive knee joint stress")
            || issue.contains("uses shoulder-intensive pressing on an Arms/Lateral focus day") {
            let joint: String
            if issue.contains("shoulder") { joint = "the shoulders" }
            else if issue.contains("elbow") { joint = "the elbows" }
            else if issue.contains("lower-back") { joint = "the lower back" }
            else { joint = "the knees" }
            return notice(
                .headsUp,
                day.map { "Day \($0) is demanding on \(joint)" } ?? "One session is demanding on \(joint)",
                "Several movements in that session load the same joint. Warm up thoroughly and drop the last exposure if anything feels off."
            )
        }

        // Kept OUT of the generic notes-vs-programming branch below on purpose. That branch's
        // advice is "follow the exercise list rather than the note", which is right when the
        // mismatch is cosmetic — and wrong here, because the note's claim is a SAFETY claim the
        // programming contradicts. Telling someone with a flagged shoulder to disregard the
        // shoulder-friendly framing and just run the lifts is the one case where that guidance
        // inverts. This finding can fire without the impingement or joint-stress rules also
        // tripping, so it has to carry its own caution.
        if issue.contains("notes describe a shoulder-friendly") {
            return notice(
                .headsUp,
                "A session is described as shoulder-friendly but isn't",
                "The written note frames that day as easy on the shoulder while the actual lifts don't back that up. Treat it as a normal pressing/pulling day: warm the cuff up properly and regress anything that pinches."
            )
        }

        // Anchor moved with the rule: it now fires for any flagged shoulder risk, not only
        // impingement, so the copy must not tell someone with anterior shoulder pain that their
        // analysis said "impingement" when it did not.
        if issue.contains("is not clearly adapted to the shoulder risk") {
            return notice(
                .attention,
                "A session isn't clearly adapted to your shoulder notes",
                "Your analysis flagged a shoulder problem, but this day's overhead pressing and prep don't obviously work around it. Warm the shoulder up properly, and stop short of anything that pinches rather than pushing through it."
            )
        }

        if issue.contains("session budget") {
            return notice(
                .headsUp,
                day.map { "Day \($0) will likely run long" } ?? "One session will likely run long",
                "Estimated time for that day is over its planned budget. Trim the last accessory if you're short on time."
            )
        }

        if issue.contains("exceeds the maintenance weekly volume ceiling") {
            return notice(
                .headsUp,
                "\(subject ?? "A non-priority muscle") is getting more work than it needs",
                "This isn't a focus muscle this block, so the extra sets spend recovery that could go to your priorities."
            )
        }

        // The FLOOR, which had no notice at all while its ceiling twin above did. That gap was
        // not theoretical: the maintenance-floor finding was the single validator result of a
        // real Week 1, and with nothing to match it the owner was shown "A plan check didn't
        // pass … isn't recognized well enough to explain here" for the only thing his week had
        // to say. `.attention` rather than `.headsUp` because a muscle under its floor is a
        // genuine coverage hole, and the shortfall is in exercise SLOTS, which no amount of
        // training harder on the day repairs.
        if issue.contains("falls below the maintenance weekly volume floor") {
            return notice(
                .attention,
                "\(subject ?? "A non-priority muscle") is getting too little work this week",
                "It only has one exercise in the whole week, and one exercise can't hold enough sets to keep a muscle where it is. It needs a second movement on another day, not more sets on the one it has."
            )
        }

        // GAP 1 (2026-09-04 coverage audit): a single-set (or otherwise below-role-floor)
        // exercise, e.g. the owner's shipped Cable Crunch at one set. `.attention` because this
        // is a genuine under-dosing of one movement — one or two sets below the app's own floor
        // for that role — not a trade-off the planner chose on purpose.
        if issue.contains("below its role-based minimum of") {
            return notice(
                .attention,
                day.map { "Day \($0) has an exercise with fewer sets than the app's own minimum" }
                    ?? "An exercise has fewer sets than the app's own minimum",
                "One movement is prescribed below the lowest set count the app considers worth doing for its role. Add a set or two yourself, or treat it as a warm-up rather than a working exercise."
            )
        }

        if issue.contains("no horizontal pull at all") {
            return notice(
                .attention,
                "Your back work is all overhead pulling",
                "Every back movement this week pulls down from above, like a pulldown or pull-up. Those don't train the muscles between your shoulder blades in their shortened position — that takes a rowing movement."
            )
        }

        if issue.contains("overhead-pulling sets against only") {
            return notice(
                .attention,
                "Your back work is mostly overhead pulling",
                "There's more than twice as much pulling-down work as rowing this week. One short row doesn't balance it — the muscles between your shoulder blades need rowing volume closer to the pulldown volume."
            )
        }

        if issue.contains("overshot its direct-set target enough to create avoidable fatigue") {
            return notice(
                .headsUp,
                "\(subject ?? "A priority muscle") is above its planned volume",
                ratio.map {
                    "\(trim($0.actual)) hard sets against a target of \(trim($0.target)). Productive, but it costs recovery elsewhere."
                } ?? "Slightly more weekly volume than planned. Productive, but it costs recovery elsewhere."
            )
        }

        if issue.contains("exceeds its focus-day direct-set cap")
            || issue.contains("exceeds its per-session direct-set cap")
            || issue.contains("is concentrated into overly fatiguing sessions") {
            return notice(
                .headsUp,
                "\(subject ?? "One muscle")'s work is stacked into too few sessions",
                day.map { "Day \($0) carries more of it than one session trains well. Later sets there will be the least productive of the week." }
                    ?? "More of it lands in a single session than that session trains well. The last sets there will be the least productive."
            )
        }

        if issue.contains("carries too much total fatigue load") {
            return notice(
                .headsUp,
                day.map { "Day \($0) is a heavy session" } ?? "One session is unusually heavy",
                "Total workload for that day is above the threshold the planner allows. Expect it to run long and leave more fatigue than the other days."
            )
        }

        if issue.contains("did not follow the Pre-Selected Exercise Menu") {
            return notice(
                .headsUp,
                "A day's exercises differ from the plan",
                day.map { "Day \($0) didn't come back with the exact lifts and set counts the planner locked in. The sets shown are still the planned ones." }
                    ?? "One day didn't come back with the exact lifts and set counts the planner locked in. The sets shown are still the planned ones."
            )
        }

        // Both fragments are quoted from the real messages `validateSubstituteQuality`
        // emits. A third clause here matched "was replaced with a poor substitute", a
        // phrase NO emitter has ever produced — it read like coverage and was worth
        // nothing. Anything added here must be pasted from an actual emitted string.
        if issue.contains("substitution changes the primary muscle target")
            || issue.contains("substitution significantly increases fatigue") {
            return notice(
                .headsUp,
                subject.map { "\($0) was swapped for a loose match" }
                    ?? "A swapped exercise isn't a close match",
                "The replacement trains something different, or costs more fatigue, than the lift it replaced. Worth swapping back if you were progressing on the original."
            )
        }

        // --- Trade-offs the planner made; the week is sound ---

        if issue.contains("missed its direct-set target") {
            return notice(
                .tuning,
                "\(subject ?? "A priority muscle") came in under its volume target",
                ratio.map {
                    "\(trim($0.actual)) hard sets against a target of \(trim($0.target))."
                } ?? "Slightly less weekly volume than targeted."
            )
        }

        if issue.contains("missed its frequency target") {
            return notice(
                .tuning,
                "\(subject ?? "A priority muscle") is trained on fewer days than planned",
                "Spreading the same volume across more sessions is usually slightly better for growth."
            )
        }

        // GAP 3 (2026-09-04 coverage audit): the opposite miss — a priority spread across
        // materially MORE days than planned (the owner's Core/Abs shipped on 3 days against a
        // plan of 1). `.tuning` because extra frequency at the same weekly volume is usually
        // neutral-to-good for growth, not a risk; this exists so the owner can see the plan
        // changed shape, not to raise an alarm.
        if issue.contains("overshot its frequency target") {
            return notice(
                .tuning,
                "\(subject ?? "A priority muscle") is trained on more days than planned",
                "It showed up in more sessions than the plan called for. That usually isn't a problem — more frequent, smaller doses is often fine for growth — but it means the week's shape drifted from what was planned."
            )
        }

        if issue.contains("minimum viable stimulus threshold") {
            return notice(
                .tuning,
                "One of \(subject ?? "a priority muscle")'s sessions is light",
                "It appears on the planned number of days, but one of those exposures is small enough that it counts for less than a full session."
            )
        }

        if issue.contains("undershot its targeted exercise-slot goal") {
            return notice(
                .tuning,
                "\(subject ?? "A priority muscle") uses fewer exercises than planned",
                "The volume is there; it's just delivered through fewer movements. Usually fine, and often better for tracking progress."
            )
        }

        if issue.contains("undershot its weighted stimulus target") {
            return notice(
                .tuning,
                "\(subject ?? "A priority muscle") gets slightly less total stimulus than targeted",
                "Counts both direct and indirect work. A small shortfall here rarely changes results."
            )
        }

        if issue.contains("uses too many weekly exercise variations") {
            return notice(
                .tuning,
                "\(subject ?? "A priority muscle") rotates through a lot of exercises",
                "Repeating the same main lifts week to week makes progress easier to see. Variety is better saved for the next block."
            )
        }

        if issue.contains("never includes a prime")
            || issue.contains("spends too many") {
            return notice(
                .tuning,
                "A focus day leans on support work",
                "One session targets its focus muscle mostly through assistance movements rather than a main growth lift."
            )
        }

        if issue.contains("was planned for") {
            return notice(
                .tuning,
                "A focus day has fewer movements for its focus than planned",
                "Fewer exercises clearly serve that day's emphasis than intended, and the direct volume there landed light."
            )
        }

        // MUST precede the day-composition branch below. "Day N includes low-value filler
        // that does not clearly support the X theme…" contains BOTH "low-value filler" and
        // "does not clearly support"; the latter also legitimately belongs to the emphasis
        // branch (a different message uses it), so ordering — not pattern removal — is what
        // routes each one correctly.
        if issue.contains("stacks too many")
            || issue.contains("Trim redundant focus work")
            || issue.contains("low-value filler")
            || issue.contains("too crowded for a fatigue-managed") {
            return notice(
                .tuning,
                day.map { "Day \($0) has some overlapping work" } ?? "One day has some overlapping work",
                "Several movements in that session train the same thing in the same way. The later ones add fatigue more than stimulus."
            )
        }

        // GAP 4 (2026-09-04 coverage audit): blueprint day-SHAPE violations from
        // `validateDayPlans` that used to carry no copy at all and no disposition — a planned
        // rest day silently becoming a training day (a real recovery-budget risk) rendered as
        // the generic "isn't recognized well enough to explain here" fallback. All three must
        // stay ahead of the generic day-composition branch below, since none of their wording
        // overlaps it.
        if issue.contains("turned it into a training session.") {
            return notice(
                .attention,
                day.map { "Day \($0) was supposed to be a rest day" } ?? "A planned rest day became a training day",
                "This day was built for recovery, but the plan turned it into a training session instead. Consider treating it as a rest day yourself, or regenerate the week."
            )
        }

        if issue.contains("generated output made it a rest day.") {
            return notice(
                .headsUp,
                day.map { "Day \($0) was supposed to be a training day" } ?? "A planned training day became a rest day",
                "The plan called for a real workout here, but this day came back empty. You're getting less training this week than intended — regenerating may fix it."
            )
        }

        if issue.contains("is missing from the generated output.") {
            return notice(
                .attention,
                "A planned day didn't come back at all",
                "One of your training days wasn't in what the plan produced. This is a system hiccup, not something you did — regenerate the week."
            )
        }

        // Day-composition findings from `validateDayPlans` (MetadataProfiles). These reach the
        // banner through the menu-locked demotion path, so they need real copy rather than the
        // unclassified fallback. They all say the same thing to a lifter: the session is fine,
        // but its shape doesn't match the emphasis it was planned for.
        if issue.contains("was supposed to emphasize")
            || issue.contains("is supposed to emphasize quads")
            || issue.contains("does not clearly support")
            || issue.contains("reads as a broad lower-body session") {
            return notice(
                .tuning,
                day.map { "Day \($0) doesn't fully match its planned emphasis" }
                    ?? "A day doesn't fully match its planned emphasis",
                "The session is safe and productive; it just leans less on the muscle it was built around than intended."
            )
        }

        if issue.contains("the generated day reads as") {
            return notice(
                .tuning,
                "A session came back as a different split than planned",
                "One day was planned as one training style and reads more like another. The work is still coherent — the week just isn't split quite the way the blueprint laid out."
            )
        }

        if issue.contains("opens its") {
            return notice(
                .tuning,
                day.map { "Day \($0) leads with support work" } ?? "A day leads with support work",
                "The main growth movement sits behind lighter prep work. Doing the primary lift while you're freshest gets more out of it."
            )
        }

        if issue.contains("Too few anchor lifts carried over") {
            return notice(
                .tuning,
                "Fewer main lifts carried over from last week",
                "Keeping one or two anchor lifts per day makes week-to-week progress easier to compare."
            )
        }

        if issue.contains("notes claim")
            || issue.contains("notes contradict the actual programming")
            || issue.contains("notes describe a low-fatigue")
            || issue.contains("session notes talk about") {
            return notice(
                .tuning,
                "A session note describes something the session doesn't do",
                "The written briefing for one day mentions work that isn't actually in it. Follow the exercise list rather than the note."
            )
        }

        if issue.contains("one identical rest prescription")
            || issue.contains("one identical tempo prescription") {
            return notice(
                .tuning,
                "One session reuses the same rest or tempo throughout",
                "Compounds and isolation work usually want different rest and cadence. Give the heavy lifts longer rests than the accessories."
            )
        }

        if issue.contains("already reached its weekly target") {
            return notice(
                .tuning,
                "\(subject ?? "A muscle") picks up work after hitting its weekly target",
                "Extra sets landed on it later in the week. Not harmful, but those sets buy less than they cost."
            )
        }

        if issue.contains("session notes are generic")
            || issue.contains("session notes are empty or too short")
            || issue.contains("notes are empty or too short")
            || issue.contains("notes do not include a concrete progression cue") {
            return notice(
                .tuning,
                "Some coaching notes are thin",
                "A few sessions or exercises came back with shorter write-ups than usual. The programming itself is unaffected."
            )
        }

        // The last finding in the four severity lists that had no copy. It matters more than most:
        // `Transform/Transform/CLAUDE.md` names "prime hypertrophy work must not be replaced in
        // practice by corrective or support work" as a top standard, and this is the rule that
        // detects exactly that. Under menu lock it is demoted to a warning on purpose — the AI is
        // forbidden to swap the exercise — so the owner reading the warning is the ONLY place this
        // finding can do any good, and until now it read as "isn't recognized well enough to
        // explain here."
        if containsAnyFragment(issue, [
            "never includes a prime hypertrophy movement",
            "but never includes a prime"
        ]) {
            return notice(
                .attention,
                day.map { "Day \($0) has no main lift for the muscle it targets" }
                    ?? "A day has no main lift for the muscle it targets",
                "That session is built around a muscle but only contains smaller support work for it — nothing heavy enough to be the main driver. The volume is there; the growth stimulus is thinner than the plan intends."
            )
        }

        // --- Structural malformation: the response is not a usable week ---
        //
        // Nineteen of the twenty-five entries in `lockedMenuHardFailurePatterns` had no copy at
        // all, so every one of them reached the owner as "A plan check didn't pass … isn't
        // recognized well enough to explain here." These are reachable in production: the
        // procedural fallback reports its own issues unfiltered, so a fault in the deterministic
        // builder surfaces here rather than being caught upstream.
        //
        // Grouped rather than written out nineteen times, because the owner's takeaway is the same
        // within each group and nineteen near-identical rows would be worse than one clear one.
        // Grouping is by what the person can actually do about it, not by which function emitted it.
        if containsAnyFragment(issue, [
            "Must contain exactly 7 days.",
            "dayNumber values must exactly match",
            "Duplicate dayNumber values found.",
            "Training days must be between 4 and 6.",
            "Rest days must be between 1 and 3.",
            "daysPerWeek should be between 4 and 6.",
            "All days are rest days.",
            "is rest day but has exercises.",
            "Blueprint calls for"
        ]) {
            return notice(
                .attention,
                "The week came back the wrong shape",
                "The plan didn't have the right number of training and rest days, so the app rebuilt it from its own template instead. The training is sound; it just isn't the AI's version. Regenerating usually fixes it."
            )
        }

        if containsAnyFragment(issue, [
            "must have 5-8 exercises.",
            "Total training exercises are too low."
        ]) {
            return notice(
                .attention,
                "A day came back with too few exercises",
                "One session had too little in it to be a real workout, so the app rebuilt the week from its own template. Regenerating usually fixes it."
            )
        }

        if containsAnyFragment(issue, [
            "has invalid sets.",
            "has invalid restSeconds."
        ]) {
            return notice(
                .attention,
                "An exercise came back with impossible numbers",
                "A lift was written with a set count or rest time outside anything sensible, so the app rebuilt the week rather than hand you those numbers."
            )
        }

        if containsAnyFragment(issue, [
            "has empty dayName.",
            "has an exercise with empty exerciseName.",
            "has empty reps.",
            "programName is empty.",
            "programSummary is empty.",
            "weekSummary is empty."
        ]) {
            return notice(
                .headsUp,
                "Part of the plan came back blank",
                "A name, a rep range or a summary was missing from the AI's response, so the app rebuilt the week from its own template. Nothing about the training itself is unsafe."
            )
        }

        // Effort-field findings. None of these had copy before — including the pre-existing
        // "is missing targetRIR", which meant the owner saw the unrecognised fallback for a
        // finding the app had understood perfectly well. Found by the disposition sweep.
        if issue.contains("has an out-of-range targetRIR") {
            return notice(
                .headsUp,
                "An exercise has a nonsense effort number",
                "Every exercise carries a target for how many reps you should have left in the tank. This one came back with a value that isn't usable. Judge that lift by feel and leave a couple of reps in reserve."
            )
        }

        if issue.contains("on a Restricted-recovery week") {
            return notice(
                .attention,
                "An accessory is prescribed too close to failure for this week",
                "Your logged sleep put this week in the most restricted recovery band, where the smaller isolation work is meant to be taken further from failure — not harder. Back that exercise off by a rep or two rather than grinding it out."
            )
        }

        if issue.contains("is missing targetRIR") {
            return notice(
                .tuning,
                "An exercise didn't say how hard to push",
                "The coach left out the how-close-to-failure target for one lift. Nothing is wrong with the rest of the plan — leave about two reps in the tank on that exercise."
            )
        }

        if issue.contains("notes contain load/rep progression instructions") {
            return notice(
                .tuning,
                "A note repeated progression advice",
                "Load and rep progression comes from your logged sets and is shown on the exercise screen. A written cue duplicating it was flagged so the two can't disagree."
            )
        }

        if issue.contains("rep bands in one week") {
            return notice(
                .tuning,
                "A rep range jumped further than usual",
                "One exercise moved a long way in one week — for example from heavy sets of 6-8 straight to light sets of 15-20. Your weight was adjusted to match, so nothing is wrong with the plan; a smaller step would build more strength."
            )
        }

        // Unrecognized shape. This branch means the finding is UNCLASSIFIED, not benign — a
        // reworded or newly added validator message lands here, and one of those could just as
        // easily deserve `.attention`. So say only what is actually known and send the owner to
        // the raw text. Never reassure about a check this code could not read.
        return notice(
            .tuning,
            "A plan check didn't pass",
            "This one isn't recognized well enough to explain here. Open the Generator Lab to read the validator's own wording before training."
        )
    }

    // MARK: - Extraction helpers

    /// First single-quoted term — the muscle group, priority, or exercise the finding is about.
    ///
    /// Anchored rather than scanning for a bare `'`, because validator prose contains
    /// contractions ("the app's logged progression verdict", "doesn't"). A naive first-quote
    /// scan would open on the apostrophe in `app's` and return everything up to the next one.
    /// Requiring the opening quote to follow whitespace or start-of-string, and the closing
    /// quote to be followed by punctuation/whitespace/end, means a term is only extracted when
    /// it really is quoted.
    /// Whether `issue` carries any of `fragments`. Mirrors `matchesValidationIssue` in the
    /// validator so the two stay conceptually identical: plain substring containment, no
    /// normalisation, no regular expressions.
    private static func containsAnyFragment(_ issue: String, _ fragments: [String]) -> Bool {
        fragments.contains { issue.contains($0) }
    }

    private static func quotedSubject(in issue: String) -> String? {
        guard let range = issue.range(
            of: #"(?:^|\s)'([^']{1,60})'(?=[\s.,:;!?]|$)"#,
            options: .regularExpression
        ) else { return nil }
        let value = issue[range]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            .trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// First `(actual/target)` pair, which the volume findings all use.
    private static func ratioValues(in issue: String) -> (actual: Double, target: Double)? {
        guard let range = issue.range(
            of: #"\((\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)\)"#,
            options: .regularExpression
        ) else { return nil }
        let inner = issue[range].dropFirst().dropLast()
        let parts = inner.split(separator: "/")
        guard parts.count == 2,
              let actual = Double(parts[0]),
              let target = Double(parts[1]) else { return nil }
        return (actual, target)
    }

    /// Case-insensitive on purpose: findings open with "Day 3 …" but the per-session cap
    /// message says "… cap on day 5 (…)" mid-sentence. Requiring digits after the word keeps
    /// "focus-day direct-set cap" from matching.
    ///
    /// "Blueprint day N" is deliberately NOT extracted. That N is `ProgramDayPlan.dayIndex`, a
    /// 1-based index WITHIN the week — the real day number is `dayStart + dayIndex - 1`, so in
    /// week 3 "Blueprint day 2" is the user's Day 16. The two only coincide in week 1. Showing
    /// the blueprint index as a day number would point the owner at the wrong session, so these
    /// findings render without one.
    private static func dayNumber(in issue: String) -> Int? {
        guard !issue.localizedCaseInsensitiveContains("blueprint day") else { return nil }
        guard let range = issue.range(
            of: #"\bday (\d+)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let digits = issue[range].filter(\.isNumber)
        return Int(digits)
    }

    /// Drop a trailing ".0" so "8.0 hard sets" reads as "8 hard sets".
    private static func trim(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
