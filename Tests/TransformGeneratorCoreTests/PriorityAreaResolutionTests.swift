import Foundation
import XCTest
@testable import Transform

/// The body-analysis AI never names exercises — it names a muscle `area`, and that string is the
/// only handle the generator has on "what did the client actually ask for". Two defects lived in
/// the string→profile mapping:
///
/// 1. The broad `Arms` profile listed "biceps"/"triceps" as *identity* triggers, and
///    `priorityProfileSpecificitySort` broke the tie on longest keyword — "forearms" (8) beat
///    "triceps" (7) and "biceps" (6). So the dedicated Biceps and Triceps profiles were
///    unreachable code, and both areas canonicalized to "Arms". Because `prioritizedFocusAreas`
///    and `mergedPriorityIntents` both key by the canonical name, a Biceps priority and a Triceps
///    priority folded into ONE "Arms" priority whose set target was `max()` of the two, not the
///    sum — roughly half the intended arm volume, with nothing surfaced to the owner.
/// 2. `Core/Abs` listed "oblique" the same way, so "Obliques" and "Oblique" resolved to two
///    different profiles depending purely on whether the AI wrote the plural.
@MainActor
final class PriorityAreaResolutionTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - The reachability property

    /// The real invariant, not just the two symptoms: every profile in the table must be
    /// reachable by its own label. Any future profile whose label is swallowed by a broader
    /// profile's trigger list fails here instead of becoming silent dead code.
    func testEveryPriorityProfileIsReachableByItsOwnLabel() {
        for profile in service.priorityProfiles {
            XCTAssertEqual(
                service.canonicalPriorityAreaName(profile.label),
                profile.label,
                "Profile '\(profile.label)' is shadowed — it can never be selected by its own name."
            )
        }
    }

    func testArmsNoLongerSwallowsBicepsAndTriceps() {
        XCTAssertEqual(service.canonicalPriorityAreaName("Biceps"), "Biceps")
        XCTAssertEqual(service.canonicalPriorityAreaName("Triceps"), "Triceps")
        XCTAssertEqual(service.canonicalPriorityAreaName("bicep"), "Biceps")
        XCTAssertEqual(service.canonicalPriorityAreaName("tricep"), "Triceps")
        XCTAssertEqual(service.canonicalPriorityAreaName("bicep peak"), "Biceps")
    }

    /// Arms is still a real, selectable area — the fix narrows what Arms *claims*, it does not
    /// delete the profile.
    func testArmsStillResolvesForGenuineArmRequests() {
        XCTAssertEqual(service.canonicalPriorityAreaName("Arms"), "Arms")
        XCTAssertEqual(service.canonicalPriorityAreaName("arm size"), "Arms")
        XCTAssertEqual(service.canonicalPriorityAreaName("forearms"), "Arms")
    }

    func testObliquesResolveConsistentlyInSingularAndPlural() {
        XCTAssertEqual(service.canonicalPriorityAreaName("Obliques"), "Obliques")
        XCTAssertEqual(service.canonicalPriorityAreaName("oblique"), "Obliques")
    }

    /// Regression guard for a rejected fix. Reworking `priorityProfileSpecificitySort` to break
    /// ties on "fewer trigger keywords = narrower" also fixed Biceps, but silently sent
    /// "lat width" to Back (3 keywords) instead of Lats (4). The shipped fix touches the keyword
    /// tables, not the sort, so multi-word lat phrasing must still land on Lats.
    func testLatPhrasingStillResolvesToLatsNotBack() {
        XCTAssertEqual(service.canonicalPriorityAreaName("lat width"), "Lats")
        XCTAssertEqual(service.canonicalPriorityAreaName("Lats"), "Lats")
        XCTAssertEqual(service.canonicalPriorityAreaName("Back"), "Back")
    }

    // MARK: - The volume consequence

    /// The bug that actually cost training volume. Before the fix this plan came back with ONE
    /// priority; both arm areas keyed to "Arms" and `mergePriorityIntent` took `max()` of their
    /// set targets rather than keeping them as two separate muscles.
    func testBicepsAndTricepsSurviveAsTwoSeparatePriorities() {
        let plan = service.fallbackTrainingIntentPlan(from: ["Biceps", "Triceps"])

        XCTAssertEqual(plan.priorities.count, 2, "Two arm priorities must not fold into one.")
        XCTAssertEqual(Set(plan.priorities.map(\.area)), ["Biceps", "Triceps"])
    }

    /// The merge itself is not the bug and must keep working. Two spellings of the SAME muscle
    /// are a genuine duplicate, and `max()` is correct there — summing would double-count one
    /// muscle's volume. This is why the fix corrects the mapping rather than the merge.
    func testGenuineDuplicateAreasStillMergeIntoOne() {
        let plan = service.fallbackTrainingIntentPlan(from: ["Lat", "Lats"])

        XCTAssertEqual(plan.priorities.count, 1, "The same muscle named twice is still one priority.")
        XCTAssertEqual(plan.priorities.first?.area, "Lats")
    }

    // MARK: - The catalog consequence

    /// Reaching the Biceps profile is only worth something if it brings its own curated movements.
    /// The Arms catalog that used to answer for it carries two entries total.
    func testBicepsPriorityGetsTheDedicatedCurlCatalog() {
        let profile = service.priorityProfile(for: "Biceps")

        XCTAssertEqual(profile.label, "Biceps")
        XCTAssertGreaterThan(profile.accessoryCatalog.count, 2)
        XCTAssertTrue(
            profile.accessoryCatalog.allSatisfy { $0.target == "Biceps" },
            "The Biceps accessory catalog should be biceps work, not mixed arm work."
        )
    }

    /// Coverage is deliberately unchanged: a curl still counts as training arms even though
    /// "biceps" is no longer an Arms *trigger*. Identity and coverage are separate questions.
    func testArmsCoverageStillRecognizesBicepsAndTricepsWork() {
        let keywords = Set(service.priorityCoverageKeywords(for: "Arms"))

        XCTAssertTrue(keywords.contains("bicep"), "Arms coverage lost biceps work.")
        XCTAssertTrue(keywords.contains("tricep"), "Arms coverage lost triceps work.")
    }

    // MARK: - Unrecognized areas must be visible

    private func analysis(priorityArea: String) -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: "Lean, developed physique with an upper-chest bottleneck. Confidence: medium.",
            trainingAssessment: "Prioritize incline pressing.",
            nutritionAssessment: "Hold maintenance.",
            recoveryRiskAssessment: "No major flags.",
            adherenceAssessment: "Consistency looks reasonable.",
            analysisLimitations: "Photo-only; no labs.",
            inputContext: nil,
            regionBreakdown: [RegionAssessment(region: "Upper Chest", assessment: "Underdeveloped clavicular head.", priority: "High")],
            topLeverageChange: "Add a second weekly incline session.",
            priorityMuscles: [priorityArea],
            workoutRecommendations: ["Low incline press 3x6-10"],
            dietRecommendations: ["Keep protein high"],
            posturalNotes: "Ribcage sits slightly forward; cue bracing on presses.",
            estimatedBodyFat: "14-16%",
            metabolicHealthNotes: "Energy management is fine.",
            psychologicalInsights: "Sustainable plan matters.",
            injuryRiskNotes: "Watch shoulder setup.",
            macroTargets: AnalysisMacroTargets(
                calories: 2800, proteinG: 190, carbsG: 300, fatG: 85,
                macroRationale: "Anchored to logged bodyweight and goal rate."
            ),
            structuredTrainingIntent: StructuredTrainingIntent(
                splitRecommendation: "Upper/Lower",
                weeklyTrainingDays: 5,
                priorities: [StructuredTrainingPriority(
                    area: priorityArea, priorityLevel: "High", rationale: "Lagging",
                    weeklyDayTarget: 2, weeklyExerciseTarget: 3,
                    preferredStyles: ["Push"], preferredMovementPatterns: ["incline press"],
                    volumeBias: "High", directWorkBias: "Direct emphasis")],
                programmingNotes: ["Manage press fatigue"])
        )
    }

    private func areaIssues(forPriorityArea area: String) -> [AnalysisValidationIssue] {
        BodyAnalysisValidator
            .validate(analysis(priorityArea: area), photoAngles: ["Front", "Back", "Side (Left)", "Side (Right)"], bodyweightLbs: 200)
            .issues
            .filter { $0.message.contains("not a recognized training area") }
    }

    func testUnrecognizedPriorityAreaIsReportedInsteadOfSilentlyGoingGeneric() {
        for invented in ["Posterior Chain", "V-Taper", "Rear Chain Thickness", "Quadz"] {
            XCTAssertEqual(
                areaIssues(forPriorityArea: invented).count, 1,
                "'\(invented)' resolves to the generic catalog and must say so."
            )
        }
    }

    func testRecognizedPriorityAreasAreNotFlagged() {
        for label in service.recognizedPriorityAreaLabels {
            XCTAssertTrue(
                areaIssues(forPriorityArea: label).isEmpty,
                "'\(label)' is a real profile and must not be flagged as unrecognized."
            )
        }
    }

    /// The warning exists to be seen, not to block. An invented area still produces a usable
    /// analysis — the owner just finds out that exercise selection was generic.
    func testUnrecognizedAreaWarnsButDoesNotBlockTheAnalysis() {
        let report = BodyAnalysisValidator.validate(
            analysis(priorityArea: "Posterior Chain"),
            photoAngles: ["Front", "Back", "Side (Left)", "Side (Right)"],
            bodyweightLbs: 200
        )

        XCTAssertTrue(report.isUsable, "An unrecognized area must not make the analysis unsaveable.")
        XCTAssertEqual(areaIssues(forPriorityArea: "Posterior Chain").first?.severity, .warning)
    }

    /// The check must agree with the behaviour it is guarding. `isRecognizedPriorityArea` saying
    /// "yes" while `priorityProfile(for:)` quietly hands back the generic catalog would put the
    /// silent-generic bug straight back. Tuple members have no key paths in Swift, so these stay
    /// closures.
    func testRecognitionCheckMatchesWhetherTheGenericCatalogIsUsed() {
        let genericNames = service.genericExerciseCatalog().map { $0.name }

        for invented in ["Posterior Chain", "V-Taper", "Quadz"] {
            XCTAssertFalse(service.isRecognizedPriorityArea(invented))
            XCTAssertEqual(
                service.priorityProfile(for: invented).accessoryCatalog.map { $0.name },
                genericNames,
                "'\(invented)' falls through to the generic catalog — that is what the warning reports."
            )
        }

        for label in service.recognizedPriorityAreaLabels {
            XCTAssertTrue(service.isRecognizedPriorityArea(label))
            XCTAssertNotEqual(
                service.priorityProfile(for: label).accessoryCatalog.map { $0.name },
                genericNames,
                "'\(label)' is a real profile and must bring its own movements."
            )
        }
    }

    func testBlankAreaIsNotTreatedAsRecognized() {
        XCTAssertFalse(service.isRecognizedPriorityArea(""))
        XCTAssertFalse(service.isRecognizedPriorityArea("   "))
    }

    // MARK: - Compound areas

    /// A compound area resolves to exactly one of the muscles it names, so the unrecognized check
    /// above cannot see it — it IS recognized. The rest of the request is dropped, which is the
    /// same halved-volume failure that made Biceps and Triceps collapse into one Arms priority.
    func testCompoundAreaIsDetectedEvenThoughItResolves() {
        let compound = "Biceps and Triceps"

        XCTAssertTrue(service.isRecognizedPriorityArea(compound), "Premise: it does resolve, which is why it was invisible.")
        XCTAssertTrue(service.priorityAreaNamesMultipleMuscles(compound))
        XCTAssertEqual(areaIssues(forPriorityArea: compound).count, 0, "It is not 'unrecognized' — a different warning covers it.")

        let report = BodyAnalysisValidator.validate(
            analysis(priorityArea: compound),
            photoAngles: ["Front", "Back", "Side (Left)", "Side (Right)"],
            bodyweightLbs: 200
        )
        XCTAssertEqual(
            report.issues.filter { $0.message.contains("names more than one muscle") }.count, 1,
            "A compound area must be reported rather than silently dropping a muscle."
        )
    }

    func testCompoundDetectionCoversTheCommonJoiners() {
        for compound in ["Biceps and Triceps", "Quads, Hamstrings", "Chest & Back", "Lats + Upper Back", "Glutes plus Hamstrings"] {
            XCTAssertTrue(
                service.priorityAreaNamesMultipleMuscles(compound),
                "'\(compound)' names several muscles."
            )
        }
    }

    /// The check is syntactic precisely because a structural one cannot work: broad profiles
    /// legitimately overlap specific ones, so "Upper Chest" fires both Upper Chest and Chest and
    /// "Lateral Deltoids" fires both Lateral Deltoids and Shoulders — both correct. No real area
    /// name may be flagged.
    func testNoRecognizedAreaNameIsMistakenForACompound() {
        for label in service.recognizedPriorityAreaLabels {
            XCTAssertFalse(
                service.priorityAreaNamesMultipleMuscles(label),
                "'\(label)' is a single recognized area and must not be flagged as compound."
            )
        }
    }
}
