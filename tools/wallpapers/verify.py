#!/usr/bin/env python3
"""Check delivered signature loops, motion continuity, heat assets and staged copies."""
import hashlib
import json
import operator
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


EXTRAS = ROOT / 'tools/edition-extras'
# An edition with its own hand-made colors.toml is a light one (tools/make-editions.sh); the rest are hue rotations.
LIGHT_EDITIONS = sorted(p.parent.name for p in EXTRAS.glob('*/colors.toml'))
DARK_EDITIONS = sorted(p.parent.name for p in EXTRAS.glob('*/edition.conf') if p.parent.name not in LIGHT_EDITIONS)


def check_loop(edition, loop):
    """The delivery spec every signature loop meets, and a seamless boundary. Returns its numbers."""
    info = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(loop)]))
    assert len(info['streams']) == 1, (edition, 'unexpected audio or extra stream')
    video = info['streams'][0]
    assert (video['codec_name'], video['profile'], video['pix_fmt']) == ('h264', 'High', 'yuv420p')
    assert (video['width'], video['height'], video['r_frame_rate'], int(video['nb_frames'])) == (2560, 1072, '30/1', 360)
    assert float(info['format']['duration']) == 12, (edition, info['format']['duration'])
    raw = subprocess.check_output([
        'ffmpeg', '-v', 'error', '-i', str(loop), '-vf', 'scale=320:134,format=gray',
        '-f', 'rawvideo', '-threads', '1', '-'])
    size = 320 * 134
    assert len(raw) == size * 360
    frames = [memoryview(raw)[i * size:(i + 1) * size] for i in range(360)]
    def difference(a, b):
        return sum(map(abs, map(operator.sub, a, b))) / size
    steps = [difference(frames[i], frames[i + 1]) for i in range(359)]
    seam = difference(frames[-1], frames[0])
    motion = max(difference(frames[0], frames[i]) for i in [90, 180, 270])
    assert motion > 0.1, (edition, 'no measurable motion', motion)
    # A sinusoidal camera is fastest near its zero crossing (the boundary). Compare against normal high-speed
    # frames, not the whole-loop median, which includes near-stationary turning points. Allow a small codec
    # quantization floor, but cap boundary change at 0.5/255 mean luma.
    p95 = sorted(steps)[int(len(steps) * 0.95)]
    limit = min(0.5, max(0.25, p95 * 2))
    assert seam <= limit, (edition, 'loop jump', seam, limit)
    return {'edition': edition, 'loop': loop.name, 'bytes': loop.stat().st_size,
            'median_frame_step': round(statistics.median(steps), 4), 'p95_frame_step': round(p95, 4),
            'boundary_step': round(seam, 4), 'quarter_loop_motion': round(motion, 4)}


def verify_light():
    """Light editions: the loop spec, every hand-made file staged unchanged, and a light palette.
    Their art is deliberately absent from the shared dark backgrounds/ folder."""
    results = []
    for edition in LIGHT_EDITIONS:
        source = ROOT / 'tools/edition-extras' / edition / 'files'
        staged = ROOT / '.editions' / edition
        loops = list((staged / 'backgrounds').glob('*.mp4'))
        assert len(loops) == 1, (edition, 'expected exactly one signature loop', loops)
        results.append(check_loop(edition, loops[0]))
        for path in sorted(p for p in source.rglob('*') if p.is_file()):
            relative = path.relative_to(source)
            assert digest(path) == digest(staged / relative), (edition, str(relative), 'stale generated asset')
        colors = (staged / 'colors.toml').read_text()
        assert 'mode = "light"' in colors, (edition, 'colors.toml is not a light palette')
        for level in ['cool', 'hot']:
            stills = {p.name for p in (staged / 'backgrounds').glob('*.jpg')}
            heat = {p.name for p in (staged / 'heat-wallpapers' / level).glob('*.jpg')}
            assert stills == heat, (edition, level, 'heat variants do not match the stills', stills ^ heat)
        assert not list((ROOT / 'backgrounds').glob(edition + '-*')), (edition, 'light art leaked into the dark picker')
    return results


def verify():
    results = []
    for edition in DARK_EDITIONS:
        source = ROOT / 'tools/edition-extras' / edition / 'files'
        staged = ROOT / '.editions' / edition
        loops = list((staged / 'backgrounds').glob('*.mp4'))
        assert len(loops) == 1, (edition, 'expected exactly one signature loop', loops)
        loop = loops[0]
        results.append(check_loop(edition, loop))
        for relative in ['backgrounds/1-horizon.jpg', f'backgrounds/{loop.name}',
                         'heat-wallpapers/cool/1-horizon.jpg', 'heat-wallpapers/hot/1-horizon.jpg']:
            assert digest(source / relative) == digest(staged / relative), (edition, relative, 'stale generated asset')
        # The top-level picker must expose the same full-resolution edition art.
        artwork = loop.stem.removeprefix('live-')
        for original, exposed in [('1-horizon.jpg', f'{edition}-{artwork}.jpg'),
                                  (loop.name, f'{edition}-{artwork}-live.mp4')]:
            assert digest(source / 'backgrounds' / original) == digest(ROOT / 'backgrounds' / exposed), (edition, exposed, 'stale root background')
    results += verify_light()
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    verify()
