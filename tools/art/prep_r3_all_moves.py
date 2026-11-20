#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「方案 2：主角全部 16 套战斗挥斩招式 R3 真刀光全量重做」的 24 张 (#141620 暗棚底 + #FFFF00 黄框) 导引底板与锁风提示词：
1. 从已定稿的 生图_真刀光_v2_R1至R4.png 左下格裁出纯净 R3 母本 ref_R3_master.png 作为唯一 图2 标杆。
2. 对全部 16 套战斗招式（含别名剪辑）共 24 张图集 (S01..S24) 执行：
   - 历史坏帧（dash 无头/断头、parry_react_2/3 残腰吞身）采用 ai-hd 完好人物姿态作 图1 骨架；
   - 旧版实心白粉笔块/锯齿紫块/暖黄方块火花 100% 剥离，转化为与 输入_真刀光底板_v2 一致的 ~22% 半透明平滑 R3 轨迹导引纱；
   - 保存每格干净人物实心保护遮罩 body_mask_XX.png，供解包时刚体对齐 (385px 零跳变) 与黑银直剑/衣发实心锁死。
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
import overhaul_all_player_actions as OV  # noqa: E402
import recolor_slash as RS  # noqa: E402

ASSETS = ROOT / "assets"
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\R3全招式真刀光_20261115"
V2_R3_SRC = ROOT / r"docs\视觉设计\角色动作\真刀光样板_20261115\生图_真刀光_v2_R1至R4.png"
BACKUP_ANIMS_FP = ROOT / r"docs\视觉设计\角色动作\全动作精修与张力升级_20261114\backup_animations_before_overhaul.json"
BG_RGB = (20, 22, 32)  # #141620

# 24 张正片排期表：(sheet_id, clip_key, cols, rows, frame_indices, move_title, cell_notes)
SHEET_SPECS: list[dict[str, Any]] = [
    {
        "id": "S01", "clip": "attack_1", "cols": 2, "rows": 2, "frames": [4, 6, 7, 8],
        "title": "普攻1段·满弓月华连续挥斩演进",
        "desc": "承接图2满弓爆发帧(f05)的前后连续相位：左上格(f04)左上方举剑刚向下起刀拉出初生冷白新月弧与淡紫起势纱；右上格(f06)满弓冷白主刀肚向右前舒展变薄、左上尾丝渐散；左下格(f07)上半尾迹消散、保留右前至右下原长剑尖的流线冷白下半弯弧与紫纱；右下格(f08)右下原长直剑贴地收锋，留一抹纤细冷白微光与半透明紫雾余韵。",
    },
    {
        "id": "S02", "clip": "attack_2", "cols": 2, "rows": 2, "frames": [1, 2, 3, 4],
        "title": "普攻2段·压身横扫反撩前半",
        "desc": "压身向前横向反撩挥剑前半程：左上格(f01)压低身姿蓄势持原长直剑微闪寒芒；右上格(f02)贴地向右横扫初起，剑刃拉出低平流线冷白锋弧与紫纱；左下格(f03)与右下格(f04)长剑由右下极速横撩向左上高处，沿图1淡影甩出宽展饱满的R3冷白满弓横弧与薄如蝉翼的半透明电光紫尾纱。",
    },
    {
        "id": "S03", "clip": "attack_2", "cols": 2, "rows": 2, "frames": [5, 6, 7, 8],
        "title": "普攻2段·压身横扫反撩后半",
        "desc": "横向反撩挥剑后半收束程：左上格(f05)与右上格(f06)高处横向冷白弧锋继续向左上舒展收薄，内侧半透明紫纱柔顺渐隐；左下格(f07)弧光尾丝消散，仅余左上剑锋一缕轻透银紫余韵；右下格(f08)保持1.0×原长黑银直剑定势收招。",
    },
    {
        "id": "S04", "clip": "attack_3", "cols": 3, "rows": 2, "frames": [2, 3, 4, 5, 6, 7],
        "title": "普攻3段·升龙连斩起势与上撩",
        "desc": "从左向右按顺序为连续6帧由低向高大弧度上撩斩：第1格(f02)贴地蓄剑初闪；第2~3格(f03-f04)长剑由下向上猛烈撩起，右侧甩出饱满圆润的R3高亮冷白满弓外锋与半透明电光紫残影纱；第4~6格(f05-f07)刀光顺势旋过头顶上方，形成优美拱形冷白亮锋与渐隐紫纱尾丝。",
    },
    {
        "id": "S05", "clip": "attack_3", "cols": 3, "rows": 2, "frames": [8, 9, 10, 11, 24, 25],
        "title": "普攻3段·重劈砸地与收尾回旋斩",
        "desc": "上排左起3格与下排第1格(f08-f11)为高举过顶顺势向前下方重劈：刀光沿图1淡影由左上经前方向下扫出饱满圆润的R3冷白满弓锋肚与半透明紫纱，并保持1.0×原长直剑；下排后2格(f24-f25)为收招低身水平回旋横扫的轻灵冷白细锋与半透明紫纱弧。",
    },
    {
        "id": "S06", "clip": "attack_up", "cols": 3, "rows": 2, "frames": [7, 8, 9, 10, 11, 12],
        "title": "上挑强普·升龙满月挑飞斩",
        "desc": "由蹲身蓄力向上方大弧度挑飞重斩的连续6帧：第1~2格(f07-f08)低蹲持原长直剑蓄力起闪；第3~4格(f09-f10)长剑极速向上挑起，沿图1淡影甩出高耸饱满的R3高亮冷白大满弓外弧与丝滑半透明电光紫残影薄纱（严禁画死白实心块或水平杂线！）；第5~6格(f11-f12)高举原长直剑收势，弧尾化作纤细银紫流丝消散。",
    },
    {
        "id": "S07", "clip": "air_attack_1", "cols": 2, "rows": 2, "frames": [8, 9, 12, 13],
        "title": "空中普攻1段·腾空起挑与斜劈前半",
        "desc": "空中挥剑前半程：左上格(f08)与右上格(f09)在空中由下向上轻挑，右侧拉出灵动圆润的R3冷白弯弧与半透明紫纱；左下格(f12)与右下格(f13)从左上向右下斜向大幅劈斩，斜向甩出修长锐利的R3高亮冷白满弓切风锋线与通透电光紫渐变尾纱。",
    },
    {
        "id": "S08", "clip": "air_attack_1", "cols": 2, "rows": 2, "frames": [14, 15, 16, 17],
        "title": "空中普攻1段·斜劈上旋收束后半",
        "desc": "空中斜劈顺势向左上收束的连续4帧(f14-f17)：沿图1淡影保留左上高处圆润顺滑的R3冷白弧锋与薄如蝉翼的半透明电光紫残影纱，逐格变细变透自然消散，手中黑银紫晶直剑保持1.0×原长笔直清晰。",
    },
    {
        "id": "S09", "clip": "air_attack_2", "cols": 3, "rows": 2, "frames": [0, 1, 2, 3, 4, 5],
        "title": "空中普攻2段·旋身回环斩前半",
        "desc": "空中旋身回环挥斩前半6帧(f00-f05)：第1~2格起势微闪紫芒；第3格(f02)下方扫出流线冷白亮锋；第4~6格(f03-f05)刀光沿左侧向上圆润扫起，外缘为极致顺滑的高亮冷白满弓亮锋，内侧为连续半透明电光紫渐变薄纱。",
    },
    {
        "id": "S10", "clip": "air_attack_2", "cols": 3, "rows": 2, "frames": [6, 7, 8, 9, 10, 11],
        "title": "空中普攻2段·旋身回环斩后半",
        "desc": "空中旋身回环挥斩后半6帧(f06-f11)：刀光顺时针掠过头顶(f07)向右上与正右方(f08-f11)饱满甩出R3高亮冷白圆弧外锋，圆润顺接入原长直剑剑尖，内侧铺展薄如蝉翼的半透明电光紫刀风纱。",
    },
    {
        "id": "S11", "clip": "air_attack_3", "cols": 2, "rows": 2, "frames": [0, 1, 2, 3],
        "title": "空中普攻3段·大满月终结斩前半",
        "desc": "空中大满月终结重斩前半4帧(f00-f03)：左上与右上格(f00-f01)从左上方绕过身侧向右下甩出恢弘圆润的R3高亮冷白大满弓外锋与半透明电光紫宽幅残影纱（外弧自然圆润完整，严禁贴边平切！）；左下与右下格(f02-f03)刀光旋至头顶上方形成修长优美的冷白上弦月华弧与渐变紫纱。",
    },
    {
        "id": "S12", "clip": "air_attack_3", "cols": 2, "rows": 2, "frames": [4, 5, 6, 7],
        "title": "空中普攻3段·大满月终结斩后半",
        "desc": "空中大满月终结重斩后半收束4帧(f04-f07)：头顶至右上方的R3冷白细锋与薄透电光紫丝纱逐格变窄变淡，在右下格(f07)完全收归1.0×原长直剑，干净利落。",
    },
    {
        "id": "S13", "clip": "dash_right_video", "cols": 3, "rows": 2, "frames": [1, 3, 4, 6, 8, 9],
        "title": "右向冲刺斩·极速破风突刺段",
        "desc": "向右贴地极速冲刺突刺6帧：第1格(f01)蹬地起冲拉出轻透紫白破风流丝；第2~5格(f03,f04,f06,f08)女剑士压低完整身姿向右疾刺，沿1.0×原长直剑拉出流线型高亮冷白破风锐锋与向身后平滑消散的R3半透明电光紫气流纱（彻底消除方白块，人物头身完整清晰！）；第6格(f09)转为向右前低位圆润横扫R3满弓刀光。",
    },
    {
        "id": "S14", "clip": "dash_right_video", "cols": 3, "rows": 2, "frames": [10, 11, 12, 13, 14, 15],
        "title": "右向冲刺斩·拔刀满月升斩段",
        "desc": "右向冲刺终段挑斩6帧：第1~2格(f10-f11)低身向前甩出流畅圆润的R3冷白横弧刀光；第3~5格(f12-f14)顺势向上撩起恢弘圆润的R3高亮冷白大满弓刀弧与薄如蝉翼的半透明电光紫渐变尾纱（人物蹲姿头身100%完整清晰！）；第6格(f15)高举原长直剑收锋余晖渐隐。",
    },
    {
        "id": "S15", "clip": "dash_left_video", "cols": 3, "rows": 2, "frames": [1, 2, 4, 6, 8, 9],
        "title": "左向冲刺斩·极速破风突刺段",
        "desc": "向左贴地极速冲刺突刺6帧：第1~4格(f01,f02,f04,f06)女剑士压低完整身姿向左疾刺，沿原长直剑拉出流线型冷白破风锐锋与向身后渐隐的R3半透明电光紫气流纱（人物头身100%完整清晰！）；第5~6格(f08-f09)向左前下方扫出圆润高亮冷白R3满弓横斩弧与紫纱。",
    },
    {
        "id": "S16", "clip": "dash_left_video", "cols": 3, "rows": 2, "frames": [10, 11, 12, 13, 14, 15],
        "title": "左向冲刺斩·拔刀满月升斩段",
        "desc": "左向冲刺终段挑斩6帧：第1~4格(f10-f13)蹲身向上方甩出圆润饱满的R3高亮冷白大满弓外弧与丝滑半透明电光紫渐变残影纱，逐格向高处收薄；第5~6格(f14-f15)斜举1.0×原长直剑，刀尖残留纤细银紫流丝自然淡出。",
    },
    {
        "id": "S17", "clip": "parry", "cols": 2, "rows": 2, "frames": [7, 8, 9, 10],
        "title": "格挡架剑·撩剑立盾月华弧",
        "desc": "将直剑由左下撩起竖直格挡的连续4帧(f07-f10)：左上格(f07)蓄势提剑；右上格(f08)与左下格(f09)长剑由左下向右上极速撩起，沿图1淡影扫出一道优雅圆润的R3高亮冷白上挑弧锋与薄透电光紫尾纱；右下格(f10)竖剑成盾，弧尾轻柔消散。",
    },
    {
        "id": "S18", "clip": "guard_hit_1", "cols": 2, "rows": 2, "frames": [0, 1, 2, 3],
        "title": "格挡受击1·竖刃卸力寒芒弧",
        "desc": "双手竖直架住1.0×原长黑银直剑承受攻击的连续4帧(f00-f03)：在竖直剑刃前侧激发出贴合刃口的R3冷白月牙形卸力冲击亮弧与半透明电光紫震波薄雾（严禁画暖黄方块火花！），从左上到右下逐格柔和扩散淡出。",
    },
    {
        "id": "S19", "clip": "guard_hit_2", "cols": 2, "rows": 2, "frames": [4, 5, 6, 7],
        "title": "格挡受击2·剑尖弹震冷紫流光",
        "desc": "稳姿架剑卸开上路攻击的连续4帧(f04-f07)：保持1.0×原长直剑笔直清晰，在剑身上段与剑尖处迸发出纤细锐利的冷白切风弧线与半透明电光紫气流薄纱，逐格轻盈消散。",
    },
    {
        "id": "S20", "clip": "guard_hit_3", "cols": 2, "rows": 2, "frames": [9, 10, 11, 12],
        "title": "格挡受击3·重击滑步破风卸力弧",
        "desc": "承受重击稳稳架剑滑步卸力的连续4帧(f09-f12)：沿竖直原长直剑外侧扫出一道饱满锋利的R3冷白卸力弯弧与半透明电光紫破风气浪，随滑步向后逐格变薄变透自然归零。",
    },
    {
        "id": "S21", "clip": "parry_react_1", "cols": 3, "rows": 2, "frames": [1, 2, 3, 6, 8, 9],
        "title": "弹刀反击1·撩剑弹反与旋腕挥光",
        "desc": "弹刀反击1关键6帧：第1格(f01)持原长直剑准备；第2~3格(f02-f03)由左下向右上撩剑弹反，拉出圆润锋利的R3冷白外弧与半透明电光紫渐变尾纱；第4格(f06)竖直剑刃中段亮起纯粹锐利的冷白夹电光紫十字剑芒寒光；第5~6格(f08-f09)高举直剑旋腕向左上甩出一缕轻灵通透的R3冷白紫纱弧。",
    },
    {
        "id": "S22", "clip": "parry_react_2", "cols": 2, "rows": 2, "frames": [0, 1, 2, 3],
        "title": "弹刀反击2·下撩满弓破招弧",
        "desc": "弹刀反击2前半上撩破招4帧(f00-f03)：左上格(f00)压剑蓄势；右上格(f01)与左下格(f02)长剑由左下向右上猛然挑起，沿真实剑刃背侧扫出饱满顺滑的R3高亮冷白满弓弧锋与半透明电光紫残影薄纱；右下格(f03)提剑收势尾丝淡出。",
    },
    {
        "id": "S23", "clip": "parry_react_2", "cols": 3, "rows": 2, "frames": [5, 6, 8, 9, 10, 11],
        "title": "弹刀反击2·旋身反斩月华弧",
        "desc": "弹刀反击2后半旋身反击6帧(f05,f06,f08-f11)：各格女剑士头身双腿100%完整清晰；长剑由头顶上方顺时针向右侧劈落，沿图1淡影拉出圆润顺滑的R3冷白弧锋与半透明电光紫刀风纱，在最后格收归原长直剑。",
    },
    {
        "id": "S24", "clip": "parry_react_3", "cols": 3, "rows": 2, "frames": [1, 2, 7, 8, 9, 10],
        "title": "弹刀反击3·上挑破招与左上斜劈反击",
        "desc": "上排第1~2格(f01-f02)由左下向右上挑剑扫出圆润R3冷白弧锋与半透明紫纱；上排第3格(f07)女剑士完整身姿斜举1.0×原长黑银直剑蓄势微泛冷紫剑芒；下排3格(f08-f10)从左上高处向身前重劈，甩出修长饱满的R3高亮冷白满弓切风弧与通透电光紫渐变尾纱。",
    },
]


def prepare_r3_master_ref() -> Path:
    """从已批准的 生图_真刀光_v2_R1至R4.png 左下格提取无黄框纯净 R3 母本 (图2)。"""
    WORK_ROOT.mkdir(parents=True, exist_ok=True)
    src = Image.open(V2_R3_SRC).convert("RGB")
    arr = np.asarray(src)
    # 左下格 R3: x in [0..768], y in [512..1024]
    cell = arr[512:1024, 0:768].copy()
    # 清除四周 8px 黄框边并填回纯净 #141620
    cell[:8, :] = BG_RGB
    cell[-8:, :] = BG_RGB
    cell[:, :8] = BG_RGB
    cell[:, -8:] = BG_RGB
    out_fp = WORK_ROOT / "ref_R3_master.png"
    Image.fromarray(cell).save(out_fp)
    return out_fp


def build_single_frame_r3_guide(
    clip_key: str,
    idx: int,
    orig_anims: dict,
    cur_anims: dict,
    sprite_cfg: dict,
    ai_hd_data: dict,
) -> tuple[np.ndarray, np.ndarray, float, float, float, float]:
    """
    返回单帧在 1:1 世界像素画布 (+PAD) 上的：
    - comp_rgba: 合成了 ~22% R3 光学淡影导引 + 100% 清晰人物与原长剑的 RGBA (背景透明，供贴到 #141620 棚底上)
    - solid_body_mask: 供解包阶段锁死人物与黑银剑实心度的 uint8 alpha 遮罩
    - world_w, world_h, world_px, world_py
    """
    hd_map = OV.load_ai_hd_pose_map(ai_hd_data, clip_key)
    fd_orig = orig_anims[clip_key]["frames"][idx]

    # 1. 左右冲刺斩：采用 100% 完好无损的 ai-hd 人物躯干，叠加原视频对应帧的刀光轨迹淡影
    if clip_key in ("dash_right_video", "dash_left_video"):
        is_left = clip_key == "dash_left_video"
        raw_f, r_ww, r_wh, r_px, r_py = OV.load_original_unpadded_base(sprite_cfg, fd_orig)
        H_r, W_r = raw_f.shape[:2]
        sl_raw, _, _, _ = RS.classify(raw_f, r_py * (H_r / max(r_wh, 1e-4)), dash=True)

        if is_left:
            k_pick = 0 if idx <= 7 else (20 if idx <= 9 else (14 if idx <= 13 else 17))
        else:
            k_pick = 0 if idx <= 8 else (19 if idx <= 11 else 15)
        D_hd, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[k_pick]]
        D_body = OV.strip_aihd_white_streaks(D_hd)
        Hb, Wb = D_body.shape[:2]
        yy_b, xx_b = np.mgrid[0:Hb, 0:Wb]
        # 净除 k=14 / k=15 鞋底外侧残留的小白三角块，确保 100% 纯净人物+原长直剑
        rgb_bd = D_body[..., :3].astype(np.int16)
        foot_white = (yy_b > Hb - 28) & (rgb_bd.min(-1) >= 210)
        D_body[foot_white] = 0

        W_w = int(round(max(r_ww, ww) + 160))
        H_w = int(round(max(r_wh, wh) + 160))
        px_w = max(r_px, wpx) + 80.0
        py_w = max(r_py, wpy) + 80.0

        canvas_body = Image.new("RGBA", (W_w, H_w), (0, 0, 0, 0))
        b_im = Image.fromarray(D_body).resize((max(4, round(ww)), max(4, round(wh))), Image.Resampling.LANCZOS)
        canvas_body.alpha_composite(b_im, (round(px_w - wpx), round(py_w - wpy)))
        body_arr = np.asarray(canvas_body)

        sl_im = Image.fromarray((sl_raw.astype(np.uint8) * 255)).resize((max(4, round(r_ww)), max(4, round(r_wh))), Image.Resampling.BILINEAR)
        sl_canvas = Image.new("L", (W_w, H_w), 0)
        sl_canvas.paste(sl_im, (round(px_w - r_px), round(py_w - r_py)))
        sl_mask = np.asarray(sl_canvas) > 96

        # 为突刺段 (idx 2..8) 构造清晰的水平流线破风矛淡影（避免原视频碎白条诱导方砖块）
        if (is_left and 1 <= idx <= 7) or ((not is_left) and 1 <= idx <= 8):
            yy_g, xx_g = np.mgrid[0:H_w, 0:W_w].astype(np.float32)
            prog = (idx - 1) / 7.0
            reach = 165.0 + 95.0 * math.sin(prog * math.pi * 0.85)
            cy_lance = py_w - 135.0
            if is_left:
                dx_l = px_w - xx_g
                in_x = (dx_l >= -40.0) & (dx_l <= reach)
                t_x = np.clip((dx_l + 40.0) / (reach + 40.0), 0.0, 1.0)
            else:
                dx_l = xx_g - px_w
                in_x = (dx_l >= -40.0) & (dx_l <= reach)
                t_x = np.clip((dx_l + 40.0) / (reach + 40.0), 0.0, 1.0)
            half_h = 34.0 * (1.0 - 0.72 * (t_x ** 1.3)) * np.clip(t_x * 4.5, 0.2, 1.0)
            sl_mask = in_x & (np.abs(yy_g - cy_lance) <= half_h)

        return _compose_guide_and_body(body_arr, sl_mask, W_w, H_w, px_w, py_w)

    # 2. parry_react_3 f05..f10 与 parry_react_2 f05..f11 坏帧救援
    if clip_key == "parry_react_3" and idx >= 5 and len(hd_map) > 0:
        if idx in (5, 6, 7):
            D_hd, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[5]]
            PAD = 64
            W_w, H_w = round(ww) + 2 * PAD, round(wh) + 2 * PAD
            px_w, py_w = wpx + PAD, wpy + PAD
            c_im = Image.new("RGBA", (W_w, H_w), (0, 0, 0, 0))
            c_im.alpha_composite(Image.fromarray(D_hd).resize((round(ww), round(wh)), Image.Resampling.LANCZOS), (PAD, PAD))
            body_arr = np.asarray(c_im)
            sl_mask = np.zeros((H_w, W_w), dtype=bool)
            return _compose_guide_and_body(body_arr, sl_mask, W_w, H_w, px_w, py_w)
        elif idx in (8, 9, 10):
            k_use = 11 if idx in (8, 9) else 14
            D_hd, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[k_use]]
            raw_f, r_ww, r_wh, r_px, r_py = OV.load_original_unpadded_base(sprite_cfg, fd_orig)
            sl_raw, _ = OV.detect_universal_slash_and_spark(raw_f.copy(), r_py * (raw_f.shape[0] / max(r_wh, 1e-4)), clip_key, idx)
            D_body = OV.strip_aihd_white_streaks(D_hd)
            W_w = int(round(max(r_ww, ww) + 140))
            H_w = int(round(max(r_wh, wh) + 140))
            px_w, py_w = max(r_px, wpx) + 70.0, max(r_py, wpy) + 70.0
            c_im = Image.new("RGBA", (W_w, H_w), (0, 0, 0, 0))
            c_im.alpha_composite(Image.fromarray(D_body).resize((round(ww), round(wh)), Image.Resampling.LANCZOS), (round(px_w - wpx), round(py_w - wpy)))
            sl_im = Image.fromarray((sl_raw.astype(np.uint8) * 255)).resize((round(r_ww), round(r_wh)), Image.Resampling.BILINEAR)
            sl_c = Image.new("L", (W_w, H_w), 0)
            sl_c.paste(sl_im, (round(px_w - r_px), round(py_w - r_py)))
            return _compose_guide_and_body(np.asarray(c_im), np.asarray(sl_c) > 96, W_w, H_w, px_w, py_w)

    if clip_key == "parry_react_2" and idx == 5:
        fd_f4 = orig_anims["parry_react_2"]["frames"][4]
        D4, ww, wh, wpx, wpy = OV.load_original_unpadded_base(sprite_cfg, fd_f4)
        D4[:int(D4.shape[0] * 0.14), :] = 0
        PAD = 56
        W_w, H_w = round(ww) + 2 * PAD, round(wh) + 2 * PAD
        c_im = Image.new("RGBA", (W_w, H_w), (0, 0, 0, 0))
        c_im.alpha_composite(Image.fromarray(D4).resize((round(ww), round(wh)), Image.Resampling.LANCZOS), (PAD, PAD))
        return _compose_guide_and_body(np.asarray(c_im), np.zeros((H_w, W_w), dtype=bool), W_w, H_w, wpx + PAD, wpy + PAD)

    # 3. 常规与已有高清剪辑：用原始未染紫帧精确提取刀光轨迹遮罩，叠加干净人物实体
    if clip_key in ("attack_1", "parry_react_1"):
        # 人物部分优先取已 1:1 高清重画的 redraw_20261115 底座（剔除外部旧刀光），刀光轨迹取原版无紫染白刀光遮罩
        fd_cur = cur_anims[clip_key]["frames"][idx]
        cur_im = Image.open(ASSETS / fd_cur["asset"]).convert("RGBA")
        c_ww, c_wh, c_px, c_py = float(fd_cur["width"]), float(fd_cur["height"]), float(fd_cur["pivotX"]), float(fd_cur["pivotY"])
        D_cur = np.asarray(cur_im.resize((round(c_ww), round(c_wh)), Image.Resampling.LANCZOS)).copy()

        D_raw, r_ww, r_wh, r_px, r_py = OV.load_original_unpadded_base(sprite_cfg, fd_orig)
        H_r, W_r = D_raw.shape[:2]
        sx_r, sy_r = W_r / max(r_ww, 1e-4), H_r / max(r_wh, 1e-4)
        px_r, py_r = r_px * sx_r, r_py * sy_r
        yy_r, xx_r = np.mgrid[0:H_r, 0:W_r]
        rgb_r = D_raw[..., :3].astype(np.int16)
        mx_r, ch_r = rgb_r.max(-1), rgb_r.max(-1) - rgb_r.min(-1)
        vest_r = (np.abs(xx_r - px_r) < 34 * sx_r) & (yy_r > py_r - 238 * sy_r) & (yy_r < py_r - 172 * sy_r)
        skin_r = OV.compute_skin_shield(D_raw) & (np.abs(xx_r - px_r) < 56 * sx_r) & (yy_r > py_r - 325 * sy_r) & (yy_r < py_r - 52 * sy_r) & (rgb_r.min(-1) < 224)
        sl_raw = (D_raw[..., 3] > 25) & (~vest_r) & (~skin_r) & (
            ((mx_r >= 162) & (ch_r <= 42))
            | ((rgb_r[..., 0] >= 185) & (rgb_r[..., 1] >= 135) & ((rgb_r[..., 0] - rgb_r[..., 2]) >= 26))
        )

        W_w = int(round(max(c_ww, r_ww) + 128))
        H_w = int(round(max(c_wh, r_wh) + 128))
        px_w, py_w = max(c_px, r_px) + 64.0, max(c_py, r_py) + 64.0

        sl_im = Image.fromarray((sl_raw.astype(np.uint8) * 255)).resize((round(r_ww), round(r_wh)), Image.Resampling.BILINEAR)
        sl_c = Image.new("L", (W_w, H_w), 0)
        sl_c.paste(sl_im, (round(px_w - r_px), round(py_w - r_py)))
        sl_mask = np.asarray(sl_c) > 96

        c_canvas = Image.new("RGBA", (W_w, H_w), (0, 0, 0, 0))
        c_canvas.alpha_composite(Image.fromarray(D_cur), (round(px_w - c_px), round(py_w - c_py)))
        body_arr = np.asarray(c_canvas).copy()
        yy, xx = np.mgrid[0:H_w, 0:W_w]
        rgb_b = body_arr[..., :3].astype(np.int16)
        skin_s = (
            OV.compute_skin_shield(body_arr)
            & (np.abs(xx - px_w) < 56)
            & (yy > py_w - 325)
            & (yy < py_w - 52)
            & (rgb_b.min(-1) < 224)
        )
        vest_z = (np.abs(xx - px_w) < 36) & (yy > py_w - 240) & (yy < py_w - 170)
        core_z = (xx >= px_w - 125) & (xx <= px_w + 105) & (yy >= py_w - 390) & (yy <= py_w + 24)
        sl_dil = cv2.dilate(sl_mask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21))) > 0
        bright_old = (rgb_b.max(-1) >= 158) | ((rgb_b[..., 2] >= 145) & ((rgb_b[..., 2] - rgb_b[..., 1]) >= 22))
        erase_ext = ((~core_z) & (sl_dil | bright_old)) & (~skin_s) & (~vest_z)
        body_arr[erase_ext] = 0
        # 躯干内部若被旧白刀光横穿，柔和压回深灰衣料底色而非挖洞，100% 保持身姿实心完整！
        cross_torso = core_z & sl_mask & (rgb_b.min(-1) >= 175) & (~skin_s) & (~vest_z)
        body_arr[cross_torso, :3] = (28, 28, 40)
        body_arr = OV.AIVfxLibrary._clean_tiny_isolated_specks(body_arr, min_keep_area=65)
        return _compose_guide_and_body(body_arr, sl_mask, W_w, H_w, px_w, py_w)

    # 其余全部剪辑（backup_animations_before_overhaul.json 中原版刀光全为无色相白灰，绝无紫色刀光；蓝紫色 100% 是角色发梢/鸦羽/宝石！）
    D0, ww, wh, wpx, wpy = OV.load_original_unpadded_base(sprite_cfg, fd_orig)
    H0, W0 = D0.shape[:2]
    sx, sy = W0 / max(ww, 1e-4), H0 / max(wh, 1e-4)
    px0, py0 = wpx * sx, wpy * sy
    strip_dust = (clip_key in OV.GROUND_DUST_CLIPS) or (clip_key in ("attack_2", "attack_3"))
    D_clean = OV.clean_stray_and_muddy_dust(D0.copy(), ground_y_px=py0, strip_muddy_dust=strip_dust)
    yy0, xx0 = np.mgrid[0:H0, 0:W0]
    if clip_key in ("attack_2", "attack_3"):
        D_clean[(xx0 < px0 - 185 * sx) | (xx0 > px0 + 700 * sx)] = 0

    rgb = D_clean[..., :3].astype(np.int16)
    mx = rgb.max(-1)
    ch = mx - rgb.min(-1)
    skin_s = (
        OV.compute_skin_shield(D_clean)
        & (np.abs(xx0 - px0) < 56 * sx)
        & (yy0 > py0 - 330 * sy)
        & (yy0 < py0 - 52 * sy)
        & (rgb.min(-1) < 224)
    )
    vest_zone = (np.abs(xx0 - px0) < 34 * sx) & (yy0 > py0 - 238 * sy) & (yy0 < py0 - 172 * sy)
    head_zone = (np.abs(xx0 - px0) < 76 * sx) & (yy0 > py0 - 388 * sy) & (yy0 < py0 - 232 * sy)
    core_char_zone = (np.abs(xx0 - px0) < 92 * sx) & (yy0 > py0 - 388 * sy) & (yy0 < py0 + 24 * sy)
    # 角色自带蓝紫发梢、鸦羽披肩、紫晶胸针与靴底 100% 免疫擦除！
    purple_char_parts = (rgb[..., 2] >= 105) & ((rgb[..., 2] - rgb[..., 1]) >= 22)

    outside_protected = (~skin_s) & (~vest_zone) & (~purple_char_parts) & (~(head_zone & (mx < 215)))
    white_sl = (D_clean[..., 3] > 20) & outside_protected & (mx >= 158) & (ch <= 42)
    warm_sp = (D_clean[..., 3] > 20) & outside_protected & (rgb[..., 0] >= 185) & (rgb[..., 1] >= 135) & ((rgb[..., 0] - rgb[..., 2]) >= 26)
    cand = white_sl | warm_sp

    n_c, lbl, st, _ = cv2.connectedComponentsWithStats(cand.astype(np.uint8), connectivity=8)
    sl0 = np.zeros((H0, W0), dtype=bool)
    min_sl_area = 80 if clip_key in ("guard_hit_1", "guard_hit_2", "guard_hit_3", "parry_react_1") else 140
    for ci in range(1, n_c):
        if st[ci, cv2.CC_STAT_AREA] >= min_sl_area:
            sl0 |= (lbl == ci)

    # 擦除身外旧白刀光及其外缘深灰抗锯齿残壳；躯干内部横穿处压暗回衣料色，绝不挖破头身五官！
    sl_dil = cv2.dilate(sl0.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13))) > 0
    char_protect = skin_s | vest_zone | head_zone | purple_char_parts | (core_char_zone & (~sl0) & (mx < 155) & (D_clean[..., 3] > 150))
    D_body0 = D_clean.copy()
    D_body0[sl_dil & (~core_char_zone) & (~char_protect)] = 0
    cross_core = core_char_zone & sl0 & (~skin_s) & (~vest_zone) & (~head_zone) & (~purple_char_parts)
    D_body0[cross_core, :3] = (28, 28, 40)
    if clip_key == "attack_up" and idx in (9, 10):
        D_body0[(xx0 > px0 + 95 * sx) & (mx >= 145)] = 0
    D_body0 = OV.AIVfxLibrary._clean_tiny_isolated_specks(D_body0, min_keep_area=60)

    PAD = 68
    W_w, H_w = int(round(ww)) + 2 * PAD, int(round(wh)) + 2 * PAD
    px_w, py_w = wpx + PAD, wpy + PAD
    pad_raw = max(8, round(PAD * sx))
    sl_taper = OV.taper_clipped_mask_borders(sl0, pad_raw)
    sl_im = Image.fromarray((sl_taper.astype(np.uint8) * 255)).resize((W_w, H_w), Image.Resampling.BILINEAR)
    sl_mask = np.asarray(sl_im) > 96

    body_im = Image.fromarray(D_body0).resize((max(4, round(ww)), max(4, round(wh))), Image.Resampling.LANCZOS)
    canvas_body = Image.new("RGBA", (W_w, H_w), (0, 0, 0, 0))
    canvas_body.alpha_composite(body_im, (PAD, PAD))
    body_arr = np.asarray(canvas_body)
    return _compose_guide_and_body(body_arr, sl_mask, W_w, H_w, px_w, py_w)


def _compose_guide_and_body(
    body_arr: np.ndarray,
    sl_mask: np.ndarray,
    W_w: int,
    H_w: int,
    px_w: float,
    py_w: float,
) -> tuple[np.ndarray, np.ndarray, float, float, float, float]:
    """将二值刀光轨迹遮罩转化为 ~22% 不透明度的平滑 R3 光学导引纱，并叠上清晰人物底座。"""
    sm = cv2.GaussianBlur(sl_mask.astype(np.float32), (0, 0), 6.2)
    sm_bin = sm > 0.34
    guide = np.zeros((H_w, W_w, 4), dtype=np.uint8)
    if sm_bin.any():
        yy, xx = np.mgrid[0:H_w, 0:W_w].astype(np.float32)
        rad = np.hypot(xx - px_w, (yy - (py_w - 185.0)) / 0.82)
        r_min = float(np.percentile(rad[sm_bin], 8))
        r_max = float(np.percentile(rad[sm_bin], 98))
        r_norm = np.clip((rad - r_min) / max(r_max - r_min, 24.0), 0.0, 1.0)
        soft_edge = np.clip(sm * 1.45, 0.0, 1.0)
        alpha_f = np.where(sm > 0.05, soft_edge * (0.07 + 0.16 * (r_norm ** 1.75)), 0.0)
        alpha_f = cv2.GaussianBlur(alpha_f, (0, 0), 2.8)
        whiteness = np.clip(r_norm ** 2.5, 0.0, 1.0)
        guide[..., 0] = (152 + 95 * whiteness).astype(np.uint8)
        guide[..., 1] = (86 + 154 * whiteness).astype(np.uint8)
        guide[..., 2] = 255
        guide[..., 3] = np.clip(np.round(alpha_f * 255.0), 0, 255).astype(np.uint8)

    comp = Image.fromarray(guide)
    comp.alpha_composite(Image.fromarray(body_arr))
    comp_arr = np.asarray(comp)

    # 紧致裁剪活跃区域（保留 24px 呼吸留白，消除 1920x1080 空画布缩水！）
    active = (comp_arr[..., 3] > 5) | (body_arr[..., 3] > 10)
    ys, xs = np.nonzero(active)
    if len(xs) == 0:
        bx0, by0, bx1, by1 = 0, 0, W_w, H_w
    else:
        bx0 = max(0, int(xs.min()) - 28)
        by0 = max(0, int(ys.min()) - 24)
        bx1 = min(W_w, int(xs.max()) + 32)
        by1 = min(H_w, int(ys.max()) + 24)

    crop_comp = comp_arr[by0:by1, bx0:bx1].copy()
    crop_body_rgba = body_arr[by0:by1, bx0:bx1].copy()
    new_ww = float(bx1 - bx0)
    new_wh = float(by1 - by0)
    new_px = float(px_w - bx0)
    new_py = float(py_w - by0)
    return crop_comp, crop_body_rgba, new_ww, new_wh, new_px, new_py


def make_prompt_for_sheet(spec: dict[str, Any]) -> str:
    cols, rows = spec["cols"], spec["rows"]
    n_cells = len(spec["frames"])
    return f"""请严格参考图1的 {cols}×{rows} 共 {n_cells} 格人物姿势、1.0×原长直剑与各格挥剑刀光淡影位置，并以图2（已定稿的 R3 满弓月华流光斩母本）为唯一角色外观与刀光光学质感标杆，输出1张横版 1536×1024 的深暗灰底2D横版动作游戏挥剑刀光序列帧（{spec['title']}）。

【全局铁律】
1. 背景统一为纯净均匀的深暗灰摄影棚底色 (#141620)，保留每格四周细 #FFFF00 边框；严禁画地面、雨丝、烟尘块、建筑或任何文字标号；刀光严格收在各自黄框内部，绝不触碰黄线硬切。
2. 各格女剑士的姿势、位置、人物身高比例与图1 100% 一致（头身四肢完整清晰）；脸部清冷五官、黑渐变蓝紫短发、额前白挑染、紫晶鸦羽发夹、头顶空心呆毛环与黑衣银饰短装严格对齐图2。
3. 【剑身原长锁死】：女剑士手中的黑银紫晶符文直剑必须 100% 保持原长笔直清晰，严禁把实体长剑向前拉长成细长光棍或画弯！
4. 【100% 复刻图2的 R3 满弓月华流光斩质感】：
   - 严格沿着图1各格淡影所示的挥砍圆弧位置与方向绘制刀光；
   - 外圈主切割弧为极致顺滑圆润的高亮冷白满弓亮锋（前缘圆润相切衔接剑尖与剑刃，零90°死折角、零锯齿毛刺）；
   - 内侧铺展与图2完全一致的薄如蝉翼、从明亮电光紫平滑过渡到完全融入 #141620 深暗灰底色的半透明光学运动残影薄纱，起刀尾端化作两三缕极细同心银紫流丝自然消失；
   - 所有内部光纱与细丝必须 100% 与外弧平行同心弯曲，严禁聚成折扇扇骨；严禁塞入水晶、独立弯月亮摆件、魔法阵、钟盘、黄色方块火花或羽毛堆等杂物！

【本张分格动作与相位要求】
{spec['desc']}
"""


def main() -> None:
    ref_r3 = prepare_r3_master_ref()
    print(f"Prepared R3 master ref -> {ref_r3}")

    orig_anims = json.loads(BACKUP_ANIMS_FP.read_text(encoding="utf-8"))
    battle = json.loads((ASSETS / "data/battle.json").read_text(encoding="utf-8"))
    sprite_cfg = battle["characters"][0]["sprite"]
    cur_anims = sprite_cfg["animations"]
    ai_hd_data = json.loads((ASSETS / "data/ai-hd-visuals.json").read_text(encoding="utf-8"))

    grid_W, grid_H = 1536, 1024
    index_manifest = []

    for spec in SHEET_SPECS:
        sid = spec["id"]
        clip_key = spec["clip"]
        cols, rows = int(spec["cols"]), int(spec["rows"])
        f_idxs = list(spec["frames"])
        cw, ch = grid_W // cols, grid_H // rows
        pad_x = 34 if cols <= 2 else (26 if cols == 3 else 20)
        pad_y = 32

        s_dir = WORK_ROOT / f"{sid}_{clip_key}"
        s_dir.mkdir(parents=True, exist_ok=True)

        # 提取本板所有帧并计算同一张板内的统一缩放比 scale，保证同板所有人物 100% 等高！
        cell_items = []
        max_bw, max_bh = 1.0, 1.0
        for fi in f_idxs:
            comp_arr, body_mask, ww, wh, px, py = build_single_frame_r3_guide(
                clip_key, fi, orig_anims, cur_anims, sprite_cfg, ai_hd_data
            )
            max_bw = max(max_bw, ww)
            max_bh = max(max_bh, wh)
            cell_items.append((fi, comp_arr, body_mask, ww, wh, px, py))

        scale = min(1.0, (cw - 2 * pad_x) / max_bw, (ch - 2 * pad_y) / max_bh)
        sheet_rgba = Image.new("RGBA", (grid_W, grid_H), (*BG_RGB, 255))
        frames_meta = []

        for c_idx, (fi, comp_arr, body_rgba, ww, wh, px, py) in enumerate(cell_items):
            rr, cc = divmod(c_idx, cols)
            cx0, cy0 = cc * cw, rr * ch
            pw = max(4, round(ww * scale))
            ph = max(4, round(wh * scale))
            local_ox = (cw - pw) // 2
            local_oy = (ch - ph) // 2
            ox = cx0 + local_ox
            oy = cy0 + local_oy

            resized_comp = Image.fromarray(comp_arr).resize((pw, ph), Image.Resampling.LANCZOS)
            sheet_rgba.alpha_composite(resized_comp, (ox, oy))

            body_fp = f"body_rgba_{c_idx:02d}.png"
            Image.fromarray(body_rgba).save(s_dir / body_fp)

            frames_meta.append({
                "cell_idx": c_idx,
                "clip": clip_key,
                "frame_idx": fi,
                "cell": [cx0, cy0, cw, ch],
                "placed_sheet": [ox, oy, pw, ph],
                "placed_cell": [local_ox, local_oy, pw, ph],
                "orig_size": [round(ww), round(wh)],
                "orig_pivot": [round(px, 3), round(py, 3)],
                "body_rgba_file": body_fp,
            })

        sheet_rgb = sheet_rgba.convert("RGB")
        draw = ImageDraw.Draw(sheet_rgb)
        for rr in range(rows):
            for cc in range(cols):
                x0, y0 = cc * cw, rr * ch
                draw.rectangle([x0 + 1, y0 + 1, x0 + cw - 2, y0 + ch - 2], outline=(255, 255, 0), width=3)

        guide_fp = s_dir / "输入_导引底板.png"
        sheet_rgb.save(guide_fp)
        prompt_text = make_prompt_for_sheet(spec)
        (s_dir / "提示词.txt").write_text(prompt_text, encoding="utf-8")

        lay_meta = {
            "sheet_id": sid,
            "clip": clip_key,
            "title": spec["title"],
            "bg_rgb": list(BG_RGB),
            "size": [grid_W, grid_H],
            "cols": cols,
            "rows": rows,
            "scale": round(scale, 5),
            "frames": frames_meta,
        }
        (s_dir / "输入_排版.json").write_text(json.dumps(lay_meta, ensure_ascii=False, indent=2), encoding="utf-8")
        index_manifest.append({
            "sheet_id": sid,
            "dir": s_dir.name,
            "clip": clip_key,
            "title": spec["title"],
            "cols": cols,
            "rows": rows,
            "scale": round(scale, 4),
            "frames": f_idxs,
        })
        print(f"[{sid}] {clip_key:17s} {cols}x{rows} ({len(f_idxs)}f) | scale={scale:.4f} -> {s_dir.name}")

    (WORK_ROOT / "sheets_index.json").write_text(json.dumps(index_manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared all {len(index_manifest)} sheets in {WORK_ROOT}")


if __name__ == "__main__":
    main()
