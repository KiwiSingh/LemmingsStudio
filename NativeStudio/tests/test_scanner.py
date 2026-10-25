import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("scan_plugins", Path(__file__).parents[1] / "tools/scan_plugins.py")
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)

class ScannerTests(unittest.TestCase):
    def test_timeout_is_quarantined_and_not_retried(self):
        with tempfile.TemporaryDirectory() as folder:
            database = Path(folder) / "registry.json"
            with patch.object(scanner.subprocess, "run", side_effect=subprocess.TimeoutExpired("host", .1)) as runner:
                scanner.scan(Path("host"), ["broken.vst3"], database, .1)
                scanner.scan(Path("host"), ["broken.vst3"], database, .1)
                self.assertEqual(runner.call_count, 1)
            entry = next(iter(json.loads(database.read_text()).values()))
            self.assertTrue(entry["quarantined"])

    def test_crash_is_quarantined(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(scanner.subprocess, "run", return_value=subprocess.CompletedProcess([], -11)):
                result = scanner.scan(Path("host"), ["crash.vst3"], Path(folder) / "registry.json")
                self.assertTrue(next(iter(result.values()))["quarantined"])
