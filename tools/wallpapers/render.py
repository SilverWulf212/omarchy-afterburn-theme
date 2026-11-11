#!/usr/bin/env python3
"""Render curated stills and periodic live loops with FFmpeg; never touches base art."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EDITIONS = {
    'voltage': ('resonance', 5, 3, 0.055),
    'cyber': ('phosphor-path', 1, 1, 0.045),
    'overdrive': ('midnight-ribbon', 3, 2, 0.05),
    'redline': ('crimson-turbine', 1, 2, 0.04),
    'phantom': ('spectral-veil', 7, 5, 0.03),
}
DURATION = 12
FPS = 30


def run(*args):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *args], check=True)


def render(edition):
    name, dx, dy, breath = EDITIONS[edition]
    source = ROOT / 'tools/wallpapers/sources' / (edition + '.png')
    target = ROOT / 'tools/edition-extras' / edition / 'files'
    backgrounds = target / 'backgrounds'
    backgrounds.mkdir(parents=True, exist_ok=True)
    fit = 'scale=3440:1440:force_original_aspect_ratio=increase:flags=lanczos,crop=3440:1440,setsar=1'
    # Retain the original default filename for heat-level and installed-background compatibility.
    for level, gamma in [('normal', 1), ('cool', 0.86), ('hot', 1.12)]:
        folder = backgrounds if level == 'normal' else target / 'heat-wallpapers' / level
        folder.mkdir(parents=True, exist_ok=True)
        run('-i', str(source), '-vf', f'{fit},eq=gamma={gamma}',
            '-frames:v', '1', '-q:v', '2', '-map_metadata', '-1', str(folder / '1-horizon.jpg'))

    # Low-resolution displacement fields are smoothly interpolated. All time terms
    # have integer harmonics over 12 seconds, so the unencoded frame at t=12 is t=0.
    # The architectural Cyber/Redline art barely bends; Phantom's veil drifts more.
    phase = f'2*PI*T/{DURATION}'
    xexpr = f'128+{dx}*sin(2*PI*Y/H+{phase})*(0.25+0.75*X/W)'
    yexpr = f'128+{dy}*sin(2*PI*X/W-{phase})*(0.25+0.75*X/W)'
    def field(expr):
        return f"geq=lum='{expr}':cb='{expr}':cr='{expr}',scale=2560:1072:flags=bilinear,format=yuv444p"
    # Perspective resamples fractional coordinates; animated crop coordinates
    # round to whole pixels and produce visible ticks on bright fine contours.
    sx = f'8*sin(2*PI*on/{FPS * DURATION})'
    sy = f'4*cos(2*PI*on/{FPS * DURATION})'
    camera = (f"perspective=x0='{sx}':y0='{sy}':x1='W+{sx}':y1='{sy}':"
              f"x2='{sx}':y2='H+{sy}':x3='W+{sx}':y3='H+{sy}':"
              'eval=frame:interpolation=cubic,crop=2560:1072:16:8')
    graph = (
        '[0:v]scale=2592:1088:force_original_aspect_ratio=increase:flags=lanczos,'
        'crop=2592:1088,setsar=1,format=yuv444p,'
        f'{camera}[art];'
        f'[1:v]split[mx][my];[mx]{field(xexpr)}[x];[my]{field(yexpr)}[y];'
        '[art][x][y]displace=edge=mirror,'
        # Gamma preserves black. Modulating contrast lifts the whole black floor
        # by quantized luma steps, which looks like a flash in a dark wallpaper.
        f"eq=gamma='1+{breath}*sin(2*PI*t/{DURATION})':eval=frame,format=yuv420p[out]"
    )
    run('-loop', '1', '-framerate', str(FPS), '-i', str(source),
        '-f', 'lavfi', '-i', f'nullsrc=s=640x268:r={FPS}:d={DURATION}',
        '-filter_complex_threads', '2', '-filter_complex', graph, '-map', '[out]',
        '-frames:v', str(FPS * DURATION), '-an', '-map_metadata', '-1',
        '-c:v', 'libx264', '-threads', '4', '-preset', 'slow', '-crf', '20',
        '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
        str(backgrounds / f'live-{name}.mp4'))
    print(f'Rendered {edition}: {name}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('edition', choices=[*EDITIONS, 'all'])
    args = parser.parse_args()
    for edition in EDITIONS if args.edition == 'all' else [args.edition]:
        render(edition)
