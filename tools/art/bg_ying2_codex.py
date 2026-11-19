#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 影街「影 2 影流向钟楼」落地（11-18）：远景素材两件——母钟楼侧影（绿底）、白光云缝天空（满幅）。

用法：python tools/art/bg_ying2_codex.py [tower sky]
参考：docs/_当前分支草稿/背景线/立体感_20261118/方向图/S2m_影流向钟楼_中间亮度.jpg（用户 11-18 选定）
产物：docs/_当前分支草稿/背景线/立体感_20261118/影2素材/<kind>.png 与 runs.json
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
OUT = BASE / "影2素材"
REF = BASE / "方向图" / "S2m_影流向钟楼_中间亮度.jpg"
GEN = Path.home() / ".codex" / "generated_images"

WORLD = """背景设定：这是 2D 横版动作游戏的「影街」——天顶裂口渗下的白光会驱逐时间（被照住的东西鲜活地停在那一秒），赶出来的流动时间在暗处积成墨黑狂影，顺着街流向远处的「司辰母钟楼」（全城时间的机械总枢，一座独立的百米青铜机械巨塔）。附图1是用户选定的目标画面，只用来定画风、色调和母钟楼的样子（画面右上那座带大齿轮的高塔）。"""

JOBS = {
    "tower": WORLD + """
请生成一张 1024×1536（竖版）的**远景素材：司辰母钟楼侧影**。
【背景】整张背景 100% 纯平涂亮绿色 #00FF00（抠图用），绿色里不要渐变、雾、光晕、阴影；塔的边缘不要绿色溢色。
【塔】一座极高极细的青铜机械巨塔，从画面底边一直伸到顶部，塔身侧面嵌着两三个巨大的半露齿轮（只看得到齿轮的侧影和齿），顶部是几层哥特尖顶和细尖针，塔身有拱窗、桁架和连桥断口。**只画侧面，绝对不要任何正面钟盘、表盘、指针。**
【画法】很远、逆光：整座塔是深炭灰的剪影，只有朝右上的轮廓边缘留一道冷白亮边（背后的白光照过来），内部只有很少的形体明暗，塔的下半截渐渐融进淡灰雾（底部 1/4 越往下越淡、越接近浅灰，便于和远景雾衔接）；可以有两三点很小的暖窗灯。不要蓝色调，是中性的炭灰。
【红线】不得出现紫色、品红、粉色；不要水、船、人物、文字、水印、边框。""",
    "sky": WORLD + """
请生成一张 1672×941（横版）的**满幅天空背景**（游戏最底层，不需要抠图，不要任何建筑、地面、树）。
【内容】雨夜的厚云层：画面大部分是深炭灰、中灰的翻卷云，**右上方约 1/3 宽的地方云层裂开，后面透出一团冷白的天顶白光**（光是柔和的发亮云团和几缕淡淡的散射光，不要锐利的光柱、不要太阳或月亮的圆盘）；越靠近白光的云越亮、越淡，越往左越暗；画面下部 1/3 是渐亮的浅灰雾带（远方城市所在的高度），好让远景城市剪影融进去。可以有很细的斜雨丝。
【色调】中性的炭灰到冷白，只带一点点冷，**不要饱和的蓝色**，不要暖色。
【红线】不得出现紫色、品红、粉色；不要水面、建筑、人物、文字、水印、边框。""",
    "ink": WORLD + """
请生成一张 1672×941（横版）的**狂影墨烟带素材表**（游戏里会让它们贴着墙、在天上缓缓流动）。
【背景】整张背景 100% 纯平涂亮绿色 #00FF00（抠图用），绿色里不要渐变、雾、光晕、阴影；墨烟边缘不要绿色溢色。
【内容】上下排开 4 条横向的长墨烟带，每条几乎横贯整个画面宽度、互相之间留足绿色空隙不重叠：
1. 最粗的一条：浓黑的墨烟，像一股粘稠的黑烟河，边缘翻卷成一团团、一缕缕，中段最粗，两头逐渐变细、散开成丝；
2. 中等粗细的一条，起伏更大，像波动的黑绸；
3. 细长的一条，主要是几股缠绕的细烟丝；
4. 一条松散的、半透明感更强的烟带（但颜色依旧是墨黑到深炭灰），边缘有很多破碎的小烟团。
【画法】和附图1里的墨黑狂影同一种手绘厚涂质感：主体接近纯黑的墨色，翻卷处有一点点深炭灰到中灰的高光，让它有体积；不要描边。不要紫色。
【红线】不得出现紫色、品红、粉色、蓝色；不要水、浪、海、人物、建筑、文字、水印、边框。""",
}


def run(kind: str) -> dict:
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_y2_{kind}"
    cwd.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(cwd), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str(REF.resolve()), "-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    p = subprocess.run(cmd, cwd=str(cwd), input=JOBS[kind].encode("utf-8"), stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, env=env, timeout=1200)
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
    res = {"kind": kind, "thread": tid, "secs": round(time.time() - t0), "usage": usage}
    if c:
        shutil.copy2(c[-1], OUT / f"{kind}.png")
        res["status"] = "ok"
    else:
        res["status"] = "missing"
        res["tail"] = out[-400:]
    return res


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    kinds = sys.argv[1:] or list(JOBS)
    with ThreadPoolExecutor(max_workers=len(kinds)) as ex:
        results = list(ex.map(run, kinds))
    hist = OUT / "runs.json"
    old = json.loads(hist.read_text(encoding="utf-8")) if hist.exists() else []
    hist.write_text(json.dumps(old + results, ensure_ascii=False, indent=1), encoding="utf-8")
    for r in results:
        print(r["kind"], r["status"], r["secs"], r.get("usage", {}).get("input_tokens"))


if __name__ == "__main__":
    main()
