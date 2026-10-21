#!/usr/bin/env python3
"""检查 GPT 出的定调图/背景图：颜色统计、锁色（蓝→青灰）、放入真实主角、眯眼测试、角色身后加薄雾示意。
用法：python3 tools/art/keyart_check.py 图.png 输出目录 [脚底y 角色x 角色高 去掉区域x0,y0,x1,y1]
"""
import cv2, numpy as np, sys, os
SPR = os.path.join(os.path.dirname(__file__), '../../assets/image/characters/nightcrow/idle/frame_0001.png')
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
FEET = int(sys.argv[3]) if len(sys.argv) > 3 else 662
CX = int(sys.argv[4]) if len(sys.argv) > 4 else 700
CH = int(sys.argv[5]) if len(sys.argv) > 5 else 185
EX = [int(v) for v in sys.argv[6].split(',')] if len(sys.argv) > 6 else None
im = cv2.imread(src).astype(np.float32) / 255; H, W = im.shape[:2]

def stats(img, tag):
    hsv = cv2.cvtColor((img * 255).astype(np.uint8), cv2.COLOR_BGR2HSV_FULL).astype(np.float32)
    h = hsv[..., 0] / 255 * 360; s = hsv[..., 1] / 255; v = hsv[..., 2] / 255
    m = np.ones((H, W), bool)
    if EX: m[EX[1]:EX[3], EX[0]:EX[2]] = False
    p = lambda k: round(100 * (k & m).sum() / m.sum(), 1)
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY); lap = np.abs(cv2.Laplacian(g, cv2.CV_32F))
    z = (slice(max(0, FEET - int(CH * 1.5)), FEET - 4), slice(0, W))
    print(f'[{tag}] 饱和蓝 {p((h > 200) & (h < 245) & (s > 0.3) & (v > 0.12))}%  紫/蓝紫 {p((h >= 245) & (h < 300) & (s > 0.25) & (v > 0.12))}%  '
          f'平均饱和 {s[m & (v > 0.12)].mean():.2f}  角色身后区 明度 {g[z].mean():.2f} 细节 {lap[z].mean():.3f}（天空上方 {lap[0:H // 5].mean():.3f}）')

def lock(img, tgt=208.0, keep=0.4):
    """冷色相转到青灰、饱和度降到 keep 倍；暖色只轻降。"""
    L, a, b = cv2.split(cv2.cvtColor(img, cv2.COLOR_BGR2LAB))
    C = np.hypot(a, b); hue = np.degrees(np.arctan2(b, a)) % 360; cool = np.clip(-b / 8, 0, 1)
    hue2 = hue + (((tgt - hue + 180) % 360) - 180) * 0.85 * cool
    C2 = C * (1 - (1 - keep) * cool) * (1 - 0.1 * (1 - cool))
    lab = cv2.merge([L, (C2 * np.cos(np.radians(hue2))).astype(np.float32), (C2 * np.sin(np.radians(hue2))).astype(np.float32)])
    return np.clip(cv2.cvtColor(lab, cv2.COLOR_LAB2BGR), 0, 1)

def haze(img, top, bot, col=(0.44, 0.39, 0.29), amt=0.42):
    """角色身后一条薄雾带（示意：分层后雾只在中景和步道之间）。col 为 BGR。"""
    y = np.arange(H, dtype=np.float32)[:, None]
    w = np.clip((y - top) / 60, 0, 1) * np.clip((bot - y) / 25, 0, 1) * amt
    soft = cv2.GaussianBlur(img, (0, 0), 1.4)
    o = img * (1 - w[..., None] * 0.6) + soft * (w[..., None] * 0.6)
    return o * (1 - w[..., None]) + np.array(col, np.float32) * w[..., None]

spr = cv2.imread(SPR, -1).astype(np.float32) / 255
ys, xs = np.where(spr[..., 3] > 0.1); spr = cv2.flip(spr[ys.min():ys.max() + 1, xs.min():xs.max() + 1], 1)
def paste(base):
    s = CH / spr.shape[0]; sp = cv2.resize(spr, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    h, w = sp.shape[:2]; o = base.copy(); a = sp[..., 3:]
    sh = np.zeros((H, W), np.float32); cv2.ellipse(sh, (CX + w // 2, FEET - 2), (int(w * 0.42), 6), 0, 0, 360, 1, -1)
    o *= (1 - 0.45 * cv2.GaussianBlur(sh, (0, 0), 4))[..., None]                       # 脚下软影子
    o[FEET - h:FEET, CX:CX + w] = sp[..., :3] * a + o[FEET - h:FEET, CX:CX + w] * (1 - a); return o
sq = lambda X: cv2.GaussianBlur(cv2.cvtColor((X * 255).astype(np.uint8), cv2.COLOR_BGR2GRAY), (0, 0), 6)
A = im; B = lock(im); Cc = haze(B, FEET - int(CH * 1.9), FEET - 6)
for X, t in ((A, '原图'), (B, '锁色'), (Cc, '锁色+薄雾')): stats(X, t)
P = [paste(X) for X in (A, B, Cc)]
for X, n in zip(P, ('orig', 'locked', 'locked_haze')):
    cv2.imwrite(f'{out}/{n}.jpg', (X * 255).astype(np.uint8), [cv2.IMWRITE_JPEG_QUALITY, 90])
cv2.imwrite(f'{out}/squint.jpg', cv2.resize(np.vstack([np.hstack([sq(P[0]), sq(P[2])])]), (W, H // 2)))
x0 = max(0, CX - 420); y0 = max(0, FEET - CH * 2); crop = lambda X: X[y0:FEET + 60, x0:x0 + 900]
cv2.imwrite(f'{out}/compare.jpg', (np.vstack([crop(P[0]), crop(P[2])]) * 255).astype(np.uint8), [cv2.IMWRITE_JPEG_QUALITY, 92])
print('ok')
