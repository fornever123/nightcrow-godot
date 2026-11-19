#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · D2「前景压框三层景深」落地（11-19 用户选 D2：“D2 三层景深”“继续”）。
站立层 B1～B3：按 D2 的画质重绘，所有能走 / 能站的结构位置不动（碰撞是按原图定的）；
远景：雾里的城市屋顶 + 母钟楼剪影横向长条；前景：一套很暗的近景栏杆 / 石柱构件（进游戏再虚化）。

用法：python tools/art/bg_d2_codex.py [B1 B2 B3 far fg]
产物：docs/_当前分支草稿/背景线/D2三层_20261119/原图/<代号>.png
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
BASE = ROOT / "docs" / "_当前分支草稿" / "背景线" / "D2三层_20261119"
OUT = BASE / "原图"
D2 = ROOT / "docs" / "_当前分支草稿" / "背景线" / "侧视方向_20261119" / "D2.png"
GEN = Path.home() / ".codex" / "generated_images"

RED = """红线：不得出现紫色 / 品红；不要海、水、水洼、积水、码头、船、绳子、木桶、木箱；不要任何人物、行人、动物；不要正面钟面；不要血；不要白瓷 / 石化质感；不要文字、水印、UI。"""

REPAINT = """附图1是我们 2D 横版游戏里一段街景的原画（站立层：角色在最下面的街面上走，也能跳上中间那条二层石步廊和楼上的阳台）。纯绿色 #00FF00 的部分是透明的天空。附图2是我们选定的新画风目标（D2）。
请**重画附图1**：
- **所有结构的位置、大小、轮廓必须和附图1一模一样**（能叠上去对齐）：街面那条线的高度、二层步廊台面的高度和左右起止、步廊上的栏杆、楼上阳台的高度和宽度、楼梯、拱洞、门、橱窗、街灯、楼的外轮廓和屋顶尖——一样都不能挪、不能加宽变窄、不能增删。
- 只把画质提升到附图2的水平：石材更精细、有体积感，尖拱窗里暖白偏淡金的灯光透出来、在石墙和窗台上留下柔和的暖光晕，铸铁壁灯和街灯有真实的光，街面是湿润的石板（只一层很薄的反光，不要水洼）。冷灰夜色为主，暖光只在灯和窗附近，整体比附图2再暗一点。
- 原来的天空部分仍然是**纯绿色 #00FF00**（楼的轮廓外全部纯绿，方便抠图），尺寸和附图1一样 1672×941。
""" + RED

JOBS = {
    "B1": (["B1"], REPAINT),
    "B2": (["B2"], REPAINT),
    "B3": (["B3"], REPAINT),
    "far": ([], """附图1是我们选定的游戏画面风格（D2，横版侧视）。请只画它的**远景层**：一条横向很长的远景，雾里层层叠叠的哥特老城屋顶、尖塔、烟囱的剪影，越远越淡越灰；靠右三分之一处有一座巨大的哥特母钟楼侧影（高塔 + 尖顶，**不画钟面**），塔背后天顶有一片冷白的天光从云缝透出来、把塔的轮廓照亮。只有少量远处窗灯是微弱的暖点。天空是冷灰的夜云（有一点云层层次，不要星空），整张低反差、偏灰、有空气感、像隔着雨雾。正侧视、没有透视。左右两端能无缝接起来。横版 3:1，2400×800。""" + RED),
    "street": ([], """附图1是我们选定的游戏画面风格（D2，横版侧视）。请只画它里面角色脚下那条**街面**的横向长条：从侧面稍微俯看的一条哥特老城湿石板街面（大块方整石板 + 石缝），上沿是贴着街边楼墙脚的那条线，往下（往镜头方向）延伸。石面被雨打湿，有一层很薄的湿润反光：街灯和窗灯在石板上映出几块柔和的暖金色光斑和竖向拉长的淡光，其余是冷灰。**不要水洼、不要积水、不要镜面倒影**，不要任何物件、人物。越往下（越靠镜头）越暗。左右两端能无缝接起来。横版 4:1，2048×512。""" + RED),
    # 11-19 用户：“你这个明显就一个很窄的长廊，房子后面明显什么也没有。而且亮度太高，不像晚上”
    "behind_a": ([], """附图1是我们的游戏画面风格（横版侧视、哥特老城雨夜）。请画**街边那排房子后面的城市**这一层：横向长条，一大片密密层层的哥特老城屋顶天际线——高低错落的坡屋顶、山墙、老虎窗、烟囱、几座尖塔和小钟塔、屋脊上的铁尖饰，楼和楼前后叠了两三排，前排略大略清楚、后排更小更淡。**这是深夜**：整体是很暗的炭灰 / 深冷灰剪影，只有屋顶边缘被一点冷月光擦亮；零零散散有不少窗户亮着暖白偏淡金的灯（大约十分之一的窗亮，亮窗是这一层最显眼的东西）。正侧视、没有透视。**天空部分全部是纯绿色 #00FF00**（屋顶轮廓以上都是纯绿，方便抠图），楼一直画到画面最底边。左右两端能无缝接起来。横版 3:1，2400×800。""" + RED),
    "behind_b": ([], """附图1是我们的游戏画面风格（横版侧视、哥特老城雨夜）。请画**更远一层的城市**：横向长条，很远很远的哥特老城天际线剪影，屋顶、尖塔、教堂塔楼、穹顶一层层叠到地平线，被夜雨的雾吞掉一半——越往下越被雾盖住。**深夜**：剪影是暗冷灰，比近处亮一点点（空气透视），极少数窗灯是很小的暖点。正侧视、没有透视。**天空部分全部是纯绿色 #00FF00**（天际线以上纯绿），城一直画到画面最底边。左右两端能无缝接起来。横版 3:1，2400×800。""" + RED),
    "fg": ([], """附图1是我们选定的游戏画面风格（D2）。请画它最前景那一层的**构件**（游戏里会放在镜头跟前、再做虚化）：一张图里横排 4 个彼此分开、互不重叠的构件：①一段很矮的哥特石栏杆（宝瓶栏杆柱 + 扶手，带一根方墩和圆球顶），②一根粗的哥特石柱（从画面上沿到下沿完整入画、带柱础），③一根带铸铁花饰的老式铁栏杆短段，④一段断开的矮石墙墩。全部是**正面平视**，颜色很暗（深炭灰，背光，只有边缘被一点冷月光擦亮），**背景纯绿色 #00FF00**，构件之间留大块绿色。横版 1536×1024。""" + RED),
}


def run(code: str) -> dict:
    refs, prompt = JOBS[code]
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_d2_{code}"
    cwd.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    imgs = [str((BASE / "输入" / f"{r}_green.png").resolve()) for r in refs] + [str(D2.resolve())]
    cmd = [exe, "exec", "-C", str(cwd), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check", "--json"]
    for i in imgs:
        cmd += ["-i", i]
    cmd += ["-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
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
