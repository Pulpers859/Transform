#!/usr/bin/env python3
"""Fail if a validator disposition pattern matches no message the app can emit.

WHY THIS EXISTS
---------------
`validationDisposition` classifies a validator finding by plain substring containment
against four hand-maintained pattern lists. A pattern that matches nothing is invisible:
it changes no behaviour, breaks no test, and reads exactly like coverage. Two shipped —
"was replaced with a poor substitute" and "notes do not include a concrete progression
cue" — each sitting in a disposition list and in the on-screen copy mapper while no
validator ever produced the phrase.

THE RULE THIS TOOL ENFORCES ON ITSELF
-------------------------------------
A pattern must never be validated by code that CONSUMES findings — only by code that
EMITS them. The first version of this script got that wrong twice over. It excluded
consumers by blacklisting two syntactic forms (`issue.contains(`, `matchesValidationIssue`)
and missed:

  - `WorkoutValidatorNotice.containsAnyFragment(issue, [...])`, whose fragment arrays span
    several lines, none of which carry the blacklisted text; and
  - `correctionTactics(for:)` in WorkoutGeneratorService+Requests.swift, which matches with
    `issues.contains(where: { $0.contains("...") })` — a string that does NOT contain the
    substring "issue.contains(".

A fabricated dead pattern mirrored into either place passed the check. Blacklisting
consumer SYNTAX cannot work, because the next consumer invents new syntax.

So the corpus is now chosen STRUCTURALLY: a file contributes only if it actually appends
validator findings (`issues.append(` / `warnings.append(`). Pure consumers — the copy
mapper, the prompt builder — contribute nothing and need no maintenance to stay excluded,
and a consumer added tomorrow is excluded automatically because it does not emit.

LIMITS, STATED RATHER THAN HIDDEN
---------------------------------
Emitted messages are Swift string literals, so two shapes cannot be read literally:

  concatenation  "...rep bands in one " + "week. The working load..."
  interpolation  "...exceeds its \\(capContext) direct-set cap on day..."

Concatenation is handled: adjacent literals joined by `+` are merged before matching.
Interpolation cannot be resolved statically — the value is only known at runtime — so
those patterns live in ALLOWED_VIA_INTERPOLATION below, each naming the emitter that
builds it. That list is deliberately small and deliberately annoying to add to: a pattern
that cannot be proven live must be justified by a human pointing at the code that writes
it, which is the whole point.

An emitter that returns finding literals without ever calling `.append(` would be missed
by the corpus rule and its patterns would report as dead. That is a LOUD failure naming
the pattern, not a silent pass, and the fix is to make this file aware of the new emitter
shape.

Run: python3 tools/check_validator_patterns.py
Exit 1 and names the offenders if any pattern is dead.
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

# What makes a file an EMITTER of validator findings.
EMITS = re.compile(r"\b(?:issues|warnings)\.append\(")

LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

# Adjacent literals joined by `+` across a line break are one runtime string.
CONCATENATION = re.compile(r'"\s*\+\s*"')

# Patterns whose emitted form is assembled through a `\(...)` interpolation, so no single
# literal in the source contains them. Each MUST name the emitter.
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
    """Remove `//` comments WITHOUT truncating a string literal that contains `//`.

    A naive `re.sub(r"//[^\\n]*", "", text)` eats the rest of the line from the `//` in
    `URL(string: "https://api.anthropic.com/v1/messages")`, silently dropping whatever
    followed on that line. Any emitted message containing a URL would lose its tail.
    """
    out = []
    for line in text.splitlines():
        in_string = False
        escaped = False
        cut = len(line)
        index = 0
        while index < len(line):
            char = line[index]
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = not in_string
            elif not in_string and char == "/" and line[index + 1:index + 2] == "/":
                cut = index
                break
            index += 1
        out.append(line[:cut])
    return "\n".join(out)


def pattern_list_blocks(text):
    """(name, whole declaration text) for each disposition list.

    The closing bracket is matched at any indentation: pinning it to a fixed number of
    spaces made a cosmetic reformat fail CI with a confusing "could not locate" error.
    """
    for name in PATTERN_LISTS:
        match = re.search(
            r"var " + name + r": \[String\] \{.*?\n[ \t]*\]\n", text, re.S
        )
        if not match:
            raise SystemExit(
                "could not locate the declaration of %s in %s.\n"
                "This check parses that array literally. If it was reformatted or renamed, "
                "update pattern_list_blocks() rather than deleting the check."
                % (name, DISPOSITION_FILE.name)
            )
        yield name, match.group(0)


def main():
    disposition_text = DISPOSITION_FILE.read_text(encoding="utf-8")

    lists = {}
    declaration_blocks = []
    for name, block in pattern_list_blocks(disposition_text):
        lists[name] = LITERAL.findall(strip_comments(block))
        declaration_blocks.append(block)

    corpus = []
    emitter_files = []
    for path in sorted(SRC.glob("*.swift")):
        text = path.read_text(encoding="utf-8")

        # Remove the declarations themselves — a pattern must never match its own
        # declaration, which is how the first dead pattern survived a check at all.
        if path == DISPOSITION_FILE:
            for block in declaration_blocks:
                text = text.replace(block, "")

        text = strip_comments(text)

        # Only files that actually append findings can vouch for a pattern.
        if not EMITS.search(text):
            continue
        emitter_files.append(path.name)

        # A consumer living INSIDE an emitter file still may not vouch for a pattern.
        text = "\n".join(
            line for line in text.splitlines()
            if "matchesValidationIssue" not in line and ".contains(" not in line
        )

        # Merge concatenated literals so a phrase split across a line break is seen whole.
        text = CONCATENATION.sub("", text)

        for literal in LITERAL.findall(text):
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

    unused = set(ALLOWED_VIA_INTERPOLATION) - allowed_used

    print("emitter files (%d): %s" % (len(emitter_files), ", ".join(emitter_files)))
    print("corpus: %d emitted literals" % len(corpus))
    for name, patterns in lists.items():
        print("  %-36s %d patterns" % (name, len(patterns)))
    print("  %-36s %d allowed via interpolation" % ("", len(allowed_used)))

    if not emitter_files:
        print("\nNo emitter files found at all — the corpus rule is broken, not the patterns.")
        return 1

    if unused:
        print("\nSTALE ALLOW-LIST ENTRIES — no longer needed, delete them:")
        for pattern in sorted(unused):
            print("  %r" % pattern)

    if dead:
        print("\nDEAD PATTERNS — these match no message the app can emit:")
        for name, pattern in dead:
            print("  %s: %r" % (name, pattern))
        print("\nEither delete the pattern, or paste the real emitted string from the")
        print("validator function that produces it. Do not add it back from memory, and do")
        print("not satisfy this by adding the phrase to a consumer — consumers do not count.")
        print("If it is genuinely built by interpolation, add it to")
        print("ALLOWED_VIA_INTERPOLATION with the emitter named.")

    if dead or unused:
        return 1

    print("\nOK: every disposition pattern matches an emitted message or a named emitter.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
