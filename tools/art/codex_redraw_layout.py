"""把一个剪辑的原帧排成给 Codex 照着重画的绿底网格（角色动作线，11-06）。

每帧一个方格：黄色细框（#FFFF00，角色身上没有这个颜色，回收时直接当背景去掉），框内四周留边；
所有帧同一缩放，脚底贴各自格子的“地面线”（格底留边处），横向按人物外框居中。
写出：输入图 + 输入_排版.json（每帧原尺寸、pivot、bbox、在网格里的位置、统一缩放），
`codex_redraw_map.py` 靠它把重画结果还原回原帧画布。

用法：python tools/art/codex_redraw_layout.py <剪辑名> 输出目录 [--frames 0-7] [--size 1024x1536 --cols 2 --rows 4]
      [--margin 0.12] [--no-boxes]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
BOX = (255, 255, 0)
GREEN = (0, 255, 0)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("clip")
    ap.add_argument("out")
    ap.add_argument("--frames", default="", help="帧范围，如 0-7（含两端）；默认全部")
    ap.add_argument("--size", default="1024x1536")
    ap.add_argument("--cols", type=int, default=2)
    ap.add_argument("--rows", type=int, default=4)
    ap.add_argument("--margin", type=float, default=0.12, help="格内四周留边，占格宽 / 格高的比例")
    ap.add_argument("--line", type=int, default=4)
    ap.add_argument("--no-boxes", action="store_true")
    args = ap.parse_args()
    W, H = (int(v) for v in args.size.split("x"))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    data = json.loads((ROOT / "assets/data/battle.json").read_text(encoding="utf-8"))
    frames = data["characters"][0]["sprite"]["animations"][args.clip]["frames"]
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
            im = im.resize(size, Image.LANCZOS)
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
    layout = {"clip": args.clip, "scale": s, "size": [W, H], "cols": args.cols, "rows": args.rows,
              "margin": [mx, my], "boxes": not args.no_boxes, "box_color": "#FFFF00", "frames": []}
    for n, (i, im, bb) in enumerate(zip(idx, ims, bbs)):
        f = frames[i]
        cx, cy = (n % args.cols) * cw, (n // args.cols) * ch
        crop = im.crop(bb)
        sc = crop.resize((max(1, round(crop.width * s)), max(1, round(crop.height * s))), Image.LANCZOS)
        x = cx + (cw - sc.width) // 2
        y = cy + ch - my - sc.height
        sheet.paste(sc, (x, y), sc)
        if not args.no_boxes:
            h = args.line // 2
            draw.rectangle([cx + h + 2, cy + h + 2, cx + cw - h - 3, cy + ch - h - 3], outline=BOX, width=args.line)
        layout["frames"].append({"frame": i, "asset": f["asset"], "size": [round(f["width"]), round(f["height"])],
                                 "pivot": [f["pivotX"], f["pivotY"]], "bbox": list(bb), "placed": [x, y, sc.width, sc.height],
                                 "cell": [cx, cy, cw, ch]})
    sheet.save(out / "输入_原帧.png")
    json.dump(layout, open(out / "输入_排版.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps({"clip": args.clip, "frames": len(idx), "scale": round(s, 3), "char_h": round(mh * s),
                      "margin_px": [mx, my]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
