"""雨夜河岸街 · 一屏样板（11-08，用户问为什么比不上空洞骑士、丝之歌）。
不生成新图，只把现有的天空 / 远景 / 背街 / 石阶段近景重新分明暗，再程序画一层前景剪影。
输出到 .runtime/mood/，默认游戏不读；tests/dev/capture_rain_mood.gd 用 Tuning.test_values 套上去截图。
"""
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets/image/rain_street"
OUT = ROOT / ".runtime/mood"
PX = json.loads((ROOT / "docs/视觉设计/雨夜河岸街/素材库/kit.json").read_text(encoding="utf-8"))["px_per_world"]
L709 = np.array([0.2126, 0.7152, 0.0722], np.float32)


def load(p):
    return np.asarray(Image.open(p).convert("RGBA")).astype(np.float32) / 255


def save(a, name):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(OUT / name)


def ramp(L, lo, hi):
    return np.array(lo, np.float32) + L[..., None] * (np.array(hi, np.float32) - np.array(lo, np.float32))


def warm_mask(rgb, a=None):
    m = np.clip((rgb[..., 0] - rgb[..., 2] - 0.06) / 0.2, 0, 1) * np.clip((rgb[..., 0] - 0.25) / 0.25, 0, 1)
    return m if a is None else m * a


def far_layer(src, name, lo, hi, gamma=1.0, keep_warm=0.0, soften=0.0):
    im = load(ART / src)
    rgb, a = im[..., :3], im[..., 3]
    L = rgb @ L709
    if soften:
        L = cv2.GaussianBlur(L, (0, 0), soften)
    v = a > 0.5
    p0, p1 = np.percentile(L[v], [2, 98])
    n = np.clip((L - p0) / (p1 - p0), 0, 1) ** gamma
    out = ramp(n, lo, hi)
    if keep_warm:
        w = warm_mask(rgb)[..., None] * keep_warm
        out = out * (1 - w) + np.array([0.86, 0.66, 0.40], np.float32) * w
    save(np.dstack([out, a]), name)


def sky():
    im = load(ART / "sky.png")[..., :3]
    L = im @ L709
    moon = cv2.GaussianBlur((L > 0.62).astype(np.float32), (0, 0), 2.0)
    soft = cv2.GaussianBlur(L, (0, 0), 16)
    h = L.shape[0]
    t = (np.arange(h, dtype=np.float32) / h)[:, None, None]
    grad = np.array([0.17, 0.235, 0.295], np.float32) * (1 - t) + np.array([0.54, 0.63, 0.67], np.float32) * t
    n = np.clip((soft - soft.min()) / (np.percentile(soft, 99) - soft.min()), 0, 1)
    out = grad * (0.86 + 0.34 * n[..., None])
    out = out * (1 - moon[..., None]) + np.array([0.86, 0.90, 0.90], np.float32) * moon[..., None]
    save(np.dstack([out, np.ones_like(L)]), "sky.png")


def near(sec):
    art = sec["art"]
    im = load(ROOT / art["near"].replace("res://", ""))
    rgb, a = im[..., :3].copy(), im[..., 3]
    H, W = a.shape
    px = lambda x: (x - art["x0"]) * PX
    py = lambda y: (y - art["y0"]) * PX
    X, Y = np.meshgrid(np.arange(W, dtype=np.float32), np.arange(H, dtype=np.float32))
    light = np.zeros_like(a)
    for x, y, _, rise in sec["lamps"]:
        d2 = (X - px(x)) ** 2 + (Y - py(y - rise)) ** 2
        light = np.maximum(light, np.exp(-d2 / (320 * PX) ** 2))
    windows = cv2.GaussianBlur(warm_mask(rgb, a), (0, 0), 46)
    light = np.maximum(light, np.clip(windows * 7, 0, 0.8))
    # 视觉中心：过街楼门洞里那条往深处去的街
    for cx, cy, r, g in [(-966, 470, 240, 0.75)]:
        light = np.maximum(light, g * np.exp(-((X - px(cx)) ** 2 + (Y - py(cy)) ** 2) / (r * PX) ** 2))
    L0 = rgb @ L709
    low = cv2.GaussianBlur(rgb, (0, 0), 9)
    detail = rgb - low
    out = low * (0.60 + 0.58 * light[..., None]) + detail * (0.20 + 0.80 * light[..., None])
    tint = np.array([1.34, 1.05, 0.80], np.float32)
    w = (light ** 1.3)[..., None]
    out = out * (1 - w) + out * tint * w + (light ** 2)[..., None] * np.array([0.085, 0.048, 0.012], np.float32)
    s = ((1 - light) * 0.3)[..., None]
    out = out * (1 - s) + np.array([0.030, 0.050, 0.072], np.float32) * s
    rim = (np.clip((L0 - 0.30) / 0.14, 0, 1) * (1 - warm_mask(rgb)))[..., None] * 0.42
    out = out * (1 - rim) + rgb * rim
    # 能站的面：一条冷亮的沿
    edge = np.zeros_like(a)
    for r in sec["platforms"] + sec["blocks"]:
        cv2.line(edge, (int(px(r[0])), int(py(r[2]))), (int(px(r[1])), int(py(r[2]))), 1.0, 3)
    edge_glow = cv2.GaussianBlur(edge, (0, 0), 5)
    rng = np.random.default_rng(5)
    broken = cv2.resize(rng.random((1, W // 60 + 2), np.float32), (W, H), interpolation=cv2.INTER_CUBIC)
    edge = np.clip(cv2.GaussianBlur(edge, (0, 0), 0.8) * 0.34 + edge_glow * 0.16, 0, 1) * (a > 0.4) * np.clip(0.25 + broken, 0, 1)
    out = out * (1 - edge[..., None]) + np.array([0.58, 0.72, 0.80], np.float32) * edge[..., None]
    # 街面和河岸护墙不动：路面的湿反光是好的
    street = np.clip((Y - py(566)) / (12 * PX), 0, 1)[..., None]
    out = out * (1 - street) + rgb * street
    save(np.dstack([out, a]), "near.png")


def front():
    # 头顶的尖拱：用廊桥部件自己的轮廓放在镜头前面，下端淡出，不挡人
    b1 = np.asarray(Image.open(ROOT / "docs/视觉设计/雨夜河岸街/素材库/b1_廊道段_透雾拱.png").convert("RGBA"))[..., 3]
    arch = b1[420:720].astype(np.float32) / 255
    aw = 860
    ah = int(arch.shape[0] * aw / arch.shape[1])
    arch = cv2.resize(arch, (aw, ah), interpolation=cv2.INTER_AREA)
    W, H = 1900, ah + 50
    m = np.zeros((H, W), np.float32)
    m[:50, 120:120 + aw] = 1
    m[50:, 120:120 + aw] = arch
    # 铁链和铁招牌
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    for x, n in [(1180, 13), (1420, 26), (1730, 9)]:
        for i in range(n):
            d.ellipse([x - 2, i * 7, x + 2, i * 7 + 6], outline=255)
    d.rectangle([1385, 182, 1455, 232], fill=255)
    d.polygon([(1385, 182), (1420, 164), (1455, 182)], fill=255)
    m = np.maximum(m, np.asarray(im).astype(np.float32) / 255)
    fade = np.clip((H - np.arange(H, dtype=np.float32)) / (H * 0.42), 0, 1)[:, None]
    m = cv2.GaussianBlur(m, (0, 0), 1.6) * fade
    col = np.ones((H, W, 3), np.float32) * np.array([0.018, 0.028, 0.040], np.float32)
    save(np.dstack([col, m]), "front.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    layout = json.loads((ROOT / "assets/data/rain_street_layout.json").read_text(encoding="utf-8"))
    sky()
    far_layer("far_city.png", "far.png", (0.24, 0.32, 0.39), (0.52, 0.61, 0.66), soften=1.0)
    far_layer("depth_deep_row_20261106.png", "deep.png", (0.25, 0.34, 0.41), (0.46, 0.55, 0.60), keep_warm=0.7, soften=1.2)
    far_layer("depth_back_row_20261106.png", "back.png", (0.12, 0.19, 0.26), (0.33, 0.42, 0.48), keep_warm=0.9, soften=1.0)
    near(layout["sections"][2])
    front()
    print("mood sample ok", OUT)


if __name__ == "__main__":
    main()
