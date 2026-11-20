"""Boss 场地「停船的河口」拼接：沿用雨街素材库和 rain_kit_compose 的拼法，输出到 assets/image/boss_arena/，
布局写 assets/data/boss_arena_layout.json。不碰雨街的成图和布局。
第 2 段现在是用廊道部件压暗的占位，等船库内部的新部件。第 3 段先用现有部件，大景等新构思定了再加。
用法：python -I tools/art/boss_arena_compose.py
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
import rain_kit_compose as rk  # noqa: E402

OUT = ROOT / "assets/image/boss_arena"
LAYOUT = ROOT / "assets/data/boss_arena_layout.json"
RES = "res://assets/image/boss_arena/"

## 战斗区半宽 1400，画布多留一点。两头都有东西挡着，撞穿时才说得通
PLAN = [
    {
        "index": 0, "name": "河口码头", "out": "s1_estuary_wharf.png", "x0": -1620, "x1": 1660,
        "items": [
            {"piece": "s3_水门塔", "x": -1620},
            {"piece": "lamp", "x": -1040},
            {"piece": "s0_吊车码头", "x": -760},
            {"piece": "s5_河岸尽头", "x": -240, "z": -1},
            {"piece": "s4_船库", "x": 660},
        ],
    },
    {
        "index": 1, "name": "船库", "out": "s2_boathouse_temp.png", "x0": -1620, "x1": 1660,
        "items": [
            {"piece": "b1_廊道段_透雾拱", "x": -1620},
            {"piece": "b2_廊道段_铁栅门"},
        ],
    },
    {
        "index": 2, "name": "水门外", "out": "s3_breakwater_near.png", "x0": -1620, "x1": 1660,
        "items": [
            {"piece": "s3_水门塔", "x": -1620},
            {"piece": "lamp", "x": -860},
            {"piece": "lamp", "x": 200},
            {"piece": "s5_河岸尽头", "x": 640, "mirror": True},
        ],
    },
]

## 每段的背景设置（boss_backdrop.gd 读）
ARENA = [
    {"depth": False, "far": True, "rays": 0.14},
    {"interior": True, "floor": [8, 10, 16], "rays": 0.0},
    {"depth": False, "far": True, "rays": 0.14},
]


def clean_lamp(kit):
    """路灯空档是从整图切出来的，带着邻楼的残边：只留路灯本身"""
    src = kit["s0_路灯空档"]
    a = np.asarray(Image.open(rk.LIB / src["file"]).convert("RGBA")).copy()
    a[:, :8, 3] = 0
    a[:, 36:, 3] = 0
    head = int(round((580 - 345 - src["top"]) * kit_px))
    a[:head, :, 3] = 0
    tmp = ROOT / ".runtime/arena/lamp_clean.png"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(a).save(tmp)
    q = dict(src)
    q["id"] = "lamp"
    q["file"] = str(tmp)
    kit["lamp"] = q


def darken_interior(name):
    """第 2 段占位：整体压得很暗，只留吊灯下几团冷光（正式的是船库内部新部件）"""
    p = OUT / name
    a = np.asarray(Image.open(p).convert("RGBA"), np.float32)
    h, w = a.shape[:2]
    light = np.full((h, w), 0.26, np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    for cx in (0.2, 0.5, 0.8):
        light += 0.5 * np.exp(-((xx - cx * w) / (w * 0.09)) ** 2) * np.exp(-((yy - h * 0.72) / (h * 0.36)) ** 2)
    a[..., :3] *= np.clip(light, 0, 1)[..., None] * np.array([0.8, 0.88, 1.0], np.float32)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(p)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    global kit_px
    PX, kit = rk.load_kit()
    kit_px = PX
    clean_lamp(kit)
    rk.ART = OUT
    layout = {
        "note": "Boss 场地「停船的河口」布局，tools/art/boss_arena_compose.py 生成。三段都是平地；arena = 这一段的背景设置（boss_backdrop.gd 读）。",
        "arenaHalf": 2400, "arenaSpacing": 6400,
        "floors": {"street": 580, "f2": 300, "f3": 20, "roof": -260},
        "sections": [{"name": p["name"], "spawns": [[0, 580]]} for p in PLAN],
    }
    for sp in PLAN:
        rk.compose(sp, PX, kit, layout)
    darken_interior("s2_boathouse_temp.png")
    for sec, plan, arena in zip(layout["sections"], PLAN, ARENA):
        sec["art"]["near"] = RES + plan["out"]
        sec["arena"] = arena
        # 小样的地形是平的：只留成图和灯
        sec["platforms"] = []
        sec["blocks"] = []
        sec["slopes"] = []
        sec["foreground"] = []
    LAYOUT.write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("布局已写", LAYOUT.name)


if __name__ == "__main__":
    main()
