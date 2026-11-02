"""雨夜河岸街 · 廊桥段（第 2 处封印，layout sections[1]）：用 GPT 素材包（5 个绿底部件）直接拼成整段近景，光影由本脚本生成。

素材：docs/视觉设计/雨夜河岸街/成图_廊桥素材/GPT原图_部件0N_*.png（用户已登录的 Edge 跑 GPT 网页批量出图，提示词在 发给GPT_廊桥素材/）。
原图只读；结果写 assets/image/rain_street/near_bridge_kit_20261030.png，并打印给 layout 用的平台 / 灯位（世界坐标，相对第 2 处封印中心）。

做法：
  1. 抠绿（build_rain_street_layers.key：局部背景绿估透明度 + 预乘还原）
  2. 统一比例：每个部件按“街面到廊道地面 = 560 世界单位”缩放（地面 580、廊道 20），部件之间在桥墩中线处重叠衔接
  3. 光影：按钟楼广场 / 走廊成图统一调色（Lab 亮度对齐、色偏收拢、暖灯保留）；右边缘补月光冷亮边；墙脚冷蓝湿反光带；接缝桥墩压暗一点
  4. 桥墩侧面加石挑台（从部件 1 的桥面石檐裁出来），给“街面 → 300 → 廊道 20”一条跳上去的路；部件 1 被画面上沿切平的尖塔补尖顶（从部件 2 裁）
  5. 街面和河岸护墙：从走廊成图里裁一段干净的街面 / 护墙，横向错位平铺，再按新灯位补暖色湿反光
用法：python -I tools/art/build_rain_bridge_kit.py
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
from build_rain_street_layers import key  # noqa: E402

KIT = ROOT / "docs/视觉设计/雨夜河岸街/成图_廊桥素材"
REF = ROOT / "assets/image/rain_street/near_plaza_corridor_20261030.png"   # 第 1 段近景（世界 x −2447 起）
OUT = ROOT / "assets/image/rain_street/near_bridge_kit_20261030.png"
PX = 1672 / 2710          # 成图 1 世界单位 = 多少像素（全关同一比例）
Y0 = -1100                # 画布上沿的世界 y（比第 1 段高：两座塔冲得更高，不能被切平）
H = int(round((826 - Y0) * PX))
X0 = -2520                # 画布左沿的世界 x（相对第 2 处封印中心）
X1 = 4000
W = int(round((X1 - X0) * PX))
STREET, GALLERY = 580.0, 20.0

# 部件：文件序号、裁切 x 范围（源像素）、左 / 右桥墩中线、廊道地面行、可站面（源像素：x0, x1, y）
PARTS = {
    1: dict(crop=(143, 1528), pier=(240, 1432), floor=432, stand=[(330, 1345, None)]),
    2: dict(crop=(211, 1461), pier=(322, 1350), floor=385, stand=[(395, 1280, None)]),
    3: dict(crop=(100, 925), pier=(190, 830), floor=940, stand=[(100, 925, None)]),
    4: dict(crop=(205, 812), pier=(248, 768), floor=955, stand=[(205, 290, None), (725, 812, None), (360, 665, 858)]),
    5: dict(crop=(40, 1640), pier=(60, None), floor=465, stand=[(40, 600, None)]),
}
ORDER = [1, 3, 4, 2, 5]   # 从左到右：标准段 → 方塔 → 中央方塔（落在封印中心附近）→ 铁栅门段 → 尽头石阶
FIRST_PIER_X = -2400.0    # 部件 1 左桥墩中线 = 第 1 段近景的右边缘（走廊尽头）


def load(i):
    f = sorted(KIT.glob(f"GPT原图_部件0{i}_*.png"))[0]
    rgb = np.asarray(Image.open(f).convert("RGB"), np.float32)
    return key(rgb)


def refine_floor(k, guess, x0, x1):
    """在猜的行上下 14 像素里找“上亮下暗”最强的一行（台面亮边）"""
    g = k[..., :3].mean(2) * (k[..., 3] > 128)
    d = g[:-2, x0:x1] - g[2:, x0:x1]
    rows = range(max(1, guess - 14), min(k.shape[0] - 3, guess + 14))
    return max(rows, key=lambda r: d[r].mean())


def lab_stats(rgba):
    m = rgba[..., 3] > 200
    lab = cv2.cvtColor(np.clip(rgba[..., :3], 0, 255).astype(np.uint8), cv2.COLOR_RGB2LAB).astype(np.float32)
    v = lab[m]
    return v.mean(0), v.std(0)


def grade(rgba, ref_mean, ref_std):
    """亮度均值 / 反差对齐参考；色偏均值拉到参考，色彩幅度只收不放（暖灯保留）"""
    m_mean, m_std = lab_stats(rgba)
    lab = cv2.cvtColor(np.clip(rgba[..., :3], 0, 255).astype(np.uint8), cv2.COLOR_RGB2LAB).astype(np.float32)
    lab[..., 0] = (lab[..., 0] - m_mean[0]) / max(m_std[0], 1) * ref_std[0] + ref_mean[0]
    for c in (1, 2):
        s = min(1.0, ref_std[c] / max(m_std[c], 1))
        lab[..., c] = (lab[..., c] - m_mean[c]) * s + ref_mean[c]
    out = cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2RGB).astype(np.float32)
    warm = (rgba[..., 0] > rgba[..., 2] + 40) & (rgba[..., 0] > 150)       # 灯和亮窗：保留原色
    out[warm] = rgba[warm, :3]
    return np.dstack([out, rgba[..., 3]])


def resize(rgba, f):
    h, w = rgba.shape[:2]
    return cv2.resize(rgba, (max(1, int(round(w * f))), max(1, int(round(h * f)))), interpolation=cv2.INTER_AREA)


def over(dst, src, x, y):
    """src（RGBA float）按 alpha 叠到 dst 的 (x, y)"""
    h, w = src.shape[:2]
    x0, y0, x1, y1 = max(x, 0), max(y, 0), min(x + w, dst.shape[1]), min(y + h, dst.shape[0])
    if x1 <= x0 or y1 <= y0:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]
    a = s[..., 3:4] / 255.0
    d = dst[y0:y1, x0:x1]
    d[..., :3] = s[..., :3] * a + d[..., :3] * (1 - a)
    d[..., 3:4] = s[..., 3:4] + d[..., 3:4] * (1 - a)


def wx(px):
    return px / PX + X0


def py(wy):
    return int(round((wy - Y0) * PX))


def main():
    near0 = np.asarray(Image.open(REF).convert("RGBA"), np.float32)
    ref_mean, ref_std = lab_stats(near0[:, near0.shape[1] - 900:])          # 走廊那一截当调色参考
    canvas = np.zeros((H, W, 4), np.float32)
    plats, lamps, piers = [], [], []
    pier_x = FIRST_PIER_X
    for i in ORDER:
        p = PARTS[i]
        k = load(i)
        cx0, cx1 = p["crop"]
        k = k[:, cx0:cx1]
        bottom = int(np.where((k[..., 3] > 128).any(1))[0].max())
        floor = refine_floor(k, p["floor"], int(k.shape[1] * 0.3), int(k.shape[1] * 0.7))
        s = (STREET - GALLERY) / (bottom - floor)            # 世界单位 / 源像素
        f = s * PX
        k = grade(k, ref_mean, ref_std)
        if i == 1:   # 被画面上沿切平的两根尖塔：补上部件 2 的尖顶
            cap = load(2)[0:70, 296:366].copy()
            cap = grade(cap, ref_mean, ref_std)
            for cxp in (240 - cx0, 1432 - cx0):
                capr = cv2.resize(cap, (int(cap.shape[1] * 1.25), int(cap.shape[0] * 1.25)))
                pad = np.zeros((capr.shape[0], k.shape[1], 4), np.float32)
                over(pad, capr, cxp - capr.shape[1] // 2, 0)
                k = np.concatenate([pad, k], 0) if cxp == 240 - cx0 else k
                if cxp != 240 - cx0:
                    over(k, capr, cxp - capr.shape[1] // 2, 0)
            top_pad = capr.shape[0]
        else:
            top_pad = 0
        kr = resize(k, f)
        left_pier_src = p["pier"][0] - cx0
        ox = int(round((pier_x - X0) * PX - left_pier_src * f))
        oy = int(round((STREET - Y0) * PX - (bottom + top_pad) * f))
        over(canvas, kr, ox, oy)
        to_w = lambda sx: (ox + (sx - cx0) * f) / PX + X0                     # 源像素 x → 世界 x
        to_wy = lambda sy: STREET - (bottom - sy) * s
        for a, b, y in p["stand"]:
            plats.append([round(to_w(a)), round(to_w(b)), round(GALLERY if y is None else to_wy(y), 1)])
        piers.append(round(pier_x))
        if p["pier"][1] is not None:
            pier_x = to_w(p["pier"][1])
        print(f"部件{i}: 缩放 {s:.3f} 世界/源像素, 廊道行 {floor}, 底 {bottom}, 世界 x {to_w(cx0):.0f} ~ {to_w(cx1):.0f}")
    piers.append(round(pier_x))

    # ---- 桥墩侧面的石挑台（世界 y 300）：从部件 1 的桥面石檐裁一段（顶面亮边 + 一排石托）
    k1 = grade(load(1), ref_mean, ref_std)
    ledge = k1[426:478, 600:1060].copy()
    ledge[..., 3] = np.where(ledge[..., 3] > 30, 255, 0)
    LEDGE_W = 360.0
    lf = LEDGE_W * PX / ledge.shape[1]
    lr = resize(ledge, lf)
    ledges = sorted(set(piers[1:-1]))   # 只挂在桥墩上（拱洞中间不放，免得悬空）
    for x in ledges:
        over(canvas, lr, int(round((x - X0) * PX - lr.shape[1] / 2)), py(300) - 2)
        plats.append([round(x - LEDGE_W / 2), round(x + LEDGE_W / 2), 300.0])

    # ---- 光影
    a = canvas[..., 3] / 255.0
    rgb = canvas[..., :3]
    # 右边缘月光冷亮边（往里 4 像素渐弱），只在上 75%
    solid = (a > 0.5).astype(np.float32)
    right_open = np.zeros_like(solid)
    right_open[:, :-3] = (solid[:, :-3] > 0) & (solid[:, 3:] == 0)
    rim = cv2.GaussianBlur(cv2.dilate(right_open, np.ones((1, 4), np.uint8)), (0, 0), 1.2) * solid
    rim[int(H * 0.75):] *= 0.3
    rgb += np.array([150, 168, 200], np.float32) * rim[..., None] * 0.45
    # 墙脚冷蓝湿反光带（地面以上 70 世界单位）
    yy = np.arange(H, dtype=np.float32)[:, None]
    band = np.clip((yy - py(STREET - 70)) / max(py(STREET) - py(STREET - 70), 1), 0, 1) ** 1.6
    rgb += np.array([18, 30, 52], np.float32) * (band * a)[..., None]
    # 接缝桥墩压暗一点（像深一层的石头，盖住两张图的笔触差别）
    for x in piers[1:-1]:
        c = (x - X0) * PX
        xx = np.arange(W, dtype=np.float32)[None, :]
        rgb *= 1 - 0.10 * np.exp(-((xx - c) / 30.0) ** 2)[..., None] * a[..., None]
    canvas[..., :3] = np.clip(rgb, 0, 255)

    # ---- 街面 + 河岸护墙：从走廊成图裁一段平铺（错位、去掉原来的暖灯倒影），再按新灯位补暖反光
    ry = lambda wy: int(round((wy + 698) * PX))   # 第 1 段近景的上沿是世界 y −698
    strip = near0[ry(574):ry(665), near0.shape[1] - 620:near0.shape[1] - 40].copy()
    warm = (strip[..., 0] > strip[..., 2] + 10) & (strip[..., 0] > 90)
    lum = strip[..., :3].mean(2, keepdims=True)
    strip[..., :3] = np.where(warm[..., None], lum * np.array([0.8, 0.88, 1.08]), strip[..., :3])
    rng = np.random.default_rng(3)
    x = 0
    street = np.zeros_like(canvas)
    while x < W:
        piece = strip[:, int(rng.integers(0, 120)):]
        over(street, piece, x, py(574))
        x += piece.shape[1] - 10
    lamp_specs = [(1, 1183, 290), (4, 325, 1100), (4, 695, 1100), (5, 1190, 255)]
    out = street
    over(out, canvas, 0, 0)

    # ---- 灯位（源像素 → 世界），给 layout 和光线层
    placed = {}
    pier_x = FIRST_PIER_X
    for i in ORDER:
        p = PARTS[i]
        k = load(i)[:, p["crop"][0]:p["crop"][1]]
        bottom = int(np.where((k[..., 3] > 128).any(1))[0].max())
        floor = refine_floor(k, p["floor"], int(k.shape[1] * 0.3), int(k.shape[1] * 0.7))
        s = (STREET - GALLERY) / (bottom - floor)
        placed[i] = (pier_x - (p["pier"][0] - p["crop"][0]) * s, bottom, s, p["crop"][0])
        if p["pier"][1] is not None:
            pier_x = placed[i][0] + (p["pier"][1] - p["crop"][0]) * s
    for i, sx, sy in lamp_specs:
        left, bottom, s, cx0 = placed[i]
        lx, ly = left + (sx - cx0) * s, STREET - (bottom - sy) * s
        lamps.append([round(lx), round(ly), "wall", 0])
        rx = int(round((lx - X0) * PX))
        g = np.exp(-((np.arange(W) - rx) / 26.0) ** 2)[None, :] * np.exp(-((np.arange(py(574), py(606)) - py(590)) / 9.0) ** 2)[:, None]
        out[py(574):py(606), :, :3] = np.clip(out[py(574):py(606), :, :3] + g[..., None] * np.array([70, 48, 22]), 0, 255)

    # 尽头石阶：按台阶斜线放几级一层台面（源像素 600,465 → 1480,775）
    left, bottom, s, cx0 = placed[5]
    for t in range(1, 5):
        sx = 600 + (1480 - 600) * t / 5
        sy = 465 + (775 - 465) * t / 5
        x0w = left + (sx - cx0) * s
        plats.append([round(x0w - 60), round(x0w + 90), round(STREET - (bottom - sy) * s, 1)])

    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(OUT)
    info = {"art": {"near": "res://assets/image/rain_street/" + OUT.name, "x0": X0, "y0": Y0, "width": round(W / PX, 2), "water_y": 665},
            "platforms": sorted(plats, key=lambda p: (p[2], p[0])), "lamps": lamps, "piers": piers}
    (ROOT / ".runtime/bridge_kit_layout.json").write_text(json.dumps(info, ensure_ascii=False, indent=1), encoding="utf-8")
    print("saved", OUT.name, out.shape[1], "x", out.shape[0])
    print(json.dumps(info, ensure_ascii=False))


if __name__ == "__main__":
    main()
