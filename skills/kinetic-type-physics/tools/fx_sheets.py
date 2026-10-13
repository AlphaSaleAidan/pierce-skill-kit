#!/usr/bin/env python3
"""Extract text-effect windows from a reference video at NATIVE frame rate and build
contact sheets (4 columns, yellow timecode per frame) for frame-by-frame analysis.

usage: fx_sheets.py <video> <out_dir> <name>:<start>:<end> [<name>:<start>:<end> ...]
   eg: fx_sheets.py reference/ref.mp4 reference/fx 02-wall-in:1.0:2.2 05-rows:3.3:4.0

Then READ every sheet (Read tool) and write the per-frame findings before any code.
"""
import os, subprocess, sys
from PIL import Image, ImageDraw

def fps_of(video):
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v', '-show_entries',
                          'stream=r_frame_rate', '-of', 'csv=p=0', video], capture_output=True, text=True).stdout.strip()
    n, d = out.split('/'); return float(n) / float(d)

def main():
    video, out_dir, windows = sys.argv[1], sys.argv[2], sys.argv[3:]
    fps = fps_of(video); os.makedirs(out_dir, exist_ok=True)
    for spec in windows:
        name, a, b = spec.split(':'); a, b = float(a), float(b)
        d = os.path.join(out_dir, name); os.makedirs(d, exist_ok=True)
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-ss', str(a), '-t', str(b - a), '-i', video,
                        '-vf', 'scale=700:-2', '-q:v', '2', f'{d}/f%03d.jpg'], check=True)
        fs = sorted(os.listdir(d)); cols, fw, fh = 4, 350, 198
        rows = (len(fs) + cols - 1) // cols
        sheet = Image.new('RGB', (cols * fw, rows * fh), 'black'); dr = ImageDraw.Draw(sheet)
        for i, f in enumerate(fs):
            im = Image.open(os.path.join(d, f)).resize((fw, fh)); x, y = (i % cols) * fw, (i // cols) * fh
            sheet.paste(im, (x, y)); dr.rectangle((x, y, x + 62, y + 12), fill='black')
            dr.text((x + 2, y), f'{a + i / fps:.2f}', fill='yellow')
        sheet.save(os.path.join(out_dir, f'{name}.jpg'), quality=85)
        print(name, len(fs), f'{1000 / fps:.0f}ms/frame', sheet.size)

if __name__ == '__main__':
    main()
