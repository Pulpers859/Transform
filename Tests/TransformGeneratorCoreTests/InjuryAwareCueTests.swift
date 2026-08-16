import XCTest
@testable import Transform

/// Cue text used to be a pure function of movement pattern and equipment, with no injury input
/// at all — so the app could penalise a shoulder-risky lift during exercise selection and then
/// coach the lifter into end range on the lift it did pick.
final class InjuryAwareCueTests: XCTestCase {

    /// THE load-bearing test. The filter matches cue strings exactly, so a reworded cue that is
    /// not updated here would silently stop protecting a flagged shoulder — a safety rule that
    /// fails open and still looks correct. Non-empty means exactly that happened.
    func testEveryEndRangeShoulderCueStillExistsInTheCueTables() {
        XCTAssertEqual(
            CoachingVoiceAudit.orphanedEndRangeShoulderCues(), [],
            "These strings no longer match any emittable cue, so the shoulder filter is silently a no-op for them"
        )
    }

    /// Removing an end-range cue must never leave the ladder empty — a blank cue is worse than
    /// a general one.
    func testLadderIsNeverEmptiedByTheFilter() {
        for pattern in CoachingVoice.Pattern.allCases {
            for equipment in CoachingVoice.Equipment.allCases {
                let filtered = CoachingVoice.cueLadderForAudit(
                    pattern: pattern,
                    equipment: equipment,
                    avoidEndRangeShoulder: true
                )
                XCTAssertFalse(filtered.isEmpty, "\(pattern)/\(equipment) produced no cue at all")
            }
        }
    }

    /// The filter must actually remove the flagged phrasing from what a lifter can be handed.
    func testFlaggedShoulderNeverReceivesAnEndRangeCue() {
        for pattern in CoachingVoice.Pattern.allCases {
            for equipment in CoachingVoice.Equipment.allCases {
                let filtered = Set(CoachingVoice.cueLadderForAudit(
                    pattern: pattern,
                    equipment: equipment,
                    avoidEndRangeShoulder: true
                ))
                XCTAssertTrue(
                    filtered.isDisjoint(with: CoachingVoice.endRangeShoulderCues),
                    "\(pattern)/\(equipment) can still emit an end-range shoulder cue"
                )
            }
        }
    }

    /// Concretely: the dip. Unfiltered it says "descend until the upper arms break parallel";
    /// filtered it must fall through to the protective cue that already sits below it, not to
    /// a generic one — the point of removing rather than replacing.
    func testDipFallsThroughToTheProtectiveCueThatAlreadyExists() {
        let cue = CoachingVoice.cue(
            forName: "Weighted Dip",
            muscleTarget: "Chest",
            avoidEndRangeShoulder: true
        )
        XCTAssertFalse(cue.contains("break parallel"), cue)
        XCTAssertTrue(
            cue.localizedCaseInsensitiveContains("shoulders pulled away") || cue.localizedCaseInsensitiveContains("lean"),
            "Expected the dip's own protective phrasing, got: \(cue)"
        )
    }

    /// An uninjured lifter must be unaffected — this is an override, not a downgrade. Asserting
    /// the UNFILTERED ladder still offers the end-range cue is what proves the filter has
    /// something real to remove, rather than the tests above passing vacuously.
    func testUnflaggedLifterStillGetsTheEndRangeCoaching() {
        let unfiltered = CoachingVoice.cueLadderForAudit(pattern: .dip, equipment: .bodyweight)
        XCTAssertFalse(
            Set(unfiltered).isDisjoint(with: CoachingVoice.endRangeShoulderCues),
            "Without a flagged shoulder the specific end-range cue must still be offered"
        )
        XCTAssertTrue(unfiltered.contains("Descend until the upper arms break parallel, then drive up without letting the shoulders roll forward."))
    }

    /// Day-scoped uniqueness must survive the filter: a shorter ladder is exactly where repeats
    /// would start appearing if the two features had not been composed.
    func testDayScopedUniquenessHoldsWithTheFilterOn() {
        let day = [
            (name: "Incline Dumbbell Press", muscleTarget: "Upper Chest"),
            (name: "Machine Chest Press", muscleTarget: "Chest"),
            (name: "Cable Lateral Raise", muscleTarget: "Lateral Deltoids"),
            (name: "Machine Lateral Raise", muscleTarget: "Lateral Deltoids")
        ]
        let cues = CoachingVoice.assignCues(for: day, avoidEndRangeShoulder: true)
        XCTAssertEqual(cues.count, day.count)
        XCTAssertEqual(Set(cues).count, cues.count, "Cues repeated within one day: \(cues)")
        XCTAssertTrue(Set(cues).isDisjoint(with: CoachingVoice.endRangeShoulderCues))
    }

    /// Filtered cues must still clear the display filter, or they render as an empty box.
    func testFilteredCuesStillSurviveTheDisplayFilter() {
        for pattern in CoachingVoice.Pattern.allCases {
            for equipment in CoachingVoice.Equipment.allCases {
                for cue in CoachingVoice.cueLadderForAudit(
                    pattern: pattern,
                    equipment: equipment,
                    avoidEndRangeShoulder: true
                ) {
                    XCTAssertEqual(
                        CoachingVoiceAudit.violations(in: cue), [],
                        "Cue would be stripped to nothing on screen: \(cue)"
                    )
                }
            }
        }
    }
}

/// The deload phase is a structural fact about the program. It used to be inferred by searching
/// free text for the word "deload", which fired on a week-3 note saying the deload had NOT
/// arrived yet, and missed week 4 entirely whenever the model followed its instruction not to
/// repeat deload language in every note.
final class MesocyclePhaseTests: XCTestCase {

    func testOnlyTheFinalProgrammedWeekIsADeload() {
        XCTAssertFalse(MesocyclePhase.isDeloadWeek(1))
        XCTAssertFalse(MesocyclePhase.isDeloadWeek(2))
        XCTAssertFalse(MesocyclePhase.isDeloadWeek(3))
        XCTAssertTrue(MesocyclePhase.isDeloadWeek(4))
    }

    /// Pins the contract, now that this constant is the ONE definition the planner reads: the
    /// exercise-count target, the rest-day pattern and the training card all route through
    /// `isDeloadWeek`, so changing this value moves every deload behaviour together — which is
    /// the point. It has to be a deliberate edit, not a drift.
    func testDeloadWeekIsTheSingleDefinitionThePlannerReads() {
        XCTAssertEqual(MesocyclePhase.deloadWeek, 4)
        XCTAssertTrue(MesocyclePhase.isDeloadWeek(MesocyclePhase.deloadWeek))
    }

    /// `WorkoutDay.weekNumber` is derived from `dayNumber`, so the day-level flag has to line up
    /// with the 7-day blocks the program is laid out in.
    func testDayLevelFlagTracksTheSevenDayBlocks() {
        let firstDayOfDeload = WorkoutDay(dayNumber: 22, dayName: "Push", muscleGroups: "Chest")
        let lastDayOfPeakWeek = WorkoutDay(dayNumber: 21, dayName: "Push", muscleGroups: "Chest")
        XCTAssertEqual(firstDayOfDeload.weekNumber, 4)
        XCTAssertTrue(firstDayOfDeload.isDeloadWeek)
        XCTAssertEqual(lastDayOfPeakWeek.weekNumber, 3)
        XCTAssertFalse(lastDayOfPeakWeek.isDeloadWeek, "Week 3 is the peak-stress week, never a deload")
    }
}

/// The day briefing renders at the top of the same screen as the exercise cards and was the one
/// piece of coaching text with no filter and no validator rule.
final class SessionNoteFilterTests: XCTestCase {

    func testLoadInstructionIsStrippedFromTheDayBriefing() {
        let kept = CoachingProse.filteredSentences(
            in: "Posterior chain focus today. Add load on your top sets. Keep ribs stacked.",
            hideProgressionCue: true,
            hideDeloadCue: false
        )
        XCTAssertEqual(kept, ["Posterior chain focus today.", "Keep ribs stacked."])
    }

    /// Deload framing is left alone at the DAY level on purpose: "keep it light this week" is
    /// context, not a competing instruction about one lift's load.
    func testDeloadFramingSurvivesInTheDayBriefing() {
        let kept = CoachingProse.filteredSentences(
            in: "This is a deload week. Keep the movements familiar.",
            hideProgressionCue: true,
            hideDeloadCue: false
        )
        XCTAssertEqual(kept.count, 2, "Day-level deload framing must not be stripped: \(kept)")
    }

    func testDuplicateSentencesCollapse() {
        let kept = CoachingProse.filteredSentences(
            in: "Brace hard. Brace hard.",
            hideProgressionCue: false,
            hideDeloadCue: false
        )
        XCTAssertEqual(kept, ["Brace hard."])
    }
}
