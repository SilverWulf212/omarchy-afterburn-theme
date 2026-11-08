"""Executable installer regressions; all commands run in a temporary HOME and whitelist PATH."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="afterburn-ownership-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.extras = self.home / ".config/omarchy/themes/afterburn/extras"
        shutil.copytree(REPO / "extras", self.extras)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("bash", "sh", "awk", "sed", "grep", "head", "tail", "cat", "cp", "mv", "rm",
                     "mkdir", "rmdir", "ln", "readlink", "realpath", "install", "chmod", "mktemp",
                     "tr", "cut", "date", "id", "basename", "dirname", "wc", "sort", "find", "jq",
                     "cmp", "sha256sum", "xargs"):
            target = shutil.which(name)
            self.assertIsNotNone(target, name)
            (self.bin / name).symlink_to(target)
        self.log = self.root / "commands"
        self.official = self.root / "omarchy"
        self.write(self.official / "shell/plugins/lock/LockView.qml",
                   'Item {\n    MultiEffect {\n    }\n    MouseArea {\n    }\n    BorderSurface {\n    }\n}\n')
        self.env = dict(HOME=str(self.home), USER="tester", PATH=str(self.bin),
                        STUB_LOG=str(self.log), LOCK_EMBERS_OMARCHY_PATH=str(self.official))
        self.stub("omarchy", '''case "$*" in
"font current") echo 'JetBrainsMono Nerd Font';;
"hook install theme-set "*) mkdir -p "$HOME/.config/omarchy/hooks/theme-set.d"; cp "$4" "$HOME/.config/omarchy/hooks/theme-set.d/afterburn-theme-set-hook";;
esac''')
        for name in ("ghostty", "cursor-fx", "systemctl", "hyprctl", "omarchy-shell", "omarchy-plugin-enable"):
            self.stub(name, "exit 0")
        self.stub("omarchy-plugin-list", 'echo "omarchy.lock enabled"')
        self.stub("omarchy-plugin-clone", '''d="$HOME/.config/omarchy/plugins/$USER.lock"
mkdir -p "$d"
cp "$LOCK_EMBERS_OMARCHY_PATH/shell/plugins/lock/LockView.qml" "$d/"
echo '{"omarchy":{"clonedFrom":"omarchy.lock"}}' > "$d/manifest.json"''')
        self.stub("omarchy-plugin-validate", "exit 0")
        self.stub("omarchy-plugin-remove", 'rm -rf "$HOME/.config/omarchy/plugins/$1"')
        self.write(self.home / ".config/xdg-terminals.list", "ghostty.desktop\n")
        self.state = self.home / ".local/state/afterburn"
        self.clone = self.home / ".config/omarchy/plugins/tester.lock"
        self.conf = self.home / ".config/afterburn/afterburn.conf"
        self.unit = self.home / ".config/systemd/user/afterburn-watch.service"
        self.desktop = self.home / ".local/share/applications/afterburn-colors.desktop"

    def write(self, path, contents):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def stub(self, name, body):
        path = self.bin / name
        if path.is_symlink():
            path.unlink()
        path.write_text('#!/bin/bash\necho "' + name + ' $*" >> "$STUB_LOG"\n' + body + '\n')
        path.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run([str(self.bin / "bash"), str(self.extras / name), *args],
                              env=self.env, input="", text=True, capture_output=True)

    def install(self):
        result = self.run_script("install.sh", "--yes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_skipped_pack_preserves_preexisting_files(self):
        self.write(self.home / ".local/bin/afterburn", "mine\n")
        files = (self.conf, self.unit, self.desktop)
        for path in files:
            self.write(path, "my resource\n")
        self.install()
        self.run_script("uninstall.sh")
        for path in files:
            self.assertTrue(path.exists(), str(path))
            self.assertEqual(path.read_text(), "my resource\n")

    def test_installer_preserves_file_collisions(self):
        for path in (self.unit, self.desktop):
            self.write(path, "mine\n")
        self.install()
        for path in (self.unit, self.desktop):
            self.assertEqual(path.read_text(), "mine\n")

    def test_existing_upstream_clone_is_not_adopted(self):
        self.write(self.clone / "manifest.json", '{"omarchy":{"clonedFrom":"omarchy.lock"}}')
        self.write(self.clone / "LockView.qml", "my custom lock\n")
        self.install()
        self.assertFalse((self.clone / "EmberLayer.qml").exists())
        self.assertFalse((self.state / "lock-embers").exists())
        self.run_script("uninstall.sh")
        self.assertEqual((self.clone / "LockView.qml").read_text(), "my custom lock\n")

    def test_failed_partial_lock_install_remains_retryable(self):
        self.stub("omarchy-plugin-validate", "exit 1")
        self.stub("omarchy-plugin-remove", "exit 1")
        self.install()
        self.assertTrue((self.state / "lock-embers").exists())
        self.assertNotEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertTrue((self.state / "lock-embers").exists())
        self.stub("omarchy-plugin-remove", 'rm -rf "$HOME/.config/omarchy/plugins/$1"')
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertFalse(self.clone.exists())

    def test_partial_lock_removal_is_retryable_without_internal_markers(self):
        self.install()
        self.stub("omarchy-plugin-remove", '''d="$HOME/.config/omarchy/plugins/$1"
rm -f "$d/EmberLayer.qml" "$d/manifest.json" "$d/.afterburn-lock-embers"
exit 1''')
        self.assertNotEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertTrue((self.state / "lock-embers").exists())
        self.assertFalse((self.clone / "manifest.json").exists())
        self.stub("omarchy-plugin-remove", 'rm -rf "$HOME/.config/omarchy/plugins/$1"')
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertFalse(self.clone.exists())

    def test_partial_lock_retry_keeps_changed_survivors(self):
        self.install()
        self.stub("omarchy-plugin-remove", 'rm -f "$HOME/.config/omarchy/plugins/$1/EmberLayer.qml"; exit 1')
        self.assertNotEqual(self.run_script("uninstall.sh").returncode, 0)
        self.write(self.clone / "LockView.qml", "my edited surviving lock\n")
        self.stub("omarchy-plugin-remove", 'rm -rf "$HOME/.config/omarchy/plugins/$1"')
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertEqual((self.clone / "LockView.qml").read_text(), "my edited surviving lock\n")

    def test_install_rollback_partial_removal_retains_external_ownership(self):
        self.assert_install_rollback_retryable()

    def test_anchor_rollback_partial_removal_retains_external_ownership(self):
        self.stub("omarchy-plugin-clone", '''d="$HOME/.config/omarchy/plugins/$USER.lock"
mkdir -p "$d"
echo 'changed layout' > "$d/LockView.qml"
echo '{"omarchy":{"clonedFrom":"omarchy.lock"}}' > "$d/manifest.json"''')
        self.assert_install_rollback_retryable()

    def assert_install_rollback_retryable(self):
        self.stub("omarchy-plugin-validate", "exit 1")
        self.stub("omarchy-plugin-remove", '''d="$HOME/.config/omarchy/plugins/$1"
rm -f "$d/EmberLayer.qml" "$d/manifest.json" "$d/.afterburn-lock-embers"
exit 1''')
        self.install()
        self.assertFalse((self.clone / "manifest.json").exists())
        self.assertFalse((self.clone / ".afterburn-lock-embers").exists())
        self.assertTrue((self.state / "lock-removal/id").exists())
        self.assertTrue((self.state / "lock-embers").exists())
        self.stub("omarchy-plugin-remove", 'rm -rf "$HOME/.config/omarchy/plugins/$1"')
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertFalse(self.clone.exists())
        self.assertFalse((self.state / "lock-embers").exists())

    def test_failed_remove_remains_retryable(self):
        self.install()
        self.stub("omarchy-plugin-remove", "exit 1")
        result = self.run_script("uninstall.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.state / "lock-embers").exists())
        self.stub("omarchy-plugin-remove", 'rm -rf "$HOME/.config/omarchy/plugins/$1"')
        result = self.run_script("uninstall.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.clone.exists())
        self.assertFalse((self.state / "lock-embers").exists())

    def test_modified_installed_resources_survive(self):
        self.install()
        for path in (self.conf, self.unit, self.desktop):
            self.write(path, "my replacement\n")
        self.run_script("uninstall.sh")
        for path in (self.conf, self.unit, self.desktop):
            self.assertTrue(path.exists(), str(path))
            self.assertEqual(path.read_text(), "my replacement\n")

    def test_modified_lock_clone_survives(self):
        self.install()
        self.write(self.clone / "custom.qml", "my customization\n")
        self.run_script("uninstall.sh")
        self.assertTrue((self.clone / "custom.qml").exists())

    def test_rerun_preserves_modified_files(self):
        self.install()
        for path in (self.unit, self.desktop):
            self.write(path, "my replacement\n")
        self.install()
        for path in (self.unit, self.desktop):
            self.assertEqual(path.read_text(), "my replacement\n")
        self.run_script("uninstall.sh")
        self.assertTrue(self.unit.exists())
        self.assertTrue(self.desktop.exists())

    def test_modified_bashrc_marker_line_survives(self):
        self.install()
        self.write(self.home / ".bashrc", "echo my custom replacement  # afterburn\n")
        self.run_script("uninstall.sh")
        self.assertEqual((self.home / ".bashrc").read_text(), "echo my custom replacement  # afterburn\n")

    def test_modified_hook_survives(self):
        self.install()
        hook = self.home / ".config/omarchy/hooks/theme-set.d/50-afterburn-extras"
        self.write(hook, "my replacement\n")
        self.install()
        self.run_script("uninstall.sh")
        self.assertEqual(hook.read_text(), "my replacement\n")

    def test_legacy_files_and_clone_remain_unclaimed(self):
        self.write(self.conf, "HEAT_SOURCE=time\n")
        self.write(self.unit, (self.extras / "afterburn-watch.service").read_text())
        self.write(self.clone / "manifest.json", '{"omarchy":{"clonedFrom":"omarchy.lock"}}')
        self.write(self.clone / "LockView.qml", "legacy customization\n")
        self.write(self.state / "lock-embers", "")
        result = self.run_script("uninstall.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.conf.exists())
        self.assertTrue(self.unit.exists())
        self.assertTrue((self.state / "lock-embers").exists())
        self.assertEqual((self.clone / "LockView.qml").read_text(), "legacy customization\n")

    def test_unit_stop_failure_is_retryable(self):
        self.install()
        self.stub("systemctl", '[[ "$*" == *"disable --now"* ]] && exit 1; exit 0')
        result = self.run_script("uninstall.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.unit.exists())
        self.assertTrue((self.home / ".local/bin/afterburn-watch").is_symlink())
        self.stub("systemctl", "exit 0")
        result = self.run_script("uninstall.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.unit.exists())
        self.assertFalse((self.home / ".local/bin/afterburn-watch").is_symlink())

    def test_cursor_failure_is_retryable(self):
        self.install()
        self.write(self.state / "prev-cursor-fx", "neon\n")
        self.stub("cursor-fx", "exit 1")
        result = self.run_script("uninstall.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.state / "prev-cursor-fx").read_text(), "neon\n")
        self.stub("cursor-fx", "exit 0")
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertFalse((self.state / "prev-cursor-fx").exists())

    def test_lock_recolor_preserves_user_changes(self):
        self.install()
        self.write(self.clone / "EmberLayer.qml", "my layer\n")
        result = self.run_script("lock/lock-embers.sh", "recolor", "112233", "445566", "778899")
        self.assertEqual(result.returncode, 0)
        self.assertEqual((self.clone / "EmberLayer.qml").read_text(), "my layer\n")
        self.run_script("uninstall.sh")
        self.assertTrue(self.clone.exists())

    def test_owned_lock_recolor_can_be_uninstalled(self):
        self.install()
        result = self.run_script("lock/lock-embers.sh", "recolor", "112233", "445566", "778899")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("445566", (self.clone / "EmberLayer.qml").read_text())
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertFalse(self.clone.exists())

    def test_uninstall_does_not_enable_stock_lock_over_user_choice(self):
        self.install()
        self.log.write_text("")
        self.run_script("uninstall.sh")
        self.assertNotIn("omarchy-plugin-enable", self.log.read_text())

    def edition(self):
        source = self.extras.parent / ".editions/voltage"
        self.write(source / "colors.toml", 'accent = "#112233"\n')
        self.write(source / "edition.conf", "ROTATE=fast\n")
        return source, self.extras.parent.parent / "afterburn-voltage"

    def test_modified_edition_survives_rerun_and_uninstall(self):
        source, dest = self.edition()
        self.install()
        self.write(dest / "edition.conf", "ROTATE=off  # mine\n")
        self.write(source / "new.txt", "new release file\n")
        self.install()
        self.assertEqual((dest / "edition.conf").read_text(), "ROTATE=off  # mine\n")
        self.run_script("uninstall.sh")
        self.assertTrue(dest.exists())
        self.assertEqual((dest / "edition.conf").read_text(), "ROTATE=off  # mine\n")

    def test_unchanged_edition_refresh_can_be_removed(self):
        source, dest = self.edition()
        self.install()
        self.write(source / "new.txt", "new release file\n")
        self.install()
        self.assertEqual((dest / "new.txt").read_text(), "new release file\n")
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertFalse(dest.exists())

    def test_preexisting_matching_links_and_bashrc_are_not_owned(self):
        link = self.home / ".local/bin/afterburn"
        link.parent.mkdir(parents=True)
        link.symlink_to(self.extras / "bin/afterburn")
        self.write(self.home / ".bashrc", "echo my setup  # afterburn\n")
        self.install()
        self.run_script("uninstall.sh")
        self.assertTrue(link.is_symlink())
        self.assertEqual((self.home / ".bashrc").read_text(), "echo my setup  # afterburn\n")

    def test_edition_refresh_does_not_write_through_directory_symlink(self):
        source, dest = self.edition()
        self.write(source / "nested/old.txt", "original\n")
        self.install()
        shutil.rmtree(dest / "nested")
        outside = self.root / "user-dir"
        outside.mkdir()
        (dest / "nested").symlink_to(outside, target_is_directory=True)
        self.write(source / "nested/new.txt", "release addition\n")
        self.install()
        self.assertFalse((outside / "new.txt").exists())
        self.run_script("uninstall.sh")
        self.assertTrue(dest.exists())

    def test_partial_edition_removal_is_retryable(self):
        _, dest = self.edition()
        self.install()
        real_rm = shutil.which("rm")
        self.stub("rm", f'''if [[ "$*" == *afterburn-voltage* ]]; then
  {real_rm} -f "$HOME/.config/omarchy/themes/afterburn-voltage/colors.toml"
  exit 1
fi
exec {real_rm} "$@"''')
        self.assertNotEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertTrue((self.state / "editions").exists())
        self.assertFalse((dest / "colors.toml").exists())
        self.stub("rm", f'exec {real_rm} "$@"')
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertFalse(dest.exists())

    def test_partial_edition_retry_keeps_changed_survivors(self):
        _, dest = self.edition()
        self.install()
        real_rm = shutil.which("rm")
        self.stub("rm", f'''if [[ "$*" == *afterburn-voltage* ]]; then
  {real_rm} -f "$HOME/.config/omarchy/themes/afterburn-voltage/colors.toml"
  exit 1
fi
exec {real_rm} "$@"''')
        self.assertNotEqual(self.run_script("uninstall.sh").returncode, 0)
        self.write(dest / "edition.conf", "my changed survivor\n")
        self.stub("rm", f'exec {real_rm} "$@"')
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertEqual((dest / "edition.conf").read_text(), "my changed survivor\n")

    def test_dotfile_write_failures_are_retryable(self):
        starship = self.home / ".config/starship.toml"
        self.write(starship, '[character]\nerror_symbol = "original"\n')
        self.install()
        real_mv = shutil.which("mv")
        self.stub("mv", f'''for arg in "$@"; do
  [[ $arg == "$HOME/.bashrc" || $arg == "$HOME/.config/starship.toml" ]] && exit 1
done
exec {real_mv} "$@"''')
        self.assertNotEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertTrue((self.state / "bashrc-line").exists())
        self.assertTrue((self.state / "starship-error-symbol").exists())
        self.stub("mv", f'exec {real_mv} "$@"')
        self.assertEqual(self.run_script("uninstall.sh").returncode, 0)
        self.assertEqual(starship.read_text(), '[character]\nerror_symbol = "original"\n')
        self.assertFalse((self.home / ".bashrc").exists())

    def test_created_resources_are_removed(self):
        self.install()
        result = self.run_script("uninstall.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for path in (self.conf, self.unit, self.desktop, self.clone):
            self.assertFalse(path.exists(), str(path))


if __name__ == "__main__":
    unittest.main()
