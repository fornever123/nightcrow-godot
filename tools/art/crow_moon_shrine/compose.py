"""把视差层按相机位置合成预览图 / 横向卷轴动图，并放入角色做尺度和可读性检查。

用法:
  py -3.10 compose.py still [camx]      -> preview_still.png (x3)
  py -3.10 compose.py scroll            -> preview_scroll.mp4 / .gif
"""
import glob
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image

from gen_scene import GROUND_Y, H, LAYERS, OUT, P, rgb

W = 640
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
CHAR_DIR = os.path.join(ROOT, "assets", "image", "characters", "nightcrow")
CHAR_H = 74  # 角色在 640x360 原生画面中的像素高度


def load_layers():
    return [(name, f, Image.open(os.path.join(OUT, name + ".png")).convert("RGBA")) for name, f, _ in LAYERS]


def char_frames(anim):
    fs = sorted(glob.glob(os.path.join(CHAR_DIR, anim, "*.png")))
    out = []
    ref = Image.open(sorted(glob.glob(os.path.join(CHAR_DIR, "idle", "*.png")))[0])
    s = CHAR_H / ref.height
    for f in fs:
        im = Image.open(f).convert("RGBA")
        im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
        a = np.array(im)
        a[..., 3] = np.where(a[..., 3] > 110, 255, 0)
        out.append(Image.fromarray(a, "RGBA"))
    return out


def compose(layers, camx, char=None, char_x=180, fg=True, particles=None):
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    for name, f, im in layers:
        if name.startswith("06") and not fg:
            continue
        if name.startswith("06") and char is not None:
            _place_char(frame, char, char_x)
            if particles:
                particles(frame)
        off = int(round(camx * f)) % im.width
        strip = im.crop((off, 0, min(im.width, off + W), H))
        frame.alpha_composite(strip, (0, 0))
        if strip.width < W:
            frame.alpha_composite(im.crop((0, 0, W - strip.width, H)), (strip.width, 0))
    if char is not None and not fg:
        _place_char(frame, char, char_x)
    return frame


def _place_char(frame, char, char_x):
    bb = char.getbbox()
    frame.alpha_composite(char, (char_x - char.width // 2, GROUND_Y - bb[3] + 1))


class Particles:
    """落羽 + 上升灵火，像素级。"""

    def __init__(self, seed=3, n_feather=26, n_mote=34):
        r = np.random.default_rng(seed)
        self.f = [[r.uniform(0, W), r.uniform(-H, H), r.uniform(0.15, 0.4), r.uniform(0, 6.28), r.random() < 0.35]
                  for _ in range(n_feather)]
        self.m = [[r.uniform(0, W), r.uniform(150, H), r.uniform(0.2, 0.5), r.uniform(0, 6.28)] for _ in range(n_mote)]

    def step(self, camdx):
        for p in self.f:
            p[1] += p[2]
            p[0] += math.sin(p[3]) * 0.4 - camdx * 1.1 - 0.15
            p[3] += 0.07
            if p[1] > H:
                p[1] -= H + 20
            p[0] %= W
        for p in self.m:
            p[1] -= p[2]
            p[0] += math.sin(p[3]) * 0.25 - camdx * 0.8
            p[3] += 0.05
            if p[1] < 120:
                p[1] = H
            p[0] %= W

    def draw(self, frame):
        a = np.array(frame)
        for x, y, s, ph, white in self.f:
            x, y = int(x), int(y)
            flip = math.sin(ph) > 0
            c = rgb(P["paper"][2]) if white else rgb(P["fg"][2])
            c2 = rgb(P["paper"][1]) if white else rgb(P["violet"][1])
            pts = [(0, 0, c), (1, 0, c2)] if flip else [(0, 0, c), (0, 1, c2)]
            for dx, dy, col in pts:
                if 0 <= y + dy < H and 0 <= x + dx < W:
                    a[y + dy, x + dx, :3] = col
        for x, y, s, ph in self.m:
            x, y = int(x), int(y)
            if 0 <= y < H and 0 <= x < W:
                tw = math.sin(ph * 3)
                a[y, x, :3] = rgb(P["violet"][4] if tw > 0.3 else P["violet"][3])
                if tw > 0.8 and y + 1 < H:
                    a[y + 1, x, :3] = rgb(P["violet"][2])
        frame.paste(Image.fromarray(a, "RGBA"))


def still(camx=0):
    layers = load_layers()
    idle = char_frames("idle")[0]
    pt = Particles()
    for _ in range(200):
        pt.step(0)
    fr = compose(layers, camx, idle, 190, particles=pt.draw)
    fr.save(os.path.join(OUT, "preview_still_1x.png"))
    fr.resize((W * 3, H * 3), Image.NEAREST).save(os.path.join(OUT, "preview_still.png"))
    compose(layers, camx).resize((W * 3, H * 3), Image.NEAREST).save(os.path.join(OUT, "preview_bg_only.png"))
    print("still ok")


def scroll(n=240, speed=1.6):
    layers = load_layers()
    run = char_frames("run")
    pt = Particles()
    for _ in range(200):
        pt.step(0)
    tmp = os.path.join(OUT, "_frames")
    os.makedirs(tmp, exist_ok=True)
    for f in glob.glob(os.path.join(tmp, "*.png")):
        os.remove(f)
    gif = []
    for i in range(n):
        camx = i * speed
        pt.step(speed)
        fr = compose(layers, camx, run[(i // 2) % len(run)], 220, particles=pt.draw)
        fr.convert("RGB").resize((W * 3, H * 3), Image.NEAREST).save(os.path.join(tmp, f"f{i:04d}.png"))
        if i % 2 == 0:
            gif.append(fr.convert("RGB"))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(tmp, "f%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", os.path.join(OUT, "preview_scroll.mp4")], check=True)
    gif[0].save(os.path.join(OUT, "preview_scroll.gif"), save_all=True, append_images=gif[1:], duration=66, loop=0)
    for f in glob.glob(os.path.join(tmp, "*.png")):
        os.remove(f)
    os.rmdir(tmp)
    print("scroll ok")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "still"
    if mode == "still":
        still(float(sys.argv[2]) if len(sys.argv) > 2 else 0)
    else:
        scroll()
