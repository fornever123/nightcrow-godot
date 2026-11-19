#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 3D 街体目标图（11-19）：用户看 RAIN_3D 原型说“你这完全不行”。原型只加了地板、墙还是一整张卡片。
这一轮先出 3 张“能走的地方全 3D、近景按真实距离”的目标效果图让用户挑，再动手。

旧说明：影街画面升级（11-18 第三轮）：用户看完影 2 色调 3 实机说“我感觉本质问题还在”。

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
OUT = ROOT / "docs" / "_当前分支草稿" / "背景线" / "3D街体_20261119" / "目标方向"
REF1 = ROOT / "docs" / "_当前分支草稿" / "背景线" / "3D街体_20261119" / "实机_v4" / "x03300.png"
REF2 = BASE / "升级方向" / "U2_HD2D实景.png"
GEN = Path.home() / ".codex" / "generated_images"

COMMON = """附图1是我们 2D 横版动作游戏现在的实机原型：只给街面加了一块 3D 石子地板，楼还是一整张平的手绘原画卡片——用户说“完全不行”。附图2是之前一张 HD-2D 方向的参考。
用户要的是：**能走的地方（街面、步廊、台阶、阳台）全部是真 3D**，近处的建筑构件（柱子、拱廊、栏杆、台阶、路灯、门洞）按**真实距离**摆在 3D 空间里，有真实的厚度、透视、遮挡、受光和投影；不是一张画后面加地板。
这条街是「影街」：哥特老城雨夜、空城无人；白光驱逐时间——被天顶白光照住的东西鲜活地停在那一秒，被赶出的时间沉进暗处化成墨黑狂影，顺着街往远处的司辰母钟楼（青铜机械巨塔，只见塔身齿轮和尖顶，不画正面钟盘）流。
请画一张**整屏游戏实机效果图**（1672×941，横版 2D 动作游戏：主角在画面中下部、朝右，可左右行走、可跳上上层步廊），保留附图1的街道要素（上下两层街：下层街面带拱门和店面、上层带石栏杆的步廊、宅邸、壁灯、空马车），按下面的方向做：
"""

RED = """
【红线】画面任何地方不得出现紫色、品红、粉色（只有主角剑上一点紫光可以保留）；狂影必须纯墨黑 / 深炭色；不得出现海、水面、积水、水洼、船、绳索、木桶、木箱、正面钟表盘、血、白瓷或石化效果、路人；湿石板只有很薄的反光。不要任何文字、UI、血条、水印、边框。
色调：不要整体蓝色滤镜；石头是中性偏暖的灰，夜空微冷，暖白偏淡金的灯火。主角是一个黑紫短发、持细长剑的少女剑士，约画面高度 1/6。
"""

DIRS = {
    "T1_全3D建模横版": """【方向 T1：全 3D 建模横版】（参照《血污：夜之仪式》Bloodstained: Ritual of the Night、《波斯王子：失落的王冠》的 2.5D 场景）
- 整条街是完整的 3D 建模场景，镜头正侧面、透视相机：拱廊的柱子是圆柱、有体积，拱门往里凹进去看得见内壁，步廊台面有厚度、栏杆一根根立体，阳台往外挑出、底面看得见。
- 主角站的街面和步廊台面都是 3D 实体，脚下有真实投影；后面的宅邸也是建模，离得越远越进雾。
- 灯光是实时 3D 光：壁灯照亮周围的柱子侧面和地面，柱子在地上投出长影，雨丝在灯光里发亮。""",
    "T2_HD2D实景微缩": """【方向 T2：HD-2D 实景微缩】（参照《歧路旅人 II》Octopath Traveler II、《三角战略》的 HD-2D）
- 镜头从侧面略高处（约 15° 俯视）看，街面一路往纵深退去，看得见街面全宽、步廊台面顶面和屋顶。
- 建筑是贴了手绘质感贴图的 3D 微缩模型（厚涂画风的石头和木头，不是照片材质），前景的栏杆 / 柱子 / 路灯离镜头近、明显虚化，远处钟楼也虚化，只有主角那条街清晰（移轴景深）。
- 主角是精致的 2D 立绘角色站在 3D 场景里，被周围的灯照亮，脚下有接触阴影；强烈的体积光、光晕和雨幕。""",
    "T3_近景真3D远景手绘": """【方向 T3：近景真 3D · 远景手绘】（参照《Trine 4》《奥日与精灵意志》的近实远绘做法）
- 主角能走、能碰到的那一层（街面、拱廊柱、台阶、步廊台面、栏杆、壁灯、马车）全是有厚度的 3D 实体，受实时灯光、互相投影，柱子和栏杆在湿石板上投出长影；镜头正侧面略低。
- 往后一层层是手绘的楼：第二层宅邸离步廊约一条街远，第三层更远的屋顶群，第四层远城和母钟楼——每层之间有真实的空气距离（越远越淡、越亮、越被雾吃掉），走动时各层速度不同。
- 最前景偶尔有一根近黑的 3D 柱子或铁栏杆从镜头前掠过，虚焦。""",
}


def run(code: str) -> dict:
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_t3d_{code[:2]}"
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
