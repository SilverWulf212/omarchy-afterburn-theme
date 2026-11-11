"""Catch stale wordmark previews by comparing selector images to real wallpapers."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]
def dimensions(path):
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(path)]))
    image = info['streams'][0]
    return image['width'], image['height']
def pixels(path):
    return subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-vf',
        'scale=240:100:flags=lanczos,format=rgb24', '-frames:v', '1', '-threads', '1', '-f', 'rawvideo', '-'])
class SelectorPreviews(unittest.TestCase):
    def test_each_theme_preview_matches_its_actual_default_wallpaper(self):
        editions = sorted(p.parent.name for p in (ROOT/'tools/edition-extras').glob('*/edition.conf'))
        themes = [('afterburn', ROOT), *[(name, ROOT/'.editions'/name) for name in editions]]
        for name, theme in themes:
            with self.subTest(theme=name):
                preview, wallpaper = theme/'preview.png', theme/'backgrounds/1-horizon.jpg'
                width, height = dimensions(preview)
                source_width, source_height = dimensions(wallpaper)
                self.assertEqual(width, 1200)
                self.assertAlmostEqual(width/height, source_width/source_height, delta=.01)
                actual, expected = pixels(preview), pixels(wallpaper)
                error = (sum((a-b)**2 for a,b in zip(actual,expected))/len(actual))**.5
                self.assertLess(error, 3, 'selector shows unrelated artwork or branding')
    def test_refresh_existing_installs_backs_up_previews_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)/'themes'
            backups = Path(tmp)/'backups'
            original = (ROOT/'preview-unlock.png').read_bytes()
            for name in ('afterburn', 'afterburn-cyber'):
                theme = home/name
                (theme/'backgrounds').mkdir(parents=True)
                source = ROOT if name == 'afterburn' else ROOT/'.editions/cyber'
                shutil.copyfile(source/'backgrounds/1-horizon.jpg', theme/'backgrounds/1-horizon.jpg')
                (theme/'preview.png').write_bytes(original)
                (theme/'preview.png').chmod(0o640)
                (theme/'colors.toml').write_text('keep my colours')
            custom = home/'afterburn-voltage'
            (custom/'backgrounds').mkdir(parents=True)
            shutil.copyfile(ROOT/'backgrounds/1-horizon.jpg', custom/'backgrounds/1-horizon.jpg')
            target = Path(tmp)/'custom.png'
            target.write_bytes(original)
            (custom/'preview.png').symlink_to(target)
            command = ['python3', str(ROOT/'tools/wallpapers/selector-previews.py'), 'install',
                       '--themes-home', str(home), '--backup-root', str(backups)]
            output = subprocess.check_output(command, text=True)
            self.assertIn('Updated: afterburn-cyber', output)
            self.assertIn('Skipped (custom preview symlink): afterburn-voltage', output)
            self.assertEqual(target.read_bytes(), original)
            for name in ('afterburn', 'afterburn-cyber'):
                theme = home/name
                saved = list(backups.glob('*/'+name+'/preview.png'))
                self.assertEqual(len(saved), 1)
                self.assertEqual(saved[0].read_bytes(), original)
                self.assertEqual((theme/'colors.toml').read_text(), 'keep my colours')
                self.assertEqual((theme/'preview.png').stat().st_mode & 0o777, 0o640)
                a, b = pixels(theme/'preview.png'), pixels(theme/'backgrounds/1-horizon.jpg')
                error = (sum((x-y)**2 for x,y in zip(a,b))/len(a))**.5
                self.assertLess(error, 3)
            output = subprocess.check_output(command, text=True)
            self.assertIn('Already current: afterburn-cyber', output)
            self.assertEqual(len(list(backups.iterdir())), 1)
            # Exercise the installed native picker routing without opening UI.
            picker = Path('/usr/share/omarchy/bin/omarchy-theme-switcher')
            if picker.exists():
                fake_bin = Path(tmp)/'bin'
                fake_bin.mkdir()
                menu = fake_bin/'omarchy-menu-images'
                menu.write_text('#!/bin/bash\nprintf "%s\\n" "${@: -1}"\n')
                menu.chmod(0o755)
                user_home = Path(tmp)/'home'
                (user_home/'.config/omarchy').mkdir(parents=True)
                (user_home/'.config/omarchy/themes').symlink_to(home, target_is_directory=True)
                stock = Path(tmp)/'stock'
                (stock/'themes').mkdir(parents=True)
                env = dict(os.environ, HOME=str(user_home), OMARCHY_PATH=str(stock),
                           XDG_CACHE_HOME=str(Path(tmp)/'cache'), PATH=str(fake_bin)+os.pathsep+os.environ['PATH'])
                output = subprocess.check_output(['bash', str(picker), '--print-rows'], env=env, text=True)
                cache = Path(output.strip())
                for name in ('afterburn', 'afterburn-cyber'):
                    self.assertEqual((cache/(name+'.png')).resolve(), (home/name/'preview.png').resolve())
                print('PASS native selector resolves installed wallpaper previews (UI not opened)')
if __name__ == '__main__': unittest.main()
