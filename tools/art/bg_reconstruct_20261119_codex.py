#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线重构档（2026-11-19，按 Claude 任务书 §3.2 / §3.4 / §3.5）：
1. 自动为 B1 / B2 / B3 / C1 生成：
   - 绿底对齐原图 (*_green.png)
   - 灰度明暗主次规划图 (*_value_plan.png)：上半部约 40% 压入暗夜雨雾、少细节低反差；
     人走的一层（街面到二层步廊）细节和暖光最集中，每屏只留 1~2 个焦点灯。
2. 并行调用 Codex (gpt-6.1-terra, medium) 重画 B1 / B2 / B3 / C1（严格锁死可走结构轮廓，
   打破楼栋重复感，统一 C1 消除偏蓝接缝）以及有厚度的哥特石街沿 street_thick。

产物目录：docs/_当前分支草稿/背景线/重构档_20261119/原图/
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(r"E:\00game\nightcrow-godot")
BASE = ROOT / "docs" / "_当前分支草稿" / "背景线" / "重构档_20261119"
IN_DIR = BASE / "输入"
OUT_DIR = BASE / "原图"
TWO_LVL = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level"
D2_DIR = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_d2"
D2_REF = ROOT / "docs" / "_当前分支草稿" / "背景线" / "侧视方向_20261119" / "D2.png"
GEN = Path.home() / ".codex" / "generated_images"

RED = (
    "【红线】紫色/品红严禁出现在任何背景、窗、灯、雾中；"
    "禁海、禁水洼、禁积水、禁镜面倒影（湿石板只留极薄一层湿光）；"
    "禁码头、船、绳子、木桶、木箱、行人动物、血肉、白瓷石化、正面钟表盘、文字UI边框。"
)


def prep_inputs() -> None:
    IN_DIR.mkdir(parents=True, exist_ok=True)
    # 每张图的焦点暖光区（归一化 x, y, rx, ry），仅 1~2 处，其余全部压暗拉开明暗主次
    focus_map = {
        "B1": [(0.14, 0.76, 0.14, 0.16), (0.86, 0.78, 0.16, 0.16)],
        "B2": [(0.50, 0.78, 0.15, 0.18), (0.82, 0.76, 0.14, 0.15)],
        "B3": [(0.37, 0.74, 0.14, 0.16), (0.69, 0.62, 0.15, 0.18)],
        "C1": [(0.36, 0.76, 0.16, 0.18), (0.50, 0.56, 0.13, 0.15)],
    }
    for code in ["B1", "B2", "B3", "C1"]:
        src = (D2_DIR / f"{code}.png") if (D2_DIR / f"{code}.png").exists() else (TWO_LVL / f"{code}.png")
        im = Image.open(src).convert("RGBA").resize((1672, 941), Image.Resampling.LANCZOS)
        arr = np.asarray(im, dtype=np.float32) / 255.0
        a = arr[..., 3:4]
        green_bg = np.zeros_like(arr[..., :3])
        green_bg[..., 1] = 1.0
        comp = arr[..., :3] * a + green_bg * (1.0 - a)
        Image.fromarray((np.clip(comp, 0, 1) * 255).astype(np.uint8), "RGB").save(IN_DIR / f"{code}_green.png")

        # 生成灰度明暗规划图（Value Plan）：
        # y=0..42% 极暗（0.08~0.16 压入雨雾、低细节），y=55%..92% 活动带中等明度（0.34~0.52），焦点灯处 0.92
        H, W = 941, 1672
        yy = np.linspace(0.0, 1.0, H)[:, None]
        xx = np.linspace(0.0, 1.0, W)[None, :]
        # 上暗下明的基础明度梯度
        base_val = np.where(yy < 0.42, 0.10 + 0.08 * (yy / 0.42), 0.18 + 0.24 * np.clip((yy - 0.42) / 0.44, 0.0, 1.0))
        base_val = np.where(yy > 0.91, 0.14, base_val)
        for fx, fy, rx, ry in focus_map[code]:
            d2 = ((xx - fx) / rx) ** 2 + ((yy - fy) / ry) ** 2
            base_val = np.maximum(base_val, 0.18 + 0.74 * np.exp(-d2 * 1.4))
        # 绿幕透明区域标成纯黑方便模型一眼读懂暗区与亮区
        v_img = np.where(arr[..., 3] > 0.3, np.clip(base_val, 0.0, 1.0), 0.0)
        Image.fromarray((v_img * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(radius=4)).save(
            IN_DIR / f"{code}_value_plan.png"
        )


BASE_REPAINT_PROMPT = """附图1是我们 2D 横版动作游戏站立层原画（纯绿色 #00FF00 为透明天空与透明拱洞），附图2是本张图的【灰度明暗主次规划图】（越暗的地方必须越沉入雨夜暗雾、少细节低反差；越亮的地方是视觉焦点暖光区）。
请严格按以下规则重画附图1（输出 1672×941，纯绿 #00FF00 区域保持一模一样）：
1. 【结构 100% 锁死】：所有能走/能站的几何结构绝对不能挪动——街面高度、二层步廊台面高度与起止、楼梯台阶、阳台位置、门洞与拱洞的外轮廓、屋脊大轮廓必须与附图1完全重合（对齐误差 < 5px）。
2. 【核心：彻底拉开明暗主次与细节密度（绝不处处画满！）】：
   - **上半部约 40%（屋顶、尖塔、高楼二三层墙面）**：严格对照附图2暗区，大幅压低明度与对比度，柔和地沉入深夜雨雾中！不要把每一块瓦片、每一道砖缝都刻得清晰刺眼，熄灭绝大多数高窗，只保留模糊大剪影与极微弱的冷灰屋脊反光。
   - **人走的活动带（底层街面到二层步廊之间）**：把最精致的石雕、铁艺、门框细节和暖白偏淡金灯光集中在附图2标出的 **1～2 个焦点区域**！焦点之外的底层石墙保持沉稳偏暗，让视觉呼吸感拉满。
3. 【色调与质感】：中性微暖炭灰石材 + 冷灰雨夜空气（绝对不要整体蓝色滤镜！），暖白偏淡金灯火，湿石板只留极薄的湿润反光（绝非水洼）。
"""

EXTRA_DESC = {
    "B1": "【本段身份：1-1A 荒弃马车石阶段】重点亮光只留在左侧阶梯转角壁灯与右侧杂货铺小橱窗/门灯两处；上方大宅二三楼窗户几乎全暗（只留极微弱的一点余光），整个屋顶与高墙沉入深夜雨雾，绝不喧宾夺主。",
    "B2": "【本段身份：1-1A 断栏街灯与窄巷段（与 B1 明显区分材质与韵味）】左侧改成苍老爬满暗湿苔痕的厚重石拱库房，中央断栏豁口处的铸铁街灯与右侧深邃拱门壁灯是唯二焦点暖光；上方两栋尖顶老楼压入浓重暗雾、熄灭大部分高窗，彻底消除像海报一样处处堆细节的问题。",
    "B3": "【本段身份：1-1A 吊灯低拱与城门关口段】视觉焦点集中在低拱下摇晃的孤灯与右侧宏伟城门柱上的壁灯；城门洞深处暗沉幽深，上方钟亭与两栋屋顶全部压暗收进冷灰夜雾中，低对比、少碎线，突出底层战斗区的清晰层次。",
    "C1": "【本段身份：J1 街口高低分流岔路（必须彻底去掉旧图偏蓝偏亮的色调，与 B1~B3 100% 同一套中性微暖暗夜石材画风！）】焦点暖光只留在左侧石阶下方的钟铃门灯与中段悬灯两处，右侧大拱洞保持内部纯绿 #00FF00 镂空，上半部屋顶、烟囱与高窗全部大幅压暗融入雨夜雾气。",
}

STREET_THICK_PROMPT = """请绘制一张 2048×512 横版 4:1 **左右无缝平铺** 的 2D 游戏【有厚度的哥特石街沿横条】（正侧微俯视，接在人物脚下往下填满屏幕底部约 1/5，彻底消灭死黑带！）。
构图精确分层：
- 顶部 0%～32%：微俯视的湿润哥特青石板步行街面（大块厚实石板与湿润石缝，带极薄的冷灰与极淡的暖石质感，不要画死明显的局部亮斑、不要水洼倒影）。
- 中部 32%～44%：厚重突出的雕花石砌路缘沿口（被顶部微光擦出一道清晰的石材棱边，体现出街道的厚重实体厚度！）。
- 下部 44%～100%：街沿下方的哥特石砌挡墙立面、粗石块砌缝、暗影中的小排水石拱券与风化雨渍，越往下越自然渐暗至深炭灰（但绝不是纯黑死洞，始终保留隐约可读的厚重石块肌理！）。
色调为中性微暖炭灰石材，严禁蓝色滤镜，左右两端完全无缝衔接。""" + RED


def run_job(code: str) -> dict:
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_rec_{code}"
    cwd.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [
        exe, "exec", "-C", str(cwd), "-m", "gpt-6.1-terra",
        "-c", 'model_reasoning_effort="medium"',
        "-c", "mcp_servers.taptap-maker.enabled=false",
        "-s", "read-only", "--skip-git-repo-check", "--json",
    ]
    if code == "street_thick":
        if D2_REF.exists():
            cmd += ["-i", str(D2_REF.resolve())]
        prompt = STREET_THICK_PROMPT
    else:
        cmd += ["-i", str((IN_DIR / f"{code}_green.png").resolve())]
        cmd += ["-i", str((IN_DIR / f"{code}_value_plan.png").resolve())]
        prompt = BASE_REPAINT_PROMPT + "\n" + EXTRA_DESC[code] + "\n" + RED
    cmd.append("-")

    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    p = subprocess.run(
        cmd, cwd=str(cwd), input=prompt.encode("utf-8"),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=1500,
    )
    out = p.stdout.decode("utf-8", "replace")
    tid, usage = "", {}
    for line in out.splitlines():
        if line.startswith("{"):
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if ev.get("type") == "thread.started":
                tid = ev.get("thread_id", "")
            elif ev.get("type") == "turn.completed":
                usage = ev.get("usage", {})
    c = sorted((GEN / tid).glob("*.png"), key=lambda q: q.stat().st_mtime) if tid and (GEN / tid).exists() else []
    res = {"code": code, "thread": tid, "secs": round(time.time() - t0, 1), "usage": usage}
    if c:
        shutil.copy2(c[-1], OUT_DIR / f"{code}.png")
        res["status"] = "ok"
    else:
        res["status"] = "missing"
        res["tail"] = (out[-350:] + "\n" + p.stderr.decode("utf-8", "replace")[-350:]).strip()
    return res


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    prep_inputs()
    codes = sys.argv[1:] or ["B1", "B2", "B3", "C1", "street_thick"]
    with ThreadPoolExecutor(max_workers=min(5, len(codes))) as ex:
        results = list(ex.map(run_job, codes))
    hist = OUT_DIR / "runs.json"
    old = json.loads(hist.read_text(encoding="utf-8")) if hist.exists() else []
    hist.write_text(json.dumps(old + results, ensure_ascii=False, indent=2), encoding="utf-8")
    for r in results:
        print(f"{r['code']}: {r['status']} ({r['secs']}s) tokens={r.get('usage', {}).get('input_tokens')} {r.get('tail', '')}")


if __name__ == "__main__":
    main()
