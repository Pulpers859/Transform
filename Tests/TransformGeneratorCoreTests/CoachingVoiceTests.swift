import XCTest
@testable import Transform

/// Coverage for the execution-cue voice.
///
/// Two classes of failure are pinned here, and they fail very differently:
///
/// * DUPLICATION is loud but harmless — the lifter reads the same sentence on two cards and
///   stops believing the app coaches them. This was live: a Day 11 push session showed the
///   same cue on Incline Dumbbell Press and Machine Incline Press, and the same second cue on
///   Machine Chest Press and Dumbbell Bench Press.
/// * A BANNED FRAGMENT is silent and expensive — `notesContainProgressionInstruction` treats
///   load/rep prose in a note as a HARD validation failure, which discards an entire paid AI
///   week and drops to the procedural generator. A single careless cue word costs real money
///   and degrades the program with no visible error.
@MainActor
final class CoachingVoiceTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Content safety

    /// The expensive one. Every string the voice can emit, against the exact fragment list
    /// `notesContainProgressionInstruction` enforces.
    func testNoCueTripsTheHardValidationFailure() {
        for cue in CoachingVoiceAudit.allCues() {
            XCTAssertFalse(
                service.notesContainProgressionInstruction(cue),
                "Cue would hard-fail generation and discard a paid AI week: \(cue)"
            )
        }
    }

    /// The display layer deletes whole sentences containing progression or recap language. A
    /// cue that trips it renders as an empty box — a failure with no error anywhere.
    func testNoCueIsStrippedByTheDisplayFilter() {
        for cue in CoachingVoiceAudit.allCues() {
            XCTAssertEqual(
                CoachingVoiceAudit.violations(in: cue), [],
                "Cue would be stripped from the card and render as an empty box: \(cue)"
            )
        }
    }

    /// `isEmptyOrTooShortInsight` flags anything under five words and costs a paid correction
    /// pass, so a terse cue is not free.
    func testEveryCueClearsTheMinimumLength() {
        for cue in CoachingVoiceAudit.allCues() {
            let words = cue.split { $0.isWhitespace || $0.isNewline }.count
            XCTAssertGreaterThanOrEqual(words, 5, "Under the 5-word validator floor: \(cue)")
        }
    }

    /// `ExercisePrescription.parse` mines bare "light"/"moderate"/"heavy" and "week N" out of
    /// note prose and re-renders them as chips — silently deleting the word mid-sentence.
    func testNoCueCollidesWithThePrescriptionParser() {
        let collisions = ["light", "moderate", "heavy"]
        for cue in CoachingVoiceAudit.allCues() {
            let words = cue.lowercased().split { !$0.isLetter }.map(String.init)
            for collision in collisions {
                XCTAssertFalse(
                    words.contains(collision),
                    "'\(collision)' is mined out of the note by the prescription parser: \(cue)"
                )
            }
            XCTAssertNil(
                cue.range(of: #"\bweek\s*\d+\b"#, options: [.regularExpression, .caseInsensitive]),
                "'week N' is mined out of the note by the prescription parser: \(cue)"
            )
        }
    }

    /// The regression that motivated the rewrite: the retired generic cue "...before chasing
    /// heavier load" matched `coachingCueConflict`'s add-load pattern, so it was flagged as
    /// contradicting the app's own progression verdict and burned a paid correction call
    /// whenever the verdict was hold-below-range. Nothing may reintroduce that shape.
    func testNoCueContradictsTheProgressionVerdict() {
        let conflictPatterns = [
            #"hold\s+(the|this|that|your)\s+(current\s+)?(load|weight)"#,
            #"stay(ing)?\s+(at|with)\s+(the|this)\s+(load|weight)"#,
            #"keep\s+(the|this|your)\s+(same\s+)?(load|weight)"#,
            #"same\s+(load|weight)"#,
            #"add\s+(load|weight|a\s+plate)"#,
            #"increase\s+(the\s+)?(load|weight)"#,
            #"go\s+up\s+(in|to)\s+(load|weight)"#,
            #"heavier\s+(load|weight|dumbbell|pair)"#,
            #"load\s+increase"#
        ]
        for cue in CoachingVoiceAudit.allCues() {
            for pattern in conflictPatterns {
                XCTAssertNil(
                    cue.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                    "Cue matches a progression-conflict pattern (paid correction pass): \(cue)"
                )
            }
        }
    }

    /// "deload" anywhere in a note flips the whole card into deload context and replaces the
    /// progression badge with hold-back guidance.
    func testNoCueMentionsDeload() {
        for cue in CoachingVoiceAudit.allCues() {
            XCTAssertFalse(cue.lowercased().contains("deload"), "Flips the card into deload context: \(cue)")
        }
    }

    /// Cues must not read a database row aloud. The retired template produced
    /// "...across all sets of Dip (Assisted or Weighted)."
    func testNoCueInterpolatesAnExerciseName() {
        for cue in CoachingVoiceAudit.allCues() {
            XCTAssertFalse(cue.contains("("), "Reads like an interpolated exercise name: \(cue)")
        }
    }

    // MARK: - Day-scoped uniqueness

    /// The exact live day that prompted this work.
    func testTheReportedPushDayHasNoRepeatedCue() {
        let day = [
            (name: "Incline Dumbbell Press", muscleTarget: "Upper Chest"),
            (name: "Machine Incline Press", muscleTarget: "Upper Chest"),
            (name: "Machine Chest Press", muscleTarget: "Chest"),
            (name: "Dumbbell Bench Press", muscleTarget: "Chest"),
            (name: "Dip (Assisted or Weighted)", muscleTarget: "Triceps"),
            (name: "Machine Lateral Raise", muscleTarget: "Lateral Deltoids")
        ]

        let cues = CoachingVoice.assignCues(for: day)

        XCTAssertEqual(cues.count, day.count)
        XCTAssertEqual(Set(cues).count, day.count, "Two exercises on one screen share a cue:\n" + cues.joined(separator: "\n"))
    }

    /// The old pool held two strings per muscle family, so three same-family movements
    /// repeated by pigeonhole. Four presses in a row is the worst realistic case.
    func testFourSameFamilyPressesStillGetFourDistinctCues() {
        let cues = CoachingVoice.assignCues(for: [
            (name: "Barbell Bench Press", muscleTarget: "Chest"),
            (name: "Dumbbell Bench Press", muscleTarget: "Chest"),
            (name: "Machine Chest Press", muscleTarget: "Chest"),
            (name: "Cable Press", muscleTarget: "Chest")
        ])

        XCTAssertEqual(Set(cues).count, 4, "Same-family presses collided:\n" + cues.joined(separator: "\n"))
    }

    /// Uniqueness has to survive an absurd day, not just a realistic one — the ladder falls
    /// through to the universal pool rather than repeating or returning an empty string.
    func testUniquenessSurvivesAnUnreasonablyRepetitiveDay() {
        let day = (0..<8).map { (name: "Machine Lateral Raise \($0)", muscleTarget: "Lateral Deltoids") }

        let cues = CoachingVoice.assignCues(for: day)

        XCTAssertEqual(cues.count, 8)
        XCTAssertTrue(cues.allSatisfy { !$0.isEmpty }, "A blank cue is worse than a repeated one")
    }

    /// Notes are persisted at generation time, so selection must be stable — a randomised or
    /// clock-dependent pick would churn stored text on every regeneration.
    func testAssignmentIsDeterministic() {
        let day = [
            (name: "Incline Dumbbell Press", muscleTarget: "Upper Chest"),
            (name: "Machine Incline Press", muscleTarget: "Upper Chest"),
            (name: "Seated Cable Row", muscleTarget: "Back")
        ]

        XCTAssertEqual(CoachingVoice.assignCues(for: day), CoachingVoice.assignCues(for: day))
    }

    /// The repair paths add one exercise to a day that already exists, so they cannot use the
    /// day-scoped pass — they pass the cues already on the day instead.
    func testSingleCueRespectsCuesAlreadyOnTheDay() {
        let first = CoachingVoice.cue(forName: "Machine Chest Press", muscleTarget: "Chest")

        let second = CoachingVoice.cue(forName: "Machine Chest Press", muscleTarget: "Chest", avoiding: [first])

        XCTAssertNotEqual(first, second)
    }

    // MARK: - Classification

    /// Equipment keying is what separates two movements that share a muscle and a pattern —
    /// the precise collision seen live on Incline Dumbbell Press vs Machine Incline Press.
    func testEquipmentSeparatesOtherwiseIdenticalMovements() {
        XCTAssertEqual(CoachingVoice.equipment(forName: "Incline Dumbbell Press"), .dumbbell)
        XCTAssertEqual(CoachingVoice.equipment(forName: "Machine Incline Press"), .machine)
        XCTAssertEqual(CoachingVoice.equipment(forName: "Cable Lateral Raise"), .cable)
        XCTAssertEqual(CoachingVoice.equipment(forName: "Dip (Assisted or Weighted)"), .bodyweight)
    }

    /// Order matters in the classifier: broad terms are contained inside narrow ones, so a
    /// leg curl must not be read as a bicep curl and a leg press must not be a chest press.
    func testNarrowPatternsWinOverTheBroadOnesTheyContain() {
        XCTAssertEqual(CoachingVoice.pattern(forName: "Seated Leg Curl", muscleTarget: "Hamstrings"), .legCurl)
        XCTAssertEqual(CoachingVoice.pattern(forName: "Barbell Curl", muscleTarget: "Biceps"), .bicepCurl)
        XCTAssertEqual(CoachingVoice.pattern(forName: "Leg Press", muscleTarget: "Quads"), .legPress)
        XCTAssertEqual(CoachingVoice.pattern(forName: "Machine Chest Press", muscleTarget: "Chest"), .horizontalPress)
        XCTAssertEqual(CoachingVoice.pattern(forName: "Incline Dumbbell Press", muscleTarget: "Upper Chest"), .inclinePress)
        XCTAssertEqual(CoachingVoice.pattern(forName: "Machine Lateral Raise", muscleTarget: "Lateral Deltoids"), .lateralRaise)
        XCTAssertEqual(CoachingVoice.pattern(forName: "Triceps Pushdown", muscleTarget: "Triceps"), .tricepExtension)
    }

    /// An unrecognised movement still gets a true sentence rather than an empty note — the
    /// old generic bucket was where every unmatched target landed and duplicated hardest.
    func testUnknownMovementStillGetsAUsableCue() {
        let cue = CoachingVoice.cue(forName: "Some Novel Apparatus", muscleTarget: "Primary Target")

        XCTAssertFalse(cue.isEmpty)
        XCTAssertGreaterThanOrEqual(cue.split { $0.isWhitespace }.count, 5)
    }
}
