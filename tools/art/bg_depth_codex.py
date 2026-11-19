#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 影街画面升级（11-18 第三轮）：用户看完影 2 色调 3 实机说“我感觉本质问题还在”。

前两轮方向图都沿用了实机的“舞台搁板”构图（镜头正侧平视、墙面贴着角色、街面只剩一条线、下方 17% 纯黑），
所以怎么调色都还是纸片。这一轮 3 个方向都**改画面结构**，各自完整一屏，彼此差异要大。

用法：python tools/art/bg_depth_codex.py [代号…]
产物：docs/_当前分支草稿/背景线/立体感_20261118/升级方向/<代号>.png 与 runs.json
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
BASE = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118"
OUT = BASE / "升级方向"
REF1 = BASE / "实机_Y2_去地影" / "x03300.png"
REF2 = BASE / "方向图" / "S2m_影流向钟楼_中间亮度.jpg"
GEN = Path.home() / ".codex" / "generated_images"

COMMON = """附图1是我们 2D 横版动作游戏现在的实机一帧，附图2是已经选定的世界观目标图「影流向钟楼」。
这条街叫「影街」：天顶白光驱逐时间，被白光照住的东西鲜活地停在那一秒；被赶出来的流动时间沉进暗处，变成蠕动的墨黑狂影，顺着街往远处的司辰母钟楼（青铜机械巨塔，只见塔身齿轮和尖顶、背后被白光照亮，绝不画正面钟盘）汇流。空城，没有路人。

现在画面的根本问题（不是颜色问题）：
1. 镜头正侧平视，宅邸立面像一堵平墙贴在角色身后，占满七成画面，近处远处一样清楚 → 像舞台布景板。
2. 街面只剩一条细线，角色脚下没有可见的地面，画面下方近 1/5 是纯黑空洞 → 像东西摆在搁板上。
3. 角色太小（不到画面高度 1/9），路灯的光照不到角色，角色像贴纸。
4. 没有任何东西在角色前面。

请画一张**整屏游戏实机效果图**（1672×941，横版 2D 动作游戏画面，主角仍在画面中下部、朝右，可横向行走），保留附图里的哥特老城雨夜、宅邸、拱门、路灯、远处母钟楼与墨黑狂影这些元素，但按下面的方向**彻底改画面结构**：
"""

RED = """
【红线】画面任何地方不得出现紫色、品红、粉色（只有主角剑上一点紫光可以保留）；狂影必须纯墨黑 / 深炭色；不得出现海、水面、积水、水洼、船、绳索、木桶、木箱、正面钟表盘、血、白瓷或石化效果、路人；湿石板路面最多只有很薄的反光。不要任何文字、UI、血条、水印、边框。
色调：不要整体蓝色滤镜；石头是中性偏暖的灰，夜空微冷，暖白偏淡金的灯火。精致手绘厚涂，和附图同一类哥特建筑。主角是一个黑紫短发、持细长剑的少女剑士。
"""

DIRS = {
    "U1_街有进深": """【方向 U1：街有进深】（参照 Ender Lilies、Blasphemous 2 的街景做法）
- 镜头略微抬高、稍微俯视，能看见一条**往纵深退去的湿石板街面**：街面占画面下部约 1/4～1/3，有清楚的透视、石板一块块往远处变小，边上有路缘石。主角走在离镜头较近的这一半街面上，脚下有被路灯照出的一团暖光和清楚的投影。
- 宅邸立面**退到街对面**，和主角之间隔着整条街，不再贴在角色身后；立面也有一点透视（看得见窗台、阳台的厚度和侧面）。
- 最前景：画面下边和左右边压几件近黑、轻微虚焦的剪影（铸铁栏杆、路灯杆、断掉的石柱），挡住一点点画面。
- 远处：街道尽头在白雾里变亮变淡，母钟楼在那里；墨黑狂影贴着街对面的墙脚和楼缝，往街道深处流。
- 主角比附图大，约画面高度的 1/6，被近处路灯从侧面勾出一道暖色轮廓光。""",
    "U2_HD2D实景": """【方向 U2：HD-2D 实景街】（参照 Octopath Traveler II、Triangle Strategy 的 HD-2D 画面）
- 整条街是**真实 3D 搭出来的微缩场景**：建筑是有厚度的立体模型，屋顶、侧墙、檐口都有真实透视；镜头从侧面略高处看，街道两侧的房子一前一后错落，前面一排矮墙 / 栏杆在最近处。
- 主角是精致的 2D 像素风 / 手绘立绘角色站在 3D 街道里（像 HD-2D 那样），脚下有真实的接触阴影，被周围点光源照亮。
- 强烈的景深：最近处和最远处都明显虚化（移轴感），只有主角所在那一条清晰。
- 真实的体积光：路灯和窗户有柔和的光晕、雨丝在灯光里发亮；远处母钟楼背后的白光穿过雾气形成大气透视。
- 墨黑狂影像有体积的黑烟，从建筑阴影里溢出，沿街往远处钟楼流。""",
    "U3_剪影大纵深": """【方向 U3：剪影压框 · 断崖大纵深】（参照 Hollow Knight、Blasphemous 的前景压框与纵深层次）
- 主角走在一条**高处的石砌步廊 / 断桥**上（步廊台面有厚度、看得见台面），身后不是墙，而是**敞开的城市深渊**：老城一层一层往下、往远处落去，至少 5 层建筑剪影，越远越淡、越亮、越被白雾吃掉，最深处是被白光照亮的母钟楼。
- 最前景：巨大的近黑剪影压在画面左右和下边（粗石柱、断拱、齿轮的一角、铸铁栏杆），占画面约 1/5，虚焦。
- 主角所在的站立层是中等明度、对比最强、细节最多的一层；暖白偏淡金的灯只有站立层和中景有。
- 墨黑狂影从下方深渊的城市里像一条条黑烟河升起，朝远处的钟楼汇流，近大远小，把纵深拉出来。
- 主角约画面高度的 1/6。""",
}


def run(code: str) -> dict:
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_up_{code[:2]}"
    cwd.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(cwd), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str(REF1.resolve()), "-i", str(REF2.resolve()), "-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    prompt = COMMON + DIRS[code] + RED
    p = subprocess.run(cmd, cwd=str(cwd), input=prompt.encode("utf-8"), stdout=subprocess.PIPE,
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
    codes = sys.argv[1:] or list(DIRS)
    with ThreadPoolExecutor(max_workers=len(codes)) as ex:
        results = list(ex.map(run, codes))
    hist = OUT / "runs.json"
    old = json.loads(hist.read_text(encoding="utf-8")) if hist.exists() else []
    hist.write_text(json.dumps(old + results, ensure_ascii=False, indent=1), encoding="utf-8")
    for r in results:
        print(r["code"], r["status"], r["secs"], r.get("usage", {}).get("input_tokens"), r.get("tail", ""))


if __name__ == "__main__":
    main()
