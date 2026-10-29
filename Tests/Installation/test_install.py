"""Exercise the real installer in an isolated home without touching running apps."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        (self.project / "scripts").mkdir(parents=True)
        shutil.copy2(REPO / "scripts/install-app.sh", self.project / "scripts/install-app.sh")
        source = self.project / "dist/CommandBacktick.app"
        source.mkdir(parents=True)
        (source / "binary").write_text("new build")
        self.home = self.root / "home"
        self.destination = self.home / "Applications/CommandBacktick.app"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        stubs = {
            "codesign": 'exit "${FAIL_SIGN:-0}"',
            "ditto": '/bin/cp -R "$1" "$2"',
            "pkill": 'exit 1',
            "mv": '''case "$1" in
  */.commandbacktick-install.*/CommandBacktick.app)
    if [ "${FAIL_INSTALL:-0}" = 1 ]; then exit 1; fi ;;
esac
exec /bin/mv "$@"''',
        }
        for name, body in stubs.items():
            path = self.bin / name
            path.write_text("#!/bin/sh\n" + body + "\n")
            path.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), TMPDIR=str(self.root),
                        PATH=str(self.bin) + ":/usr/bin:/bin")

    def old_app(self):
        self.destination.mkdir(parents=True)
        (self.destination / "binary").write_text("old build")

    def install(self, **overrides):
        return subprocess.run(["/bin/sh", str(self.project / "scripts/install-app.sh")],
                              env=dict(self.env, **overrides), capture_output=True, text=True)

    def test_first_install_and_update_preserve_previous_bundle(self):
        first = self.install()
        self.assertEqual(first.returncode, 0, first.stderr)
        (self.destination / "binary").write_text("old build")
        old_inode = self.destination.stat().st_ino
        update = self.install()
        self.assertEqual(update.returncode, 0, update.stderr)
        self.assertEqual((self.destination / "binary").read_text(), "new build")
        backups = list(self.root.glob("commandbacktick-backup.*/CommandBacktick.app"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_ino, old_inode)
        self.assertEqual((backups[0] / "binary").read_text(), "old build")
        self.assertNotEqual(self.destination.stat().st_ino, old_inode)

    def test_invalid_signature_leaves_installed_app_alone(self):
        self.old_app()
        result = self.install(FAIL_SIGN="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.destination / "binary").read_text(), "old build")

    def test_failed_replacement_restores_previous_bundle(self):
        self.old_app()
        result = self.install(FAIL_INSTALL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.destination / "binary").read_text(), "old build")
        self.assertEqual(list((self.home / "Applications").glob(".commandbacktick-install.*")), [])
