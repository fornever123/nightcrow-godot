"""雨夜河岸街 · 街道深处（用户 11-06：“没有很考虑环境除了路上的风景外的其它地方，比如街上更深处的地方”）。

近景那排楼和远景剪影之间原来什么都没有。这里用素材库的楼拼两排背街，夹在中间（street_backdrop.gd 按各自的视差画，镜像平铺）：
  back_row：紧贴近景后面的一排，缩到 0.66，细节还看得清，亮窗和路灯留着
  deep_row：再往里一排，缩到 0.42，只剩大形和亮窗，脚下没进雾里
楼之间留空档，能从前一排的缝里看到后一排；越往下雾越浓。每盏灯补一团暖雾光。
用法：python -I tools/art/rain_kit_depth.py    输出 assets/image/rain_street/depth_{back,deep}_row_20261106.png
"""
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "docs/视觉设计/雨夜河岸街/素材库"
ART = ROOT / "assets/image/rain_street"
FOG = np.array([70, 100, 146], np.float32)    # 远景图下半截的雾色

BUILDINGS = ["s0_尖顶哥特楼", "s0_铁门拱", "s0_老虎窗排屋", "s0_阶梯山墙楼", "s1_排屋_左窗亮", "s0_凸窗窄楼", "s0_店铺", "s0_仓库吊钩楼",
             "s0_老虎窗小楼", "s0_城门塔"]   # 不用钟楼（地标）；不用孟莎顶塔楼（警署蓝灯全关只有一盏）
ROWS = {
    "back": dict(scale=0.66, width=3700, gap=(50, 260), keep=0.62, dark=(30, 44, 74), fog_top=0.10, fog_bottom=0.92, window=0.85, seed=11),
    "deep": dict(scale=0.42, width=3700, gap=(10, 150), keep=0.30, dark=(38, 56, 90), fog_top=0.30, fog_bottom=1.0, window=0.70, seed=29),
}


def build_row(name, cfg, kit, PX):
    rng = np.random.default_rng(cfg["seed"])
    s = cfg["scale"]
    tall = max(kit[b]["h"] for b in BUILDINGS) * s * PX
    H = int(tall) + 8
    W = cfg["width"]
    row = np.zeros((H, W, 4), np.float32)
    lamps = []
    x = int(rng.integers(0, 60))
    order = list(BUILDINGS)
    rng.shuffle(order)
    i = 0
    while True:
        p = kit[order[i % len(order)]]
        i += 1
        img = np.asarray(Image.open(LIB / p["file"]).convert("RGBA"), np.float32)
        mirror = bool(rng.integers(0, 2))
        if mirror:
            img = img[:, ::-1]
        small = cv2.resize(img, (max(1, int(img.shape[1] * s)), max(1, int(img.shape[0] * s))), interpolation=cv2.INTER_AREA)
        if x + small.shape[1] > W:
            break
        y = H - small.shape[0]
        a = small[..., 3:] / 255.0
        row[y:H, x:x + small.shape[1], :3] = small[..., :3] * a + row[y:H, x:x + small.shape[1], :3] * (1 - a)
        row[y:H, x:x + small.shape[1], 3:] = small[..., 3:] + row[y:H, x:x + small.shape[1], 3:] * (1 - a)
        for lx, ly, _, rise in p["lamps"]:
            lx = p["w"] - lx if mirror else lx
            # 灯在件里的高度：y 是世界坐标，件底是 FOOT（576）
            lamps.append((x + lx * PX * s, H - (576 - (ly - rise)) * PX * s))
        x += small.shape[1] + int(rng.integers(*cfg["gap"]) * PX * s * 2)

    # 空气透视：明度往暗蓝里压，越往下越进雾；亮窗少压
    rgb, alpha = row[..., :3], row[..., 3]
    warm = np.clip((rgb[..., 0] - rgb[..., 2] - 12) / 50.0, 0, 1)
    warm = cv2.GaussianBlur(warm, (0, 0), 0.8)[..., None]
    cooled = rgb * cfg["keep"] + np.array(cfg["dark"], np.float32) * (1 - cfg["keep"])
    rgb = cooled * (1 - warm) + rgb * cfg["window"] * warm
    t = (np.arange(H, dtype=np.float32) / (H - 1))[:, None, None]
    fog = cfg["fog_top"] + (cfg["fog_bottom"] - cfg["fog_top"]) * np.clip((t - 0.35) / 0.65, 0, 1) ** 1.5
    rgb = rgb * (1 - fog) + FOG * fog
    # 暖雾光：加在楼上，也要加在楼之间的空档里，所以给 alpha 也补一点
    glow = np.zeros((H, W), np.float32)
    for lx, ly in lamps:
        if 0 <= lx < W and 0 <= ly < H:
            glow[int(ly), int(lx)] = 1.0
    r = 34 * s / 0.66
    halo = cv2.GaussianBlur(glow, (0, 0), r)
    halo = halo / max(halo.max(), 1e-6)
    rgb = rgb + np.array([120, 84, 44], np.float32) * halo[..., None] * (0.55 if name == "back" else 0.4)
    alpha = np.maximum(alpha, halo * 120)
    # 脚下淡出：接在远景的雾里，看不到底边
    alpha = alpha * np.clip((1.0 - t[..., 0]) / 0.10, 0, 1)
    out = np.dstack([np.clip(rgb, 0, 255), alpha])
    path = ART / f"depth_{name}_row_20261106.png"
    Image.fromarray(out.astype(np.uint8)).save(path)
    print(name, path.name, W, "x", H, "灯", len(lamps))
    prev = Image.new("RGBA", (W, H), (70, 100, 146, 255))
    prev.alpha_composite(Image.fromarray(out.astype(np.uint8)))
    prev.convert("RGB").save(ROOT / f".runtime/depth_{name}_prev.png")


def main():
    kit = json.loads((LIB / "kit.json").read_text(encoding="utf-8"))
    for name, cfg in ROWS.items():
        build_row(name, cfg, kit["pieces"], kit["px_per_world"])


if __name__ == "__main__":
    main()
