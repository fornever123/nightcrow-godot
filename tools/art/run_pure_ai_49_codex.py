#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
执行用户已批准的 49 张（上限 54 张）Codex (gpt-6.1-terra, medium) 100% 纯 AI 角色动作与狂野剑戟特效生图任务：
- 支持按批次/全量并发执行（默认并发度 5，平稳高效不挤占带宽）
- 幂等断点续跑：已成功产出 生成_<ID>.png 的分板自动跳过
- 严格硬护栏：累计调用次数绝不超过批准上限 54 次；遇额度耗尽错误立即熔断停止汇报
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
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\全动作纯AI重塑_20261114"
OUT_DIR = WORK_ROOT / "codex_out"
CODEX_IMG_ROOT = Path.home() / ".codex" / "generated_images"

MAX_APPROVED_CALLS = 54

CODEX_CMD_BASE = [
    shutil.which("codex") or "codex.cmd",
    "exec",
    "-m", "gpt-6.1-terra",
    "-c", 'model_reasoning_effort="medium"',
    "-c", "mcp_servers.taptap-maker.enabled=false",
    "-s", "read-only",
    "--skip-git-repo-check",
    "-C", str(ROOT),
]


def run_single_job(job: dict) -> dict:
    jid = job["id"]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dst_png = OUT_DIR / f"生成_{jid}.png"
    if dst_png.exists() and dst_png.stat().st_size > 20_000:
        return {"id": jid, "status": "skipped_existing", "saved_png": str(dst_png), "tokens": 0}

    cmd = list(CODEX_CMD_BASE)
    for img_p in job["images"]:
        cmd.extend(["-i", img_p])
    cmd.append("-")

    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"

    t0 = time.time()
    proc = subprocess.run(
        cmd,
        input=job["prompt"].encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        timeout=540,
    )
    elapsed = round(time.time() - t0, 1)
    log_text = proc.stdout.decode("utf-8", errors="replace")
    (OUT_DIR / f"codex_log_{jid}.txt").write_text(log_text, encoding="utf-8")

    m_sess = re.search(r"session id:\s*([0-9a-fA-F\-]+)", log_text)
    m_tok = re.search(r"tokens used\s*([\d,]+)", log_text)
    session_id = m_sess.group(1) if m_sess else ""
    tokens_int = int(m_tok.group(1).replace(",", "")) if m_tok else 0

    # 检测额度/配额耗尽错误
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
        sdir = CODEX_IMG_ROOT / session_id
        if sdir.exists():
            pngs = sorted(sdir.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
            if pngs:
                shutil.copy2(pngs[0], dst_png)
                saved_png = str(dst_png)

    status = "ok" if saved_png else "missing_image"
    return {
        "id": jid,
        "status": status,
        "returncode": proc.returncode,
        "session_id": session_id,
        "tokens": tokens_int,
        "elapsed_s": elapsed,
        "saved_png": saved_png,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("--ids", default="", help="可选：逗号分隔的指定板号，如 V01,S05；留空跑全部未完成分板")
    args = ap.parse_args()

    jobs = json.loads((WORK_ROOT / "prompts_49.json").read_text(encoding="utf-8"))
    if args.ids:
        want = {x.strip() for x in args.ids.split(",") if x.strip()}
        jobs = [j for j in jobs if j["id"] in want]

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    history_fp = OUT_DIR / "summary_codex_runs.json"
    history = json.loads(history_fp.read_text(encoding="utf-8")) if history_fp.exists() else []
    prior_calls = sum(1 for r in history if r.get("status") not in ("skipped_existing",))

    pending = [j for j in jobs if not ((OUT_DIR / f"生成_{j['id']}.png").exists() and (OUT_DIR / f"生成_{j['id']}.png").stat().st_size > 20_000)]
    if prior_calls + len(pending) > MAX_APPROVED_CALLS:
        raise RuntimeError(f"Guardrail triggered: prior_calls({prior_calls}) + pending({len(pending)}) > MAX_APPROVED_CALLS({MAX_APPROVED_CALLS})")

    print(f"Starting Codex batch: pending={len(pending)}/{len(jobs)}, workers={args.workers}, prior_calls={prior_calls}/{MAX_APPROVED_CALLS}", flush=True)
    quota_hit = False
    done_cnt = 0

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        fut_map = {ex.submit(run_single_job, j): j["id"] for j in pending}
        for fut in as_completed(fut_map):
            res = fut.result()
            done_cnt += 1
            history.append(res)
            history_fp.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"[{done_cnt}/{len(pending)}] {res['id']} -> {res['status']} (tokens={res.get('tokens')}, {res.get('elapsed_s')}s) {res.get('saved_png','')}", flush=True)
            if res["status"] == "quota_error":
                quota_hit = True
                print("QUOTA ERROR DETECTED! Cancelling remaining queued futures...", flush=True)
                for f2 in fut_map:
                    f2.cancel()
                break

    total_tok = sum(r.get("tokens", 0) for r in history)
    ok_files = len(list(OUT_DIR.glob("生成_*.png")))
    print(f"Batch finished: ok_pngs={ok_files}/49, total_calls={len([r for r in history if r.get('status')!='skipped_existing'])}/{MAX_APPROVED_CALLS}, cumulative_tokens={total_tok:,}, quota_hit={quota_hit}", flush=True)


if __name__ == "__main__":
    main()
