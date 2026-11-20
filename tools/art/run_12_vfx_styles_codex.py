#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
执行用户已批准的「12 种不同高帅度特效风格 1:1 同姿样板横评」3 张 Codex (gpt-6.1-terra, medium) 生图任务
（硬上限 4 次调用，含最多 1 次重抽备用）：
- 板A (D01–D04): 次元断空空间裂口 / 扳机社折角紫雷 / 刹那断晷碎时星轨 / 错位断层切帧
- 板B (D05–D08): 九日狂墨夹紫电 / 夜鸦千本刃羽流 / 不死妖炎鬼火涡流 / 极简居合双弦一线天
- 板C (D09–D12): 双层音爆激波环 / 千刃残像扇面连斩 / 黑曜棱镜哥特琉璃 / 断晓蚀日外黑内白反转斩
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
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\特效样板12方向_20261115"
IMG1 = WORK_ROOT / "输入_原帧_f05四格同姿.png"
REF_CHAR = ROOT / r"docs\视觉设计\角色动作\原帧重画_20261106\弹刀1_前8帧_带刀光\图2_造型参考_已认可的转向重画.png"
CODEX_IMG_ROOT = Path.home() / ".codex" / "generated_images"
NEUTRAL_CWD = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988\scratch\codex_img_cwd")

MAX_APPROVED_IMAGE_CALLS = 4

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
    {"id": "板A_D01至D04", "prompt_file": "提示词_板A_D01至D04.txt"},
    {"id": "板B_D05至D08", "prompt_file": "提示词_板B_D05至D08.txt"},
    {"id": "板C_D09至D12", "prompt_file": "提示词_板C_D09至D12.txt"},
]


def run_job(job: dict, force: bool = False) -> dict:
    jid = job["id"]
    dst_png = WORK_ROOT / f"生图_{jid}.png"
    if not force and dst_png.exists() and dst_png.stat().st_size > 20_000:
        return {"id": jid, "status": "skipped_existing", "saved_png": str(dst_png), "tokens": 0}

    NEUTRAL_CWD.mkdir(parents=True, exist_ok=True)
    prompt_fp = WORK_ROOT / job["prompt_file"]
    cmd = list(CODEX_CMD_BASE) + ["-C", str(NEUTRAL_CWD), "-i", str(IMG1), "-i", str(REF_CHAR), "-"]

    wrapper = (
        "用你的 image_gen 工具立即只生成 1 张横版 1536×1024 图，不要生成第二张，"
        "不要运行任何命令、不要读或改任何文件。两张附图按顺序依次是图1（原帧绿底黄框四格模板）、图2（角色与直剑设定参考）。"
        "生成完直接回复“完成”即可。图片要求如下：\n\n"
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
    (WORK_ROOT / f"codex_log_{jid}.txt").write_text(log_text, encoding="utf-8")

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
    ap.add_argument("--ids", default="")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    history_fp = WORK_ROOT / "summary_12styles_runs.json"
    history = json.loads(history_fp.read_text(encoding="utf-8")) if history_fp.exists() else []
    prior_imgs = sum(1 for r in history if r.get("status") == "ok")

    jobs = list(JOBS)
    if args.ids:
        want = {x.strip() for x in args.ids.split(",") if x.strip()}
        jobs = [j for j in jobs if j["id"] in want]

    pending = [
        j for j in jobs
        if args.force or not ((WORK_ROOT / f"生图_{j['id']}.png").exists() and (WORK_ROOT / f"生图_{j['id']}.png").stat().st_size > 20_000)
    ]
    if prior_imgs + len(pending) > MAX_APPROVED_IMAGE_CALLS:
        raise RuntimeError(f"Hard cap exceeded: {prior_imgs} + {len(pending)} > {MAX_APPROVED_IMAGE_CALLS}")

    print(f"Running 12-style VFX sheets: pending={len(pending)}, prior={prior_imgs}/{MAX_APPROVED_IMAGE_CALLS}", flush=True)
    with ThreadPoolExecutor(max_workers=3) as ex:
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
