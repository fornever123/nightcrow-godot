#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成「第一章影街 · 大纵深双路线样板（R1 2D四层重构 + R2 3D HD-2D实景）」所需的高清手绘素材。

产物目录：
  docs/_当前分支草稿/背景线/大纵深重构_20261118/raw/
    R1（2D 四层独立拆件）：
      - r1_far_sky_tower.png      远景天光云缝 + 青铜母钟楼侧影
      - r1_mid_city_abyss.png     中远景断崖深渊哥特城群（#00FF00 绿幕抠空上天）
      - r1_play_viaduct.png       玩法层高架石桥步廊 + 左侧门楼 + 透视厚湿石板 + 镂空桥洞（#00FF00 绿幕抠空）
      - r1_fg_frame.png           最前景暗剪影压框（铸铁栏杆与角部残件，#00FF00 绿幕抠空）
    R2（3D HD-2D 无缝手绘厚涂贴图）：
      - r2_tex_cobble.png         无缝湿润哥特青石板路面贴图
      - r2_tex_facade.png         无缝哥特石砌建筑立面贴图（含暖窗与石雕细节）
      - r2_tex_stone_trim.png     无缝哥特石拱/石柱/雕花檐口材质贴图
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
BASE = ROOT / "docs" / "_当前分支草稿" / "背景线" / "大纵深重构_20261118"
RAW = BASE / "raw"
GEN = Path.home() / ".codex" / "generated_images"

REF_U3 = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "升级方向" / "U3_剪影大纵深.png"
REF_U2 = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "升级方向" / "U2_HD2D实景.png"

COMMON_STYLE = """
【统一画风与世界观铁律】
- 精致 2D 黑暗哥特雨夜厚涂插画质感（参照附图画风与质感，类似《空洞骑士：丝之歌》《血源诅咒》《终焉之玛格诺莉亚》）。
- 色调：严禁廉价饱和蓝色滤镜！建筑石材为中性微暖炭灰石色，雨夜雾气偏银灰冷调，灯火为暖白偏淡金。
- 严格红线：画面任何地方严禁出现紫色、品红、粉色；严禁海洋、河面、水洼、船只、绳索、木桶、正面钟表盘、人物/路人、UI文字、边框水印。
"""

JOBS: dict[str, dict] = {
    "r1_far_sky_tower": {
        "refs": [REF_U3],
        "prompt": """请绘制一张 1672x941 横版 2D 游戏【最远景天空与司辰母钟楼】分层背景底图（不包含任何近景桥面、不包含前景、不包含人物）。
构图要求：
- 画面右上约 72% 水平位置，翻滚的银灰雨云撕开一道斜向下的冷白「驱时天光」云缝，柔和的体积光束斜照下来。
- 在冷白天光前方的远雾中，矗立着高耸入云的独立百米青铜哥特【司辰母钟楼】侧影（只画尖顶、飞扶壁、裸露的巨型青铜轮廓齿轮剪影，绝不画正面钟表盘！）。
- 天空左半与中段是深沉阴郁的银灰暗雨云，几缕极淡的墨黑长影如烟河般在高空斜向右上方母钟楼方向缓缓汇流。
- 画面底部 25% 过渡为柔和的亮银灰城市雾海，方便前方中景城群无缝叠加。
- 左右边缘云雾柔和，适合宽屏横向视差移动。""" + COMMON_STYLE,
    },
    "r1_mid_city_abyss": {
        "refs": [REF_U3],
        "prompt": """请绘制一张 1672x941 横版 2D 游戏【中远景断崖哥特城群】分层素材图，用于叠加在远景天空前方做视差移动。
【抠图铁律】：画布上半部分的天空区域必须铺满 100% 纯平无渐变的纯亮绿幕 #00FF00（不要雾气渐隐到绿幕里，屋脊剪影与绿幕交界清晰锐利），且建筑本身严禁出现任何亮绿色反光。
构图要求：
- 占据画布中下部（约 y=32% 到 y=100%）：层层叠叠、顺着断崖高低错落向下延伸的哥特老城建筑群——高耸尖顶、双层石拱高架桥、飞扶壁、窄巷阶梯与陡峭石板屋顶。
- 必须具有强烈的大气空气透视：整体明度偏亮银灰雾感（约 0.28~0.42 明度，明显亮于近景暗石桥，用来把前景暗色角色清晰衬托出来），只点缀极少量温暖淡金色远窗微光。
- 底部直通画布下沿（y=100%），画满向下延伸的深渊底层屋顶与雾中石桥，方便透过前方玩法层桥洞看到下方城市深渊！
- 左右两端建筑高度自然衔接，可横向无缝平铺。""" + COMMON_STYLE,
    },
    "r1_play_viaduct": {
        "refs": [REF_U3, REF_U2],
        "prompt": """请绘制一张 1672x941 横版 2D 动作游戏【玩法站立层：高架哥特石桥与街角门楼】独立分层图（参照附图 U3 的高架石桥断崖构图 + 附图 U2 的微俯视厚实湿石板街面）。
【抠图铁律】：所有敞开的天空区域以及石桥下方的所有拱形桥洞内部，必须 100% 铺满纯平纯亮绿幕 #00FF00（无阴影、无雾、无渐变），严禁石材沾染亮绿色。绝不画任何人物或怪物！
构图与精确几何要求（极其重要）：
- **微俯视透视湿石板步行路面**位于画布纵向 y=70% 到 y=79% 之间（一条完全水平、连续贯通画布左右边缘 x=0% 到 x=100% 的宽厚湿青石板路面，路面本身有清晰的透视石板纹理与轻微湿润反光，绝不是细线！）。
- **路面下方（y=79% 到 y=100%）**：绝不能是纯黑空洞！画满极具厚重立体感的哥特石拱桥腹、粗壮雕花石墩、石砌拱券与风化裂痕；**拱形桥洞的内部全部填满纯绿幕 #00FF00 彻底镂空**，让游戏里透过桥洞能看见下方深渊里的中景老城！
- **路面上方（y=0% 到 y=70%）打破平墙**：
  - 仅在画面最左侧 0%～32% 矗立一座厚重的三层哥特街角门楼（带侧墙透视厚度、二楼凸出暖光尖拱窗、底层暖白偏淡金壁灯、一处离地适中的石砌阳台露台）；
  - 画面中右部 32%～100% **彻底敞开不建实墙**！只保留沿桥面后缘延伸的矮石雕栏杆、两盏造型精美的铸铁暖白街灯、一处微破损的石栏断口与右端一小座石桥墩柱——让大片纯绿幕 #00FF00 天空敞开，实机里透出背后层层叠叠的深渊哥特城与天际母钟楼！
- 建筑比例宏大威严（门楼单层高度充足，绝不像微缩模型屋）。""" + COMMON_STYLE,
    },
    "r1_fg_frame": {
        "refs": [REF_U3],
        "prompt": """请绘制一张 1672x941 横版 2D 动作游戏【最前景暗剪影压框层】素材图，叠在角色最前方做视差景深。
【抠图铁律】：画面中央 75% 以上区域必须 100% 保持纯净纯平亮绿幕 #00FF00！
构图要求：
- 只在画面**最底部边缘（y=82% 到 y=100%）**画一条连绵的近黑哥特锻铁尖刺栏杆剪影（从左下斜向右中下渐隐），以及在**右下角（x=80%..100%, y=72%..100%）**压入一只巨型铸铁残破时钟齿轮的一角剪影，在**左上角（x=0%..14%, y=0%..22%）**压入一角哥特石拱檐口阴影。
- 所有前景物体均为极深炭黑剪影（亮度 0.02~0.08，仅边缘带极微弱的冷灰轮廓反光），绝不挡住画面中部的战斗视野！""" + COMMON_STYLE,
    },
    "r2_tex_cobble": {
        "refs": [REF_U2],
        "prompt": """请绘制一张 1024x1024 **四方无缝平铺（seamless tileable）** 的正俯视（top-down orthographic）手绘厚涂【雨夜湿润哥特青石板路面】3D 游戏贴图。
要求：
- 严格正俯视视角，无透视变形，无光照方向阴影（中性均匀漫反射，方便 3D 引擎实时打光）。
- 质感：古老风化的中性微暖炭灰色方石板与扇形拼石，石缝深沉湿润，石面有精致的厚涂笔触与雨夜微湿光泽感，夹杂少量细微裂纹。
- 严禁紫色、严禁水洼倒影画死、严禁文字水印。""" + COMMON_STYLE,
    },
    "r2_tex_facade": {
        "refs": [REF_U2, REF_U3],
        "prompt": """请绘制一张 1024x1024 **左右无缝平铺（horizontally tileable）** 的正立面（orthographic front elevation）手绘厚涂【哥特雨夜石砌建筑立面】3D 游戏贴图。
要求：
- 严格正视平拍，无透视斜角，上下分两层：底层为厚重深灰石块拱廊与一扇精致木门、上层为哥特双尖拱石窗（其中 2 扇透出温暖柔和的淡金琥珀色室内灯光，其余暗沉）、带雕花石砌腰线与石雕装饰。
- 石材为中性微暖炭灰，精致手绘厚涂质感（像《终焉之玛格诺莉亚》《八方旅人 II》的建筑贴图），绝不偏蓝、绝无紫色。""" + COMMON_STYLE,
    },
    "r2_tex_stone_trim": {
        "refs": [REF_U3],
        "prompt": """请绘制一张 1024x1024 **四方无缝平铺（seamless tileable）** 的正视手绘厚涂【风化哥特雕花粗石墙与石桥墩】3D 游戏材质贴图。
要求：
- 严格正视，无透视畸变，无单侧强阴影。
- 厚重的大块砌石、细密雨渍与沧桑石刻浮雕纹理，中性微暖炭灰石色，适合贴在 3D 石桥腹、石墩、护栏矮墙与远处哥特高塔上。""" + COMMON_STYLE,
    },
}


def run_job(code: str) -> dict:
    spec = JOBS[code]
    cwd = Path(os.environ.get("LOCALAPPDATA", "C:/Temp")) / f"nightcrow_codex_dlab_{code}"
    cwd.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [
        exe, "exec", "-C", str(cwd), "-m", "gpt-6.1-terra",
        "-c", 'model_reasoning_effort="medium"',
        "-c", "mcp_servers.taptap-maker.enabled=false",
        "-s", "read-only", "--skip-git-repo-check", "--json",
    ]
    for r in spec["refs"]:
        if r.exists():
            cmd.extend(["-i", str(r.resolve())])
    cmd.append("-")

    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    t0 = time.time()
    p = subprocess.run(
        cmd, cwd=str(cwd), input=spec["prompt"].encode("utf-8"),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=1500,
    )
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
    res = {"code": code, "thread": tid, "secs": round(time.time() - t0, 1), "usage": usage}
    if c:
        shutil.copy2(c[-1], RAW / f"{code}.png")
        res["status"] = "ok"
    else:
        res["status"] = "missing"
        res["tail"] = (out[-350:] + "\n" + p.stderr.decode("utf-8", "replace")[-350:]).strip()
    return res


def main() -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    codes = sys.argv[1:] or list(JOBS.keys())
    with ThreadPoolExecutor(max_workers=min(4, len(codes))) as ex:
        results = list(ex.map(run_job, codes))
    log_path = RAW / "runs.json"
    old = json.loads(log_path.read_text(encoding="utf-8")) if log_path.exists() else []
    log_path.write_text(json.dumps(old + results, ensure_ascii=False, indent=2), encoding="utf-8")
    for r in results:
        print(f"{r['code']}: {r['status']} ({r['secs']}s) tokens={r.get('usage', {}).get('input_tokens')} {r.get('tail', '')}")


if __name__ == "__main__":
    main()
