"""雨夜河岸街 · 近景拼接：按拼接方案（tools/art/rain_street_compose.json）把素材库里的单件拼成每一段的近景成图，光影统一生成，
再把成图位置、可站面、石台、灯位（和方案里给的出生点）写回 assets/data/rain_street_layout.json。

素材库由 rain_kit_library.py 生成（docs/视觉设计/雨夜河岸街/素材库/kit.json + 单件 PNG）。
方案里每一段：
  index / out：布局里第几段、输出文件名（assets/image/rain_street/ 下，新文件名，不覆盖旧成图）
  x0 / x1：画布左右（世界 x，相对该段封印中心）；y0：画布上沿（不给就按最高的件自动定）
  items：从左到右的件。{"piece": id, "x": 左接口的世界 x（不给就接在上一件的右接口上）, "mirror": 左右翻, "z": 画的先后（默认按顺序）}
  join_ledges：在相邻两件都标了 seam 的接缝（桥墩）上各放一块这个件（石挑台），{"piece": id, "y": 台面 y}
  spawns / foreground：给了就覆盖布局里的
  reflections：额外的街面倒影 [x, [r, g, b]]（例如警署的蓝灯）
光影：GPT 部件（relight）右边缘补月光冷亮边、墙脚冷蓝湿反光；GPT 部件之间的接缝压暗一点；街面和河岸护墙用第 1 段成图里裁出来的街面错位平铺，
再按每盏灯补暖色湿倒影。原成图切出来的件光已经画好，不再加。
用法：python -I tools/art/rain_kit_compose.py [段号 ...]   （不给段号就全拼）
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
from build_rain_bridge_kit import over  # noqa: E402

LIB = ROOT / "docs/视觉设计/雨夜河岸街/素材库"
PLAN = ROOT / "tools/art/rain_street_compose.json"
LAYOUT = ROOT / "assets/data/rain_street_layout.json"
ART = ROOT / "assets/image/rain_street"
S0_SRC, S0_X0, S0_Y0 = ART / "near_plaza_corridor_20261030.png", -2447.0, -698.0
STREET, BOTTOM, WATER = 580.0, 826.0, 665
LAMP_WARM = [70, 48, 22]


def load_kit():
    kit = json.loads((LIB / "kit.json").read_text(encoding="utf-8"))
    return kit["px_per_world"], kit["pieces"]


def mirrored(p):
    """件的元数据左右翻（图片在用的时候翻）"""
    w = p["w"]
    q = dict(p)
    q["attach"] = [round(w - p["attach"][1], 1), round(w - p["attach"][0], 1)]
    q["stand"] = [[round(w - b, 1), round(w - a, 1), y, s] for a, b, y, s in p["stand"]]
    q["blocks"] = [[round(w - b, 1), round(w - a, 1), y, s] for a, b, y, s in p["blocks"]]
    q["lamps"] = [[round(w - x, 1), y, k, r] for x, y, k, r in p["lamps"]]
    return q


def street_strip(PX, width, rng):
    """第 1 段成图的街面 + 河岸护墙（世界 y 574 ~ 665），避开钟楼底下（朱红倒影），去掉原来的暖灯倒影，错位平铺到 width 像素"""
    near0 = np.asarray(Image.open(S0_SRC).convert("RGBA"), np.float32)
    ry = lambda wy: int(round((wy - S0_Y0) * PX))
    strip = near0[ry(574):ry(WATER)].copy()
    warm = (strip[..., 0] > strip[..., 2] + 10) & (strip[..., 0] > 90)
    lum = strip[..., :3].mean(2, keepdims=True)
    strip[..., :3] = np.where(warm[..., None], lum * np.array([0.8, 0.88, 1.08]), strip[..., :3])
    cx = lambda wx: int(round((wx - S0_X0) * PX))
    sources = [(cx(-2440), cx(-420)), (cx(420), cx(3990))]
    out = np.zeros((strip.shape[0], width, 4), np.float32)
    x = 0
    while x < width:
        a, b = sources[int(rng.integers(0, len(sources)))]
        w = int(rng.integers(220, 480))
        s0 = int(rng.integers(a, b - w))
        piece = strip[:, s0:s0 + w].copy()
        piece[:, :6, 3] *= np.linspace(0, 1, 6)[None, :] if x > 0 else 1   # 接头 6 像素淡入，看不出硬边
        over(out, piece, x, 0)
        x += w - 6
    return out


def compose(sec_plan, PX, kit, layout):
    X0, X1 = float(sec_plan["x0"]), float(sec_plan["x1"])
    # ---- 摆位：左接口对上一件的右接口（或方案给的 x）
    placed, cursor = [], None
    for n, it in enumerate(sec_plan["items"]):
        p = kit[it["piece"]]
        meta = mirrored(p) if it.get("mirror") else p
        ax = float(it["x"]) if "x" in it else cursor
        left = ax - meta["attach"][0]
        cursor = left + meta["attach"][1]
        placed.append(dict(it=it, p=p, meta=meta, left=left, z=it.get("z", n), dy=0.0))
    joins = [(a, b) for a, b in zip(placed, placed[1:]) if a["meta"]["seam"] and b["meta"]["seam"]]
    jl = sec_plan.get("join_ledges")
    if jl:
        lp = kit[jl["piece"]]
        for a, _ in joins:
            jx = a["left"] + a["meta"]["attach"][1]
            placed.append(dict(it={}, p=lp, meta=lp, left=jx - lp["w"] / 2, z=1000, dy=float(jl["y"]) - lp["stand"][0][2]))
    tops = [q["meta"]["top"] + q["dy"] for q in placed]
    Y0 = float(sec_plan.get("y0", np.floor((min(tops) - 20) / 10) * 10))
    W, H = int(round((X1 - X0) * PX)), int(round((BOTTOM - Y0) * PX))
    px = lambda wx: int(round((wx - X0) * PX))
    py = lambda wy: int(round((wy - Y0) * PX))

    canvas = np.zeros((H, W, 4), np.float32)
    relit = np.zeros((H, W), np.float32)      # GPT 部件占的地方（亮边、湿反光只加在这里）
    for q in sorted(placed, key=lambda q: q["z"]):
        img = np.asarray(Image.open(LIB / q["p"]["file"]).convert("RGBA"), np.float32)
        if q["it"].get("mirror"):
            img = img[:, ::-1].copy()
        x, y = px(q["left"]), py(q["meta"]["top"] + q["dy"])
        over(canvas, img, x, y)
        if q["meta"]["relight"]:
            m = np.zeros((H, W, 4), np.float32)
            over(m, np.dstack([np.zeros_like(img[..., :3]), img[..., 3:]]), x, y)
            relit = np.maximum(relit * (1 - m[..., 3] / 255.0), m[..., 3] / 255.0)
        else:
            m = np.zeros((H, W, 4), np.float32)
            over(m, np.dstack([np.zeros_like(img[..., :3]), img[..., 3:]]), x, y)
            relit *= 1 - m[..., 3] / 255.0

    # ---- 光影（只在 GPT 部件上）
    a = canvas[..., 3] / 255.0
    rgb = canvas[..., :3]
    solid = (a > 0.5).astype(np.float32)
    right_open = np.zeros_like(solid)
    right_open[:, :-3] = (solid[:, :-3] > 0) & (solid[:, 3:] == 0)
    rim = cv2.GaussianBlur(cv2.dilate(right_open, np.ones((1, 4), np.uint8)), (0, 0), 1.2) * solid * relit
    rim[py(345):] *= 0.3
    rgb += np.array([150, 168, 200], np.float32) * rim[..., None] * 0.45
    yy = np.arange(H, dtype=np.float32)[:, None]
    band = np.clip((yy - py(STREET - 70)) / max(py(STREET) - py(STREET - 70), 1), 0, 1) ** 1.6
    rgb += np.array([18, 30, 52], np.float32) * (band * a * relit)[..., None]
    xx = np.arange(W, dtype=np.float32)[None, :]
    for q, _ in joins:
        c = (q["left"] + q["meta"]["attach"][1] - X0) * PX
        rgb *= 1 - 0.10 * np.exp(-((xx - c) / 30.0) ** 2)[..., None] * a[..., None]
    canvas[..., :3] = np.clip(rgb, 0, 255)

    # ---- 街面 + 河岸护墙，楼盖在上面
    rng = np.random.default_rng(int(sec_plan["index"]) * 7 + 3)
    out = np.zeros_like(canvas)
    over(out, street_strip(PX, W, rng), 0, py(574))
    over(out, canvas, 0, 0)

    # ---- 平台 / 石台 / 灯（件内坐标 → 段内世界坐标）
    plats, blocks, lamps = [], [], []
    for q in placed:
        L, dy = q["left"], q["dy"]
        plats += [[round(L + x0, 1), round(L + x1, 1), round(y + dy, 2), s] for x0, x1, y, s in q["meta"]["stand"]]
        blocks += [[round(L + x0, 1), round(L + x1, 1), round(y + dy, 2), s] for x0, x1, y, s in q["meta"]["blocks"]]
        lamps += [[round(L + x, 1), round(y + dy, 2), k, r] for x, y, k, r in q["meta"]["lamps"]]
    refl = [[l[0], LAMP_WARM] for l in lamps] + sec_plan.get("reflections", [])
    for lx, col in refl:
        if not X0 <= lx <= X1:
            continue
        g = np.exp(-((np.arange(W) - px(lx)) / 26.0) ** 2)[None, :] * np.exp(-((np.arange(py(574), py(606)) - py(590)) / 9.0) ** 2)[:, None]
        out[py(574):py(606), :, :3] = np.clip(out[py(574):py(606), :, :3] + g[..., None] * np.array(col, np.float32), 0, 255)

    outp = ART / sec_plan["out"]
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(outp)
    sec = layout["sections"][int(sec_plan["index"])]
    sec["art"] = {"near": "res://assets/image/rain_street/" + outp.name, "x0": X0, "y0": Y0, "width": round(W / PX, 2), "water_y": WATER}
    sec["platforms"] = sorted(plats, key=lambda p: (-p[2], p[0]))
    sec["blocks"] = sorted(blocks, key=lambda p: p[0])
    sec["lamps"] = lamps
    if "spawns" in sec_plan:
        sec["spawns"] = sec_plan["spawns"]
    if "foreground" in sec_plan:
        sec["foreground"] = sec_plan["foreground"]
    print(f"段 {sec_plan['index']} {sec.get('name')}: {outp.name} {W}x{H}, y0 {Y0}, 件 {len(placed)}, 平台 {len(plats)}, 石台 {len(blocks)}, 灯 {len(lamps)}")
    for q in placed:
        print(f"   {q['p']['id']:<14} {'翻' if q['it'].get('mirror') else '  '} x {q['left']:8.1f} ~ {q['left'] + q['p']['w']:8.1f}")


def check(layout):
    """交接文档 §4 的校验：顶头、能上去；出生点要站在面上"""
    ok = True
    for si, sec in enumerate(layout["sections"]):
        surf = [(a, b, y) for a, b, y, _ in sec["platforms"]] + [(a, b, y) for a, b, y, _ in sec["blocks"]]
        bad = [(A, B) for A in surf for B in surf if A is not B and A[1] > B[0] and A[0] < B[1] and 0 < B[2] - A[2] < 188]
        unreach = [(a, b, y) for a, b, y, k in sec["platforms"] if not any(
            (B[2] > y and B[2] - y <= 300 and max(0, max(a, B[0]) - min(b, B[1])) <= 380) or
            (abs(B[2] - y) <= 60 and (B[0], B[1], B[2]) != (a, b, y) and max(0, max(a, B[0]) - min(b, B[1])) <= 450)
            for B in surf + [(-1e9, 1e9, 580)])]
        spawn_bad = [s for s in sec["spawns"] if not (abs(s[1] - 580) < 1 or any(a <= s[0] <= b and abs(y - s[1]) < 1 for a, b, y in surf))]
        print(si, "headroom:", bad or "ok", " reach:", unreach or "ok", " spawns:", spawn_bad or "ok")
        ok = ok and not bad and not unreach and not spawn_bad
    return ok


def dump(o, ind=0):
    """和布局文件原来的写法一致：缩进 2，最里层的数组写在一行"""
    pad, pad1 = "  " * ind, "  " * (ind + 1)
    if isinstance(o, dict):
        return "{\n" + ",\n".join(f"{pad1}{json.dumps(k, ensure_ascii=False)}: {dump(v, ind + 1)}" for k, v in o.items()) + f"\n{pad}}}"
    if isinstance(o, list) and any(isinstance(v, (dict, list)) for v in o):
        return "[\n" + ",\n".join(pad1 + dump(v, ind + 1) for v in o) + f"\n{pad}]"
    return json.dumps(o, ensure_ascii=False)


def main():
    PX, kit = load_kit()
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    only = {int(a) for a in sys.argv[1:]}
    for sp in plan["sections"]:
        if not only or int(sp["index"]) in only:
            compose(sp, PX, kit, layout)
    if not check(layout):
        print("校验没过：布局没有写回")
        sys.exit(1)
    LAYOUT.write_text(dump(layout) + "\n", encoding="utf-8")
    print("布局已写回", LAYOUT.name)


if __name__ == "__main__":
    main()
