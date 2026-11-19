#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 立体感重做（11-18）：拿实机一帧当构图参考，Codex 重画 3 个差异很大的整屏目标画面（去蓝滤镜、远近分层）。

用法：python tools/art/bg_direction_codex.py [代号…]（D1_… / S1_… 等，见 DIRS）
产物：docs/_当前分支草稿/背景线/立体感_20261118/方向图/<代号>.png 与 runs.json
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
OUT = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "方向图"
REF = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "实机_0" / "x03300.png"
GEN = Path.home() / ".codex" / "generated_images"

COMMON = """附图1是我们 2D 横版动作游戏现在的实机一帧（哥特老城雨夜，上下两层街：下面是街面，上面是带石栏杆的步廊，左边拱门里一辆空马车，后面是宅邸、尖顶楼和远处城区，中间站着一个很小的持剑少女）。
现在的问题：整张画面被一层蓝色滤镜罩住，近处远处一样蓝、一样亮、一样清楚，看起来像一张平贴的纸片，没有立体感。
请重画一张**整屏目标画面效果图**（1672×941，横版，镜头角度和附图一样是侧面平视），保留同样的场景要素和大致构图（街面在画面下方约 1/5 处、上层步廊、拱门马车、宅邸、路灯、尖顶、小角色），但按下面的方向彻底重做光影、色彩和远近层次：
"""

RED = """
【红线】除了角色剑上原有的一点紫光，画面任何地方不得出现紫色、品红、粉色；不得出现水面、积水、水洼倒影、船、绳索、木桶、木箱、正面钟表盘、血、白瓷或石化效果；不要任何文字、UI、血条、水印、边框。画风是精致手绘厚涂，和附图同一类哥特建筑。
"""

DIRS = {
    "D1_冷暖纵深": """【方向：冷暖纵深 · 明度三级】（参考空洞骑士、Ender Lilies 的层次做法）
- 最前景：画面左右边缘压几件几乎纯黑的近景剪影（粗石柱、铸铁栏杆、垂下的断拱），轻微虚焦。
- 站立层（街面、步廊、拱门、马车、宅邸近处墙面）：中性偏暖的灰褐色石头，不是蓝色；被琥珀色路灯照出一团团清楚的暖光，光照到的石块有立体起伏；阴影是深炭黑。
- 中景楼：退成灰青色，对比明显降低、细节变少。
- 远景城区和天空：很淡、偏亮的冷灰蓝雾里的剪影，几乎和天空融在一起。
- 三级明度必须一眼分开：前景最黑 → 站立层中等且对比最强 → 远景最亮最淡。蓝色只留在远景和天空。""",
    "D2_月下逆光": """【方向：月下逆光 · 层层剪影】（参考 Ori、Limbo 的逆光剪影层次）
- 天空靠下的一大片是冷白的月光雾（月亮在画外或被云遮住，只见一片发亮的云层）。
- 所有建筑都是逆光：离镜头越远越淡越亮，至少 5 层楼的剪影一层叠一层往后退，每层顶边一道冷白亮边。
- 站立层整体偏暗但轮廓清晰，窗里点点暖灯，路灯一圈暖光；最前景有一两件全黑剪影。
- 空气里有斜着的雨幕和从云缝漏下来的淡光束。
- 色调是银灰 + 暖窗灯，不要饱和的蓝色。""",
    "D3_琥珀灯火": """【方向：琥珀灯火 · 电影光】（参考老照片里钠灯照亮的夜街、电影夜景布光）
- 整体从蓝调改成炭黑 + 琥珀金：街面和步廊被一排路灯照成一条条暖金色光带，每盏灯下有清楚的体积光锥穿过雨丝。
- 阴影深而干净（暖黑、炭灰），光暗对比强烈，像电影夜景布光。
- 天空是深炭灰带一点点青灰，不是饱和蓝；远处楼在暖色薄雾里变淡、变模糊。
- 最前景一两件近乎黑色的剪影压在画边，增加纵深。""",
}


# 11-18 用户：“你能不能想想这个是影街啊”——第二轮按影街世界观出（白光驱逐时间：光里停住、暗处积成狂影）
WORLD = """
【这条街是什么】这是「影街」：天顶裂口渗下的白光只有一个性质——驱逐时间。被白光照住的东西保持 100% 鲜活原貌、停在那一秒（雨珠悬在半空不落，颜色和细节清清楚楚，绝不是白瓷、石像或褪色）；从光里赶出来的流动时间全挤进照不到光的地方，沉积成会蠕动的浓墨黑影（狂影）。影街是空城，没有任何路人；满墙黑影在躁动，并顺着街往远处的司辰母钟楼汇流。白光每晚从高空一点点往下压。黑影必须是纯墨黑 / 深炭色，绝不能带紫色。
"""

S_DIRS = {
    "S1_白光压城": """【方向：白光压城 · 上停下流】
- 画面上部约 1/3（远处尖顶、宅邸屋顶、天空）被从天顶斜压下来的冷白光淹没：这一截的屋顶、尖塔清晰锐利、颜色鲜活，雨珠在这里全部悬停成一颗颗发亮的水珠，像时间被按了暂停。
- 一条清楚的明暗分界线横切过建筑中部，线以下是影街：街面、步廊、拱门沉在冷灰蓝的阴影里，雨照常往下落；墙面和墙脚爬满墨黑的狂影（像烟又像墨的长条黑影，从墙缝和门洞里往外涌），只有几盏暖白偏淡金的小灯照出局部。
- 远近层次靠这条“光 / 影”分界和白光里的远景剪影拉开：越远越被白光吃掉、越亮越淡。""",
    "S2_影流向钟楼": """【方向：影流向钟楼 · 纵深汇流】
- 远景正中偏右，一座百米青铜机械巨塔「司辰母钟楼」的侧面剪影高耸进云里（只能看到塔身、齿轮结构和尖顶，不要画任何正面钟盘），塔顶背后被白光照亮。
- 全街的墨黑狂影像一条条黑色的烟河，贴着墙面、屋檐、街面往画面深处的母钟楼流过去：近处的黑影大、浓、边缘翻卷；越远越细、越淡，最后汇进钟楼脚下。这股流向本身就把画面的纵深拉出来。
- 建筑是冷灰蓝湿石板（低饱和的灰蓝，不是蓝色滤镜），近处暗而对比强，远处在白雾里变亮变淡；只有零星暖白偏淡金的灯。湿石板街面只有很薄的倒影。""",
    "S3_光缝停时": """【方向：光缝停时 · 明暗切块】
- 天顶白光从楼与楼之间的缝隙、破屋顶里直直劈下来几道又窄又亮的光柱，斜斜落到步廊和街面上。
- 每道光柱里时间是停住的：雨珠悬在半空成一串串亮点，光柱照到的那一小块街景保持鲜活原色（木门的红褐、铜灯的金、窗帘的暗绿、石头的暖灰都清清楚楚）。
- 光柱之外整条街沉在深灰蓝的暗里，墙上、地上的墨黑狂影在光柱边缘被切开、往暗处退缩翻滚；最前景压一两件近黑的剪影。
- 层次靠一道道光柱在不同远近处落下（近处的光柱粗、虚，远处的细、清）来拉开。""",
}
DIRS.update(S_DIRS)

# 11-18 用户：“影3是最差的，以后绝对不要再用。1和2感觉亮了”——影1、影2 原图当参考，只压暗 + 修毛病
DARK_COMMON = """附图1是我们已经选中方向的一张「影街」目标画面。保持构图、建筑、角色、狂影的形状和走向、远景内容全部不变，只做下面的修改：
- 整体压暗成真正的深夜：画面平均亮度降到附图的一半左右。街面、站立层的楼大部分沉进深炭灰的暗里，只有暖白偏淡金的灯照到的地方和窗灯是亮的。
- 层次必须保留：远处白光里的那一块依然是全画面最亮的，但面积收小、亮度收住，不要大片发白、不要光芒四射。
- 墨黑狂影更浓、更黑、更有压迫感。
- 不要整体蓝色滤镜：暗部是中性的深炭灰，只带一点点冷。
"""
DARK = {
    "S1d_白光压城_暗": ("S1_白光压城.png", """- 去掉建筑中间那条发光的横向分界线，改成白光从天顶往下渐渐变弱、由亮到暗的柔和过渡。
- 悬停的雨珠只留在上部白光里，变小，像细碎发亮的光点，不要卡通水滴形状。"""),
    "S2d_影流向钟楼_暗": ("S2_影流向钟楼.png", """- 画面底部那片黑色波浪看起来像水面，必须改成贴着地面翻卷的墨黑烟雾（像浓烟、像墨在空气里散开），不能有任何水、浪、海的感觉。
- 母钟楼依旧是远景侧影，只有塔身、齿轮和尖顶，不画正面钟盘。"""),
}


def run(code: str) -> dict:
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_dir_{code[:2]}"
    cwd.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(cwd), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str((OUT / DARK[code][0]).resolve() if code in DARK else REF.resolve()), "-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    if code in DARK:
        prompt = DARK_COMMON + DARK[code][1] + WORLD + RED
    else:
        prompt = COMMON + (WORLD if code.startswith("S") else "") + DIRS[code] + RED
    p = subprocess.run(cmd, cwd=str(cwd), input=prompt.encode("utf-8"), stdout=subprocess.PIPE,
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
    res = {"code": code, "thread": tid, "secs": round(time.time() - t0), "usage": usage}
    if c:
        shutil.copy2(c[-1], OUT / f"{code}.png")
        res["status"] = "ok"
    else:
        res["status"] = "missing"
        res["tail"] = out[-400:]
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
        print(r["code"], r["status"], r["secs"], r.get("usage", {}).get("input_tokens"))


if __name__ == "__main__":
    main()
