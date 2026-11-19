#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 立体感试验（11-18）：前景遮挡件（压在角色前面、越近越暗）一张图出一组，绿底。

用法：python tools/art/bg_foreground_codex.py
产物：docs/_当前分支草稿/背景线/立体感_20261118/codex原图/FG1.png
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(r"E:\00game\nightcrow-godot")
OUT = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "codex原图"
REF = ROOT / "docs" / "_当前分支草稿" / "背景线" / "第一章升级_20261118" / "1-1A上下两层街" / "codex原图" / "B1.png"
CWD = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / "nightcrow_codex_fg"
GEN = Path.home() / ".codex" / "generated_images"

PROMPT = """附图1是一张 2D 横版动作游戏的站立层原画（哥特老城雨夜街道），只用来定画风、石材和铸铁的样子。
请生成一张 1672×941 的**前景遮挡件素材表**：这些东西在游戏里放在镜头最前面、压在角色前面，离镜头很近，所以比附图1里的东西大很多。
【背景】整张图背景是 100% 纯平涂亮绿色 #00FF00（抠图用），绿色里不要任何渐变、雾、光晕、阴影、噪点；物体边缘不要绿色溢色。
【件】横向排开 5 件，互相之间留足绿色空隙、不重叠、不出画：
1. 一根粗大的方形哥特石柱的一段，从画面顶边一直到底边（顶边、底边直接截断），柱身有竖向凹槽和一道石箍，宽约 180 像素。
2. 一根细高的铸铁路灯杆的一段，从顶边到底边截断，杆上一个卷草铁托，挂一盏**熄灭**的玻璃灯笼。
3. 一段从顶边垂下来的断裂石拱券（只有拱券的一角，下沿是碎裂的石茬），挂着两根垂下来的短铁链。
4. 一段铸铁栏杆（5～6 根栏杆 + 顶部扶手 + 尖头），从底边长出来，高约 260 像素。
5. 一块从底边长出来的倒塌石块堆（几块方石 + 一截断栏柱），高约 220 像素。
【画法】和附图1同样的手绘厚涂，但这些是**近处逆光的暗剪影**：整体非常暗，接近黑色的冷灰蓝，只在轮廓的一侧留一道很细的冷白湿亮边（雨水反光），内部只有极少的形体明暗；不要暖光、不要亮的细节。
【红线】不得出现任何紫色、品红、粉色；不得出现水面、积水、船、绳索、木桶、木箱、正面钟表盘、人物、动物、植物、文字、水印、边框。
"""


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    CWD.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(CWD), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str(REF.resolve()), "-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    p = subprocess.run(cmd, cwd=str(CWD), input=PROMPT.encode("utf-8"), stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, env=env, timeout=900)
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
    res = {"kind": "FG1", "thread": tid, "secs": round(time.time() - t0), "usage": usage}
    if c:
        dst = OUT / "FG1.png"
        if dst.exists():
            dst.rename(OUT / f"FG1_{int(dst.stat().st_mtime)}.png")
        shutil.copy2(c[-1], dst)
        res["status"] = "ok"
    else:
        res["status"] = "missing"
        res["tail"] = out[-400:]
    print(json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main()
