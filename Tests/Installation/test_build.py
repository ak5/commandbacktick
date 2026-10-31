"""Check identity selection without using a real keychain or compiling Swift."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]


class BuildSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(REPO / "scripts/build-app.sh", self.root / "scripts/build-app.sh")
        (self.root / "Info.plist").write_text("fixture")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "CommandBacktick").write_text("synthetic executable")
        self.log = self.root / "signing-arguments"
        stubs = {
            "swift": 'case "$*" in *--show-bin-path*) printf "%s\\n" "$TEST_BUILD_BIN" ;; esac',
            "codesign": 'printf "%s\\n" "$@" >> "$TEST_SIGNING_LOG"\nexit "${FAIL_SIGN:-0}"',
        }
        for name, body in stubs.items():
            path = self.bin / name
            path.write_text("#!/bin/sh\n" + body + "\n")
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ":/usr/bin:/bin",
                        TEST_BUILD_BIN=str(self.bin), TEST_SIGNING_LOG=str(self.log))
        self.env.pop("COMMAND_BACKTICK_SIGNING_IDENTITY", None)

    def build(self, **overrides):
        return subprocess.run(["/bin/sh", str(self.root / "scripts/build-app.sh")],
                              env=dict(self.env, **overrides), capture_output=True, text=True)

    def test_default_build_is_adhoc(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--sign\n-\n", self.log.read_text())
        self.assertIn("--verify\n--strict\n", self.log.read_text())

    def test_local_identity_and_environment_override(self):
        (self.root / "signing.local.txt").write_text("Fixture Local Identity\n")
        self.assertEqual(self.build().returncode, 0)
        self.assertIn("--sign\nFixture Local Identity\n", self.log.read_text())
        self.log.unlink()
        self.assertEqual(self.build(COMMAND_BACKTICK_SIGNING_IDENTITY="Fixture Override").returncode, 0)
        self.assertIn("--sign\nFixture Override\n", self.log.read_text())

    def test_configured_identity_failure_does_not_fall_back(self):
        result = self.build(COMMAND_BACKTICK_SIGNING_IDENTITY="Missing Identity", FAIL_SIGN="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--sign\nMissing Identity\n", self.log.read_text())
        self.assertNotIn("--sign\n-\n", self.log.read_text())

    def test_empty_configured_identity_fails(self):
        result = self.build(COMMAND_BACKTICK_SIGNING_IDENTITY="")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())
