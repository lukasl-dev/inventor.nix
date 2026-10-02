"""Installation discovery and provenance regressions with synthetic files only."""

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import deployment


class DeploymentTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.data = Path(temporary.name)
        self.prefix = self.data / "prefix"
        self.autodesk = self.prefix / "drive_c/Program Files/Autodesk"

    def executable(self, year: str = "2026", name: str = "Inventor.exe") -> Path:
        executable = self.autodesk / f"Inventor {year}/Bin" / name
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(b"MZsynthetic application")
        return executable

    def test_missing_installation_does_not_create_state(self) -> None:
        with self.assertRaisesRegex(SystemExit, "not found"):
            deployment.resolve_executable(self.prefix)
        self.assertFalse(self.prefix.exists())

    def test_single_release_is_discovered(self) -> None:
        executable = self.executable()
        self.assertEqual(deployment.resolve_executable(self.prefix), executable)

    def test_multiple_releases_require_selection(self) -> None:
        old = self.executable("2025")
        new = self.executable("2026")
        with self.assertRaisesRegex(SystemExit, "Multiple"):
            deployment.resolve_executable(self.prefix)
        self.assertEqual(deployment.resolve_executable(self.prefix, "2025"), old)
        self.assertEqual(deployment.resolve_executable(self.prefix, "2026"), new)

    def test_invalid_or_absent_year_is_rejected(self) -> None:
        self.executable()
        for year in ("26", "../../2026", "2026 --evil"):
            with self.subTest(year=year):
                with self.assertRaisesRegex(SystemExit, "four digits"):
                    deployment.resolve_executable(self.prefix, year)
        with self.assertRaisesRegex(SystemExit, "not found"):
            deployment.resolve_executable(self.prefix, "2025")

    def test_case_insensitive_names_are_supported(self) -> None:
        executable = self.autodesk / "INVENTOR 2026/bIN/inVENTOR.ExE"
        executable.parent.mkdir(parents=True)
        executable.touch()
        self.assertEqual(deployment.resolve_executable(self.prefix), executable)

    def test_case_ambiguous_executables_are_not_guessed(self) -> None:
        self.executable(name="Inventor.exe")
        self.executable(name="inventor.exe")
        with self.assertRaisesRegex(SystemExit, "Multiple"):
            deployment.resolve_executable(self.prefix)

    def test_non_release_and_wrong_executable_are_ignored(self) -> None:
        wrong = self.autodesk / "Inventor tools/Bin/Inventor.exe"
        wrong.parent.mkdir(parents=True)
        wrong.touch()
        self.executable(name="InventorView.exe")
        with self.assertRaisesRegex(SystemExit, "not found"):
            deployment.resolve_executable(self.prefix)

    def test_executable_cannot_escape_autodesk_directory(self) -> None:
        outside = self.data / "external/Inventor.exe"
        outside.parent.mkdir()
        outside.touch()
        linked = self.autodesk / "Inventor 2026/Bin/Inventor.exe"
        linked.parent.mkdir(parents=True)
        linked.symlink_to(outside)
        with self.assertRaisesRegex(SystemExit, "escapes"):
            deployment.resolve_executable(self.prefix)

    def test_autodesk_directory_cannot_escape_prefix(self) -> None:
        outside = self.data / "external"
        executable = outside / "Inventor 2026/Bin/Inventor.exe"
        executable.parent.mkdir(parents=True)
        executable.touch()
        self.autodesk.parent.mkdir(parents=True)
        self.autodesk.symlink_to(outside)
        with self.assertRaisesRegex(SystemExit, "escapes the Inventor prefix"):
            deployment.resolve_executable(self.prefix)

    def test_windows_installer_signature_and_file_are_required(self) -> None:
        valid = self.data / "Setup.exe"
        valid.write_bytes(b"MZsynthetic installer")
        deployment.validate_installer(valid)
        invalid = self.data / "page.exe"
        invalid.write_bytes(b"<!doctype html>")
        with self.assertRaisesRegex(SystemExit, "MZ"):
            deployment.validate_installer(invalid)
        for path in (self.data / "missing.exe", self.data / "setup.msi", self.data):
            with self.subTest(path=path):
                with self.assertRaisesRegex(SystemExit, "existing"):
                    deployment.validate_installer(path)

    def test_provenance_records_presence_not_compatibility(self) -> None:
        executable = self.executable()
        installer = self.data / "Setup.exe"
        installer.write_bytes(b"MZsynthetic installer")
        deployment.record_installation(self.prefix, self.data, installer, "11.16")
        metadata = json.loads((self.data / "installation.json").read_text())
        self.assertEqual(
            metadata["installer_sha256"],
            hashlib.sha256(installer.read_bytes()).hexdigest(),
        )
        self.assertEqual(metadata["wine_version"], "11.16")
        self.assertEqual(
            metadata["executables"], [str(executable.relative_to(self.prefix))]
        )
        self.assertIn("unverified", metadata["validation"])
        self.assertFalse((self.data / "installation.tmp").exists())

    def test_failed_installation_does_not_replace_existing_metadata(self) -> None:
        metadata = self.data / "installation.json"
        metadata.write_text('{"keep": true}\n')
        with self.assertRaisesRegex(SystemExit, "no success metadata"):
            deployment.record_installation(
                self.prefix, self.data, self.data / "Setup.exe", "11.16"
            )
        self.assertEqual(metadata.read_text(), '{"keep": true}\n')


if __name__ == "__main__":
    unittest.main()
