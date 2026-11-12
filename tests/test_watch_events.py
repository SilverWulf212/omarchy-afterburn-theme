import json
import shutil
import time
import unittest

from support import Sandbox


class FullscreenEventTests(unittest.TestCase):
    def test_only_fullscreen_events_reach_the_expensive_path(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.use_stubs(["afterburn"])
        # Count load_conf calls with an in-shell counter (no fork needed to count).
        body = '''
            n=0; load_conf() { n=$((n+1)); FULLSCREEN_QUIET=yes; }; is_afterburn() { return 0; }
            for l in 'activewindow>>kitty,~' 'focusedmon>>eDP-1,1' 'workspace>>2' 'windowtitle>>0xabc' \\
                     'fullscreen>>1' 'openwindow>>x' 'fullscreen>>0' 'fullscreen>>x'; do
              fullscreen_event "$l"
            done
            echo "load_conf_calls=$n"
        '''
        r = sb.watch_func(body)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("load_conf_calls=2", r.stdout)
        self.assertEqual([c for c in sb.call_log() if c.startswith("afterburn")],
                         ["afterburn quiet on", "afterburn quiet off"])

    def test_fullscreen_quiet_off_in_conf_does_nothing(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.use_stubs(["afterburn"])
        conf = sb.home / ".config" / "afterburn" / "afterburn.conf"
        conf.parent.mkdir(parents=True)
        conf.write_text("FULLSCREEN_QUIET=no\n")
        r = sb.watch_func("fullscreen_event 'fullscreen>>1'")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sb.call_log(), [])


class WeatherTests(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        jq = self.sb.bin / "jq"
        jq.unlink()                                  # a symlink to the real jq: count the calls instead
        jq.write_text(f'#!/bin/bash\necho jq >> "$SB/calls.log"\nexec {shutil.which("jq")} "$@"\n')
        jq.chmod(0o755)

    def level(self, age, **cache):
        cache["checked"] = int(time.time()) - age
        self.sb.write_state_text(self.sb.state_dir / "weather.json", json.dumps(cache))
        r = self.sb.watch_func("curl() { return 1; }; HOT_F=90 COOL_F=50 LAT=1 LON=2; weather_level; echo rc=$?")
        return r.stdout.split(), self.sb.call_log().count("jq")

    def test_a_cached_sample_is_one_jq_and_the_same_rules(self):
        for cache, want in (({"tempF": 95, "text": "Sunny", "night": False}, "hot"),
                            ({"tempF": 95, "text": "Sunny", "night": True}, "normal"),
                            ({"tempF": 70, "text": "Light Rain | Fog", "night": False}, "cool"),
                            ({"tempF": 40}, "cool")):
            with self.subTest(cache=cache):
                self.sb.calls.write_text("")
                self.assertEqual(self.level(60, **cache), ([want, "rc=0"], 1))

    def test_no_temperature_or_a_failed_refresh_means_no_change(self):
        self.assertEqual(self.level(60, text="Sunny")[0], ["rc=1"])
        self.assertEqual(self.level(3600, tempF=95, text="Sunny")[0], ["rc=1"])   # stale; the refresh fails


if __name__ == "__main__":
    unittest.main()
