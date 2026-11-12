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
        sb.write_state_text(sb.state_dir / "quiet", "on\n")   # the stub does not write it; `quiet off` is only called while on
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

    def quiet_case(self, conf_text, event, quiet_state):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.use_stubs(["afterburn"])
        conf = sb.home / ".config" / "afterburn" / "afterburn.conf"
        conf.parent.mkdir(parents=True)
        conf.write_text(conf_text)
        if quiet_state:
            sb.write_state_text(sb.state_dir / "quiet", quiet_state + "\n")
        r = sb.watch_func(f"fullscreen_event '{event}'")
        self.assertEqual(r.returncode, 0, r.stderr)
        return sb.call_log()

    def test_fullscreen_quiet_off_in_conf_does_not_enter_quiet(self):
        self.assertEqual(self.quiet_case("FULLSCREEN_QUIET=no\n", "fullscreen>>1", ""), [])

    def test_leaving_fullscreen_clears_quiet_even_if_the_setting_is_now_no(self):  # bug 4
        self.assertEqual(self.quiet_case("FULLSCREEN_QUIET=no\n", "fullscreen>>0", "on"), ["afterburn quiet off"])

    def test_leaving_fullscreen_with_quiet_already_off_calls_nothing(self):
        self.assertEqual(self.quiet_case("FULLSCREEN_QUIET=no\n", "fullscreen>>0", "off"), [])
        self.assertEqual(self.quiet_case("FULLSCREEN_QUIET=no\n", "fullscreen>>0", ""), [])


def two_monitors(fs_a=0, fs_b=0, ws_b=2):
    """Two monitors showing workspaces 1 and 2, one window on each (and one on hidden workspace 3)."""
    mons = [{"name": "A", "activeWorkspace": {"id": 1}}, {"name": "B", "activeWorkspace": {"id": 2}}]
    cls = [{"workspace": {"id": 1}, "fullscreen": fs_a}, {"workspace": {"id": ws_b}, "fullscreen": fs_b}]
    return {"STUB_MONITORS": json.dumps(mons), "STUB_CLIENTS": json.dumps(cls)}


class ScreenFullscreenTests(unittest.TestCase):
    """Quiet follows the screen: any fullscreen window on a visible workspace, not the last event (#12)."""
    def run_watch(self, body, quiet_state, env, conf_text=""):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.use_stubs(["afterburn"])
        if conf_text:
            conf = sb.home / ".config" / "afterburn" / "afterburn.conf"
            conf.parent.mkdir(parents=True)
            conf.write_text(conf_text)
        if quiet_state:
            sb.write_state_text(sb.state_dir / "quiet", quiet_state + "\n")
        r = sb.watch_func(body, **env)
        self.assertEqual(r.returncode, 0, r.stderr)
        return [c for c in sb.call_log() if not c.startswith("hyprctl")]

    def test_leaving_fullscreen_on_one_monitor_keeps_quiet_while_the_other_is_fullscreen(self):
        self.assertEqual(self.run_watch("fullscreen_event 'fullscreen>>0'", "on", two_monitors(fs_b=1)), [])

    def test_leaving_fullscreen_with_none_left_clears_quiet(self):
        self.assertEqual(self.run_watch("fullscreen_event 'fullscreen>>0'", "on", two_monitors()),
                         ["afterburn quiet off"])

    def test_a_fullscreen_window_on_a_hidden_workspace_does_not_hold_quiet(self):
        self.assertEqual(self.run_watch("fullscreen_event 'fullscreen>>0'", "on", two_monitors(fs_b=1, ws_b=3)),
                         ["afterburn quiet off"])

    def test_leaving_fullscreen_clears_quiet_when_the_setting_is_no_even_if_another_is_fullscreen(self):
        self.assertEqual(self.run_watch("fullscreen_event 'fullscreen>>0'", "on", two_monitors(fs_b=1),
                                        "FULLSCREEN_QUIET=no\n"), ["afterburn quiet off"])

    def test_startup_with_a_fullscreen_window_on_an_unfocused_monitor_turns_quiet_on(self):
        self.assertEqual(self.run_watch("sync_quiet", "", two_monitors(fs_b=1)), ["afterburn quiet on"])

    def test_startup_with_nothing_fullscreen_turns_quiet_off(self):
        self.assertEqual(self.run_watch("sync_quiet", "", two_monitors()), ["afterburn quiet off"])

    def test_startup_with_the_setting_no_never_turns_quiet_on(self):
        self.assertEqual(self.run_watch("sync_quiet", "", two_monitors(fs_b=1), "FULLSCREEN_QUIET=no\n"),
                         ["afterburn quiet off"])


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
                            ({"tempF": 40}, "cool"),
                            ({"tempF": 95, "text": 5}, "hot")):           # a text that is not a string: no text
            with self.subTest(cache=cache):
                self.sb.calls.write_text("")
                self.assertEqual(self.level(60, **cache), ([want, "rc=0"], 1))

    def test_no_temperature_or_a_failed_refresh_means_no_change(self):
        self.assertEqual(self.level(60, text="Sunny")[0], ["rc=1"])
        self.assertEqual(self.level(3600, tempF=95, text="Sunny")[0], ["rc=1"])   # stale; the refresh fails


if __name__ == "__main__":
    unittest.main()
