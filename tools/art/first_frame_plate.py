"""做即梦首尾帧用的纯色底画面（主角站姿 / 跑姿）。

底：#7FA88F 纯色（黑紫角色反差大，抠像好抠）
角色：贴到画面里，脚底落在画面高度 92% 处
      - 站姿用 AI 高清关键姿势 `ai-hd-20261020/idle/pose_002.png`（实测最锐），放大 1.6 倍补足像素
      - 跑姿用游戏里 `desktop-actions/跑步/frame_00001.png`，原生尺寸不缩放

只读游戏素材，不改任何帧。
输出：docs/视觉设计/角色动作/跑步重做_20261102/

用法：python tools/art/first_frame_plate.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "docs" / "视觉设计" / "角色动作" / "跑步重做_20261102"
BG = (0x7F, 0xA8, 0x8F, 255)

# (源图, 源图里的脚底 pivot, 放大倍数, 画布, 输出名, 左右位置比例)
JOBS = [
    # 站姿：ai-hd 清单里 pivot 378.3195/421.2814 是在 481.2605×428.4218 的显示坐标，
# 除以 1.42807 换成源图像素 → 264.9 / 295.0
    ("assets/image/ai-hd-20261020/idle/pose_002.png", (264.9, 295.0), 1.6,
     (1280, 720), "首帧_站立_纯色底_1280x720.png", 0.58),
    ("assets/image/ai-hd-20261020/idle/pose_002.png", (264.9, 295.0), 1.6,
     (720, 720), "首帧_站立_纯色底_720x720_方版.png", 0.58),
    # 跑姿（第一帧，原生尺寸）
    ("assets/image/desktop-actions/跑步/frame_00001.png", (321.5089, 339.0), 1.0,
     (1280, 720), "首帧_跑姿_纯色底_1280x720.png", 0.58),
]


def build(rel: str, pivot: tuple[float, float], zoom: float,
          canvas: tuple[int, int], name: str, root_x_frac: float) -> None:
    img = Image.open(ROOT / rel).convert("RGBA")
    if abs(zoom - 1.0) > 1e-6:
        img = img.resize((round(img.width * zoom), round(img.height * zoom)), Image.LANCZOS)
    w, h = canvas
    plate = Image.new("RGBA", canvas, BG)
    foot_y = round(h * 0.92)
    root_x = round(w * root_x_frac)
    plate.alpha_composite(img, (round(root_x - pivot[0] * zoom), round(foot_y - pivot[1] * zoom)))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / name
    plate.convert("RGB").save(out)
    # 角色在画面里的占比：用不透明像素的实际外框量，而不是图幅
    body = img.split()[3].point(lambda v: 255 if v > 8 else 0).getbbox()
    body_h = (body[3] - body[1]) * 1.0
    print(f"{name}: 画布 {w}x{h}，角色实高 {body_h * 1:.0f}px = {body_h / h:.0%}，"
          f"脚底 y={foot_y}，脚底中心 x={root_x}，放大 {zoom}×")


def main() -> None:
    for rel, pivot, zoom, canvas, name, frac in JOBS:
        build(rel, pivot, zoom, canvas, name, frac)


if __name__ == "__main__":
    main()
