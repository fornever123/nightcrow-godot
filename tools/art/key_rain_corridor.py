"""雨夜河岸街走廊（x 2560 ~ 4000）近景抠图：用 Remotion 草图的遮罩模式当三分图，GrabCut 细抠边缘，接到钟楼广场近景右边。

用法（仓库根目录）：
  cd tools/art/rain_street_remotion && npx remotion still Corridor <matte.png> --props='{"showLines":false,"showOpenings":true,"matte":true}'
  python -I tools/art/key_rain_corridor.py <matte.png>

输出 source-art/rain-corridor-20261030/：
  near_corridor_keyed.png      走廊这一块（钟楼广场近景的像素网格，宽 889）
  near_street0_candidate.png   钟楼广场近景 + 走廊拼好的整张（3978×941），接入前的候选
"""
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GPT = ROOT / "docs/视觉设计/雨夜河岸街/成图_走廊/GPT原图_走廊v3_01.webp"
PLAZA = ROOT / "assets/image/rain_street/near_plaza_complete_20261028.png"
OUT = ROOT / "source-art/rain-corridor-20261030"

COL_OFF = 2306  # 钟楼广场近景第 c 列 = 成图第 c − 2306 列（模板匹配 2306.25）
ROW_OFF = 3  # 钟楼广场近景第 r 行 = 成图第 r + 3 行（楼体匹配 1.5，但成图右段街面比左段低 2 px，按街面对齐；台面因此比布局高约 3 世界单位）
QUAY_BOTTOM = 849  # 成图里河岸护墙底边（再往下是河，游戏里由水面 shader 画）
FADE = 24  # 接缝处街面 / 护墙的交叉过渡宽度
# 草图里没有、成图里有的东西：交给 GrabCut 判断的框（成图坐标 x0, y0, x1, y1）
EXTRA = [(738, 230, 800, 312)]  # 门楼左角的石像鬼（GPT 画得比草图大、往左越过接缝）
# 一定是近景的框：廊道屋顶顶边那道虚线亮边，GrabCut 会把它抠成断的
# 门楼垛口下面那段女儿墙：后面远景被月光照亮，颜色跟墙接近，GrabCut 会挖出深缺口
SOLID = [(1100, 280, 1672, 300), (845, 250, 1040, 272), (1028, 240, 1045, 272)]
# 接缝左边、钟楼广场近景透明（天空）的地方，用走廊这张补（石像鬼越过了接缝）
SEAM_OVER = (740, 230, 783, 320)


def main(matte_path: str) -> None:
    g = np.asarray(Image.open(GPT).convert("RGB")).astype(np.float32)
    h, w = g.shape[:2]
    m = np.asarray(Image.open(matte_path).convert("L")) > 128
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)).astype(bool)
    m[QUAY_BOTTOM:] = False

    # 三分图：草图轮廓往里收 = 一定是近景，往外扩 = 一定是天空 / 远景，中间那一圈交给 GrabCut
    fg = cv2.erode(m.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))).astype(bool)
    near = cv2.dilate(m.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (19, 19))).astype(bool)
    gc = np.full((h, w), cv2.GC_BGD, np.uint8)
    gc[near] = cv2.GC_PR_BGD
    gc[near & m] = cv2.GC_PR_FGD
    gc[fg] = cv2.GC_FGD
    for x0, y0, x1, y1 in EXTRA:
        box = gc[y0:y1, x0:x1]
        box[box == cv2.GC_BGD] = cv2.GC_PR_BGD
    gc[QUAY_BOTTOM:] = cv2.GC_BGD
    bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
    cv2.grabCut(g.astype(np.uint8), gc, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
    hard = np.isin(gc, (cv2.GC_FGD, cv2.GC_PR_FGD)).astype(np.float32)
    for x0, y0, x1, y1 in SOLID:
        hard[y0:y1, x0:x1] = 1
    # 去掉 GrabCut 留在天空里的小碎块
    n, lab, stats, _ = cv2.connectedComponentsWithStats(hard.astype(np.uint8), 8)
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] < 60:
            hard[lab == i] = 0

    # 边缘软化一像素，只在那一圈里
    band = near & ~fg
    for x0, y0, x1, y1 in EXTRA:
        band[y0:y1, x0:x1] = True
    a = hard.copy()
    a[band] = cv2.GaussianBlur(hard, (0, 0), 0.7)[band]
    a[QUAY_BOTTOM:] = 0

    # 边缘去色：按“局部背景色”把混进来的天空色减掉
    bgm = (a < 0.02).astype(np.float32)
    num = cv2.GaussianBlur(g * bgm[..., None], (0, 0), 6)
    den = cv2.GaussianBlur(bgm, (0, 0), 6)[..., None]
    b = num / np.maximum(den, 1e-4)
    edge = (a > 0.05) & (a < 0.95)
    f = g.copy()
    f[edge] = np.clip((g[edge] - (1 - a[edge, None]) * b[edge]) / a[edge, None], 0, 255)

    rgba = np.dstack([f, a * 255]).astype(np.float32)

    plaza = np.asarray(Image.open(PLAZA).convert("RGBA")).astype(np.float32)
    ph, pw = plaza.shape[:2]
    out_w = COL_OFF + w  # 成图右边缘 = 世界 x 4000
    canvas = np.zeros((ph, out_w, 4), np.float32)
    # 成图挪到钟楼广场近景的像素网格
    shifted = np.zeros((ph, w, 4), np.float32)
    shifted[: h - ROW_OFF] = rgba[ROW_OFF:]
    canvas[:, :pw] = plaza
    canvas[:, pw:] = shifted[:, pw - COL_OFF:]

    # 接缝左边那一小块：钟楼广场近景是天空的地方，叠上走廊这张抠出来的东西
    x0, y0, x1, y1 = SEAM_OVER
    for c in range(x0 + COL_OFF, x1 + COL_OFF):
        src = shifted[y0 - ROW_OFF:y1 - ROW_OFF, c - COL_OFF]
        dst = canvas[y0 - ROW_OFF:y1 - ROW_OFF, c]
        sky = dst[:, 3] < 10
        dst[sky] = src[sky]
    # 接缝：两边都实的地方（街面、护墙）交叉过渡，其余保持钟楼广场原样
    for k in range(FADE):
        c = pw - FADE + k
        t = (k + 1) / (FADE + 1)
        src = shifted[:, c - COL_OFF]
        both = (plaza[:, c, 3] > 250) & (src[:, 3] > 250)
        canvas[both, c, :3] = plaza[both, c, :3] * (1 - t) + src[both, :3] * t

    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.round(canvas[:, pw:]).astype(np.uint8), "RGBA").save(OUT / "near_corridor_keyed.png")
    Image.fromarray(np.round(canvas).astype(np.uint8), "RGBA").save(OUT / "near_street0_candidate.png")
    print("canvas", canvas.shape, "tile", out_w - pw)


if __name__ == "__main__":
    main(sys.argv[1])
