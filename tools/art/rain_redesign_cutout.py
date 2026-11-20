#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 画面重构样板屏：把 Codex 绿底原图抠成透明层，长条层做成左右无缝循环（2026-11-17）。

用法：python -I tools/art/rain_redesign_cutout.py
读：docs/_当前分支草稿/背景线/画面重构_20261117/codex原图/L*.png
写：assets/image/rain_street/redesign_20261117/*.png 与 layers.json（每层尺寸、内容上下沿、亮边行）
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"E:\00game\nightcrow-godot")
SRC = ROOT / "docs" / "_当前分支草稿" / "背景线" / "画面重构_20261117" / "codex原图"
DST = ROOT / "assets" / "image" / "rain_street" / "redesign_20261117"

# 代号 -> 是否做左右循环、循环交叉融合宽度比例
LOOP = {"L2_far": 0.14, "L3_mid": 0.14, "L5_deck": 0.10, "L6_lower": 0.14}


def key_green(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    spill = g - np.maximum(r, b)              # 绿得多明显
    a = 1.0 - np.clip((spill - 0.10) / 0.28, 0.0, 1.0)
    # 去溢色：绿通道不许高过红蓝的较大者
    out = rgb.copy()
    out[..., 1] = np.minimum(g, np.maximum(r, b) * 1.02)
    # 半透明边缘再压一点亮度，避免发亮的绿边变灰边
    edge = (a > 0.02) & (a < 0.98)
    out[edge] *= 0.85
    # 挖空处周围 8 像素内：绿色常混进湿街面成了青色，按 (r+b)/2 压绿（不碰远离挖空处的真绿植）
    hole = a < 0.5
    near = hole.copy()
    for _ in range(8):
        n2 = near.copy()
        n2[1:] |= near[:-1]; n2[:-1] |= near[1:]; n2[:, 1:] |= near[:, :-1]; n2[:, :-1] |= near[:, 1:]
        near = n2
    band = near & ~hole
    avg = (out[..., 0] + out[..., 2]) * 0.5
    g2 = np.where(band, np.minimum(out[..., 1], avg), out[..., 1])
    out[..., 1] = g2
    return out, a


def purple_ratio(rgb: np.ndarray, a: np.ndarray) -> float:
    import colorsys  # noqa: F401  # 只做粗算
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    purple = (b > g + 0.06) & (r > g + 0.06) & (sat > 0.25) & (mx > 0.15) & (a > 0.5)
    return float(purple.sum()) / max(1.0, float((a > 0.5).sum()))


def make_loop(rgba: np.ndarray, frac: float) -> np.ndarray:
    h, w, _ = rgba.shape
    ov = int(w * frac)
    t = np.linspace(0.0, 1.0, ov)[None, :, None]
    t = t * t * (3 - 2 * t)
    left = rgba[:, :ov].copy()
    right = rgba[:, w - ov:].copy()
    # 预乘后混合，免得透明处混出黑边
    def pm(x):
        y = x.copy(); y[..., :3] *= y[..., 3:4]; return y
    mix = pm(right) * (1 - t) + pm(left) * t
    a = mix[..., 3:4]
    mix[..., :3] = np.where(a > 1e-4, mix[..., :3] / np.maximum(a, 1e-4), 0)
    out = np.concatenate([mix, rgba[:, ov:w - ov]], axis=1)
    return out


def split_items(rgba: np.ndarray, min_area: int = 300, mask: np.ndarray | None = None, k: int = 4) -> list[tuple[int, int, int, int]]:
    """在缩小 k 倍的蒙版上做连通块，返回每块的原图包围盒（默认蒙版 = 不透明处）。"""
    from collections import deque
    m = (rgba[::k, ::k, 3] > 0.3) if mask is None else mask[::k, ::k]
    h, w = m.shape
    seen = np.zeros_like(m)
    boxes = []
    for y in range(h):
        for x in range(w):
            if not m[y, x] or seen[y, x]:
                continue
            q = deque([(y, x)]); seen[y, x] = True
            y0 = y1 = y; x0 = x1 = x; n = 0
            while q:
                cy, cx = q.popleft(); n += 1
                y0 = min(y0, cy); y1 = max(y1, cy); x0 = min(x0, cx); x1 = max(x1, cx)
                for ny in range(max(cy - 1, 0), min(cy + 2, h)):
                    for nx in range(max(cx - 1, 0), min(cx + 2, w)):
                        if m[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True; q.append((ny, nx))
            if n >= min_area // (k * k) * 4:
                boxes.append((x0 * k, y0 * k, min((x1 + 1) * k, rgba.shape[1]), min((y1 + 1) * k, rgba.shape[0])))
    return sorted(boxes)


def full_row(rgba: np.ndarray) -> int:
    """从上往下第一行“整行都不透明”的地方 = 街面（上面有巷缝、门洞挖空，街面才是整行实心）。"""
    cover = (rgba[..., 3] > 0.5).mean(axis=1)
    rows = np.where(cover > 0.985)[0]
    return int(rows[0]) if len(rows) else -1


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    meta = {}
    for fp in sorted(list(SRC.glob("L*.png")) + list(SRC.glob("N*.png"))):
        code = fp.stem
        if "_" not in code or code.count("_") > 1:
            continue  # 跳过旧版改名的备份
        pim = Image.open(fp).convert("RGB")
        src_size = list(pim.size)
        if code.startswith("N") and pim.size[1] != 941:
            # 新近景：按高度缩到和原站立层同高（楼层比例跟着高度走），宽度按原比例
            pim = pim.resize((round(pim.size[0] * 941 / pim.size[1]), 941), Image.LANCZOS)
        im = np.asarray(pim).astype(np.float32) / 255.0
        info = {"src": fp.name, "src_size": src_size}
        if code == "L1_sky":
            rgba = np.concatenate([im, np.ones(im.shape[:2] + (1,), np.float32)], axis=2)
        else:
            rgb, a = key_green(im)
            rgba = np.concatenate([rgb, a[..., None]], axis=2)
            info["purple"] = round(purple_ratio(rgb, a), 5)
        if code in LOOP:
            rgba = make_loop(rgba, LOOP[code])
            info["loop"] = True
        a = rgba[..., 3]
        rows = np.where(a.max(axis=1) > 0.5)[0]
        info["content_top"] = int(rows[0]) if len(rows) else 0
        info["content_bottom"] = int(rows[-1]) if len(rows) else rgba.shape[0] - 1
        if code == "L5_deck":
            # 街面亮边：从内容顶往下 60 行里，找平均亮度最高的一行
            lum = (rgba[..., :3].mean(axis=2) * a)
            top = info["content_top"]
            band = lum[top:top + 80].mean(axis=1)
            info["rim_row"] = int(top + int(np.argmax(band)))
        if code == "L7_fg":
            items = []
            for i, (x0, y0, x1, y1) in enumerate(split_items(rgba)):
                crop = rgba[y0:y1, x0:x1]
                Image.fromarray((np.clip(crop, 0, 1) * 255).astype(np.uint8), "RGBA").save(DST / f"fg_{i}.png")
                items.append({"file": f"fg_{i}.png", "box": [x0, y0, x1, y1]})
            info["items"] = items
        if code != "L1_sky":
            r, g, b, al = rgba[..., 0], rgba[..., 1], rgba[..., 2], rgba[..., 3]
            warm = (r > 0.5) & (r > b + 0.18) & (al > 0.5)
            lights = []
            for (x0, y0, x1, y1) in split_items(rgba, min_area=8, mask=warm, k=2):
                lights.append([round((x0 + x1) / 2), round((y0 + y1) / 2), max(x1 - x0, y1 - y0)])
            info["lights"] = lights
        if code.startswith("N"):
            info["street_row"] = full_row(rgba)
            # 街面和街下墙：巷口的绿会倒映在湿石板上，整条压绿（这一带没有绿植）
            y0 = max(0, info["street_row"] - 30)
            seg = rgba[y0:, :, :3]
            seg[..., 1] = np.minimum(seg[..., 1], (seg[..., 0] + seg[..., 2]) * 0.5 + 0.02)
        info["size"] = [rgba.shape[1], rgba.shape[0]]
        Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(DST / f"{code}.png")
        meta[code] = info
        print(code, info)
    # 旧站立层（近处保持原样）：只量一下暖灯位置，给样板屏配灯光
    for code in ["stand", "stand_entry"]:
        fp = ROOT / "assets" / "image" / "rain_street" / "layered" / f"{code}.png"
        rgba = np.asarray(Image.open(fp).convert("RGBA")).astype(np.float32) / 255.0
        r, g, b, al = rgba[..., 0], rgba[..., 1], rgba[..., 2], rgba[..., 3]
        warm = (r > 0.55) & (r > b + 0.18) & (al > 0.5)
        lights = [[round((x0 + x1) / 2), round((y0 + y1) / 2), max(x1 - x0, y1 - y0)]
                  for (x0, y0, x1, y1) in split_items(rgba, min_area=8, mask=warm, k=2)]
        meta[code] = {"src": f"layered/{code}.png", "size": [rgba.shape[1], rgba.shape[0]], "lights": lights, "street_row": full_row(rgba)}
        print(code, meta[code]["size"], len(lights), "lights")
    (DST / "layers.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
