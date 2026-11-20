"""把当前游戏内的跑步循环帧拼成一条对照图，标出帧号 / 持续时间。

用途：给"角色动作优化"这条线做现状基线。只读 assets/image/desktop-actions/跑步，
输出到 .runtime/action-audit/ 下，不改任何游戏资源。

用法：python tools/art/run_strip.py
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CLIP_DIR = ROOT / "assets" / "image" / "desktop-actions" / "跑步"
BATTLE = ROOT / "assets" / "data" / "battle.json"
OUT_DIR = ROOT / ".runtime" / "action-audit"


def clip_from_battle(name: str) -> dict:
    data = json.loads(BATTLE.read_text(encoding="utf-8"))
    return data["characters"][0]["sprite"]["animations"][name]


def main() -> None:
    clip = clip_from_battle("run")
    frames = clip["frames"]
    fps = float(clip["fps"])

    tiles = []
    for i, fr in enumerate(frames):
        path = ROOT / "assets" / fr["asset"]
        img = Image.open(path).convert("RGBA")
        tiles.append((i, fr, img))

    pad, label_h = 8, 34
    cell_w = max(img.width for _, _, img in tiles) + pad * 2
    cell_h = max(img.height for _, _, img in tiles) + pad * 2 + label_h
    sheet = Image.new("RGBA", (cell_w * len(tiles), cell_h), (28, 28, 36, 255))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 15)
    except OSError:
        font = ImageFont.load_default()

    t = 0.0
    for col, (i, fr, img) in enumerate(tiles):
        x0 = col * cell_w + pad
        y0 = label_h + pad
        sheet.alpha_composite(img, (x0, y0))
        dur = fr.get("durationTicks", 1) / fps
        head = f"#{i + 1}  t={t:.3f}s"
        sub = f"{fr['asset'].split('/')[-1]}  dur={dur * 1000:.0f}ms"
        draw.text((col * cell_w + pad, 3), head, font=font, fill=(150, 220, 255, 255))
        draw.text((col * cell_w + pad, 19), sub, font=font, fill=(150, 150, 165, 255))
        draw.line([(col * cell_w, 0), (col * cell_w, cell_h)], fill=(80, 80, 95, 255))
        # 第一帧单独描边，方便一眼找到
        if i == 0:
            draw.rectangle([x0 - 3, y0 - 3, x0 + img.width + 2, y0 + img.height + 2],
                           outline=(190, 130, 255, 255), width=2)
        t += dur

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / "跑步_现状_6帧.png"
    sheet.save(out)
    print(f"clip run: {len(frames)} frames @ {fps:.2f}fps, 一圈 {t * 1000:.0f}ms")
    print(f"first frame: assets/{frames[0]['asset']}")
    print(f"written: {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
