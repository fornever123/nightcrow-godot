#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 影街 3D 街体（11-19，用户：“地面做成3d，近景有距离的做真实的贴图距离，就是能走的地方，都是3d”）。
Codex 出 3D 街面 / 步廊台面 / 台口立面 / 石墙的可平铺贴图，画风对齐 1-1A 站立层原画 B1。

用法：python tools/art/bg_street3d_tex_codex.py [代号…]
产物：docs/_当前分支草稿/背景线/3D街体_20261119/贴图原图/<代号>.png（之后 bg_street3d_tex_prep.py 做无缝 + 法线进 assets）
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
OUT = ROOT / "docs" / "_当前分支草稿" / "背景线" / "3D街体_20261119" / "贴图原图"
REF = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level" / "B1.png"
REF_U2 = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "升级方向" / "U2_HD2D实景.png"
GEN = Path.home() / ".codex" / "generated_images"

HOUSE = """【构件：哥特联排小楼立面 ×2】按附图的画风画**两栋**彼此分开、左右并排的哥特老城小楼，**严格正面立面图**（正交、没有透视、看不到侧墙和屋顶上面），每栋从一楼地面的墙脚一直画到屋顶尖、完整入画，两栋之间留大块绿色空隙。
- 楼高 3～4 层，深灰偏暖的方整石墙，带石线脚腰线、尖拱窗（窗里透出暖白偏淡金的灯光，约一半窗亮）、窗台、铁艺壁灯，深冷灰石板瓦屋顶。
- 光：左上方冷月光擦亮屋檐和窗台上沿，窗里暖光，墙脚偏暗；手绘厚涂、细节丰富，和附图一样精致。
- 背景纯绿色 #00FF00，楼与楼之间、屋顶上方都是纯绿。竖版 1024×1536。
"""
COMMON = """附图1是我们 2D 横版游戏的一张哥特老城雨夜街景画面（精致手绘厚涂）。我们要把“能走的地面”改成真 3D 模型，需要给 3D 模型贴的**可无缝平铺贴图**。
要求：
- 画风、石头的颜色和笔触质感和附图里的石头一致（中性偏暖的灰石，带一点点冷，手绘厚涂但细节清楚），不要照片感、不要卡通。
- **均匀照明**：贴图里不能有方向光、投影、暗角、灯光、高光斑；整张明暗均匀，只有石头本身的颜色变化和缝隙阴影。
- 四边可以无缝平铺（左右边、上下边的内容能接上）。
- 只画材质本身，不要任何物件、植物、文字、边框、水印。
- 不得出现紫色、品红、水洼、积水、苔藓血迹。
"""

JOBS = {
    "floor_cobble": (1024, 1024, """【街面石子路】正上方垂直俯视的老城湿石子路（cobblestone），石块大小约拳头到砖块大小、排列略不规则，石缝深色，石面因为下雨略带一点湿润的微光（很淡，不要反光镜面、不要水洼）。正方形 1024×1024。"""),
    "deck_top": (1024, 1024, """【步廊台面石板】正上方垂直俯视的长方形石板铺面（比石子路的石块大很多，一块约 1:2 长条），石板之间有清楚的接缝，表面有轻微磨损和雨后潮湿感。正方形 1024×1024。"""),
    "deck_face": (1536, 384, """【步廊台口立面】从正面平视看到的一段哥特石砌步廊的台口侧面（厚约一臂），上沿一道带线脚的压檐石、下面一排小托石（corbel）往下收。只画这一条横向长条立面，左右可以无限无缝接续，背景纯绿色 #00FF00（托石之间的空隙是绿色）。宽高比 4:1，1536×384。"""),
    "prop_lamp": (1024, 1536, """【街灯杆（立体道具，不是贴图）】一根完整的哥特式铸铁街灯：石质底座、细长铸铁灯杆、顶上一盏四面玻璃灯笼，灯笼里暖白偏淡金的灯火。正面平视、垂直居中、从底座到灯笼顶完整入画、上下留一点边。背景纯绿色 #00FF00。这一张不需要无缝、可以有灯火自己的亮光，但灯杆本身不要被方向光照出明显的明暗面。竖版 1024×1536。"""),
    "prop_bollard": (1024, 1024, """【街边石桩（立体道具，不是贴图）】横向一排 3 个彼此分开的哥特老城街边石桩（车挡石，约膝盖高，方柱带斜顶或圆顶，略有风化），每个之间留大块空隙。正面平视，背景纯绿色 #00FF00。不需要无缝。正方形 1024×1024。"""),
    # 11-19 U2 HD-2D 样板角：参考图换成 U2 目标图
    "u2_floor": (1024, 1024, """【街面（HD-2D 版）】正上方垂直俯视的老城街面：大块方整石板和小石子混铺（中间一条大石板带、两侧碎石子），石块大小不一、不规则，石面因为下雨有一层很薄的湿润光泽（不要水洼、不要镜面倒影）。颜色中性偏暖灰。正方形 1024×1024。"""),
    "u2_windows": (1536, 1024, """【构件：哥特窗】一张图里横排 4 扇彼此分开、互不重叠的哥特式尖拱窗（石窗框 + 铅条玻璃），窗里透出暖白偏淡金的室内灯光，其中 1 扇是不亮的暗窗。正面平视、每扇完整入画。背景纯绿色 #00FF00（窗与窗之间是大块绿色）。这张允许窗里的灯光。1536×1024。"""),
    "u2_doors": (1536, 1024, """【构件：门与店面】一张图里横排 3 个彼此分开的构件：一扇带石拱门框的厚木门、一个透出暖光的小店橱窗（橱窗里摆着瓶罐，不要木箱木桶）、一扇带铁格栅的半圆拱门。正面平视、每个完整入画。背景纯绿色 #00FF00。1536×1024。"""),
    "u2_roof": (1024, 1024, """【屋顶石板瓦】正面看的哥特老屋屋面：深灰偏冷的鱼鳞形 / 长方形石板瓦一排排叠压，被雨打湿。正方形 1024×1024。"""),
    "u2_balustrade": (1536, 384, """【构件：石栏杆一段】从正面平视的一段哥特石栏杆：上面一条扶手压顶石、下面一条底座、中间一排宝瓶形栏杆柱（balusters），左右可以无限无缝接续。背景纯绿色 #00FF00（栏杆柱之间的空隙是绿色）。4:1，1536×384。"""),
    # 11-19 用户选“手绘分层”：楼 / 拱廊用 U2 画风的手绘构件按真实距离摆
    "u2p_house_a": (1024, 1536, HOUSE + "这一张：左边一栋带尖山墙朝前、二楼一个挑出的凸窗；右边一栋平檐带一排老虎窗。"),
    "u2p_house_b": (1024, 1536, HOUSE + "这一张：左边一栋窄高、带一座小尖塔；右边一栋宽一些、二楼带石栏杆小阳台。"),
    "u2p_house_c": (1024, 1536, HOUSE + "这一张：左边一栋带两个并排小山墙；右边一栋带圆角塔楼和尖顶。"),
    "u2p_arcade_front": (1536, 512, """【构件：拱廊前排柱拱】正面平视的一排哥特石拱廊的**前排**：上面一条厚石梁（上层步廊的台口，带线脚和小托石），下面一排圆形石柱（带柱础、柱头）撑着一个个半圆拱。**拱洞里面全部是纯绿色 #00FF00**（只画柱子和拱，不画拱廊里面的东西），柱子下面到画底也是绿色以外的柱础。左右可以无缝接续。手绘厚涂，冷月光从左上擦亮拱边，柱子下部偏暗。3:1，1536×512。"""),
    "u2p_arcade_back": (1536, 512, """【构件：拱廊后墙】正面平视的一段哥特拱廊**里面的后墙**（在拱廊柱子后面、离街远一点）：深色石墙上依次有一扇厚木门、一个透着暖光的小店橱窗（瓶罐，不要木箱木桶）、两扇亮着暖光的尖拱窗、一盏铁艺壁灯；墙脚有一级台阶。整体比前排暗一点，有空气感。左右可以无缝接续，铺满整幅、不留绿色。3:1，1536×512。"""),
    "wall_stone": (1024, 1024, """【石墙】从正面平视的哥特老城方整石砌墙面（ashlar），石块大小和附图墙面一致，灰缝清楚，石面有风化和雨痕。正方形 1024×1024。"""),
}


def run(code: str) -> dict:
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_tex_{code}"
    cwd.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [exe, "exec", "-C", str(cwd), "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="medium"',
           "-c", "mcp_servers.taptap-maker.enabled=false", "-s", "read-only", "--skip-git-repo-check",
           "--json", "-i", str((REF_U2 if code.startswith("u2") else REF).resolve()), "-"]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    prompt = COMMON + JOBS[code][2]
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
