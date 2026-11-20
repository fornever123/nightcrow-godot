#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
执行用户已批准（「批准2」）的主角全部 16 套战斗招式 R3 真刀光全量重做：
共 24 张 Codex (gpt-6.1-terra, medium) 1536×1024 图集，硬上限 <= 28 次调用（含最多 4 次瑕疵重抽余量）。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(r"E:\00game\nightcrow-godot")
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\R3全招式真刀光_20261115"
REF_R3 = WORK_ROOT / "ref_R3_master.png"
CODEX_IMG_ROOT = Path.home() / ".codex" / "generated_images"
NEUTRAL_CWD = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988\scratch\codex_img_cwd")

MAX_APPROVED_IMAGE_CALLS = 28

CODEX_CMD_BASE = [
    shutil.which("codex") or "codex.cmd",
    "exec",
    "-m", "gpt-6.1-terra",
    "-c", 'model_reasoning_effort="medium"',
    "-c", "mcp_servers.taptap-maker.enabled=false",
    "-s", "read-only",
    "--skip-git-repo-check",
]

LOCK = threading.Lock()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--only", nargs="*", default=None, help="例如 S01 S06")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    NEUTRAL_CWD.mkdir(parents=True, exist_ok=True)
    sheets_index = json.loads((WORK_ROOT / "sheets_index.json").read_text(encoding="utf-8"))
    history_fp = WORK_ROOT / "summary_r3_all_moves_runs.json"
    history: list[dict] = json.loads(history_fp.read_text(encoding="utf-8")) if history_fp.exists() else []
    calls_used = sum(1 for r in history if r.get("status") in ("ok", "missing_image", "reserved"))
    # 只统计真实已发生的 subprocess 调用次数
    calls_used = len(history)

    only_set = set(args.only) if args.only else None
    todo: list[dict] = []
    for item in sheets_index:
        sid = item["sheet_id"]
        if only_set and sid not in only_set:
            continue
        s_dir = WORK_ROOT / item["dir"]
        dst_png = s_dir / "生图_R3.png"
        if not args.force and dst_png.exists() and dst_png.stat().st_size > 20_000:
            print(f"[SKIP] {sid} already exists -> {dst_png.name}")
            continue
        todo.append(item)

    if not todo:
        print("Nothing to generate.")
        return

    if calls_used + len(todo) > MAX_APPROVED_IMAGE_CALLS:
        raise RuntimeError(
            f"Hard cap exceeded: calls_used={calls_used} + todo={len(todo)} > MAX={MAX_APPROVED_IMAGE_CALLS}"
        )

    print(
        f"Launching {len(todo)} R3 sheets with workers={args.workers} "
        f"(prior calls={calls_used}/{MAX_APPROVED_IMAGE_CALLS})...",
        flush=True,
    )

    reserved_counter = [calls_used]

    def run_one(item: dict) -> dict:
        sid = item["sheet_id"]
        s_dir = WORK_ROOT / item["dir"]
        img1_fp = s_dir / "输入_导引底板.png"
        prompt_fp = s_dir / "提示词.txt"
        dst_png = s_dir / "生图_R3.png"
        log_fp = s_dir / "codex_log.txt"

        with LOCK:
            if reserved_counter[0] + 1 > MAX_APPROVED_IMAGE_CALLS:
                raise RuntimeError(f"Hard cap reached before {sid}: {reserved_counter[0]}/{MAX_APPROVED_IMAGE_CALLS}")
            reserved_counter[0] += 1
            call_no = reserved_counter[0]

        wrapper = (
            "用你的 image_gen 工具立即只生成 1 张横版 1536×1024 图，不要生成第二张，"
            "不要运行任何命令、不要读或改任何文件。两张附图按顺序依次是图1（深暗灰底 #141620 黄框人物与刀光轨迹导引图）、"
            "图2（已定稿的 R3 满弓月华流光斩唯一角色与刀光质感母本）。生成完直接回复“完成”即可。图片要求如下：\n\n"
        )
        prompt_text = wrapper + prompt_fp.read_text(encoding="utf-8")
        cmd = list(CODEX_CMD_BASE) + ["-C", str(NEUTRAL_CWD), "-i", str(img1_fp), "-i", str(REF_R3), "-"]

        env = os.environ.copy()
        env["PYTHONIOENCODING"] = "utf-8"

        print(f"[START {call_no:02d}/{MAX_APPROVED_IMAGE_CALLS}] {sid} ({item['clip']})...", flush=True)
        t0 = time.time()
        proc = subprocess.run(
            cmd,
            input=prompt_text.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
            timeout=600,
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
            "call_no": call_no,
            "sheet_id": sid,
            "clip": item["clip"],
            "status": "ok" if saved_png else "missing_image",
            "returncode": proc.returncode,
            "session_id": session_id,
            "tokens": tokens_int,
            "elapsed_s": elapsed,
            "saved_png": saved_png,
        }
        with LOCK:
            history.append(res)
            history_fp.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")
        print(
            f"[DONE  {call_no:02d}/{MAX_APPROVED_IMAGE_CALLS}] {sid} status={res['status']} "
            f"tokens={tokens_int:,} elapsed={elapsed}s",
            flush=True,
        )
        return res

    ok_cnt = 0
    fail_list = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(run_one, it) for it in todo]
        for f in as_completed(futs):
            r = f.result()
            if r["status"] == "ok":
                ok_cnt += 1
            else:
                fail_list.append(r["sheet_id"])

    total_tokens = sum(int(x.get("tokens", 0)) for x in history)
    print(
        f"Batch finished: ok={ok_cnt}/{len(todo)}, fails={fail_list}, "
        f"total_calls_used={len(history)}/{MAX_APPROVED_IMAGE_CALLS}, total_tokens={total_tokens:,}",
        flush=True,
    )


if __name__ == "__main__":
    main()
