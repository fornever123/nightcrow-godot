"""给 Remotion 草图准备 public/ 里的素材（在仓库根目录运行）：
  每个画幅一套：<名>bg.png（天空 + 远景成图，和游戏里一致）、<名>strip.png（已经画好的近景成图里落在画幅左边那一段，带透明，GPT 照着往右接）
  layout.json  关卡布局副本（草图读平台、灯）
画幅（世界坐标，宽 2710 = 1672 像素，和左半边同一比例）：
  右半边  x −150 ~ 2560   →  bg.png / strip.png（左边接钟楼右半）
  走廊    x 1290 ~ 4000   →  corridor_bg.png / corridor_strip.png（左边接已经画好的右半边）
用法：python -I tools/art/rain_street_remotion/prep.py
"""
import os, shutil
import numpy as np
from PIL import Image

OUT = "tools/art/rain_street_remotion/public"
W, H = 1672, 941
S = W / 2710
NEAR = "assets/image/rain_street/near_plaza_complete_20261028.png"   # 世界 x −2447 起，同一比例
NEAR_X0 = -2447
FRAMES = {"": (-150, 263, True), "corridor_": (1290, 2560, False)}   # 名 → (画幅左边的世界 x, 接缝 = 已有成图的右边缘, 远景是否用镜像那一张)
os.makedirs(OUT, exist_ok=True)


def bg(flip_far: bool) -> Image.Image:
    sky = Image.open("assets/image/rain_street/sky.png").convert("RGB").resize((W, H), Image.LANCZOS).convert("RGBA")
    far = Image.open("assets/image/rain_street/far_city.png").convert("RGBA")
    if flip_far:
        far = far.transpose(Image.FLIP_LEFT_RIGHT)
    fy = int(round((-781 + 700) * S))
    farc = far.crop((0, -fy, W, H)) if fy < 0 else far
    sky.alpha_composite(farc, (0, max(fy, 0)))
    img = np.asarray(sky.convert("RGB"), np.float32).copy()
    img[min(H, farc.height + max(fy, 0)):] = np.asarray(far, np.float32)[-1, :, :3].mean(0)
    return Image.fromarray(img.astype(np.uint8))


near = Image.open(NEAR).convert("RGBA")
for name, (x0, seam, flip) in FRAMES.items():
    bg(flip).save(f"{OUT}/{name}bg.png")
    near.crop((int(round((x0 - NEAR_X0) * S)), 0, int(round((seam - NEAR_X0) * S)), near.height)).save(f"{OUT}/{name}strip.png")
shutil.copy("assets/data/rain_street_layout.json", f"{OUT}/layout.json")
print("prepared", sorted(os.listdir(OUT)))
