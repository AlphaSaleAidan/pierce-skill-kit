#!/usr/bin/env python3
"""RVM matting: video in -> RGBA PNG sequence out (alpha from rvm_mobilenetv3).
Usage: rvm_local.py <in.mov> <outdir> [--model rvm_mobilenetv3_fp32.onnx] [--start S] [--dur D]
       [--height H] [--fps F] [--crop W:H:X:Y] [--feather PX] [--tonemap]
Model: rvm_mobilenetv3_fp32.onnx from the PeterL1n/RobustVideoMatting releases (GPL-3.0 at the time of writing; check before redistributing).
"""
import sys, os, subprocess, numpy as np, cv2, onnxruntime as ort

src, outdir = sys.argv[1], sys.argv[2]
def arg(name, default):
    return float(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default
start, dur, height, fps = arg("--start", 0), arg("--dur", 0), int(arg("--height", 1280)), arg("--fps", 30)
crop = sys.argv[sys.argv.index("--crop") + 1] if "--crop" in sys.argv else ""   # w:h:x:y at scaled size
feather = arg("--feather", 0.8)   # px sigma on alpha edge; erode ~1px first to kill bright rims
# phone HLG/BT.2020 source: tone-map to SDR Rec.709 so the cutout grades like normal footage
TONEMAP = "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=mobius,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
VF = (f"{TONEMAP}," if "--tonemap" in sys.argv else "") + f"scale=-2:{height}" + (f",crop={crop}" if crop else "")   # --tonemap only for HDR phone footage

os.makedirs(outdir, exist_ok=True)
# decode via ffmpeg pipe at target scale/fps so RVM sees exactly what we keep
cmd = ["ffmpeg", "-v", "error"]
if start: cmd += ["-ss", str(start)]
cmd += ["-i", src]
if dur: cmd += ["-t", str(dur)]
cmd += ["-vf", f"{VF},fps={fps}", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"]
# phone clips carry rotation metadata; decode one frame the same way to learn
# the real post-rotation size instead of trusting the container's width/height
probe_png = os.path.join(outdir, "_probe.png")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-frames:v", "1",
                "-vf", VF, probe_png], check=True)
H, W = cv2.imread(probe_png).shape[:2]
os.remove(probe_png)
print(f"decoded frame size {W}x{H}", flush=True)

model = sys.argv[sys.argv.index("--model") + 1] if "--model" in sys.argv else os.path.join(os.path.dirname(__file__), "rvm_mobilenetv3_fp32.onnx")
sess = ort.InferenceSession(model,
                            providers=["CPUExecutionProvider"])
rec = [np.zeros([1, 1, 1, 1], dtype=np.float32)] * 4
dsr = np.array([0.4], dtype=np.float32)  # downsample_ratio

proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
n = 0
frame_bytes = W * H * 3
while True:
    buf = proc.stdout.read(frame_bytes)
    if len(buf) < frame_bytes: break
    rgb = np.frombuffer(buf, np.uint8).reshape(H, W, 3)
    src_t = (rgb.astype(np.float32) / 255.0).transpose(2, 0, 1)[None]
    fgr, pha, *rec = sess.run(None, {"src": src_t, "r1i": rec[0], "r2i": rec[1],
                                     "r3i": rec[2], "r4i": rec[3], "downsample_ratio": dsr})
    a = (pha[0, 0] * 255).astype(np.uint8)
    if feather > 0:
        er = cv2.erode(a, np.ones((3, 3), np.uint8))
        a = cv2.addWeighted(a, 0.6, er, 0.4, 0)
        a = cv2.GaussianBlur(a, (0, 0), feather)
    f = (fgr[0].transpose(1, 2, 0) * 255).astype(np.uint8)
    rgba = np.dstack([f[:, :, ::-1], a])  # BGR + A for cv2
    cv2.imwrite(os.path.join(outdir, f"f{n:05d}.png"), rgba)
    n += 1
    if n % 60 == 0: print(f"{n} frames", flush=True)
proc.wait()
print(f"done: {n} frames at {W}x{H} -> {outdir}")
