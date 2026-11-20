#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
精确校准主角普攻三连 (attack_1 / attack_2 / attack_3) 的每帧 (pivotX, pivotY)：
1. 用「中性墨黑衣靴 + 暖肤色」高纯度实体特征 100% 剥离 R3 巨型冷白/靛紫刀光干扰，精确定位每一帧的人物脊柱中心与最低靴底；
2. 消除普攻各帧靴子陷入地面 (+13px) 或单帧悬空跳起 (-32px，如 attack_2 f02) 的垂直抖动，全部锁死踩实地面线 (bot = 0.0px)；
3. 消除普攻内部单帧左右横跳 (±20..38px)，使每帧人物脊柱轴线平滑对齐 idle 基准线，同时 100% 保留原有 rootMotionX 与招式判定不变。
"""
from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
BATTLE_JSON = ASSETS / "data" / "battle.json"


def measure_pure_char_body(rgba: np.ndarray) -> tuple[float, float, float]:
    """
    通过中性暗墨衣靴 + 暖肤色特征彻底排除任何冷白/电光紫/深靛紫刀光与细剑尖干扰，
    返回源图像素系下的 (top_y, bot_y, spine_cx)。
    """
    al = rgba[..., 3]
    rgb = rgba[..., :3].astype(np.float32)
    luma = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]

    # 中性墨黑发/衣/丝袜/长靴 (B-G <= 12.5 且亮度 < 148) + 暖肤色
    dark_cloth_boot = (rgb[..., 2] - rgb[..., 1] <= 12.5) & (luma < 148.0)
    warm_skin = (rgb[..., 0] > rgb[..., 2] + 3.0) & (rgb[..., 0] - rgb[..., 1] > 5.0) & (luma < 228.0)
    pure_char = (al > 175) & (dark_cloth_boot | warm_skin)

    # 形态学闭连接短裙与黑丝靴，再用开运算断掉极细长剑杆
    closed = cv2.morphologyEx(pure_char.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 11)))
    opened = cv2.morphologyEx(closed, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
    if opened.sum() < 80:
        opened = pure_char.astype(np.uint8)

    n_c, lbl, st, _ = cv2.connectedComponentsWithStats(opened, 8)
    if n_c > 1:
        j = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        _, txs = np.where(lbl == j)
    else:
        _, txs = np.where(pure_char)

    torso_cx = float(np.median(txs)) if len(txs) > 0 else rgba.shape[1] * 0.5

    # 在躯干中心 ±125px 走廊内用原始高置信实体掩码恢复精确到 1px 的靴底最下沿与头顶！
    h_im, w_im = al.shape
    x_lo = max(0, int(round(torso_cx - 125)))
    x_hi = min(w_im, int(round(torso_cx + 125)))
    corridor = np.zeros_like(pure_char)
    corridor[:, x_lo:x_hi] = pure_char[:, x_lo:x_hi]

    n2, l2, s2, _ = cv2.connectedComponentsWithStats(corridor.astype(np.uint8), 8)
    clean_body = np.zeros_like(pure_char)
    for ci in range(1, n2):
        if s2[ci, cv2.CC_STAT_AREA] >= 20:
            clean_body |= (l2 == ci)
    if clean_body.sum() < 50:
        clean_body = pure_char

    bys, bxs = np.where(clean_body)
    top_y = float(bys.min())
    # 靴底严格在躯干正下方 ±66px 内测量，避免 attack_1 f09/f10 斜指地面的剑尖被误算为鞋底！
    foot_zone = clean_body[:, max(0, int(round(torso_cx - 66))):min(w_im, int(round(torso_cx + 66)))]
    f_ys, _ = np.where(foot_zone)
    bot_y = float(f_ys.max()) if len(f_ys) >= 10 else float(bys.max())
    bh = max(bot_y - top_y, 1.0)
    spine_band = (bys >= top_y + 0.20 * bh) & (bys <= top_y + 0.62 * bh)
    spine_cx = float(np.median(bxs[spine_band])) if spine_band.sum() >= 15 else torso_cx
    return top_y, bot_y, spine_cx


def main() -> None:
    battle = json.loads(BATTLE_JSON.read_text(encoding="utf-8"))
    sp = battle["characters"][0]["sprite"]
    anims = sp["animations"]

    # 以 idle f00 的脊柱偏移与脚底为全游戏唯一零点基准
    idle_f0 = anims["idle"]["frames"][0]
    im_idle = np.array(Image.open(ASSETS / idle_f0["asset"]).convert("RGBA"))
    _, ibot, iscx = measure_pure_char_body(im_idle)
    idle_spine_off = float(iscx - float(idle_f0["pivotX"]))
    print(f"Idle pure-body spine offset = {idle_spine_off:+.2f}px (bot={ibot:.1f}, pivY={idle_f0['pivotY']})")

    for ck in ("attack_1", "attack_2", "attack_3"):
        clip = anims[ck]
        fms = clip["frames"]
        for idx, fm in enumerate(fms):
            im = np.array(Image.open(ASSETS / fm["asset"]).convert("RGBA"))
            sh, sw = im.shape[:2]
            w = float(fm.get("width", sw))
            h = float(fm.get("height", sh))
            sx, sy = w / sw, h / sh

            fm.setdefault("pivotXBeforeAlignFix", fm["pivotX"])
            fm.setdefault("pivotYBeforeAlignFix", fm["pivotY"])

            _, by, scx = measure_pure_char_body(im)
            # 全部地面普攻帧靴底严格贴合地面线 (bot = 0.0)，脊柱严格对齐 idle 轴线
            new_px = (scx - idle_spine_off) * sx
            new_py = by * sy
            fm["pivotX"] = round(float(new_px), 3)
            fm["pivotY"] = round(float(new_py), 3)
        print(f"  [ALIGNED] {ck:12s}: {len(fms)} frames locked to ground & idle spine axis")

    BATTLE_JSON.write_text(json.dumps(battle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Saved aligned battle.json!")


if __name__ == "__main__":
    main()
