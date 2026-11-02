"""雨夜河岸街 · 背景素材库：把已有成图和 GPT 绿底部件切成一件件可以拼接的单件（用户 11-01：以前和以后的背景全部用拼接）。

每件存成统一比例的透明 PNG（1 世界单位 = PX 像素，和游戏里近景成图同一比例），元数据写进 kit.json：
  w / top / h：宽（世界单位）、图片上沿的世界 y、高；街面统一在世界 y 580
  attach：左右接口（件内 x）。拼接时下一件的左接口对齐上一件的右接口（GPT 部件是桥墩中线，楼是墙边）
  stand：可站面 [x0, x1, y, 样式]；blocks：实心石台 [x0, x1, 顶面 y, 样式]；lamps：灯 [x, y, 类型, rise]（x 都是件内坐标）
  relight：拼接时要不要补亮边 / 墙脚湿反光（GPT 部件要，原成图切出来的件已经画好了光，不要）
  unique：地标件（钟楼）只能出现一次
来源（只读）：
  - 第 1 段近景成图 near_plaza_corridor_20261030.png：按楼的墙边竖切 16 件，可站面 / 灯从当时的布局里按位置分给各件
  - GPT 部件：成图_廊桥素材/（5 件）、成图_石阶素材/（2 件）：抠绿 → 按参考线定比例 → 对齐第 1 段的色调
用法：python -I tools/art/rain_kit_library.py   （改了切法 / 比例后重跑，再跑 rain_kit_compose.py）
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
from build_rain_bridge_kit import grade, lab_stats, over, refine_floor, resize  # noqa: E402
from build_rain_street_layers import key  # noqa: E402

LIB = ROOT / "docs/视觉设计/雨夜河岸街/素材库"
ART = ROOT / "assets/image/rain_street"
BRIDGE = ROOT / "docs/视觉设计/雨夜河岸街/成图_廊桥素材"
STEPS = ROOT / "docs/视觉设计/雨夜河岸街/成图_石阶素材"
PX = 1672 / 2710
STREET, GALLERY = 580.0, 20.0
FOOT = 576.0      # 切件的下沿（世界 y）：再往下是街面，由拼接脚本统一铺

# 第 1 段近景：世界 x（相对第 1 处封印中心）的切线和每件的名字。切在墙边；钟楼是地标，只能用一次
S0_SRC = ART / "near_plaza_corridor_20261030.png"
S0_X0, S0_Y0 = -2447.0, -698.0
S0_CUTS = [
    (-2447, -1975, "s0_仓库吊钩楼", []),
    (-1975, -1552, "s0_尖顶哥特楼", []),
    (-1552, -1445, "s0_铁桥", ["connector"]),
    (-1445, -900, "s0_老虎窗排屋", []),
    (-900, -612, "s0_凸窗窄楼", []),
    (-612, -345, "s0_拱桥石台", ["connector"]),
    (-345, 345, "s0_钟楼", ["landmark"]),
    (345, 700, "s0_吊车码头", ["connector"]),
    (700, 1000, "s0_阶梯山墙楼", []),
    (1000, 1450, "s0_店铺", []),
    (1450, 1605, "s0_铁门拱", ["connector"]),
    (1605, 2005, "s0_孟莎顶塔楼", []),
    (2005, 2400, "s0_老虎窗小楼", []),
    (2400, 2545, "s0_路灯空档", ["connector"]),
    (2545, 3075, "s0_城门塔", []),
    (3075, 4000, "s0_廊道起点", []),
]


def gpt(path, crop):
    rgb = np.asarray(Image.open(path).convert("RGB"), np.float32)
    return key(rgb)[:, crop[0]:crop[1]]


def alpha_bottom(k):
    return int(np.where((k[..., 3] > 128).any(1))[0].max())


def save(img, name):
    LIB.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(LIB / f"{name}.png")
    return f"{name}.png"


def piece_from_gpt(name, k, s, bottom, *, attach_src=None, stand=(), blocks=(), lamps=(), tags=(), seam=True):
    """k：已抠绿、已裁、已调色的源图；s：世界单位 / 源像素；bottom：源图里街面那一行。源像素坐标 → 件内世界坐标"""
    img = resize(k, s * PX)
    top = STREET - bottom * s
    wy = lambda sy: round(STREET - (bottom - sy) * s, 1)
    sx = lambda x: round(x * s, 1)
    w = img.shape[1] / PX
    a = attach_src or (0, k.shape[1])
    return dict(
        id=name, file=save(img, name), w=round(w, 1), top=round(top, 1), h=round(img.shape[0] / PX, 1),
        attach=[sx(a[0]), sx(a[1])], scale=round(s, 4), relight=True, seam=seam, unique=False, tags=list(tags),
        stand=[[sx(x0), sx(x1), GALLERY if y is None else wy(y), st] for x0, x1, y, st in stand],
        blocks=[[sx(x0), sx(x1), wy(y), st] for x0, x1, y, st in blocks],
        lamps=[[sx(x), wy(y), kind, round(rise * s, 1)] for x, y, kind, rise in lamps],
    )


def section0(pieces):
    layout = json.loads((ROOT / "assets/data/rain_street_layout.json").read_text(encoding="utf-8"))
    s0 = layout["sections"][0]
    img = np.asarray(Image.open(S0_SRC).convert("RGBA"), np.float32)
    foot = int(round((FOOT - S0_Y0) * PX))
    for x0, x1, name, tags in S0_CUTS:
        a, b = int(round((x0 - S0_X0) * PX)), int(round((x1 - S0_X0) * PX))
        cut = img[:foot, a:b].copy()
        rows = np.where((cut[..., 3] > 8).any(1))[0]
        r0 = int(rows.min()) if len(rows) else 0
        cut = cut[r0:]
        inside = lambda xa, xb: x0 <= (xa + xb) / 2 < x1
        loc = lambda x: round(x - x0, 1)
        pieces.append(dict(
            id=name, file=save(cut, name), w=round(x1 - x0, 1), top=round(S0_Y0 + r0 / PX, 1), h=round(cut.shape[0] / PX, 1),
            attach=[0.0, round(x1 - x0, 1)], scale=1.0, relight=False, seam=False, unique="landmark" in tags, tags=tags,
            stand=[[loc(p[0]), loc(p[1]), p[2], p[3]] for p in s0["platforms"] if inside(p[0], p[1])],
            blocks=[[loc(p[0]), loc(p[1]), p[2], p[3]] for p in s0["blocks"] if inside(p[0], p[1])],
            lamps=[[loc(l[0]), l[1], l[2], l[3] if len(l) > 3 else 0] for l in s0["lamps"] if inside(l[0], l[0])],
            source=f"{S0_SRC.name} 世界 x {x0}~{x1}",
        ))


def bridge_parts(pieces, ref):
    f = lambda i: sorted(BRIDGE.glob(f"GPT原图_部件0{i}_*.png"))[0]

    def prep(i, crop, floor_guess, ref_row=GALLERY):
        k = gpt(f(i), crop)
        bottom = alpha_bottom(k)
        floor = refine_floor(k, floor_guess, int(k.shape[1] * 0.3), int(k.shape[1] * 0.7))
        return grade(k, *ref), (STREET - ref_row) / (bottom - floor), bottom

    # 部件 1：标准廊道段。被画面上沿切平的两根尖塔补上部件 2 的尖顶
    k, s, bottom = prep(1, (143, 1528), 432)
    cap = grade(gpt(f(2), (296, 366))[0:70], *ref)
    capr = cv2.resize(cap, (int(cap.shape[1] * 1.25), int(cap.shape[0] * 1.25)))
    pad = np.zeros((capr.shape[0], k.shape[1], 4), np.float32)
    k = np.concatenate([pad, k], 0)
    for cx in (240 - 143, 1432 - 143):
        over(k, capr, cx - capr.shape[1] // 2, 0)
    bottom += capr.shape[0]
    pieces.append(piece_from_gpt("b1_廊道段_透雾拱", k, s, bottom, attach_src=(97, 1289), stand=[(187, 1202, None, "gallery")],
                                 lamps=[(1183 - 143, 290 + capr.shape[0], "wall", 0)], tags=["bridge"]))
    # 部件 2：铁栅门段
    k, s, bottom = prep(2, (211, 1461), 385)
    pieces.append(piece_from_gpt("b2_廊道段_铁栅门", k, s, bottom, attach_src=(111, 1139), stand=[(184, 1069, None, "gallery")], tags=["bridge"]))
    # 部件 3：廊道方塔（带两边各一截廊道）
    k, s, bottom = prep(3, (100, 925), 940)
    pieces.append(piece_from_gpt("b3_廊道方塔", k, s, bottom, attach_src=(90, 730), stand=[(0, 825, None, "gallery")], tags=["bridge", "tower"]))
    # 部件 4：中央方塔（塔门两盏壁灯，塔上一圈挑台）
    k, s, bottom = prep(4, (205, 812), 955)
    pieces.append(piece_from_gpt("b4_中央方塔", k, s, bottom, attach_src=(43, 563),
                                 stand=[(0, 85, None, "gallery"), (520, 607, None, "gallery"), (155, 460, 858, "balcony")],
                                 lamps=[(120, 1100, "wall", 0), (490, 1100, "wall", 0)], tags=["bridge", "tower"]))
    # 部件 5：尽头石阶（左半截拱 + 拱廊平台 + 往右下的石阶 + 收尾石柱）
    k5, s5, bottom5 = prep(5, (40, 1640), 465)
    steps = []
    for t in range(1, 5):   # 台阶斜线（源像素 600,465 → 1480,775）上放几级台面
        sx, sy = 600 + 880 * t / 5, 465 + 310 * t / 5
        steps.append((sx - 60 / s5, sx + 90 / s5, sy, "balcony"))
    pieces.append(piece_from_gpt("b5_尽头石阶", k5, s5, bottom5, attach_src=(20, 1600), stand=[(0, 560, None, "gallery")] + [(a - 40, b - 40, y, st) for a, b, y, st in steps],
                                 lamps=[(1150, 255, "wall", 0)], tags=["bridge", "stairs"]))
    # 部件 5 只取石阶那一半（从桥墩起）：可以两边对称用，拼一座双跑大石阶
    full = gpt(f(5), (495, 1645))
    for plain in (False, True):
        k = grade(full.copy(), *ref)
        if plain:   # 去掉墙脚的木桶木箱（同一座石阶连着出现时不至于一眼看出是复制的）：用台阶下那段平墙盖上
            wall = k[650:880, 965 - 495:1130 - 495].copy()
            for x in range(680 - 495, 965 - 495, wall.shape[1] - 6):
                w = min(wall.shape[1], 965 - 495 - x)
                k[650:880, x:x + w] = wall[:, :w]
        st = [(505 - 495, 720 - 495, None, "gallery")] + [(a - 495, b - 495, y, sty) for a, b, y, sty in steps]
        pieces.append(piece_from_gpt("b5_石阶半边" + ("_无木桶" if plain else ""), k, s5, bottom5, attach_src=(60, 1150),
                                     stand=st, lamps=[(1190 - 495, 255, "wall", 0)], tags=["stairs"]))
    # 桥墩石挑台：部件 1 的桥面石檐（顶面亮边 + 一排石托），宽 360，顶面放在 y 300
    k1 = grade(gpt(f(1), (0, 1672)), *ref)
    ledge = k1[426:478, 600:1060].copy()
    ledge[..., 3] = np.where(ledge[..., 3] > 30, 255, 0)
    s = 360.0 / ledge.shape[1]
    img = resize(ledge, s * PX)
    pieces.append(dict(id="ledge_石挑台", file=save(img, "ledge_石挑台"), w=360.0, top=round(300 - 2 / PX, 1), h=round(img.shape[0] / PX, 1),
                       attach=[0.0, 360.0], scale=round(s, 4), relight=True, seam=False, unique=False, tags=["overlay"],
                       stand=[[0.0, 360.0, 300.0, "bridge"]], blocks=[], lamps=[]))


def steps_parts(pieces, ref):
    f = lambda i: sorted(STEPS.glob(f"GPT原图_部件0{i}_*.png"))[0]
    # 船库：二层木廊 = y 300
    k = gpt(f(4), (40, 1640))
    bottom = alpha_bottom(k)
    deck = refine_floor(k, 455, 300, 1300)
    s = (STREET - 300) / (bottom - deck)
    ridge = 68
    pieces.append(piece_from_gpt("s4_船库", grade(k, *ref), s, bottom, attach_src=(0, k.shape[1]),
                                 stand=[(5, 1590, deck, "gallery"), (240, 1350, ridge, "ridge")],
                                 lamps=[(515, 650, "wall", 0)], tags=["house"], seam=False))
    # 河岸尽头：没有台面可对，按三头灯柱高 ≈ 2.5 个人（420）定比例
    k = gpt(f(5), (5, 1660))
    bottom = alpha_bottom(k)
    s = 420.0 / (715 - 45)
    pieces.append(piece_from_gpt("s5_河岸尽头", grade(k, *ref), s, bottom, attach_src=(0, k.shape[1]),
                                 stand=[(860, 1150, 352, "eave")], blocks=[(5, 1545, 705, "steps")],
                                 lamps=[(678, 705, "street", 705 - 150)], tags=["end"], seam=False))


def main():
    near0 = np.asarray(Image.open(S0_SRC).convert("RGBA"), np.float32)
    ref = lab_stats(near0[:, near0.shape[1] - 900:])     # 走廊那一截当调色参考
    pieces = []
    section0(pieces)
    bridge_parts(pieces, ref)
    steps_parts(pieces, ref)
    kit = {"note": __doc__.strip().splitlines()[0], "px_per_world": PX, "street": STREET, "pieces": {p["id"]: p for p in pieces}}
    (LIB / "kit.json").write_text(json.dumps(kit, ensure_ascii=False, indent=1), encoding="utf-8")
    for p in pieces:
        print(f"{p['id']:<16} w {p['w']:>7} top {p['top']:>7} 接口 {p['attach']} 站 {len(p['stand'])} 台 {len(p['blocks'])} 灯 {len(p['lamps'])}")


if __name__ == "__main__":
    main()
