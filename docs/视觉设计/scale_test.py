# 角色显示尺寸对比测试：仅用于设计判断，不修改任何源图。
import os
from PIL import Image

SRC = r"C:\Users\MECHREVO\Desktop\实际应用到游戏的序列帧"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "art")

FRAMES = [
    (r"在空中下坠期间动画\frame_00001.png", "t-dive"),
    (r"空中普攻第一段\frame_00013.png", "t-thrust"),
    (r"空中普攻第三段\frame_00031.png", "t-arc"),
]

SIZES = [220, 300, 380, 460, 560]


def load(rel):
    im = Image.open(os.path.join(SRC, rel)).convert("RGBA")
    bbox = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    return im.crop(bbox)


def scaled(im, target_h, method=Image.LANCZOS):
    s = target_h / im.height
    return im.resize((max(1, round(im.width * s)), target_h), method)


# ① 带透明通道的成品帧尺寸 -> 供后续合成使用
os.makedirs(OUT, exist_ok=True)
for rel, tag in FRAMES:
    im = load(rel)
    print(tag, "原生裁剪尺寸", im.size)
    for h in SIZES:
        scaled(im, h).save(os.path.join(OUT, f"{tag}-{h}.png"))

# ② 阶梯对比图：同屏并排，看整体比例与可读性
BG = (30, 30, 46, 255)
PAD = 24
sheets = []
for rel, tag in FRAMES:
    im = load(rel)
    items = [scaled(im, h) for h in SIZES]
    w = sum(i.width for i in items) + PAD * (len(items) + 1)
    h = max(i.height for i in items) + PAD * 2
    sheet = Image.new("RGBA", (w, h), BG)
    x = PAD
    for i in items:
        sheet.alpha_composite(i, (x, h - PAD - i.height))
        x += i.width + PAD
    sheets.append(sheet)

W = max(s.width for s in sheets)
H = sum(s.height for s in sheets) + PAD * (len(sheets) - 1)
ladder = Image.new("RGBA", (W, H), (18, 18, 28, 255))
y = 0
for s in sheets:
    ladder.alpha_composite(s, (0, y))
    y += s.height + PAD
ladder.save(os.path.join(OUT, "size-ladder.png"))
print("阶梯图", ladder.size, "对应高度", SIZES)

# ③ 头部特写：判断放大后是否出现模糊/涂抹（取最靠上的一块）
rel, tag = FRAMES[0]
im = load(rel)
head_src = im.crop((int(im.width * 0.45), 0, im.width, int(im.height * 0.28)))
strips = []
for h in SIZES:
    s = h / im.height
    hh = max(1, round(head_src.height * s))
    r = head_src.resize((max(1, round(head_src.width * s)), hh), Image.LANCZOS)
    r = r.resize((r.width * 3, r.height * 3), Image.NEAREST)  # 放大 3 倍便于观察
    strips.append((h, r))
w = sum(r.width for _, r in strips) + PAD * (len(strips) + 1)
h = max(r.height for _, r in strips) + PAD * 2
face = Image.new("RGBA", (w, h), BG)
x = PAD
for _, r in strips:
    face.alpha_composite(r, (x, PAD))
    x += r.width + PAD
face.save(os.path.join(OUT, "size-face.png"))
print("头部特写", face.size, "自左至右", SIZES)
