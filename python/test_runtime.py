"""Exercise packaged command boundaries without Wine or proprietary media."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

LAUNCHER = Path(os.environ["INVENTOR_TEST_LAUNCHER"])


class RuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.environment = dict(os.environ)
        for key in (
            "DISPLAY",
            "WAYLAND_DISPLAY",
            "SSH_TTY",
            "XDG_DATA_HOME",
            "XDG_CACHE_HOME",
            "XDG_STATE_HOME",
            "INVENTOR_DATA_HOME",
            "INVENTOR_CACHE_HOME",
            "INVENTOR_STATE_HOME",
            "WINEDEBUG",
        ):
            self.environment.pop(key, None)
        self.environment["HOME"] = str(self.home)
        self.environment["SSH_CONNECTION"] = "fixture"
        self.data = self.home / ".local/share/inventor"

    def launch(
        self, *arguments: str, environment: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(LAUNCHER), *arguments],
            env=self.environment | (environment or {}),
            text=True,
            capture_output=True,
            timeout=10,
            check=False,
        )

    def test_help_is_explicit_and_has_no_side_effects(self) -> None:
        result = self.launch("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        for text in ("experimental", "--installer", "--year", "INVENTOR_", "Wine"):
            self.assertIn(text, result.stdout)
        self.assertFalse(self.data.exists())

    def test_install_help_never_initializes_prefix(self) -> None:
        result = self.launch("install", "--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No Autodesk payload", result.stdout)
        self.assertFalse(self.data.exists())

    def test_invalid_commands_and_options_do_not_create_state(self) -> None:
        for arguments, message in (
            (("unknown",), "Unknown command"),
            (("install",), "Provide official"),
            (("install", "--installer"), "requires a file"),
            (("install", "--unknown"), "Unknown install option"),
            (
                ("install", "--installer", "missing", "--graphics", "opengl"),
                "Graphics must be",
            ),
            (("run", "--year"), "--year requires"),
            (("run", "--year", "invalid"), "four digits"),
            (("run", "--unknown"), "Unknown run option"),
            (("doctor", "unexpected"), "doctor takes no arguments"),
            (("stop", "unexpected"), "stop takes no arguments"),
            (("wine",), "Usage: inventor wine"),
        ):
            with self.subTest(arguments=arguments):
                result = self.launch(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertFalse(self.data.exists())

    def test_missing_prefix_does_not_start_wine(self) -> None:
        for arguments in (("run",), ("stop",), ("wine", "cmd")):
            with self.subTest(arguments=arguments):
                result = self.launch(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("No managed Inventor prefix", result.stderr)
                self.assertFalse(self.data.exists())

    def test_invalid_local_media_is_rejected_before_prefix_creation(self) -> None:
        installer = self.home / "Setup.exe"
        installer.write_text("not a Windows executable")
        result = self.launch("install", "--installer", str(installer))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing MZ", result.stderr)
        self.assertFalse(self.data.exists())

    def test_valid_synthetic_media_still_requires_a_display(self) -> None:
        installer = self.home / "Setup.exe"
        installer.write_bytes(b"MZfixture, never executed")
        result = self.launch("install", "--installer", str(installer))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No X11 display", result.stderr)
        self.assertFalse(self.data.exists())

    def test_doctor_is_read_only(self) -> None:
        result = self.launch("doctor")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Owned prefix: absent", result.stdout)
        self.assertIn("no Inventor compatibility established", result.stdout)
        self.assertIn("Wine diagnostics: -all,err+all", result.stdout)
        self.assertFalse(self.data.exists())

    def test_explicit_wine_diagnostics_are_preserved(self) -> None:
        result = self.launch(
            "doctor", environment={"WINEDEBUG": "-all,err+all,+loaddll"}
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Wine diagnostics: -all,err+all,+loaddll", result.stdout)
        self.assertFalse(self.data.exists())

    def test_relative_state_override_is_rejected(self) -> None:
        result = self.launch("--help", environment={"INVENTOR_DATA_HOME": "relative"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("absolute, non-root", result.stderr)
        self.assertFalse(self.data.exists())

    def test_fusion_state_is_not_used_as_inventor_prefix(self) -> None:
        fusion = self.home / ".local/share/fusion360"
        (fusion / "prefix").mkdir(parents=True)
        registry = fusion / "prefix/system.reg"
        registry.write_text("unrelated Wine prefix")
        result = self.launch("run", environment={"INVENTOR_DATA_HOME": str(fusion)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No managed Inventor prefix", result.stderr)
        self.assertEqual(registry.read_text(), "unrelated Wine prefix")
        self.assertFalse((fusion / "prefix.lock").exists())


if __name__ == "__main__":
    unittest.main()
