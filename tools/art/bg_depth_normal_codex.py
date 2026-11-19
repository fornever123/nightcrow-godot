#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 立体感试验（2026-11-18）：让 Codex 给一张站立层原图出「深度图」和「法线图」，供 Godot 里做真打光 / 分层视差。

用法：python tools/art/bg_depth_normal_codex.py SRC.png [depth normal]
产物：docs/_当前分支草稿/背景线/立体感_20261118/codex原图/<原图名>_<depth|normal>.png
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
OUT = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "codex原图"
CWD = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / "nightcrow_codex_depth"
GEN = Path.home() / ".codex" / "generated_images"

COMMON = """附图1是一张 2D 横版动作游戏的背景站立层原画（哥特老城的街面、拱、步廊、楼、阳台、灯），纯亮绿色 #00FF00 是抠图底（天空、洞口）。
请生成与附图1**完全同尺寸、同构图、像素级逐一对齐**的一张技术贴图（不是重新画一张画）：每一根柱子、每一个窗、每一块阳台、每一级台阶的轮廓都必须和附图1在同一位置，不要增删、不要移动、不要改形状。
附图1中所有 #00FF00 的区域，在输出里也保持 100% 纯 #00FF00 不变。
不要任何文字、水印、边框、标注、色标。
"""

JOBS = {
    "depth": COMMON + """【输出：深度图（灰度）】把附图1转成一张灰度深度图：离镜头越近越白、越远越黑。
- 街面最前沿、最外凸的石墩、阳台外沿、灯、栏杆柱、马车：最亮（接近白）。
- 墙面主体：中灰；凹进去的门洞、窗洞、拱洞内部、阳台下的阴影凹处：明显更暗。
- 步廊后面往后退的楼：比前面的墙暗一档；再往后退、只露出屋顶的楼：再暗一档。
- 每一个独立的建筑块内部深度平滑连续，块与块之间在轮廓处有清楚的深度断层。
- 只有灰度，没有任何颜色、纹理、光影、雨、砖缝细节。
""",
    "normal": COMMON + """【输出：切线空间法线图（OpenGL 约定）】把附图1转成一张游戏用的法线贴图，正视观察：
- 朝正前方的平面 = 均匀的 RGB(128,128,255) 淡紫蓝。
- 朝右的面偏红、朝左的面偏青；朝上的面偏绿（例如台面、檐口顶面、阳台顶面、步廊顶面）、朝下的面偏暗绿紫（例如檐口底面、阳台底托、拱券内侧顶部）。
- 圆柱、栏杆柱、拱券、石块的倒角都要有平滑的法线渐变；石块砌缝是细细的凹槽法线；窗洞、门洞的侧壁有清楚的朝向色。
- 只表达形状起伏，不要任何原画的颜色、亮暗、灯光、雨、阴影。
""",
}


def run(src: Path, kind: str) -> dict:
    CWD.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(CWD), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str(src), "-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=str(CWD), input=(JOBS[kind] + "\n").encode("utf-8"), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=env, timeout=900)
    except subprocess.TimeoutExpired:
        return {"kind": kind, "status": "timeout"}
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
    res = {"src": src.name, "kind": kind, "thread": tid, "secs": round(time.time() - t0), "usage": usage}
    c = sorted((GEN / tid).glob("*.png"), key=lambda q: q.stat().st_mtime) if tid and (GEN / tid).exists() else []
    if not c:
        res["status"] = "missing"
        res["tail"] = (out + p.stderr.decode("utf-8", "replace"))[-400:]
        return res
    dst = OUT / f"{src.stem}_{kind}.png"
    if dst.exists():
        dst.rename(OUT / f"{src.stem}_{kind}_{int(dst.stat().st_mtime)}.png")
    shutil.copy2(c[-1], dst)
    res["status"] = "ok"
    res["file"] = str(dst)
    return res


def main() -> None:
    src = Path(sys.argv[1]).resolve()
    kinds = sys.argv[2:] or list(JOBS)
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=len(kinds)) as ex:
        results = list(ex.map(lambda k: run(src, k), kinds))
    hist = OUT / "runs.json"
    old = json.loads(hist.read_text(encoding="utf-8")) if hist.exists() else []
    hist.write_text(json.dumps(old + results, ensure_ascii=False, indent=1), encoding="utf-8")
    for r in results:
        print(json.dumps(r, ensure_ascii=False))


if __name__ == "__main__":
    main()
