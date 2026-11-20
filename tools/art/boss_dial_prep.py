"""Boss 大表盘：把 Codex 样板拆成「玻璃里的景」和「表盘铁框」两层，去掉辐条和指针（指针改由代码画），红环压暗。
输入：docs/视觉设计/Boss战/钟室_20261113/大表盘_原图.png
输出：assets/image/boss_duanchao/dial/dial_glass.png、dial_frame.png、dial_meta.json
用法：py -3.10 -I tools/art/boss_dial_prep.py
"""
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/视觉设计/Boss战/钟室_20261113/大表盘_原图.png"
OUT = ROOT / "assets/image/boss_duanchao/dial"
DBG = ROOT / ".runtime/arena/dial"

CX, CY, R = 833.0, 436.0, 406.0      # 玻璃圆（拟合）
HUB = (836.0, 425.0)                 # 轮毂
LEDGE = 748                          # 台面上沿
HANDS = [((836, 425), (801, -10)), ((836, 425), (856, 770))]


def seg_dist(xx, yy, a, b):
    ax, ay = a
    bx, by = b
    vx, vy = bx - ax, by - ay
    t = np.clip(((xx - ax) * vx + (yy - ay) * vy) / (vx * vx + vy * vy), 0, 1)
    return np.hypot(xx - (ax + t * vx), yy - (ay + t * vy))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    DBG.mkdir(parents=True, exist_ok=True)
    rgb = np.asarray(Image.open(SRC).convert("RGB"))
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    h, w = bgr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    rr = np.hypot(xx - CX, yy - CY)
    g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)

    # 1) 玻璃里的暗线（辐条、指针、轮毂）→ 补成云
    local = cv2.GaussianBlur(g, (0, 0), 9)
    dark = (g < local - 10) | (g < 70)
    inside = rr < R - 3
    mask = (dark & inside).astype(np.uint8)
    hand_d = np.minimum(*[seg_dist(xx, yy, a, b) for a, b in HANDS])
    mask |= ((hand_d < 16) & (g < local + 4) & (yy < LEDGE + 2) & (rr < R + 40)).astype(np.uint8)
    mask |= (np.hypot(xx - HUB[0], yy - HUB[1]) < 62).astype(np.uint8)
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
    mask[yy >= LEDGE - 1] = 0
    clean = cv2.inpaint(bgr, mask * 255, 9, cv2.INPAINT_TELEA)
    # 补过的地方再轻轻糊一下，接缝不显
    soft = cv2.GaussianBlur(clean, (0, 0), 3)
    mk = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 3)[..., None]
    clean = (clean * (1 - mk) + soft * mk).astype(np.uint8)
    cv2.imwrite(str(DBG / "mask.png"), mask * 255)

    # 2) 玻璃层：圆内（台面以下也留着，代码会被台面挡住）
    glass = cv2.cvtColor(clean, cv2.COLOR_BGR2RGB)
    a = np.clip((R + 2 - rr) / 4.0, 0, 1)
    ga = np.dstack([glass, (a * 255).astype(np.uint8)])
    x0, y0 = int(CX - R - 4), max(0, int(CY - R - 4))
    x1, y1 = int(CX + R + 4), min(h, int(CY + R + 4))
    Image.fromarray(ga[y0:y1, x0:x1]).save(OUT / "dial_glass.png")

    # 3) 铁框层：挖掉玻璃，红环压暗去饱和；指针越过红环的部分也补掉
    hsv = cv2.cvtColor(clean, cv2.COLOR_BGR2HSV).astype(np.float32)
    redm = ((hsv[..., 0] < 12) | (hsv[..., 0] > 165)) & (hsv[..., 1] > 50)
    redm = cv2.GaussianBlur(redm.astype(np.float32), (0, 0), 1.2)
    hsv2 = hsv.copy()
    hsv2[..., 1] *= 1 - 0.42 * redm
    hsv2[..., 2] *= 1 - 0.52 * redm
    frame = cv2.cvtColor(np.clip(hsv2, 0, 255).astype(np.uint8), cv2.COLOR_HSV2RGB)
    fa = np.clip((rr - (R - 2)) / 3.0, 0, 1)
    fa[yy >= LEDGE - 2] = 1.0
    Image.fromarray(np.dstack([frame, (fa * 255).astype(np.uint8)])).save(OUT / "dial_frame.png")
    Image.fromarray(cv2.cvtColor(clean, cv2.COLOR_BGR2RGB)).save(DBG / "clean_full.png")

    meta = {
        "note": "tools/art/boss_dial_prep.py 生成。坐标都是 dial_frame.png 的像素。",
        "size": [w, h], "center": [CX, CY], "radius": R, "hub": list(HUB), "ledge_row": LEDGE,
        "glass_origin": [x0, y0],
    }
    (OUT / "dial_meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("ok", w, h, (x0, y0, x1, y1))


if __name__ == "__main__":
    main()
