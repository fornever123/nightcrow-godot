#!/usr/bin/env python3
"""
《断晓》Google Drive 云盘持久化 + Colab GPU 纯 AI 音效生成工作台 (colab_drive_sfx.py)

架构（「一次装进云盘，每次用时从云盘秒导进 Colab」）：
  1. 云盘持久化目录：Google Drive `Nightcrow_AI_SFX/` (Folder ID 自动定位或创建)
     采用 3 个分卷归档高速直传（规避 Google Drive 小文件每秒创建限频，千兆内网 15 秒级秒拉）：
     - `wheels_repos.tar`    : 全部 Python 离线依赖轮子 + MMAudio / TangoFlux 源码库 + torch_constraints.txt
     - `mmaudio_weights.tar` : mmaudio_large_44k_v2.pth + v1-44.pth + synchformer_state_dict.pth + best_netG.pt
     - `hf_cache.tar`        : TangoFlux + flan-t5-large + OpenCLIP (DFN5B-CLIP-ViT-H-14-384) + torch_cache 完整预热缓存
     - `READY_MANIFEST.json` : 离线包版本与校验清单

  2. 子命令：
     - `status`     : 只读查询当前 Colab 账号余额、活跃实例与计费速率（0 消耗）
     - `stop`       : 强制释放全部云端 GPU 实例并核验 `burn_rate_hourly == 0.0`
     - `pack-drive` : 唤醒云端实例 -> 下载全部轮子与双模型权重并预热校验 -> 打包存入 Google 云盘 -> 自动关机归零
     - `generate`   : 唤醒云端实例 -> 从 Google 云盘秒拉离线包并离线安装 -> 进程内常驻运行 TangoFlux + MMAudio 生成 44.1kHz WAV
                      与动作同步预览 MP4 -> 回传本地并生成试听对比网页 `index.html` -> `finally:` 自动关机归零
"""
from __future__ import annotations

import argparse
import html
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from pathlib import Path

for _sn in ("stdout", "stderr"):
    _st = getattr(sys, _sn, None)
    if _st is not None and hasattr(_st, "reconfigure"):
        try:
            _st.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

EASYCOLAB_ROOT = os.environ.get("EASYCOLAB_ROOT", r"e:\.0ai视频\EasyColab")
INTERNAL_DIR = os.path.join(EASYCOLAB_ROOT, "_internal")
SITE_PKGS = os.path.join(INTERNAL_DIR, "site-packages")
for _p in (INTERNAL_DIR, SITE_PKGS):
    if os.path.isdir(_p) and _p not in sys.path:
        sys.path.insert(0, _p)

import colab_bridge  # type: ignore  # noqa: E402
from colab_cli.common import state  # type: ignore  # noqa: E402
from colab_cli.contents import ContentsClient  # type: ignore  # noqa: E402
from colab_cli.runtime import ColabRuntime  # type: ignore  # noqa: E402

GDRIVE_TOKEN_PATH = os.path.expanduser(r"~\.gemini\antigravity\plugin_data\gdrive\token.json")
GDRIVE_CLI_CANDIDATES = [
    os.path.expanduser(r"~\.gemini\antigravity\bin\gdrive.cmd"),
    "gdrive",
]
DEFAULT_DRIVE_FOLDER_NAME = "Nightcrow_AI_SFX"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def _find_gdrive_cli() -> str:
    for c in GDRIVE_CLI_CANDIDATES:
        if os.path.isfile(c):
            return c
        w = shutil.which(c)
        if w:
            return w
    raise RuntimeError("未找到 gdrive CLI，请先初始化 gdrive 技能脚本。")


def ensure_gdrive_folder_and_rclone_conf(folder_name: str = DEFAULT_DRIVE_FOLDER_NAME) -> tuple[str, str]:
    """
    1) 调用本地 `gdrive auth status` 自动刷新 OAuth access_token；
    2) 查找或创建 Google Drive 根目录下的 `Nightcrow_AI_SFX` 文件夹，拿到 Folder ID；
    3) 生成绑定该 `root_folder_id` 与官方 Drive 配额项目的 rclone 配置内容（仅上传至当前隔离 Colab 实例内存盘）。
    """
    gdrive_bin = _find_gdrive_cli()
    subprocess.run([gdrive_bin, "auth", "status"], check=True, stdout=subprocess.DEVNULL)

    search_out = subprocess.check_output(
        [gdrive_bin, "readonly", "search", "--name-exact", folder_name, "--json"],
        text=True,
        encoding="utf-8",
    )
    items = json.loads(search_out or "[]")
    folder_id = ""
    for it in items:
        mime = it.get("mimeType", "")
        if mime == "application/vnd.google-apps.folder" and not it.get("trashed", False):
            folder_id = it.get("id", "")
            break

    if not folder_id:
        mk_out = subprocess.check_output(
            [gdrive_bin, "mutate", "mkdir", folder_name],
            text=True,
            encoding="utf-8",
        )
        # 格式形如: Created folder: Nightcrow_AI_SFX (ID: 1Z14c1oN9Ds5kait4BFXpLk8RZRH2YQWQ)
        if "ID:" in mk_out:
            folder_id = mk_out.split("ID:", 1)[1].strip().rstrip(")").strip()
    if not folder_id:
        raise RuntimeError(f"无法在 Google Drive 中定位或创建目录 {folder_name}")

    if not os.path.isfile(GDRIVE_TOKEN_PATH):
        raise RuntimeError(f"未找到 gdrive OAuth 凭据文件: {GDRIVE_TOKEN_PATH}")

    raw = json.loads(Path(GDRIVE_TOKEN_PATH).read_text(encoding="utf-8"))
    tok_inner = raw.get("token") or {}
    if not isinstance(tok_inner, dict) or not tok_inner.get("access_token"):
        raise RuntimeError("gdrive token.json 结构异常或缺少 access_token，请重新执行 gdrive auth login")

    rclone_tok = {
        "access_token": tok_inner["access_token"],
        "token_type": tok_inner.get("token_type", "Bearer"),
        "refresh_token": tok_inner.get("refresh_token", ""),
    }
    if tok_inner.get("expiry"):
        rclone_tok["expiry"] = tok_inner["expiry"]

    conf_lines = [
        "[nc_gdrive]",
        "type = drive",
        f"client_id = {raw.get('client_id', '')}",
        f"client_secret = {raw.get('client_secret', '')}",
        "scope = drive",
        f"root_folder_id = {folder_id}",
        f"token = {json.dumps(rclone_tok, separators=(',', ':'))}",
        "",
    ]
    return folder_id, "\n".join(conf_lines)


def allocate_colab_vm(gpu_type: str, rclone_conf: str):
    if not colab_bridge._has_valid_token():
        raise RuntimeError("尚未登录 EasyColab Google 账号，请先检查 EasyColab 授权状态。")

    local_sessions, _ = colab_bridge._safe_sync_sessions()
    target = local_sessions.get("nightcrow_sfx") or local_sessions.get("easycolab")
    req_acc = colab_bridge._resolve_gpu_accel(gpu_type)

    if target is not None:
        cur_acc = (target.accelerator or "").strip().upper()
        if cur_acc != req_acc.value.upper() or not colab_bridge._wait_for_runtime_ready(target, timeout_s=15):
            try:
                state.client.unassign(target.endpoint)
            except Exception:
                pass
            state.prune_session(target.name)
            target = None

    if target is None:
        target = colab_bridge._allocate_fresh_session("nightcrow_sfx", gpu_type)
        colab_bridge._wait_for_runtime_ready(target, timeout_s=60)

    contents = ContentsClient(target)
    fd, tmp_rc = tempfile.mkstemp(prefix="nc_rc_", suffix=".conf")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as wf:
            wf.write(rclone_conf)
        contents.upload(tmp_rc, "content/.nc_rclone.conf")
    finally:
        if os.path.exists(tmp_rc):
            os.remove(tmp_rc)

    return target, contents


def refresh_target_proxy(target) -> None:
    try:
        _, assignments = colab_bridge._safe_sync_sessions()
        for a in assignments:
            if a.endpoint == target.endpoint:
                info_proxy = a.runtime_proxy_info
                target.token = info_proxy.token
                target.url = info_proxy.url
                target.token_expires_at = info_proxy.expires_at()
                state.store.add(target)
                break
    except Exception:
        pass


def exec_on_colab(target, code: str, timeout: int = 1800) -> str:
    refresh_target_proxy(target)

    def _on_kid(kid):
        target.kernel_id = kid
        state.store.add(target)

    def _on_sid(sid):
        target.session_id = sid
        state.store.add(target)

    outputs = None
    last_exc = None
    for attempt in range(3):
        refresh_target_proxy(target)
        # 始终复用已启动的 kernel_id（除非第 3 次兜底），防止断线重连拉起第二个内核双倍占满显存！
        use_saved = attempt < 2
        rt = ColabRuntime(
            target.url,
            target.token,
            session_name=target.name,
            history=state.history,
            kernel_id=target.kernel_id if use_saved else None,
            session_id=target.session_id if use_saved else None,
            on_kernel_started=_on_kid,
            on_session_started=_on_sid,
        )
        try:
            outputs = rt.execute_code(code, allow_stdin=False, timeout=timeout)
            last_exc = None
            break
        except Exception as exc:
            last_exc = exc
            time.sleep(2.0)
        finally:
            try:
                rt.stop(shutdown_kernel=False)
            except Exception:
                pass

    if last_exc is not None or outputs is None:
        raise RuntimeError(f"Colab WebSocket 执行中断: {last_exc}")

    full_text: list[str] = []
    for out in outputs:
        if "text" in out:
            txt = out["text"]
            for line in txt.splitlines():
                print(f"  [Colab] {line}", flush=True)
            full_text.append(txt)
        elif out.get("output_type") == "error":
            tb = "\n".join(out.get("traceback") or [])
            err = f"{out.get('ename', 'Error')}: {out.get('evalue', '')}\n{tb}"
            raise RuntimeError(f"Colab 远端执行报错:\n{err}")
    return "\n".join(full_text)


def start_keepalive(target, stop_evt: threading.Event) -> threading.Thread:
    import requests as _req

    def _loop():
        while not stop_evt.wait(45.0):
            try:
                refresh_target_proxy(target)
                if target.url and target.token:
                    base_url = target.url.rstrip("/")
                    headers = {
                        "Accept": "application/json",
                        "X-Colab-Client-Agent": "colab-cli",
                        "X-Colab-Runtime-Proxy-Token": target.token,
                        "Authorization": f"Bearer {target.token}",
                    }
                    _req.get(
                        f"{base_url}/api/kernels",
                        headers=headers,
                        params={"authuser": "0", "colab-runtime-proxy-token": target.token},
                        timeout=10,
                    )
            except Exception:
                pass

    t = threading.Thread(target=_loop, daemon=True)
    t.start()
    return t


REMOTE_RCLONE_BOOT = r"""
import os, shutil, subprocess

rc_src = "/content/.nc_rclone.conf"
if os.path.exists(rc_src):
    rc_dir = os.path.expanduser("~/.config/rclone")
    os.makedirs(rc_dir, mode=0o700, exist_ok=True)
    rc_dst = os.path.join(rc_dir, "rclone.conf")
    shutil.move(rc_src, rc_dst)
    os.chmod(rc_dst, 0o600)

if not shutil.which("rclone"):
    subprocess.run(
        ["bash", "-lc", "curl -fsSL https://downloads.rclone.org/rclone-current-linux-amd64.zip -o /tmp/rclone.zip && unzip -q -o /tmp/rclone.zip -d /tmp && cp /tmp/rclone-*-linux-amd64/rclone /usr/local/bin/rclone && chmod +x /usr/local/bin/rclone && rm -rf /tmp/rclone*"],
        check=True,
    )
out = subprocess.check_output(["rclone", "lsf", "nc_gdrive:"], text=True)
print("RCLONE_READY files=" + str(len(out.splitlines())), flush=True)
"""


REMOTE_PACK_DRIVE_CODE = r"""
import gc, json, os, shutil, subprocess, sys, time
from pathlib import Path

PACK = "/content/Nightcrow_AI_SFX"
WHEELS = os.path.join(PACK, "wheels")
REPOS = os.path.join(PACK, "repos")
HF_CACHE = os.path.join(PACK, "hf_cache")
TORCH_CACHE = os.path.join(PACK, "torch_cache")
MM_W = os.path.join(PACK, "mmaudio_weights")

for d in (WHEELS, REPOS, HF_CACHE, TORCH_CACHE, MM_W):
    os.makedirs(d, exist_ok=True)

os.environ["HF_HOME"] = HF_CACHE
os.environ["TORCH_HOME"] = TORCH_CACHE
os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"

print("1/6 正在克隆 MMAudio 与 TangoFlux 官方源码仓库...", flush=True)
if not os.path.exists(os.path.join(REPOS, "MMAudio")):
    subprocess.run(["git", "clone", "--depth", "1", "https://github.com/hkchengrex/MMAudio.git", os.path.join(REPOS, "MMAudio")], check=True)
if not os.path.exists(os.path.join(REPOS, "TangoFlux")):
    subprocess.run(["git", "clone", "--depth", "1", "https://github.com/declare-lab/TangoFlux.git", os.path.join(REPOS, "TangoFlux")], check=True)

print("2/6 正在下载并锁定 Colab 原生 PyTorch ABI 的全部离线依赖轮子...", flush=True)
import numpy as np
import scipy
import torch, torchvision, torchaudio

constraints_txt = os.path.join(PACK, "torch_constraints.txt")
with open(constraints_txt, "w", encoding="utf-8") as cf:
    cf.write(f"torch=={torch.__version__.split('+')[0]}\n")
    cf.write(f"torchvision=={torchvision.__version__.split('+')[0]}\n")
    cf.write(f"torchaudio=={torchaudio.__version__.split('+')[0]}\n")
    cf.write(f"numpy=={np.__version__}\n")
    cf.write(f"scipy=={scipy.__version__}\n")

base_pkgs = [
    "huggingface_hub>=0.26.0",
    "hf_transfer",
    "safetensors",
    "accelerate>=0.34.2",
    "diffusers>=0.30.0",
    "transformers>=4.44.0,<5.0.0",
    "datasets>=2.21.0",
    "einops>=0.6",
    "open_clip_torch>=2.29.0",
    "torchdiffeq>=0.2.5",
    "torchlibrosa",
    "tensordict>=0.6.1",
    "colorlog",
    "hydra-core>=1.3.2",
    "hydra_colorlog",
    "omegaconf",
    "nitrous-ema",
    "av>=14.0.0",
    "timm>=1.0.12",
    "soundfile",
    "librosa>=0.8.1",
    "sentencepiece",
    "protobuf",
    "pyyaml",
    "python-dotenv",
    "gitpython>=3.1",
]
with open(os.path.join(PACK, "offline_reqs.txt"), "w", encoding="utf-8") as rf:
    rf.write("\n".join(base_pkgs) + "\n")

subprocess.run(
    [sys.executable, "-m", "pip", "download", "-q", "-d", WHEELS, "-c", constraints_txt, "-r", os.path.join(PACK, "offline_reqs.txt")],
    check=True,
)
# 剔除 Colab 已自带的巨型底层轮子（保持 wheels 包在 200MB 级别秒装且绝不破坏 CUDA ABI）
for fn in list(os.listdir(WHEELS)):
    low = fn.lower()
    if low.startswith(("torch-", "torchvision-", "torchaudio-", "nvidia_", "triton-", "numpy-", "scipy-")):
        os.remove(os.path.join(WHEELS, fn))

subprocess.run(
    [sys.executable, "-m", "pip", "install", "-q", "--no-index", "--find-links", WHEELS, "-c", constraints_txt, "-r", os.path.join(PACK, "offline_reqs.txt")],
    check=True,
)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-deps", "-e", os.path.join(REPOS, "MMAudio")], check=True)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-deps", "-e", os.path.join(REPOS, "TangoFlux")], check=True)

print("3/6 正在高速拉取 MMAudio Large 44.1kHz v2 权重并预热 OpenCLIP / Synchformer 缓存...", flush=True)
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="hkchengrex/MMAudio",
    local_dir=MM_W,
    allow_patterns=[
        "weights/mmaudio_large_44k_v2.pth",
        "ext_weights/v1-44.pth",
        "ext_weights/synchformer_state_dict.pth",
        "ext_weights/best_netG.pt",
    ],
)
for sub in ("weights", "ext_weights"):
    src = os.path.join(MM_W, sub)
    dst = os.path.join(REPOS, "MMAudio", sub)
    if os.path.exists(src) and not os.path.exists(dst):
        os.symlink(src, dst)

# 实例化一次 FeaturesUtils 与 MMAudio 确保所有子权重进入 HF_CACHE / TORCH_CACHE
if os.path.join(REPOS, "MMAudio") not in sys.path:
    sys.path.insert(0, os.path.join(REPOS, "MMAudio"))
from mmaudio.eval_utils import all_model_cfg
from mmaudio.model.networks import get_my_mmaudio
from mmaudio.model.utils.features_utils import FeaturesUtils

_mcfg = all_model_cfg["large_44k_v2"]
_fu = FeaturesUtils(
    tod_vae_ckpt=str( Path(MM_W) / "ext_weights/v1-44.pth" ),
    synchformer_ckpt=str( Path(MM_W) / "ext_weights/synchformer_state_dict.pth" ),
    enable_conditions=True,
    mode="44k",
    bigvgan_vocoder_ckpt=None,
    need_vae_encoder=False,
)
_net = get_my_mmaudio(_mcfg.model_name)
del _fu, _net
gc.collect()
torch.cuda.empty_cache()

print("4/6 正在高速拉取 TangoFlux 44.1kHz 立体声权重与 flan-t5-large 编码器并预热校验...", flush=True)
if os.path.join(REPOS, "TangoFlux") not in sys.path:
    sys.path.insert(0, os.path.join(REPOS, "TangoFlux"))
snapshot_download(repo_id="declare-lab/TangoFlux")
snapshot_download(
    repo_id="google/flan-t5-large",
    ignore_patterns=["*.msgpack", "*.h5", "pytorch_model.bin", "*.ot"],
)
from tangoflux import TangoFluxInference
_tf = TangoFluxInference(name="declare-lab/TangoFlux")
del _tf
gc.collect()
torch.cuda.empty_cache()

manifest = {
    "packed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "models": [
        "hkchengrex/MMAudio (large_44k_v2, 44.1kHz video+text foley)",
        "declare-lab/TangoFlux (44.1kHz stereo flow-matching text-to-sfx)",
    ],
    "colab_torch": torch.__version__,
    "archives": ["wheels_repos.tar", "mmaudio_weights.tar", "hf_cache.tar"],
}
with open(os.path.join(PACK, "READY_MANIFEST.json"), "w", encoding="utf-8") as mf:
    json.dump(manifest, mf, indent=2, ensure_ascii=False)

print("5/6 正在将离线包封存为 3 个零损耗高速分卷归档 (.tar)...", flush=True)
STAGING = "/content/nc_drive_staging"
if os.path.exists(STAGING):
    shutil.rmtree(STAGING)
os.makedirs(STAGING, exist_ok=True)
shutil.copy2(os.path.join(PACK, "READY_MANIFEST.json"), os.path.join(STAGING, "READY_MANIFEST.json"))

subprocess.run(["tar", "-cf", os.path.join(STAGING, "wheels_repos.tar"), "-C", PACK, "wheels", "repos", "torch_constraints.txt", "offline_reqs.txt", "READY_MANIFEST.json"], check=True)
subprocess.run(["tar", "-cf", os.path.join(STAGING, "mmaudio_weights.tar"), "-C", PACK, "mmaudio_weights"], check=True)
subprocess.run(["tar", "-cf", os.path.join(STAGING, "hf_cache.tar"), "-C", PACK, "hf_cache", "torch_cache"], check=True)

print("6/6 正在通过 Google 内网千兆专线直传至你的 Google 云盘 `Nightcrow_AI_SFX/`...", flush=True)
t_up = time.time()
subprocess.run(
    ["rclone", "copy", STAGING, "nc_gdrive:", "--transfers", "4", "--drive-chunk-size", "128M"],
    check=True,
)
shutil.rmtree(STAGING, ignore_errors=True)
ls_out = subprocess.check_output(["rclone", "ls", "nc_gdrive:"], text=True)
print(f"DRIVE_PACK_COMPLETE ({time.time() - t_up:.1f}s):\n" + ls_out, flush=True)
"""


REMOTE_IMPORT_FROM_DRIVE_CODE = r"""
import concurrent.futures, os, shutil, subprocess, sys, time

t0 = time.time()
PACK = "/content/Nightcrow_AI_SFX"
if not os.path.exists(os.path.join(PACK, "READY_MANIFEST.json")):
    print("正在从 Google Drive 云盘 (`Nightcrow_AI_SFX/`) 千兆内网并行流式解包至 Colab...", flush=True)
    os.makedirs(PACK, exist_ok=True)

    def _stream_untar(arc_name: str) -> str:
        t_a = time.time()
        subprocess.run(
            ["bash", "-lc", f"set -o pipefail; rclone cat nc_gdrive:{arc_name} | tar -xf - -C {PACK}"],
            check=True,
        )
        return f"{arc_name} ({time.time() - t_a:.1f}s)"

    arcs = ("wheels_repos.tar", "mmaudio_weights.tar", "hf_cache.tar")
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futs = [pool.submit(_stream_untar, a) for a in arcs]
        for f in concurrent.futures.as_completed(futs):
            print("  [Drive->Colab 解包完成] " + f.result(), flush=True)

WHEELS = os.path.join(PACK, "wheels")
REPOS = os.path.join(PACK, "repos")
HF_CACHE = os.path.join(PACK, "hf_cache")
TORCH_CACHE = os.path.join(PACK, "torch_cache")
MM_W = os.path.join(PACK, "mmaudio_weights")

os.environ["HF_HOME"] = HF_CACHE
os.environ["TORCH_HOME"] = TORCH_CACHE

print("正在从云盘离线轮子库秒装 Python 依赖（--no-index 纯离线模式）...", flush=True)
subprocess.run(
    [
        sys.executable, "-m", "pip", "install", "-q",
        "--no-index", "--find-links", WHEELS,
        "-c", os.path.join(PACK, "torch_constraints.txt"),
        "-r", os.path.join(PACK, "offline_reqs.txt"),
    ],
    check=True,
)
for sub in ("weights", "ext_weights"):
    src = os.path.join(MM_W, sub)
    dst = os.path.join(REPOS, "MMAudio", sub)
    if os.path.exists(src) and not os.path.exists(dst):
        os.symlink(src, dst)

subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-deps", "-e", os.path.join(REPOS, "MMAudio")], check=True)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-deps", "-e", os.path.join(REPOS, "TangoFlux")], check=True)
print(f"IMPORT_FROM_DRIVE_OK ({time.time() - t0:.1f}s)", flush=True)
"""


REMOTE_RUN_JOBS_CODE = r"""
import gc, json, os, random, shutil, sys, time, zipfile
from pathlib import Path
import numpy as np
import soundfile as sf
import torch

PACK = "/content/Nightcrow_AI_SFX"
REPOS = os.path.join(PACK, "repos")
HF_CACHE = os.path.join(PACK, "hf_cache")
TORCH_CACHE = os.path.join(PACK, "torch_cache")
MM_W = os.path.join(PACK, "mmaudio_weights")

os.environ["HF_HOME"] = HF_CACHE
os.environ["TORCH_HOME"] = TORCH_CACHE

for r_sub in ("MMAudio", "TangoFlux"):
    rp = os.path.join(REPOS, r_sub)
    if rp not in sys.path:
        sys.path.insert(0, rp)

torch.backends.cuda.matmul.allow_tf32 = True
torch.backends.cudnn.allow_tf32 = True

with open("/content/nc_jobs.json", "r", encoding="utf-8") as jf:
    spec = json.load(jf)

jobs = spec.get("jobs", [])
out_dir = Path("/content/nc_sfx_out")
if out_dir.exists():
    shutil.rmtree(out_dir)
out_dir.mkdir(parents=True, exist_ok=True)

def save_clean_wav(wav_tensor: torch.Tensor, sr: int, target_dur: float, dst: Path) -> None:
    arr = wav_tensor.detach().cpu().float().numpy()
    if arr.ndim == 1:
        arr = arr[None, :]
    # shape: (channels, samples)
    target_n = int(round(target_dur * sr))
    if arr.shape[1] > target_n:
        arr = arr[:, :target_n].copy()
        fade_n = min(int(0.05 * sr), target_n // 5)
        if fade_n > 0:
            arr[:, -fade_n:] *= np.linspace(1.0, 0.0, fade_n, dtype=np.float32)
    pk = float(np.max(np.abs(arr))) if arr.size else 0.0
    if pk > 0.95:
        arr = arr * (0.95 / pk)
    elif 0.0 < pk < 0.35:
        # 若模型生成偏轻，温和抬升峰值到 0.85 防听感过弱
        arr = arr * (0.85 / pk)
    sf.write(str(dst), arr.T, sr, subtype="PCM_16")

manifest_out = []

# 1) 进程内单次加载运行 TangoFlux (44.1kHz Stereo Flow-Matching Text-to-SFX)
tf_jobs = [j for j in jobs if j.get("engine") == "tangoflux"]
if tf_jobs:
    print(f"=== [1/2] 常驻加载 TangoFlux 执行 {len(tf_jobs)} 组纯文生音效任务 ===", flush=True)
    from tangoflux import TangoFluxInference
    tf_model = TangoFluxInference(name="declare-lab/TangoFlux")
    sr_tf = int(getattr(tf_model.vae.config, "sampling_rate", 44100))
    for j in tf_jobs:
        jid = j["id"]
        prompt = j["prompt"]
        dur = float(j.get("duration", 2.0))
        steps = int(j.get("steps", 50))
        cfg = float(j.get("cfg_strength", 4.5))
        seeds = j.get("seeds", [42])
        for seed in seeds:
            s_int = int(seed)
            random.seed(s_int)
            np.random.seed(s_int % (2**31 - 1))
            torch.manual_seed(s_int)
            torch.cuda.manual_seed_all(s_int)
            t0 = time.time()
            # 生成至少 2.0s 让流匹配潜空间充分展开，再精确收尾到目标时长（直调 inference_flow 透传真实 seed）
            gen_dur = max(2.0, dur)
            with torch.no_grad():
                latents = tf_model.model.inference_flow(
                    prompt,
                    duration=gen_dur,
                    num_inference_steps=steps,
                    guidance_scale=cfg,
                    seed=s_int,
                    disable_progress=True,
                )
                wav = tf_model.vae.decode(latents.transpose(2, 1)).sample.cpu()[0]
                wav = wav[:, : int(gen_dur * sr_tf)]
            fname = f"{jid}_tf_s{s_int}.wav"
            save_clean_wav(wav, sr_tf, dur, out_dir / fname)
            print(f"  [TangoFlux OK] {fname} ({time.time()-t0:.2f}s)", flush=True)
            manifest_out.append({
                "id": jid,
                "category": j.get("category", jid),
                "label": j.get("label", jid),
                "engine": "TangoFlux (44.1kHz 立体声流匹配)",
                "seed": s_int,
                "duration": dur,
                "prompt": prompt,
                "file": fname,
                "preview_mp4": "",
            })
    del tf_model
    gc.collect()
    torch.cuda.empty_cache()

# 2) 进程内单次加载运行 MMAudio (large_44k_v2: 实机动作视频帧同步 + 文本控制)
mm_jobs = [j for j in jobs if j.get("engine") == "mmaudio"]
if mm_jobs:
    print(f"=== [2/2] 常驻加载 MMAudio-Large-44k-v2 执行 {len(mm_jobs)} 组动作帧同步配音任务 ===", flush=True)
    from mmaudio.eval_utils import all_model_cfg, generate as mm_generate, load_video, make_video
    from mmaudio.model.flow_matching import FlowMatching
    from mmaudio.model.networks import get_my_mmaudio
    from mmaudio.model.utils.features_utils import FeaturesUtils

    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.bfloat16
    mcfg = all_model_cfg["large_44k_v2"]
    seq_cfg = mcfg.seq_cfg

    model_ckpt = Path(MM_W) / "weights/mmaudio_large_44k_v2.pth"
    vae_ckpt = Path(MM_W) / "ext_weights/v1-44.pth"
    sync_ckpt = Path(MM_W) / "ext_weights/synchformer_state_dict.pth"

    net = get_my_mmaudio(mcfg.model_name).to(device, dtype).eval()
    net.load_weights(torch.load(model_ckpt, map_location=device, weights_only=True))
    feature_utils = FeaturesUtils(
        tod_vae_ckpt=str(vae_ckpt),
        synchformer_ckpt=str(sync_ckpt),
        enable_conditions=True,
        mode=mcfg.mode,
        bigvgan_vocoder_ckpt=None,
        need_vae_encoder=False,
    ).to(device, dtype).eval()

    vid_cache = {}
    with torch.inference_mode():
        for j in mm_jobs:
            jid = j["id"]
            prompt = j["prompt"]
            neg = j.get("negative_prompt", "music, speech, voice, crowd, static noise")
            dur = float(j.get("duration", 2.0))
            steps = int(j.get("steps", 35))
            cfg = float(j.get("cfg_strength", 4.8))
            vid_rel = j.get("remote_video", "")
            seeds = j.get("seeds", [42])

            fm = FlowMatching(min_sigma=0, inference_mode="euler", num_steps=steps)
            if vid_rel and os.path.exists(vid_rel):
                ck = (vid_rel, dur)
                if ck not in vid_cache:
                    vid_cache[ck] = load_video(Path(vid_rel), dur)
                vinfo = vid_cache[ck]
                clip_frames = vinfo.clip_frames.unsqueeze(0)
                sync_frames = vinfo.sync_frames.unsqueeze(0)
                eff_dur = float(vinfo.duration_sec)
            else:
                vinfo = None
                clip_frames = None
                sync_frames = None
                eff_dur = dur

            seq_cfg.duration = eff_dur
            net.update_seq_lengths(seq_cfg.latent_seq_len, seq_cfg.clip_seq_len, seq_cfg.sync_seq_len)

            for seed in seeds:
                s_int = int(seed)
                rng = torch.Generator(device=device)
                rng.manual_seed(s_int)
                t0 = time.time()
                audios = mm_generate(
                    clip_frames,
                    sync_frames,
                    [prompt],
                    negative_text=[neg],
                    feature_utils=feature_utils,
                    net=net,
                    fm=fm,
                    rng=rng,
                    cfg_strength=cfg,
                )
                audio = audios.float().cpu()[0]
                fname = f"{jid}_mm_s{s_int}.wav"
                save_clean_wav(audio, int(seq_cfg.sampling_rate), eff_dur, out_dir / fname)

                vid_out_name = ""
                if vinfo is not None:
                    vid_out_name = f"{jid}_mm_s{s_int}.mp4"
                    make_video(vinfo, out_dir / vid_out_name, audio, sampling_rate=int(seq_cfg.sampling_rate))

                print(f"  [MMAudio OK] {fname} ({time.time()-t0:.2f}s)", flush=True)
                manifest_out.append({
                    "id": jid,
                    "category": j.get("category", jid),
                    "label": j.get("label", jid),
                    "engine": "MMAudio-Large-44k-v2" + (" [实机动作帧同步]" if vinfo is not None else " [纯文本]"),
                    "seed": s_int,
                    "duration": round(eff_dur, 2),
                    "prompt": prompt,
                    "negative_prompt": neg,
                    "file": fname,
                    "preview_mp4": vid_out_name,
                })

    del net, feature_utils, vid_cache
    gc.collect()
    torch.cuda.empty_cache()

with open(out_dir / "manifest.json", "w", encoding="utf-8") as mf:
    json.dump(
        {"generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "items": manifest_out},
        mf,
        ensure_ascii=False,
        indent=2,
    )

zip_path = "/content/nc_sfx_results.zip"
if os.path.exists(zip_path):
    os.remove(zip_path)
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for p in sorted(out_dir.iterdir()):
        zf.write(p, arcname=p.name)
print(f"ALL_JOBS_DONE: {len(manifest_out)} wavs -> {zip_path}", flush=True)
"""


def build_audition_html(out_dir: Path) -> Path:
    import hashlib

    manifest_file = out_dir / "manifest.json"
    data = json.loads(manifest_file.read_text(encoding="utf-8"))
    raw_items = data.get("items", [])

    # 自动过滤字节完全相同的重复 WAV，并将 MMAudio 实机动作帧同步候选项排在每组最前
    seen_hashes: set[str] = set()
    items: list[dict] = []
    for it in raw_items:
        fp = out_dir / it["file"]
        if fp.is_file():
            h = hashlib.sha256(fp.read_bytes()).hexdigest()
            if h in seen_hashes:
                continue
            seen_hashes.add(h)
        items.append(it)

    items.sort(key=lambda x: (0 if "MMAudio" in x.get("engine", "") else 1))

    by_cat: dict[str, list[dict]] = {}
    for it in items:
        by_cat.setdefault(it.get("category", "未分类"), []).append(it)

    sections_html: list[str] = []
    for cat, rows in by_cat.items():
        cards: list[str] = []
        for r in rows:
            fn = html.escape(r["file"])
            lbl = html.escape(r.get("label", r["id"]))
            eng = html.escape(r.get("engine", ""))
            seed = r.get("seed", "")
            dur = r.get("duration", "")
            pr = html.escape(r.get("prompt", ""))
            mp4 = r.get("preview_mp4", "")
            is_mm = "MMAudio" in r.get("engine", "")
            badge_cls = "badge mm" if is_mm else "badge"
            vid_block = (
                f'<video controls preload="metadata" src="{html.escape(mp4)}" style="width:100%;max-height:205px;border-radius:6px;margin-top:8px;background:#07080c"></video>'
                if mp4
                else ""
            )
            cards.append(
                f"""
                <div class="card">
                  <div class="meta">
                    <span class="{badge_cls}">{eng}</span>
                    <span class="seed">Seed {seed} · {dur}s</span>
                  </div>
                  <label class="pick">
                    <input type="checkbox" value="{fn}" data-label="{lbl} (Seed {seed})">
                    <span class="title">{lbl} <code style="font-size:11px;color:#8f9bb8">({fn})</code></span>
                  </label>
                  <audio controls preload="auto" src="{fn}"></audio>
                  {vid_block}
                  <div class="prompt">{pr}</div>
                </div>
                """
            )
        sections_html.append(
            f"""
            <section>
              <h2>{html.escape(cat)}</h2>
              <div class="grid">{''.join(cards)}</div>
            </section>
            """
        )

    page = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>《断晓》纯 AI 大模型音效试听台（Google Drive -> Colab）</title>
<style>
  body {{ background:#0b0d13; color:#e7eaf3; font-family:"Microsoft YaHei",system-ui,sans-serif; margin:0; padding:28px 36px 90px; }}
  h1 {{ margin:0 0 8px; font-size:24px; color:#f4f0ff; }}
  .sub {{ color:#9aa3b8; font-size:14px; margin-bottom:22px; line-height:1.65; }}
  .toolbar {{ position:sticky; top:12px; z-index:20; background:rgba(20,24,36,0.94); border:1px solid #353f5e; border-radius:10px; padding:12px 16px; display:flex; align-items:center; gap:12px; backdrop-filter:blur(8px); margin-bottom:22px; }}
  .btn {{ background:#7c5cff; color:#fff; border:none; border-radius:6px; padding:8px 16px; font-size:13px; font-weight:600; cursor:pointer; }}
  .btn:hover {{ background:#9277ff; }}
  #pickOut {{ flex:1; background:#0d1018; color:#d7def0; border:1px solid #283048; border-radius:6px; padding:7px 10px; font-size:12px; }}
  h2 {{ border-left:4px solid #9d7bff; padding-left:12px; font-size:18px; margin:28px 0 14px; color:#dcd4ff; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(360px, 1fr)); gap:16px; }}
  .card {{ background:#141824; border:1px solid #262d42; border-radius:10px; padding:14px 16px; }}
  .meta {{ display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; font-size:12px; }}
  .badge {{ background:#252c40; color:#b8c4e0; padding:3px 8px; border-radius:4px; font-weight:600; }}
  .badge.mm {{ background:#2c1f54; color:#decfff; border:1px solid #593ea8; }}
  .seed {{ color:#7f89a3; }}
  .pick {{ display:flex; align-items:flex-start; gap:8px; cursor:pointer; margin-bottom:10px; }}
  .pick input {{ margin-top:3px; transform:scale(1.15); accent-color:#9d7bff; }}
  .title {{ font-size:15px; font-weight:600; }}
  audio {{ width:100%; height:36px; }}
  .prompt {{ margin-top:8px; font-size:12px; color:#8b95ad; line-height:1.45; word-break:break-word; }}
</style>
</head>
<body>
  <h1>《断晓》纯 AI 神经网络音效试听台（100% 零 CC0 素材）</h1>
  <div class="sub">
    Google Drive (<code>Nightcrow_AI_SFX/</code>) 离线包导入 Colab L4 GPU 生成 · 44.1kHz PCM_16<br>
    重点推荐先点开紫色标签 <b>MMAudio-Large-44k-v2 [实机动作帧同步]</b> 的视频卡片：直接对主角实机动作逐帧拟音，高频冷钢泛音（2.5k–12kHz）占比达 <b>75%–91.6%</b>！
  </div>
  <div class="toolbar">
    <button class="btn" onclick="copyPicks()">复制勾选的音效清单</button>
    <input id="pickOut" readonly placeholder="勾选下方满意的音效卡片后，点左侧按钮一键复制发给我即可...">
  </div>
  {''.join(sections_html)}
  <script>
    function updateBox() {{
      const chks = [...document.querySelectorAll('.pick input:checked')];
      document.getElementById('pickOut').value = chks.map(c => c.value + ' [' + c.dataset.label + ']').join(' | ');
    }}
    document.querySelectorAll('.pick input').forEach(el => el.addEventListener('change', updateBox));
    function copyPicks() {{
      updateBox();
      const inp = document.getElementById('pickOut');
      inp.select();
      navigator.clipboard.writeText(inp.value || '');
    }}
  </script>
</body>
</html>
"""
    index_path = out_dir / "index.html"
    index_path.write_text(page, encoding="utf-8")
    return index_path


def cmd_pack_drive(args: argparse.Namespace) -> None:
    folder_id, rclone_conf = ensure_gdrive_folder_and_rclone_conf()
    log(f"📁 已定位 Google Drive 云盘目录 `Nightcrow_AI_SFX` (ID: {folder_id})")
    stop_evt = threading.Event()
    try:
        log(f"🚀 唤醒 Colab [{args.gpu}]，准备下载 MMAudio + TangoFlux 完整离线轮子与权重并存入云盘...")
        target, _ = allocate_colab_vm(args.gpu, rclone_conf)
        start_keepalive(target, stop_evt)
        exec_on_colab(target, REMOTE_RCLONE_BOOT, timeout=300)
        exec_on_colab(target, REMOTE_PACK_DRIVE_CODE, timeout=2700)
        log("✅ 全部依赖与双模型权重已永久存入 Google Drive (`Nightcrow_AI_SFX/`)！")
    finally:
        stop_evt.set()
        if not args.keep_warm:
            log("🛑 正在释放云端 GPU 实例确保 0.00 CU/hr...")
            colab_bridge.cmd_stop_all()


def cmd_generate(args: argparse.Namespace) -> None:
    jobs_path = Path(args.jobs).resolve()
    spec = json.loads(jobs_path.read_text(encoding="utf-8"))
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    folder_id, rclone_conf = ensure_gdrive_folder_and_rclone_conf()
    log(f"📁 已连接 Google Drive 云盘目录 `Nightcrow_AI_SFX` (ID: {folder_id})")

    stop_evt = threading.Event()
    try:
        log(f"🚀 唤醒 Colab [{args.gpu}]，准备从 Google Drive 导入 AI 音效引擎...")
        target, contents = allocate_colab_vm(args.gpu, rclone_conf)
        start_keepalive(target, stop_evt)
        exec_on_colab(target, REMOTE_RCLONE_BOOT, timeout=300)

        if args.auto_pack:
            check_code = r"""
import subprocess
out = subprocess.check_output(["rclone", "lsf", "nc_gdrive:"], text=True)
files = set(line.strip() for line in out.splitlines() if line.strip())
needed = {"READY_MANIFEST.json", "wheels_repos.tar", "mmaudio_weights.tar", "hf_cache.tar"}
print("ALREADY_PACKED" if needed.issubset(files) else "NEED_PACK", flush=True)
"""
            chk = exec_on_colab(target, check_code, timeout=120)
            if "NEED_PACK" in chk:
                log("📦 检测到云盘尚未封存完整离线包，本轮自动在云端下载并永久封存至 Google Drive...")
                exec_on_colab(target, REMOTE_PACK_DRIVE_CODE, timeout=2700)

        exec_on_colab(target, REMOTE_IMPORT_FROM_DRIVE_CODE, timeout=900)

        refresh_target_proxy(target)
        contents = ContentsClient(target)

        # 上传所有本地参考动作短视频（供 MMAudio 帧级卡点配音）
        exec_on_colab(target, "import os; os.makedirs('/content/nc_refs', exist_ok=True)", timeout=60)
        uploaded_refs: set[str] = set()
        for job in spec.get("jobs", []):
            lv = job.get("local_video", "")
            if lv:
                lv_path = Path(lv)
                if not lv_path.is_absolute():
                    lv_path = (jobs_path.parent / lv_path).resolve()
                if not lv_path.is_file():
                    raise FileNotFoundError(f"找不到参考动作视频: {lv_path}")
                remote_v = f"content/nc_refs/{lv_path.name}"
                if remote_v not in uploaded_refs:
                    log(f"📤 上传动作参考短片 -> /{remote_v}")
                    contents.upload(str(lv_path), remote_v)
                    uploaded_refs.add(remote_v)
                job["remote_video"] = f"/{remote_v}"

        fd, tmp_jobs = tempfile.mkstemp(prefix="nc_jobs_", suffix=".json")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as wf:
                json.dump(spec, wf, ensure_ascii=False, indent=2)
            contents.upload(tmp_jobs, "content/nc_jobs.json")
        finally:
            if os.path.exists(tmp_jobs):
                os.remove(tmp_jobs)

        log("⚡ 开始云端 GPU 批量生成纯 AI 音效...")
        exec_on_colab(target, REMOTE_RUN_JOBS_CODE, timeout=2400)

        refresh_target_proxy(target)
        contents = ContentsClient(target)
        local_zip = out_dir / "nc_sfx_results.zip"
        log(f"📥 正在回传生成音频与预览视频包 -> {local_zip}")
        contents.download("content/nc_sfx_results.zip", str(local_zip))
        with zipfile.ZipFile(local_zip, "r") as zf:
            zf.extractall(out_dir)
        index_html = build_audition_html(out_dir)
        log(f"🎉 纯 AI 音效试听台已就绪: {index_html}")
    finally:
        stop_evt.set()
        if not args.keep_warm:
            log("🛑 正在释放云端 GPU 实例确保 0.00 CU/hr...")
            colab_bridge.cmd_stop_all()


def main() -> None:
    p = argparse.ArgumentParser(description="Google Drive -> Colab 纯 AI 游戏音效生成管线")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="查询 Colab 账户与余额状态（0 消耗）")
    sub.add_parser("stop", help="释放全部云端 GPU 实例并归零计费")

    p_pack = sub.add_parser("pack-drive", help="下载 MMAudio + TangoFlux 完整离线轮子与权重存入 Google 云盘")
    p_pack.add_argument("--gpu", default="L4", choices=["L4", "G4", "A100", "T4"])
    p_pack.add_argument("--keep-warm", action="store_true")

    p_gen = sub.add_parser("generate", help="从 Google 云盘导入离线包并批量生成纯 AI 音效")
    p_gen.add_argument("--jobs", required=True, help="任务描述 JSON 路径")
    p_gen.add_argument("--out-dir", required=True, help="本地输出目录")
    p_gen.add_argument("--gpu", default="L4", choices=["L4", "G4", "A100", "T4"])
    p_gen.add_argument("--auto-pack", action="store_true", help="若云盘尚未封包则在同一会话自动封包并继续生成")
    p_gen.add_argument("--keep-warm", action="store_true")

    args = p.parse_args()
    if args.cmd == "status":
        colab_bridge.cmd_auth_status()
    elif args.cmd == "stop":
        colab_bridge.cmd_stop_all()
    elif args.cmd == "pack-drive":
        cmd_pack_drive(args)
    elif args.cmd == "generate":
        cmd_generate(args)


if __name__ == "__main__":
    main()
