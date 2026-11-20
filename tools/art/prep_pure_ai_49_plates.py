#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建全角色 36 套动作 100% 纯 AI 重塑管线的 49 张输入底板与逐张完整提示词清单：
- S01..S41：41 张高张力人物动作板（#00FF00 纯绿底 + #FFFF00 黄框，已净除旧坏帧/大白雾块并预烘剑戟发力姿态微调，使人物在格内高分辨率占满）
- V01..V08：8 张 1536×1024 大画幅独立狂野剑戟特效模板（#00FF00 纯绿底 + #FFFF00 黄框分格模板）
- 输出：docs/视觉设计/角色动作/全动作纯AI重塑_20261114/plates_in/ 及 prompts_49.json
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(r"E:\00game\nightcrow-godot")
BACKUP_JSON = ROOT / r"docs\视觉设计\角色动作\全动作精修与张力升级_20261114\backup_animations_before_overhaul.json"
AI_HD_JSON = ROOT / r"assets\data\ai-hd-visuals.json"
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\全动作纯AI重塑_20261114"
PLATES_DIR = WORK_ROOT / "plates_in"

GREEN = (0, 255, 0)
BOX = (255, 255, 0)


def build_reference_anchors():
    """构建 100% 原版颜值人设锚点图 (ref_char_authentic.png) 与狂野冷紫书法特效参考图 (ref_vfx_style.png)。"""
    PLATES_DIR.mkdir(parents=True, exist_ok=True)

    # 1. 原版角色人设高清双姿合集（左：ai-hd idle/pose_002 778锐度原貌站姿；右：11-06 钦定弹刀1第1帧高清重画）
    p_idle = Image.open(ROOT / r"assets\image\ai-hd-20261020\idle\pose_002.png").convert("RGBA")
    p_parry = Image.open(ROOT / r"docs\视觉设计\角色动作\原帧重画_20261106\弹刀1_前8帧_带刀光\帧\frame_00001.png").convert("RGBA")

    ref_char = Image.new("RGB", (1024, 1024), GREEN)
    for idx, im in enumerate([p_idle, p_parry]):
        arr = np.asarray(im)
        ys, xs = np.nonzero(arr[..., 3] > 20)
        crop = im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
        scale = min(440.0 / crop.width, 820.0 / crop.height)
        sc = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
        ox = idx * 512 + (512 - sc.width) // 2
        oy = 920 - sc.height
        ref_char.paste(sc, (ox, oy), sc)
    ref_char.save(PLATES_DIR / "ref_char_authentic.png")

    # 2. 冷紫书法刀光与特效画法锚点（纯特效无人物：右上裁自 11-06 a1 纯刀光段 + 下半取自 V5 纯 AI 斩爆特效板）
    ref_a1 = Image.open(ROOT / r"docs\视觉设计\角色动作\原帧重画_20261106\弹刀1_前8帧_带刀光\图3_刀光风格参考_光线线a1.png").convert("RGBA")
    # 只裁右侧纯紫色大弧部分，彻底不含左侧小人，防止特效板误画人物
    arc_only = ref_a1.crop((int(ref_a1.width * 0.48), 0, ref_a1.width, ref_a1.height))
    ref_vfx = Image.new("RGB", (1024, 1024), GREEN)
    s1 = min(880.0 / arc_only.width, 460.0 / arc_only.height)
    r1 = arc_only.resize((round(arc_only.width * s1), round(arc_only.height * s1)), Image.Resampling.LANCZOS)
    ref_vfx.paste(r1, ((1024 - r1.width) // 2, 24), r1)

    v5_b_path = ROOT / r"docs\视觉设计\角色动作\普攻1段与特效大改_20261113\v5_ai_assets\_work_key\_keyed_B.png"
    if v5_b_path.exists():
        vb = Image.open(v5_b_path).convert("RGBA")
        vb_top = vb.crop((0, 0, vb.width, vb.height // 2))
        s2 = min(960.0 / vb_top.width, 460.0 / vb_top.height)
        r2 = vb_top.resize((round(vb_top.width * s2), round(vb_top.height * s2)), Image.Resampling.LANCZOS)
        ref_vfx.paste(r2, ((1024 - r2.width) // 2, 520), r2)
    ref_vfx.save(PLATES_DIR / "ref_vfx_style.png")


def strip_giant_smear_keep_character(im: Image.Image, pivot_x: float, pivot_y: float) -> Image.Image:
    """
    剥离旧原帧中遮天蔽日的白色阶梯刀影/柠檬黄色块/暗灰扫描线，保留核心人物与直剑骨架，
    避免旧大拖影把人物在格子里挤成火柴人。
    """
    arr = np.asarray(im).copy()
    h, w = arr.shape[:2]
    a = arr[..., 3]
    if np.count_nonzero(a > 20) < 60:
        return im

    r, g, b = arr[..., 0].astype(int), arr[..., 1].astype(int), arr[..., 2].astype(int)
    # 剔除柠檬黄脏块 (parry_react_3 等)
    yellow_junk = (a > 0) & (r > 185) & (g > 185) & (b < 115)
    arr[yellow_junk, 3] = 0

    # 100% 保护人物躯干核心半径 (dist <= 135px) 内的白衣、白挑染、白十字与剑芯，绝不挖绿洞！仅剥离躯干外 (>135px) 的大白拖影与淡雾
    yy, xx = np.mgrid[0:h, 0:w]
    cx = np.clip(pivot_x, 0, w - 1)
    cy = np.clip(pivot_y - 88.0, 0, h - 1)
    dist = np.hypot((xx - cx) * 0.85, (yy - cy) * 0.72)

    outer_white_smear = (dist > 135.0) & (a > 0) & (r > 205) & (g > 202) & (b > 205) & ((np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)) < 42)
    outer_fog = (dist > 150.0) & (a < 215)
    arr[outer_white_smear | outer_fog, 3] = 0

    # 保留与躯干邻域连通的主体块
    mask = (arr[..., 3] > 24).astype(np.uint8)
    dil = cv2.dilate(mask, np.ones((5, 5), np.uint8), iterations=1)
    num, labeled = cv2.connectedComponents(dil)
    if num > 2:
        near_body = (dist < 110.0) & (mask > 0)
        valid_labels = set(np.unique(labeled[near_body])) - {0}
        if valid_labels:
            keep = np.isin(labeled, list(valid_labels)) & (arr[..., 3] > 0)
            arr[..., 3] = np.where(keep, arr[..., 3], 0)

    if np.count_nonzero(arr[..., 3] > 24) < 200:
        return im
    return Image.fromarray(arr)


def apply_sakuga_tension_prewarp(
    im: Image.Image,
    px: float,
    py: float,
    sx: float = 1.0,
    sy: float = 1.0,
    lean_deg: float = 0.0,
) -> Image.Image:
    """以脚底锚点 (px, py) 为不动点施加发力姿态微调（压沉蓄劲/跨步前倾/拔身冲顶），供 Codex 直接画成锐利原画。"""
    if abs(sx - 1.0) < 1e-3 and abs(sy - 1.0) < 1e-3 and abs(lean_deg) < 1e-2:
        return im
    w, h = im.size
    sh = math.tan(math.radians(lean_deg))
    # x_out = px + sx*(x_in - px) + sh*(py - y_in)
    # y_out = py + sy*(y_in - py)
    # 逆变换矩阵 (x_in, y_in) = M * (x_out, y_out, 1)
    inv_sx = 1.0 / sx
    inv_sy = 1.0 / sy
    # y_in = py + (y_out - py) * inv_sy
    # py - y_in = -(y_out - py) * inv_sy
    # x_in = px + (x_out - px - sh*(py - y_in)) * inv_sx = px + (x_out - px)*inv_sx + (sh*inv_sy*inv_sx)*(y_out - py)
    a = inv_sx
    b = sh * inv_sy * inv_sx
    c = px - a * px - b * py
    d = 0.0
    e = inv_sy
    f = py - e * py
    return im.transform((w, h), Image.Transform.AFFINE, (a, b, c, d, e, f), resample=Image.Resampling.BICUBIC)


def load_ai_hd_pose(hd_clips: dict, clip_key: str, pose_idx: int, target_h: float = 215.0):
    """直接按 ai-hd-visuals.json 官方标定的游戏空间尺寸 (width, height, pivotX, pivotY) 加载完好姿态，杜绝白弧导致人物缩水！"""
    frames = hd_clips[clip_key]["frames"]
    pose_idx = max(0, min(len(frames) - 1, pose_idx))
    fr = frames[pose_idx]
    im = Image.open(ROOT / "assets" / fr["asset"]).convert("RGBA")
    nw, nh = max(1, round(fr["width"])), max(1, round(fr["height"]))
    im_s = im.resize((nw, nh), Image.Resampling.LANCZOS)
    return im_s, float(fr["pivotX"]), float(fr["pivotY"])


def build_character_sheet_plate(
    tag: str,
    clip_entries: list[dict],
    cols: int,
    rows: int,
    W: int,
    H: int,
    margin_ratio: float = 0.10,
) -> dict:
    """
    把一组动作关键帧排成 #00FF00 绿底 + #FFFF00 黄框输入板，写出精确逆映射 JSON。
    clip_entries 每项包含:
      clip, frame_idx, im (RGBA), pivot (px, py), orig_size (w, h),
      sx, sy, lean_deg (预姿态张力参数)
    """
    cw, ch = W // cols, H // rows
    mx, my = round(cw * margin_ratio), round(ch * margin_ratio)

    prepped = []
    for ent in clip_entries:
        im0 = strip_giant_smear_keep_character(ent["im"], ent["pivot"][0], ent["pivot"][1])
        im1 = apply_sakuga_tension_prewarp(
            im0, ent["pivot"][0], ent["pivot"][1],
            sx=ent.get("sx", 1.0), sy=ent.get("sy", 1.0), lean_deg=ent.get("lean_deg", 0.0),
        )
        arr = np.asarray(im1)
        ys, xs = np.nonzero(arr[..., 3] > 20)
        if len(xs) == 0:
            bb = (0, 0, im1.width, im1.height)
        else:
            bb = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
        prepped.append((ent, im1, bb))

    mw = max(b[2] - b[0] for _, _, b in prepped)
    mh = max(b[3] - b[1] for _, _, b in prepped)
    scale = min((cw - 2 * mx) / float(max(1, mw)), (ch - 2 * my) / float(max(1, mh)))

    sheet = Image.new("RGB", (W, H), GREEN)
    draw = ImageDraw.Draw(sheet)

    layout = {
        "tag": tag,
        "size": [W, H],
        "cols": cols,
        "rows": rows,
        "cell_size": [cw, ch],
        "margin": [mx, my],
        "scale": scale,
        "cells": [],
    }

    for idx, (ent, im1, bb) in enumerate(prepped):
        cx, cy = (idx % cols) * cw, (idx // cols) * ch
        crop = im1.crop(bb)
        sw = max(1, round(crop.width * scale))
        sh = max(1, round(crop.height * scale))
        sc = crop.resize((sw, sh), Image.Resampling.LANCZOS)

        # 横向按人物 crop 居中，纵向让脚底贴近格底地面线（同时保证不越过上下边距）
        foot_from_bottom = (bb[3] - ent["pivot"][1]) * scale
        px_cell = cx + (cw - sw) // 2
        py_cell = round(cy + ch - my - sh + max(0.0, min(28.0, foot_from_bottom)))
        py_cell = max(cy + my // 2 + 6, min(cy + ch - my // 2 - 6 - sh, py_cell))

        sheet.paste(sc, (px_cell, py_cell), sc)
        draw.rectangle([cx + 4, cy + 4, cx + cw - 5, cy + ch - 5], outline=BOX, width=4)

        piv_sheet_x = px_cell + (ent["pivot"][0] - bb[0]) * scale
        piv_sheet_y = py_cell + (ent["pivot"][1] - bb[1]) * scale

        layout["cells"].append({
            "cell_idx": idx,
            "clip": ent["clip"],
            "frame_idx": ent["frame_idx"],
            "orig_size": list(ent["orig_size"]),
            "orig_pivot": list(ent.get("orig_pivot_orig", ent["pivot"])),
            "canvas_pivot": list(ent["pivot"]),
            "bbox": list(bb),
            "placed": [px_cell, py_cell, sw, sh],
            "cell_rect": [cx, cy, cw, ch],
            "pivot_in_sheet": [piv_sheet_x, piv_sheet_y],
        })

    out_png = PLATES_DIR / f"输入_{tag}.png"
    out_json = PLATES_DIR / f"排版_{tag}.json"
    sheet.save(out_png)
    out_json.write_text(json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8")
    return layout


def build_vfx_template_plate(tag: str, cols: int, rows: int, W: int = 1536, H: int = 1024):
    """构建独立大画幅特效板 #00FF00 绿底 + #FFFF00 黄框网格模板，确保 AI 在格内最大化绘制特效且互不粘连。"""
    cw, ch = W // cols, H // rows
    sheet = Image.new("RGB", (W, H), GREEN)
    dr = ImageDraw.Draw(sheet)
    for r_i in range(rows):
        for c_i in range(cols):
            cx, cy = c_i * cw, r_i * ch
            dr.rectangle([cx + 4, cy + 4, cx + cw - 5, cy + ch - 5], outline=BOX, width=4)
    out_png = PLATES_DIR / f"输入_{tag}.png"
    sheet.save(out_png)
    meta = {"tag": tag, "size": [W, H], "cols": cols, "rows": rows, "cell_size": [cw, ch]}
    (PLATES_DIR / f"排版_{tag}.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")


CHAR_STYLE_FOOTER = """
人设颜值、原版比例与画风硬锁死（全格必须是 100% 同一个人，严格对齐图2 原版设定，绝不画丑或换人！）：
1. 脸型五官与原版头身比：保持图2 清冷灵动、精致秀气的 18 岁少女小脸与原版头身比例，细眉长睫，通透紫罗兰渐变眼瞳配亮白高光点，战斗挥斩格眼神凌厉有剑客杀气。
2. 左右不对称发型（严禁左右画反）：头顶正中有一枚空心圆环呆毛；前额一侧垂下一缕干净纯白挑染发丝并别着紫色菱形水晶+紫白小鸦羽发夹；短发主体为深墨黑向发梢微泛冷紫宝蓝光泽。
3. 服装与唯一笔直长剑：黑高领紫晶扣、露肩白色短上衣、黑百褶短裙、深灰黑过膝长袜配高跟战靴、肩背墨黑鸦羽披肩；全程只有一把完全笔直锐利的冷紫发光晶棱符文长直剑（十字护手镶紫晶），任何一格绝不能弯成弯刀、不能断裂、不能多画第二把剑！
4. 动态张力升级：以图1 每一格的动作阶段、朝向和脚底高度为基准，大胆强化日式剑戟作画张力——蓄力格压沉拧腰蓄满寸劲，挥斩/冲刺/升龙格拉出舒展凌厉的跨步前倾发力弧线，鸦羽披肩与发丝随剑风狂烈翻飞，脸颊与衣褶暗部映出帅气的冷紫剑芒轮廓受光！
5. 输出规格：纯绿底 #00FF00，原样保留相同位置的 #FFFF00 黄色细框；人物与长剑四周留足干净 #00FF00 绿底边距，绝不碰或越过黄框；本图专注把高张力人物与笔直发光长剑画到极致高清锐利（大型跨格刀光由独立特效板合成，本图只在剑刃周围画细腻贴剑寒芒即可）；线条纤细锐利，硬边赛璐璐分层上色，零绿雾毛边、不要地面阴影和文字编号。
"""

VFX_STYLE_HEADER = """用你的 image_gen 工具只生成 1 张横版 1536×1024 图，不要生成第二张，不要运行任何命令、不要读或改项目里任何文件。两张附图按顺序是图1（绿底黄框分格模板）、图2（本项目冷紫干笔书法刀光画法参考）。生成完回复“完成”即可。图片要求如下：

请按图1 的 #00FF00 纯绿背景和 #FFFF00 黄色细框分格位置，在每一格正中央绘制顶级商业 2D 动作游戏（ufotable ×《九日》×《丝之歌》凌厉剑戟美学）的纯手绘大特效（绝对不要画人物、手脚或武器实体！每一格特效四周留出至少 24 像素纯绿 #00FF00 边距，绝对不能碰到 #FFFF00 黄框！）。

特效视觉美学硬要求（极致帅气、狂野、锋利如剃刀！）：
1. 四阶硬边赛璐璐色阶与狂草飞白：主弧外侧凸缘是刺破夜幕的极亮炽白锐刃（#FDFAFF），向内依次是冰晶浅紫（#D8C6FF）、高饱和电光紫（#9D6BFF）、深邃鸦墨暗紫（#3E1C8C）的硬边分层平涂色块（拒绝模糊廉价渐变雾团！）；弧带内部必须画出高速干笔狂草飞白刷痕、撕裂空气的细锐紫白闪电丝，尾端裂开 3~5 道如利爪般修长锋锐的破风细丝！
2. 空间裂口与夜鸦基因：重击与爆发格融入锐利墨黑紫边空间裂隙纹与少量随剑风旋散的锋利墨黑夜鸦飞羽剪影，严禁出现任何黄色、橙色俗气火花！所有像素不透明硬边干净，零半透明绿雾，便于绿幕抠图。
"""


def main():
    build_reference_anchors()
    anims = json.loads(BACKUP_JSON.read_text(encoding="utf-8"))
    hd_clips = json.loads(AI_HD_JSON.read_text(encoding="utf-8"))["clips"]

    def raw_entry(clip: str, f_idx: int, sx: float = 1.0, sy: float = 1.0, lean: float = 0.0, hd_override: tuple[str, int] | None = None):
        fr = anims[clip]["frames"][f_idx]
        w0, h0 = round(fr.get("width", 520)), round(fr.get("height", 420))
        px0, py0 = float(fr.get("pivotX", w0 * 0.5)), float(fr.get("pivotY", h0 * 0.85))
        if hd_override is not None:
            hc, hi = hd_override
            im_hd, hpx, hpy = load_ai_hd_pose(hd_clips, hc, hi)
            cw_hd = max(w0, im_hd.width + 120, 640)
            ch_hd = max(h0, im_hd.height + 120, 520)
            canvas = Image.new("RGBA", (cw_hd, ch_hd), (0, 0, 0, 0))
            tx = cw_hd * 0.5
            ty = ch_hd - 60.0
            ox, oy = round(tx - hpx), round(ty - hpy)
            canvas.paste(im_hd, (ox, oy), im_hd)
            return {"clip": clip, "frame_idx": f_idx, "im": canvas, "pivot": (tx, ty), "orig_size": (w0, h0), "orig_pivot_orig": (px0, py0), "sx": sx, "sy": sy, "lean_deg": lean}

        im = Image.open(ROOT / "assets" / fr["asset"]).convert("RGBA")
        if im.size != (w0, h0):
            im = im.resize((w0, h0), Image.Resampling.LANCZOS)
        return {"clip": clip, "frame_idx": f_idx, "im": im, "pivot": (px0, py0), "orig_size": (w0, h0), "sx": sx, "sy": sy, "lean_deg": lean}

    # ==================== 1. 构建 V01..V08 8 张大画幅独立特效板 ====================
    vfx_specs = [
        ("V01", 3, 2, """3 列 × 2 行共 6 格（阅读顺序从左到右、从上到下）：
- 第 1 格（第1行左）：普攻横斩起势破风弯刃——一道纤细如剃刀的初生右弯新月紫白锐弧，尖端迸出 2 道细锐紫电丝。
- 第 2 格（第1行中）：普攻 1 段主爆发「190° 狂草飞白破空满月巨弧」——朝画面右侧饱满鼓出的超宽霸气满月大刀光，外刃炽白如闪电，内层电光紫与鸦墨深紫狂草飞白刷痕交错，尾端裂出 5 道锋利长丝并卷起 3 片墨黑鸦羽剪影！
- 第 3 格（第1行右）：满月横斩高速消散残弧——大弧沿原轨迹碎裂成 5 道彼此断开、锋利如爪的紫白干笔飞丝与细碎紫晶。
- 第 4 格（第2行左）：普攻 2 段反撩起势锐针——自右下方挑起的紧凑锐利冷紫白弯钩剑芒。
- 第 5 格（第2行中）：普攻 2 段主爆发「右下扫向左上 S 型反撩裂空巨弧」——极具速度张力的斜向大弦月狂草刀光（凸弧朝右上外侧），内部带交错细紫闪电纹与飞白断口！
- 第 6 格（第2行右）：反撩高位裂散残芒——斜向左上展开的 4 道细锐紫白干笔残丝与 2 片飘散黑羽。"""),

        ("V02", 2, 2, """2 列 × 2 行共 4 个超大特效格：
- 第 1 格（左上）：普攻 3 段终结重劈「鸦墨紫雷裂地新月巨刃」——从左上方高处猛劈向右下方地面的超宽厚重狂草新月巨型斩弧，底部触地瞬间炸开锐利的冷紫纯白剑气地刺簇与跳跃紫电弧！
- 第 2 格（右上）：重劈裂地余波——新月巨刃碎裂为锋利鸦墨紫白残片，底部向两侧炸开低矮锐利的赛璐璐冷紫冲击地刺波。
- 第 3 格（左下）：空连 3 段「高空彗尾俯冲纵劈巨刃」——从正上方垂直贯向右下方（11点至5点方向）的修长凌厉彗星裂空巨弧，外缠螺旋细紫闪电丝与黑羽残影！
- 第 4 格（右下）：俯冲纵劈残痕——纵向撕裂空间的墨黑紫白闪电细裂隙与干笔飞丝。"""),

        ("V03", 3, 2, """3 列 × 2 行共 6 格：
- 第 1 格（第1行左）：升龙上挑起势贴地挑弧——自地面向上勾起的锋锐冷紫白弯弧配一圈小型贴地破风气环。
- 第 2 格（第1行中）：上挑强普主爆发「冲天升龙螺旋剑气巨弧」——自画面底部垂直冲向顶部的修长纵向新月巨刃（凸弧朝右前），周围盘旋缠绕两股凌厉上升的电光紫破风流光带与细紫电弧！
- 第 3 格（第1行右）：升龙冲顶消散残芒——纵向向上的 4 道修长干笔紫白破风细丝与 2 片上升黑羽。
- 第 4 格（第2行左）：空连 1 段「滞空水平流线弦月斩弧」——轻灵锋锐的朝右偏下斜扫冷紫骨白弦月弧，尾拖平行速度细线。
- 第 5 格（第2行中）：空连 2 段「滞空双层交叠大弯月反撩弧」——朝右上斜扬的双层硬边冷紫炽白狂草弯月刀光，张力十足。
- 第 6 格（第2行右）：空中旋斩环形干笔碎丝——呈弧形散开的细锐紫白残影丝。"""),

        ("V04", 3, 2, """3 列 × 2 行共 6 格（高速疾行冲刺与剃刀横扫特效套组，全部朝画面右侧冲刺方向绘制）：
- 第 1 格（第1行左）：疾冲瞬间「音障破风紫雷三角楔影（浓）」——横向极速拉长的锐利流线型V字破风音障锥，外白内电光紫配多道水平撕裂闪电速度线与 3 片拉长黑羽残影！
- 第 2 格（第1行中）：高速掠影「双叉流光速度残影带」——3 道平行修长、前后错落的硬边冷紫炽白水平疾风流光线束。
- 第 3 格（第1行右）：冲刺急刹主爆发「剃刀一字水平裂空长斩弧」——横向贯满格子、纵向扁平锋利到极致的水平新月狂草刀光（凸弧朝右），带耀眼炽白刃锋与紫电尾丝！
- 第 4 格（第2行左）：一字横扫裂解残光——水平展开的锋利干笔断丝与紫白电火花。
- 第 5 格（第2行中）：战靴急刹「贴地向后喷射冷紫电火擦地流光」——从左向右下方地面擦出的两束锐利上扬冷紫白火花羽流。
- 第 6 格（第2行右）：转身甩剑轻灵小月牙弧——紧凑锋利的小号右下甩尾冷紫白新月弧。"""),

        ("V05", 3, 2, """3 列 × 2 行共 6 格（《只狼》级弹刀金石交击核爆寒星与旋身反击烈弧套组）：
- 第 1 格（第1行左）：弹刀完美格开瞬间「刹那不对称超长十字核爆寒星」——中心炽白、外缘电光紫与鸦墨黑交错的斜向超长四芒十字闪光 + 一圈锐利椭圆形音爆破风环 + 飞溅冷紫碎晶刺！
- 第 2 格（第1行中）：弹刀寒星外扩碎裂——十字寒星化作向外高速迸射的 8 道锋利紫白放射刺线与碎星点。
- 第 3 格（第1行右）：弹刀 1/2 反手斜撩「高曲率凌厉反击弯刀烈弧」——从右下猛撩向左上方的紧凑凶狠狂草冷紫骨白弯月弧！
- 第 4 格（第2行左）：弹刀反击斜劈烈弧——从左上劈向右下方的锐利S弯冷紫白刀光配干笔裂尾。
- 第 5 格（第2行中）：弹刀 3 主爆发「270° 狂野旋风护体满月斩环」——环绕大半圈的超大张力狂草飞白四阶冷紫炽白回旋刀环，外溅紫电与黑羽！
- 第 6 格（第2行右）：270° 旋风斩环裂散——环形分布的锋利干笔紫白飞丝与细碎晶芒。"""),

        ("V06", 3, 2, """3 列 × 2 行共 6 格（格挡架盾符文灵火与三阶受击冲击盾波套组）：
- 第 1 格（第1行左）：持续架盾「竖直剑脊游走冷紫符文灵火（上行态）」——一道细腻锐利的竖向冷紫炽白符文火苗纹配顶端小十字寒星。
- 第 2 格（第1行中）：持续架盾「竖直剑脊冷紫寒星绽放（顶点态）」——精巧锐利的竖向剑气微芒配耀眼小号四角冷紫白寒星。
- 第 3 格（第1行右）：轻格挡受击「半月冷紫卸力盾弧 + 紫白火花簇」——朝右侧凸出的紧凑硬边冷紫护盾弯弧，中心迸出 5 道锐利紫白短刺火花。
- 第 4 格（第2行左）：中格挡受击「双层电弧受击盾波 + 交叉十字星芒」——双层平行硬边冷紫冲击弧配耀眼斜十字紫白寒星。
- 第 5 格（第2行中）：重格挡破势「狂暴扇形紫雷冲击爆波」——朝右前方炸开的宽大硬边电光紫与炽白放射电弧冲击扇面！
- 第 6 格（第2行右）：重格挡滑退「双轨贴地擦地紫电火花束」——贴地向右侧飞溅的两道修长锐利冷紫白电火尾迹。"""),

        ("V07", 3, 2, """3 列 × 2 行共 6 格（居合一线拔刀闪、归鞘星芒与 4 帧循环盘龙蓄力气旋套组）：
- 第 1 格（第1行左）：居合拔刀出鞘「寒星剃刀一线裂空弧」——左侧鞘口一点耀眼炽白四角寒星，向右上方拉出一道极长、极细、锋利如激光剃刀的微弯四阶冷紫炽白一线拔刀斩痕！
- 第 2 格（第1行中）：旋腕收刀归鞘「咔哒入鞘斜十字紫白寒星 + 纤细余韵剑花丝」——精致帅气的不对称斜十字冷紫纯白星闪配一缕半圆形极细紫丝。
- 第 3~6 格（第1行右、第2行左、中、右）：蓄力持续「4 拍无缝循环鸦墨紫炎盘龙螺旋气旋（相位 0° / 90° / 180° / 270°）」——自底部宽口呈锥形向上高速盘旋收束的四阶硬边电光紫+鸦墨黑赛璐璐螺旋气旋流带，周围跳跃细锐紫白电弧，4 格形态连贯旋转构成完美循环动画！"""),

        ("V08", 3, 2, """3 列 × 2 行共 6 格（满蓄力终极技「断晓一闪」空间裂口巨环、气浪卷云与战败「破魂晶羽爆裂」套组）：
- 第 1 格（第1行左）：满蓄力破界瞬间「黑白紫反相放射裂空核闪」——极具作画冲击力的墨黑内芯+炽白电光紫超长放射裂隙闪光纹！
- 第 2 格（第1行中）：满蓄力主爆发「360° 断晓一闪空间裂口狂草回旋巨环」——横向宽展的霸气椭圆形 360° 狂草飞白四阶冷紫炽白巨型回旋斩环，环内嵌墨黑空间裂隙纹与细紫闪电！
- 第 3 格（第1行右）：满蓄力地面震波「左右双向狂暴翻涌硬边冷紫气浪卷云」——贴地向左右两侧高速翻卷扩散的锋利赛璐璐冷紫白冲击波卷云簇！
- 第 4 格（第2行左）：360° 巨环裂解余韵——椭圆形排布的十余道修长锋利紫白干笔残丝、细紫电弧与飞旋黑羽。
- 第 5 格（第2行中）：战败受创瞬间「破魂碎玻璃紫晶簇 + 夜鸦黑羽爆裂（初爆）」——向四周凄美炸开的硬边冷紫纯白几何碎晶块与 6 片锋利墨黑夜鸦飞羽！
- 第 6 格（第2行右）：破魂爆裂飘散（余韵）——向外扩散变小的冷紫晶屑星点与缓缓飘落的 5 片夜鸦黑羽剪影。"""),
    ]

    all_jobs = []
    for v_tag, vc, vr, v_detail in vfx_specs:
        build_vfx_template_plate(v_tag, vc, vr, 1536, 1024)
        prompt = VFX_STYLE_HEADER + "\n本张分格具体绘制内容：\n" + v_detail
        all_jobs.append({
            "id": v_tag,
            "kind": "vfx",
            "cols": vc,
            "rows": vr,
            "size": [1536, 1024],
            "images": [
                str(PLATES_DIR / f"输入_{v_tag}.png"),
                str(PLATES_DIR / "ref_vfx_style.png"),
            ],
            "prompt": prompt,
        })

    # ==================== 2. 构建 S01..S41 41 张高张力人物动作板 ====================
    char_sheet_defs = [
        # (tag, cols, rows, W, H, entries, detail_prompt)
        ("S01", 2, 4, 1024, 1536, [
            raw_entry("idle", 0), raw_entry("idle", 9, sy=1.01), raw_entry("idle", 18, sy=1.02), raw_entry("idle", 27, sy=1.02),
            raw_entry("idle", 35, sy=1.01), raw_entry("idle", 44), raw_entry("idle", 53, sy=0.99), raw_entry("idle", 62),
        ], "「待机呼吸与夜风吹拂循环」竖版 2×4 共 8 格：少女 3/4 朝右侧身孤傲清冷站立，右手在身侧后方反手稳握笔直冷紫发光符文长直剑斜指右下方（4~5点钟方向），左手自然垂落；第 1~4 格轻微吸气胸肩微提、夜风吹拂鸦羽披肩尾羽与白挑染发丝轻盈浮起，第 5~8 格轻缓呼气平顺落回第 1 格构成无缝循环，剑芯流淌细腻冷紫微光。"),

        ("S02", 3, 2, 1536, 1024, [
            raw_entry("turn_right_left", 0, lean=-3.0), raw_entry("turn_right_left", 1, sx=1.03, sy=0.97, lean=-4.0),
            raw_entry("turn_right_left", 2, sx=1.04, sy=0.96, lean=-5.0), raw_entry("turn_right_left", 3, sx=1.04, sy=0.96, lean=-7.0),
            raw_entry("turn_right_left", 4, sx=1.05, sy=0.95, lean=-9.0),
        ], "「高速跑动急刹右转左蹬出」横版 3×2 前 5 格有动作（右下第 6 格保持 #00FF00 纯绿空白）：第 1~2 格左脚狠踩地面急刹左转，修净原图后腿黑重影并将弯剑修成笔直长直剑斜指左下；第 3~4 格压低重心拧身蓄力，鸦羽披肩甩开扇面，右手将笔直长直剑带向身后右下方（4~5点钟，修直原图钩状弯剑）；第 5 格身体如猎豹般朝左大幅前倾猛蹬起跑，身后笔直长直剑斜指右下。"),

        ("S03", 3, 3, 1536, 1024, [
            raw_entry("jump", 0, sx=1.05, sy=0.94), raw_entry("jump", 1, sx=1.06, sy=0.93), raw_entry("jump", 2, sx=0.96, sy=1.05, lean=3.0),
            raw_entry("jump", 3, sx=0.95, sy=1.06, lean=4.0), raw_entry("jump", 4, sx=0.95, sy=1.06, lean=4.0), raw_entry("jump", 5, sx=0.96, sy=1.05, lean=3.0),
            raw_entry("jump", 6, sy=1.03), raw_entry("jump", 7, sy=1.02), raw_entry("jump", 8),
        ], "「起跳深蹲蓄劲与拔身腾空」横版 3×3 共 9 格：第 1~2 格屈膝压腰蓄满弹跳寸劲，笔直长直剑斜拖右后下方；第 3~6 格双腿猛力蹬离地面纵向挺拔冲顶，鸦羽披肩与裙摆随上升气流帅气向下飘展，右手携笔直长直剑在身后斜指右下；第 7~9 格升至最高点附近轻盈收膝滞空，神态清冷凌厉。"),

        ("S04", 2, 4, 1024, 1536, [
            raw_entry("fall", 0, sx=0.97, sy=1.04), raw_entry("fall", 3, sx=0.97, sy=1.04), raw_entry("fall", 6, sx=0.97, sy=1.04),
            raw_entry("land", 0, sx=1.06, sy=0.93, lean=3.0), raw_entry("land", 1, sx=1.07, sy=0.92, lean=4.0),
            raw_entry("land", 3, sx=1.03, sy=0.96, lean=2.0), raw_entry("land", 5, sy=0.99), raw_entry("land", 7),
        ], "「空中下坠 3 拍 + 落地半蹲缓冲 5 拍」竖版 2×4 共 8 格：第 1~3 格为滞空下坠姿态，双腿微曲悬空、鸦羽披肩与发丝受风压向上高高扬起，右手握笔直长直剑斜指右后上方（约2点钟）；第 4~5 格双靴稳踏地面深蹲压膝卸力，披肩帅气向下拍落，直剑斜指右下；第 6~8 格利落回弹起身恢复备战站姿。"),

        ("S05", 2, 4, 1024, 1536, [
            raw_entry("attack_1", 0), raw_entry("attack_1", 1, sx=1.02, sy=0.98, lean=-3.0),
            raw_entry("attack_1", 2, sx=1.04, sy=0.96, lean=-5.0), raw_entry("attack_1", 3, sx=1.05, sy=0.95, lean=-6.0),
            raw_entry("attack_1", 4, sx=1.04, sy=0.96, lean=6.0, hd_override=("attack_1", 3)),
            raw_entry("attack_1", 5, sx=1.06, sy=0.94, lean=8.0, hd_override=("attack_1", 4)),
            raw_entry("attack_1", 6, sx=1.05, sy=0.95, lean=7.0, hd_override=("attack_1", 5)),
        ], "「普攻 1 段前半：拧腰满弓蓄力与大跨步暴烈横斩」竖版 2×4 前 7 格有动作（第 8 格保持 #00FF00 纯绿空白）：第 1~4 格沉腰拧肩将笔直长直剑高蓄向左肩后上方，前膝微提蓄满杀机；第 5~7 格向前大跨步俯身暴烈挥斩，身体前倾成凌厉突进直线，右手紧握笔直发光长直剑向右下斜伸到底，脑后鸦羽披肩狂烈炸开飞扬（注意脑后飞起的是墨黑宝蓝鸦羽披肩，绝不是第二把剑），脸颊映出强烈冷紫剑芒轮廓光！"),

        ("S06", 3, 2, 1536, 1024, [
            raw_entry("attack_1", 7, sx=1.04, sy=0.96, lean=5.0, hd_override=("attack_1", 5)),
            raw_entry("attack_1", 8, sx=1.03, sy=0.97, lean=4.0, hd_override=("attack_1", 6)),
            raw_entry("attack_1", 9, sx=1.02, sy=0.98, lean=2.0),
            raw_entry("attack_1", 10, lean=1.0), raw_entry("attack_1", 11), raw_entry("attack_1", 12),
        ], "「普攻 1 段后半：弓步定剑与潇洒旋腕回正」横版 3×2 共 6 格：第 1~2 格保持大跨步低蹲弓步定势，右手紧握笔直发光长直剑斜指右前下方，眼神冷冽；第 3~6 格从弓步利落发力起身，右手携笔直长直剑沿优雅弧线旋回身侧右后方回归备战站姿。"),

        ("S07", 2, 4, 1024, 1536, [
            raw_entry("attack_2", 0, sx=1.03, sy=0.97, lean=-3.0), raw_entry("attack_2", 1, sx=1.04, sy=0.96, lean=-4.0),
            raw_entry("attack_2", 2, sx=1.05, sy=0.95, lean=-5.0), raw_entry("attack_2", 3, lean=2.0),
            raw_entry("attack_2", 4, sx=1.04, sy=0.97, lean=6.0), raw_entry("attack_2", 5, sx=1.05, sy=0.98, lean=7.0),
            raw_entry("attack_2", 6, sx=1.03, sy=1.02, lean=5.0), raw_entry("attack_2", 7, sx=1.02, sy=1.02, lean=4.0),
        ], "「普攻 2 段前半：沉腰蓄势与反手大斜撩爆发」竖版 2×4 共 8 格：第 1~3 格沉膝压腰将笔直长直剑蓄在右后下方（4~5点钟）；第 4~6 格猛然拧胯跨步，右臂携笔直长直剑自右下向右上再向头顶左上方潇洒反手斜撩（剑尖依次指 3点→1点→11点钟方向），鸦羽披肩随旋身大开大合翻飞；第 7~8 格直剑高扬在左上方（11点钟）凌厉定势！"),

        ("S08", 2, 4, 1024, 1536, [
            raw_entry("attack_2", 8, lean=3.0), raw_entry("attack_2", 9, lean=2.0),
            raw_entry("attack_2", 10, lean=1.0), raw_entry("attack_2", 11),
            raw_entry("attack_2", 12), raw_entry("attack_2", 14),
            raw_entry("attack_2", 16), raw_entry("attack_2", 17),
        ], "「普攻 2 段后半：高位扬剑余韵与旋腕收势」竖版 2×4 共 8 格：承接左上扬剑终态，少女从左上方（11点钟）握持笔直长直剑的飒爽姿势，逐格旋腕绕身将长剑顺滑收回右侧后下方备战位，披肩与裙摆随回身平顺落定。"),

        ("S09", 2, 4, 1024, 1536, [
            raw_entry("attack_2_start", 0, lean=-2.0), raw_entry("attack_2_start", 2, sx=1.04, sy=0.96, lean=-4.0),
            raw_entry("attack_2_start", 4, sx=1.05, sy=0.95, lean=-5.0), raw_entry("attack_2_start", 6, lean=3.0),
            raw_entry("attack_2_start", 8, sx=1.04, lean=6.0), raw_entry("attack_2_start", 10, sx=1.04, sy=1.02, lean=6.0),
            raw_entry("attack_2_start", 13, lean=3.0), raw_entry("attack_2_start", 16),
        ], "「普攻 2 段带前摇衔接版」竖版 2×4 共 8 格：第 1~3 格踏步压低重心将笔直长直剑拉向身后蓄力；第 4~6 格拧腰突进将笔直长直剑从右下猛撩向右上与左上方，披肩狂烈翻飞；第 7~8 格高位持剑定势并利落回稳。"),

        ("S10", 2, 4, 1024, 1536, [
            raw_entry("attack_2_recovery", 0, lean=4.0), raw_entry("attack_2_recovery", 2, sx=1.04, lean=6.0),
            raw_entry("attack_2_recovery", 4, sy=1.02, lean=5.0), raw_entry("attack_2_recovery", 7, lean=3.0),
            raw_entry("attack_2_recovery", 11, lean=1.0), raw_entry("attack_2_recovery", 16),
            raw_entry("attack_2_recovery", 22), raw_entry("attack_2_recovery", 29),
        ], "「普攻 2 段带长后摇收剑版」竖版 2×4 共 8 格：第 1~3 格爆发斜撩将笔直长直剑扬向头顶左上方；第 4~8 格展现潇洒从容的剑客收招韵律——直剑从高位旋腕划过身侧，步伐轻盈收回，最终沉息归于标准侧身持剑站姿。"),

        ("S11", 2, 4, 1024, 1536, [
            raw_entry("attack_3", 0, lean=-2.0), raw_entry("attack_3", 1, sx=1.03, sy=0.97, lean=-4.0),
            raw_entry("attack_3", 2, sy=1.03, lean=-5.0), raw_entry("attack_3", 3, sy=1.05, lean=-6.0),
            raw_entry("attack_3", 4, sy=1.05, lean=-4.0), raw_entry("attack_3", 5, sx=1.05, sy=0.96, lean=7.0),
            raw_entry("attack_3", 6, sx=1.07, sy=0.93, lean=10.0), raw_entry("attack_3", 7, sx=1.07, sy=0.92, lean=9.0),
        ], "「普攻 3 段终结重劈前半：旋身背剑高举与雷霆扑劈」竖版 2×4 共 8 格：第 1~5 格拧身跨步将笔直发光长直剑高高举过头顶左上方蓄满千钧之力，鸦羽披肩随拔身大展；第 6~8 格全身重量灌注剑尖向右下前方暴烈重劈到底（直剑斜指右下4点钟），大弓步极低伏冲刺姿态极具终结技压迫感！"),

        ("S12", 2, 4, 1024, 1536, [
            raw_entry("attack_3", 8, sx=1.06, sy=0.93, lean=8.0), raw_entry("attack_3", 10, sx=1.04, sy=0.95, lean=6.0),
            raw_entry("attack_3", 12, sx=1.02, sy=0.97, lean=4.0), raw_entry("attack_3", 15, lean=2.0),
            raw_entry("attack_3", 19), raw_entry("attack_3", 23),
            raw_entry("attack_3", 26), raw_entry("attack_3", 29),
        ], "「普攻 3 段终结重劈后半：低伏定剑与稳健收势」竖版 2×4 共 8 格：第 1~3 格维持大弓步重劈低伏定剑姿势，笔直长直剑斜指右前地面，眼神锐利；第 4~8 格修净原图边缘杂色，少女收腿发力稳健起身、将笔直长直剑收回右后侧标准站姿。"),

        ("S13", 2, 4, 1024, 1536, [
            raw_entry("strong_attack", 0, sx=1.04, sy=0.95, lean=-3.0), raw_entry("strong_attack", 2, sx=1.06, sy=0.92, lean=-5.0),
            raw_entry("strong_attack", 4, sx=1.07, sy=0.91, lean=-5.0), raw_entry("strong_attack", 6, sx=1.02, sy=1.02, lean=4.0),
            raw_entry("strong_attack", 7, sx=0.95, sy=1.07, lean=6.0), raw_entry("strong_attack", 8, sx=0.94, sy=1.08, lean=6.0),
            raw_entry("strong_attack", 9, sx=0.95, sy=1.07, lean=5.0), raw_entry("strong_attack", 11, sx=0.96, sy=1.05, lean=3.0),
        ], "「上挑升龙强普前半：贴地深蹲蓄剑与冲天拔身挑斩」竖版 2×4 共 8 格：第 1~3 格极低深蹲沉腰，将笔直长直剑压在左后下方贴近地面蓄满寸劲；第 4~7 格双腿猛蹬地面如升龙般笔直冲天跃起，右臂将笔直发光长直剑自下而上一路高挑至头顶正上方（剑尖指12~1点钟），纵向拉伸剪影帅气凌厉；第 8 格高空扬剑定势！"),

        ("S14", 2, 4, 1024, 1536, [
            raw_entry("strong_attack", 13, sy=1.03, lean=2.0), raw_entry("strong_attack", 15, sy=1.01),
            raw_entry("strong_attack", 17), raw_entry("strong_attack", 19, sx=1.03, sy=0.97),
            raw_entry("strong_attack", 22, sx=1.02, sy=0.98), raw_entry("strong_attack", 25),
            raw_entry("strong_attack", 28), raw_entry("strong_attack", 30),
        ], "「上挑升龙强普后半：高位旋剑落定与归位」竖版 2×4 共 8 格：少女从高举笔直长直剑的冲顶姿态轻盈落回地面，双膝微屈缓冲卸力，同时右手将长剑利落旋回身侧右后方恢复备战站姿。"),

        ("S15", 2, 4, 1024, 1536, [
            raw_entry("air_attack_1", 0, lean=-3.0), raw_entry("air_attack_1", 2, lean=-5.0),
            raw_entry("air_attack_1", 4, lean=-4.0), raw_entry("air_attack_1", 6, lean=5.0),
            raw_entry("air_attack_1", 7, lean=7.0), raw_entry("air_attack_1", 8, lean=7.0),
            raw_entry("air_attack_1", 9, lean=5.0), raw_entry("air_attack_1", 10, lean=4.0),
        ], "「空连 1 段前半：滞空收腿蓄势与凌空横斩」竖版 2×4 共 8 格：全程双腿屈膝悬空滞空姿态！第 1~3 格在空中拧腰将笔直长直剑拉向左肩后上方蓄势；第 4~7 格空中猛然转体向右前下方挥出笔直长直剑（剑尖指3~4点钟），披肩在空中帅气飞展；第 8 格凌空定剑。"),

        ("S16", 3, 2, 1536, 1024, [
            raw_entry("air_attack_1", 11, lean=3.0), raw_entry("air_attack_1", 12, lean=2.0),
            raw_entry("air_attack_1", 14, lean=1.0), raw_entry("air_attack_1", 15),
            raw_entry("air_attack_1", 16), raw_entry("air_attack_1", 17),
        ], "「空连 1 段后半：凌空收剑回稳」横版 3×2 共 6 格：保持轻盈滞空屈膝姿态，将右前方的笔直长直剑平稳收回身侧右下方（修直原图模糊断剑），准备衔接二段空斩。"),

        ("S17", 2, 4, 1024, 1536, [
            raw_entry("air_attack_2", 0, lean=-3.0), raw_entry("air_attack_2", 1, lean=-4.0),
            raw_entry("air_attack_2", 2, lean=4.0), raw_entry("air_attack_2", 4, lean=7.0),
            raw_entry("air_attack_2", 5, lean=6.0), raw_entry("air_attack_2", 7, lean=4.0),
            raw_entry("air_attack_2", 9, lean=2.0), raw_entry("air_attack_2", 11),
        ], "「空连 2 段：凌空拧腰反手斜撩」竖版 2×4 共 8 格：彻底修净原图灰糊雾团与弯剑！全程悬空屈膝跃动姿：第 1~2 格滞空沉臂将直剑压在右下方蓄劲；第 3~5 格空中仰身拧腰将笔直长直剑从右下猛力反撩至右上方与头顶左上方，披肩飞扬极具空战美感；第 6~8 格空中高位持剑回稳。"),

        ("S18", 2, 4, 1024, 1536, [
            raw_entry("air_attack_3", 0, sy=1.03, lean=-4.0), raw_entry("air_attack_3", 2, sy=1.04, lean=-5.0),
            raw_entry("air_attack_3", 4, sy=1.05, lean=-6.0), raw_entry("air_attack_3", 6, sy=1.04, lean=-3.0),
            raw_entry("air_attack_3", 8, sx=1.04, lean=7.0), raw_entry("air_attack_3", 9, sx=1.05, lean=9.0),
            raw_entry("air_attack_3", 10, sx=1.05, lean=9.0), raw_entry("air_attack_3", 12, lean=7.0),
        ], "「空连 3 段前半：高空蜷身举剑与彗星俯冲重劈」竖版 2×4 共 8 格：第 1~4 格在空中收腿蓄势、双手将笔直发光长直剑高举过顶（11点钟方向）；第 5~8 格在空中全力向前下方俯冲纵劈（笔直长直剑猛劈向右下5点钟方向），身体舒展前倾充满高空斩落魄力！"),

        ("S19", 2, 4, 1024, 1536, [
            raw_entry("air_attack_3", 14, lean=5.0), raw_entry("air_attack_3", 16, lean=4.0),
            raw_entry("air_attack_3", 18, lean=3.0), raw_entry("air_attack_3", 20, lean=2.0),
            raw_entry("air_attack_3", 22, lean=1.0), raw_entry("air_attack_3", 23),
            raw_entry("air_attack_3", 24), raw_entry("air_attack_3", 25),
        ], "「空连 3 段后半：俯劈余势与滞空收剑」竖版 2×4 共 8 格：承接空中俯冲重劈姿态，少女在半空稳住身形，右手握笔直长直剑从右下逐步收回身侧，披肩自然垂落衔接下坠。"),

        ("S20", 2, 4, 1024, 1536, [
            raw_entry("dash_left", 0, sx=1.04, sy=0.96, lean=-5.0, hd_override=("dash_left", 0)),
            raw_entry("dash_left", 1, sx=1.06, sy=0.94, lean=-7.0, hd_override=("dash_left", 1)),
            raw_entry("dash_left", 3, sx=1.08, sy=0.92, lean=-9.0, hd_override=("dash_left", 2)),
            raw_entry("dash_left", 5, sx=1.09, sy=0.91, lean=-10.0, hd_override=("dash_left", 3)),
            raw_entry("dash_left", 6, sx=1.08, sy=0.92, lean=-9.0, hd_override=("dash_left", 3)),
            raw_entry("dash_left", 8, sx=1.07, sy=0.93, lean=-8.0, hd_override=("dash_left", 4)),
            raw_entry("dash_left", 9, sx=1.06, sy=0.94, lean=-7.0, hd_override=("dash_left", 4)),
            raw_entry("dash_left", 10, sx=1.05, sy=0.95, lean=-6.0, hd_override=("dash_left", 5)),
        ], "「朝左疾行冲刺斩前半：贴地掠影俯冲与急刹横斩」竖版 2×4 共 8 格（每一格必须是头身四肢 100% 完整的高清少女！）：第 1~5 格身体朝画面左侧极度压低前倾贴地高速疾冲，鸦羽披肩向右侧水平飞扬，右手将笔直长直剑反拖于右后方；第 6~8 格前靴急刹弓步，猛然拧腰将笔直发光长直剑横扫至左前方（剑尖水平指左9点钟），眼神凌厉杀气毕露！"),

        ("S21", 2, 4, 1024, 1536, [
            raw_entry("dash_left", 11, sx=1.05, sy=0.95, lean=-5.0, hd_override=("dash_left", 5)),
            raw_entry("dash_left", 12, sx=1.04, sy=0.96, lean=-4.0, hd_override=("dash_left", 6)),
            raw_entry("dash_left", 14, sx=1.02, sy=0.98, lean=-3.0, hd_override=("dash_left", 6)),
            raw_entry("dash_left", 16, lean=-2.0, hd_override=("dash_left", 7)),
            raw_entry("dash_left", 17, lean=-1.0), raw_entry("dash_left", 18),
            raw_entry("dash_left", 19), raw_entry("dash_left", 20),
        ], "「朝左疾行冲刺斩后半：刹步定剑与利落起身」竖版 2×4 共 8 格：第 1~3 格保持朝左低蹲急刹横斩终态，笔直长直剑稳指左前方；第 4~8 格从半蹲急刹姿态逐格干脆起身，收剑恢复沉稳备战姿。"),

        ("S22", 2, 4, 1024, 1536, [
            raw_entry("dash_right", 0, sx=1.04, sy=0.96, lean=5.0, hd_override=("dash_right", 0)),
            raw_entry("dash_right", 2, sx=1.07, sy=0.93, lean=8.0, hd_override=("dash_right", 1)),
            raw_entry("dash_right", 4, sx=1.09, sy=0.91, lean=10.0, hd_override=("dash_right", 2)),
            raw_entry("dash_right", 6, sx=1.09, sy=0.91, lean=10.0, hd_override=("dash_right", 3)),
            raw_entry("dash_right", 8, sx=1.07, sy=0.93, lean=8.0, hd_override=("dash_right", 4)),
            raw_entry("dash_right", 10, sx=1.06, sy=0.94, lean=7.0, hd_override=("dash_right", 4)),
            raw_entry("dash_right", 12, sx=1.05, sy=0.95, lean=6.0, hd_override=("dash_right", 5)),
            raw_entry("dash_right", 14, sx=1.04, sy=0.96, lean=5.0, hd_override=("dash_right", 5)),
        ], "「朝右疾行冲刺斩前半：猎豹俯冲疾掠与跨步一字横斩」竖版 2×4 共 8 格：第 1~4 格身体朝画面右侧大幅压低俯冲疾驰，鸦羽披肩向左侧水平拉出凌厉风压流线，笔直长直剑反拖左后方；第 5~8 格右脚大跨步踏地急刹，全身发力将笔直发光长直剑猛扫至右前方（剑尖指3点钟）！"),

        ("S23", 2, 4, 1024, 1536, [
            raw_entry("dash_right", 16, sx=1.03, sy=0.97, lean=4.0, hd_override=("dash_right", 6)),
            raw_entry("dash_right", 18, lean=3.0, hd_override=("dash_right", 6)),
            raw_entry("dash_right", 20, lean=2.0, hd_override=("dash_right", 7)),
            raw_entry("dash_right", 21, lean=1.0, hd_override=("dash_right", 7)),
            raw_entry("dash_right", 25), raw_entry("dash_right", 28),
            raw_entry("dash_right", 31), raw_entry("dash_right", 34),
        ], "「朝右疾行冲刺斩后半：滑步定剑与旋腕归位」竖版 2×4 共 8 格：第 1~3 格维持朝右大弓步突刺横斩定势，笔直长直剑斜指右前；第 4~8 格撤步收腿起身，右手将笔直长直剑利落旋回身侧右后方标准站姿。"),

        ("S24", 2, 4, 1024, 1536, [
            raw_entry("guard_start", 0), raw_entry("guard_start", 1, lean=-1.0),
            raw_entry("guard_start", 2, lean=-2.0), raw_entry("guard_start", 5, sx=1.02, sy=0.98, lean=-2.0),
            raw_entry("guard_start", 7, sx=1.03, sy=0.98, lean=-3.0), raw_entry("guard_start", 9, sx=1.02, sy=0.98, lean=-2.0),
            raw_entry("guard_start", 10, lean=-2.0), raw_entry("guard_start", 11, lean=-2.0),
        ], "「举剑架盾 / 弹刀起手」竖版 2×4 共 8 格：第 1~3 格少女眼神骤凛，右手迅速将笔直长直剑从身侧提向身前；第 4~8 格扎稳步法，右手高位握剑柄、左手轻抵护手侧，将笔直发光长直剑斜竖架在身前右侧严密防御位，剑脊泛出冷冽紫光！"),

        ("S25", 2, 4, 1024, 1536, [
            raw_entry("guard_hold", 0, lean=-2.0), raw_entry("guard_hold", 0, sy=1.01, lean=-2.0),
            raw_entry("guard_hold", 0, sy=1.02, lean=-2.5), raw_entry("guard_hold", 0, sy=1.02, lean=-2.5),
            raw_entry("guard_hold", 0, sy=1.01, lean=-2.0), raw_entry("guard_hold", 0, lean=-2.0),
            raw_entry("guard_hold", 0, sy=0.99, lean=-1.5), raw_entry("guard_hold", 0, lean=-2.0),
        ], "「持续格挡架盾呼吸循环」竖版 2×4 共 8 格：少女稳扎马步将笔直发光长直剑竖架身前凝神戒备；8 格构成细腻沉稳的备战呼吸循环——肩胸微不可察起伏、夜风吹动鸦羽披肩尾端与白挑染刘海轻微摆动，剑芯冷紫晶棱由暗渐亮再微收，冷酷帅气。"),

        ("S26", 2, 4, 1024, 1536, [
            raw_entry("guard_hit_1", 0, lean=-2.0), raw_entry("guard_hit_1", 1, sx=1.04, sy=0.96, lean=-5.0),
            raw_entry("guard_hit_1", 2, sx=1.05, sy=0.95, lean=-6.0), raw_entry("guard_hit_1", 3, sx=1.03, sy=0.97, lean=-4.0),
            raw_entry("guard_hit_1", 4, lean=-3.0), raw_entry("guard_hit_1", 6, lean=-2.5),
            raw_entry("guard_hit_1", 7, lean=-2.0), raw_entry("guard_hit_1", 8, lean=-2.0),
        ], "「轻格挡受击硬直」竖版 2×4 共 8 格：第 1~3 格敌刃轰在身前竖直长剑上，少女压膝沉腰微向后仰卸去冲力，披肩向后激扬，脸庞被剑锋冷紫强光映亮；第 4~8 格迅速稳住下盘顶回原防御架势。"),

        ("S27", 2, 4, 1024, 1536, [
            raw_entry("guard_hit_2", 0, lean=-3.0), raw_entry("guard_hit_2", 1, sx=1.05, sy=0.95, lean=-7.0),
            raw_entry("guard_hit_2", 2, sx=1.06, sy=0.94, lean=-8.0), raw_entry("guard_hit_2", 4, sx=1.04, sy=0.96, lean=-6.0),
            raw_entry("guard_hit_2", 6, lean=-4.0), raw_entry("guard_hit_2", 8, lean=-3.0),
            raw_entry("guard_hit_2", 10, lean=-2.5), raw_entry("guard_hit_2", 12, lean=-2.0),
        ], "「中格挡受击滑步卸力」竖版 2×4 共 8 格：第 1~4 格承受强力斩击，少女咬牙微眯单眼、重心压低向后半滑步硬抗冲击，双手紧撑笔直发光长直剑不退，披肩大幅扬起；第 5~8 格沉腰发力重新站稳防御姿态。"),

        ("S28", 2, 4, 1024, 1536, [
            raw_entry("guard_hit_3", 0, lean=-3.0), raw_entry("guard_hit_3", 3, sx=1.06, sy=0.93, lean=-9.0),
            raw_entry("guard_hit_3", 6, sx=1.07, sy=0.92, lean=-10.0), raw_entry("guard_hit_3", 9, sx=1.06, sy=0.93, lean=-8.0),
            raw_entry("guard_hit_3", 12, sx=1.04, sy=0.95, lean=-6.0), raw_entry("guard_hit_3", 16, lean=-4.0),
            raw_entry("guard_hit_3", 23, lean=-2.5), raw_entry("guard_hit_3", 33, lean=-2.0),
        ], "「重格挡破势大幅滑退」竖版 2×4 共 8 格：第 1~4 格遭遇千钧重击，少女极度压低重心屈膝向后滑退卸力，鸦羽披肩狂烈翻卷，双手死死架住笔直长直剑；第 5~8 格靴底刹住退势，稳健起身重整剑架！"),

        ("S29", 2, 4, 1024, 1536, [
            raw_entry("parry_react_1", 8, sx=1.03, lean=4.0, hd_override=("parry_react_1", 4)),
            raw_entry("parry_react_1", 9, sx=1.04, lean=5.0, hd_override=("parry_react_1", 5)),
            raw_entry("parry_react_1", 10, lean=3.0), raw_entry("parry_react_1", 11, lean=2.0),
            raw_entry("parry_react_1", 12, lean=1.0), raw_entry("parry_react_1", 13),
            raw_entry("parry_react_1", 14), raw_entry("parry_react_1", 15),
        ], "「弹刀 1 后半（第9~16帧）：拧腰反手左上撩开与定剑」竖版 2×4 共 8 格（全部画成腰腹双腿 100% 完整的高清人物与完整笔直长剑！）：第 1~2 格承接格开敌刃后猛然拧腰转半正面，右臂将笔直长直剑从身前猛力挥向画面左上方（10点钟方向），左臂在右下张开平衡，眼神杀气凛然；第 3~8 格双脚叉开稳立，右臂斜向左上（10点半方向）高举笔直长直剑潇洒定势收招！"),

        ("S30", 2, 4, 1024, 1536, [
            raw_entry("parry_react_2", 0), raw_entry("parry_react_2", 1, lean=-2.0),
            raw_entry("parry_react_2", 2, sx=1.03, lean=-4.0),
            raw_entry("parry_react_2", 3, sx=1.04, lean=-4.0, hd_override=("parry_react_2", 2)),
            raw_entry("parry_react_2", 4, sx=1.04, lean=-3.0, hd_override=("parry_react_2", 3)),
            raw_entry("parry_react_2", 5, lean=-1.0, hd_override=("parry_react_2", 4)),
            raw_entry("parry_react_2", 6, lean=2.0), raw_entry("parry_react_2", 7, lean=3.0),
        ], "「弹刀 2 前半：精准弹开敌刃与拧腰蓄反击」竖版 2×4 共 8 格（原图第4~6格缺失的双腿腰腹必须 100% 补全完整，去掉头顶杂块！）：第 1~3 格沉稳举剑迎击；第 4~5 格发力格弹开来袭刀锋，披肩激扬、身姿挺拔完整；第 6~8 格顺势拧腰将笔直长直剑拉向身侧蓄满反击寸劲！"),

        ("S31", 2, 4, 1024, 1536, [
            raw_entry("parry_react_2", 8, sx=1.05, lean=6.0), raw_entry("parry_react_2", 9, sx=1.05, lean=7.0),
            raw_entry("parry_react_2", 10, lean=5.0), raw_entry("parry_react_2", 11, lean=3.0),
            raw_entry("parry_react_2", 12, lean=2.0), raw_entry("parry_react_2", 13, lean=1.0),
            raw_entry("parry_react_2", 14), raw_entry("parry_react_2", 15),
        ], "「弹刀 2 后半：电光石火跨步斜劈反击与回稳」竖版 2×4 共 8 格：第 1~3 格借弹刀之势向前跨步猛劈出笔直发光长直剑，身形舒展凌厉；第 4~8 格利落收剑回归标准侧身备战站姿。"),

        ("S32", 2, 4, 1024, 1536, [
            raw_entry("parry_react_3", 0), raw_entry("parry_react_3", 1, lean=-3.0),
            raw_entry("parry_react_3", 3, sx=1.04, lean=-4.0),
            raw_entry("parry_react_3", 5, sx=1.05, lean=5.0, hd_override=("parry_react_3", 2)),
            raw_entry("parry_react_3", 6, sx=1.06, lean=7.0, hd_override=("parry_react_3", 3)),
            raw_entry("parry_react_3", 7, sx=1.05, lean=6.0, hd_override=("parry_react_3", 4)),
            raw_entry("parry_react_3", 8, lean=4.0), raw_entry("parry_react_3", 9, lean=3.0),
        ], "「弹刀 3 前半：大旋身卸力狂野弹反」竖版 2×4 共 8 格（严禁出现任何黄色色块，全部画成清晰完整的高清少女！）：第 1~3 格压低重心迎敌；第 4~6 格借重击之力帅气旋身大挥臂弹反，鸦羽披肩旋成华丽扇面，手中笔直发光长直剑大开大合横扫；第 7~8 格旋身余势持剑展开！"),

        ("S33", 2, 4, 1024, 1536, [
            raw_entry("parry_react_3", 10, lean=2.0), raw_entry("parry_react_3", 11, lean=1.0),
            raw_entry("parry_react_3", 13), raw_entry("parry_react_3", 14),
            raw_entry("parry_react_3", 16), raw_entry("parry_react_3", 17),
            raw_entry("parry_react_3", 18), raw_entry("parry_react_3", 19),
        ], "「弹刀 3 后半：旋身落定与潇洒收剑」竖版 2×4 共 8 格：少女从旋身弹反姿态稳稳踏地落定，披肩与发丝平顺垂落，右手握持笔直长直剑回归冷静备战站姿。"),

        ("S34", 2, 4, 1024, 1536, [
            raw_entry("draw", 0), raw_entry("draw", 7, sx=1.04, sy=0.96, lean=-3.0),
            raw_entry("draw", 13, sx=1.06, sy=0.94, lean=-4.0), raw_entry("draw", 17, sx=1.05, sy=0.95, lean=6.0),
            raw_entry("draw", 20, sx=1.04, lean=7.0), raw_entry("draw", 24, lean=4.0),
            raw_entry("draw", 31, lean=2.0), raw_entry("draw", 45),
        ], "「居合拔刀出鞘」竖版 2×4 共 8 格：第 1~3 格标准日式居合蓄势——沉腰压膝、左手按左腰剑鞘、右手握柄蓄满寸劲，眼神凝练如冰；第 4~5 格电光石火踏步拔剑横斩亮剑，右臂携笔直发光长直剑向身前右方凌厉展臂；第 6~8 格潇洒定剑回落至标准持剑备战姿。"),

        ("S35", 2, 4, 1024, 1536, [
            raw_entry("sheathe", 0), raw_entry("sheathe", 4, lean=2.0),
            raw_entry("sheathe", 8, lean=1.0), raw_entry("sheathe", 12),
            raw_entry("sheathe", 16, lean=-2.0), raw_entry("sheathe", 20, lean=-1.0),
            raw_entry("sheathe", 26), raw_entry("sheathe", 35),
        ], "「旋腕挽花收刀归鞘」竖版 2×4 共 8 格：第 1~3 格右手持笔直长直剑在身侧潇洒旋腕挽剑；第 4~5 格凝神将笔直剑身精准顺滑推入左腰剑鞘；第 6 格护手咔哒合拢入鞘瞬间手扶剑柄定格；第 7~8 格双手自然松开恢复清冷孤傲的收刀站姿。"),

        ("S36", 2, 4, 1024, 1536, [
            raw_entry("charge_hold", 0, sx=1.05, sy=0.94, lean=-4.0), raw_entry("charge_hold", 3, sx=1.05, sy=0.94, lean=-4.0),
            raw_entry("charge_hold", 6, sx=1.06, sy=0.93, lean=-4.5), raw_entry("charge_hold", 9, sx=1.06, sy=0.93, lean=-4.5),
            raw_entry("charge_hold", 12, sx=1.06, sy=0.93, lean=-4.5), raw_entry("charge_hold", 15, sx=1.05, sy=0.94, lean=-4.0),
            raw_entry("charge_hold", 18, sx=1.05, sy=0.94, lean=-4.0), raw_entry("charge_hold", 21, sx=1.05, sy=0.94, lean=-4.0),
        ], "「蓄力持续凝神聚气循环」竖版 2×4 共 8 格（去掉原图灰黑横扫描线脏纹）：少女极低深蹲压腰蓄力，紧握笔直发光长直剑蓄在身侧；8 格构成充满压迫感的蓄力循环——鸦羽披肩与发丝受脚底上升气旋吹拂向上狂舞飘扬，剑身冷紫晶芒强烈闪耀并在脸庞映出冷紫强光！"),

        ("S37", 2, 4, 1024, 1536, [
            raw_entry("charge_slash", 0, sx=1.06, sy=0.93, lean=-5.0), raw_entry("charge_slash", 3, sx=1.07, sy=0.92, lean=-6.0),
            raw_entry("charge_slash", 6, sx=1.08, sy=0.91, lean=-6.0), raw_entry("charge_slash", 9, sx=1.08, sy=0.91, lean=-7.0),
            raw_entry("charge_slash", 12, sx=1.09, sy=0.90, lean=-7.0), raw_entry("charge_slash", 15, sx=1.05, sy=0.95, lean=4.0),
            raw_entry("charge_slash", 17, sx=1.06, sy=0.94, lean=7.0), raw_entry("charge_slash", 18, sx=1.07, sy=0.93, lean=9.0),
        ], "「满蓄力断晓一闪（一）：蓄满极点与破界起斩」竖版 2×4 共 8 格：第 1~5 格少女重心压低到极限如满弦强弓，披肩发丝高扬，手中笔直长直剑迸发刺目冷紫白强光；第 6~8 格猛然踏步暴起拧腰挥斩，爆发毁天灭地的出刀初势！"),

        ("S38", 2, 4, 1024, 1536, [
            raw_entry("charge_slash", 19, sx=1.07, sy=0.93, lean=10.0), raw_entry("charge_slash", 20, sx=1.08, sy=0.92, lean=10.0),
            raw_entry("charge_slash", 22, sx=1.08, sy=0.92, lean=9.0), raw_entry("charge_slash", 24, sx=1.07, sy=0.93, lean=8.0),
            raw_entry("charge_slash", 26, sx=1.06, sy=0.94, lean=7.0), raw_entry("charge_slash", 28, sx=1.05, sy=0.95, lean=6.0),
            raw_entry("charge_slash", 30, sx=1.04, sy=0.96, lean=5.0), raw_entry("charge_slash", 32, sx=1.03, sy=0.97, lean=4.0),
        ], "「满蓄力断晓一闪（二）：高对比爆发与大跨步旋斩」竖版 2×4 共 8 格（修补原图胸口黑洞残缺，人物 100% 完整锐利！）：第 1 格画成极具视觉冲击力的冷紫炽白高对比受光爆发斩击姿态；第 2~8 格少女大跨步压身旋斩到底，鸦羽披肩狂烈飞展，右手紧握笔直发光长直剑向身前凌厉挥展！"),

        ("S39", 2, 4, 1024, 1536, [
            raw_entry("charge_slash", 34, lean=3.0), raw_entry("charge_slash", 36, lean=2.0),
            raw_entry("charge_slash", 38, lean=1.5), raw_entry("charge_slash", 40, lean=1.0),
            raw_entry("charge_slash", 43), raw_entry("charge_slash", 48),
            raw_entry("charge_slash", 56), raw_entry("charge_slash", 75),
        ], "「满蓄力断晓一闪（三）：大招余韵与从容收剑归位」竖版 2×4 共 8 格：少女从满蓄力挥斩跨步终态平稳收步起身，披肩缓缓落定，右手握笔直长直剑回归冷静孤傲的备战站姿。"),

        ("S40", 2, 4, 1024, 1536, [
            raw_entry("death", 0, lean=-3.0), raw_entry("death", 8, lean=-6.0),
            raw_entry("death", 14, lean=-8.0), raw_entry("death", 19, lean=-10.0),
            raw_entry("death", 22, lean=-11.0), raw_entry("death", 25, lean=-12.0),
            raw_entry("death", 28, lean=-12.0), raw_entry("death", 31, lean=-12.0),
        ], "「战败碎魂（一）：受创仰身与失重坠落」竖版 2×4 共 8 格：第 1~3 格少女遭受重创蹙眉闭眼、身体向后剧烈仰折；第 4~8 格呈现凄美具张力的失重后仰下落曲线，鸦羽披肩与发丝在空中散开，右手无力垂下笔直长直剑。"),

        ("S41", 2, 4, 1024, 1536, [
            raw_entry("death", 34), raw_entry("death", 37),
            raw_entry("death", 40), raw_entry("death", 43),
            raw_entry("death", 46), raw_entry("death", 50),
            raw_entry("death", 55), raw_entry("death", 70),
        ], "「战败碎魂（二）：坠地缓冲与唯美倒地终态」竖版 2×4 共 8 格：第 1~5 格少女顺势跌落地面、鸦羽披肩与裙摆铺散缓冲；第 6~8 格安静倒卧地面终态，双目轻阖，笔直长直剑横落在身旁（格内四周留足 #00FF00 纯绿边距，绝不碰黄框）。"),
    ]

    for s_tag, sc, sr, sw, sh, entries, s_detail in char_sheet_defs:
        lay = build_character_sheet_plate(s_tag, entries, sc, sr, sw, sh)
        size_desc = f"{sw}×{sh}（{sc} 列 × {sr} 行）"
        prompt = (
            f"用你的 image_gen 工具只生成 1 张 {size_desc} 图，不要生成第二张，不要运行任何命令、不要读或改项目里任何文件。"
            f"两张附图按顺序是图1（原动作分格骨架）、图2（主角原版高清人设参考）。生成完回复“完成”即可。图片要求如下：\n\n"
            f"图1 是{s_detail}\n\n"
            f"请把图1 每一格重画成与图2 100% 同一人设颜值、但剑戟发力动态更帅更有张力的高清赛璐璐动作帧：\n"
            f"{CHAR_STYLE_FOOTER}"
        )
        all_jobs.append({
            "id": s_tag,
            "kind": "char",
            "cols": sc,
            "rows": sr,
            "size": [sw, sh],
            "num_cells": len(entries),
            "scale": lay["scale"],
            "images": [
                str(PLATES_DIR / f"输入_{s_tag}.png"),
                str(PLATES_DIR / "ref_char_authentic.png"),
            ],
            "prompt": prompt,
        })

    manifest_fp = WORK_ROOT / "prompts_49.json"
    manifest_fp.write_text(json.dumps(all_jobs, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared {len(all_jobs)} pure-AI sheets ({sum(1 for j in all_jobs if j['kind']=='vfx')} VFX + {sum(1 for j in all_jobs if j['kind']=='char')} Char) -> {manifest_fp}")


if __name__ == "__main__":
    main()
