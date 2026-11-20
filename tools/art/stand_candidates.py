"""比几张"站立"候选帧的画质：原尺寸并排 + 3 倍放大的头部。

只读，不改任何游戏资源。
输出：.runtime/action-audit/站立候选_对比.png

用法：python tools/art/stand_candidates.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".runtime" / "action-audit"

CANDIDATES = [
    ("in-game idle（游戏里在用）", "assets/image/desktop-actions/待机/frame_00001.png"),
    ("AI 高清关键姿势", "assets/image/ai-hd-20261020/idle/pose_001.png"),
    ("原片 idle", "assets/image/characters/nightcrow/idle/frame_0001.png"),
    ("cleaned idle", "assets/image/cleaned/nightcrow/idle/frame_0001.png"),
    ("selected-original 00014", "assets/image/selected-original/mmh3_action_00014/character/frame_00001.png"),
]


def load(rel: str) -> Image.Image:
    return Image.open(ROOT / rel).convert("RGBA")


def main() -> None:
    imgs = [(label, load(rel)) for label, rel in CANDIDATES]

    # 上排：原尺寸（统一按高度对齐）；下排：同一头部区域 3 倍放大
    zoom = 3
    pad, label_h = 10, 26
    cells = []
    for label, img in imgs:
        head = img.crop((int(img.width * 0.32), 0, int(img.width * 0.86), int(img.height * 0.42)))
        cells.append((label, img, head.resize((head.width * zoom, head.height * zoom), Image.NEAREST)))

    top_h = max(i.height for _, i, _ in cells) + label_h + pad
    bot_h = max(h.height for _, _, h in cells) + label_h + pad
    col_w = [max(i.width, h.width) + pad for _, i, h in cells]
    W, H = sum(col_w), top_h + bot_h
    sheet = Image.new("RGBA", (W, H), (26, 26, 32, 255))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 15)
        small = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
    except OSError:
        font = small = ImageFont.load_default()

    x = 0
    for (label, img, head), w in zip(cells, col_w):
        draw.text((x + 4, 3), f"{label} {img.width}x{img.height}", font=font, fill=(170, 220, 255, 255))
        sheet.alpha_composite(img, (x + (w - img.width) // 2, label_h + pad))
        hy = top_h + label_h + pad
        sheet.alpha_composite(head, (x + (w - head.width) // 2, hy))
        draw.text((x + 4, top_h + 3), f"头部 ×{zoom}", font=small, fill=(140, 140, 155, 255))
        draw.line([(x, 0), (x, H)], fill=(70, 70, 84, 255))
        x += w

    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "站立候选_对比.png"
    sheet.save(out)
    print(f"written: {out}")


if __name__ == "__main__":
    main()
