#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 画面重构样板屏「光压城，影沉底」分层素材生图（Codex，2026-11-17）。

用法：python -I tools/art/rain_redesign_codex.py [层代号 ...]   不写代号 = 全部
产物：docs/_当前分支草稿/背景线/画面重构_20261117/codex原图/<代号>.png 与 runs.json
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(r"E:\00game\nightcrow-godot")
OUT = ROOT / "docs" / "_当前分支草稿" / "背景线" / "画面重构_20261117" / "codex原图"
CWD = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / "nightcrow_codex_bg_redesign"
STYLE_REF = ROOT / "docs" / "视觉设计" / "雨夜河岸街" / "成图_分层试验" / "Codex原图_站立层_乙2_修正版.png"
GEN = Path.home() / ".codex" / "generated_images"
_LOCK = threading.Lock()

HEAD = """请直接调用一次图片生成工具，生成 1 张横版宽幅（16:9，1672×941 或 1536×1024）的图片。只调用一次图片生成工具，不要重试，不要写代码，不要运行终端命令，不要提问。
【附图】（若是站立层任务，附图1同时锁定比例和亮度，见下文）附图1用来对齐画风：2D 横版动作游戏的手绘厚涂、哥特老城石材、冷灰蓝夜色、干净的冷白受光边和克制的暖黄灯。不要照搬附图1的构图、楼、物件（尤其不要它的船舵、绳索、木桶、吊车、招牌）。
【画风】商业级 2D 横版动作游戏背景分层素材。学习《空洞骑士》《丝之歌》的方法：大块干净的剪影、强烈的大气透视（越远越接近雾色、越近越暗）、细节只集中在受光边缘、大量安静的负空间。纯侧视正交视角：没有透视灭点、没有俯仰，所有建筑竖直不倾斜，比例写实不夸张。
【红线】画面中不得出现任何紫色、品红、粉色；不得出现海、河、水面、积水倒影、码头、吊车、船、船舵、绳索、木桶；不得出现正面的大钟表盘；不得出现人物、动物、鸟、文字、字母、水印、边框、UI。
"""

GREEN = """【抠图底色】所有“空”的地方（天空、能看穿的门洞拱洞、物件之间）一律用 100% 纯平涂亮绿色 #00FF00 填满。绿色区域内不要任何渐变、雾气、光晕、噪点、反光；物体边缘不要绿色溢色描边，边缘干净利落。
"""

NEAR = """【内容】《断晓》入口街“站立层”的升级版：玩家奔跑的那一排街楼 + 脚下湿石板街 + 街面下的石砌墙，用来替换附图1。
【比例必须照附图1】画面同为 1672×941 时，玩家脚踩的街面在从上往下第 800 行左右（约 85% 处），街面以下是和附图1一样高的石砌墙一直到画面底；楼层高度、门窗大小和附图1完全一致（一层楼约占画面高度 16%），楼要顶到画面上沿附近，不要把楼画小、画矮。
【亮度不能比附图1暗】石材是有明暗层次的冷灰蓝，被路灯和橱窗照到的墙面要看得清石块、雕花和窗框；暗部也要有细节，不要大片死黑。
【升级要点】楼面前后有层次：凸出的阳台、悬挑的二层、深门廊、几级石阶上到门口、檐下挂的铸铁灯、透出暖光的店铺橱窗；屋顶轮廓丰富：尖顶小塔、成对烟囱、老虎窗、屋脊滴水兽；湿石板街面反光，路灯在街面投下暖色光斑。
【挖空】楼与楼之间留 1～2 道窄巷缝，巷缝里挖空为 #00FF00；楼顶以上的天空全是 #00FF00；下面写到的拱门洞 / 廊下也挖空为 #00FF00（以后透出后面的远景）。
【拼接】最左边和最右边都正好截在一道窄巷缝（#00FF00）上；街面和街下石墙在左右两端的高度和附图1一模一样，好几张横向拼在一起。
【不要】船舵、绳索、木桶、木箱、吊车、锚、渔网等任何码头物件；任何紫色；正面的大钟表盘；人物和动物。
"""
NEAR_REF = ROOT / "docs" / "视觉设计" / "雨夜河岸街" / "成图_分层试验" / "Codex原图_站立层_乙2_修正版.png"

JOBS: dict[str, dict] = {
    "N1_near": {"green": True, "ref": "stand", "body": NEAR + """【这一张的主题】左边一间钟表修理铺（橱窗里暖光，挂着几只停摆的小怀表），中间一座三层哥特大宅，一层正中是一个高大的尖拱门洞（门洞挖空 #00FF00），门洞两侧各一盏壁灯；右边一栋窄高的四层石楼。"""},
    "N2_near": {"green": True, "ref": "stand", "body": NEAR + """【这一张的主题】左边一栋带石阶和深门廊的书店（橱窗暖光，门廊里有一盏吊灯），中间一座高窄的方形钟亭塔楼（侧面，看不到表盘），塔楼和右边楼之间在二层高度架一道带栏杆的石廊桥，廊桥下面挖空 #00FF00；右边是带悬挑木结构二层的老茶馆，窗里暖光。"""},
    "N3_near": {"green": True, "ref": "stand", "body": NEAR + """【这一张的主题】左边一栋高高的四层哥特住宅，外墙挂一道铸铁折梯通到二层阳台；中间一排带铸铁雨棚的小店面（花店已关门、窗内一盏小灯），雨棚下街面最亮；右边一座带角楼的街角楼，一层有一个通往后街的低矮拱廊（拱廊挖空 #00FF00）。"""},

    "L1_sky": {"green": False, "body": """【内容】夜空整图（没有任何建筑、地面、月亮、星星）：画面上方三分之二是厚重的冷灰蓝雨云，云层在画面中间偏左的上方被撕开一道长长的裂缝，冷白色的天光从裂缝里压下来，形成 4 道从上往下、略微倾斜、边缘柔和的冷白光柱，一直落到画面底部；光柱照亮附近云层的下缘。画面下方三分之一是无建筑的灰蓝雾霭，越往下越暗。整体中低明度、冷色，最亮处只在云缝和光柱的中心，雾和云有细腻的厚涂笔触。"""},
    "L2_far": {"green": True, "body": """【内容】远城天际线长条（会被横向循环拼接）：画面下方一半是一整排极远处哥特老城的剪影——尖顶、侧面的钟塔（看不到表盘）、教堂尖塔、成片屋脊，高低错落但整体是平缓起伏的波浪，最高的尖塔约到画面高度的 55%。被厚雾吞没：剪影是很浅的灰蓝色（明度约 35%～50%），几乎没有内部细节，只在屋脊上有极淡的冷白受光，零星 3～5 个极小的暖窗点。剪影底部向下渐渐融进同色的灰蓝雾，画面最底部 15% 是实心灰蓝雾色（不是绿色）。左右两端的剪影高度相近。剪影上方的天空全部是 #00FF00。"""},
    "L3_mid": {"green": True, "body": """【内容】中景老城屋顶长条（会被横向循环拼接）：一排中等距离的老城屋顶群——陡峭的石板坡屋顶、成簇的砖烟囱、老虎窗、细窄的塔楼、屋脊上的小铁栏。屋脊线有清楚的节奏（大、小、小、大），最高处约到画面高度的 70%。中等雾化：灰蓝色，明度约 20%～32%；只在屋脊、烟囱顶有一线冷白受光边；零星 6～8 扇小小的暖黄窗。屋顶下面的楼体向下融进暗灰蓝雾，画面最底部 20% 是实心暗灰蓝雾色（不是绿色）。左右两端屋脊高度相近。屋顶上方的天空全部是 #00FF00。"""},
    "L4a_facade": {"green": True, "body": """【内容】近后景街屋立面（舞台布景片一样的纯侧视立面）：一排 3～4 层高的哥特式联排石楼，高窄的尖拱窗、阳台铸铁栏、陡峭尖屋脊、成对的砖烟囱，楼顶高低错落，最高处约到画面高度的 90%。最重要的设计：一层是一整排深深的拱廊（3 个高高的尖拱门），**拱门里面是挖空的 #00FF00**（以后从里面透出远处的亮雾）；二、三层只有 2 扇窗透出暖黄灯光，其余窗是黑的。石材是墨蓝灰，整体很暗（明度约 10%～18%），只在檐口、窗台、拱券边缘有冷白的受光边。楼脚落在一条平直的水平线上，画面最底部 8% 是暗石色的墙基（不是绿色）。楼与楼之间留一道窄巷缝，缝里也是 #00FF00。楼顶上方的天空全部是 #00FF00。"""},
    "L4b_facade": {"green": True, "body": """【内容】近后景街屋立面第二款（纯侧视立面）：画面中间偏右是一座更高更窄的石砌钟亭塔楼（侧面，绝对看不到表盘），塔顶是镂空的尖顶钟亭，**钟亭的镂空处是 #00FF00**；左边是两栋矮一些的三层哥特石楼；塔楼和左边石楼之间，在二层高度架着一座带栏杆的石拱廊桥，**廊桥下方的拱洞挖空为 #00FF00**。一层有一扇高高的尖拱门洞，**门洞里也是 #00FF00**。只有 2～3 扇窗亮着暖黄灯。石材墨蓝灰，整体很暗（明度约 10%～18%），只在檐口、拱券、塔尖边缘有冷白受光边。楼脚落在一条平直的水平线上，画面最底部 8% 是暗石色墙基（不是绿色）。楼顶上方的天空全部是 #00FF00。"""},
    "L5_deck": {"green": True, "body": """【内容】玩家奔跑的地面：纯侧视的高架石街截面（不是码头、不是河岸，下面没有水）。从上到下：①画面上部 38% 全是 #00FF00；②一条笔直水平的街面（厚度约画面高度 5%），顶面是湿润发亮的石板，**顶边有一道清晰连续的冷白亮边**（天光照在街沿上），街面上没有任何物件；③街面下是一条雕花石檐带和一排短短的石栏柱装饰（都在街面以下）；④再往下是一排巨大的石拱桥墩：中间 2 个完整的大半圆拱，左右两端各半个拱，**拱洞内部全部挖空为 #00FF00**；桥墩粗壮厚重，石块砌缝清楚，越往下越暗，画面最底部 12% 的桥墩完全没入纯黑。石材墨蓝灰，只有街沿亮边和拱券上缘有冷白光，桥墩侧面隐约有一点冷蓝反光。左右两端都在桥墩正中截断，方便横向循环拼接。"""},
    "L6_lower": {"green": True, "body": """【内容】深谷底下的旧城屋顶群（以后放在高架桥的桥洞后面、从高处往下看到；纯侧视）：画面里**绝对不要桥、不要拱桥、不要栏杆、不要拱廊**，只有一层层前后叠压、挤在一起的老城坡屋顶、烟囱、尖顶、断了半截的钟塔顶，像整座城沉在深谷里，越往下越暗，最后完全没入黑色浓雾。屋顶轮廓有大小节奏，最高的断塔尖约到画面高度 65%。画面上部 30% 是 #00FF00；最上沿的几处屋顶被斜上方来的冷白光照到（受光边很淡、很窄），其余都是墨蓝黑的剪影，只有 2～3 点非常微弱的暖光。画面下方 35% 是近乎纯黑（明度 3%～6%）的浓雾，雾里只能隐约看到更深处的屋顶轮廓。没有水，没有河。左右两端高度相近，可横向循环。"""},
    "L7_fg": {"green": True, "body": """【内容】前景剪影素材表：在纯 #00FF00 底上整齐排开 6 个互不重叠、彼此间距宽松的独立物件，每个都是**近乎纯黑的剪影**（明度 2%～6%），只有极细的冷蓝轮廓光，用作镜头最前方的虚化遮挡层：①一根高高的哥特铸铁路灯柱，灯罩里只有灯芯一点暖光（占画面约 85% 高）；②一段带尖头的铸铁栏杆（横向长条）；③一根断裂的石柱带半个拱券；④一只蹲在一截石檐上的滴水兽石像；⑤一组从画面顶边垂下来的粗铁链和铁钩；⑥一块从画面顶边伸下来的石拱门楣转角。除⑤⑥贴着画面顶边外，其余物件底部切平、贴着画面底边。"""},
}


def run(code: str) -> dict:
    job = JOBS[code]
    prompt = HEAD + (GREEN if job["green"] else "") + job["body"] + "\n"
    CWD.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(CWD), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str(NEAR_REF if job.get("ref") == "stand" else STYLE_REF), "-"]
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
