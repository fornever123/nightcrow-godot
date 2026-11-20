"""原帧重画 + 刀影层的对比图和预览动图（角色动作线，11-06）。

每帧三格：原来 / 重画的人和剑 / 叠上刀影层，按 pivot 对齐、游戏 N 倍大小，灰底。
另出实速动图（剪辑原 fps）和慢放动图。

用法：python tools/art/overlay_preview.py <剪辑目录(含 输入_排版.json、帧/、刀影/)> [--zoom 3]
      [--third 帧_刀影 --label "Codex 加刀影" --tag 刀影版]：第三行改用另一套已还原的帧（自带特效，按它自己的 pad 对齐），输出文件名加 _<tag>
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DS = 0.41075794621026895


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--zoom", type=float, default=3)
    ap.add_argument("--third", default="")
    ap.add_argument("--label", default="重画 + 刀影层")
    ap.add_argument("--tag", default="")
    ap.add_argument("--label2", default="重画（人和剑）")
    ap.add_argument("--gif-row", type=int, default=2, help="动图右边放第几行（0 原来 / 1 第二行 / 2 第三行）")
    args = ap.parse_args()
    D = Path(args.dir)
    lay = json.load(open(D / "输入_排版.json", encoding="utf-8"))
    man = json.load(open(D / "帧" / "manifest.json", encoding="utf-8"))
    pad = man["pad"]
    data = json.loads((ROOT / "assets/data/battle.json").read_text(encoding="utf-8"))
    fps = float(data["characters"][0]["sprite"]["animations"][lay["clip"]].get("fps", 24))
    has_fx = (D / "刀影").exists()
    man3 = json.load(open(D / args.third / "manifest.json", encoding="utf-8")) if args.third else None
    pad3 = man3["pad"] if man3 else pad
    sfx = f"_{args.tag}" if args.tag else ""
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)

    def tiles(z):
        ext = [0, 0, 0, 0]
        for f in lay["frames"]:
            w, h = f["size"]
            px, py = f["pivot"]
            P = max(pad, pad3)
            ext = [max(ext[0], px + P), max(ext[1], w - px + P), max(ext[2], py + P), max(ext[3], h - py + P)]
        CW, CH = round((ext[0] + ext[1]) * z) + 8, round((ext[2] + ext[3]) * z) + 8
        PV = (ext[0] * z + 4, ext[2] * z + 4)
        rows = []
        for f, m in zip(lay["frames"], man["frames"]):
            w, h = f["size"]
            px, py = f["pivot"]
            o = Image.open(ROOT / "assets" / f["asset"]).convert("RGBA").resize((w, h), Image.LANCZOS)
            b = Image.open(D / "帧" / m["file"]).convert("RGBA")
            if man3:
                c = Image.open(D / args.third / m["file"]).convert("RGBA")
            else:
                c = b.copy()
                fx_path = D / "刀影" / f"fx_{f['frame'] + 1:05d}.png"
                if has_fx and fx_path.exists():
                    c.alpha_composite(Image.open(fx_path).convert("RGBA"))
            row = []
            for im, pv in [(o, (px, py)), (b, (px + pad, py + pad)), (c, (px + pad3, py + pad3))]:
                t = Image.new("RGB", (CW, CH), (52, 56, 64))
                s = im.resize((max(1, round(im.width * z)), max(1, round(im.height * z))), Image.LANCZOS)
                t.paste(s, (round(PV[0] - pv[0] * z), round(PV[1] - pv[1] * z)), s)
                row.append(t)
            rows.append(row)
        return rows, CW, CH

    rows, CW, CH = tiles(DS * args.zoom)
    labels = ["原来", args.label2, args.label]
    n = len(rows)
    sheet = Image.new("RGB", (n * CW, 3 * CH + 3 * 30), (30, 32, 38))
    d = ImageDraw.Draw(sheet)
    for r in range(3):
        d.text((6, r * (CH + 30) + 4), labels[r], fill=(255, 220, 140), font=font)
        for i in range(n):
            sheet.paste(rows[i][r], (i * CW, r * (CH + 30) + 30))
            d.text((i * CW + 6, r * (CH + 30) + 34), str(lay["frames"][i]["frame"] + 1), fill=(200, 200, 210), font=font)
    sheet.save(D / f"对比_原来_重画_刀影{sfx}.png")
    rows, CW, CH = tiles(DS * 2)
    frames = []
    for row in rows:
        c = Image.new("RGB", (CW * 2 + 10, CH + 26), (30, 32, 38))
        c.paste(row[0], (0, 26))
        c.paste(row[args.gif_row], (CW + 10, 26))
        dd = ImageDraw.Draw(c)
        dd.text((4, 2), "原来", fill=(255, 200, 120), font=font)
        dd.text((CW + 14, 2), labels[args.gif_row], fill=(160, 230, 160), font=font)
        frames.append(c)
    frames[0].save(D / f"预览_实速{sfx}.gif", save_all=True, append_images=frames[1:] + [frames[-1]] * 8,
                   duration=round(1000 / fps), loop=0)
    frames[0].save(D / f"预览_慢放{sfx}.gif", save_all=True, append_images=frames[1:], duration=300, loop=0)
    print("ok", n, "frames", fps, "fps")


if __name__ == "__main__":
    main()
