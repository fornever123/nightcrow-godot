#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 1-1A 上下两层街：裁切、缩放、台面 / 灯 / 刷怪点（图上像素）→ 世界坐标，写进第一章布局（2026-11-18）。

用法：python tools/art/ch1_1a_two_level_layout.py
读写：assets/image/rain_street/ch1_1a_two_level/tiles.json（补 crop / scale / street_row）
写：  assets/image/rain_street/ch1_1a_two_level/layout_1a.json（生成脚本 build_ch1_layout_from_paintings.py 也读它）
      assets/data/ch1_shadow_street_layout.json 第 0 段里 1-1A 那一截（-2460..2440，不含入口街 layered 行）

坐标：站立层容器缩放 bg_k=0.75，图上 1 像素 = PX(1.62) 容器单位 = 1.215 世界单位（再乘每张的 scale）。
三张图紧接入口街 N1 裁切右缘（世界 x = 2018.2）往右铺；每张按自己的街面行对齐 FLOOR=580。
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"E:\00game\nightcrow-godot")
DIR = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level"
LAYOUT = ROOT / "assets" / "data" / "ch1_shadow_street_layout.json"
FIRST_X = 4400.0
X0_WORLD = 2018.2          # 入口街 N1 裁切右缘
WPX = 1.215                # 世界单位 / 图像素
FLOOR = 580.0
DECK_GAP = 240             # 三张统一：街面到步廊面 240 像素（v2 B1～B3），各张等比缩放对齐

# v2（用户 11-18 嫌 v1“这么工整一堆马车”后重出）：图上像素；street = 街面第一整行；deck = 步廊面
# crop 两端落在实心墙段 / 通天高墙上；deck_segs = 步廊能站的区段（B2 中间断开一个缺口）
TILES = {
    "B1": {"street": 857, "deck": 597, "crop": [40, 1645],
           "deck_segs": [[300, 1645]],
           "platforms": [[40, 130, 688, "slab"], [440, 1300, 435, "slab"]],   # 楼梯平台、宅邸大阳台
           "lamps": [[210, 690], [540, 330], [1535, 690]],
           "spawns": [[800, "street"], [1000, "deck"], [900, 435]]},
    "B2": {"street": 849, "deck": 590, "crop": [680, 1566],
           "deck_segs": [[680, 765], [880, 1566]],
           "platforms": [[1150, 1410, 412, "slab"]],                         # 半圆阳台
           "lamps": [[830, 680], [1400, 670]],
           "spawns": [[1300, "street"], [1200, "deck"], [1280, 412]]},
    "B3": {"street": 838, "deck": 600, "crop": [20, 1672],
           "deck_segs": [[20, 1040]],
           "platforms": [[145, 490, 465, "slab"]],                           # 窄楼阳台
           "lamps": [[380, 680], [1150, 490], [1600, 540]],
           "spawns": [[650, "street"], [600, "deck"], [300, 465]]},
}


# J1 街口高低分流岔路（C1，接在首段尾 first_x+2440 往右 1520 单位）：高路 = 石阶 → 平台 → 踏步 → 第 430 行过街步道；低路 = 街面穿拱门
J1 = {"code": "C1", "street": 830, "crop": [0, 1302], "x0": FIRST_X + 2440.0, "width": 1520.0,
      "slopes": [[205, 610, 500, 830, "steps"]],                            # 下跑石阶（顺着走上平台）
      "platforms": [[5, 205, 610, "slab"], [170, 262, 520, "slab"],          # 楼梯平台、上跑中间踏步
                    [300, 1255, 430, "slab"], [478, 692, 525, "slab"]],       # 高路：露台 + 过街步道；小楼铁栏阳台
      "lamps": [[528, 640], [810, 510]]}


def r1(v: float) -> float:
    return round(v, 1)


def main() -> None:
    meta = json.loads((DIR / "tiles.json").read_text(encoding="utf-8"))
    x_cursor = X0_WORLD
    platforms, lamps, spawns, decks = [], [], [], []
    for code in TILES:
        t = TILES[code]
        s = DECK_GAP / float(t["street"] - t["deck"])
        c0, c1 = t["crop"]
        meta[code].update({"crop": [c0, c1], "scale": round(s, 4), "street_row": t["street"]})

        def wx(px: float) -> float:
            return x_cursor + (px - c0) * WPX * s

        def wy(py: float) -> float:
            return FLOOR + (py - t["street"]) * WPX * s

        deck_y = wy(t["deck"])
        for d0, d1 in t["deck_segs"]:
            if decks and abs(decks[-1][1] - wx(d0)) < 6.0:
                decks[-1][1] = wx(d1)
            else:
                decks.append([wx(d0), wx(d1)])
        for px0, px1, py, kind in t["platforms"]:
            platforms.append([r1(wx(px0) - FIRST_X), r1(wx(px1) - FIRST_X), r1(wy(py)), kind, {"ch1_hidden": True}])
        for lx, ly in t["lamps"]:
            if c0 + 6 <= lx <= c1 - 6:
                lamps.append([r1(wx(lx) - FIRST_X), r1(wy(ly)), "wall", 0])
        for sx, where in t["spawns"]:
            y = FLOOR if where == "street" else deck_y if where == "deck" else wy(float(where))
            spawns.append([round(wx(sx) - FIRST_X), r1(y)])
        x_cursor = wx(c1)
        print(code, "scale", round(s, 4), "deck_y", r1(deck_y), "end x", r1(x_cursor))
    deck_y = r1(FLOOR - DECK_GAP * WPX)
    for i, (d0, d1) in enumerate(decks):
        platforms.insert(i, [r1(d0 - FIRST_X), r1(d1 - FIRST_X), deck_y, "slab", {"ch1_hidden": True}])
    # J1：缩放让裁切宽度正好填满 1520 单位
    j = J1
    js = j["width"] / ((j["crop"][1] - j["crop"][0]) * WPX)
    meta[j["code"]].update({"crop": j["crop"], "scale": round(js, 4), "street_row": j["street"]})

    def jx(px: float) -> float:
        return j["x0"] + (px - j["crop"][0]) * WPX * js

    def jy(py: float) -> float:
        return FLOOR + (py - j["street"]) * WPX * js

    j_out = {"slopes": [[r1(jx(a) - FIRST_X), r1(jy(b)), r1(jx(c) - FIRST_X), r1(jy(d)), k, {"ch1_hidden": True}] for a, b, c, d, k in j["slopes"]],
             "platforms": [[r1(jx(a) - FIRST_X), r1(jx(b) - FIRST_X), r1(jy(c)), k, {"ch1_hidden": True}] for a, b, c, k in j["platforms"]],
             "lamps": [[r1(jx(a) - FIRST_X), r1(jy(b)), "wall", 0] for a, b in j["lamps"]], "spawns": []}
    print("C1 scale", round(js, 4), j_out)
    (DIR / "layout_j1.json").write_text(json.dumps(j_out, ensure_ascii=False, indent=1), encoding="utf-8")

    # 刷怪点：右 / 左交替（和生成脚本一样）
    right = [p for p in spawns if p[0] >= 0]
    left = [p for p in spawns if p[0] < 0]
    inter = []
    for i in range(max(len(right), len(left))):
        if i < len(right):
            inter.append(right[i])
        if i < len(left):
            inter.append(left[i])
    out = {"note": "1-1A 上下两层街（背景线 11-18，方向丙）：由 tools/art/ch1_1a_two_level_layout.py 从新图量出",
           "x_end": r1(x_cursor), "slopes": [], "platforms": platforms, "lamps": lamps, "spawns": inter}
    (DIR / "layout_1a.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    (DIR / "tiles.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")

    # 写进第一章布局第 0 段：1-1A 那一截（-2460..2440 的非 layered 行）换成新的，入口街 layered 行和 J1 岔路的行不动
    lay = json.loads(LAYOUT.read_text(encoding="utf-8"))
    sec = lay["sections"][0]
    assert sec.get("ch1_code") == "1-1A"

    def keep(row: list, x: float) -> bool:
        tag = row[-1] if row and isinstance(row[-1], dict) else {}
        return bool(tag.get("layered")) or not (-2460.0 <= x < 2440.0)

    sec["slopes"] = [r for r in sec["slopes"] if keep(r, min(float(r[0]), float(r[2])))]
    sec["platforms"] = [r for r in sec["platforms"] if keep(r, float(r[0]))] + platforms
    sec["lamps"] = [r for r in sec["lamps"] if keep(r, float(r[0]))] + lamps
    sec["spawns"] = inter
    # J1 的行在所有“首段”变体里都有（1-1A 第 0 段、1-1B、E1_S0）：2440..3960 那一截换成新的
    def in_j1(x: float) -> bool:
        return 2440.0 <= x < 3960.0
    for d in [sec, lay["routeVariants"]["1-1B"], lay["routeVariants"]["E1_S0"]]:
        d["slopes"] = [r for r in d["slopes"] if not in_j1(min(float(r[0]), float(r[2])))] + j_out["slopes"]
        d["platforms"] = [r for r in d["platforms"] if not in_j1(float(r[0]))] + j_out["platforms"]
        d["lamps"] = [r for r in d["lamps"] if not in_j1(float(r[0]))] + j_out["lamps"]
    LAYOUT.write_text(json.dumps(lay, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
