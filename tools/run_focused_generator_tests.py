#!/usr/bin/env python3
"""Bounded, API-free planning feedback. A pass is NOT full generator approval."""
from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

# Deliberate behavioral coverage, not a changed-filename heuristic. Add new planning
# suites here when they become part of this feedback lane; full CI remains unfiltered.
PLANNING_SUITES = (
    "SixExerciseCapacityTests",
    "JointAppearancePlanningTests",
    "WorkoutAppearancePlannerTests",
    "SetBudgetPolicyTests",
    "WeeklySetAccountingTests",
    "SubstitutionPreflightTests",
    "AccessoryRelocationTests",
    "CrossDayTricepsTests",
    "PlanningAdmissionOutcomeTests",
    "BackBalanceAndStyleCanonicalTests",
    "CoreAdjunctStyleTests",
    "ExactFundedDoseTests",
    "JointDoseSearchTests",
    "JointDoseProjectionTests",
    "PriorityStyleAndSlotCapacityTests",
    "InjuryTimeAndSessionBudgetTests",
    "SessionOrderingPolicyTests",
    "OwnerPlanningReplayTests",
)
EXPECTED_CLASSES = {f"TransformGeneratorCoreTests.{name}" for name in PLANNING_SUITES}
REQUIRED_CASES = {
    ("TransformGeneratorCoreTests.SixExerciseCapacityTests",
     "testTraceFiveCompleteWeekOnePlansWithOptionalSixSlotReservation"),
    ("TransformGeneratorCoreTests.OwnerPlanningReplayTests",
     "testSyntheticFiveDayConstrainedPlanningReplay"),
}


def test_filter() -> str:
    return r"^TransformGeneratorCoreTests\.({})/".format(
        "|".join(re.escape(name) for name in PLANNING_SUITES)
    )


def verify_results(path: Path) -> Counter:
    """Require real passing cases from EVERY selected suite; reject empty/partial runs."""
    root = ET.parse(path).getroot()
    cases = list(root.iter("testcase"))
    if not cases:
        raise ValueError("No test cases executed")
    for suite in root.iter("testsuite"):
        for attribute in ("failures", "errors"):
            if int(suite.get(attribute, "0")) != 0:
                raise ValueError(f"Report has {attribute}")
    counts = Counter()
    identities = set()
    for case in cases:
        identity = (case.get("classname", ""), case.get("name", ""))
        if identity[0] not in EXPECTED_CLASSES or not identity[1]:
            raise ValueError(f"Unexpected or unnamed test: {identity}")
        if identity in identities:
            raise ValueError(f"Duplicate test: {identity}")
        identities.add(identity)
        if any(case.find(tag) is not None for tag in ("failure", "error", "skipped")):
            raise ValueError(f"Failed, errored or skipped test: {identity}")
        counts[identity[0]] += 1
    missing = EXPECTED_CLASSES - counts.keys()
    if missing:
        raise ValueError(f"Selected suites did not execute: {sorted(missing)}")
    if not REQUIRED_CASES <= identities:
        raise ValueError(f"Required planning probes did not execute: {sorted(REQUIRED_CASES - identities)}")
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = args.output_dir / "planning-tests.xml"
    # Never accidentally validate an earlier run's XML after a build failure.
    if report.exists():
        report.unlink()
    command = ["swift", "test", "--enable-xctest", "--parallel", "--filter",
               test_filter(), "--xunit-output", str(report)]
    manifest = {"mode": "planning", "fullVerification": False,
                "commit": os.environ.get("GITHUB_SHA", "local"),
                "suites": list(PLANNING_SUITES), "command": command}
    (args.output_dir / "planning-scope.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("FOCUSED PLANNING: partial verification, not full-suite approval.", flush=True)
    print("Selected suites: " + ", ".join(PLANNING_SUITES), flush=True)
    with (args.output_dir / "planning-tests.log").open("w", encoding="utf-8") as log:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, encoding="utf-8", errors="replace") as process:
            for line in process.stdout:
                print(line, end="", flush=True)
                log.write(line)
            status = process.wait()
    if status:
        return status
    counts = verify_results(report)
    summary = (f"## FOCUSED planning — partial verification only\n\n"
               f"Commit: `{os.environ.get('GITHUB_SHA', 'local')}`\n\n"
               f"Executed {sum(counts.values())} passing tests across {len(counts)} suites.\n\n"
               "This does not run the full 20-week journey matrix, nutrition tests, or all "
               "other regression tests. Require FULL Generator Tests and the Swift app build "
               "on the final commit before calling the work complete. No paid AI calls.\n")
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as output:
            output.write(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
