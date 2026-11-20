"""刀影叠加层（角色动作线，11-06）：原帧减去 Codex 重画的人和剑 → 刀影区域 → 磨圆 → 光线线定稿的四阶硬边紫上色。

刀影的形状、大小、方向和出现在第几帧都照原帧；颜色照光线线 10-31 定稿（recolor_slash_hard.py 的色值）：
外缘白芯 → 浅紫 → 紫 → 深紫，紫带里有和外缘平行的刷痕，内缘干笔锯齿收尾。
原帧里的黄白火花不照搬，换成冷紫白小星芒（设定集 §9：主角特效只用黑影、黑羽、冷紫光刃）。
输出和重画帧同画布、同 pivot 的透明 PNG（叠加层），以及叠好的预览。不碰 battle.json。

用法：python tools/art/slash_overlay.py <输入_排版.json> <重画帧目录(含 manifest.json)> <输出目录>
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]


def hexc(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


CORE = hexc("f4f0ff")
BANDS = [(0.13, hexc("c6b4ff")), (0.50, hexc("a487ff")), (1.01, hexc("7656ea"))]
STRIPE = hexc("6447d6")
CORE_PX = 5.5
CUT_U, CUT_JAG = 0.74, 0.13
MIN_AREA = 900      # 原帧像素：比这小的剩余块不算刀影（重画和原帧没对齐的细边、旧弯剑尖、火花光晕等）
GROW_R = 45         # 从种子往外长全时最多长这么远（防止顺着白皮肤长到脸上）
OPEN_R = 4          # 开运算半径：去掉细长的残边


def disk(r: int) -> np.ndarray:
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return x * x + y * y <= r * r


def smear_mask(orig: np.ndarray, body: np.ndarray, spark: np.ndarray) -> np.ndarray:
    """刀影区域。① 种子：原帧里新人身（外扩 5px）盖不住的亮色大块；
    ② 长全：原帧里“亮且灰白 / 淡紫”的像素中，和种子连在一起的整片都算（刀影压在腿上的部分也找回来）；
    ③ 火花外圈光晕（火花外扩 70px）不算刀影。"""
    a = orig[..., 3] > 24
    rgb = orig[..., :3].astype(int)
    lum = rgb.max(-1)
    sat = rgb.max(-1) - rgb.min(-1)
    halo = ndimage.binary_dilation(spark, structure=disk(70)) if spark.any() else np.zeros_like(a)
    covered = ndimage.binary_dilation(body[..., 3] > 30, structure=disk(5))
    seed = a & ~covered & (lum > 110) & ~halo
    seed = ndimage.binary_opening(seed, structure=disk(OPEN_R))
    lab, n = ndimage.label(seed)
    keep_seed = np.zeros_like(seed)
    for k in range(1, n + 1):
        m = lab == k
        if m.sum() >= MIN_AREA:
            keep_seed |= m
    if not keep_seed.any():
        return keep_seed
    pale = a & (lum > 175) & ((sat < 80) | ((rgb[..., 2] > rgb[..., 1] + 25) & (lum > 200))) & ~halo
    pale = ndimage.binary_closing(pale | keep_seed, structure=disk(2))
    lab, n = ndimage.label(pale)
    hit = np.unique(lab[keep_seed & (lab > 0)])
    grown = np.isin(lab, hit[hit > 0]) & ndimage.binary_dilation(keep_seed, structure=disk(GROW_R))
    return ndimage.binary_fill_holes(grown)


def spark_mask(orig: np.ndarray, body: np.ndarray) -> np.ndarray:
    """黄白火花：颜色和皮肤很像，所以只认新画的人身（外扩 3px）盖不住的地方，再要求成块。"""
    r, g, b, a = (orig[..., i].astype(int) for i in range(4))
    m = (a > 30) & (r > 200) & (g > 170) & (b < 200) & (r - b > 40)
    m &= ~ndimage.binary_dilation(body[..., 3] > 30, structure=disk(3))
    m = ndimage.binary_opening(m, structure=disk(1))
    lab, n = ndimage.label(ndimage.binary_dilation(m, structure=disk(4)))
    keep = np.zeros_like(m)
    for k in range(1, n + 1):
        mm = (lab == k) & m
        if mm.sum() >= 450 and np.median(orig[..., 2][mm]) < 185:
            keep |= mm
    return keep


def paint_smear(mask: np.ndarray, seed: int) -> np.ndarray:
    h, w = mask.shape
    out = np.zeros((h, w, 4), np.float32)
    if not mask.any():
        return out
    sm = ndimage.gaussian_filter(mask.astype(np.float32), 9.0) > 0.5  # 磨圆台阶（原帧刀影的阶梯有 6–10px）
    # 外缘 = 落在凸包边上的边界（弧形刀影的凸侧 = 刃扫过的一边），其余边界 = 内缘
    edge = sm & ~ndimage.binary_erosion(sm)
    ys, xs = np.nonzero(sm)
    from scipy.spatial import ConvexHull
    pts = np.stack([xs, ys], 1).astype(float)
    hull = pts[ConvexHull(pts).vertices]
    hull_img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(hull_img).polygon([tuple(p) for p in hull], outline=255, width=1)
    hull_line = ndimage.binary_dilation(np.asarray(hull_img) > 0, structure=disk(2))
    outer = edge & hull_line
    inner = edge & ~outer
    if not outer.any() or not inner.any():
        outer, inner = edge, edge
    d_o = ndimage.distance_transform_edt(~outer)
    d_i = ndimage.distance_transform_edt(~inner)
    u = d_o / np.maximum(d_o + d_i, 1e-3)
    rng = np.random.default_rng(seed)
    # 干笔：内缘按低频噪声硬切
    noise = ndimage.gaussian_filter(rng.standard_normal((h, w)), 6)
    noise = noise / (np.abs(noise).max() + 1e-6)
    alive = sm & (u < CUT_U + CUT_JAG * noise)
    col = np.zeros((h, w, 3), np.float32)
    lo = 0.0
    for hi, c in BANDS:
        band = (u >= lo) & (u < hi)
        col[band] = c
        lo = hi
    stripes = (np.mod(d_o + 3 * noise, 9.0) < 1.6) & (u > 0.2) & (u < 0.62)
    col[stripes] = STRIPE
    col[d_o < CORE_PX] = CORE
    out[..., :3] = col / 255
    out[..., 3] = alive.astype(np.float32)
    # 最外一圈 1px 抗锯齿
    soft = ndimage.gaussian_filter(out[..., 3], 0.6)
    out[..., 3] = np.where(alive, 1.0, np.clip(soft * 0.8, 0, 1))
    return out


def paint_spark(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    if mask.sum() < 30:
        return np.asarray(out).astype(np.float32) / 255
    cy, cx = ndimage.center_of_mass(mask)
    ys, xs = np.nonzero(mask)
    R = max(xs.max() - xs.min(), ys.max() - ys.min()) * 0.55
    d = ImageDraw.Draw(out)
    for ang, length, width, colr in [(0, 1.0, 0.16, (164, 135, 255)), (90, 1.0, 0.16, (164, 135, 255)),
                                     (45, 0.6, 0.12, (198, 180, 255)), (135, 0.6, 0.12, (198, 180, 255))]:
        t = np.deg2rad(ang)
        dx, dy = np.cos(t) * R * length, np.sin(t) * R * length
        nx, ny = -np.sin(t) * R * width, np.cos(t) * R * width
        d.polygon([(cx - dx, cy - dy), (cx + nx, cy + ny), (cx + dx, cy + dy), (cx - nx, cy - ny)], fill=colr + (255,))
    d.ellipse([cx - R * 0.16, cy - R * 0.16, cx + R * 0.16, cy + R * 0.16], fill=(244, 240, 255, 255))
    return np.asarray(out).astype(np.float32) / 255


def main() -> None:
    lay = json.load(open(sys.argv[1], encoding="utf-8"))
    body_dir = Path(sys.argv[2])
    out = Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    man = json.load(open(body_dir / "manifest.json", encoding="utf-8"))
    pad = int(man["pad"])
    report = []
    for fr, m in zip(lay["frames"], man["frames"]):
        w, h = fr["size"]
        orig = Image.open(ROOT / "assets" / fr["asset"]).convert("RGBA")
        if orig.size != (w, h):
            orig = orig.resize((w, h), Image.LANCZOS)
        O = np.zeros((h + 2 * pad, w + 2 * pad, 4), np.uint8)
        O[pad:pad + h, pad:pad + w] = np.asarray(orig)
        body = np.asarray(Image.open(body_dir / m["file"]).convert("RGBA"))
        sp = spark_mask(O, body)
        sm = smear_mask(O, body, sp)
        layer = paint_smear(sm & ~ndimage.binary_dilation(sp, structure=disk(3)), seed=fr["frame"] * 7 + 3)
        spark = paint_spark(sp)
        a = np.maximum(layer[..., 3], spark[..., 3])
        rgb = np.where(spark[..., 3:4] > 0, spark[..., :3], layer[..., :3])
        img = Image.fromarray((np.dstack([rgb, a]) * 255 + 0.5).astype(np.uint8))
        img.save(out / f"fx_{fr['frame'] + 1:05d}.png")
        report.append({"frame": fr["frame"], "smear_px": int(sm.sum()), "spark_px": int(sp.sum())})
    json.dump({"pad": pad, "frames": report}, open(out / "fx_manifest.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps(report))


if __name__ == "__main__":
    main()
