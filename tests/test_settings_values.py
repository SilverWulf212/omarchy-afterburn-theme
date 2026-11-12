"""`afterburn set` edge cases: LAPTOP_MODE goes through `laptop`, hours and coordinates stay in range."""
import unittest

try:
    from support import Sandbox
except ImportError:
    from tests.support import Sandbox


class SetTests(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        (self.sb.home / ".local/state/omarchy/current/theme").mkdir(parents=True)

    def conf(self):
        return (self.sb.home / ".config/afterburn/afterburn.conf").read_text()

    def set(self, key, value):
        return self.sb.afterburn("set", key, value)

    def test_set_laptop_mode_does_what_laptop_does(self):  # codex #9
        for mode, saver in (("on", "on"), ("off", "off")):
            with self.subTest(mode=mode):
                r = self.set("LAPTOP_MODE", mode)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn(f"LAPTOP_MODE={mode}", self.conf())
                self.assertEqual((self.sb.state_dir / "saver").read_text().strip(), saver)

    def test_set_laptop_mode_auto_follows_the_power_source(self):
        self.sb.supply("BAT0", "Battery", scope="System", status="Discharging", capacity=70)
        self.sb.supply("AC", "Mains", online=0)
        self.assertEqual(self.set("LAPTOP_MODE", "auto").returncode, 0)
        self.assertEqual((self.sb.state_dir / "saver").read_text().strip(), "on")

    def test_set_laptop_mode_still_rejects_a_bad_value(self):
        r = self.set("LAPTOP_MODE", "maybe")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("bad value for LAPTOP_MODE", r.stderr)

    def test_evening_hours_must_be_hours(self):  # E2E M1
        for v in ("0-23", "00-00", "19-07", "7-9", "23-0"):
            with self.subTest(ok=v):
                self.assertEqual(self.set("EVENING_HOURS", v).returncode, 0)
                self.assertIn(f"EVENING_HOURS={v}", self.conf())
        for v in ("24-07", "19-24", "25-99", "7-", "-7", "7-9-1"):
            with self.subTest(bad=v):
                r = self.set("EVENING_HOURS", v)
                self.assertNotEqual(r.returncode, 0)
                self.assertIn("bad value for EVENING_HOURS", r.stderr)

    def test_latitude_and_longitude_stay_on_the_globe(self):  # E2E M2
        for key, good, bad in (("LAT", ("90", "-90", "89.9999", "0", "33.5", ""), ("90.1", "-90.5", "95.0", "99")),
                               ("LON", ("180", "-180", "-179.5", "0", "118.25", ""), ("180.1", "-181", "999", "-180.01"))):
            for v in good:
                with self.subTest(key=key, ok=v):
                    self.assertEqual(self.set(key, v).returncode, 0, v)
            for v in bad:
                with self.subTest(key=key, bad=v):
                    r = self.set(key, v)
                    self.assertNotEqual(r.returncode, 0)
                    self.assertIn(f"bad value for {key}", r.stderr)

    def test_a_hand_edited_out_of_range_value_falls_back(self):
        self.sb.write_state_text(self.sb.home / ".config/afterburn/afterburn.conf", "EVENING_HOURS=25-99\nLAT=95\nLON=-181\n")
        r = self.sb.afterburn("get")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("EVENING_HOURS=19-07", r.stdout)
        self.assertIn("LAT=\n", r.stdout)
        self.assertIn("LON=\n", r.stdout)


if __name__ == "__main__":
    unittest.main()
