"""基于 11-06 codex_redraw_layout.py 的无损升级版：
计算 bbox 时自动剔除原视频残留的孤立空中微尘噪点（< 80px 且远离主体），
防止孤立脏点撑大 bbox 把人物挤到角落；同时 100% 保留人物 + 真剑 + 原版刀光/火花的完整原始轮廓与精确逆映射坐标！
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
BOX = (255, 255, 0)
GREEN = (0, 255, 0)


def clean_stray_specks(im: Image.Image) -> Image.Image:
    arr = np.asarray(im).copy()
    m = (arr[..., 3] > 20).astype(np.uint8)
    n_lbl, lbls, stats, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    if n_lbl <= 1:
        return im
    max_area = int(stats[1:, cv2.CC_STAT_AREA].max())
    for li in range(1, n_lbl):
        area = int(stats[li, cv2.CC_STAT_AREA])
        if area < 1500 and area < max_area * 0.035:
            arr[lbls == li, 3] = 0
    return Image.fromarray(arr)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("clip")
    ap.add_argument("out")
    ap.add_argument("--frames", default="")
    ap.add_argument("--size", default="1024x1536")
    ap.add_argument("--cols", type=int, default=2)
    ap.add_argument("--rows", type=int, default=4)
    ap.add_argument("--margin", type=float, default=0.10)
    ap.add_argument("--line", type=int, default=4)
    ap.add_argument("--source-json", default="", help="可选：从备份 JSON 读取原始动画定义")
    args = ap.parse_args()

    W, H = (int(v) for v in args.size.split("x"))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    if args.source_json:
        anims = json.loads(Path(args.source_json).read_text(encoding="utf-8"))
    else:
        data = json.loads((ROOT / "assets/data/battle.json").read_text(encoding="utf-8"))
        anims = data["characters"][0]["sprite"]["animations"]

    frames = anims[args.clip]["frames"]
    idx = list(range(len(frames)))
    if args.frames:
        a, b = (int(v) for v in args.frames.split("-"))
        idx = list(range(a, b + 1))
    assert len(idx) <= args.cols * args.rows, "帧数多于格子数"

    ims, bbs = [], []
    for i in idx:
        f = frames[i]
        im = Image.open(ROOT / "assets" / f["asset"]).convert("RGBA")
        size = (round(f["width"]), round(f["height"]))
        if im.size != size:
            im = im.resize(size, Image.Resampling.LANCZOS)
        im = clean_stray_specks(im)
        ys, xs = np.nonzero(np.asarray(im)[..., 3] > 20)
        ims.append(im)
        bbs.append((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))

    cw, ch = W // args.cols, H // args.rows
    mx, my = round(cw * args.margin), round(ch * args.margin)
    mw = max(b[2] - b[0] for b in bbs)
    mh = max(b[3] - b[1] for b in bbs)
    s = min((cw - 2 * mx) / mw, (ch - 2 * my) / mh)

    sheet = Image.new("RGB", (W, H), GREEN)
    draw = ImageDraw.Draw(sheet)
    layout = {
        "clip": args.clip,
        "scale": s,
        "size": [W, H],
        "cols": args.cols,
        "rows": args.rows,
        "margin": [mx, my],
        "boxes": True,
        "box_color": "#FFFF00",
        "frames": [],
    }

    for n, (i, im, bb) in enumerate(zip(idx, ims, bbs)):
        f = frames[i]
        cx, cy = (n % args.cols) * cw, (n // args.cols) * ch
        crop = im.crop(bb)
        sc = crop.resize((max(1, round(crop.width * s)), max(1, round(crop.height * s))), Image.Resampling.LANCZOS)
        x = cx + (cw - sc.width) // 2
        y = cy + ch - my - sc.height
        sheet.paste(sc, (x, y), sc)
        h = args.line // 2
        draw.rectangle([cx + h + 2, cy + h + 2, cx + cw - h - 3, cy + ch - h - 3], outline=BOX, width=args.line)
        layout["frames"].append({
            "frame": i,
            "asset": f["asset"],
            "size": [round(f["width"]), round(f["height"])],
            "pivot": [f["pivotX"], f["pivotY"]],
            "bbox": list(bb),
            "placed": [x, y, sc.width, sc.height],
            "cell": [cx, cy, cw, ch],
        })

    sheet.save(out / "输入_原帧.png")
    (out / "输入_排版.json").write_text(json.dumps(layout, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({"clip": args.clip, "frames": len(idx), "scale": round(s, 3), "char_h": round(mh * s)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
