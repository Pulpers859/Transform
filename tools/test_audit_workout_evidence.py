"""Attacks against the observer, independent of the shipping validator."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from audit_workout_evidence import audit


def fixture():
    weeks = []
    for number in range(1, 5):
        days = [{"dayNumber": day, "isRestDay": (day - 1) % 7 != 0,
                 "exercises": []} for day in range((number - 1) * 7 + 1, number * 7 + 1)]
        days[0]["exercises"] = [
            {"exerciseName": "Row", "muscleTarget": "Back", "sets": 3, "reps": "8-12", "restSeconds": 90},
            {"exerciseName": "Curl", "muscleTarget": "Biceps", "sets": 1, "reps": "10-12", "restSeconds": 60}]
        weeks.append({"weekNumber": number, "plannedTrainingDays": 1, "days": days,
                      "validatorFindings": []})
    return {"schemaVersion": 1, "personas": [{"name": "Synthetic", "weeks": weeks}]}


class EvidenceAuditTests(unittest.TestCase):
    def test_counts_actual_exercises_even_without_validator_warnings(self):
        week = audit(fixture(), expected_personas=1)[0]
        self.assertEqual((week["totalSets"], week["appearances"], week["trainingDays"]), (4, 2, 1))
        self.assertEqual(week["displayedTargetSets"], {"Back": 3, "Biceps": 1})
        self.assertEqual(week["belowTwoSets"], [{"day": 1, "exercise": "Curl", "sets": 1}])

    def test_repeating_exercise_on_another_day_spends_another_dose(self):
        document = fixture()
        week = document["personas"][0]["weeks"][0]
        week["days"][1]["isRestDay"] = False
        week["days"][1]["exercises"] = copy.deepcopy(week["days"][0]["exercises"])
        week["plannedTrainingDays"] = 2
        result = audit(document, expected_personas=1)[0]
        self.assertEqual((result["totalSets"], result["appearances"]), (8, 4))

    def test_rejects_missing_evidence(self):
        for key in ("personas", "schemaVersion"):
            document = fixture()
            del document[key]
            with self.assertRaises(ValueError):
                audit(document, expected_personas=1)

    def test_rejects_incomplete_persona_matrix(self):
        with self.assertRaises(ValueError):
            audit(fixture())

    def test_cli_acceptance_fails_until_actual_dose_changes(self):
        document = fixture()
        document["personas"] = [copy.deepcopy(document["personas"][0]) for _ in range(5)]
        for index, persona in enumerate(document["personas"]):
            persona["name"] = f"Synthetic {index}"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            command = [sys.executable, str(Path(__file__).with_name("audit_workout_evidence.py")),
                       str(path), "--require-min-sets", "2"]
            path.write_text(json.dumps(document), encoding="utf-8")
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("20 prescriptions below two sets", result.stdout)
            for persona in document["personas"]:
                for week in persona["weeks"]:
                    week["days"][0]["exercises"][1]["sets"] = 2
            path.write_text(json.dumps(document), encoding="utf-8")
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            path.write_text("{}", encoding="utf-8")
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)

    def test_rejects_bad_prescriptions_instead_of_coercing_them(self):
        for value in (0, -1, 1.5, "2", True, None):
            with self.subTest(value=value):
                document = fixture()
                document["personas"][0]["weeks"][0]["days"][0]["exercises"][0]["sets"] = value
                with self.assertRaises(ValueError):
                    audit(document, expected_personas=1)

    def test_rejects_bad_rest_day_duplicate_and_missing_days(self):
        for attack in ("rest", "duplicate", "missing", "renumber", "trainingCount", "empty"):
            with self.subTest(attack=attack):
                document = fixture()
                week = document["personas"][0]["weeks"][0]
                if attack == "rest":
                    week["days"][0]["isRestDay"] = True
                elif attack == "duplicate":
                    week["days"][0]["exercises"] *= 2
                elif attack == "missing":
                    week["days"].pop()
                elif attack == "renumber":
                    week["days"][0]["dayNumber"] = 2
                elif attack == "trainingCount":
                    week["plannedTrainingDays"] = 2
                else:
                    week["days"][0]["exercises"] = []
                with self.assertRaises(ValueError):
                    audit(document, expected_personas=1)


if __name__ == "__main__":
    unittest.main()
