#!/usr/bin/env python3
"""Self-test for check_validator_patterns.py — every way it has been broken so far.

The checker exists because a validator pattern matching no emitted message is invisible.
The checker itself then had that same bug three separate times, each found by an adversarial
audit rather than by reading it:

  1. it validated a pattern against its own declaration;
  2. it validated a pattern against CONSUMER code (`containsAnyFragment`, `correctionTactics`);
  3. it validated a pattern against ANY literal in a file that emitted something somewhere —
     an unused constant, or a string in a neighbouring regex array, counted as proof.

It also failed in the other direction: a trailing comment after a list's closing bracket made
the parser overrun into unrelated code and condemn fourteen live patterns.

Each of those is an attack below. A checker whose own regressions are not pinned is the thing
it was written to prevent.

Run: python3 tools/test_check_validator_patterns.py
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FAKE = "zzqx fabricated phrase no emitter produces"

DISPOSITION = "Transform/Transform/WorkoutGeneratorService+ParsingValidation.swift"
NOTICE = "Transform/Transform/WorkoutValidatorNotice.swift"
REQUESTS = "Transform/Transform/WorkoutGeneratorService+Requests.swift"
LIST_ANCHOR = "    var correctionWorthyIssuePatterns: [String] {\n        [\n"


def run(tree):
    result = subprocess.run(
        [sys.executable, "tools/check_validator_patterns.py"],
        cwd=tree, capture_output=True, text=True,
    )
    return result.returncode, result.stdout + result.stderr


def edit(tree, relative, old, new):
    """Replace the FIRST occurrence of `old`. Fails loudly if the anchor has moved."""
    path = pathlib.Path(tree) / relative
    text = path.read_text(encoding="utf-8")
    assert old in text, "anchor no longer present in %s — update this attack" % relative
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def add_fake_pattern(tree):
    edit(tree, DISPOSITION, LIST_ANCHOR, LIST_ANCHOR + '            "%s",\n' % FAKE)


# --- attacks: each must be CAUGHT (exit 1) -----------------------------------------------

def attack_no_mirror(tree):
    """The plain case: a pattern nothing anywhere produces."""
    add_fake_pattern(tree)


def attack_consumer_notice(tree):
    """Hidden in WorkoutValidatorNotice's multi-line containsAnyFragment array."""
    add_fake_pattern(tree)
    anchor = '        if containsAnyFragment(issue, [\n'
    edit(tree, NOTICE, anchor, anchor + '            "%s",\n' % FAKE)


def attack_consumer_tactics(tree):
    """Hidden in correctionTactics, which matches via `issues.contains(where:)`."""
    add_fake_pattern(tree)
    anchor = "    func correctionTactics(for issues: [String]) -> String {\n"
    edit(tree, REQUESTS, anchor,
         anchor + '        if issues.contains(where: { $0.contains("%s") }) { }\n' % FAKE)


def attack_unused_literal(tree):
    """An UNUSED constant inside a file that emits findings elsewhere."""
    add_fake_pattern(tree)
    anchor = "extension ClaudeService {"
    edit(tree, DISPOSITION, anchor,
         anchor + '\n    private var _unused: String { "%s" }\n' % FAKE)


def attack_neighbouring_array(tree):
    """Inside a real non-append consumer array in an emitting file (the regex list)."""
    add_fake_pattern(tree)
    path = pathlib.Path(tree) / DISPOSITION
    text = path.read_text(encoding="utf-8")
    anchor = "let holdPatterns"
    assert anchor in text, "holdPatterns anchor moved; update this attack"
    index = text.index("[", text.index(anchor))
    path.write_text(text[:index + 1] + '\n            "%s",' % FAKE + text[index + 1:],
                    encoding="utf-8")


def attack_concat_fabrication(tree):
    """Two literals welded into a string no code path emits.

    The old checker deleted lines containing `.contains(` and THEN merged `" + "` across the
    whole file, so a ternary sandwiched between two literals vanished and the halves fused
    into a string nothing produces. Line deletion is gone and the merge is per-span, so the
    fused form must no longer vouch for anything.
    """
    path = pathlib.Path(tree) / DISPOSITION
    text = path.read_text(encoding="utf-8")
    anchor = "extension ClaudeService {"
    injected = anchor + \
        '\n    func _fabricate(_ issue: String) -> [String] {\n' \
        '        var issues: [String] = []\n' \
        '        issues.append(\n' \
        '            "zzqx fabricated LEFT half" +\n' \
        '            (issue.contains("bait") ? "x" : "y") +\n' \
        '            " and fabricated RIGHT half"\n' \
        '        )\n' \
        '        return issues\n' \
        '    }\n'
    text = text.replace(anchor, injected, 1)
    fused = "zzqx fabricated LEFT half and fabricated RIGHT half"
    text = text.replace(LIST_ANCHOR, LIST_ANCHOR + '            "%s",\n' % fused, 1)
    path.write_text(text, encoding="utf-8")


def attack_exercise_keyword_collision(tree):
    """A nonsense pattern that collides with an exercise-keyword list.

    "skull crusher" is a real literal in an exercise-keyword array. Under the
    return-[...]-anywhere rule it fully vouched for itself as a validator pattern.
    """
    edit(tree, DISPOSITION, LIST_ANCHOR, LIST_ANCHOR + '            "skull crusher",\n')


def attack_catalogue_literal(tree):
    """A pattern lifted from the procedural fallback's exercise catalogue."""
    edit(tree, DISPOSITION, LIST_ANCHOR, LIST_ANCHOR + '            "Seated Cable Row",\n')


ATTACKS = [
    ("dead pattern, mirrored nowhere", attack_no_mirror),
    ("hidden in containsAnyFragment", attack_consumer_notice),
    ("hidden in correctionTactics", attack_consumer_tactics),
    ("hidden in an unused constant", attack_unused_literal),
    ("hidden in a neighbouring array", attack_neighbouring_array),
    ("welded from two unconcatenated literals", attack_concat_fabrication),
    ("an exercise keyword, not a finding", attack_exercise_keyword_collision),
    ("a catalogue exercise name", attack_catalogue_literal),
]


# --- benign edits: each must still PASS (exit 0) ------------------------------------------

def benign_reindent(tree):
    """Cosmetic reindent of a list's closing bracket."""
    path = pathlib.Path(tree) / DISPOSITION
    text = path.read_text(encoding="utf-8")
    anchor = "    var acceptableWarningIssuePatterns: [String] {\n"
    index = text.index("\n        ]\n", text.index(anchor))
    path.write_text(text[:index] + "\n            ]\n" + text[index + len("\n        ]\n"):],
                    encoding="utf-8")


def benign_trailing_comment(tree):
    """A trailing comment after the LAST list's closing bracket.

    This one used to make the parser run ~215 lines into unrelated code and condemn
    fourteen live patterns, printing their own emitted text as proof they were dead.
    """
    path = pathlib.Path(tree) / DISPOSITION
    text = path.read_text(encoding="utf-8")
    anchor = "    var menuLockedDemotionPatterns: [String] {\n"
    index = text.index("\n        ]\n", text.index(anchor))
    path.write_text(text[:index] + "\n        ] // trailing note\n"
                    + text[index + len("\n        ]\n"):], encoding="utf-8")


def _add_validator(tree, body_lines, message):
    """Add a real `validate*` function using `body_lines`, and its pattern."""
    path = pathlib.Path(tree) / DISPOSITION
    text = path.read_text(encoding="utf-8")
    anchor = "extension ClaudeService {"
    func = anchor + "\n    func validateSyntheticShape() -> [String] {\n" + body_lines + "    }\n"
    text = text.replace(anchor, func, 1)
    text = text.replace(LIST_ANCHOR, LIST_ANCHOR + '            "%s",\n' % message, 1)
    path.write_text(text, encoding="utf-8")


def benign_plus_equals_shape(tree):
    """`issues += [...]` — ordinary Swift, invisible to every syntax-enumerating rule."""
    message = "uses the plus-equals emission shape"
    _add_validator(
        tree,
        '        var issues: [String] = []\n'
        '        issues += ["A day plan %s for findings."]\n'
        '        return issues\n' % message,
        message,
    )


def benign_let_then_return_shape(tree):
    """`let messages = [...]; return messages` — the natural refactor of a bare return."""
    message = "uses the let-then-return emission shape"
    _add_validator(
        tree,
        '        let messages = ["A day plan %s for findings."]\n'
        '        return messages\n' % message,
        message,
    )


BENIGN = [
    ("cosmetic reindent", benign_reindent),
    ("trailing comment after a list", benign_trailing_comment),
    ("issues += [...] emission shape", benign_plus_equals_shape),
    ("let-then-return emission shape", benign_let_then_return_shape),
]


def main():
    failures = []

    code, output = run(ROOT)
    if code != 0:
        print("BASELINE FAILED — the real tree does not pass:\n%s" % output)
        return 1
    print("PASS  baseline: the real tree is clean")

    for label, mutate in ATTACKS:
        with tempfile.TemporaryDirectory() as scratch:
            tree = pathlib.Path(scratch) / "repo"
            shutil.copytree(ROOT, tree, ignore=shutil.ignore_patterns(".git", "__pycache__"))
            mutate(tree)
            code, output = run(tree)
            if code == 1 and any(t in output for t in ("zzqx", "skull crusher", "Seated Cable Row")):
                print("PASS  caught: %s" % label)
            else:
                failures.append("NOT CAUGHT: %s (exit %d)\n%s" % (label, code, output))

    for label, mutate in BENIGN:
        with tempfile.TemporaryDirectory() as scratch:
            tree = pathlib.Path(scratch) / "repo"
            shutil.copytree(ROOT, tree, ignore=shutil.ignore_patterns(".git", "__pycache__"))
            mutate(tree)
            code, output = run(tree)
            if code == 0:
                print("PASS  tolerated: %s" % label)
            else:
                failures.append("FALSE POSITIVE: %s (exit %d)\n%s" % (label, code, output))

    if failures:
        print("\n" + "\n\n".join(failures))
        return 1
    print("\nOK: every known attack is caught and every benign edit is tolerated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
