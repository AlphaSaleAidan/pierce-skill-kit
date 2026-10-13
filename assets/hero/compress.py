# raw-<v>.png (Blender output) -> hero-<v>.png under 500 KB. 216 tone colours + 40 reserved
# for the red/teal accents so the thin emissive lines survive the palette.  python3 compress.py
from PIL import Image, ImageFilter
import numpy as np, os

for v in ("dark", "light"):
    raw = Image.open(f"raw-{v}.png").convert("RGB")
    im = raw.filter(ImageFilter.GaussianBlur(0.6))  # no OIDN in this blender build
    # flat areas (floor, bg) get a heavy blur so sample noise doesn't turn into dither grain
    edge = np.asarray(raw.convert("L").filter(ImageFilter.GaussianBlur(2)).filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(9))).astype(float)
    m = np.clip(1 - edge / 6, 0, 1)[..., None]  # 1 = flat, 0 = near an edge/line
    soft = np.asarray(raw.filter(ImageFilter.GaussianBlur(4))).astype(float)
    im = Image.fromarray((m * soft + (1 - m) * np.asarray(im)).round().astype(np.uint8))
    a = np.asarray(im).astype(int)
    acc = a[(a.max(2) - a.min(2)) > 40].reshape(-1, 1, 3).astype(np.uint8)
    accp = Image.fromarray(acc).quantize(40, method=Image.Quantize.MEDIANCUT).getpalette()[:120]
    basep = im.quantize(216, method=Image.Quantize.MEDIANCUT).getpalette()[:648]
    pal = Image.new("P", (1, 1))
    pal.putpalette(basep + accp)
    im.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG).save(f"hero-{v}.png", optimize=True)
    size = os.path.getsize(f"hero-{v}.png")
    assert size < 500_000, (v, size)
    print(v, size)
