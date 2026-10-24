#!/usr/bin/env python3
"""大招切入立绘：用户 GPT 出的洋红底立绘 → 透明 PNG（assets/image/ult/cutin.png）。
用法：python3 tools/art/make_ult_cutin.py 原图.png [输出=assets/image/ult/cutin.png]
抠图：离品红 #FF00FF 的距离 → 透明度（边缘 1～2px 软过渡），半透明边缘减掉混进来的品红（去粉边）。
角色身上的紫色 / 蓝紫色离品红足够远，不会被抠掉。"""
import sys
import numpy as np
from PIL import Image

src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "assets/image/ult/cutin.png"
im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
H, W = im.shape[:2]
d = np.linalg.norm(im - np.array([1.0, 0.0, 1.0]), axis=2)
# 只抠“和画面边缘连通的品红”：剑刃、眼睛里的紫光和背景颜色接近，但不连到边缘，不会被抠掉
import cv2
cand = (d < 0.32).astype(np.uint8)
n, lab = cv2.connectedComponents(cand, connectivity=4)
edge_labels = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bg = np.isin(lab, list(edge_labels))
# 被头发 / 手臂围起来的品红小块：几乎纯品红（剑光、眼睛的紫离纯品红远），面积够大就也算背景
pure = (d < 0.15).astype(np.uint8)
n2, lab2, stats, _ = cv2.connectedComponentsWithStats(pure, connectivity=4)
for i in range(1, n2):
    if stats[i, cv2.CC_STAT_AREA] >= 120:
        bg |= (lab2 == i)
# 边缘过渡带：背景外扩 2px 的那圈按品红距离给半透明，并反解前景色去粉边
ring = cv2.dilate(bg.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool) & ~bg
a = np.ones((H, W), np.float32)
a[bg] = 0.0
a[ring] = np.clip((d[ring] - 0.30) / 0.45, 0.0, 1.0)
fg = (im - np.array([1.0, 0.0, 1.0]) * (1.0 - a[..., None])) / np.maximum(a[..., None], 1e-3)
fg = np.clip(fg, 0.0, 1.0)
rgb = np.where(ring[..., None], fg, im)
rgba = np.dstack([rgb, a])
img = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
bbox = img.getbbox()
img = img.crop(bbox)
img.save(out)
print("saved", out, img.size, "bbox", bbox)
