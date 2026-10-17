# 把源序列帧裁掉空白并缩到游戏显示尺寸的 2 倍，仅用于设计样张占位。
# 源图不动，输出为新建文件。
import sys, os
from PIL import Image

SRC = r"C:\Users\MECHREVO\Desktop\实际应用到游戏的序列帧"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "art")
TARGET_H = 440  # 1080p 下角色约 220 px 高，样张为 2 倍

    (r"在空中下坠期间动画\frame_00001.png", "hero-dive.png"),
    (r"空中普攻第一段\frame_00013.png",      "hero-thrust.png"),
    (r"空中普攻第三段\frame_00031.png",      "hero-arc.png"),
    (r"空中普攻第二段\frame_00022.png",      "hero-slash2.png"),
]

os.makedirs(OUT, exist_ok=True)
for rel, name in JOBS:
    im = Image.open(os.path.join(SRC, rel)).convert("RGBA")
    bbox = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    im = im.crop(bbox)
    scale = TARGET_H / im.height
    im = im.resize((max(1, round(im.width * scale)), TARGET_H), Image.LANCZOS)
    im.save(os.path.join(OUT, name))
    print(name, im.size)
