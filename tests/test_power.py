import unittest

try:  # `unittest discover -s tests` and `unittest tests.test_x` both work
    from support import Sandbox
except ImportError:
    from tests.support import Sandbox

SAVER_CALLS = ("afterburn saver on", "afterburn saver off")


class PowerBase(unittest.TestCase):
    def make(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.use_stubs(["afterburn"])         # the watcher calls `afterburn saver ...`: record it
        return sb

    def tick(self, sb, saver=""):
        r = sb.watch_func(f'saver="{saver}"; power_tick')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return [c for c in sb.call_log() if c in SAVER_CALLS]


class WatcherTests(PowerBase):
    def test_desktop_with_only_a_mouse_battery_is_not_a_laptop(self):  # issues #3 and #4
        sb = self.make()
        sb.supply("hidpp_battery_0", "Battery", scope="Device", status="Discharging", capacity=15)
        self.assertEqual(self.tick(sb), [])

    def test_mouse_battery_with_no_mains_and_no_scope_file_but_device_scope_variants(self):
        sb = self.make()
        sb.supply("hidpp_battery_0", "Battery", scope="device", status="Discharging", capacity=5)
        sb.supply("hid-1234-battery", "Battery", scope="Device", status="Discharging", capacity=5)
        self.assertEqual(self.tick(sb), [])

    def test_real_battery_on_battery_turns_saver_on(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Discharging", capacity=70)
        sb.supply("AC", "Mains", online=0)
        self.assertEqual(self.tick(sb), ["afterburn saver on"])

    def test_real_battery_without_a_scope_file_still_counts(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", status="Discharging", capacity=70)
        sb.supply("AC", "Mains", online=0)
        self.assertEqual(self.tick(sb), ["afterburn saver on"])

    def test_real_battery_on_ac_turns_saver_off(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Charging", capacity=70)
        sb.supply("AC", "Mains", online=1)
        self.assertEqual(self.tick(sb, saver="on"), ["afterburn saver off"])

    def test_laptop_plus_mouse_follows_the_system_battery(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Charging", capacity=70)
        sb.supply("hidpp_battery_0", "Battery", scope="Device", status="Discharging", capacity=3)
        sb.supply("AC", "Mains", online=1)
        self.assertEqual(self.tick(sb), ["afterburn saver off"])

    def test_saver_left_on_by_the_old_bug_is_cleared_on_a_desktop(self):
        sb = self.make()
        sb.supply("hidpp_battery_0", "Battery", scope="Device", status="Discharging", capacity=15)
        sb.write_state_text(sb.state_dir / "saver", "on\n")
        self.assertEqual(self.tick(sb), ["afterburn saver off"])

    def test_a_later_manual_saver_on_stands_on_a_desktop(self):
        sb = self.make()
        sb.supply("hidpp_battery_0", "Battery", scope="Device", status="Discharging", capacity=15)
        body = (f'saver=""; power_tick; printf "on\\n" > "{sb.state_dir}/saver"; power_tick')
        sb.state_dir.mkdir(parents=True, exist_ok=True)
        (sb.state_dir / "saver").write_text("off\n")
        r = sb.watch_func(body)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual([c for c in sb.call_log() if c in SAVER_CALLS], [])

    def test_forced_laptop_mode_is_not_touched(self):
        sb = self.make()
        sb.write_state_text(sb.home / ".config/afterburn/afterburn.conf", "LAPTOP_MODE=on\n")
        sb.write_state_text(sb.state_dir / "saver", "on\n")
        self.assertEqual(self.tick(sb), [])

    def test_mains_without_an_online_file_is_not_ac(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Discharging", capacity=70)
        sb.supply("AC", "Mains")
        self.assertEqual(self.tick(sb), ["afterburn saver on"])

    def test_missing_files_are_quiet_and_count_as_empty(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", status="Discharging")
        (sb.sysfs / "odd").mkdir()                       # a supply folder with no type file
        (sb.home / ".local/state/omarchy/current/theme.name").unlink()
        r = sb.watch_func('is_afterburn && echo yes; ab_ps_kind "$POWER_DIR/odd"; '
                          'printf "[%s]" "$(ab_ps_attr "$POWER_DIR/BAT0" online)"; ab_on_ac || echo no-ac')
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "other\n[]no-ac\n", ""))

    def test_the_battery_is_asked_once_but_the_adapter_every_tick(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Charging", capacity=70)
        sb.supply("AC", "Mains", online=1)
        off_ac = f'printf "0\\n" > "{sb.sysfs}/AC/online"'
        r = sb.watch_func(f'saver=""; power_tick; ab_has_battery() {{ echo asked; return 1; }}; {off_ac}; power_tick')
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
        self.assertEqual([c for c in sb.call_log() if c in SAVER_CALLS], ["afterburn saver off", "afterburn saver on"])


class DiagnosticTests(PowerBase):
    def test_doctor_names_the_ignored_peripheral(self):
        sb = self.make()
        sb.supply("hidpp_battery_0", "Battery", scope="Device", status="Discharging", capacity=100)
        sb.write_state_text(sb.state_dir / "saver", "on\n")
        r = sb.afterburn("doctor", STUB_CONFIGERRORS="line one\nline two\n")
        out = r.stdout
        self.assertEqual(r.returncode, 0, out + r.stderr)
        for needle in ("afterburn", "hidpp_battery_0", "Device", "Discharging", "ignored", "active",
                       "cursor-fx", "ghostty", "config errors: 2"):
            self.assertIn(needle, out)
        self.assertNotIn("counted as laptop battery", out)

    def test_doctor_is_read_only(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Discharging", capacity=50)
        before = sorted(p for p in sb.home.rglob("*") if p.is_file())
        sb.afterburn("doctor")
        after = sorted(p for p in sb.home.rglob("*") if p.is_file())
        self.assertEqual(before, after)
        self.assertFalse(any(c.startswith(("afterburn saver", "cursor-fx")) for c in sb.call_log()))

    def test_status_says_which_supply_turned_saver_on(self):
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Discharging", capacity=50)
        sb.supply("AC", "Mains", online=0)
        sb.write_state_text(sb.state_dir / "saver", "on\n")
        r = sb.afterburn("status")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertRegex(r.stdout, r"saver:\s+on.*BAT0")

    def test_status_on_a_desktop_does_not_blame_the_mouse(self):
        sb = self.make()
        sb.supply("hidpp_battery_0", "Battery", scope="Device", status="Discharging", capacity=50)
        sb.write_state_text(sb.state_dir / "saver", "on\n")
        r = sb.afterburn("status")
        saver_line = [l for l in r.stdout.splitlines() if l.startswith("saver:")][0]
        self.assertIn("no system battery", saver_line)
        self.assertIn("afterburn saver off", saver_line)


if __name__ == "__main__":
    unittest.main()
