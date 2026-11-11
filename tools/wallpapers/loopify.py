#!/usr/bin/env python3
"""Turn a clip that nearly returns to its first frame into an exactly periodic loop.

loopify.py IN OUT [--fade N] [--frames N] [--fps N] [--size WxH] [--vf FILTERS]

The clip's last N frames are crossfaded into its first N, which are then dropped from the start, so
the loop has (clip frames - N) distinct frames and its end runs into its beginning. The loop is then
resampled in time to exactly --frames frames (each a blend of its two neighbours, wrapping around),
so frame[frames] would be frame[0]. Needs ffmpeg and numpy.
"""
import argparse, subprocess, sys
import numpy as np

p = argparse.ArgumentParser()
p.add_argument('src'); p.add_argument('dst')
p.add_argument('--fade', type=int, default=24)
p.add_argument('--frames', type=int, default=360)
p.add_argument('--fps', type=int, default=30)
p.add_argument('--size', default='2560x1072')
p.add_argument('--vf', default='')
p.add_argument('--crf', default='21')
a = p.parse_args()
w, h = map(int, a.size.split('x'))
vf = f'scale={w}:-2:flags=lanczos,crop={w}:{h}' + (',' + a.vf if a.vf else '')
raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', a.src, '-vf', vf, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                     check=True, capture_output=True).stdout
size = w * h * 3
n = len(raw) // size
clip = np.frombuffer(raw, np.uint8, n * size).reshape(n, size)
k = a.fade
if not 0 < k < n // 2:
    sys.exit('loopify: --fade must be under half the clip')
m = n - k                                   # distinct loop frames: clip[k..n-1], the last k blended into clip[0..k-1]
def loop_frame(i):
    i %= m
    f = clip[k + i].astype(np.float32)
    j = i - (m - k)                         # 0..k-1 inside the fade
    if j >= 0:
        t = (j + 1) / (k + 1)
        f = f * (1 - t) + clip[j].astype(np.float32) * t
    return f
enc = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{w}x{h}',
                        '-r', str(a.fps), '-i', '-', '-an', '-c:v', 'libx264', '-profile:v', 'high',
                        '-pix_fmt', 'yuv420p', '-preset', 'slow', '-crf', a.crf, '-movflags', '+faststart',
                        '-map_metadata', '-1', a.dst], stdin=subprocess.PIPE)
for o in range(a.frames):
    s = o * m / a.frames
    i = int(s); t = s - i
    f = loop_frame(i) if t < 1e-6 else loop_frame(i) * (1 - t) + loop_frame(i + 1) * t
    enc.stdin.write(np.clip(f + 0.5, 0, 255).astype(np.uint8).tobytes())
enc.stdin.close()
sys.exit(enc.wait())
