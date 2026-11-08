"""Behavior regressions; desktop commands run only as stubs in a temporary HOME."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class RuntimeModes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="afterburn-modes-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in ("bash cat grep sed head tail awk mkdir mv rm readlink realpath "
                        "basename dirname printf date sleep ls jq").split():
            path = shutil.which(command)
            if path:
                (self.bin / command).symlink_to(path)
        theme = self.home / ".config/omarchy/themes/afterburn"
        theme.mkdir(parents=True)
        shutil.copytree(REPO / "extras", theme / "extras")
        shutil.copy(REPO / "colors.toml", theme / "colors.toml")
        self.state = self.home / ".local/state/afterburn"
        self.state.mkdir(parents=True)
        current = self.home / ".local/state/omarchy/current"
        (current / "theme").mkdir(parents=True)
        (current / "theme.name").write_text("afterburn\n")
        self.ghostty = self.home / ".config/ghostty/config"
        self.ghostty.parent.mkdir(parents=True)
        self.ghostty.write_text("config-file = cursor-effects/embers.conf\n")
        self.subtle = self.ghostty.parent / "subtle"
        self.subtle.write_text("off\n")
        self.conf = self.home / ".config/afterburn/afterburn.conf"
        self.conf.parent.mkdir(parents=True)
        self.conf.write_text("HEAT_SOURCE=off\nLAPTOP_MODE=auto\n")
        self.power = self.root / "power"
        (self.power / "BAT").mkdir(parents=True)
        (self.power / "BAT/type").write_text("Battery\n")
        (self.power / "AC").mkdir()
        (self.power / "AC/type").write_text("Mains\n")
        (self.power / "AC/online").write_text("1\n")
        self.env = {"HOME": str(self.home), "PATH": str(self.bin),
                    "POWER_DIR": str(self.power)}
        self.ab = theme / "extras/bin/afterburn"
        self.watch = theme / "extras/bin/afterburn-watch"
        (self.bin / "afterburn").symlink_to(self.ab)
        self.stub("hyprctl", 'echo "$*" >> "$HOME/hypr.log"; exit 0')
        self.stub("omarchy-theme-bg-set", "exit 0")
        self.stub("cursor-fx", '''if [[ $1 == subtle ]]; then
  if [[ -z ${2:-} ]]; then
    echo "Subtle version: $(cat "$HOME/.config/ghostty/subtle") (cursor-fx subtle on|off)"
  else echo "$2" > "$HOME/.config/ghostty/subtle"; fi
elif [[ $1 == off ]]; then echo '# effect off' > "$HOME/.config/ghostty/config"
else printf 'config-file = cursor-effects/%s.conf\\n' "$1" > "$HOME/.config/ghostty/config"; fi''')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def cli(self, *args):
        result = subprocess.run(["/bin/bash", str(self.ab), *args], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def flag(self, name):
        path = self.state / name
        return path.read_text().strip() if path.exists() else "off"

    def tick(self, cached=""):
        result = subprocess.run(["/bin/bash", "-c",
                                 'source "$1"; saver="$2"; power_tick',
                                 "test", str(self.watch), cached], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_effect(self, effect="embers"):
        self.assertEqual(self.ghostty.read_text().strip(),
                         f"config-file = cursor-effects/{effect}.conf")

    def test_quiet_exit_restores_effect_while_saver_stays_on(self):
        self.cli("quiet", "on")
        self.cli("saver", "on")
        self.cli("quiet", "off")
        self.assert_effect()
        self.assertEqual(self.subtle.read_text().strip(), "on")
        self.assertTrue((self.state / "cursor-pre-quiet").exists())
        self.cli("saver", "off")
        self.assert_effect()
        self.assertEqual(self.subtle.read_text().strip(), "off")

    def test_saver_then_fullscreen_resumes_new_effect_and_keeps_own_subtle(self):
        self.subtle.write_text("on\n")
        self.cli("saver", "on")
        self.cli("quiet", "on")
        self.cli("set", "CURSOR_FX", "neon")
        self.cli("quiet", "off")
        self.assert_effect("neon")
        self.cli("saver", "off")
        self.assert_effect("neon")
        self.assertEqual(self.subtle.read_text().strip(), "on")

    def test_disabling_fullscreen_policy_releases_quiet(self):
        self.cli("quiet", "on")
        self.cli("set", "FULLSCREEN_QUIET", "no")
        self.assertEqual(self.flag("quiet"), "off")
        self.assert_effect()

    def test_generic_laptop_force_on_and_off_apply_immediately(self):
        self.cli("set", "LAPTOP_MODE", "on")
        self.assertEqual(self.flag("saver"), "on")
        self.cli("set", "LAPTOP_MODE", "off")
        self.assertEqual(self.flag("saver"), "off")
        (self.power / "AC/online").write_text("0\n")
        self.cli("set", "LAPTOP_MODE", "auto")
        self.assertEqual(self.flag("saver"), "on")

    def test_laptop_auto_reconciles_stale_manual_state_immediately(self):
        self.cli("laptop", "on")
        self.cli("laptop", "auto")
        self.assertEqual(self.flag("saver"), "off")
        self.assert_effect()

    def test_watcher_uses_actual_state_instead_of_stale_cache(self):
        self.cli("saver", "on")
        self.tick("off")
        self.assertEqual(self.flag("saver"), "off")

    def test_watcher_reconciles_forced_policy_after_start(self):
        self.conf.write_text("LAPTOP_MODE=on\n")
        self.tick()
        self.assertEqual(self.flag("saver"), "on")
        self.conf.write_text("LAPTOP_MODE=off\n")
        self.tick("on")
        self.assertEqual(self.flag("saver"), "off")

    def test_usb_power_is_external_power(self):
        for kind in ("USB", "USB_C", "USB_PD", "USB_PD_DRP", "Wireless"):
            with self.subTest(kind=kind):
                (self.power / "AC/type").write_text(kind + "\n")
                self.cli("saver", "on")
                self.tick()
                self.assertEqual(self.flag("saver"), "off")

    def test_auto_on_battery_and_without_battery(self):
        (self.power / "AC/online").write_text("0\n")
        self.tick()
        self.assertEqual(self.flag("saver"), "on")
        shutil.rmtree(self.power / "BAT")
        self.tick("on")
        self.assertEqual(self.flag("saver"), "off")

    def test_power_settings_do_not_wait_for_upower_events(self):
        self.cli("quiet", "on")
        self.stub("upower", "sleep 60")
        proc = subprocess.Popen(["/bin/bash", "-c", 'source "$1"; watch_power',
                                 "test", str(self.watch)], env=self.env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                start_new_session=True)
        try:
            time.sleep(0.3)
            self.conf.write_text("LAPTOP_MODE=on\nFULLSCREEN_QUIET=no\n")
            deadline = time.monotonic() + 7
            while (self.flag("saver"), self.flag("quiet")) != ("on", "off") and time.monotonic() < deadline:
                time.sleep(0.1)
            self.assertEqual(self.flag("saver"), "on")
            self.assertEqual(self.flag("quiet"), "off")
            self.assert_effect()
        finally:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.communicate(timeout=3)


if __name__ == "__main__":
    unittest.main()
