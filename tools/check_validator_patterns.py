#!/usr/bin/env python3
"""Fail if a workout-validator disposition pattern matches no message the app can emit.

WHY THIS EXISTS
---------------
`validationDisposition` classifies a validator finding by plain substring containment
against four hand-maintained pattern lists. A pattern that matches nothing is invisible:
it changes no behaviour, breaks no test, and reads exactly like coverage. Two shipped that
way and were only found by adversarial audit.

WHY IT LOOKS LIKE THIS (four rebuilds, each after being broken)
---------------------------------------------------------------
Every earlier version defined the corpus by guessing at SYNTAX, and every one was defeated
by syntax it had not guessed:

  1. "every string literal in the source" — a pattern matched its own DECLARATION.
  2. "...minus lines containing `issue.contains(` or `matchesValidationIssue`" — defeated by
     `containsAnyFragment(issue, [...])`, whose array spans lines carrying neither, and by
     `issues.contains(where:)`, which does not contain the substring "issue.contains(".
  3. "any literal in a FILE that emits a finding" — measured 7.4% signal. An UNUSED constant,
     or a literal in a neighbouring regex array, vouched for a pattern.
  4. "literals inside `issues.append(...)` and `return [...]` spans" — `return [` matches
     EVERY array and dictionary return in every file, so ~80% of that corpus was exercise
     catalogues, muscle-group tables, JSON request keys, and two unrelated validation
     pipelines (Body Analysis, Nutrition) that never reach `validationDisposition`. The
     nonsense pattern "skull crusher" passed, vouched for by an exercise-keyword list.

Enumerating emission syntax cannot work: `issues.append(x)`, `issues += [x]`, `return [x]`,
and `let m = [x]; return m` are all ordinary Swift, and the next one is not on any list.

So the corpus is now scoped by FUNCTION, not by syntax and not by file: the bodies of the
`validate*` functions in `WorkoutGeneratorService*.swift`. Those are the functions whose
output reaches `validationDisposition`. Every emission shape inside one is covered because
the whole body is read, and no shape outside one counts. That is ~195 literals against 2268
under rule 1.

A validator added under a name that does not start with `validate` will have its patterns
reported dead. That is a LOUD failure naming the pattern, not a silent pass, and the fix is
to make VALIDATOR_FUNCTION aware of it.

LIMITS, STATED RATHER THAN HIDDEN
---------------------------------
  - Interpolated messages (`"...exceeds its \\(capContext) direct-set cap..."`) cannot be
    resolved statically. Those patterns live in ALLOWED_VIA_INTERPOLATION, each naming its
    emitter — deliberately small and deliberately annoying to add to.
  - Reachability is not analysed. A literal inside `if false { }` still counts. A text
    checker cannot know what runs.

Run: python3 tools/check_validator_patterns.py
Self-test: python3 tools/test_check_validator_patterns.py
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Transform" / "Transform"
DISPOSITION_FILE = SRC / "WorkoutGeneratorService+ParsingValidation.swift"

# Only the workout generator's own validation surface. BodyAnalysisModels.swift and
# NutritionGeneratorService.swift also contain `validate*` functions, but they feed separate
# pipelines that never reach `validationDisposition`; including them let their messages
# vouch for workout patterns.
VALIDATOR_SOURCES = "WorkoutGeneratorService*.swift"

# The functions whose output is classified by `validationDisposition`.
VALIDATOR_FUNCTION = re.compile(r"\bfunc\s+(validate[A-Za-z0-9_]*)\s*[(<]")

PATTERN_LISTS = [
    "lockedMenuHardFailurePatterns",
    "acceptableWarningIssuePatterns",
    "correctionWorthyIssuePatterns",
    "menuLockedDemotionPatterns",
]

LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

# Adjacent literals joined by `+` are one runtime string.
CONCATENATION = re.compile(r'"\s*\+\s*"')

# Swift raw strings. Used in this repo for regexes, never for validator messages, and their
# unescaped quotes desync a naive scanner — so they are removed before anything else runs.
RAW_STRING = re.compile(r'#+"(?:.|\n)*?"#+')

ALLOWED_VIA_INTERPOLATION = {
    # ParsingValidation builds the cap kind separately:
    #     let capContext = ... ? "focus-day" : "per-session"
    #     "Blueprint priority '\(...)' exceeds its \(capContext) direct-set cap on day ..."
    "exceeds its focus-day direct-set cap":
        "ParsingValidation.swift capContext ternary + the direct-set cap message",
    "exceeds its per-session direct-set cap":
        "ParsingValidation.swift capContext ternary + the direct-set cap message",
}


def strip_noise(text):
    """Remove raw strings and `//` comments without truncating a string literal.

    Two real bugs this has had: `re.sub(r"//[^\\n]*", "")` ate the tail of the line holding
    `URL(string: "https://...")`, and the line-by-line replacement that fixed it reset quote
    state at every newline so a `//` inside a `\"\"\"` block was still cut. This scans once,
    tracking `"` and `\"\"\"` across lines.
    """
    text = RAW_STRING.sub('""', text)
    out = []
    index = 0
    in_line_string = False
    in_block_string = False
    while index < len(text):
        if text.startswith("\\", index) and (in_line_string or in_block_string):
            out.append(text[index:index + 2])
            index += 2
            continue
        if text.startswith('"""', index):
            if not in_line_string:
                in_block_string = not in_block_string
            out.append('"""')
            index += 3
            continue
        char = text[index]
        if char == '"' and not in_block_string:
            in_line_string = not in_line_string
        elif char == "\n":
            in_line_string = False
        elif (
            not in_line_string and not in_block_string
            and char == "/" and text[index + 1:index + 2] == "/"
        ):
            newline = text.find("\n", index)
            index = len(text) if newline == -1 else newline
            continue
        out.append(char)
        index += 1
    return "".join(out)


def function_body(text, start):
    """Text of the function whose declaration begins at `start`, braces balanced."""
    try:
        index = text.index("{", start)
    except ValueError:
        return ""
    depth = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            in_string = not in_string
        elif not in_string and char == "{":
            depth += 1
        elif not in_string and char == "}":
            depth -= 1
            if depth == 0:
                return text[start:index]
        index += 1
    return text[start:]


def pattern_list_blocks(text):
    """(name, declaration text) for each disposition list. `text` must be noise-stripped.

    Two overruns have happened here. A trailing `// note` after `]` defeated the anchor and
    the match ran ~215 lines into function bodies, condemning live patterns. A list reflowed
    onto ONE line has no newline before its `]`, so the anchor matched the NEXT list's
    bracket and silently absorbed that whole list — with no error at all. Both guards below
    exist for a specific observed failure; neither is theoretical.
    """
    for name in PATTERN_LISTS:
        match = re.search(
            r"var " + name + r": \[String\] \{.*?\n[ \t]*\][ \t]*\n", text, re.S
        )
        if not match:
            raise SystemExit(
                "could not locate the declaration of %s in %s.\n"
                "This check parses that array literally. If it was reformatted or renamed, "
                "update pattern_list_blocks() rather than deleting the check."
                % (name, DISPOSITION_FILE.name)
            )
        block = match.group(0)
        # Check the block's CODE, not its text: a pattern may legitimately contain the word
        # "return" (one does), and matching inside string literals made the guard fire on a
        # perfectly well-formed list.
        skeleton = LITERAL.sub('""', block)
        if "func " in skeleton or "return " in skeleton:
            raise SystemExit(
                "the parsed declaration of %s ran past its closing bracket into code.\n"
                "Fix pattern_list_blocks() — do NOT trust the list it would produce." % name
            )
        swallowed = [other for other in PATTERN_LISTS
                     if other != name and ("var %s:" % other) in block]
        if swallowed:
            raise SystemExit(
                "the parsed declaration of %s swallowed %s.\n"
                "Its closing bracket was not found where expected — most likely the array was "
                "reflowed onto one line. Fix pattern_list_blocks(); the pattern counts it "
                "would report are wrong." % (name, ", ".join(swallowed))
            )
        yield name, block


def main():
    if not DISPOSITION_FILE.exists():
        raise SystemExit(
            "cannot find %s. If it was renamed, update DISPOSITION_FILE in this script."
            % DISPOSITION_FILE
        )

    disposition_text = strip_noise(DISPOSITION_FILE.read_text(encoding="utf-8"))

    lists = {}
    for name, block in pattern_list_blocks(disposition_text):
        lists[name] = LITERAL.findall(block)

    corpus = []
    scanned = []
    for path in sorted(SRC.glob(VALIDATOR_SOURCES)):
        text = strip_noise(path.read_text(encoding="utf-8"))
        found_here = 0
        for match in VALIDATOR_FUNCTION.finditer(text):
            body = CONCATENATION.sub("", function_body(text, match.start()))
            for literal in LITERAL.findall(body):
                if len(literal) >= 8:
                    corpus.append(literal)
                    found_here += 1
        if found_here:
            scanned.append("%s(%d)" % (path.name, found_here))

    dead = []
    allowed_used = set()
    for name, patterns in lists.items():
        for pattern in patterns:
            if any(pattern in literal for literal in corpus):
                continue
            if pattern in ALLOWED_VIA_INTERPOLATION:
                allowed_used.add(pattern)
                continue
            dead.append((name, pattern))

    unused = set(ALLOWED_VIA_INTERPOLATION) - allowed_used

    print("validator sources (%d): %s" % (len(scanned), ", ".join(scanned)))
    print("corpus: %d literals, all from inside a validate* function body" % len(corpus))
    for name, patterns in lists.items():
        print("  %-36s %d patterns" % (name, len(patterns)))
    print("  %-36s %d allowed via interpolation" % ("", len(allowed_used)))

    if not corpus:
        print("\nThe corpus is empty — the scoping rule is broken, not the patterns.")
        return 1

    if unused:
        print("\nSTALE ALLOW-LIST ENTRIES — no longer needed, delete them:")
        for pattern in sorted(unused):
            print("  %r" % pattern)

    if dead:
        print("\nDEAD PATTERNS — these match no message a validate* function can emit:")
        for name, pattern in dead:
            print("  %s: %r" % (name, pattern))
        print("\nEither delete the pattern, or paste the real emitted string from the")
        print("validator that produces it. Do not add it back from memory, and do not")
        print("satisfy this by adding the phrase anywhere outside a validate* function —")
        print("nothing outside one counts. If a new validator is not named validate*, teach")
        print("VALIDATOR_FUNCTION about it. If the message is built by interpolation, add it")
        print("to ALLOWED_VIA_INTERPOLATION with the emitter named.")

    if dead or unused:
        return 1

    print("\nOK: every disposition pattern matches an emitted message or a named emitter.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
