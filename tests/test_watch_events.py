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


if __name__ == "__main__":
    unittest.main()
