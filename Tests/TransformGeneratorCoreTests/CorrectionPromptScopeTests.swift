import XCTest
@testable import Transform

/// What a paid correction pass is allowed to ask a menu-locked model to do.
///
/// Under menu lock the model owns reps, tempo, rest, targetRIR and note text. It may not add,
/// remove or swap an exercise, and it may not move a set count — those belong to the
/// deterministic allocator that built the menu before the call was made.
///
/// The regression pinned here: `correctionRequestBody` filtered the issue list with
/// `!isDemotedByMenuLock(issue)` alone, and that filter and `acceptableWarningIssuePatterns`
/// share no entry, so every one of the ten warnings survived it. A correction pass only runs
/// when the candidate also carries a correction-worthy finding, so those warnings rode along
/// into a prompt that says "fix ONLY the listed issues" and "the listed validator issues are
/// not optional". Nine of the ten can only be satisfied by breaking the lock.
@MainActor
final class CorrectionPromptScopeTests: XCTestCase {

    private let service = ClaudeService.shared

    /// A finding the model genuinely owns under lock, taken from the emitting site.
    private let repairable = "Day 3: notes contain load/rep progression instructions."

    private func correctionPrompt(issues: [String]) -> String? {
        let body = service.correctionRequestBody(
            config: ClaudeService.GenerationConfig(model: "test-model", maxTokens: 8192, timeout: 180),
            systemPrompt: "system",
            toolName: service.programToolName,
            toolSchema: [String: Any](),
            issues: issues,
            menuLocked: true,
            context: "context",
            originalUserPrompt: "original"
        )
        guard let messages = body["messages"] as? [[String: Any]],
              let content = messages.first?["content"] as? [[String: Any]] else {
            return nil
        }
        return content.first?["text"] as? String
    }

    // MARK: - The regression

    /// Verbatim from the emitting site in `validateBackBalance`. Its own text asks for "a
    /// rowing movement, not another pulldown variation" — an exercise the locked model is
    /// forbidden to add.
    func testACorrectionPassDoesNotAskALockedModelToAddAnExercise() {
        let noHorizontalPull = "The week trains the back with no horizontal pull at all — every "
            + "back movement pulls down from overhead. Vertical pulling does not load the "
            + "rhomboids and mid-traps in their shortened position, so this needs a rowing "
            + "movement, not another pulldown variation."

        XCTAssertEqual(
            service.validationDisposition(for: noHorizontalPull, menuLocked: true),
            .acceptableWarning,
            "Premise: this is a warning, so it only reaches the prompt alongside a repairable finding"
        )

        guard let prompt = correctionPrompt(issues: [repairable, noHorizontalPull]) else {
            return XCTFail("Correction body did not carry a user prompt")
        }

        XCTAssertTrue(
            prompt.contains("notes contain load/rep progression instructions"),
            "The finding the model owns must still be sent"
        )
        XCTAssertFalse(
            prompt.contains("no horizontal pull at all"),
            "A locked model cannot add a rowing movement, so paying to ask it to is waste at best"
        )
    }

    /// Set counts are the allocator's, not the model's.
    func testACorrectionPassDoesNotAskALockedModelToChangeSetCounts() {
        let belowFloor = "Day 2 exercise Cable Lateral Raise is prescribed 1 set(s), "
            + "below its role-based minimum of 2 set(s)."

        XCTAssertEqual(
            service.validationDisposition(for: belowFloor, menuLocked: true),
            .acceptableWarning
        )

        guard let prompt = correctionPrompt(issues: [repairable, belowFloor]) else {
            return XCTFail("Correction body did not carry a user prompt")
        }
        XCTAssertFalse(
            prompt.contains("below its role-based minimum of"),
            "Set counts belong to the deterministic allocator under menu lock"
        )
    }

    /// Every acceptable warning except the allow-listed one must be filtered. Driven off the
    /// real pattern list rather than a hand-copied sample, so a warning added later is covered
    /// the day it is added instead of the day someone remembers to extend this test.
    func testOnlyModelOwnedWarningsSurviveTheFilter() {
        for pattern in service.acceptableWarningIssuePatterns {
            let isModelOwned = service.matchesValidationIssue(
                pattern,
                patterns: service.modelOwnedAcceptableWarningPatterns
            )
            guard !isModelOwned else { continue }
            guard !service.isDemotedByMenuLock(pattern) else { continue }
            // A pattern that resolves to something other than a warning is another list's
            // business; this sweep only speaks for the acceptable-warning tier.
            guard service.validationDisposition(for: pattern, menuLocked: true) == .acceptableWarning else {
                continue
            }

            guard let prompt = correctionPrompt(issues: [repairable, pattern]) else {
                return XCTFail("Correction body did not carry a user prompt")
            }
            XCTAssertFalse(
                prompt.contains(pattern),
                "Warning the model cannot act on under lock reached a paid correction prompt: \(pattern)"
            )
        }
    }

    // MARK: - What must NOT be filtered

    /// The other half, and the reason this is an allow-list rather than "drop every warning":
    /// reps are the model's to write, so a rep-band leap is a free fix on a call already paid
    /// for. This mirrors `testACorrectionPassKeepsTheWarningsTheModelCanStillFix`.
    func testACorrectionPassKeepsARepBandLeap() {
        let repBands = "Day 2 exercise Lat Pulldown: rep prescription moved from 5-8 to 15-20, "
            + "which is 3 rep bands in one week. The working load has to move with it."

        XCTAssertEqual(service.validationDisposition(for: repBands, menuLocked: true), .acceptableWarning)

        guard let prompt = correctionPrompt(issues: [repairable, repBands]) else {
            return XCTFail("Correction body did not carry a user prompt")
        }
        XCTAssertTrue(
            prompt.contains("rep bands in one week"),
            "Reps are the model's field under lock — this one it can still repair"
        )
    }

    /// The existing fallback must survive: when nothing repairable is left, send what we were
    /// given rather than a correction request with an empty issue list. The debug paths rely
    /// on this, because they correct whenever the issue list is non-empty.
    func testAnAllWarningIssueListStillSendsSomething() {
        let noHorizontalPull = "The week trains the back with no horizontal pull at all — every "
            + "back movement pulls down from overhead."

        guard let prompt = correctionPrompt(issues: [noHorizontalPull]) else {
            return XCTFail("Correction body did not carry a user prompt")
        }
        XCTAssertTrue(
            prompt.contains("no horizontal pull at all"),
            "With nothing else to send, the original list is still the best available request"
        )
    }
}
