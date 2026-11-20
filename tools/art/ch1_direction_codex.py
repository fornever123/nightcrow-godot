#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 第一章影街升级：1-1A「灯影空轿街」三个方向效果图（Codex，2026-11-18）。

用法：python tools/art/ch1_direction_codex.py [方向代号 ...]   不写 = 全部
产物：docs/_当前分支草稿/背景线/第一章升级_20261118/方向效果图/<代号>.png 与 runs.json
附图：同目录 参考_现在的入口街实机.png（锁画风、比例、亮度）
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
OUT = ROOT / "docs" / "_当前分支草稿" / "背景线" / "第一章升级_20261118" / "方向效果图"
REF = OUT / "参考_现在的入口街实机.png"
CWD = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / "nightcrow_codex_ch1_dir"
GEN = Path.home() / ".codex" / "generated_images"

HEAD = """请直接调用一次图片生成工具，生成 1 张横版 16:9（1672×941）的图片。只调用一次图片生成工具，不要重试，不要写代码，不要运行终端命令，不要提问。
【这是什么】2D 横版动作肉鸽《断晓》第一章第一处战场「灯影空轿街」的**实机效果图**（一整屏游戏画面，像游戏截图，但不要任何 HUD、文字、血条、按键提示）。
【附图1】是现在游戏里入口街的实机截图：画风（手绘厚涂、哥特老城石材、银灰冷色石墙 + 暖黄窗灯、湿石板街面薄倒影）、建筑比例（一层楼约等于 1.8 个角色高）、亮度都以它为准，新画面要和它是同一个游戏、同一条街的延续，但构图、楼、物件要全新设计，不要照抄附图1。
【镜头】纯侧视横版镜头，地平线水平，建筑竖直不倾斜。玩家脚踩的街面在画面从上往下约 80% 处，街面以下是一条湿石板薄倒影（只是雨后石板反光，不是河、不是积水）。
【人物】画面里有 1 个主角：一个娇小的黑衣少女剑士，侧身持一把细长的刀，刀身带一点紫色微光（整张图里只有这把刀可以有紫色）；身高约画面高度 12%。另有 2～3 个“狂影”敌人：没有五官的黑色人形影子，边缘像烟一样微微散开，只露两点暗黄的眼睛。都是小小的游戏角色比例，不要特写。
【世界观】这座城被“白光”定住了时间：白光照到的东西保持鲜活原样、一动不动（悬停的雨珠、定格的物件）；被赶出来的流动时间沉在暗处，变成躁动的狂影。画面要一眼看出“光里静止、暗里躁动”。
【红线】除主角刀光外不得有任何紫色、品红、粉色；不得有海、河、水淹、积水水面、码头、船、船舵、绳索、木桶、吊车；不得有血、肉、尸体；不得有白瓷化或石化的雕像人；不得有正对镜头的大钟表盘；不要贵族、侍从这类阶级场面；不要文字、水印、边框、UI。
【品质】商业级 2D 横版动作游戏画面，对标《空洞骑士：丝之歌》《神之亵渎2》《奥日》的整帧完成度：前景、中景、远景至少 4 层清楚的纵深，大气透视（越远越接近雾色），光有明确来源，角色站的活动带要被衬亮、和背景分得开。
"""

JOBS = {
    "甲_连续长街": """【方向甲：连续长街——把入口街一路延续下去】
一条完整连贯的雨夜长街，没有任何拼接感：近处是一整排高大的三四层哥特商铺楼（灯笼铺、空茶座的拱廊、关着门的钟表店），楼面有凸窗、阳台、檐下铸铁灯，几扇暖窗里映着躁动的人形黑影；街上停着三四辆没有马、也没有人的黑色旧式厢式马车（“空轿”），车灯还亮着暖光，其中一辆车门半开、里面空空。
楼缝和一处大拱门里能看到后街的屋顶和远处被雨雾吞没的高大钟楼侧影（看不到表盘）。楼脚有一层低低的冷雾，把主角和敌人站的那条活动带衬亮。
天空厚云，只有一道窄窄的冷白光缝。整体：银灰石墙 + 暖灯，安静、精致、可信。""",
    "乙_白光截街": """【方向乙：白光截街——把“白光驱逐时间”放到画面正中】
厚云被撕开一道裂口，一根巨大的冷白光柱斜斜地砸在街道正中，把整条街切成“光里”和“光外”两半：
- 光柱里：雨珠悬停成一颗颗发亮的小珠，一辆没有马的空马车定格在转弯的半途，车轮旁溅起的水花也凝在半空，一盏摔落的提灯停在离地一尺处——都保持鲜活原样，颜色干净；
- 光外两侧的街：很暗，墙面和门洞里挤满躁动的黑色人形狂影，像烟一样往光边上涌，又被光边逼退，光的边缘有一圈细细的冷白亮边。
主角站在光柱边缘，一半身子在光里；狂影从暗处扑来。建筑仍是哥特商铺街，但被光柱压成大块剪影，黑白对比强烈，冲击力优先。""",
    "丙_上下两层街": """【方向丙：上下两层街——纵向层次和可站的高台一眼看清】
街道分上下两层：下层是湿石板街和一排深深的尖拱廊（拱廊里透出后街的暖灯和雾），廊下停着两辆没有马的空马车；拱廊顶上是一条带石栏杆的高架步廊，步廊在画面中间跨过一座小拱桥，连到对面一栋带角楼的高楼；角楼的阳台和挑檐形成第三层可以站的高台。
步廊上方和楼缝里能看到层层叠叠的中景屋顶、更远处雾里的老城和一座侧面的高大钟楼（看不到表盘）。
主角站在高架步廊上，狂影一个在下层街面、一个从拱廊阴影里爬出来。光：檐下铸铁灯和拱廊里的暖光一层层往上递，天顶一道冷白月光边勾出步廊栏杆。整体：纵深感、空间感最强，能站的地方（街面、步廊、阳台）结构清楚。""",
}


def run(code: str) -> dict:
    prompt = HEAD + JOBS[code] + "\n"
    CWD.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(CWD), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str(REF), "-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=str(CWD), input=prompt.encode("utf-8"), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=env, timeout=900)
    except subprocess.TimeoutExpired:
        return {"code": code, "status": "timeout"}
    out = p.stdout.decode("utf-8", "replace")
    err = p.stderr.decode("utf-8", "replace")
    (OUT / "logs").mkdir(parents=True, exist_ok=True)
    (OUT / "logs" / f"{code}_{int(t0)}.jsonl").write_text(out + "\n---STDERR---\n" + err, encoding="utf-8")
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
    png = ""
    if tid and (GEN / tid).exists():
        c = sorted((GEN / tid).glob("*.png"), key=lambda q: q.stat().st_mtime)
        png = str(c[-1]) if c else ""
    res = {"code": code, "thread": tid, "secs": round(time.time() - t0), "usage": usage, "rc": p.returncode}
    if not png:
        res["status"] = "missing"
        res["tail"] = (out + err)[-400:]
        return res
    dst = OUT / f"{code}.png"
    if dst.exists():
        dst.rename(OUT / f"{code}_{int(dst.stat().st_mtime)}.png")
    shutil.copy2(png, dst)
    res["status"] = "ok"
    res["file"] = str(dst)
    return res


def main() -> None:
    codes = sys.argv[1:] or list(JOBS)
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=len(codes)) as ex:
        results = list(ex.map(run, codes))
    hist = OUT / "runs.json"
    old = json.loads(hist.read_text(encoding="utf-8")) if hist.exists() else []
    hist.write_text(json.dumps(old + results, ensure_ascii=False, indent=1), encoding="utf-8")
    for r in results:
        print(json.dumps(r, ensure_ascii=False))


if __name__ == "__main__":
    main()
