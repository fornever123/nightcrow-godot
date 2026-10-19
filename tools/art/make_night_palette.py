#!/usr/bin/env python3
"""夜景调色板（第三轮节点 16，见 docs/HANDOFF-试玩版.md §14）。

用法：python3 tools/art/make_night_palette.py 截图1.png 截图2.png ... [--n 64]
截图用 tests/dev/scene_shot.gd 拍（BG=1 NOQ=1：只拍背景、退后调色和 2×2 像素化打开、量化关掉），
多拍几个位置，覆盖星空、月亮、城堡灯火、海面月光带、灯笼和萤火。
本脚本把截图按 2×2 像素块取样，用 k-means 求 n 色，另外保证几种“点缀色”（灯笼火、萤火、月白）一定在调色板里，
再按亮度排序，写进 assets/shaders/night_pixel.gdshader 的 @@PALETTE@@ … @@END@@ 之间。
"""
import sys, re, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHADER = os.path.join(ROOT, 'assets/shaders/night_pixel.gdshader')
# 点缀色：面积很小、但一定要保住的颜色（不然 k-means 会把它们并进大块的蓝色里）
ACCENTS = [
    (1.00, 0.86, 0.56),   # 灯笼火芯
    (0.97, 0.66, 0.34),   # 灯笼暖光
    (0.84, 0.98, 0.70),   # 萤火
    (0.93, 0.95, 1.00),   # 月白
]


def main():
    args = sys.argv[1:]
    n = 64
    if '--n' in args:
        i = args.index('--n'); n = int(args[i + 1]); del args[i:i + 2]
    px = []
    for f in args:
        a = np.asarray(Image.open(f).convert('RGB'))
        px.append(a[::2, ::2].reshape(-1, 3))
    px = np.concatenate(px)
    im = Image.fromarray(px[None, :, :])
    k = n - len(ACCENTS)
    q = im.quantize(colors=k, method=Image.Quantize.MEDIANCUT, kmeans=8, dither=Image.Dither.NONE)
    pal = np.array(q.getpalette()[:k * 3], np.float32).reshape(-1, 3) / 255.0
    pal = np.concatenate([pal, np.array(ACCENTS, np.float32)])
    lum = pal @ np.array([0.299, 0.587, 0.114], np.float32)
    pal = pal[np.argsort(lum)]
    body = 'const int PAL_N = %d;\nconst vec3 PAL[%d] = vec3[%d](\n' % (len(pal), len(pal), len(pal))
    body += ',\n'.join('\tvec3(%.4f, %.4f, %.4f)' % tuple(c) for c in pal) + ');\n'
    s = open(SHADER, encoding='utf-8').read()
    s = re.sub(r'(// @@PALETTE@@\n).*?(// @@END@@)', lambda m: m.group(1) + body + m.group(2), s, flags=re.S)
    open(SHADER, 'w', encoding='utf-8').write(s)
    # 误差报告：量化前后平均色差
    sub = px[::17]
    d = ((sub[:, None, :].astype(np.float32) / 255.0 - pal[None, :, :]) ** 2 * [0.3, 0.5, 0.2]).sum(-1)
    print('palette', len(pal), 'colors; mean err %.5f' % float(d.min(1).mean()))


if __name__ == '__main__':
    main()
