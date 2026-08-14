import Foundation

/// The phrases that must never appear in an exercise coaching note, in one place.
///
/// WHY THIS EXISTS
/// ---------------
/// These fragments were written out three separate times — in the validator
/// (`notesContainProgressionInstruction`), in the display filter (`coachingSentences`), and in
/// `CoachingVoiceAudit`, which existed to check cue content against the other two. Copies of a
/// rule do not stay equal. `CoachingVoiceAudit` had drifted to hold only the display list, so
/// six validator fragments went unchecked and any consumer trusting it as its safety net could
/// emit a string that passed the audit and HARD-FAILED generation — discarding a paid AI week.
///
/// The lists are genuinely different rules with different consequences, so they stay separate
/// constants; what they no longer are is retyped. Anything that needs "all of it" composes
/// `all` rather than maintaining a fourth copy.
///
/// SEVERITY, HIGHEST FIRST
/// -----------------------
/// * `validatorBanned` — a HARD generation failure. The whole paid AI week is discarded and
///   the procedural generator takes over. The most expensive string in the app.
/// * `progressionOwnedByBanner` — the sentence is silently deleted from the card, because the
///   deterministic progression banner is the single voice that owns load and rep advice.
/// * `sessionRecap` — silently deleted; the Last panel already says what you did.
/// * `deloadContext` — silently deleted on a deload day; effort ships as the structured
///   `targetRIR` field, and the bare word "deload" anywhere in a note also flips the whole
///   card into deload context.
enum ProgressionProseFragments {

    /// Banned outright by the validator. A note containing any of these fails generation.
    static let validatorBanned: [String] = [
        "next session", "next week", "add load", "add weight", "increase to",
        "add reps", "add a rep", "add one rep", "add 1 rep", "when you clear",
        "beat last week", "before increasing load", "before adding load",
        "progression target", "deload target", "baseline target"
    ]

    /// Load/rep advice the structured progression banner owns. Stripped from the card when a
    /// banner is present, so a note carrying these renders shorter than it reads in storage.
    static let progressionOwnedByBanner: [String] = [
        "next session", "add load", "add weight", "add reps", "before adding",
        "before loading", "progression", "progress load", "hold load", "increase to",
        "ankle weight", "add a dumbbell", "add a rep", "stack step",
        "barbell step", "reliably progress", "when you clear", "add a plate",
        "external load", "next week add",
        "move up to", "go up to", "go heavier", "bump the load", "bump to", "chase reps"
    ]

    /// Narrating the previous session. Always stripped — the Last panel and the badge already
    /// show it.
    static let sessionRecap: [String] = [
        "you logged", "you used", "your last session", "last time you", "you beat"
    ]

    /// Stripped on a deload day.
    static let deloadContext: [String] = [
        "deload", "10%", "under your last", "leave 2", "leave 3", "reserve",
        "chase pr", "prs", "personal record"
    ]

    /// Everything, de-duplicated. What a cue must clear to be safe on every path.
    static let all: [String] = {
        Array(Set(validatorBanned + progressionOwnedByBanner + sessionRecap + deloadContext)).sorted()
    }()
}
