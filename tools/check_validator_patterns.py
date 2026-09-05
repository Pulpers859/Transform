#!/usr/bin/env python3
"""Fail if a validator disposition pattern matches no message the app can emit.

WHY THIS EXISTS
---------------
`validationDisposition` classifies a validator finding by plain substring containment
against four hand-maintained pattern lists. A pattern that matches nothing is invisible:
it changes no behaviour, breaks no test, and reads exactly like coverage. One shipped —
"was replaced with a poor substitute" sat in two disposition lists and in the on-screen
copy mapper while `validateSubstituteQuality` never produced that phrase.

It survived an ad-hoc check because that check searched every string literal in the
source, INCLUDING the pattern lists themselves. The pattern matched its own declaration
and reported a pass. A corpus that contains the thing under test cannot fail.

So the corpus here is built by EXCLUSION: pattern-list declarations and consumer
matchers (`issue.contains(...)`, `matchesValidationIssue`) are stripped before anything
is compared. What remains is emitter text.

Run: python3 tools/check_validator_patterns.py
Exit 1 and names the offenders if any pattern is dead.

LIMITS, STATED RATHER THAN HIDDEN
---------------------------------
Emitted messages are Swift string literals, so two shapes cannot be read literally:

  concatenation  "...rep bands in one " + "week. The working load..."
  interpolation  "...exceeds its \(capContext) direct-set cap on day..."

Concatenation is handled: adjacent literals joined by `+` are merged before matching.
Interpolation cannot be resolved statically — the value is only known at runtime — so
those patterns live in ALLOWED_VIA_INTERPOLATION below, each naming the emitter that
builds it. That list is deliberately small and deliberately annoying to add to: a
pattern that cannot be proven live must be justified by a human pointing at the code
that writes it, which is the whole point.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Transform" / "Transform"
DISPOSITION_FILE = SRC / "WorkoutGeneratorService+ParsingValidation.swift"

PATTERN_LISTS = [
    "lockedMenuHardFailurePatterns",
    "acceptableWarningIssuePatterns",
    "correctionWorthyIssuePatterns",
    "menuLockedDemotionPatterns",
]

LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

# Adjacent literals joined by `+` across a line break are one runtime string.
CONCATENATION = re.compile(r'"\s*\+\s*"')

# Patterns whose emitted form is assembled through a `\(...)` interpolation, so no
# single literal in the source contains them. Each MUST name the emitter.
ALLOWED_VIA_INTERPOLATION = {
    # WorkoutGeneratorService+ParsingValidation.swift builds the cap kind separately:
    #     let capContext = ... ? "focus-day" : "per-session"
    #     "Blueprint priority '\(...)' exceeds its \(capContext) direct-set cap on day ..."
    "exceeds its focus-day direct-set cap":
        "ParsingValidation.swift capContext ternary + the direct-set cap message",
    "exceeds its per-session direct-set cap":
        "ParsingValidation.swift capContext ternary + the direct-set cap message",
}


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", text)


def pattern_list_blocks(text):
    """(name, whole declaration text) for each disposition list."""
    for name in PATTERN_LISTS:
        m = re.search(r"var " + name + r": \[String\] \{.*?\n        \]\n", text, re.S)
        if not m:
            raise SystemExit("could not locate pattern list: " + name)
        yield name, m.group(0)


def main():
    disposition_text = DISPOSITION_FILE.read_text(encoding="utf-8")

    lists = {}
    declaration_blocks = []
    for name, block in pattern_list_blocks(disposition_text):
        lists[name] = LITERAL.findall(strip_comments(block))
        declaration_blocks.append(block)

    # Build the emitter corpus.
    corpus = []
    for path in sorted(SRC.glob("*.swift")):
        text = path.read_text(encoding="utf-8")

        # Remove the declarations themselves — this is the exclusion that makes the
        # check capable of failing at all.
        if path == DISPOSITION_FILE:
            for block in declaration_blocks:
                text = text.replace(block, "")

        text = strip_comments(text)

        # Merge concatenated literals so a phrase split across a line break is seen whole.
        text = CONCATENATION.sub("", text)

        for line in text.splitlines():
            # Consumer matchers are not emitters. A pattern must not be validated by the
            # code that consumes it.
            if "issue.contains(" in line or "matchesValidationIssue" in line:
                continue
            for literal in LITERAL.findall(line):
                if len(literal) >= 8:
                    corpus.append((path.name, literal))

    dead = []
    allowed_used = set()
    for name, patterns in lists.items():
        for pattern in patterns:
            if any(pattern in text for _, text in corpus):
                continue
            if pattern in ALLOWED_VIA_INTERPOLATION:
                allowed_used.add(pattern)
                continue
            dead.append((name, pattern))

    # An allow-list entry that is no longer needed is itself stale. Say so.
    unused = set(ALLOWED_VIA_INTERPOLATION) - allowed_used

    print("corpus: %d emitter literals across %d files"
          % (len(corpus), len(list(SRC.glob('*.swift')))))
    for name, patterns in lists.items():
        print("  %-36s %d patterns" % (name, len(patterns)))

    print("  %-36s %d allowed via interpolation" % ("", len(allowed_used)))

    if unused:
        print("\nSTALE ALLOW-LIST ENTRIES — no longer needed, delete them:")
        for pattern in sorted(unused):
            print("  %r" % pattern)

    if dead:
        print("\nDEAD PATTERNS — these match no message the app can emit:")
        for name, pattern in dead:
            print("  %s: %r" % (name, pattern))
        print("\nEither delete the pattern, or paste the real emitted string from the")
        print("validator function that produces it. Do not add it back from memory.")
        print("If it is genuinely built by interpolation, add it to")
        print("ALLOWED_VIA_INTERPOLATION with the emitter named.")

    if dead or unused:
        return 1

    print("\nOK: every disposition pattern matches an emitted message or a named emitter.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
