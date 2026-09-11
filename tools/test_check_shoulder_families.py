#!/usr/bin/env python3
"""Self-test for check_shoulder_families.py.

A checker is only worth its runtime if it FAILS on the things it claims to catch. Each case below
is a real way the shoulder tables have broken or could break, applied to a synthetic source, plus
benign edits that must NOT trip it. The real sources are also run once, so a parser that has
drifted away from the code it reads is caught here rather than in CI.

Run: python3 tools/test_check_shoulder_families.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_shoulder_families as checker


SELECTION = '''
extension ClaudeService {
    func shoulderFamilyPhrases(forMovementPattern pattern: String) -> [String] {
        if pattern.contains("vertical press") {
            return ["overhead press", "overhead"]
        }
        if pattern.contains("dip") {
            return ["dip"]
        }
        if pattern.contains("close-grip press") || pattern.contains("close grip press") {
            return ["close grip", "close-grip"]
        }
        if pattern.contains("rear delt") {
            return ["rear delt", "fly", "row"]
        }
        if pattern.contains("row") {
            return ["row", "rowing"]
        }
        if pattern.contains("shoulder") {
            return ["shoulder", "delt"]
        }
        return []
    }

    func reportNamesAnyMovement(_ normalizedReport: String) -> Bool {
        let jointAndMuscleWords: Set<String> = ["shoulder", "delt", "rear delt"]
        let movementPhrases = [
            "Vertical Press", "Dip", "Close-Grip Press", "Rear Delt", "Row", "Shoulder"
        ]
        .flatMap { shoulderFamilyPhrases(forMovementPattern: normalizedPriorityText($0)) }
        .filter { !jointAndMuscleWords.contains($0) }
        return containsPluralTolerantPriorityPhrase(in: normalizedReport, keywords: movementPhrases)
    }
}
'''

METADATA = '''
extension ClaudeService {
    func exerciseJointStress(for exercise: WorkoutExerciseResponse, injuryRiskFocus: String) -> JointStressBudget {
        var stress = JointStressBudget()
        if shoulderIsReported {
            if containsAny(pattern, keywords: ["vertical press", "dip"]) {
                stress.shoulder += 1
            } else if containsAny(pattern, keywords: ["row"]) {
                stress.shoulder += 2
            }
        }
        if containsAny(pattern, keywords: ["curl"]) {
            stress.elbow += 1
        }
        return stress
    }

    static let catalog = [
        ExerciseMetadata(canonicalName: "A", movementPattern: "Vertical Press", fatigueCost: 2),
        ExerciseMetadata(canonicalName: "B", movementPattern: "Dip", fatigueCost: 2),
        ExerciseMetadata(canonicalName: "C", movementPattern: "Row", fatigueCost: 2),
        ExerciseMetadata(canonicalName: "D", movementPattern: "Curl", fatigueCost: 1),
        ExerciseMetadata(canonicalName: "E", movementPattern: "Press", fatigueCost: 2),
    ]
}
'''

PASSES = 0
FAILURES = []


def check(label, selection, metadata, must_fail, expect_phrase=None):
    global PASSES
    try:
        result = checker.run(selection, metadata)
        problems = result["problems"]
    except checker.CheckFailed as error:
        problems = [f"parse failure: {error}"]

    failed = bool(problems)
    if failed != must_fail:
        FAILURES.append(
            f"{label}: expected {'a failure' if must_fail else 'a pass'}, got "
            + ("; ".join(problems) if problems else "no problems")
        )
        return
    if expect_phrase and not any(expect_phrase in problem for problem in problems):
        FAILURES.append(f"{label}: caught, but no problem mentioned {expect_phrase!r}: {problems}")
        return
    PASSES += 1
    print(f"PASS  {label}")


# ---- The baseline holds -------------------------------------------------------------------
check("baseline: the synthetic source is clean", SELECTION, METADATA, must_fail=False)

# ---- Attacks ------------------------------------------------------------------------------
check(
    "attack: a family exists but nothing in the specificity union reaches it",
    SELECTION.replace(
        'if pattern.contains("row") {',
        'if pattern.contains("face pull") {\n            return ["face pull"]\n        }\n        if pattern.contains("row") {',
    ),
    METADATA,
    must_fail=True,
    expect_phrase="stop narrowing",
)

check(
    "attack: the specificity union names a pattern with no family",
    SELECTION.replace('"Row", "Shoulder"', '"Row", "Shoulder", "Hip Thrust"'),
    METADATA,
    must_fail=True,
    expect_phrase="resolves to no family",
)

check(
    "attack: a filtered anatomy word that no family produces",
    SELECTION.replace(
        '["shoulder", "delt", "rear delt"]',
        '["shoulder", "delt", "rear delt", "scapular"]',
    ),
    METADATA,
    must_fail=True,
    expect_phrase="removes nothing",
)

check(
    "attack: shoulder load charged to a pattern that can only be reached by exact name",
    SELECTION,
    METADATA.replace('["vertical press", "dip"]', '["vertical press", "dip", "lateral raise"]'),
    must_fail=True,
    expect_phrase="has no family",
)

check(
    "attack: a new shoulder-ish movement pattern with no family and no written reason",
    SELECTION,
    METADATA.replace(
        'movementPattern: "Curl"',
        'movementPattern: "Landmine Press"',
    ),
    must_fail=True,
    expect_phrase="reaches nothing",
)

check(
    "attack: a family branch emptied out",
    SELECTION.replace('return ["dip"]', "return []"),
    METADATA,
    must_fail=True,
    expect_phrase="parse failure",
)

check(
    "attack: the family function renamed, so the checker would measure nothing",
    SELECTION.replace("func shoulderFamilyPhrases(forMovementPattern", "func shoulderWords(forPattern"),
    METADATA,
    must_fail=True,
    expect_phrase="parse failure",
)

check(
    "attack: the shoulder block un-gated, so the checker would read the wrong scope",
    SELECTION,
    METADATA.replace("if shoulderIsReported {", "if true {"),
    must_fail=True,
    expect_phrase="parse failure",
)

check(
    "attack: a movement pattern written as a ternary, which the parser must still see",
    SELECTION,
    METADATA.replace(
        'movementPattern: "Curl", fatigueCost: 1',
        'movementPattern: rowLike ? "Row" : "Shoulder Pull", fatigueCost: 1',
    ),
    must_fail=True,
    expect_phrase="reaches nothing",
)

check(
    "attack: a family whose every phrase is filtered out, so it contributes nothing",
    SELECTION.replace(
        '["shoulder", "delt", "rear delt"]',
        '["shoulder", "delt", "rear delt", "dip"]',
    ),
    METADATA,
    must_fail=True,
    expect_phrase="contributes no words",
)

# ---- Benign edits that must be tolerated ---------------------------------------------------
check(
    "tolerated: a phrase added to an existing family",
    SELECTION.replace('["overhead press", "overhead"]', '["overhead press", "overhead", "military press"]'),
    METADATA,
    must_fail=False,
)

check(
    "tolerated: a new movement pattern with nothing shoulder-ish in its name",
    SELECTION,
    METADATA.replace('movementPattern: "Curl"', 'movementPattern: "Sled Drag"'),
    must_fail=False,
)

check(
    "tolerated: a second keyword spelling on one branch",
    SELECTION.replace(
        'if pattern.contains("dip") {',
        'if pattern.contains("dip") || pattern.contains("dips") {',
    ),
    METADATA,
    must_fail=False,
)

# ---- And the real sources, so parser drift is caught here ----------------------------------
real = checker.run(checker.SELECTION.read_text(), checker.METADATA.read_text())
if len(real["families"]) < 10:
    FAILURES.append(f"real source: only {len(real['families'])} families parsed — the parser has drifted")
elif real["problems"]:
    FAILURES.append("real source: " + "; ".join(real["problems"]))
else:
    PASSES += 1
    print(f"PASS  real source parses ({len(real['families'])} families) and is clean")

print()
if FAILURES:
    for failure in FAILURES:
        print(f"FAIL  {failure}")
    sys.exit(1)
print(f"OK: {PASSES} checks — every known attack is caught and every benign edit is tolerated.")
