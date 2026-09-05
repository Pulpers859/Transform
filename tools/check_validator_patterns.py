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

# The two shapes a validator uses to produce a finding. Verified by reading the emitters,
# not assumed: `validateBackPatternBalance` and `validatePrimeFocusDensity` return their
# messages as `return ["..."]` and never call `.append(` at all, so an append-only rule
# reported six live patterns as dead.
EMIT_CALL = re.compile(r"\b(?:issues|warnings)\.append\(")
EMIT_RETURN = re.compile(r"\breturn\s*\[")

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
    """Remove `//` comments without touching anything inside a string literal.

    Two bugs this has had, both real:
      - `re.sub(r"//[^\n]*", "")` ate the tail of the line holding
        `URL(string: "https://api.anthropic.com/...")`, truncating at the `//` in the URL.
      - The line-by-line replacement that fixed it reset quote state at every newline, so
        a `//` inside a Swift `\"\"\"` multi-line literal was still cut. Nothing in the repo
        trips that today, but "fixed" was overstated.

    So this scans the whole text once, tracking both `"` and `\"\"\"` state across lines.
    """
    out = []
    index = 0
    in_line_string = False
    in_block_string = False
    length = len(text)
    while index < length:
        if text.startswith('\\', index) and (in_line_string or in_block_string):
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
            # An unterminated single-line literal cannot span a newline in valid Swift.
            in_line_string = False
        elif (
            not in_line_string
            and not in_block_string
            and char == "/"
            and text[index + 1:index + 2] == "/"
        ):
            newline = text.find("\n", index)
            index = length if newline == -1 else newline
            continue
        out.append(char)
        index += 1
    return "".join(out)


def _balanced_span(text, open_index, opener, closer):
    """End index of the delimiter opened at `open_index`, ignoring delimiters in strings."""
    index = open_index
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
        elif not in_string and char == opener:
            depth += 1
        elif not in_string and char == closer:
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def finding_spans(text):
    """(start, end) of every expression that PRODUCES a validator finding.

    THE CORPUS IS THESE SPANS AND NOTHING ELSE. The previous rule admitted every literal in
    any file that emitted a finding somewhere, which measured out at 7.4% genuinely emitted
    text and 92.6% unrelated strings — exercise-name keywords, prompt fragments, log lines.
    Under it an UNUSED constant, or a literal in a neighbouring regex array, vouched for a
    pattern exactly as well as a real message. Both were demonstrated by injection.

    Delimiters inside string literals are ignored, so a message containing "(" or "[" cannot
    end its own span early.
    """
    spans = []
    for match in EMIT_CALL.finditer(text):
        end = _balanced_span(text, match.end() - 1, "(", ")")
        if end is not None:
            spans.append((match.end() - 1, end))
    for match in EMIT_RETURN.finditer(text):
        open_index = text.index("[", match.start())
        end = _balanced_span(text, open_index, "[", "]")
        if end is not None:
            spans.append((open_index, end))
    return spans


def pattern_list_blocks(text):
    """(name, declaration text) for each disposition list.

    `text` MUST already have comments stripped. A trailing `// note` after the closing `]`
    used to defeat the `\n[ \t]*\]\n` anchor, so the non-greedy match ran on to the next
    closing bracket it could find — ~215 lines into unrelated function bodies — and the
    check then condemned 14 live patterns, printing their own emitted text as proof they
    were dead. The `func ` guard below turns that class of overrun into a clear error
    instead of a confident wrong answer.
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
        if "func " in block or "return " in block:
            raise SystemExit(
                "the parsed declaration of %s ran past its closing bracket into code.\n"
                "Something about that array's formatting defeated the parser. Fix "
                "pattern_list_blocks() — do NOT trust the pattern list it would produce."
                % name
            )
        yield name, block


def main():
    if not DISPOSITION_FILE.exists():
        raise SystemExit(
            "cannot find %s. If it was renamed, update DISPOSITION_FILE in this script."
            % DISPOSITION_FILE
        )

    disposition_text = strip_comments(DISPOSITION_FILE.read_text(encoding="utf-8"))

    lists = {}
    for name, block in pattern_list_blocks(disposition_text):
        lists[name] = LITERAL.findall(block)

    corpus = []
    emitter_files = []
    for path in sorted(SRC.glob("*.swift")):
        text = strip_comments(path.read_text(encoding="utf-8"))
        spans = finding_spans(text)
        if not spans:
            continue

        literals_here = 0
        for start, end in spans:
            # Merge concatenated literals INSIDE the call so a phrase split across a line
            # break is seen whole. Applied per span rather than to whole-file text: the old
            # whole-text merge, combined with a line-deletion filter, could weld two
            # literals that were never concatenated into a string nothing emits.
            argument = CONCATENATION.sub("", text[start:end + 1])
            for literal in LITERAL.findall(argument):
                if len(literal) >= 8:
                    corpus.append((path.name, literal))
                    literals_here += 1
        if literals_here:
            emitter_files.append("%s(%d)" % (path.name, literals_here))

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

    print("emitting files (%d): %s" % (len(emitter_files), ", ".join(emitter_files)))
    print("corpus: %d literals, all from inside a finding-producing expression" % len(corpus))
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
