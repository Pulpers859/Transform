"""Independently count prescriptions in the synthetic journey JSON, not validator messages.

Displayed-target totals are NOT anatomical/direct-stimulus credits. This observer cannot
prove safety, optimal programming, AI behavior, or device integration. --require-min-sets
is an explicit product acceptance check, not a physiological claim.
"""
import argparse
import json
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, label, minimum=0):
    require(type(value) is int and value >= minimum, f"Invalid {label}: {value!r}")
    return value


def audit(document, expected_personas=5):
    require(type(document.get("schemaVersion")) is int and document["schemaVersion"] == 1,
            "Unsupported evidence schema")
    personas = document.get("personas")
    require(isinstance(personas, list) and len(personas) == expected_personas,
            f"Expected {expected_personas} personas")
    results = []
    seen_personas = set()
    for persona in personas:
        name = persona.get("name")
        require(isinstance(name, str) and name.strip() and name not in seen_personas,
                "Missing or duplicate persona name")
        seen_personas.add(name)
        weeks = persona.get("weeks")
        require(isinstance(weeks, list) and len(weeks) == 4, f"{name}: expected four weeks")
        require([integer(w.get("weekNumber"), "weekNumber", 1) for w in weeks] == [1, 2, 3, 4],
                f"{name}: wrong weeks")
        for week in weeks:
            number = week["weekNumber"]
            days = week.get("days")
            require(isinstance(days, list) and len(days) == 7, f"{name}/{number}: expected seven days")
            expected_days = list(range((number - 1) * 7 + 1, number * 7 + 1))
            require([d.get("dayNumber") for d in days] == expected_days, f"{name}/{number}: wrong day numbers")
            total_sets = appearances = training_days = 0
            target_sets = {}
            below_two = []
            daily = []
            for day in days:
                day_number = integer(day.get("dayNumber"), "dayNumber", 1)
                require(type(day.get("isRestDay")) is bool, "Missing rest-day flag")
                exercises = day.get("exercises")
                require(isinstance(exercises, list), "Missing exercises")
                require(not day["isRestDay"] or not exercises, "Rest day contains exercises")
                require(day["isRestDay"] or exercises, "Empty training day")
                training_days += not day["isRestDay"]
                day_sets = 0
                names = set()
                for exercise in exercises:
                    exercise_name = exercise.get("exerciseName")
                    target = exercise.get("muscleTarget")
                    require(isinstance(exercise_name, str) and exercise_name.strip(), "Missing exercise name")
                    require(isinstance(target, str) and target.strip(), "Missing target label")
                    require(exercise_name not in names, "Duplicate exact exercise name within day")
                    names.add(exercise_name)
                    sets = integer(exercise.get("sets"), "sets", 1)
                    require(isinstance(exercise.get("reps"), str) and exercise["reps"].strip(), "Missing reps")
                    integer(exercise.get("restSeconds"), "restSeconds", 1)
                    day_sets += sets
                    appearances += 1
                    target_sets[target] = target_sets.get(target, 0) + sets
                    if sets < 2:
                        below_two.append({"day": day_number, "exercise": exercise_name, "sets": sets})
                total_sets += day_sets
                daily.append({"day": day_number, "sets": day_sets, "appearances": len(exercises)})
            planned = integer(week.get("plannedTrainingDays"), "plannedTrainingDays", 1)
            require(training_days == planned, f"{name}/{number}: planned/delivered training days differ")
            results.append({"persona": name, "week": number, "trainingDays": training_days,
                            "totalSets": total_sets, "appearances": appearances,
                            "displayedTargetSets": dict(sorted(target_sets.items())),
                            "belowTwoSets": below_two, "days": daily})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-min-sets", type=int, choices=[2])
    args = parser.parse_args()
    try:
        results = audit(json.loads(args.evidence.read_text(encoding="utf-8")))
    except (OSError, ValueError, TypeError, AttributeError, KeyError) as error:
        parser.exit(2, f"Evidence rejected: {error}\n")
    output = json.dumps({"scope": "Prescription arithmetic only; displayed targets are not biological credits.",
                         "weeks": results}, indent=2) + "\n"
    if args.output:
        args.output.write_text(output, encoding="utf-8")
    else:
        print(output, end="")
    short = sum(len(w["belowTwoSets"]) for w in results)
    print(f"Measured {len(results)} weeks; {short} prescriptions below two sets.")
    if args.require_min_sets and short:
        parser.exit(1, "Product acceptance FAILED: below-two-set prescriptions remain.\n")


if __name__ == "__main__":
    main()
