"""Watcher survives Hyprland reloads and restarts: configreloaded re-applies the heat level, a dead instance's
leftover socket is skipped, and the chosen signature reaches the `afterburn` calls the loops make."""
import os
import shutil
import unittest

try:
    from support import REPO, Sandbox
except ImportError:
    from tests.support import REPO, Sandbox


def instance(run, name, mtime, alive):
    """A Hyprland instance folder. Both kinds keep a .socket2.sock; only a live one has a lock with a live pid."""
    d = run / "hypr" / name
    d.mkdir(parents=True)
    (d / ".socket2.sock").touch()
    if alive is not None:
        (d / "hyprland.lock").write_text(f"{alive}\nwayland-1\n")
    os.utime(d, (mtime, mtime))
    return d


class ReloadEventTests(unittest.TestCase):
    def reload(self, level=None, quiet=None, saver=None, theme="afterburn", event="configreloaded>>"):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.use_stubs(["afterburn"])
        sb.write_state_text(sb.home / ".local/state/omarchy/current/theme.name", theme)
        for name, val in (("level", level), ("quiet", quiet), ("saver", saver)):
            if val:
                sb.write_state_text(sb.state_dir / name, val + "\n")
        r = sb.watch_func(f"fullscreen_event '{event}'")
        self.assertEqual(r.returncode, 0, r.stderr)
        return sb.call_log()

    def test_a_reload_puts_the_saved_level_back(self):
        self.assertEqual(self.reload("hot"), ["afterburn level hot"])
        self.assertEqual(self.reload("cool"), ["afterburn level cool"])

    def test_the_event_carries_no_data_but_a_suffix_still_counts(self):
        self.assertEqual(self.reload("hot", event="configreloaded>>1"), ["afterburn level hot"])

    def test_a_reload_at_normal_needs_nothing_because_the_file_holds_normal(self):
        self.assertEqual(self.reload("normal"), [])
        self.assertEqual(self.reload(None), [])

    def test_quiet_or_saver_keeps_the_glow_still(self):
        self.assertEqual(self.reload("hot", quiet="on"), [])
        self.assertEqual(self.reload("hot", saver="on"), [])
        self.assertEqual(self.reload("hot", quiet="off", saver="off"), ["afterburn level hot"])

    def test_another_theme_is_left_alone(self):
        self.assertEqual(self.reload("hot", theme="nord"), [])

    def test_unrelated_events_still_cost_nothing(self):
        for ev in ("activewindow>>kitty,~", "workspace>>2", "configreloaded", "windowtitle>>configreloaded>>"):
            with self.subTest(ev=ev):
                self.assertEqual(self.reload("hot", event=ev), [])

    def test_the_level_push_itself_does_not_reload(self):
        # afterburn's own reload emits configreloaded too; the call the watcher makes in answer must not reload again.
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        (sb.home / ".local/state/omarchy/current/theme").mkdir(parents=True)
        sb.write_state_text(sb.state_dir / "level", "hot\n")
        r = sb.afterburn("level", "hot")
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = [c for c in sb.call_log() if c.startswith("hyprctl")]
        self.assertEqual(len(calls), 1, calls)
        self.assertTrue(calls[0].startswith("hyprctl eval"), calls)


class HyprPickTests(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        self.run_dir = self.sb.root / "run"
        self.me = os.getpid()    # a pid that is alive for as long as the test runs

    def pick(self, body="hypr_pick", sig=None):
        extra = {"XDG_RUNTIME_DIR": str(self.run_dir)}
        if sig is not None:
            extra["HYPRLAND_INSTANCE_SIGNATURE"] = sig
        r = self.sb.watch_func(body, **extra)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.split()

    def test_a_dead_instance_with_a_leftover_socket_is_skipped(self):  # E2E I1
        instance(self.run_dir, "dead-new", 3000, None)           # newest, socket left behind, no lock
        instance(self.run_dir, "crashed", 2500, 2 ** 22 + 99)    # lock left behind, its pid gone
        instance(self.run_dir, "live", 2000, self.me)
        for sig in (None, "dead-new", "gone"):
            with self.subTest(env=sig):
                self.assertEqual(self.pick('hypr_pick; echo "$HYPRLAND_INSTANCE_SIGNATURE"', sig), ["live"])

    def test_the_env_instance_stays_when_it_is_alive(self):
        instance(self.run_dir, "old", 1000, self.me)
        instance(self.run_dir, "new", 2000, self.me)
        self.assertEqual(self.pick('hypr_pick; echo "$HYPRLAND_INSTANCE_SIGNATURE"', "old"), ["old"])

    def test_the_newest_live_one_wins_without_an_env_one(self):
        instance(self.run_dir, "old", 1000, self.me)
        instance(self.run_dir, "new", 2000, self.me)
        self.assertEqual(self.pick('hypr_pick; echo "$HYPRLAND_INSTANCE_SIGNATURE"'), ["new"])

    def test_nothing_alive_falls_back_to_the_newest_and_says_so(self):
        instance(self.run_dir, "old", 1000, None)
        instance(self.run_dir, "new", 2000, None)
        self.assertEqual(self.pick('hypr_pick; echo "rc=$? $HYPRLAND_INSTANCE_SIGNATURE"'), ["rc=1", "new"])

    def test_child_processes_get_the_chosen_signature(self):  # E2E I2
        instance(self.run_dir, "live", 2000, self.me)
        self.assertEqual(self.pick("hypr_pick; env | grep ^HYPRLAND_INSTANCE_SIGNATURE=", "dead"),
                         ["HYPRLAND_INSTANCE_SIGNATURE=live"])

    def test_the_socket_path_follows_the_pick(self):
        instance(self.run_dir, "live", 2000, self.me)
        self.assertEqual(self.pick("hypr_pick; hypr_socket", "dead"), [f"{self.run_dir}/hypr/live/.socket2.sock"])


class SignatureReachesCallsTests(unittest.TestCase):
    """The power and heat loops run in their own processes: each must pick the live signature before it calls afterburn."""

    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        (self.sb.bin / "afterburn").write_text('#!/bin/bash\necho "afterburn $* sig=$HYPRLAND_INSTANCE_SIGNATURE" >> "$SB/calls.log"\n')
        (self.sb.bin / "afterburn").chmod(0o755)
        self.run_dir = self.sb.root / "run"
        instance(self.run_dir, "dead", 3000, None)
        instance(self.run_dir, "live", 2000, os.getpid())
        self.env = {"XDG_RUNTIME_DIR": str(self.run_dir), "HYPRLAND_INSTANCE_SIGNATURE": "dead"}

    def test_the_saver_call(self):
        self.sb.supply("BAT0", "Battery", scope="System", status="Discharging", capacity=70)
        self.sb.supply("AC", "Mains", online=0)
        r = self.sb.watch_func('saver=""; power_tick', **self.env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.sb.call_log(), ["afterburn saver on sig=live"])

    def test_the_heat_call(self):
        conf = self.sb.home / ".config/afterburn/afterburn.conf"
        conf.parent.mkdir(parents=True)
        conf.write_text("HEAT_SOURCE=time\nEVENING_HOURS=10-14\n")
        date = self.sb.bin / "date"           # the hour is fixed at 12: inside 10-14, whatever the clock says
        date.unlink()
        date.write_text('#!/bin/bash\n[[ $1 == +%H ]] && echo 12 || exec ' + shutil.which("date") + ' "$@"\n')
        date.chmod(0o755)
        r = self.sb.watch_func("sleep() { exit 0; }; watch_heat", **self.env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.sb.call_log(), ["afterburn level cool sig=live"])


class ReconnectTests(unittest.TestCase):
    def test_the_fullscreen_state_is_read_again_after_a_reconnect(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.use_stubs(["afterburn"])
        (sb.bin / "socat").write_text("#!/bin/bash\nexit 1\n")     # connects to nothing: the loop goes round
        (sb.bin / "socat").chmod(0o755)
        run = sb.root / "run"
        instance(run, "live", 2000, os.getpid())
        r = sb.watch_func("n=0; sleep() { n=$((n+1)); (( n < 3 )) || exit 0; }; watch_fullscreen", XDG_RUNTIME_DIR=str(run))
        self.assertEqual(r.returncode, 0, r.stderr)
        # main() reads it once at start; after that, once per reconnect (2 sleeps = 2 reconnects before the exit).
        self.assertEqual([c for c in sb.call_log() if c.startswith("hyprctl activewindow")], ["hyprctl activewindow -j"] * 2)


    def reconnects(self, level):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.use_stubs(["afterburn"])
        sb.write_state_text(sb.state_dir / "level", level + "\n")
        (sb.bin / "socat").write_text("#!/bin/bash\nexit 1\n")
        (sb.bin / "socat").chmod(0o755)
        run = sb.root / "run"
        instance(run, "live", 2000, os.getpid())
        r = sb.watch_func("n=0; sleep() { n=$((n+1)); (( n < 3 )) || exit 0; }; watch_fullscreen", XDG_RUNTIME_DIR=str(run))
        self.assertEqual(r.returncode, 0, r.stderr)
        return [c for c in sb.call_log() if c.startswith("afterburn level")]

    def test_the_heat_level_is_put_back_after_a_reconnect(self):
        # A restarted Hyprland loads the generated Lua (normal level) and sends no configreloaded for it.
        self.assertEqual(self.reconnects("hot"), ["afterburn level hot"] * 2)
        self.assertEqual(self.reconnects("normal"), [])


class UnitTests(unittest.TestCase):
    def test_the_user_unit_is_part_of_the_graphical_session(self):  # codex #11
        text = (REPO / "extras" / "afterburn-watch.service").read_text()
        unit = text.split("[Service]")[0]
        self.assertIn("PartOf=graphical-session.target", unit.splitlines())


if __name__ == "__main__":
    unittest.main()
