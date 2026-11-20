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


class ProfileTests(PowerBase):
    """With power-profiles-daemon the saver follows the power-saver profile, not the power source."""
    def laptop(self, profile, ac_online):
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Discharging", capacity=70)
        sb.supply("AC", "Mains", online=ac_online)
        (sb.root / "profile").write_text(profile + "\n")
        return sb

    def test_power_saver_on_ac_turns_saver_on(self):
        self.assertEqual(self.tick(self.laptop("power-saver", 1)), ["afterburn saver on"])

    def test_balanced_on_battery_keeps_the_animation(self):
        self.assertEqual(self.tick(self.laptop("balanced", 0), saver="on"), ["afterburn saver off"])

    def test_performance_on_battery_keeps_the_animation(self):
        self.assertEqual(self.tick(self.laptop("performance", 0)), ["afterburn saver off"])

    def test_desktop_in_power_saver_is_still_not_a_laptop(self):
        sb = self.make()
        sb.supply("hidpp_battery_0", "Battery", scope="Device", status="Discharging", capacity=15)
        (sb.root / "profile").write_text("power-saver\n")
        self.assertEqual(self.tick(sb), [])

    def test_status_names_the_profile(self):
        sb = self.laptop("power-saver", 1)
        sb.write_state_text(sb.state_dir / "saver", "on\n")
        r = sb.afterburn("status")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertRegex(r.stdout, r"saver:\s+on.*power profile is power-saver")

    def test_laptop_auto_follows_the_profile(self):
        sb = self.laptop("balanced", 0)
        (sb.home / ".local/state/omarchy/current/theme").mkdir(parents=True)
        for mode in ("on", "auto"):   # on battery with saver on, then auto: balanced turns it off
            r = sb.afterburn("laptop", mode)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual((sb.state_dir / "saver").read_text().strip(), "off")


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

    def test_a_non_auto_period_clears_the_cache_so_auto_applies_again(self):  # bug 3b
        sb = self.make()
        sb.supply("BAT0", "Battery", scope="System", status="Charging", capacity=70)
        sb.supply("AC", "Mains", online=1)
        conf = sb.home / ".config/afterburn/afterburn.conf"
        sb.write_state_text(conf, "LAPTOP_MODE=on\n")
        body = f'saver=off; power_tick; printf "LAPTOP_MODE=auto\\n" > "{conf}"; power_tick'
        r = sb.watch_func(body)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual([c for c in sb.call_log() if c in SAVER_CALLS], ["afterburn saver off"])


class LaptopAutoTests(PowerBase):
    """`afterburn laptop auto` puts saver in line with the power source at once (bug 3a)."""

    def saver_after(self, sb, first, ac_online):
        sb.supply("BAT0", "Battery", scope="System", status="Discharging", capacity=70)
        sb.supply("AC", "Mains", online=ac_online)
        (sb.home / ".local/state/omarchy/current/theme").mkdir(parents=True)
        for args in (("laptop", first), ("laptop", "auto")):
            r = sb.afterburn(*args)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return (sb.state_dir / "saver").read_text().strip()

    def test_laptop_on_then_auto_on_ac_turns_saver_off(self):
        self.assertEqual(self.saver_after(self.make(), "on", 1), "off")

    def test_laptop_off_then_auto_on_battery_turns_saver_on(self):
        self.assertEqual(self.saver_after(self.make(), "off", 0), "on")


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



class SaverPolicyAndSerialising(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        (self.sb.home / ".local/state/omarchy/current/theme").mkdir(parents=True)

    def test_laptop_on_survives_a_theme_round_trip(self):  # Codex review C8
        r = self.sb.afterburn("laptop", "on")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        (self.sb.state_dir / "saver").unlink()          # leaving Afterburn drops the flag
        r = self.sb.afterburn("apply")                  # coming back
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual((self.sb.state_dir / "saver").read_text().strip(), "on")

    def test_commands_that_change_things_wait_for_each_other(self):  # Codex review C4
        import fcntl
        self.sb.state_dir.mkdir(parents=True, exist_ok=True)
        lck = open(self.sb.state_dir / "afterburn.lck", "w")
        self.addCleanup(lck.close)
        fcntl.flock(lck, fcntl.LOCK_EX)
        r = self.sb.afterburn("quiet", "on", AFTERBURN_LOCK_WAIT="1")
        self.assertNotEqual(r.returncode, 0, r.stdout)
        self.assertIn("try again", r.stderr)
        self.assertFalse((self.sb.state_dir / "quiet").exists())
        fcntl.flock(lck, fcntl.LOCK_UN)
        r = self.sb.afterburn("status")                 # reading never waits
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
