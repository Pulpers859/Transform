#!/usr/bin/env python3
"""Self-test for check_evidence_profile.py.

A checker that stops checking is worse than no checker: it reads as coverage. Each case below is
a defect that ACTUALLY SHIPPED in this repo, replayed against a mutated copy of the real tree. If
the checker stops catching one, this file fails and says which.
"""
from __future__ import annotations
import os, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "tools/check_evidence_profile.py"
FILES = [
    "Transform/Transform/EvidenceProfile.md",
    "Transform/Transform/WorkoutGeneratorService.swift",
    "Transform/Transform/WorkoutGeneratorService+PriorityIntent.swift",
    "Transform/Transform/WorkoutGeneratorService+ParsingValidation.swift",
    "Transform/Transform/WorkoutGeneratorService+ExerciseSelection.swift",
]


def run_against(tree: Path) -> subprocess.CompletedProcess:
    env = dict(os.environ, TRANSFORM_REPO_ROOT=str(tree))
    return subprocess.run([sys.executable, str(CHECKER)], env=env, capture_output=True, text=True)


def build_tree(tmp: Path) -> Path:
    for rel in FILES:
        dst = tmp / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, dst)
    return tmp


def mutate(tree: Path, rel: str, old: str, new: str) -> None:
    p = tree / rel
    text = p.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(
            f"SELF-TEST STALE: expected exactly one {old!r} in {rel}, found {text.count(old)}. "
            f"The attack no longer describes the real code, so it is testing nothing."
        )
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


DOC = FILES[0]
SVC = FILES[1]
PRI = FILES[2]
PAR = FILES[3]
SEL = FILES[4]

# (name, [(file, old, new), ...], substring the failure message must contain)
ATTACKS = [
    ("stale version string, which is printed into the AI prompt",
     [(SVC, 'version: "hypertrophy_v1_9"', 'version: "hypertrophy_v1_8"')],
     "prompt"),
    ("doc band drifts from the Swift band",
     [(SVC, '"High": 8...12', '"High": 10...14')],
     "VOL-001 documents High"),
    ("band upper bound demands more exercise slots than VAR-001 allows",
     [(SVC, '"High": 8...12', '"High": 8...20'),
      (DOC, "High priority areas target `8-12`", "High priority areas target `8-20`")],
     "maximumUsefulVariationCount"),
    ("maintenance floor raised above what one covering movement can deliver",
     [(PAR, "maintenanceFloor = recoveryTight ? 2.0 : 3.0", "maintenanceFloor = recoveryTight ? 3.0 : 4.0"),
      (DOC, "floored at `3`", "floored at `4`")],
     "unreachable"),
    ("allocator and validator ceilings disagree",
     [(SEL, "let maintenanceCeiling = recoveryTight ? 8.0 : 10.0",
           "let maintenanceCeiling = recoveryTight ? 5.0 : 6.0")],
     "do not agree"),
    ("a session fatigue cap too low to build a full-size day (the pre-linear values)",
     [(SVC, '"push": 48', '"push": 19')],
     "seededDayFitsItsBudgets"),
    ("the fatigue model silently reverted to the step multiplier",
     [(PRI, "metadata.fatigueCost * max(0, exercise.sets)",
            "metadata.fatigueCost * (exercise.sets >= 5 ? 3 : exercise.sets >= 4 ? 2 : 1)")],
     "no longer `fatigueCost * sets`"),
    ("owner-facing prose still quotes a band the code does not use",
     [(DOC, "targeting `6-10` direct sets/week", "targeting `4-6` direct sets/week")],
     "tell the owner"),
]


def main() -> int:
    failures = []

    with tempfile.TemporaryDirectory() as td:
        clean = build_tree(Path(td) / "clean")
        result = run_against(clean)
        if result.returncode != 0:
            failures.append(
                "BASELINE: the checker fails on the UNMODIFIED tree, so every attack below would "
                f"'pass' for the wrong reason.\n{result.stdout}{result.stderr}"
            )

    for name, muts, expect in ATTACKS:
        with tempfile.TemporaryDirectory() as td:
            tree = build_tree(Path(td) / "t")
            for rel, old, new in muts:
                mutate(tree, rel, old, new)
            result = run_against(tree)
            if result.returncode == 0:
                failures.append(f"NOT CAUGHT: {name}")
            elif expect not in (result.stdout + result.stderr):
                failures.append(
                    f"CAUGHT BUT MISREPORTED: {name}\n  expected the message to mention {expect!r}\n"
                    f"  got: {(result.stdout + result.stderr).strip()[:300]}"
                )

    if failures:
        print(f"FAIL: {len(failures)} self-test failure(s)\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}\n", file=sys.stderr)
        return 1
    print(f"OK: checker rejects all {len(ATTACKS)} pinned defects and accepts the real tree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
