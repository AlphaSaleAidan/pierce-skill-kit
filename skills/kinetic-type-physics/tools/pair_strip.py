#!/usr/bin/env python3
"""Side-by-side verification strip: reference frames (left) vs our rendered frames
(right) at the same cadence.

usage: pair_strip.py <ref_dir> <ref_start> <ours_dir> <ours_start> <fps> <out.jpg> [step]
  ref_dir  : frames fNNN.jpg from fx_sheets.py (1-based)
  ours_dir : frames fNNNNN.jpg from render_cut.mjs (0-based)
  step     : sample every Nth frame (default 2)
"""
import os, sys
from PIL import Image, ImageDraw

def main():
    R, ra, O, oa, fps, out = sys.argv[1], float(sys.argv[2]), sys.argv[3], float(sys.argv[4]), float(sys.argv[5]), sys.argv[6]
    step = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    rf, of = sorted(os.listdir(R)), sorted(os.listdir(O)); n = min(len(rf), len(of))
    W, H = 400, 225; idx = list(range(0, n, step))
    sheet = Image.new('RGB', (W * 2, H * len(idx)), 'black'); d = ImageDraw.Draw(sheet)
    for k, i in enumerate(idx):
        sheet.paste(Image.open(os.path.join(R, rf[i])).resize((W, H)), (0, k * H))
        sheet.paste(Image.open(os.path.join(O, of[i])).resize((W, H)), (W, k * H))
        d.text((4, k * H + 2), f'REF {ra + i / fps:.2f}s', fill='yellow')
        d.text((W + 4, k * H + 2), f'OURS {oa + i / fps:.2f}s', fill='yellow')
    sheet.save(out, quality=80); print(out, sheet.size)

if __name__ == '__main__':
    main()
