#!/usr/bin/env python3
"""Negative controls for focused-test evidence; runs without Swift or networking."""
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import xml.etree.ElementTree as ET

from run_focused_generator_tests import EXPECTED_CLASSES, PLANNING_SUITES, REQUIRED_CASES, main, test_filter, verify_results


class FocusedEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "results.xml"
        self.root = ET.Element("testsuite", failures="0", errors="0")
        for name in sorted(EXPECTED_CLASSES):
            method = next((method for suite, method in REQUIRED_CASES if suite == name), "testExample")
            ET.SubElement(self.root, "testcase", classname=name, name=method)

    def verify(self):
        ET.ElementTree(self.root).write(self.path)
        return verify_results(self.path)

    def test_every_suite_required(self):
        self.assertEqual(sum(self.verify().values()), len(PLANNING_SUITES))
        self.root.remove(self.root[0])
        with self.assertRaises(ValueError):
            self.verify()

    def test_empty_report_rejected(self):
        self.root.clear()
        with self.assertRaises(ValueError):
            self.verify()

    def test_required_probe_cannot_hide_behind_another_passing_test(self):
        for case in self.root:
            if (case.get("classname"), case.get("name")) in REQUIRED_CASES:
                case.set("name", "testDifferentPassingCase")
                break
        with self.assertRaises(ValueError):
            self.verify()

    def test_missing_and_malformed_report_rejected(self):
        with self.assertRaises(FileNotFoundError):
            verify_results(self.path)
        self.path.write_text("<broken", encoding="utf-8")
        with self.assertRaises(ET.ParseError):
            verify_results(self.path)

    def test_failed_errored_or_skipped_case_rejected(self):
        for tag in ("failure", "error", "skipped"):
            with self.subTest(tag=tag):
                child = ET.SubElement(self.root[0], tag)
                with self.assertRaises(ValueError):
                    self.verify()
                self.root[0].remove(child)

    def test_aggregate_failure_rejected(self):
        for attribute in ("failures", "errors"):
            self.root.set(attribute, "1")
            with self.assertRaises(ValueError):
                self.verify()
            self.root.set(attribute, "0")

    def test_duplicate_rejected(self):
        ET.SubElement(self.root, "testcase", **self.root[0].attrib)
        with self.assertRaises(ValueError):
            self.verify()

    def test_unexpected_class_rejected(self):
        self.root[0].set("classname", "TransformGeneratorCoreTests.UnrelatedTests")
        with self.assertRaises(ValueError):
            self.verify()

    def test_filter_is_anchored_and_includes_only_allowlisted_suites(self):
        pattern = re.compile(test_filter())
        for name in EXPECTED_CLASSES:
            self.assertIsNotNone(pattern.search(name + "/testExample"))
            self.assertIsNone(pattern.search("Other" + name + "/testExample"))
            self.assertIsNone(pattern.search(name + "Extra/testExample"))
        self.assertIsNone(pattern.search("TransformGeneratorCoreTests.BodyAnalysisLiveContractTests/testLive"))

    def test_selected_suites_exist_in_repository(self):
        test_root = Path(__file__).resolve().parent.parent / "Tests/TransformGeneratorCoreTests"
        declarations = "\n".join(path.read_text(encoding="utf-8") for path in test_root.glob("*.swift"))
        for name in PLANNING_SUITES:
            self.assertRegex(declarations, rf"\bclass\s+{name}\s*:\s*XCTestCase\b")

    def invoke_runner(self, status, write_report=False):
        process = MagicMock()
        process.__enter__.return_value = process
        process.stdout = iter(["mock Swift output\n"])
        process.wait.return_value = status

        def launch(command, **kwargs):
            # The previous report must be gone BEFORE Swift starts.
            self.assertFalse((Path(self.temp.name) / "planning-tests.xml").exists())
            self.assertEqual(command[0:4], ["swift", "test", "--enable-xctest", "--parallel"])
            self.assertFalse(kwargs.get("shell", False))
            if write_report:
                ET.ElementTree(self.root).write(Path(self.temp.name) / "planning-tests.xml")
            return process

        with patch("sys.argv", ["runner", "--output-dir", self.temp.name]), \
             patch.dict("os.environ", {"GITHUB_STEP_SUMMARY": ""}), \
             patch("builtins.print"), \
             patch("run_focused_generator_tests.subprocess.Popen", side_effect=launch):
            return main()

    def test_swift_failure_cannot_reuse_stale_passing_report(self):
        stale = Path(self.temp.name) / "planning-tests.xml"
        ET.ElementTree(self.root).write(stale)
        self.assertEqual(self.invoke_runner(7), 7)
        self.assertFalse(stale.exists())

    def test_success_exit_without_xml_still_fails(self):
        with self.assertRaises(FileNotFoundError):
            self.invoke_runner(0)

    def test_success_requires_fresh_verified_xml(self):
        self.assertEqual(self.invoke_runner(0, write_report=True), 0)


if __name__ == "__main__":
    unittest.main()
