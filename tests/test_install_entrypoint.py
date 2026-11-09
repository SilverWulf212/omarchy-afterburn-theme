"""The short installer preserves the existing Omarchy/extras flow and terminal input."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ENTRY = Path(__file__).resolve().parents[1] / 'install.sh'


class InstallEntrypoint(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.env = {**os.environ, 'HOME': str(self.home), 'PATH': str(self.bin)}
        self.installer = self.home / '.config/omarchy/themes/afterburn/extras/install.sh'
        self.installer.parent.mkdir(parents=True)
        self.installer.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$HOME/extras-args"\nIFS= read -r reply\nprintf "%s" "$reply" > "$HOME/reply"\n')
        self.installer.chmod(0o755)

    def omarchy(self, status=0):
        path = self.bin / 'omarchy'
        path.write_text(f'#!/bin/bash\nprintf "%s\\n" "$@" > "$HOME/theme-args"\nexit {status}\n')
        path.chmod(0o755)

    def run_entry(self, *args):
        return subprocess.run(['/bin/bash', str(ENTRY), *args], env=self.env,
                              input='keep-terminal-input\n', text=True, capture_output=True)

    def test_original_theme_command_then_extras_preserves_arguments_and_stdin(self):
        self.omarchy()
        result = self.run_entry('--yes')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / 'theme-args').read_text().splitlines(),
                         ['theme', 'install', 'https://github.com/silverwulf212/omarchy-afterburn-theme'])
        self.assertEqual((self.home / 'extras-args').read_text(), '--yes\n')
        self.assertEqual((self.home / 'reply').read_text(), 'keep-terminal-input')

    def test_theme_failure_stops_before_extras(self):
        self.omarchy(status=17)
        result = self.run_entry()
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertFalse((self.home / 'extras-args').exists())

    def test_missing_omarchy_has_clear_failure(self):
        result = self.run_entry()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Omarchy', result.stderr)
        self.assertFalse((self.home / 'extras-args').exists())

    def test_missing_extras_has_clear_failure(self):
        self.omarchy()
        self.installer.unlink()
        result = self.run_entry()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('extras installer', result.stderr)


if __name__ == '__main__':
    unittest.main()
