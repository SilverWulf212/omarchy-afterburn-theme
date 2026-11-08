"""Executable artifact contracts: no desktop access or external packages."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / 'tools/release-packs.py'

class ReleasePacks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        for name, body in {'colors.toml': 'accent = "#abcdef"', 'LICENSE': 'license', 'extras/bin/afterburn': '#!/bin/sh\n', 'backgrounds/still.jpg': 'still', 'backgrounds/live.mp4': 'movie', '.editions/cyber/colors.toml': 'cyber', '.editions/cyber/backgrounds/live.mp4': 'cyber movie'}.items():
            f = self.source / name
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(body)
        (self.source / 'extras/bin/afterburn').chmod(0o755)

    def run_tool(self, *args, success=True):
        p = subprocess.run([sys.executable, str(TOOL), *map(str, args)], text=True, capture_output=True)
        self.assertEqual(p.returncode == 0, success, p.stderr)
        return p

    def build(self, out='packs'):
        path = self.root / out
        self.run_tool('build', '--source', self.source, '--output', path, '--version', 'v1.2.3')
        return path

    def install(self, packs, name='base', success=True):
        self.run_tool('install', '--manifest', packs / 'release.json', '--pack', packs / f'afterburn-v1.2.3-{name}.tar.gz', '--destination', self.root / 'stage', success=success)

    def test_deterministic_selective_packs_and_executable_mode(self):
        first, second = self.build(), self.build('second')
        self.assertEqual({f.name: f.read_bytes() for f in first.iterdir()}, {f.name: f.read_bytes() for f in second.iterdir()})
        self.install(first)
        dest = self.root / 'stage'
        self.assertTrue((dest / 'colors.toml').exists())
        self.assertFalse((dest / 'backgrounds/live.mp4').exists())
        self.assertFalse((dest / '.editions').exists())
        self.assertEqual((dest / 'extras/bin/afterburn').stat().st_mode & 0o777, 0o755)
        self.install(first, 'edition-cyber')
        self.assertEqual((dest / '.editions/cyber/backgrounds/live.mp4').read_text(), 'cyber movie')
        self.install(first, 'base-live')
        self.assertTrue((dest / 'backgrounds/live.mp4').exists())
        self.install(first)  # identical reinstallation is safe

    def test_standalone_bootstrap_is_checksummed_and_installs_without_checkout(self):
        packs = self.build()
        helper = packs / 'afterburn-pack-tool.py'
        self.assertTrue(helper.exists())
        manifest = json.loads((packs / 'release.json').read_text())
        self.assertEqual(manifest['bootstrap']['sha256'], hashlib.sha256(helper.read_bytes()).hexdigest())
        self.assertIn('  afterburn-pack-tool.py\n', (packs / 'SHA256SUMS').read_text())
        p = subprocess.run([sys.executable, str(helper), 'install', '--manifest', str(packs / 'release.json'), '--pack', str(packs / 'afterburn-v1.2.3-base.tar.gz'), '--destination', str(self.root / 'standalone')], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue((self.root / 'standalone/colors.toml').exists())

    def test_bundle_installer_stages_base_and_editions_then_runs_extras(self):
        import os
        installer = self.source / 'extras/install.sh'
        installer.write_text('#!/bin/sh\nprintf "%s" "$*" > "$HOME/activated"\n')
        installer.chmod(0o755)
        packs = self.build()
        script = packs / 'install-afterburn.sh'
        self.assertTrue(script.exists())
        home = self.root / 'home'
        home.mkdir()
        result = subprocess.run(['bash', str(script), '--yes'],
                                env={**os.environ, 'HOME': str(home)}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        target = home / '.config/omarchy/themes/afterburn'
        self.assertTrue((target / 'colors.toml').exists())
        self.assertTrue((target / '.editions/cyber/colors.toml').exists())
        self.assertEqual((home / 'activated').read_text(), '--yes')
        # An edited installed theme must not be overwritten or activated again.
        (target / 'colors.toml').write_text('my edits')
        (home / 'activated').unlink()
        result = subprocess.run(['bash', str(script), '--yes'],
                                env={**os.environ, 'HOME': str(home)}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((target / 'colors.toml').read_text(), 'my edits')
        self.assertFalse((home / 'activated').exists())

    def test_modified_file_preserved_and_no_partial_collision_install(self):
        packs = self.build()
        dest = self.root / 'stage'
        dest.mkdir()
        (dest / 'colors.toml').write_text('my palette')
        self.install(packs, success=False)
        self.assertEqual((dest / 'colors.toml').read_text(), 'my palette')
        self.assertFalse((dest / 'LICENSE').exists())

    def test_wrong_archive_hash_rejected_before_writes(self):
        packs = self.build()
        with (packs / 'afterburn-v1.2.3-base.tar.gz').open('ab') as f:
            f.write(b'corrupt')
        self.install(packs, success=False)
        self.assertFalse((self.root / 'stage/colors.toml').exists())

    def malicious(self, member, kind=None, wrong_file_hash=False):
        packs = self.root / 'evil'
        packs.mkdir(exist_ok=True)
        archive = packs / 'afterburn-v1.2.3-base.tar.gz'
        body = b'evil'
        records = {member: {'sha256': '0'*64 if wrong_file_hash else hashlib.sha256(body).hexdigest(), 'mode': 0o644}}
        with tarfile.open(archive, 'w:gz') as tar:
            info = tarfile.TarInfo(member)
            info.size = len(body)
            if kind:
                info.type = kind
                info.linkname = '/tmp'
                info.size = 0
            tar.addfile(info, io.BytesIO(body) if not kind else None)
            manifest = json.dumps({'schema': 1, 'files': records}).encode()
            info = tarfile.TarInfo('MANIFEST.json')
            info.size = len(manifest)
            tar.addfile(info, io.BytesIO(manifest))
        (packs / 'release.json').write_text(json.dumps({'schema': 1, 'version': 'v1.2.3', 'packs': {archive.name: {'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}}}))
        return packs

    def test_unsafe_members_and_bad_internal_hash_rejected(self):
        for name, kind, bad_hash in [('../escape', None, False), ('/absolute', None, False), ('link', tarfile.SYMTYPE, False), ('hard', tarfile.LNKTYPE, False), ('valid', None, True), ('a//b', None, False)]:
            with self.subTest(name=name):
                self.install(self.malicious(name, kind, bad_hash), success=False)
        self.assertFalse((self.root / 'stage/valid').exists())

    def test_archive_file_parent_collision_rejected_before_writes(self):
        packs = self.malicious('a')
        archive = packs / 'afterburn-v1.2.3-base.tar.gz'
        body = b'evil'
        records = {name: {'sha256': hashlib.sha256(body).hexdigest(), 'mode': 0o644} for name in ['a', 'a/b']}
        with tarfile.open(archive, 'w:gz') as tar:
            for name, content in [('a', body), ('a/b', body), ('MANIFEST.json', json.dumps({'schema': 1, 'files': records}).encode())]:
                info = tarfile.TarInfo(name)
                info.size = len(content)
                tar.addfile(info, io.BytesIO(content))
        (packs / 'release.json').write_text(json.dumps({'schema': 1, 'version': 'v1.2.3', 'packs': {archive.name: {'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}}}))
        self.install(packs, success=False)
        self.assertFalse((self.root / 'stage/a').exists())

    def test_destination_symlink_rejected(self):
        packs = self.build()
        dest = self.root / 'stage'
        dest.mkdir()
        (dest / 'extras').symlink_to(self.source / 'extras', target_is_directory=True)
        self.install(packs, success=False)

    def test_source_symlink_rejected(self):
        (self.source / 'extras/link').symlink_to('/etc/passwd')
        self.run_tool('build', '--source', self.source, '--output', self.root / 'packs', '--version', 'v1', success=False)

if __name__ == '__main__':
    unittest.main()
