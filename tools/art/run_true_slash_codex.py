#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
执行用户已批准的「真·刀光（人剑光一体·扇形扫掠半透明残影）」1 张 Codex (gpt-6.1-terra, medium) 生图任务
（硬上限 <= 2 次调用，含最多 1 次备用重抽）。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(r"E:\00game\nightcrow-godot")
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\真刀光样板_20261115"
IMG1 = WORK_ROOT / "输入_真刀光底板_f05四格.png"
REF_CHAR = ROOT / r"docs\视觉设计\角色动作\原帧重画_20261106\弹刀1_前8帧_带刀光\图2_造型参考_已认可的转向重画.png"
CODEX_IMG_ROOT = Path.home() / ".codex" / "generated_images"
NEUTRAL_CWD = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988\scratch\codex_img_cwd")

MAX_APPROVED_IMAGE_CALLS = 2

CODEX_CMD_BASE = [
    shutil.which("codex") or "codex.cmd",
    "exec",
    "-m", "gpt-6.1-terra",
    "-c", 'model_reasoning_effort="medium"',
    "-c", "mcp_servers.taptap-maker.enabled=false",
    "-s", "read-only",
    "--skip-git-repo-check",
]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--v2", action="store_true")
    args = ap.parse_args()

    history_fp = WORK_ROOT / "summary_true_slash_runs.json"
    history = json.loads(history_fp.read_text(encoding="utf-8")) if history_fp.exists() else []
    prior_imgs = sum(1 for r in history if r.get("status") == "ok")

    if args.v2:
        img1_fp = WORK_ROOT / "输入_真刀光底板_v2.png"
        prompt_fp = WORK_ROOT / "提示词_真刀光_v2.txt"
        dst_png = WORK_ROOT / "生图_真刀光_v2_R1至R4.png"
        log_fp = WORK_ROOT / "codex_log_v2_R1至R4.txt"
        run_id = "真刀光_v2_R1至R4"
    else:
        img1_fp = IMG1
        prompt_fp = WORK_ROOT / "提示词_真刀光_S1至S4.txt"
        dst_png = WORK_ROOT / "生图_真刀光_S1至S4.png"
        log_fp = WORK_ROOT / "codex_log_S1至S4.txt"
        run_id = "真刀光_S1至S4"

    if not args.force and dst_png.exists() and dst_png.stat().st_size > 20_000:
        print(f"Already exists: {dst_png}")
        return

    if prior_imgs + 1 > MAX_APPROVED_IMAGE_CALLS:
        raise RuntimeError(f"Hard cap exceeded: {prior_imgs} + 1 > {MAX_APPROVED_IMAGE_CALLS}")

    NEUTRAL_CWD.mkdir(parents=True, exist_ok=True)
    cmd = list(CODEX_CMD_BASE) + ["-C", str(NEUTRAL_CWD), "-i", str(img1_fp), "-i", str(REF_CHAR), "-"]

    wrapper = (
        "用你的 image_gen 工具立即只生成 1 张横版 1536×1024 图，不要生成第二张，"
        "不要运行任何命令、不要读或改任何文件。两张附图按顺序依次是图1（深暗灰底黄框四格人物与刀光轨迹导引图）、图2（角色与直剑设定参考）。"
        "生成完直接回复“完成”即可。图片要求如下：\n\n"
    )
    prompt_text = wrapper + prompt_fp.read_text(encoding="utf-8")
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"

    print(f"Running Codex image_gen [{run_id}] (prior={prior_imgs}/{MAX_APPROVED_IMAGE_CALLS})...", flush=True)
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
    log_fp.write_text(log_text, encoding="utf-8")

    m_sess = re.search(r"session id:\s*([0-9a-fA-F\-]+)", log_text)
    m_tok = re.search(r"tokens used\s*([\d,]+)", log_text)
    session_id = m_sess.group(1) if m_sess else ""
    tokens_int = int(m_tok.group(1).replace(",", "")) if m_tok else 0

    saved_png = ""
    if session_id:
        cdir = CODEX_IMG_ROOT / session_id
        if cdir.exists():
            pngs = sorted(cdir.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
            if pngs:
                shutil.copy2(pngs[0], dst_png)
                saved_png = str(dst_png)

    res = {
        "id": run_id,
        "status": "ok" if saved_png else "missing_image",
        "returncode": proc.returncode,
        "session_id": session_id,
        "tokens": tokens_int,
        "elapsed_s": elapsed,
        "saved_png": saved_png,
    }
    history.append(res)
    history_fp.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(res, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
