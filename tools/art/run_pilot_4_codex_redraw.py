#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
执行用户已批准的「原帧 1:1 角色+高颜值特效一体重画」4 张样板分板（生图硬上限 5 张，含最多 1 张重抽备用）：
- 01_普攻1段_f0_f4 (1536x1024, 图1 + 图2 + 图3)
- 02_普攻1段_f5_f8_带刀光 (1536x1024, 图1 + 图2 + 图3)
- 03_普攻1段_f9_f12 (1536x1024, 图1 + 图2)
- 04_弹刀1_后8帧_f8_f15 (1024x1536, 图1 + 图2 + 图3)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(r"E:\00game\nightcrow-godot")
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\原帧一体重画_20261115"
REF_CHAR = ROOT / r"docs\视觉设计\角色动作\原帧重画_20261106\弹刀1_前8帧_带刀光\图2_造型参考_已认可的转向重画.png"
REF_VFX = WORK_ROOT / "图3_高颜值剑气画法参考板.png"
CODEX_IMG_ROOT = Path.home() / ".codex" / "generated_images"
NEUTRAL_CWD = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988\scratch\codex_img_cwd")

MAX_APPROVED_IMAGE_CALLS = 5

CODEX_CMD_BASE = [
    shutil.which("codex") or "codex.cmd",
    "exec",
    "-m", "gpt-6.1-terra",
    "-c", 'model_reasoning_effort="medium"',
    "-c", "mcp_servers.taptap-maker.enabled=false",
    "-s", "read-only",
    "--skip-git-repo-check",
]

JOBS = [
    {
        "id": "01_普攻1段_f0_f4",
        "size_desc": "横版 1536×1024",
        "use_vfx_ref": True,
    },
    {
        "id": "02_普攻1段_f5_f8_带刀光",
        "size_desc": "横版 1536×1024",
        "use_vfx_ref": True,
    },
    {
        "id": "03_普攻1段_f9_f12",
        "size_desc": "横版 1536×1024",
        "use_vfx_ref": False,
    },
    {
        "id": "04_弹刀1_后8帧_f8_f15",
        "size_desc": "竖版 1024×1536",
        "use_vfx_ref": True,
    },
]


def run_job(job: dict, force: bool = False) -> dict:
    jid = job["id"]
    sdir = WORK_ROOT / jid
    dst_png = sdir / "重画_原图.png"
    if not force and dst_png.exists() and dst_png.stat().st_size > 20_000:
        return {"id": jid, "status": "skipped_existing", "saved_png": str(dst_png), "tokens": 0}

    NEUTRAL_CWD.mkdir(parents=True, exist_ok=True)
    img1 = sdir / "输入_原帧.png"
    prompt_fp = sdir / "提示词.txt"
    if not img1.exists() or not prompt_fp.exists():
        raise FileNotFoundError(f"Missing input or prompt in {sdir}")

    images = [str(img1), str(REF_CHAR)]
    if job["use_vfx_ref"]:
        images.append(str(REF_VFX))
        ref_note = "三张附图按顺序依次是图1（原帧绿底黄框网格）、图2（角色与直剑设定参考）、图3（高颜值冷紫剑气画法参考）。"
    else:
        ref_note = "两张附图按顺序依次是图1（原帧绿底黄框网格）、图2（角色与直剑设定参考）。"

    cmd = list(CODEX_CMD_BASE) + ["-C", str(NEUTRAL_CWD)]
    for p in images:
        cmd.extend(["-i", p])
    cmd.append("-")

    wrapper = (
        f"用你的 image_gen 工具立即只生成 1 张{job['size_desc']}图，不要生成第二张，"
        f"不要运行任何命令、不要读或改任何文件。{ref_note}生成完直接回复“完成”即可。图片要求如下：\n\n"
    )
    prompt_text = wrapper + prompt_fp.read_text(encoding="utf-8")
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"

    t0 = time.time()
    proc = subprocess.run(
        cmd,
        input=prompt_text.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        timeout=540,
    )
    elapsed = round(time.time() - t0, 1)
    log_text = proc.stdout.decode("utf-8", errors="replace")
    (sdir / "codex_log.txt").write_text(log_text, encoding="utf-8")

    m_sess = re.search(r"session id:\s*([0-9a-fA-F\-]+)", log_text)
    m_tok = re.search(r"tokens used\s*([\d,]+)", log_text)
    session_id = m_sess.group(1) if m_sess else ""
    tokens_int = int(m_tok.group(1).replace(",", "")) if m_tok else 0

    lower_log = log_text.lower()
    if proc.returncode != 0 and any(k in lower_log for k in ["usage limit", "quota", "insufficient_quota", "billing", "out of credits"]):
        return {
            "id": jid,
            "status": "quota_error",
            "returncode": proc.returncode,
            "session_id": session_id,
            "tokens": tokens_int,
            "elapsed_s": elapsed,
            "error_tail": log_text[-600:],
        }

    saved_png = ""
    if session_id:
        cdir = CODEX_IMG_ROOT / session_id
        if cdir.exists():
            pngs = sorted(cdir.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
            if pngs:
                shutil.copy2(pngs[0], dst_png)
                saved_png = str(dst_png)

    return {
        "id": jid,
        "status": "ok" if saved_png else "missing_image",
        "returncode": proc.returncode,
        "session_id": session_id,
        "tokens": tokens_int,
        "elapsed_s": elapsed,
        "saved_png": saved_png,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default="", help="逗号分隔指定分板 ID，留空跑全部未生成分板")
    ap.add_argument("--force", action="store_true", help="对 --ids 指定分板强制重抽（计入 5 张生图硬上限）")
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()

    history_fp = WORK_ROOT / "summary_pilot_runs.json"
    history = json.loads(history_fp.read_text(encoding="utf-8")) if history_fp.exists() else []
    prior_img_calls = sum(1 for r in history if r.get("status") == "ok")

    jobs = list(JOBS)
    if args.ids:
        want = {x.strip() for x in args.ids.split(",") if x.strip()}
        jobs = [j for j in jobs if j["id"] in want]

    pending = []
    for j in jobs:
        dst = WORK_ROOT / j["id"] / "重画_原图.png"
        if args.force or not (dst.exists() and dst.stat().st_size > 20_000):
            pending.append(j)

    if prior_img_calls + len(pending) > MAX_APPROVED_IMAGE_CALLS:
        raise RuntimeError(
            f"Hard cap exceeded: prior_img_calls({prior_img_calls}) + pending({len(pending)}) > MAX_APPROVED_IMAGE_CALLS({MAX_APPROVED_IMAGE_CALLS})"
        )

    print(f"Running pilot Codex redraw: pending={len(pending)}, prior_img_calls={prior_img_calls}/{MAX_APPROVED_IMAGE_CALLS}", flush=True)
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(run_job, j, args.force): j for j in pending}
        for fut in as_completed(futs):
            res = fut.result()
            history.append(res)
            history_fp.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps(res, ensure_ascii=False), flush=True)

    total_imgs = sum(1 for r in history if r.get("status") == "ok")
    total_tokens = sum(int(r.get("tokens", 0)) for r in history)
    print(f"Done. total_imgs={total_imgs}/{MAX_APPROVED_IMAGE_CALLS}, total_tokens={total_tokens}", flush=True)


if __name__ == "__main__":
    main()
