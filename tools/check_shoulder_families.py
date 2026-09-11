#!/usr/bin/env python3
"""Fail if the shoulder phrase tables can no longer reach a movement a lifter might name.

WHY THIS EXISTS
---------------
Shoulder caution is evidence-bound: a movement is treated carefully only when the lifter's own
injury note reaches it, by name or by the everyday words for its family. That is the behaviour the
owner asked for. It has one failure mode, it is silent, and it happened three times in a single
session: a family is missing or unreachable, a real complaint matches nothing, and the app is
LESS careful than it reports being. Nothing catches that. It compiles, no test fails, and the
generated week looks fine.

Four structural invariants hold the mechanism together. The first three have each been broken
once; the fourth was added after an audit found this script asserting a coverage claim it had
never actually evaluated.

  1. EVERY FAMILY IS IN THE SPECIFICITY UNION. `reportNamesAnyMovement` decides whether a report
     named a movement at all, and it builds its word list by naming each family. Add a family to
     `shoulderFamilyPhrases` and forget to name it there, and a report using only that family's
     words reads as naming NO movement, so caution falls back to broad. That is the safe
     direction, but it means the narrowing the owner asked for silently stops applying.

  2. EVERY FILTERED WORD IS REAL. `reportNamesAnyMovement` removes anatomy words from its union so
     that naming a body part does not count as naming a movement. Those words are matched by
     EXACT STRING against the phrases the families produce. A filter entry that matches no phrase
     does nothing while reading as protection, which is how "straight-arm" and "straight arm"
     had to be listed separately.

  3. EVERY MOVEMENT THAT CAN BE CHARGED SHOULDER LOAD CAN BE NAMED. `exerciseJointStress` charges
     shoulder load per set to a list of movement patterns. If one of those patterns has no family,
     the only way a report can ever reach it is by writing the exercise's exact catalogue name.

  4. EVERY SHOULDER-ISH PATTERN THE APP CAN PRODUCE HAS A FAMILY, OR A WRITTEN REASON NOT TO.
     `EXPECTED_NO_FAMILY` is that list of reasons. This invariant is only as good as the set of
     patterns the parser can see, which is why `parse_declared_patterns` reads ternaries too:
     `movementPattern: rowLikePattern ? "Row" : "Pull"` produces a real pattern, and an earlier
     regex that demanded a quote straight after the colon skipped it. "Pull" was therefore never
     put to this decision at all while the script printed OK.

WHAT IT DOES NOT DO
-------------------
  - It does not judge whether a family's WORDS are the right words. No script knows how a person
    writes about a sore shoulder. That is what the table in `ShoulderReportCorpusTests` is for,
    and the two are meant to be read together: this one proves the wiring, that one proves the
    vocabulary.
  - It does not analyse reachability. A branch inside `if false` still counts.

Parsing is by brace matching over a named function body, not by scanning whole files, and every
extraction step fails LOUDLY with the name it could not find rather than passing on an empty
result. A checker that silently measures nothing is worse than no checker.

Run: python3 tools/check_shoulder_families.py
Self-test: python3 tools/test_check_shoulder_families.py
"""
import re
import sys
import pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent
SELECTION = REPO / "Transform" / "Transform" / "WorkoutGeneratorService+ExerciseSelection.swift"
METADATA = REPO / "Transform" / "Transform" / "WorkoutGeneratorService+MetadataProfiles.swift"

# Patterns that deliberately have no family, each with the reason. Deliberately small and
# deliberately annoying to add to: every entry is a movement a report can only reach by exact name.
EXPECTED_NO_FAMILY = {
    "Press": 'the generic press pattern. A bare "press" phrase would match almost any report '
             "mentioning pressing and would re-create the blanket penalty through the widest door.",
    "Pressdown": "a triceps movement. It loads the elbow, not the shoulder joint.",
    "Calf Raise": 'shares the word "raise" with a shoulder family and nothing else.',
    "Leg Raise": 'shares the word "raise" with a shoulder family and nothing else.',
    "Pull": 'the generic pull pattern, the mirror of "Press" above. `inferredExerciseMetadata` '
            "gives it to a back-targeted name it can place no more precisely than that. A bare "
            '"pull" phrase would swallow pulldown, pull-up, pull-apart and face pull reports at '
            "once, which is the blanket behaviour the families exist to end.",
}

# Union entries that deliberately contribute NO words to the specificity check, with the reason.
EXPECTED_NO_PHRASES = {
    "Shoulder": "its family is the joint words themselves, and those must never prove that a "
                "report named a MOVEMENT — `hasShoulderRisk` already requires one of them, so "
                "counting them would make every report look specific and switch off the broad "
                "fallback entirely.",
}

# Words in a pattern name that make it worth asking whether a shoulder report could name it.
SHOULDER_ISH = ("press", "row", "pull", "raise", "fly", "dip", "delt", "shoulder")


class CheckFailed(Exception):
    pass


def function_body(source, signature_start, what):
    """The braces-balanced body of the first function whose declaration starts with the given text."""
    at = source.find(signature_start)
    if at < 0:
        raise CheckFailed(f"could not find {what} (looked for {signature_start!r})")
    opened = source.find("{", at)
    if opened < 0:
        raise CheckFailed(f"found {what} but no opening brace")
    depth = 0
    for index in range(opened, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opened + 1:index]
    raise CheckFailed(f"unbalanced braces in {what}")


def string_literals(text):
    return re.findall(r'"([^"\\\n]*)"', text)


def parse_families(source):
    """{branch key: [phrases]} from `shoulderFamilyPhrases`, in declaration order."""
    body = function_body(
        source,
        "func shoulderFamilyPhrases(forMovementPattern",
        "shoulderFamilyPhrases",
    )
    families = []
    for match in re.finditer(r'pattern\.contains\(("(?:[^"\\\n]*)"(?:\s*\)\s*\|\|\s*pattern\.contains\("[^"\\\n]*")*)\)', body):
        keys = string_literals(match.group(1))
        tail = body[match.end():]
        ret = re.search(r'return\s*\[(.*?)\]', tail, re.S)
        if not ret:
            raise CheckFailed(f"family branch {keys!r} has no return list")
        phrases = string_literals(ret.group(1))
        if not phrases:
            raise CheckFailed(f"family branch {keys!r} returns no phrases")
        families.append((keys, phrases))
    if not families:
        raise CheckFailed("shoulderFamilyPhrases declared no families at all")
    return families


def resolve(families, pattern):
    """Mirror of the Swift function: first branch whose key is contained in the pattern wins."""
    lowered = pattern.lower()
    for keys, phrases in families:
        if any(key in lowered for key in keys):
            return keys, phrases
    return None, []


def parse_specificity_union(source):
    """(filtered words, pattern names) from `reportNamesAnyMovement`."""
    body = function_body(
        source,
        "func reportNamesAnyMovement(",
        "reportNamesAnyMovement",
    )
    filtered = re.search(r'jointAndMuscleWords:\s*Set<String>\s*=\s*\[(.*?)\]', body, re.S)
    if not filtered:
        raise CheckFailed("reportNamesAnyMovement declares no jointAndMuscleWords set")
    names = re.search(r'let movementPhrases\s*=\s*\[(.*?)\]', body, re.S)
    if not names:
        raise CheckFailed("reportNamesAnyMovement declares no movementPhrases list")
    return string_literals(filtered.group(1)), string_literals(names.group(1))


def parse_shoulder_loaded_patterns(source):
    """Movement patterns `exerciseJointStress` charges shoulder load to."""
    body = function_body(source, "func exerciseJointStress(", "exerciseJointStress")
    guard = body.find("shoulderIsReported {")
    if guard < 0:
        raise CheckFailed("exerciseJointStress has no shoulder block gated on shoulderIsReported")
    depth = 0
    end = None
    for index in range(body.find("{", guard), len(body)):
        if body[index] == "{":
            depth += 1
        elif body[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    if end is None:
        raise CheckFailed("unbalanced braces in the shoulder block of exerciseJointStress")
    block = body[guard:end]
    patterns = []
    for match in re.finditer(r'containsAny\(pattern,\s*keywords:\s*\[(.*?)\]', block, re.S):
        patterns.extend(string_literals(match.group(1)))
    if not patterns:
        raise CheckFailed("the shoulder block of exerciseJointStress charges no patterns")
    return patterns


def parse_declared_patterns(source):
    """Every movement pattern the app can attach to an exercise.

    Both shapes count. `movementPattern: "Row"` is the common one; `movementPattern: cond ? "Row"
    : "Pull"` is real too, and the regex that demanded a quote straight after the colon silently
    skipped both of its branches. That is how "Pull" stayed out of the EXPECTED_NO_FAMILY decision
    while this script reported clean.
    """
    declared = set()
    for line in source.splitlines():
        at = line.find("movementPattern:")
        if at < 0:
            continue
        declared.update(re.findall(r'"([^"\\]+)"', line[at:]))
    declared = sorted(declared)
    if not declared:
        raise CheckFailed("no movementPattern literals found in the metadata source")
    return declared


def run(selection_source, metadata_source):
    families = parse_families(selection_source)
    filtered_words, union_patterns = parse_specificity_union(selection_source)
    loaded_patterns = parse_shoulder_loaded_patterns(metadata_source)
    declared_patterns = parse_declared_patterns(metadata_source)

    problems = []

    # 1. Every family is reachable from the specificity union AND actually contributes words.
    #
    # "Named" is the weaker claim and was the one being checked. A family every one of whose
    # phrases is filtered out by `jointAndMuscleWords` contributes nothing, which is the same
    # failure as omitting it and is invisible from the union list alone. `EXPECTED_NO_PHRASES`
    # is the deliberate case: a movement whose pattern IS "Shoulder" is reached by a report
    # naming the shoulder, and the joint words are exactly what must not prove specificity.
    reached = set()
    for name in union_patterns:
        keys, phrases = resolve(families, name)
        if keys is None:
            problems.append(
                f'`reportNamesAnyMovement` lists "{name}", which resolves to no family. '
                "It contributes nothing to the specificity check."
            )
            continue
        reached.add(tuple(keys))
        surviving = [phrase for phrase in phrases if phrase not in filtered_words]
        if not surviving and name not in EXPECTED_NO_PHRASES:
            problems.append(
                f'family {keys!r} contributes no words to the specificity check: every phrase '
                "it returns is filtered out by `jointAndMuscleWords`. Naming it in "
                "`reportNamesAnyMovement` does nothing. Add it to EXPECTED_NO_PHRASES with the "
                "reason, or stop filtering one of its phrases."
            )
    for keys, _ in families:
        if tuple(keys) not in reached:
            problems.append(
                f"family {keys!r} is in `shoulderFamilyPhrases` but no pattern in "
                "`reportNamesAnyMovement` resolves to it. A report using only that family's words "
                "will read as naming no movement, and caution will stop narrowing."
            )

    # 2. Every filtered word is a word some family actually produces.
    all_phrases = {phrase for _, phrases in families for phrase in phrases}
    for word in filtered_words:
        if word not in all_phrases:
            problems.append(
                f'`jointAndMuscleWords` filters "{word}", which no family produces. '
                "It removes nothing and reads as protection that is not there."
            )

    # 3. Every pattern that can be charged shoulder load can be named.
    for pattern in loaded_patterns:
        keys, phrases = resolve(families, pattern)
        if not phrases:
            problems.append(
                f'`exerciseJointStress` charges shoulder load to "{pattern}", which has no family. '
                "Only the exact catalogue name can ever reach it."
            )

    # 4. Every shoulder-ish pattern the app can produce has a family, or a written reason not to.
    for pattern in declared_patterns:
        if not any(word in pattern.lower() for word in SHOULDER_ISH):
            continue
        _, phrases = resolve(families, pattern)
        if phrases:
            if pattern in EXPECTED_NO_FAMILY:
                problems.append(
                    f'"{pattern}" is listed in EXPECTED_NO_FAMILY but now HAS a family. '
                    "Remove the entry so the list keeps meaning something."
                )
            continue
        if pattern not in EXPECTED_NO_FAMILY:
            problems.append(
                f'movement pattern "{pattern}" has no family in `shoulderFamilyPhrases`. '
                "A report naming it reaches nothing. Add a family, or add it to "
                "EXPECTED_NO_FAMILY with the reason."
            )

    return {
        "families": families,
        "union_patterns": union_patterns,
        "filtered_words": filtered_words,
        "loaded_patterns": loaded_patterns,
        "declared_patterns": declared_patterns,
        "problems": problems,
    }


def main():
    try:
        result = run(SELECTION.read_text(), METADATA.read_text())
    except CheckFailed as error:
        print(f"FAILED to read the shoulder tables: {error}")
        return 1

    print(
        f"families: {len(result['families'])}; "
        f"specificity union: {len(result['union_patterns'])} patterns, "
        f"{len(result['filtered_words'])} filtered words; "
        f"shoulder-loaded patterns: {len(result['loaded_patterns'])}; "
        f"declared patterns: {len(result['declared_patterns'])}"
    )
    for pattern, reason in sorted(EXPECTED_NO_FAMILY.items()):
        print(f"  no family on purpose: {pattern} — {reason}")

    if result["problems"]:
        print()
        for problem in result["problems"]:
            print(f"PROBLEM: {problem}")
        return 1

    print("\nOK: every family is reachable, every filter bites, every charged pattern can be named.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
