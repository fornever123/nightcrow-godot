#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""执行已获用户明确批准（原话：“A”）的第一章方案 A 扩充包生图任务（17 张正式图，含重抽硬上限 22 次调用）。

严格护栏：
1. 模型固定：codex exec -m gpt-6.1-terra -c model_reasoning_effort="medium" -c mcp_servers.taptap-maker.enabled=false
2. 严守硬上限 MAX_APPROVED_CALLS = 22（17 张首轮 + 最多 5 次瑕疵重抽），每次真实调用均落盘计入 summary_codex_runs.json；
3. 遇到配额/额度错误立即熔断取消后续排队任务并汇报；
4. 仅挂载 100% 无人物、无水印的纯净标杆图（绿底抠空件挂 Codex原图_站立层_乙2_修正版.png + 对应关卡成图；整屏件挂 style_entry_benchmark.png + 对应关卡成图）。
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import shutil
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"E:\00game\nightcrow-godot")
PROMPT_DIR = ROOT / "docs" / "视觉设计" / "地图规划" / "提示词_第一章扩充A_20261114"
CH1_INITIAL_DIR = ROOT / "docs" / "视觉设计" / "地图规划" / "第一章成图_20261114"
OUT_DIR = ROOT / "docs" / "视觉设计" / "地图规划" / "第一章扩充A_20261114"

ISOLATED_CWD = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\dd3f72bb-5259-4e90-aa89-c06a4ccca2b9\scratch\codex_refs")
CUTOUT_BENCH_REF = ROOT / "docs" / "视觉设计" / "雨夜河岸街" / "成图_分层试验" / "Codex原图_站立层_乙2_修正版.png"
FULL_BENCH_REF = ISOLATED_CWD / "style_entry_benchmark.png"
CODEX_GEN_ROOT = Path.home() / ".codex" / "generated_images"

MAX_APPROVED_CALLS = 22

EXEC_HEADER_CUTOUT = """【已获用户明确批准（原话：“A”）——请直接执行，无需再次询问确认】
请直接调用一次图片生成工具，生成 1 张宽幅横版（16:9，1672×941 或 1536×1024 横构图）的 2D 横版动作游戏商业级绿底镂空站立层背景资产。只调用一次图片生成工具，不要重试，不要写代码，不要运行终端命令。
【附图说明】附图1是《断晓》入口街纯绿底（#00FF00）站立层标杆（严格对齐其 100% 纯平涂亮绿 #00FF00 天空抠空法、0.75 建筑比例、厚涂失边笔触、深冷石板灰蓝 0.11–0.17 暗部明度与干净克制的暖白偏淡金灯火）；附图2是本拼块直接左右衔接的同关主图（严格对齐其石材色调、灯光冷暖与地面高度，不要照搬附图1右上角的吊车前景）。
"""

EXEC_HEADER_FULL = """【已获用户明确批准（原话：“A”）——请直接执行，无需再次询问确认】
请直接调用一次图片生成工具，生成 1 张宽幅横版（16:9，1672×941 或 1536×1024 横构图）的 2D 横版动作游戏商业级整屏厚涂背景成图。只调用一次图片生成工具，不要重试，不要写代码，不要运行终端命令。
【附图说明】附图1是《断晓》入口街画风与光感母本（严格对齐其厚涂失边质感、0.75 建筑尺度、深冷石板灰蓝暗部与干净暖白偏淡金局部光源，不要照搬附图1右上角斜穿画面的吊臂）；附图2是同章节相邻关卡成图（严格保持同一座城市的材质与色调统一）。
"""

JOBS = [
    {"code": "A01", "stem": "A01_1-1A左拼块_书报钟亭与暗拱长街", "mode": "cutout", "stage_ref": "成图16x9_01_1-1_无人夜宴街.png"},
    {"code": "A02", "stem": "A02_1-1A右拼块_停摆茶座外廊与石阶", "mode": "cutout", "stage_ref": "成图16x9_01_1-1_无人夜宴街.png"},
    {"code": "A03", "stem": "A03_1-2A左拼块_铅皮高脊与群鸦烟囱林", "mode": "cutout", "stage_ref": "成图16x9_02_1-2A_飞鸦玻璃花房顶.png"},
    {"code": "A04", "stem": "A04_1-2A右拼块_铜制通风塔与碎裂温室翼", "mode": "cutout", "stage_ref": "成图16x9_02_1-2A_飞鸦玻璃花房顶.png"},
    {"code": "A05", "stem": "A05_1-2B左拼块_发条修配窄门与过街石梁", "mode": "cutout", "stage_ref": "成图16x9_03_1-2B_百表当铺夹巷.png"},
    {"code": "A06", "stem": "A06_1-2B右拼块_挂表铁栈桥与暗巷深井", "mode": "cutout", "stage_ref": "成图16x9_03_1-2B_百表当铺夹巷.png"},
    {"code": "A07", "stem": "A07_1-3A左拼块_双层铆接高架西引桥", "mode": "cutout", "stage_ref": "成图16x9_04_1-3A_逆影铸铁飞廊.png"},
    {"code": "A08", "stem": "A08_1-3A右拼块_信号灯笼桥台与逆影石墩", "mode": "cutout", "stage_ref": "成图16x9_04_1-3A_逆影铸铁飞廊.png"},
    {"code": "A09", "stem": "A09_1-3B左拼块_断裂音叉架与铸钟熔炉冷室", "mode": "indoor", "stage_ref": "成图16x9_05_1-3B_司辰铸钟残廊.png"},
    {"code": "A10", "stem": "A10_1-3B右拼块_巨型钟锤滑轨与试音残钟厅", "mode": "indoor", "stage_ref": "成图16x9_05_1-3B_司辰铸钟残廊.png"},
    {"code": "A11", "stem": "A11_1-4上段_母钟擒纵天轴与临顶盘旋阶", "mode": "indoor", "stage_ref": "成图16x9_06_1-4_巨钟背影盘旋阶.png"},
    {"code": "A12", "stem": "A12_1-1B左拼块_停摆电车雨站_西月台与559站钟", "mode": "cutout", "stage_ref": "成图16x9_01_1-1_无人夜宴街.png"},
    {"code": "A13", "stem": "A13_1-1B右拼块_停摆电车雨站_车厢影群与东天桥", "mode": "cutout", "stage_ref": "成图16x9_01_1-1_无人夜宴街.png"},
    {"code": "A14", "stem": "A14_S1_无主校时表坊_肉鸽中场休整室", "mode": "indoor", "stage_ref": "成图16x9_03_1-2B_百表当铺夹巷.png"},
    {"code": "A15", "stem": "A15_E1_漏光校晷小广场_破晓乱入与同道试刀场", "mode": "outdoor_full", "stage_ref": "成图16x9_07_J1J2_街口高低分流岔路.png"},
    {"code": "A16", "stem": "A16_1-3C左拼块_司辰母钟楼正门前庭_万表校时阶", "mode": "cutout", "stage_ref": "成图16x9_06_1-4_巨钟背影盘旋阶.png"},
    {"code": "A17", "stem": "A17_1-3C右拼块_司辰母钟楼正门前庭_青铜总枢巨门", "mode": "cutout", "stage_ref": "成图16x9_06_1-4_巨钟背影盘旋阶.png"},
]

_LOCK = threading.Lock()


def normalize_to_16x9(raw_png: Path, std_dst: Path) -> dict:
    im = Image.open(raw_png).convert("RGB")
    w, h = im.size
    target_w, target_h = 1672, 940
    target_ratio = target_w / target_h
    cur_ratio = w / h
    if abs(cur_ratio - target_ratio) < 0.012:
        cropped = im
    elif cur_ratio > target_ratio:
        new_w = int(round(h * target_ratio))
        x0 = (w - new_w) // 2
        cropped = im.crop((x0, 0, x0 + new_w, h))
    else:
        new_h = int(round(w / target_ratio))
        # Bias slightly toward keeping bottom ground line intact
        y0 = int(round((h - new_h) * 0.45))
        cropped = im.crop((0, y0, w, y0 + new_h))
    im_169 = cropped.resize((target_w, target_h), Image.Resampling.LANCZOS)
    im_169.save(std_dst, format="PNG")

    arr = np.asarray(im_169, dtype=np.float32) / 255.0
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    is_green = (g - np.maximum(r, b)) > 0.18
    non_green = ~is_green
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    band_mask = non_green[int(target_h * 0.45) : int(target_h * 0.85), :]
    band_lum = lum[int(target_h * 0.45) : int(target_h * 0.85), :]
    valid_vals = band_lum[band_mask] if np.any(band_mask) else band_lum.ravel()

    # Check forbidden purple tint (R>0.25, B>0.30, B>G*1.35 and R>G*1.25)
    purple_mask = non_green & (r > 0.22) & (b > 0.28) & (b > g * 1.35) & (r > g * 1.22)
    return {
        "raw_size": f"{w}x{h}",
        "green_pct": round(float(is_green.mean() * 100.0), 2),
        "band_med_lum": round(float(np.median(valid_vals)), 4),
        "band_mean_lum": round(float(np.mean(valid_vals)), 4),
        "bright_gt45_pct": round(float((lum[non_green] > 0.45).mean() * 100.0), 2) if np.any(non_green) else 0.0,
        "purple_pct": round(float(purple_mask.mean() * 100.0), 3),
    }


def run_one_job(job: dict, extra_note: str = "") -> dict:
    stem = job["stem"]
    prompt_txt_path = PROMPT_DIR / f"{stem}.txt"
    base_prompt = prompt_txt_path.read_text(encoding="utf-8")
    header = EXEC_HEADER_CUTOUT if job["mode"] == "cutout" else EXEC_HEADER_FULL
    full_prompt = header.strip() + "\n\n" + base_prompt.strip()
    if extra_note:
        full_prompt += "\n\n【补充修正要求】\n" + extra_note.strip()
    full_prompt += "\n"

    ref1 = CUTOUT_BENCH_REF if job["mode"] == "cutout" else FULL_BENCH_REF
    ref2 = CH1_INITIAL_DIR / job["stage_ref"]
    assert ref1.exists(), f"Missing ref1: {ref1}"
    assert ref2.exists(), f"Missing ref2: {ref2}"
    ISOLATED_CWD.mkdir(parents=True, exist_ok=True)

    codex_bin = shutil.which("codex.cmd") or shutil.which("codex") or "codex.cmd"
    cmd = [
        codex_bin,
        "exec",
        "-C", str(ISOLATED_CWD),
        "-m", "gpt-6.1-terra",
        "-c", 'model_reasoning_effort="medium"',
        "-c", "mcp_servers.taptap-maker.enabled=false",
        "-s", "read-only",
        "--skip-git-repo-check",
        "--json",
        "-i", str(ref1),
        "-i", str(ref2),
        "-",
    ]

    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"

    with _LOCK:
        before_dirs = set(os.listdir(CODEX_GEN_ROOT)) if CODEX_GEN_ROOT.exists() else set()

    t0 = time.time()
    proc = subprocess.run(
        cmd,
        cwd=str(ISOLATED_CWD),
        input=full_prompt.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=540,
    )
    elapsed = round(time.time() - t0, 1)
    stdout_txt = proc.stdout.decode("utf-8", errors="replace")
    stderr_txt = proc.stderr.decode("utf-8", errors="replace")

    log_dir = OUT_DIR / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    ts_tag = int(time.time())
    (log_dir / f"codex_{job['code']}_{ts_tag}.jsonl").write_text(stdout_txt + "\n---STDERR---\n" + stderr_txt, encoding="utf-8")

    combined_low = (stdout_txt + "\n" + stderr_txt).lower()
    if proc.returncode != 0 and any(k in combined_low for k in ["usage limit", "quota", "insufficient_quota", "billing", "out of credits", "rate limit reached"]):
        return {
            "code": job["code"],
            "stem": stem,
            "status": "quota_error",
            "returncode": proc.returncode,
            "elapsed_s": elapsed,
            "error_tail": (stdout_txt + "\n" + stderr_txt)[-600:],
        }

    thread_id = ""
    usage = {}
    for line in stdout_txt.splitlines():
        s = line.strip()
        if not s.startswith("{"):
            continue
        try:
            ev = json.loads(s)
            if ev.get("type") == "thread.started":
                thread_id = ev.get("thread_id", "")
            elif ev.get("type") == "turn.completed":
                usage = ev.get("usage", {})
        except Exception:
            pass

    png_found = ""
    if thread_id:
        cand_dir = CODEX_GEN_ROOT / thread_id
        if cand_dir.exists():
            pngs = sorted(cand_dir.glob("*.png"), key=lambda p: p.stat().st_mtime)
            if pngs:
                png_found = str(pngs[-1])

    if not png_found and CODEX_GEN_ROOT.exists():
        after_dirs = set(os.listdir(CODEX_GEN_ROOT)) - before_dirs
        for d in sorted(after_dirs):
            pngs = sorted((CODEX_GEN_ROOT / d).glob("*.png"), key=lambda p: p.stat().st_mtime)
            if pngs:
                png_found = str(pngs[-1])
                thread_id = thread_id or d
                break

    if not png_found:
        return {
            "code": job["code"],
            "stem": stem,
            "status": "missing_image",
            "returncode": proc.returncode,
            "thread_id": thread_id,
            "elapsed_s": elapsed,
            "tokens_in": usage.get("input_tokens", 0),
            "tokens_out": usage.get("output_tokens", 0),
            "tail": (stdout_txt + "\n" + stderr_txt)[-500:],
        }

    raw_dst = OUT_DIR / f"Codex原图_{stem}.png"
    std_dst = OUT_DIR / f"成图16x9_{stem}.png"
    shutil.copy2(png_found, raw_dst)
    metrics = normalize_to_16x9(raw_dst, std_dst)
    metrics.update({
        "code": job["code"],
        "stem": stem,
        "mode": job["mode"],
        "status": "ok",
        "returncode": proc.returncode,
        "thread_id": thread_id,
        "elapsed_s": elapsed,
        "tokens_in": usage.get("input_tokens", 0),
        "tokens_out": usage.get("output_tokens", 0),
        "raw_dst": str(raw_dst),
        "std_dst": str(std_dst),
    })
    return metrics


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--ids", default="", help="Comma-separated codes e.g. A01,A02")
    ap.add_argument("--reroll", action="store_true", help="Force re-generate specified --ids (archives v1)")
    ap.add_argument("--note", default="", help="Optional extra polish instruction when rerolling")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    history_fp = OUT_DIR / "summary_codex_runs.json"
    history = json.loads(history_fp.read_text(encoding="utf-8")) if history_fp.exists() else []
    prior_calls = len(history)

    selected = list(JOBS)
    if args.ids:
        want = {x.strip().upper() for x in args.ids.split(",") if x.strip()}
        selected = [j for j in selected if j["code"] in want]

    pending = []
    for j in selected:
        std_dst = OUT_DIR / f"成图16x9_{j['stem']}.png"
        if std_dst.exists() and std_dst.stat().st_size > 25_000 and not args.reroll:
            continue
        if args.reroll and std_dst.exists():
            arch_dir = OUT_DIR / "archive_v1"
            arch_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(std_dst, arch_dir / f"{std_dst.stem}_prev_{prior_calls}.png")
        pending.append(j)

    if prior_calls + len(pending) > MAX_APPROVED_CALLS:
        raise RuntimeError(
            f"Hard cap exceeded: prior_calls={prior_calls} + pending={len(pending)} > MAX_APPROVED_CALLS={MAX_APPROVED_CALLS}"
        )

    print(
        f"[Batch-A Codex] pending={len(pending)}/{len(selected)}, workers={args.workers}, calls_used={prior_calls}/{MAX_APPROVED_CALLS}",
        flush=True,
    )
    if not pending:
        print("[Batch-A Codex] All requested targets already exist. Nothing to call.", flush=True)
        return

    quota_hit = False
    done_cnt = 0
    with ThreadPoolExecutor(max_workers=max(1, min(args.workers, len(pending)))) as ex:
        fut_map = {ex.submit(run_one_job, j, args.note): j["code"] for j in pending}
        for fut in as_completed(fut_map):
            res = fut.result()
            done_cnt += 1
            with _LOCK:
                history.append(res)
                history_fp.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")
            print(
                f"[{done_cnt}/{len(pending)}] {res['code']} ({res['stem']}) -> {res['status']} "
                f"({res.get('elapsed_s')}s, green={res.get('green_pct')}%, lum={res.get('band_med_lum')})",
                flush=True,
            )
            if res["status"] == "quota_error":
                quota_hit = True
                print("[ALERT] Quota error detected! Cancelling remaining futures immediately.", flush=True)
                for f2 in fut_map:
                    f2.cancel()
                break

    ok_total = len(list(OUT_DIR.glob("成图16x9_A*.png")))
    print(
        f"[Batch-A Codex Done] ok_16x9={ok_total}/17, total_calls={len(history)}/{MAX_APPROVED_CALLS}, quota_hit={quota_hit}",
        flush=True,
    )


if __name__ == "__main__":
    main()
