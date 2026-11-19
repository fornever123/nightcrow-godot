#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 侧视方向图（11-19）。
用户看完 3D 街体手绘分层版：“不行越来越丑了”“为什么效果越来越差啊”，同意“先出方向图”。
复盘：U2 目标图是顺着街道看的透视画，游戏是横版侧视——这次按**游戏实际镜头**出整屏画面，
附图 1 = 现在游戏同一帧（定构图：两层能走的高度、角色大小），附图 2 = U2 目标图（定画风、精细度、光感）。

用法：python tools/art/bg_side_dir_codex.py [D1 D2 D3]
产物：docs/_当前分支草稿/背景线/侧视方向_20261119/<代号>.png
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

ROOT = Path(r"E:\00game\nightcrow-godot")
OUT = ROOT / "docs" / "_当前分支草稿" / "背景线" / "侧视方向_20261119"
REF_GAME = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "实机_Y2_去地影" / "x03300.png"
REF_U2 = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "升级方向" / "U2_HD2D实景.png"
GEN = Path.home() / ".codex" / "generated_images"

COMMON = """附图1是我们 2D 横版动作游戏现在的一帧实机画面（镜头永远正对街道侧面，角色只左右走）。附图2是我们想要的画面品质（精致手绘厚涂、HD-2D 那种细节和光感）。
请画一张**新的整屏游戏画面**（横版 16:9，1920×1080）：
- **镜头必须和附图1一样是横版侧视**：正对街对面的楼，不要顺着街道往远处看的透视，不要斜角。
- **构图沿用附图1**：画面下方约 1/4 是角色走的街面（湿石板，只有很薄的湿润反光，**不要水洼、不要积水、不要镜面倒影**）；画面中部偏上有一条能站人的二层石步廊 / 阳台，高度和附图1里的二层平台差不多。
- 把附图1里那个黑紫色头发、拿长刀的小女孩角色，按同样大小、同样位置画在街面上（她只占画面高度约 1/6），用来看比例。
- 画质、材质、光感按附图2：方整石墙、尖拱窗里暖白偏淡金的灯光、铸铁街灯、湿石板，冷灰夜色 + 少量暖灯。
- 红线：整张图**不得出现紫色 / 品红**（只有角色刀上原本的紫光可以保留）；不要海、水、码头、船、绳子、木桶、木箱；不要任何行人和其他角色；不要正面钟面；不要血；不要白瓷 / 石化质感；不要文字、UI、水印。
"""

JOBS = {
    "D1": """【方向 D1 · 楼缝透光】街对面的楼**不连成一堵墙**：三四栋高矮不一的哥特小楼之间留出两道宽窄不同的缝，缝里透出远处雾中的城市层层剪影，和远方一座巨大哥特母钟楼的侧影（只见塔身和尖顶，**不画钟面**），塔顶背后天顶有一束冷白的光从云缝落下来照亮雨丝。近处楼暗、远处亮，形成明显的前暗后亮纵深。画面里只有一两处重点暖光：二层步廊下一个亮着的小店橱窗、一盏街灯，其余压暗。""",
    "D2": """【方向 D2 · 前景压框三层景深】画面分清楚三层：①最前景（镜头跟前）一段很暗、明显虚焦的石栏杆和一根石柱的剪影，压在画面最下沿和左侧，像隔着栏杆看戏；②中景是角色所在的街面和身后的二层石拱廊（拱洞里有暖光的门和窗），清晰锐利；③远景是雾里虚掉的成片城市屋顶和远方钟楼剪影（不画钟面），冷灰、低反差。像移轴摄影一样，只有中景清楚，前后都虚。""",
    "D3": """【方向 D3 · 高楼压顶窄天】镜头还是侧视，但街对面的楼**很高**，一直顶出画面上沿，只在两栋楼之间留一条窄窄的竖向天缝，天缝里是冷白的天光和斜落的雨。楼面竖向线条强（扶壁、长尖拱窗、竖向雨痕），压迫感强、有教堂般的高度。二层步廊横穿画面，下面是暗的拱廊。光源：天缝落下的一道冷白光斜照在街面上（照亮一块石板和角色），加上两三盏暖色壁灯，其余是深冷灰。""",
}


def run(code: str) -> dict:
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_side_{code}"
    cwd.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(cwd), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str(REF_GAME.resolve()), "-i", str(REF_U2.resolve()), "-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    p = subprocess.run(cmd, cwd=str(cwd), input=(COMMON + JOBS[code]).encode("utf-8"), stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, env=env, timeout=1500)
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
    res = {"code": code, "thread": tid, "secs": round(time.time() - t0), "usage": usage}
    if c:
        shutil.copy2(c[-1], OUT / f"{code}.png")
        res["status"] = "ok"
    else:
        res["status"] = "missing"
        res["tail"] = out[-400:] + p.stderr.decode("utf-8", "replace")[-400:]
    return res


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    codes = sys.argv[1:] or list(JOBS)
    with ThreadPoolExecutor(max_workers=len(codes)) as ex:
        results = list(ex.map(run, codes))
    hist = OUT / "runs.json"
    old = json.loads(hist.read_text(encoding="utf-8")) if hist.exists() else []
    hist.write_text(json.dumps(old + results, ensure_ascii=False, indent=1), encoding="utf-8")
    for r in results:
        print(r["code"], r["status"], r["secs"], r.get("usage", {}).get("input_tokens"), r.get("tail", ""))


if __name__ == "__main__":
    main()
