"""分层试验（11-08）：把 Codex 出的 5 层抠绿、调明暗、加景深，道具按深度拆开，给 tests/dev/preview_rain_layers.gd 用。

用法（仓库根目录）：C:/Python314/python.exe tools/art/rain_layer_test_prep.py
输出 source-art/rain-layer-test-20261108/
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/视觉设计/雨夜河岸街/成图_分层试验"
OUT = ROOT / "source-art/rain-layer-test-20261108"
# 站立层上能站的台面（成图坐标 x0, x1, y）：压暗时亮边没了，补一道冷白湿高光
LEDGES = [(75, 282, 526), (345, 780, 606), (788, 1452, 468)]


def box_mean(a: np.ndarray, r: int) -> np.ndarray:
    """边长 2r+1 的均值模糊（浮点，暗部不起色阶）。"""
    p = np.pad(a, ((r + 1, r + 1), (r + 1, r + 1)) + ((0, 0),) * (a.ndim - 2), mode="edge")
    c = np.cumsum(np.cumsum(p, 0), 1)
    k = 2 * r + 1
    out = c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]
    return out[: a.shape[0], : a.shape[1]] / (k * k)


def key(name: str) -> tuple[np.ndarray, np.ndarray]:
    a = np.asarray(Image.open(SRC / f"Codex原图_{name}.png").convert("RGB")).astype(np.float32) / 255
    alpha = 1 - np.clip((a[..., 1] - np.maximum(a[..., 0], a[..., 2]) - 0.12) / 0.25, 0, 1)
    a[..., 1] = np.minimum(a[..., 1], np.maximum(a[..., 0], a[..., 2]))  # 去绿边
    return a, alpha


def blur(a: np.ndarray, alpha: np.ndarray, r: float) -> tuple[np.ndarray, np.ndarray]:
    """预乘后模糊，边缘不带黑圈。"""
    if r <= 0:
        return a, alpha
    pm = Image.fromarray((np.clip(a * alpha[..., None], 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))
    al = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))
    pa, na = np.asarray(pm).astype(np.float32) / 255, np.asarray(al).astype(np.float32) / 255
    return pa / np.maximum(na[..., None], 1e-3), na


def save(name: str, a: np.ndarray, alpha: np.ndarray, box: tuple[int, int, int, int] | None = None) -> None:
    rgba = np.dstack([np.clip(a, 0, 1), alpha])
    im = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
    if box is not None:
        im = im.crop(box)
    im.save(OUT / f"{name}.png")
    print(name, im.size)


def windows_in(a: np.ndarray, al: np.ndarray) -> list[list[int]]:
    """找出一栋楼上的窗：玻璃比石墙暗得多，连通的暗块按窗棂拼回一扇窗，返回玻璃区 [x0, y0, x1, y1]。"""
    from collections import deque
    lum = a.mean(-1)
    dark = (lum < 0.2) & (al > 0.6)
    h, w = dark.shape
    seen = np.zeros_like(dark)
    boxes = []
    for y0 in range(0, h, 2):
        for x0 in range(0, w, 2):
            if not dark[y0, x0] or seen[y0, x0]:
                continue
            q = deque([(y0, x0)])
            seen[y0, x0] = True
            ys, xs = [], []
            while q:
                y, x = q.popleft()
                ys.append(y)
                xs.append(x)
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny_, nx_ = y + dy, x + dx
                    if 0 <= ny_ < h and 0 <= nx_ < w and dark[ny_, nx_] and not seen[ny_, nx_]:
                        seen[ny_, nx_] = True
                        q.append((ny_, nx_))
            bx = [min(xs), min(ys), max(xs), max(ys)]
            bw, bh = bx[2] - bx[0] + 1, bx[3] - bx[1] + 1
            if 4 <= bw <= 90 and 10 <= bh <= 260 and len(xs) / (bw * bh) > 0.3:
                boxes.append(bx)
    merged = True    # 同一扇窗被窗棂分成几块：横向挨着、竖向大半重叠的拼起来
    while merged:
        merged = False
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                p, q2 = boxes[i], boxes[j]
                ov = min(p[3], q2[3]) - max(p[1], q2[1])
                gap = max(p[0], q2[0]) - min(p[2], q2[2])
                vgap = max(p[1], q2[1]) - min(p[3], q2[3])
                hov = min(p[2], q2[2]) - max(p[0], q2[0])
                if (gap < 9 and ov > 0.5 * min(p[3] - p[1], q2[3] - q2[1])) or (vgap < 9 and hov > 0.5 * min(p[2] - p[0], q2[2] - q2[0])):
                    boxes[i] = [min(p[0], q2[0]), min(p[1], q2[1]), max(p[2], q2[2]), max(p[3], q2[3])]
                    boxes.pop(j)
                    merged = True
                    break
            if merged:
                break
    out = []
    for b in boxes:
        bw, bh = b[2] - b[0], b[3] - b[1]
        frac = float(dark[b[1]:b[3] + 1, b[0]:b[2] + 1].mean())
        if bw < 14 or bh < 30 or bw > 110 or bh > 290 or frac < 0.4:
            continue
        if bw > 90 and bh < 1.8 * bw:      # 宽而不高：多半连着屋顶，不是窗
            continue
        if bw > 1.2 * bh:                  # 窗都是竖的；横的多半是烟囱座
            continue
        if b[3] > 925 and bh < 60:         # 楼脚切边上的碎块
            continue
        out.append(b)
    return out


def mid_houses() -> None:
    """中景专属楼（11-12 生成 A、B 两张）：抠绿，按绿缝切成 6 栋，压到中景的明暗；输出每栋的窗、烟囱口、屋脊给试验场景用。"""
    import json
    ref = np.asarray(Image.open(OUT / "near_a.png")).astype(np.float32) / 255
    ref_lum = float((ref[..., :3].mean(-1) * ref[..., 3]).sum() / ref[..., 3].sum())
    # 每栋：原图、横向范围、烟囱口 x、乌鸦落脚 x（都按原图坐标）
    spec = {
        "mh_a1": ("A", 100, 548, [130, 157], []),
        "mh_a2": ("A", 600, 1052, [], [828]),
        "mh_a3": ("A", 1130, 1606, [1203, 1257, 1352, 1540], [1180, 1215, 1300]),
        "mh_b1": ("B", 10, 660, [70, 97, 538, 588], [280, 330, 380]),
        "mh_b2": ("B", 710, 1125, [], [778, 1030]),
        "mh_b3": ("B", 1165, 1660, [1223, 1250], [1420, 1460]),
    }
    info = {}
    for name, (src, x0, x1, chims, perch) in spec.items():
        a, al = key("中景楼_" + src)
        if src == "B":    # 天桥的玻璃被当成绿底抠掉了：补成暗玻璃
            hole = (al[470:570, 245:415] < 0.5)
            a[470:570, 245:415][hole] = (0.1, 0.12, 0.16)
            al[470:570, 245:415][hole] = 1.0
        a, al = a[:, x0:x1].copy(), al[:, x0:x1].copy()
        wins = windows_in(a, al)
        lum = float((a.mean(-1) * al).sum() / al.sum())
        a = a * (ref_lum / lum) * np.array([0.95, 0.98, 1.08], np.float32)
        a, al = blur(a, al, 0.8)
        save(name, a, al)
        top = lambda x: int(np.argmax(al[:, int(x) - x0] > 0.5))
        info[name] = {
            "wins": wins,
            "chims": [[c - x0, top(c)] for c in chims],
            "perch": [[c - x0, top(c)] for c in perch],
        }
        print(name, len(wins), "windows")
    (OUT / "mid_houses.json").write_text(json.dumps(info), encoding="utf8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    a, al = key("站立层_乙2_修正版")
    a = np.clip(a, 0, 1) ** 0.72  # 修正版压暗过头（亮度中位 0.052），提回来
    a[..., 2] *= 1.05
    # 明暗重点：灯下和门洞一带留着，其余压暗；本来就亮的高光（窗、灯、湿边）不压
    h, w = a.shape[:2]
    yy, xx = np.mgrid[:h, :w].astype(np.float32)
    pool = lambda cx, cy, rx, ry, k: k * np.exp(-(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2))
    moon = np.clip((620 - yy) / 420, 0, 1)    # 越往上月光越多
    m = 0.56 + 0.12 * moon + pool(637, 680, 190, 200, 0.6) + pool(1428, 640, 150, 190, 0.5) + pool(1248, 680, 270, 270, 0.55)
    m = np.clip(np.maximum(m, 0.85 * (yy >= 785)), 0, 1)
    # 笔触只在灯照到的地方：用 AI 笔触重绘版（和乙2 逐像素对齐）的笔触纹理，换掉灯下这一圈的细碎纹理；暗处保持乙2 干净的大块面
    b, _ = key("站立层_笔触重绘")
    bl = np.clip(b, 0, 1).mean(-1) ** 0.9
    lit = np.clip(pool(637, 660, 170, 190, 1.0) + pool(1428, 630, 120, 170, 1.0) + pool(450, 540, 60, 60, 0.5) + pool(1015, 225, 60, 60, 0.5) + pool(1248, 660, 120, 190, 0.45), 0, 1)
    amt = np.clip(0.06 + 0.9 * lit, 0, 1)[..., None]
    low = box_mean(a, 6)
    a = low + (a - low) * (1 - amt) + (bl - box_mean(bl, 6))[..., None] * 0.9 * amt
    keep = np.clip((a.mean(-1) - 0.38) / 0.3, 0, 1)
    a *= (m + (1 - m) * keep)[..., None]
    # 上半部分的冷月光：把檐口、栏杆这些受光的边提出来，楼身不提
    lum8 = Image.fromarray((np.clip(a.mean(-1), 0, 1) * 255).astype(np.uint8))
    edge = np.clip(np.asarray(lum8).astype(np.float32) - np.asarray(lum8.filter(ImageFilter.GaussianBlur(5))).astype(np.float32), 0, 255) / 255
    a += ((edge * 1.9 + 0.016) * moon)[..., None] * np.array([0.72, 0.84, 1.0], np.float32)
    rng = np.random.default_rng(7)
    for x0, x1, y in LEDGES:
        n = np.interp(np.arange(x0, x1), np.arange(x0, x1 + 40, 40), rng.uniform(0.45, 1.0, (x1 + 40 - x0) // 40 + 1 if (x1 - x0) % 40 == 0 else (x1 - x0) // 40 + 2)[: len(np.arange(x0, x1 + 40, 40))])
        for dy, k in ((-1, 0.35), (0, 0.8), (1, 0.45)):
            col = np.array([0.62, 0.70, 0.84], np.float32)
            row = a[y + dy, x0:x1]
            a[y + dy, x0:x1] = row + (col - row) * (k * n)[..., None] * al[y + dy, x0:x1][..., None]
    save("stand", a, al)

    a, al = key("中近景层")
    a, al = blur(a * 0.75, al, 1.0)
    # 按楼缝切成三块，放在不同深度，互相遮挡
    save("near_a", a, al, (0, 0, 570, 941))
    save("near_b", a, al, (570, 0, 1130, 941))
    save("near_c", a, al, (1130, 0, 1672, 941))
    # 门洞里那两排：朝中间的一边淡出，不留笔直的切边
    for name, x0, x1 in (("arch_b", 570, 1130), ("arch_c", 1130, 1672)):
        fade = al.copy()
        fade[:, x1 - 90:x1] *= np.linspace(1.0, 0.0, 90, dtype=np.float32)
        save(name, a, fade, (x0, 0, x1, 941))

    a, al = key("中景层")
    a, al = blur(a * 0.5, al, 1.6)
    save("mid", a, al)
    mid_houses()

    a, al = key("远景层")
    a, al = blur(a * 0.9, al, 2.4)
    save("far", a, al)

    # 天际线钟楼（11-12 生成，用户选的方向 A）：楼身压成接近夜空的剪影，钟室拱窗的月光雾留着当记忆点，侧面表盘压成暗朱红，底部渐隐进雾
    a, al = key("天际线钟楼")
    a, al = a[:, 560:1110], al[:, 560:1110]
    lum = a.mean(-1)
    red = np.clip((a[..., 0] - np.maximum(a[..., 1], a[..., 2]) * 1.5 - 0.05) / 0.12, 0, 1)
    win = np.clip((lum - 0.32) / 0.25, 0, 1) * (1 - red)
    body = a * np.array([0.62, 0.66, 0.74], np.float32)
    lit = a * np.array([0.6, 0.66, 0.78], np.float32)
    dial = np.array([0.3, 0.07, 0.055], np.float32) * (a[..., :1] / max(float(a[..., 0].max()), 1e-3)) ** 1.2 * 1.25
    a = body * (1 - win[..., None]) + lit * win[..., None]
    a = a * (1 - red[..., None]) + dial * red[..., None]
    h = al.shape[0]
    al = al * np.clip((h * 0.97 - np.arange(h)) / (h * 0.32), 0, 1)[:, None]
    a, al = blur(a, al, 1.3)
    save("sky_tower", a, al)

    a, al = key("前景层")
    a, al = blur(a * 0.35, al, 3.0)
    save("fg_eave", a, al, (0, 0, 350, 415))
    chain = al.copy()
    chain[:245] = 0
    chain[:, :1490] = 0
    save("fg_chain", a, chain, (1490, 245, 1640, 660))
    crane = al.copy()
    crane[245:] = 0
    crane[:, :860] = 0
    a2, al2 = key("前景层")  # 吊车要认得出来：比其它前景亮一点、虚得少一点
    crane = al2.copy()
    crane[245:] = 0
    crane[:, :860] = 0
    a2, crane = blur(a2 * 0.6, crane, 1.6)
    save("fg_crane", a2, crane, (860, 0, 1640, 260))
    save("fg_rail", a, al, (1270, 720, 1672, 941))


if __name__ == "__main__":
    main()
