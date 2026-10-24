"""生成大招「千刃」的题字图（assets/image/ult/title.png）。
字体：Ma Shan Zheng（马善政毛笔楷书，SIL OFL 1.1，许可证见 assets/image/ult/OFL-MaShanZheng.txt）。
字体文件本身不进仓库（只用来生成这张图）：python3 tools/art/make_ult_title.py 字体.ttf
构成：墨色飞白笔刷带（程序生成）+ 白字 + 紫色描边 + 右下角一枚小印章。"""
import sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = sys.argv[1] if len(sys.argv) > 1 else "MaShanZheng-Regular.ttf"
OUT = sys.argv[2] if len(sys.argv) > 2 else "assets/image/ult/title.png"
W, H = 1280, 560
rng = np.random.default_rng(7)

# ---- 墨色笔刷带：斜着一笔扫过，起笔浓、收笔飞白（只沿笔刷方向出丝，不交叉）
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
cx, cy, ang = W * 0.5, H * 0.55, -0.06
u = (xx - cx) * math.cos(ang) + (yy - cy) * math.sin(ang)        # 沿笔刷方向
v = -(xx - cx) * math.sin(ang) + (yy - cy) * math.cos(ang)        # 垂直方向
half_len = W * 0.49
t = np.clip((u + half_len) / (2 * half_len), 0, 1)                # 0 起笔 → 1 收笔
prof = np.maximum(np.sin(np.pi * np.clip(t * 1.05 + 0.02, 0, 1)), 0) ** 0.45
width = 128 * (0.35 + 0.65 * prof) * (1.0 - 0.25 * t)
_en = np.convolve(rng.normal(0, 1, 2400), np.hanning(90) / np.hanning(90).sum(), mode="same") * 60.0
edge_noise = np.interp(u, np.linspace(-W, W, 2400), _en) * (0.4 + t)
inside = (np.abs(v) < width + edge_noise) & (u > -half_len) & (u < half_len)
# 飞白：每根“刷毛”是一条沿笔刷方向的细带；每根毛在某个位置之后断开（越靠收笔断得越多）
NB = 240
bristle = np.clip(((v / np.maximum(width, 1)) * 0.5 + 0.5) * NB, 0, NB - 1).astype(np.int32)
break_at = rng.uniform(0.45, 1.25, NB)          # 这根毛从哪里开始断
gap_seed = rng.random((NB, 300))
gap = gap_seed[bristle, np.clip((t * 299).astype(np.int32), 0, 299)]
dry = (t > break_at[bristle]) & (gap < np.clip((t - break_at[bristle]) * 3.0, 0, 0.9))
dry |= (t < 0.04) & (gap < 0.5)
mask = inside & ~dry
alpha = mask.astype(np.float32)
shade = 0.75 + 0.25 * np.interp(v, np.linspace(-200, 200, 120), rng.random(120))
band = np.zeros((H, W, 4), np.float32)
band[..., 0] = 16 / 255.0 * shade
band[..., 1] = 11 / 255.0 * shade
band[..., 2] = 26 / 255.0 * shade
band[..., 3] = alpha * 0.94
img = Image.fromarray((band * 255).astype(np.uint8), "RGBA")
img = img.filter(ImageFilter.GaussianBlur(0.5))

# ---- 字：外圈紫光 + 深墨细描边 + 白→浅紫竖向渐变
font = ImageFont.truetype(FONT, 380)
pos = (W * 0.5, H * 0.5)
def text_mask(stroke):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).text(pos, "千刃", font=font, anchor="mm", fill=255, stroke_width=stroke, stroke_fill=255)
    return m
glow_m = text_mask(14).filter(ImageFilter.GaussianBlur(16))
glow = Image.new("RGBA", (W, H), (164, 135, 255, 0)); glow.putalpha(glow_m.point(lambda a: int(a * 0.9)))
edge = Image.new("RGBA", (W, H), (27, 21, 38, 255)); edge.putalpha(text_mask(7))
grad = np.zeros((H, W, 4), np.uint8)
k = np.linspace(0, 1, H)[:, None]
grad[..., 0] = (255 - 34 * k).astype(np.uint8); grad[..., 1] = (252 - 42 * k).astype(np.uint8); grad[..., 2] = (242 + 13 * k).astype(np.uint8)
fill = Image.fromarray(grad, "RGBA"); fill.putalpha(text_mask(0))
img = Image.alpha_composite(img, glow)
img = Image.alpha_composite(img, edge)
img = Image.alpha_composite(img, fill)

# ---- 印章：右下角朱红小方印（唯一的暖色点缀）
seal = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
sd = ImageDraw.Draw(seal)
sd.rounded_rectangle((4, 4, 92, 92), 8, fill=(200, 52, 44, 235))
sf = ImageFont.truetype(FONT, 62)
sd.text((48, 50), "影", font=sf, anchor="mm", fill=(255, 236, 220, 255))
na = np.array(seal).astype(np.float32)
na[..., 3] *= (rng.random(na.shape[:2]) > 0.06)
seal = Image.fromarray(na.astype(np.uint8), "RGBA").rotate(-6, resample=Image.BICUBIC, expand=True)
img.alpha_composite(seal, (int(W * 0.80), int(H * 0.66)))
img.save(OUT)
print("saved", OUT, img.size)
