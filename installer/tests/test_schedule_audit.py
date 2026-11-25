"""Offline preservation checks for active feeders; no device is contacted."""

from copy import deepcopy
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

path = Path(__file__).resolve().parents[2] / "tools/audit_schedule.py"
spec = importlib.util.spec_from_file_location("schedule_audit", path)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def snapshot(order="sunday_bit_0"):
    return {"format": 1, "device_id": "synthetic-feeder-a", "weekday_order": order, "meals": [
        {"weekdays": mask, "hour": hour, "minute": 5, "portions": hour % 10 + 1, "enabled": True}
        for hour, mask in enumerate([1, 2, 4, 8, 16, 32, 64, 127])]}


class ScheduleAuditTests(unittest.TestCase):
    def test_complete_active_table_converts_without_losing_rows(self):
        before = snapshot()
        after = snapshot("saturday_bit_0")
        for row, mask in zip(after["meals"], [64, 32, 16, 8, 4, 2, 1, 127]):
            row["weekdays"] = mask
        original = deepcopy(after)
        result = audit.compare(before, after)
        self.assertTrue(result["match"])
        self.assertEqual(result["rows_after"], 8)
        self.assertEqual(result["enabled_after"], 8)
        self.assertEqual(after, original)
        self.assertEqual(result["device_commands"], 0)

    def test_every_meal_field_and_row_count_are_compared(self):
        before = snapshot()
        for field, value in [("weekdays", 3), ("hour", 23), ("minute", 59), ("portions", 10), ("enabled", False)]:
            after = deepcopy(before)
            after["meals"][0][field] = value
            self.assertEqual(audit.compare(before, after)["changed_row_numbers"], [1])
        after = deepcopy(before)
        after["meals"].pop()
        self.assertEqual(audit.compare(before, after)["changed_row_numbers"], [8])

    def test_wrong_device_is_refused_even_with_an_identical_table(self):
        after = snapshot()
        after["device_id"] = "synthetic-feeder-b"
        with self.assertRaisesRegex(ValueError, "different devices"):
            audit.compare(snapshot(), after)

    def test_ambiguous_masks_and_invalid_rows_are_refused(self):
        for field, value in [("weekday_order", "tuya"), ("format", True), ("device_id", "")]:
            data = snapshot()
            data[field] = value
            with self.assertRaises(ValueError): audit.normalize(data)
        for field, value in [("weekdays", True), ("weekdays", 128), ("hour", 24), ("minute", 60), ("portions", 0), ("enabled", 1)]:
            data = snapshot()
            data["meals"][0][field] = value
            with self.assertRaises(ValueError): audit.normalize(data)
        data = snapshot()
        data["meals"].append(data["meals"][0])
        with self.assertRaises(ValueError): audit.normalize(data)

    def test_reports_do_not_include_identity_or_meal_times(self):
        report = str(audit.compare(snapshot(), snapshot()))
        for text in ["synthetic-feeder-a", "weekdays", "hour", "minute", "portions"]:
            self.assertNotIn(text, report)

    def test_invalid_json_and_oversized_files_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "snapshot.json"
            for content in [b"not-json", b"\xff", b" " * 65537]:
                path.write_bytes(content)
                with self.assertRaises(ValueError): audit.read_snapshot(path)

    def test_cli_exit_codes_distinguish_match_mismatch_and_invalid_identity(self):
        import json
        with tempfile.TemporaryDirectory() as directory:
            before = Path(directory) / "before.json"
            after = Path(directory) / "after.json"
            before.write_text(json.dumps(snapshot()))
            for expected, data in [(0, snapshot()), (1, snapshot()), (2, snapshot())]:
                if expected == 1: data["meals"][7]["enabled"] = False
                if expected == 2: data["device_id"] = "another-synthetic-device"
                after.write_text(json.dumps(data))
                result = subprocess.run([sys.executable, str(path), "--before", str(before), "--after", str(after)],
                                        capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, expected)
                self.assertNotIn("synthetic-feeder-a", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
