"""雨夜河岸街 · 钟楼广场左半：把用户 GPT 生成的分层原图加工成游戏用的运行图。
原图只读不改（docs/视觉设计/雨夜河岸街/分层_v9.2/GPT原图_*），结果写到 assets/image/rain_street/。

  近景 near_plaza_left.png  ← GPT原图_近景_01.webp（纯绿底），按标杆图 成图_v9.2/GPT原图_v9.2_01.webp 补修
  远景 far_city.png         ← GPT原图_远景_02.webp（纯绿底）
  天空 sky.png              ← GPT原图_天空_02.webp

近景的处理（每一步的原因见 分层_v9.2/素材账本.md）：
  1. 按“局部背景绿”估计透明度并预乘还原——背景绿不是常数，用常数反解会把暗绿边算成紫色（紫色留给主角）
  2. GPT 把贴墙阳台栏杆的空隙也填了绿（后面其实是楼自己的墙）等几处：整块取标杆像素
  3. 真镂空的细铁件和推车：按标杆图“比局部背景暗”补回透明度
  4. 烟囱帽颜色退回标杆（GPT 改成了陶红，红色只留给钟楼）；山尖后多出的远处竖杆改透明
  5. 去青边：对着透明的 4px 边缘带取标杆颜色，透明度不变
用法：python -I tools/art/build_rain_street_layers.py
"""
import os
import numpy as np, cv2
from PIL import Image

SRC = "docs/视觉设计/雨夜河岸街/分层_v9.2"
BENCH = "docs/视觉设计/雨夜河岸街/成图_v9.2/GPT原图_v9.2_01.webp"
OUT = "assets/image/rain_street"
W, H = 1672, 941


def load(p):
    im = Image.open(p).convert("RGB")
    return np.asarray(im.resize((W, H), Image.LANCZOS) if im.size != (W, H) else im, np.float32)


def key(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    gx = g - np.maximum(r, b)
    sure = ((gx / (g + 8.0)) > 0.55).astype(np.float32)
    bg = np.zeros_like(rgb)
    wsum = np.zeros(sure.shape, np.float32)
    for sig in (4, 12, 40):   # 由近到远补齐背景估计
        w = cv2.GaussianBlur(sure, (0, 0), sig)
        est = np.dstack([cv2.GaussianBlur(rgb[..., i] * sure, (0, 0), sig) for i in range(3)]) / np.maximum(w, 1e-4)[..., None]
        take = (wsum < 0.05) & (w > 0.02)
        bg[take] = est[take]
        wsum[take] = w[take]
    bg[wsum < 0.05] = (0, 255, 0)
    bgx = np.maximum(bg[..., 1] - np.maximum(bg[..., 0], bg[..., 2]), 40.0)
    a = np.clip(1.0 - gx / bgx, 0.0, 1.0)
    a[sure > 0] = 0.0
    a[a < 0.06] = 0.0
    fg = (rgb - (1 - a[..., None]) * bg) / np.maximum(a[..., None], 0.15)
    fg = np.clip(fg, 0, 255)
    fg[..., 1] = np.minimum(fg[..., 1], np.maximum(fg[..., 0], fg[..., 2]) + 6)
    return np.dstack([fg, a * 255]).astype(np.float32)


def edge_band(alpha):
    op = (alpha > 250).astype(np.uint8)
    return (cv2.dilate(1 - op, np.ones((9, 9), np.uint8)) > 0) & (alpha > 0)


# 整块取标杆、不透明（像素坐标，图 1672×941）
FACADE = [(30, 580, 290, 624), (100, 415, 215, 452),                            # 货栈 二层铸铁廊、三层小阳台
          (292, 400, 540, 438), (292, 576, 522, 612), (335, 218, 500, 250),     # 会馆 三层、二层、屋顶石栏
          (622, 578, 948, 624),                                                 # 商住楼 二层铸铁花栏
          (1352, 232, 1672, 272), (1352, 405, 1672, 450), (1352, 583, 1672, 624),   # 钟楼三层环廊
          (126, 316, 190, 414),      # 货栈阁楼门洞（GPT 画进了尖顶天际线）
          (378, 326, 454, 412),      # 会馆三层花格窗（GPT 画亮了）
          (1356, 8, 1388, 50)]       # 钟楼左上壁柱（被绿色反光误抠的洞）
DARKMAT = [(518, 576, 632, 616), (1118, 642, 1168, 698), (505, 728, 612, 792)]   # 铁桥栏杆、挂牌铁架、推车
RECOLOR = [(240, 62, 292, 92), (615, 145, 675, 175), (900, 152, 960, 182)]       # 三组烟囱帽


def build_near(bench):
    near = key(load(f"{SRC}/GPT原图_近景_01.webp"))
    fm = np.zeros((H, W), np.float32)
    for x0, y0, x1, y1 in FACADE:
        fm[y0:y1, x0:x1] = 1.0
    fm = cv2.GaussianBlur(fm, (0, 0), 1.2)
    near[..., :3] = near[..., :3] * (1 - fm[..., None]) + bench * fm[..., None]
    near[..., 3] = np.maximum(near[..., 3], fm * 255)
    lum = bench.mean(2)
    bgl = cv2.dilate(cv2.GaussianBlur(lum, (0, 0), 1.0), np.ones((9, 9), np.uint8))
    for x0, y0, x1, y1 in DARKMAT:
        am = np.clip((bgl[y0:y1, x0:x1] - lum[y0:y1, x0:x1] - 14) / 25.0, 0, 1) * 255
        take = am > near[y0:y1, x0:x1, 3]
        near[y0:y1, x0:x1, :3][take] = bench[y0:y1, x0:x1][take]
        near[y0:y1, x0:x1, 3][take] = am[take]
    for x0, y0, x1, y1 in RECOLOR:
        near[y0:y1, x0:x1, :3] = bench[y0:y1, x0:x1]
    yy, xx = np.mgrid[0:40, 136:184]
    near[0:40, 136:184, 3][yy < 4 + np.abs(xx - 160) * 1.6] = 0
    band = edge_band(near[..., 3])
    near[band, :3] = bench[band]
    return np.clip(near, 0, 255).astype(np.uint8)


def build_far():
    far = key(load(f"{SRC}/GPT原图_远景_02.webp"))
    band = edge_band(far[..., 3])
    far[band, 1] = np.minimum(far[band, 1], (far[band, 0] + far[band, 2]) / 2 + 4)   # 青边 → 冷蓝灰
    # 原图宽 1670、放大到 1672 时最外两列会发亮；游戏里镜像平铺，接缝处要和里面一样
    far[:, :3] = far[:, 3:4]
    far[:, -3:] = far[:, -4:-3]
    return np.clip(far, 0, 255).astype(np.uint8)


def teal(rgba):
    a = rgba[..., 3]
    e = (a > 0) & (a < 250)
    r, g, b = [rgba[..., i].astype(np.int32) for i in range(3)]
    return int((e & (g > r + 20) & (g >= b - 5)).sum())


def purple(rgba):
    r, g, b, a = [rgba[..., i].astype(np.int32) for i in range(4)]
    return int(((r > g + 25) & (b > g + 25) & (a > 77)).sum())


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bench = load(BENCH)
    near = build_near(bench)
    far = build_far()
    Image.fromarray(near).save(f"{OUT}/near_plaza_left.png")
    Image.fromarray(far).save(f"{OUT}/far_city.png")
    Image.fromarray(load(f"{SRC}/GPT原图_天空_02.webp").astype(np.uint8)).save(f"{OUT}/sky.png")
    print("near", near.shape, "青边", teal(near), "偏紫", purple(near))
    print("far ", far.shape, "青边", teal(far), "偏紫", purple(far))
