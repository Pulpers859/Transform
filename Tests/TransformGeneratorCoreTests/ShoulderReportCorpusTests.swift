import Foundation
import XCTest
@testable import Transform

/// Every shoulder rule, run against a written list of the ways an injury note can actually read.
///
/// WHY THIS FILE EXISTS. Four rounds of shoulder fixes in one session each broke something, and
/// every break had the same shape: the rule was correct for the one report that was in mind while
/// it was written, and wrong for the next report someone could plausibly get. A test built from
/// that same one report cannot catch that, because it shares the blind spot with the rule. Three
/// of the four rounds shipped a rule that went QUIET — caution silently switched off — and the
/// only reason any of them was found was a human re-reading the code afterwards.
///
/// So the unit under test here is not a function, it is the TABLE. Every row is a report shape a
/// real analysis produces, and every column is a movement. A rule that narrows too far turns a
/// TRUE into a FALSE somewhere in the grid and this fails; a rule that widens too far does the
/// reverse. New rules are added by extending the grid, never by adding a test with a fresh example
/// invented to suit them.
///
/// `injuryRiskFocus` is free prose written by the body-analysis model (`analysis.injuryRiskNotes`),
/// so the rows below deliberately include clinical wording, posture wording, hyphens, plurals and
/// a sentence that says a movement is FINE. Those are not exotic — three of them were live defects.
@MainActor
final class ShoulderReportCorpusTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - The columns

    /// One catalogue movement per family branch in `shoulderFamilyPhrases`.
    ///
    /// Every name and target here was read out of the catalogue in
    /// `WorkoutGeneratorService+MetadataProfiles.swift` rather than recalled, and the `family`
    /// field records the `movementPattern` that catalogue entry declares. A probe whose metadata
    /// pattern drifts away from its family makes this table describe something other than what it
    /// claims, so the first test asserts the pattern too.
    private struct Probe {
        let name: String
        let target: String
        let family: String
    }

    private static let probes: [Probe] = [
        Probe(name: "Seated Dumbbell Shoulder Press", target: "Anterior Deltoids", family: "Vertical Press"),
        Probe(name: "Landmine Press", target: "Anterior Deltoids", family: "Landmine Press"),
        Probe(name: "Incline Barbell Press", target: "Upper Chest", family: "Incline Press"),
        Probe(name: "Flat Barbell Bench Press", target: "Chest", family: "Horizontal Press"),
        Probe(name: "Close-Grip Barbell Bench Press", target: "Triceps", family: "Close-Grip Press"),
        Probe(name: "Dip (Assisted or Weighted)", target: "Triceps", family: "Dip"),
        Probe(name: "Cable Fly", target: "Chest", family: "Fly"),
        Probe(name: "Cable Lateral Raise", target: "Lateral Deltoids", family: "Lateral Raise"),
        Probe(name: "Cable Upright Row", target: "Lateral Deltoids", family: "Upright Row"),
        Probe(name: "Cable Rear Delt Fly", target: "Rear Deltoids", family: "Rear Delt Fly"),
        Probe(name: "Chest-Supported Rear Delt Row", target: "Rear Deltoids", family: "Rear Delt Row"),
        Probe(name: "Cable Face Pull", target: "Rear Deltoids", family: "Face Pull"),
        Probe(name: "Band Pull-Apart", target: "Shoulders", family: "Scapular Raise"),
        Probe(name: "Straight-Arm Pulldown", target: "Lats", family: "Pullover"),
        Probe(name: "Lat Pulldown", target: "Lats", family: "Vertical Pull"),
        Probe(name: "Chest-Supported Row", target: "Upper Back", family: "Row")
    ]

    // MARK: - The rows

    /// How far caution should reach for one report.
    ///
    /// `.everything` and `.only` are not just two answers, they are the two BEHAVIOURS the owner
    /// asked for, and the table exists to keep them apart. "Don't attack exercises that I don't
    /// mark or talk about hurting" is `.only`. A report that names no movement has nothing to
    /// narrow to, so it stays `.everything` — the broad behaviour he never objected to.
    ///
    /// The two also imply what `reportNamesAnyMovement` must say, and the test asserts that link
    /// rather than storing it in a third column: `.only` means the report named a movement,
    /// `.everything` means it did not. A future row that genuinely breaks that link is telling you
    /// something real about a phrase table and should be looked at, not papered over.
    private enum Reach: Equatable {
        /// No shoulder problem in the report at all. Nothing may be penalised, warned about, or
        /// charged shoulder load.
        case nothing
        /// A shoulder problem with no movement named. Caution stays broad.
        case everything
        /// A shoulder problem with movements named. Exactly these probes, and no others.
        case only([String])
    }

    private struct Row {
        let report: String
        let shape: String
        let reach: Reach
    }

    private static let corpus: [Row] = [

        // ---- Nothing to work around -------------------------------------------------------

        Row(
            report: "No injuries reported.",
            shape: "the empty case",
            reach: .nothing
        ),
        Row(
            report: "Mild left knee discomfort during deep squatting; upper body is clear.",
            shape: "a real injury somewhere else",
            reach: .nothing
        ),
        Row(
            report: "Broad shoulders and a long torso make width look better than it measures.",
            shape: "the joint named with no problem — the app must not panic at the word",
            reach: .nothing
        ),

        // ---- A shoulder problem, no movement named ----------------------------------------
        //
        // This block is the one that has broken three times. Each of these reports matched no
        // family and no exercise name, so a version of `reportedShoulderPainImplicates` that had
        // no general fallback answered FALSE for every movement in the catalogue and switched off
        // all five gated shoulder rules at once, silently.

        Row(
            report: "Shoulder impingement noted on the left side.",
            shape: "a named diagnosis",
            reach: .everything
        ),
        Row(
            report: "Rotator cuff irritation on the left, worse after night shifts.",
            shape: "a named structure",
            reach: .everything
        ),
        Row(
            report: "History of a left labral tear, currently quiet but worth respecting.",
            shape: "a named structure, past tense",
            reach: .everything
        ),
        Row(
            report: "AC joint tenderness on the left.",
            shape: "a named joint region",
            reach: .everything
        ),
        Row(
            report: "Internally rotated shoulders with an upper crossed posture pattern.",
            shape: "posture language, no complaint word",
            reach: .everything
        ),
        Row(
            report: "Shoulder health is a priority this block.",
            shape: "a goal rather than a complaint",
            reach: .everything
        ),
        Row(
            report: "Left shoulder aches through the day and is sore on waking.",
            shape: "plain description, no movement",
            reach: .everything
        ),
        Row(
            report: "Left shoulder and delt pain, worse in the evening.",
            shape: "names the joint and the muscle only — neither is a movement",
            reach: .everything
        ),
        Row(
            report: "Left shoulder pain with narrowing of the subacromial space.",
            shape: "clinical wording that HIDES a movement word: narrowing contains row",
            reach: .everything
        ),
        Row(
            report: "Left shoulder pain with scapular dyskinesis and poor scapular control.",
            shape: "posture wording that names anatomy the phrase tables also use",
            reach: .everything
        ),
        Row(
            report: "Shoulder discomfort reproduced with straight arm elevation.",
            shape: "a clinical position that shares a phrase with the pullover family",
            reach: .everything
        ),
        Row(
            report: "Left shoulder pain with overhead reaching and difficulty sleeping on that side.",
            shape: "a POSITION, not a lift — and it shares a word with the vertical-press family",
            reach: .everything
        ),
        Row(
            report: "Subacromial impingement on the left; pain provoked by overhead activity at work.",
            shape: "an anatomical diagnosis that never writes the word shoulder",
            reach: .everything
        ),

        // ---- One movement named ------------------------------------------------------------

        Row(
            report: """
            Left anterior shoulder pain during neutral-grip overhead pressing is the key flag: \
            this pattern warrants modifying pressing angle, reducing overhead range temporarily, \
            and monitoring rather than pushing through.
            """,
            shape: "the owner's real 2026-09-08 note — overhead pressing and nothing else",
            reach: .only(["Seated Dumbbell Shoulder Press"])
        ),
        Row(
            report: "Shoulder pain when pressing overhead.",
            shape: "the same family, worded the other way round",
            reach: .only(["Seated Dumbbell Shoulder Press"])
        ),
        Row(
            report: "Anterior shoulder pain on dips.",
            shape: "a plural, and the movement the owner says is fine for him",
            reach: .only(["Dip (Assisted or Weighted)"])
        ),
        Row(
            report: "Shoulder pain during bench pressing.",
            shape: "one family named by its everyday name",
            reach: .only(["Flat Barbell Bench Press"])
        ),
        Row(
            report: "Shoulder pain on lateral raises.",
            shape: "an isolation movement, plural",
            reach: .only(["Cable Lateral Raise"])
        ),
        Row(
            report: "Shoulder pain with lat pulldowns.",
            shape: "a pulling movement, plural",
            reach: .only(["Lat Pulldown"])
        ),
        Row(
            report: "Shoulder pain on the landmine press.",
            shape: "a press that is NOT reached by the overhead phrases",
            reach: .only(["Landmine Press"])
        ),
        Row(
            report: "Shoulder pain with band pull-aparts.",
            shape: "a hyphenated corrective movement, plural",
            reach: .only(["Band Pull-Apart"])
        ),
        Row(
            report: "Shoulder pain on face pulls.",
            shape: "two words, plural",
            reach: .only(["Cable Face Pull"])
        ),

        // ---- Rows that prove a family by its WORDS, not by quoting the exercise ------------
        //
        // Each of these exists because `testEveryFamilyIsProvenByARowThatNamesNoExercise` went
        // red without it. The rows above that look like they cover these families do not: their
        // reports quote the movement's own name, so `namedOutright` answers first and the family
        // is never consulted. Deleting the family left every one of those rows passing.

        Row(
            report: "Shoulder pain on the pec deck.",
            shape: "the Fly family reached by a machine name, not by the word fly",
            reach: .only(["Cable Fly"])
        ),
        Row(
            report: "Shoulder pain on Y raises.",
            shape: "the Scapular Raise family by its other vocabulary",
            reach: .only(["Band Pull-Apart"])
        ),
        Row(
            report: "Shoulder pain with landmine work.",
            shape: "the Landmine Press family without the word press",
            reach: .only(["Landmine Press"])
        ),
        Row(
            report: "Shoulder pain on chin-ups.",
            shape: "the Vertical Pull family by a movement that is not a pulldown",
            reach: .only(["Lat Pulldown"])
        ),
        Row(
            report: "Shoulder pain with cable pullovers.",
            shape: "the Pullover family, which no row reached at all before this one",
            reach: .only(["Straight-Arm Pulldown"])
        ),

        // ---- Named movements that legitimately reach more than one family ------------------
        //
        // These rows look surprising and are correct. They are here so the overlap is a recorded
        // decision rather than something rediscovered as a bug. Both rear-delt patterns are named
        // "Rear Delt Fly" and "Rear Delt Row", so that family has to answer to BOTH vocabularies
        // or a report saying "rows hurt" reaches neither.

        Row(
            report: "Shoulder pain on rows.",
            shape: "row vocabulary reaches the row family AND both rear-delt movements",
            reach: .only([
                "Chest-Supported Row",
                "Cable Rear Delt Fly",
                "Chest-Supported Rear Delt Row"
            ])
        ),
        Row(
            report: "Shoulder pain with cable flyes.",
            shape: "fly vocabulary, spelled the way lifters spell it, same overlap",
            reach: .only([
                "Cable Fly",
                "Cable Rear Delt Fly",
                "Chest-Supported Rear Delt Row"
            ])
        ),
        Row(
            report: "Shoulder pain with cable flies.",
            shape: "the OTHER spelling — an irregular plural the +s/+es rule cannot reach",
            reach: .only([
                "Cable Fly",
                "Cable Rear Delt Fly",
                "Chest-Supported Rear Delt Row"
            ])
        ),
        Row(
            report: "Shoulder pain with upright rows.",
            shape: "a specific movement whose name contains a broader family's word",
            reach: .only([
                "Cable Upright Row",
                "Chest-Supported Row",
                "Cable Rear Delt Fly",
                "Chest-Supported Rear Delt Row"
            ])
        ),
        Row(
            report: "Shoulder pain on close-grip bench press.",
            shape: "a hyphen, and a name that contains another family's name",
            reach: .only([
                "Close-Grip Barbell Bench Press",
                "Flat Barbell Bench Press"
            ])
        ),
        Row(
            report: "Shoulder pain on incline bench press.",
            shape: "same overlap on the incline side",
            reach: .only([
                "Incline Barbell Press",
                "Flat Barbell Bench Press"
            ])
        ),

        // ---- A known limitation, pinned so it stays visible --------------------------------
        //
        // The matching reads WHICH movements a report mentions. It has no idea whether the
        // sentence said they hurt or said they were fine, so a note clearing a movement still
        // implicates it. This is the owner's own sentence — "dips don't bother it" — turned
        // against him if it ever reaches the analysis notes. Fixing it means guessing at negation,
        // which fails in both directions, so it is recorded rather than papered over. If this row
        // ever starts passing with the dip absent, someone has taught the app about negation and
        // this comment should become a description of how.

        Row(
            report: "Left shoulder pain with overhead pressing; dips are pain free.",
            shape: "KNOWN LIMITATION: a movement the note CLEARS is still implicated",
            reach: .only([
                "Seated Dumbbell Shoulder Press",
                "Dip (Assisted or Weighted)"
            ])
        )
    ]

    // MARK: - Helpers

    private static func expectedNames(_ reach: Reach) -> Set<String> {
        switch reach {
        case .nothing:
            return []
        case .everything:
            return Set(probes.map(\.name))
        case .only(let names):
            return Set(names)
        }
    }

    private func exercise(_ probe: Probe, sets: Int = 3) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: probe.name,
            sets: sets,
            reps: "10-12",
            tempo: "2-0-1-1",
            restSeconds: 90,
            notes: "",
            muscleTarget: probe.target
        )
    }

    private func day(_ exercises: [WorkoutExerciseResponse], dayNumber: Int = 3) -> WorkoutDayResponse {
        WorkoutDayResponse(
            dayNumber: dayNumber,
            dayName: "Session",
            muscleGroups: "Mixed",
            isRestDay: false,
            notes: "",
            exercises: exercises
        )
    }

    // MARK: - The grid

    /// The probes still are what the table says they are.
    ///
    /// Without this the whole file can go quietly wrong: if a catalogue entry is renamed or its
    /// pattern changed, every row below keeps passing while testing a different movement than it
    /// names, and the coverage claim in this file's header becomes false.
    func testEveryProbeStillDeclaresTheFamilyThisTableSaysItDoes() {
        for probe in Self.probes {
            let metadata = service.exerciseMetadata(
                forExerciseName: probe.name,
                muscleTarget: probe.target
            )
            XCTAssertEqual(
                metadata.movementPattern,
                probe.family,
                "\(probe.name) is the table's stand-in for the \(probe.family) family"
            )
            XCTAssertFalse(
                service.shoulderFamilyPhrases(
                    forMovementPattern: service.normalizedPriorityText(probe.family)
                ).isEmpty,
                "\(probe.family) must have everyday phrases, or a real complaint about it reaches nothing"
            )
        }
    }

    /// Every family is PROVEN by a row that does not quote the exercise's own name.
    ///
    /// This is the test that audits the table, and it exists because the table looked complete
    /// and was not. Checking by hand — deleting each family from a faithful simulation and seeing
    /// which rows changed — four families turned out to be carried by nothing:
    ///
    ///   * Pullover and the "Shoulder" catch-all had no row at all.
    ///   * Fly LOOKED covered. The row "Shoulder pain with cable flyes." expects Cable Fly, but
    ///     that report quotes the exercise's own name, so the `namedOutright` branch answers it
    ///     and the family is never consulted. Delete the family and the row still passes.
    ///   * Scapular Raise had the same problem through "band pull-aparts".
    ///
    /// A row whose answer comes from the name proves the name matching, which is worth having and
    /// is not what it appears to prove. So the requirement is specific: for every movement there
    /// must be a row that reaches it through its FAMILY WORDS ALONE.
    func testEveryFamilyIsProvenByARowThatNamesNoExercise() {
        for probe in Self.probes {
            let provingRows = Self.corpus.filter { row in
                guard case .only(let names) = row.reach, names.contains(probe.name) else {
                    return false
                }
                // The report must not contain the movement's own name, or `namedOutright`
                // answers before the family is ever consulted.
                return !service.containsPluralTolerantPriorityPhrase(
                    in: service.normalizedPriorityText(row.report),
                    keywords: [service.normalizedPriorityText(probe.name)]
                )
            }
            XCTAssertFalse(
                provingRows.isEmpty,
                "No row reaches \(probe.name) through the \(probe.family) family alone. "
                + "Delete that family and nothing in this table would notice."
            )
        }
    }

    /// A movement the app cannot classify is treated as a shoulder movement, deliberately.
    ///
    /// `inferredExerciseMetadata` has a catch-all: anything whose name or target says shoulder or
    /// delt, and which matched no more specific branch, gets the pattern "Shoulder". Its family is
    /// the words "shoulder" and "delt", so any report naming the joint reaches it — including a
    /// report that otherwise names only one other movement.
    ///
    /// That is a real tension with "stay off movements I haven't flagged" and it is resolved on
    /// purpose in the cautious direction: the app does not know what the movement is, and the
    /// lifter's own note says that joint hurts. Pinned rather than left implicit, because it is
    /// the one place where naming one movement does not fully narrow the week.
    func testAnUnclassifiedShoulderMovementStaysCoveredByAnyShoulderReport() {
        let unclassified = WorkoutExerciseResponse(
            exerciseName: "Shoulder Circles",
            sets: 2,
            reps: "10-12",
            tempo: "2-0-1-1",
            restSeconds: 60,
            notes: "",
            muscleTarget: "Shoulders"
        )

        XCTAssertEqual(
            service.exerciseMetadata(for: unclassified).movementPattern,
            "Shoulder",
            "Premise: this is the inference catch-all. If it now resolves elsewhere, this test "
            + "is measuring something other than what it names."
        )

        XCTAssertTrue(
            service.reportedShoulderPainImplicates(
                exerciseName: unclassified.exerciseName,
                muscleTarget: unclassified.muscleTarget,
                injuryRiskFocus: "Anterior shoulder pain on dips."
            ),
            "A movement the app cannot classify stays covered even when the note names another one"
        )
        XCTAssertFalse(
            service.reportedShoulderPainImplicates(
                exerciseName: unclassified.exerciseName,
                muscleTarget: unclassified.muscleTarget,
                injuryRiskFocus: "No injuries reported."
            ),
            "A lifter who reported nothing is still not penalised anywhere"
        )
    }

    /// The table itself: every report against every movement.
    func testCautionReachesExactlyTheMovementsEachReportNames() {
        for row in Self.corpus {
            XCTAssertEqual(
                service.hasShoulderRisk(injuryRiskFocus: row.report),
                row.reach != .nothing,
                "Whether this registers as a shoulder problem at all — \(row.shape) — \(row.report)"
            )

            if row.reach != .nothing {
                let namesAMovement: Bool
                switch row.reach {
                case .everything: namesAMovement = false
                case .only, .nothing: namesAMovement = true
                }
                XCTAssertEqual(
                    service.reportNamesAnyMovement(service.normalizedPriorityText(row.report)),
                    namesAMovement,
                    "Specificity decides whether caution narrows or stays broad — \(row.shape)"
                )
            }

            let expected = Self.expectedNames(row.reach)
            for probe in Self.probes {
                let implicated = service.reportedShoulderPainImplicates(
                    exerciseName: probe.name,
                    muscleTarget: probe.target,
                    injuryRiskFocus: row.report
                )
                XCTAssertEqual(
                    implicated,
                    expected.contains(probe.name),
                    "\(probe.name) vs \"\(row.report)\" (\(row.shape))"
                )
            }
        }
    }

    /// The joint-stress rule reads the same table.
    ///
    /// The owner's instruction is a floor, not a preference: "Stay off of movements that I haven't
    /// flagged." Shoulder load is built from `metadata.shoulderRisk`, a hardcoded name list that
    /// gives a dip a 4, so before it was gated a week full of dips could still be told to drop a
    /// pressing slot on shoulder grounds. The assertion that matters is the ZERO direction, and it
    /// is checked for every row rather than for one report.
    func testUnflaggedMovementsNeverAccumulateShoulderLoad() {
        for row in Self.corpus {
            let expected = Self.expectedNames(row.reach)
            let untouched = Self.probes.filter { !expected.contains($0.name) }
            guard !untouched.isEmpty else { continue }

            let stress = service.sessionJointStress(
                for: day(untouched.map { exercise($0) }),
                injuryRiskFocus: row.report
            )
            XCTAssertEqual(
                stress.shoulder,
                0,
                accuracy: 0.0001,
                "A session of movements this report never names must carry no shoulder load — \(row.shape)"
            )
        }
    }

    /// And the other direction, so the rule is not simply switched off for everyone.
    func testFlaggedPressingStillAccumulatesShoulderLoad() {
        let pressingDay = day([
            exercise(Self.probes[0]),
            exercise(Self.probes[2]),
            exercise(Self.probes[3])
        ])

        XCTAssertGreaterThan(
            service.sessionJointStress(
                for: pressingDay,
                injuryRiskFocus: "Shoulder impingement noted on the left side."
            ).shoulder,
            0,
            "A report naming no movement leaves caution broad, so pressing must still be counted"
        )
        XCTAssertEqual(
            service.sessionJointStress(
                for: pressingDay,
                injuryRiskFocus: "No injuries reported."
            ).shoulder,
            0,
            accuracy: 0.0001,
            "A lifter who reported nothing is charged nothing"
        )
    }

    /// The Arms-day warning reads the same table too.
    ///
    /// This is the rule that produced a finding about a Dip for a lifter whose report names only
    /// overhead pressing, and who says dips do not bother him. It asserts the family per keyword
    /// rather than inferring one, so it is worth checking against the grid instead of trusting
    /// that the two agree.
    func testTheArmsDayWarningAgreesWithTheTable() {
        let dip = Self.probes.first { $0.family == "Dip" }!
        let armDay = day([exercise(dip), exercise(Self.probes[7])], dayNumber: 5)

        for row in Self.corpus {
            let findings = service.validateArmsDayShoulderStress(
                on: armDay,
                expectedStyle: "Arms",
                focusArea: "Lateral Deltoids",
                injuryRiskFocus: row.report
            )
            XCTAssertEqual(
                findings.isEmpty,
                !Self.expectedNames(row.reach).contains(dip.name),
                "The Arms-day warning must fire for a dip exactly when the report reaches one — \(row.shape)"
            )
        }
    }
}
