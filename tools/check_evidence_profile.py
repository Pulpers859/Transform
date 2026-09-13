#!/usr/bin/env python3
"""Fail if EvidenceProfile.md and the Swift generator disagree, or if a documented band is
arithmetically unreachable.

WHY THIS EXISTS
---------------
EvidenceProfile.md is the programming contract. Nothing compiles it, so every number in it is
a claim that no test checks. Three real defects lived in that gap at once:

  1. The doc declared `hypertrophy_v1_9` while the code declared `v1_8`, and that stale string
     is printed into the AI prompt on every generation.
  2. MAINT-001 floored a non-priority muscle at 4.0 weekly direct sets, while `canAddSet` caps a
     non-prime movement at its role default -- 3 for an accessory, secondary or core movement in
     week 1. A group covered by exactly one such movement could therefore NEVER reach the floor.
     The warning fired on every generation and no allocation could answer it.
  3. `weeklyDirectSetTarget` adds up to +2.5 for volume/direct-work bias with no upper clamp, so
     the shipped "8-12" High band could return 12.5 -- outside its own stated maximum.

All three are invisible to Swift tests: each individual number is self-consistent, and only the
RELATIONSHIP between the doc and two or three separate Swift sites is wrong.

THE ARITHMETIC THIS PINS
------------------------
Weekly exercise slots are `max(levelTarget, ceil(weeklySetTarget / 4))` (PriorityIntent.swift,
`minimumExerciseSlots`), and `maximumUsefulVariationCount` caps distinct primary exercises at
4 / 3 / 2 by tier. So a tier's weekly set target is bounded above by `variationCeiling * 4`.
Raising VOL-001 past that bound silently re-creates the defect class where a blueprint prints a
target no allocator can reach -- which is the same shape as (2) above, one layer up.

USAGE
    python3 tools/check_evidence_profile.py          # exits non-zero on any mismatch
"""
from __future__ import annotations
import math, re, sys
from pathlib import Path

import os
# Overridable so `test_check_evidence_profile.py` can point the checker at a mutated copy of
# the tree. Nothing in production sets it.
ROOT = Path(os.environ.get("TRANSFORM_REPO_ROOT", Path(__file__).resolve().parent.parent))
DOC = ROOT / "Transform/Transform/EvidenceProfile.md"
SVC = ROOT / "Transform/Transform/WorkoutGeneratorService.swift"
PRIORITY = ROOT / "Transform/Transform/WorkoutGeneratorService+PriorityIntent.swift"
PARSING = ROOT / "Transform/Transform/WorkoutGeneratorService+ParsingValidation.swift"
SELECTION = ROOT / "Transform/Transform/WorkoutGeneratorService+ExerciseSelection.swift"

SLOT_SET_DIVISOR = 4.0  # minimumExerciseSlots(forWeeklySetTarget:) -- asserted below, not assumed


def read(p: Path) -> str:
    if not p.exists():
        die(f"expected file not found: {p}")
    return p.read_text(encoding="utf-8")


def die(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def need(match, what: str):
    """A parse that finds nothing must FAIL, never silently pass."""
    if not match:
        die(f"could not parse {what} -- this checker is stale and is no longer checking anything")
    return match


def swift_direct_set_bands(svc: str) -> dict[str, tuple[float, float]]:
    block = need(
        re.search(r"directSetTargetsByPriority:\s*\[(.*?)\]", svc, re.S),
        "directSetTargetsByPriority in WorkoutGeneratorService.swift",
    ).group(1)
    bands = {m.group(1): (float(m.group(2)), float(m.group(3)))
             for m in re.finditer(r'"(\w+)":\s*([\d.]+)\s*\.\.\.\s*([\d.]+)', block)}
    if set(bands) != {"High", "Medium", "Low"}:
        die(f"directSetTargetsByPriority tiers changed: {sorted(bands)}")
    return bands


def swift_variation_ceilings(priority: str) -> dict[str, int]:
    body = need(
        re.search(r"func maximumUsefulVariationCount\(.*?\)\s*->\s*Int\s*\{(.*?)\n    \}", priority, re.S),
        "maximumUsefulVariationCount in +PriorityIntent.swift",
    ).group(1)
    ceilings: dict[str, int] = {}
    for tier, value in re.findall(r'case\s+"(\w+)":\s*\n\s*return\s+(\d+)', body):
        ceilings[tier] = int(value)
    default = need(re.search(r"default:\s*\n\s*return\s+(\d+)", body), "default arm of maximumUsefulVariationCount")
    ceilings.setdefault("Medium", ceilings.get("Medium", 0))
    ceilings["Low"] = int(default.group(1))
    for tier in ("High", "Medium", "Low"):
        if tier not in ceilings:
            die(f"maximumUsefulVariationCount has no arm for {tier}")
    return ceilings


def swift_slot_divisor(priority: str) -> float:
    body = need(
        re.search(r"func minimumExerciseSlots\(forWeeklySetTarget[^)]*\)\s*->\s*Int\s*\{(.*?)\n    \}", priority, re.S),
        "minimumExerciseSlots in +PriorityIntent.swift",
    ).group(1)
    return float(need(re.search(r"setTarget\s*/\s*([\d.]+)", body), "divisor inside minimumExerciseSlots").group(1))


def swift_phase_defaults(svc: str) -> dict[int, dict[str, int]]:
    phases = {}
    for m in re.finditer(
        r"(\d+): EvidencePhasePrescription\(anchorSets: (\d+), secondarySets: (\d+), "
        r"accessorySets: (\d+), coreSets: (\d+)", svc):
        phases[int(m.group(1))] = {"anchor": int(m.group(2)), "secondary": int(m.group(3)),
                                   "accessory": int(m.group(4)), "core": int(m.group(5))}
    if sorted(phases) != [1, 2, 3, 4]:
        die(f"phasePrescriptionsByWeek no longer covers weeks 1-4: {sorted(phases)}")
    return phases


def swift_maintenance_ceilings(text: str, label: str) -> list[tuple[float, float]]:
    """Every `maintenanceCeiling` declaration in a file, as (recoveryTight, normal).

    There are three: +ExerciseSelection.swift declares it twice (once as Int, once as Double) and
    +ParsingValidation.swift once. The allocator funds to it and the validator grades against it,
    so a single site drifting means the app is marked down for obeying its own budget.
    """
    found = [(float(m.group(1)), float(m.group(2)))
             for m in re.finditer(r"maintenanceCeiling = recoveryTight \? ([\d.]+) : ([\d.]+)", text)]
    if not found:
        die(f"could not parse any maintenanceCeiling in {label} -- this checker is stale")
    return found


def swift_maintenance_floor(text: str) -> float:
    """The floor exists only in the validator: nothing in the allocator funds toward it."""
    m = need(re.search(r"maintenanceFloor = recoveryTight \? ([\d.]+) : ([\d.]+)", text),
             "maintenanceFloor in +ParsingValidation.swift")
    return float(m.group(2))


def doc_row(doc: str, rule_id: str) -> str:
    return need(re.search(rf"^\| `{re.escape(rule_id)}` \|(.*)$", doc, re.M), f"{rule_id} row in EvidenceProfile.md").group(1)


def main() -> int:
    doc, svc = read(DOC), read(SVC)
    priority, parsing, selection = read(PRIORITY), read(PARSING), read(SELECTION)
    failures: list[str] = []

    # --- 1. the doc's declared implemented version must match the Swift constant -------------
    doc_impl = need(re.search(r"Implemented in code: `([\w.]+)`", doc), "'Implemented in code' line in EvidenceProfile.md").group(1)
    code_ver = need(re.search(r'version:\s*"([\w.]+)"', svc), "evidenceProfileCache version").group(1)
    if doc_impl != code_ver:
        failures.append(
            f"EvidenceProfile.md says the code implements '{doc_impl}' but "
            f"WorkoutGeneratorService.swift declares '{code_ver}'. That string is printed into the AI "
            f"prompt via blueprintContext, so a stale value misreports the contract to the model."
        )

    # --- 2. VOL-001's documented bands must equal the Swift bands ----------------------------
    bands = swift_direct_set_bands(svc)
    vol_row = doc_row(doc, "VOL-001")
    for tier, token in (("High", "High priority areas target"), ("Medium", "medium"), ("Low", "low")):
        m = re.search(re.escape(token) + r"\s*`([\d.]+)-([\d.]+)`", vol_row)
        if not m:
            failures.append(f"VOL-001 row does not state a band for {tier}")
            continue
        documented = (float(m.group(1)), float(m.group(2)))
        if documented != bands[tier]:
            failures.append(
                f"VOL-001 documents {tier} as {documented[0]:g}-{documented[1]:g} weekly sets but "
                f"directSetTargetsByPriority declares {bands[tier][0]:g}...{bands[tier][1]:g}"
            )

    # --- 3. every band's upper bound must be fundable within VAR-001's variation ceiling -----
    divisor = swift_slot_divisor(priority)
    if divisor != SLOT_SET_DIVISOR:
        failures.append(f"minimumExerciseSlots divides by {divisor}, not the documented {SLOT_SET_DIVISOR}")
    ceilings = swift_variation_ceilings(priority)
    for tier, (_, upper) in bands.items():
        slots_needed = math.ceil(upper / divisor)
        if slots_needed > ceilings[tier]:
            failures.append(
                f"{tier} weekly set target may reach {upper:g}, which needs "
                f"ceil({upper:g}/{divisor:g}) = {slots_needed} exercise slots, but "
                f"maximumUsefulVariationCount caps {tier} at {ceilings[tier]} distinct exercises. "
                f"The blueprint would print a target no menu can fund. Max fundable: "
                f"{ceilings[tier] * divisor:g} sets."
            )

    # --- 4. the two Swift maintenance sites must agree, and match the doc --------------------
    p_floor = swift_maintenance_floor(parsing)
    all_ceilings = (swift_maintenance_ceilings(parsing, "+ParsingValidation.swift")
                    + swift_maintenance_ceilings(selection, "+ExerciseSelection.swift"))
    if len(set(all_ceilings)) != 1:
        failures.append(
            f"the {len(all_ceilings)} maintenanceCeiling declarations do not agree: {sorted(set(all_ceilings))}. "
            f"The allocator funds to one number and the validator grades against another."
        )
    p_ceiling = all_ceilings[0][1]
    maint_row = doc_row(doc, "MAINT-001")
    m = re.search(r"capped at `([\d.]+)`.*?floored at `([\d.]+)`", maint_row)
    if not m:
        failures.append("MAINT-001 row no longer states 'capped at `N`' and 'floored at `N`'")
    else:
        if float(m.group(2)) != p_floor:
            failures.append(f"MAINT-001 documents floor {m.group(2)} but code uses {p_floor:g}")
        if float(m.group(1)) != p_ceiling:
            failures.append(f"MAINT-001 documents ceiling {m.group(1)} but code uses {p_ceiling:g}")

    # The validator's OWNER-FACING text restates the band in prose. That prose is read by a person
    # deciding whether to act, so a stale band there is worse than a stale constant: it tells him a
    # number the app is not using. Both emitting strings must match MAINT-001's documented target band.
    band = re.search(r"targeting `([\d.]+)-([\d.]+)` direct sets/week", maint_row)
    if not band:
        failures.append("MAINT-001 row no longer states a 'targeting `N-M` direct sets/week' band")
    else:
        want = f"{band.group(1)}-{band.group(2)}"
        stale = sorted({f"{a}-{b}" for a, b in
                        re.findall(r"(?:roughly|near) ([\d.]+)-([\d.]+) quality sets per week", parsing)}
                       - {want})
        if stale:
            failures.append(
                f"validator messages tell the owner maintenance is {', '.join(stale)} quality sets per "
                f"week, but MAINT-001 documents {want}. Fix the strings in validateNonPriorityMuscleVolume."
            )

    # --- 5. the maintenance floor must be REACHABLE by a single covering movement ------------
    # canAddSet caps a non-prime movement at its role default. A major muscle group is routinely
    # covered by exactly one accessory/secondary/core movement, and enforceMaintenanceExposureBreadth
    # is best-effort, so it cannot be relied on to supply a second. Week 4 is exempt from the floor
    # (`enforcesMaintenanceFloor = !MesocyclePhase.isDeloadWeek(weekNumber)`), so only weeks 1-3 bind.
    phases = swift_phase_defaults(svc)
    worst = min((phases[w][role], w, role)
                for w in (1, 2, 3) for role in ("secondary", "accessory", "core"))
    if p_floor > worst[0]:
        failures.append(
            f"maintenance floor {p_floor:g} is unreachable: a group covered by one {worst[2]} movement "
            f"caps at its week-{worst[1]} role default of {worst[0]} sets, so the finding fires on every "
            f"generation and no allocation can answer it. Either lower the floor to {worst[0]} or raise "
            f"that role default."
        )

    # --- 6. every session fatigue cap must admit a FULL-SIZE day --------------------------
    # `seededDayFitsItsBudgets` decides whether a day may take another movement by projecting the
    # WHOLE day at `minimumSetFloor` and comparing to the style's cap. Under FAT-001's linear
    # model that projection is large: an anchor alone projects fatigueCost 3 x floor 3 = 9. A cap
    # below the projection makes a full-size day unbuildable before a single extra set is funded --
    # the day silently collapses to 4-5 movements and the validator then hard-fails it for being
    # short. Nothing in Swift catches this: the cap is valid on its own and the projection is valid
    # on its own; only the relationship is wrong.
    linear = re.search(r"func fatigueContribution\([^)]*\)\s*->\s*Int\s*\{\s*\n\s*metadata\.fatigueCost \* max\(0, exercise\.sets\)",
                       priority)
    if not linear:
        failures.append(
            "fatigueContribution is no longer `fatigueCost * sets`. The full-day projection check "
            "below assumes the linear model; re-derive it before changing the model, or this "
            "checker silently stops describing the code."
        )
    else:
        caps = {m.group(1): int(m.group(2))
                for m in re.finditer(r'"(push|pull|upper|legs|lower|arms)": (\d+)', svc)}
        if len(caps) != 6:
            die(f"could not parse all six sessionFatigueCapsByStyle entries (got {sorted(caps)})")
        lower_ceiling = need(re.search(r'canonicalTrainingStyle\(style\) == "Lower" \? (\d+) : (\d+)', selection),
                             "comfortableDayExerciseCeiling day sizes")
        sizes = {"lower": int(lower_ceiling.group(1)), "legs": int(lower_ceiling.group(1))}
        # A deliberately CONSERVATIVE composition: two anchors and the rest accessories, each at
        # its `minimumSetFloor` (3 for an anchor, 2 otherwise). Real days carry secondaries too and
        # so project higher, which means passing this check is necessary, not sufficient.
        for style, cap in caps.items():
            movements = sizes.get(style, int(lower_ceiling.group(2)))
            projection = 2 * (3 * 3) + max(0, movements - 2) * (1 * 2)
            if cap < projection:
                failures.append(
                    f"session fatigue cap for '{style}' is {cap}, below the {projection} that a "
                    f"{movements}-movement day projects at minimumSetFloor (2 anchors + "
                    f"{movements - 2} accessories). `seededDayFitsItsBudgets` would refuse to build "
                    f"a full-size day, and the validator hard-fails a day under 5 movements."
                )

    if failures:
        print(f"FAIL: {len(failures)} EvidenceProfile/code inconsistency(ies)\n", file=sys.stderr)
        for i, f in enumerate(failures, 1):
            print(f"  {i}. {f}\n", file=sys.stderr)
        return 1
    print("OK: EvidenceProfile.md and the generator agree, and every documented band is fundable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
