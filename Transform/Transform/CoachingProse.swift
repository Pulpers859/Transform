import Foundation

/// Prose primitives shared by the paths that JUDGE coaching text.
///
/// WHY THIS EXISTS
/// ---------------
/// Two independent consumers were each doing their own string handling on the same coaching
/// notes, and each had a defect the other did not:
///
/// * The validator matched banned fragments as raw substrings, so `"increase to"` fired on
///   `"increase total time under tension"` — and that path discards a paid AI week.
/// * Both the validator and the card split notes into sentences on every `.`, including the
///   one inside `22.5`. The card could render `"Work at 22."` as the prescription, and the
///   validator's `hold ... <number> lb` contradiction patterns could never match a decimal
///   load at all, so half-pound and 2.5 lb increments were invisible to the check.
///
/// `ProgressionProseFragments` already made the fragment LISTS single-source. This does the
/// same for the two operations performed on them.
enum CoachingProse {

    /// Where a session note stops being a briefing and starts being a warm-up checklist.
    ///
    /// One list, because two consumers depend on cutting at the SAME place: the card renders the
    /// briefing and the checklist as separate blocks, and the validator polices the briefing for
    /// load instructions while deliberately leaving the checklist alone (ramping load is what a
    /// warm-up is). If these drifted apart the validator would start policing text the lifter
    /// never reads as a briefing.
    static let warmupSectionMarkers = [
        "Warm-up checklist:", "Warm up checklist:", "Warm-up:", "Warm up:",
        "Mobility/activation:", "Mobility:", "Activation:", "Prime with:"
    ]

    /// True when `phrase` appears in `text` as a whole phrase rather than as the prefix of a
    /// longer word.
    ///
    /// A trailing plural "s" is still the same phrase ("progression targets" matches
    /// "progression target"), because the alternative — demanding an exact boundary — would
    /// quietly stop banning phrasings that are unambiguously the banned thing.
    ///
    /// Callers pass already-normalized (lowercased, diacritic-folded) text; this does not
    /// normalize, so that the caller keeps ownership of what "the same string" means.
    static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        guard !phrase.isEmpty else { return false }

        var searchStart = text.startIndex
        while let range = text.range(of: phrase, range: searchStart..<text.endIndex) {
            if isBoundedStart(of: range, in: text) && isBoundedEnd(of: range, in: text) {
                return true
            }
            // Advance by ONE character, not past the whole match: overlapping occurrences are
            // possible and a later one may be properly bounded even when this one is not.
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    static func containsAnyPhrase(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { containsPhrase(text, $0) }
    }

    /// Splits coaching prose into sentences WITHOUT breaking inside a decimal number.
    ///
    /// `22.5` is an ordinary load in this app (dumbbells, 2.5 lb plates, micro-loading), and a
    /// naive split on `.` turns one sentence into two mid-number. Whitespace is collapsed
    /// first so a note wrapped across lines behaves like the same note on one line.
    static func sentences(in text: String) -> [String] {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return [] }

        // A sentence is a run of non-terminators, where a period sitting between two digits
        // is treated as an ordinary character, optionally closed by its terminator.
        let pattern = #"(?:[^.!?]|(?<=\d)\.(?=\d))+[.!?]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [collapsed] }
        let range = NSRange(collapsed.startIndex..<collapsed.endIndex, in: collapsed)

        return regex.matches(in: collapsed, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: collapsed) else { return nil }
            let sentence = collapsed[matchRange].trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? nil : sentence
        }
    }

    /// The card's display filter: drop the sentences another element of the screen already owns,
    /// then de-duplicate. Shared by the exercise cue AND the day's session-note summary, which
    /// previously had no filter of any kind — the whole two-voices architecture was built for
    /// exercise notes, and the day note rendered raw above cards that could say the opposite.
    ///
    /// Matching here is plain substring, unlike `containsPhrase`. That asymmetry is deliberate:
    /// over-stripping only shortens a note, while under-stripping leaves a second voice giving
    /// load advice next to the deterministic banner. The validator, whose false positives cost a
    /// paid generation, gets the strict rule instead.
    static func filteredSentences(
        in text: String,
        hideProgressionCue: Bool,
        hideDeloadCue: Bool
    ) -> [String] {
        let all = sentences(in: text)
        guard !all.isEmpty else { return [] }

        var seen = Set<String>()
        var kept: [String] = []

        for sentence in all {
            let normalized = sentence
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()

            if hideDeloadCue, containsAnySubstring(normalized, ProgressionProseFragments.deloadContext) {
                continue
            }
            if hideProgressionCue, containsAnySubstring(normalized, ProgressionProseFragments.progressionOwnedByBanner) {
                continue
            }
            // The Last panel and the progression badge already show what you did, so
            // narrating it again never belongs in the execution cue.
            if containsAnySubstring(normalized, ProgressionProseFragments.sessionRecap) {
                continue
            }

            let key = normalized
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(key).inserted else { continue }

            kept.append(sentence)
        }

        return kept
    }

    private static func containsAnySubstring(_ text: String, _ fragments: [String]) -> Bool {
        fragments.contains { text.contains($0) }
    }

    // MARK: - Boundaries

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func isBoundedStart(of range: Range<String.Index>, in text: String) -> Bool {
        guard range.lowerBound > text.startIndex else { return true }
        return !isWordCharacter(text[text.index(before: range.lowerBound)])
    }

    private static func isBoundedEnd(of range: Range<String.Index>, in text: String) -> Bool {
        guard range.upperBound < text.endIndex else { return true }
        let next = text[range.upperBound]
        if !isWordCharacter(next) { return true }

        // Allow a plural "s", but only when the word genuinely ends there.
        guard next == "s" || next == "S" else { return false }
        let afterS = text.index(after: range.upperBound)
        guard afterS < text.endIndex else { return true }
        return !isWordCharacter(text[afterS])
    }
}
