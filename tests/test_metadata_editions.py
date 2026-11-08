"""Generated metadata must follow real palette/config sources and detect drift."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / 'tools/generate-edition-data.py'

class EditionMetadata(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.output = Path(self.tmp.name) / 'edition-data.js'

    def generate(self, *args, success=True):
        p = subprocess.run([sys.executable, str(TOOL), '--output', str(self.output), *map(str, args)], capture_output=True, text=True)
        self.assertEqual(p.returncode == 0, success, p.stderr)
        if success and self.output.exists():
            return json.loads(self.output.read_text().split('window.AFTERBURN_EDITIONS = ', 1)[1].rstrip(';\n'))

    def test_canonical_palettes_defaults_and_presentation_hues(self):
        data = self.generate()
        self.assertEqual(list(data), ['afterburn', 'voltage', 'cyber', 'overdrive', 'redline', 'phantom'])
        self.assertEqual(data['afterburn']['s'], ['#f59145', '#ff5a1f', '#ffc48a'])
        self.assertEqual(data['afterburn']['rust'], '#e8703a')
        self.assertEqual(data['afterburn']['cursor'], 'embers')
        self.assertEqual(data['voltage']['cursor'], 'lightning')
        self.assertEqual(data['voltage']['rot'], 2.5)
        self.assertEqual(data['redline']['rot'], 0)
        self.assertEqual(data['redline']['on'], '#fafafa')
        self.assertEqual([row['hue'] for row in data.values()], [0, 159, 89, 289, 329, 244])
        self.assertEqual(data['phantom']['provenance']['colors'], '.editions/phantom/colors.toml')
        self.generate('--check')
        self.output.write_text(self.output.read_text().replace('#f59145', '#ffffff'))
        self.generate('--check', success=False)

    def test_changes_in_source_appear_in_output_and_fail_drift_check(self):
        source = Path(self.tmp.name) / 'theme'
        source.mkdir()
        for name in ['colors.toml', 'extras/afterburn-theme.sh', 'tools/make-editions.sh']:
            (source / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, source / name)
        shutil.copytree(ROOT / '.editions', source / '.editions', ignore=shutil.ignore_patterns('*.jpg', '*.png', '*.mp4', '*.webm'))
        shutil.copytree(ROOT / 'tools/edition-extras', source / 'tools/edition-extras', ignore=shutil.ignore_patterns('files'))
        doc = Path(self.tmp.name) / 'edition-defaults.md'
        self.generate('--source', source, '--markdown-output', doc)
        self.assertIn('| Voltage | lightning | 2.5 | 0.06 | 12 | spark |', doc.read_text())
        conf = source / 'tools/edition-extras/voltage/edition.conf'
        conf.write_text(conf.read_text().replace('GLOW_RANGE=12', 'GLOW_RANGE=13'))
        self.generate('--source', source, '--check', success=False)
        data = self.generate('--source', source)
        self.assertEqual(data['voltage']['glow'], 13)
        # JS is now current; the unchanged documentation must fail independently.
        self.generate('--source', source, '--markdown-output', doc, '--check', success=False)
        self.generate('--source', source, '--markdown-output', doc)
        self.assertIn('| Voltage | lightning | 2.5 | 0.06 | 13 | spark |', doc.read_text())
        self.assertIn('| Afterburn | embers | 10 | 0.08 | 14 | rise |', doc.read_text())
        self.generate('--source', source, '--markdown-output', doc, '--check')
        doc.write_text(doc.read_text().replace('| 13 | spark |', '| 12 | spark |'))
        self.generate('--source', source, '--markdown-output', doc, '--check', success=False)
        palette = source / '.editions/voltage/colors.toml'
        palette.write_text(palette.read_text().replace('45e6f5', '123456'))
        data = self.generate('--source', source)
        self.assertEqual(data['voltage']['s'][0], '#123456')

if __name__ == '__main__':
    unittest.main()
