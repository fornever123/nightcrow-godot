"""大招开场素材板：从雨街截图生成 Remotion 开场用的背景板、她的抠图、建筑 / 地面轮廓线。只依赖 numpy + Pillow。

  python tools/art/make_ult_opening_plates.py <SHOT_DIR> [输出目录]

输入（tests/dev/ult_opening_plates.gd 截的）：u01.png（有她）、u01_noher.png（同一帧没她）
输出（默认 E:/00game/ult-slash-remotion/public/opening/）：
  bg.png          = u01_noher.png
  her.png         = 两张差分抠出的她（开运算去掉雨丝，再按扩张后的范围找回细剑）
  edges_wall.png  = 墙根（y < 572）以上的轮廓线（白线 + alpha）
  edges_floor.png = 墙根以下（街面、河面）的轮廓线
墙根 572、她的大致范围按 2026-10-30 的摆位写死；换了摆位要改 GROUND 和 BOX。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

GROUND = 572
BOX = (380, 380, 700, 600)  # x0, y0, x1, y1：她所在的范围


def main() -> None:
    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("E:/00game/ult-slash-remotion/public/opening")
    out.mkdir(parents=True, exist_ok=True)
    a_im = Image.open(src / "u01.png").convert("RGB")
    b_im = Image.open(src / "u01_noher.png").convert("RGB")
    b_im.save(out / "bg.png")
    a = np.asarray(a_im, np.float32) / 255
    b = np.asarray(b_im, np.float32) / 255

    # 她：差分 → 开运算去雨丝 → 扩张后找回细剑
    d = np.abs(a - b).max(axis=2)
    raw = d > 0.05
    x0, y0, x1, y1 = BOX
    box = np.zeros_like(raw)
    box[y0:y1, x0:x1] = True
    raw &= box
    to_im = lambda m: Image.fromarray((m * 255).astype(np.uint8))
    to_m = lambda im: np.asarray(im, np.float32) / 255 > 0.5
    opened = to_m(to_im(raw).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5)))
    grow = to_m(to_im(opened).filter(ImageFilter.MaxFilter(13)))
    m = to_m(to_im(raw & grow).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3)))
    al = np.asarray(to_im(m).filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255
    Image.fromarray((np.dstack([a, al]) * 255).astype(np.uint8), "RGBA").save(out / "her.png")

    # 轮廓线：轻度模糊去雨丝，再取梯度
    g = np.asarray(b_im.convert("L").filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255
    gx = np.zeros_like(g)
    gy = np.zeros_like(g)
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]
    gy[1:-1] = g[2:] - g[:-2]
    e = np.clip((np.hypot(gx, gy) - 0.035) / 0.08, 0, 1)
    wall = e.copy()
    wall[GROUND - 2:] = 0
    floor = e.copy()
    floor[:GROUND + 2] = 0
    for arr, name in ((wall, "edges_wall"), (floor, "edges_floor")):
        one = np.ones_like(arr)
        Image.fromarray((np.dstack([one, one, one, arr]) * 255).astype(np.uint8), "RGBA").save(out / f"{name}.png")
    print("wrote", out)


if __name__ == "__main__":
    main()
