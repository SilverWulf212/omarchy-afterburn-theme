"""Runtime contract: no desktop commands outside temporary HOME and restricted PATH."""
import concurrent.futures
import subprocess
import test_runtime_modes as modes


class Reliability(modes.RuntimeModes):
    def test_declined_cursor_effects_survive_modes_and_saved_effect_changes(self):
        self.conf.write_text("CURSOR_EFFECTS=no\n")
        self.ghostty.write_text("config-file = cursor-effects/neon.conf\n")
        self.cli('quiet', 'on')
        self.cli('saver', 'on')
        self.cli('set', 'CURSOR_FX', 'katana')
        self.cli('quiet', 'off')
        self.cli('saver', 'off')
        self.assert_effect('neon')
        self.cli('set', 'CURSOR_EFFECTS', 'yes')
        self.assert_effect('katana')
        self.cli('set', 'CURSOR_EFFECTS', 'no')
        self.assert_effect('neon')

    def test_declined_glow_is_not_reenabled_by_heat_changes(self):
        self.cli('set', 'GLOW', 'no')
        self.cli('level', 'hot')
        self.cli('apply')
        log = (self.home / 'hypr.log').read_text()
        enabled = [line for line in log.splitlines() if 'decoration:shadow:enabled' in line]
        self.assertTrue(enabled)
        self.assertTrue(all(line.endswith(' false') for line in enabled), enabled)
        self.cli('set', 'GLOW', 'yes')
        self.assertIn('decoration:shadow:enabled true', (self.home / 'hypr.log').read_text())

    def test_config_is_data_and_values_reset_between_reads(self):
        marker = self.home / "executed"
        self.conf.write_text(f'HEAT_SOURCE=$(echo unsafe > {marker})\nMOTION="off" # user choice\nEVENING_HOURS=99-99\nLAT=99\nLON=181\n')
        self.assertIn('HEAT_SOURCE=time', self.cli('get'))
        self.assertFalse(marker.exists())
        self.assertEqual(self.cli('get', 'MOTION').strip(), 'off')
        self.assertEqual(self.cli('get', 'EVENING_HOURS').strip(), '19-07')
        self.assertEqual(self.cli('get', 'LAT').strip(), '')
        self.assertEqual(self.cli('get', 'LON').strip(), '')

    def test_motion_preserves_independent_choices(self):
        self.cli('set', 'ROTATE', 'fast')
        self.cli('set', 'CURSOR_FX', 'neon')
        self.cli('set', 'MOTION', 'off')
        self.assertIn('# effect off', self.ghostty.read_text())
        self.assertEqual(self.cli('get', 'ROTATE').strip(), 'fast')
        self.cli('set', 'MOTION', 'on')
        self.assert_effect('neon')

    def test_apply_failure_is_reported_and_retried(self):
        self.stub('hyprctl', 'exit 17')
        result = subprocess.run(['/bin/bash', str(self.ab), 'apply'], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('last error:', self.cli('status'))
        self.assertIn('hyprctl', (self.state / 'last-error').read_text())
        self.stub('hyprctl', 'exit 0')
        self.cli('apply')
        self.assertFalse((self.state / 'last-error').exists())

    def test_concurrent_sets_do_not_lose_values(self):
        choices = [('ROTATE', 'fast'), ('DIM', '0.2'), ('GLOW_RANGE', '22'), ('MOTION', 'off')]
        with concurrent.futures.ThreadPoolExecutor() as pool:
            list(pool.map(lambda pair: self.cli('set', *pair), choices))
        for key, value in choices:
            self.assertEqual(self.cli('get', key).strip(), value)

    def test_watcher_does_not_execute_conf_and_reloads_defaults(self):
        marker = self.home / 'watch-executed'
        self.conf.write_text(f'LAPTOP_MODE=$(echo unsafe > {marker})\nFULLSCREEN_QUIET=no\n')
        result = subprocess.run(['/bin/bash', '-c', 'source "$1"; load_conf; echo "$FULLSCREEN_QUIET"; : > "$CONF"; load_conf; echo "$FULLSCREEN_QUIET"', 'test', str(self.watch)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(result.stdout, 'no\nyes\n')

    def test_spaces_quotes_and_final_invalid_assignment(self):
        self.conf.write_text(' ROTATE = "fast" # comment\nMOTION=off\nMOTION=invalid\nFAIL_FX=\'off\'')
        self.assertEqual(self.cli('get', 'ROTATE').strip(), 'fast')
        self.assertEqual(self.cli('get', 'MOTION').strip(), 'on')
        self.assertEqual(self.cli('get', 'FAIL_FX').strip(), 'off')

    def test_mutator_waits_for_shared_lock(self):
        import fcntl
        import time
        with (self.state / 'runtime.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            proc = subprocess.Popen(['/bin/bash', str(self.ab), 'set', 'DIM', '0.3'], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                time.sleep(0.15)
                self.assertIsNone(proc.poll())
                self.assertNotIn('DIM=0.3', self.conf.read_text())
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)
                out, err = proc.communicate(timeout=5)
            self.assertEqual(proc.returncode, 0, out + err)
        self.assertEqual(self.cli('get', 'DIM').strip(), '0.3')

    def test_hook_nested_apply_and_motion_restoration(self):
        hook = self.ab.parent.parent / 'afterburn-theme-set-hook'
        self.stub('systemctl', 'exit 0')
        self.cli('set', 'CURSOR_FX', 'neon')
        self.cli('set', 'MOTION', 'off')
        for theme in ('afterburn', 'afterburn'):
            result = subprocess.run(['/bin/bash', str(hook), theme], env=self.env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.cli('set', 'MOTION', 'on')
        self.assert_effect('neon')

    def test_failed_atomic_writer_keeps_original(self):
        helper = self.ab.parent.parent / 'afterburn-theme.sh'
        self.conf.write_text('MOTION=on\n')
        (self.bin / 'cat').unlink()
        self.stub('cat', 'exit 9')
        result = subprocess.run(['/bin/bash', '-c', 'source "$1"; printf bad | ab_atomic_write "$2"', 'test', str(helper), str(self.conf)], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.conf.read_text(), 'MOTION=on\n')

    def test_socket_rediscovery_matches_display(self):
        runtime = self.root / 'runtime'
        for signature in ('old', 'ours', 'other'):
            directory = runtime / 'hypr' / signature
            directory.mkdir(parents=True)
            # Actual socket creation is blocked by this execution sandbox. Replace
            # only the OS socket-type probe, retaining real selection/CLI behavior.
            (directory / '.socket2.sock').touch()
        self.stub('hyprctl', '''echo '[{"instance":"ours","wl_socket":"wayland-1"},{"instance":"other","wl_socket":"wayland-2"}]' ''')
        self.env.update(XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='stale', WAYLAND_DISPLAY='wayland-1')
        result = subprocess.run(['/bin/bash', '-c', 'source "$1"; ab_socket_exists() { [[ -e $1 ]]; }; fullscreen_socket', 'test', str(self.watch)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(runtime / 'hypr/ours/.socket2.sock'))
        self.env['WAYLAND_DISPLAY'] = 'wayland-missing'
        result = subprocess.run(['/bin/bash', '-c', 'source "$1"; ab_socket_exists() { [[ -e $1 ]]; }; fullscreen_socket', 'test', str(self.watch)], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_symlink_config_target_is_updated_atomically(self):
        target = self.home / 'dotfile.conf'
        self.conf.rename(target)
        self.conf.symlink_to(target)
        self.cli('set', 'ROTATE', 'fast')
        self.assertTrue(self.conf.is_symlink())
        self.assertIn('ROTATE=fast', target.read_text())
        self.cli('unset', 'ROTATE')
        self.assertTrue(self.conf.is_symlink())
        self.assertNotIn('ROTATE=fast', target.read_text())

    def test_first_cli_read_initializes_default_config(self):
        self.conf.unlink()
        self.assertEqual(self.cli('get', 'MOTION').strip(), 'on')
        self.assertTrue(self.conf.is_file())

    def test_lock_motion_all_styles_and_restoration(self):
        self.env['USER'] = 'tester'
        clone = self.home / '.config/omarchy/plugins/tester.lock'
        clone.mkdir(parents=True)
        (clone / 'manifest.json').write_text('{"omarchy":{"clonedFrom":"omarchy.lock"}}')
        (clone / '.afterburn-lock-embers').touch()
        (clone / 'EmberLayer.qml').write_text('initial')
        helper = self.ab.parent.parent / 'lock/lock-embers.sh'
        for cmd in ('find', 'sort', 'sha256sum', 'cmp', 'id', 'cp'):
            import shutil
            (self.bin / cmd).symlink_to(shutil.which(cmd))
        self.stub('omarchy-shell', 'exit 0')
        def inventory():
            result = subprocess.run(['/bin/bash', '-c', 'source "$1"; clone_inventory "$2" > "$2/.afterburn-inventory"', 'test', str(helper), str(clone)], env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        inventory()
        (self.state / 'lock-embers').touch()
        for style in ('rise', 'fall', 'drift', 'spark', 'pulse', 'burst'):
            self.cli('set', 'EMBER_STYLE', style)
            self.cli('set', 'MOTION', 'off')
            self.assertIn('readonly property bool active: false', (clone / 'EmberLayer.qml').read_text())
            self.cli('set', 'MOTION', 'on')
            layer = (clone / 'EmberLayer.qml').read_text()
            self.assertIn('readonly property bool active: root.visible', layer)
            self.assertEqual(self.cli('get', 'EMBER_STYLE').strip(), style)

    def test_motion_off_initial_theme_hook_restores_edition_choice(self):
        hook = self.ab.parent.parent / 'afterburn-theme-set-hook'
        self.stub('systemctl', 'exit 0')
        self.conf.write_text('MOTION=off\nCURSOR_FX=neon\n')
        result = subprocess.run(['/bin/bash', str(hook), 'afterburn'], env=self.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('# effect off', self.ghostty.read_text())
        self.cli('set', 'MOTION', 'on')
        self.assert_effect('neon')

    def test_no_motion_environment_overrides_saved_on(self):
        self.env['NO_MOTION'] = ''
        self.cli('apply')
        self.assertIn('# effect off', self.ghostty.read_text())
        lua = (self.home / '.local/state/omarchy/current/theme/hyprland.lua').read_text()
        self.assertIn('leaf = "borderangle", enabled = false', lua)
        self.assertEqual(self.cli('get', 'MOTION').strip(), 'on')

    def test_reconnect_rediscovers_socket_and_resyncs_quiet(self):
        import os
        import shutil
        import signal
        import time
        (self.bin / 'real-sleep').symlink_to(shutil.which('sleep'))
        (self.bin / 'sleep').unlink()
        self.stub('sleep', 'real-sleep 0.05')
        self.stub('hyprctl', 'if [[ $1 == activewindow ]]; then echo \'{"fullscreen":1}\'; fi')
        self.stub('socat', '''echo "$*" >> "$HOME/connections"
echo 'N starting data transfer loop with FDs' >&2
real-sleep 0.15''')
        choice = self.home / 'socket-choice'
        choice.write_text('/first/.socket2.sock\n')
        proc = subprocess.Popen(['/bin/bash', '-c', 'source "$1"; fullscreen_socket() { cat "$HOME/socket-choice"; }; watch_fullscreen', 'test', str(self.watch)], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
        def wait_until(predicate):
            deadline = time.monotonic() + 5
            while not predicate() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(predicate())
        try:
            wait_until(lambda: self.flag('quiet') == 'on')
            self.cli('quiet', 'off')
            choice.write_text('/second/.socket2.sock\n')
            wait_until(lambda: '/second/' in (self.home / 'connections').read_text() and self.flag('quiet') == 'on')
            wait_until(lambda: (self.state / 'fullscreen-socket').exists())
        finally:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.communicate(timeout=3)

    def test_cursor_failure_is_nonzero_and_same_intent_retries(self):
        self.stub('cursor-fx', 'exit 13')
        for _ in range(2):
            result = subprocess.run(['/bin/bash', str(self.ab), 'quiet', 'on'], env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 13, result.stdout + result.stderr)
            self.assertIn('cursor-fx', (self.state / 'last-error').read_text())

    def test_bad_weather_response_keeps_last_good_observation(self):
        self.stub('curl', 'echo invalid')
        (self.bin / 'jq').unlink()
        self.stub('jq', 'if [[ $1 == -n ]]; then exit 2; else echo station; fi')
        weather = self.state / 'weather.json'
        weather.write_text('{"checked":1,"tempF":60}\n')
        result = subprocess.run(['/bin/bash', '-c', 'source "$1"; load_conf; fetch_weather', 'test', str(self.watch)], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(weather.read_text(), '{"checked":1,"tempF":60}\n')
        self.assertTrue((self.state / 'weather-error').exists())

    def test_noop_preserves_failed_application_and_same_state_retry(self):
        self.stub('hyprctl', 'exit 17')
        def quiet():
            return subprocess.run(['/bin/bash', str(self.ab), 'quiet', 'on'], env=self.env, capture_output=True, text=True)
        self.assertEqual(quiet().returncode, 17)
        self.cli('level', 'cool')  # quiet suppresses live keywords; this only saves intent
        self.cli('get', 'MOTION')
        self.assertTrue((self.state / 'last-error').exists())
        self.assertEqual(quiet().returncode, 17)

    def test_locate_resets_weather_retry_only_after_success(self):
        for name in ('weather.json', 'weather-attempt', 'weather-error'):
            (self.state / name).write_text('prior-data')
        self.stub('curl', 'exit 22')
        result = subprocess.run(['/bin/bash', str(self.ab), 'locate', '76000'], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        for name in ('weather.json', 'weather-attempt', 'weather-error'):
            self.assertEqual((self.state / name).read_text(), 'prior-data')
        self.stub('curl', '''echo '{"places":[{"latitude":"32","longitude":"-97"}]}' ''')
        self.cli('locate', '76000')
        for name in ('weather.json', 'weather-attempt', 'weather-error'):
            self.assertFalse((self.state / name).exists())

    def test_palette_menu_does_not_hold_mutation_lock(self):
        import os
        import signal
        import time
        os.mkfifo(self.home / 'menu-close')
        # A real wait keeps the menu open until cleanup without depending on a
        # sleep binary's argv[0] handling or a fixed timeout on slower CI hosts.
        self.stub('omarchy-menu-select', 'echo ready > "$HOME/menu-open"; read -r token < "$HOME/menu-close"; exit 1')
        proc = subprocess.Popen(['/bin/bash', str(self.ab), 'colors', '--menu'], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline = time.monotonic() + 3
            while not (self.home / 'menu-open').exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.home / 'menu-open').exists())
            started = time.monotonic()
            self.cli('quiet', 'on')
            self.assertLess(time.monotonic() - started, 2)
            self.assertIsNone(proc.poll())
        finally:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            proc.communicate(timeout=3)
