#!/usr/bin/env python3
"""
《断晓》腾讯混元 HunyuanVideo-Foley-XXL (48kHz 双声道) Google 云盘持久化 -> Colab 推理管线

云盘持久化路径：Google Drive `Nightcrow_AI_SFX/HunyuanFoley_XXL/`
  - `hyfoley_wheels_repos.tar` : 全部离线 Python 依赖轮子 + HunyuanVideo-Foley & audiotools 源码仓库
  - `hyfoley_xxl_weights.tar`  : hunyuanvideo_foley.pth (XXL 10.3GB) + vae_128d_48k.pth (48kHz 双声道 DAC) + synchformer + config.yaml
  - `hyfoley_hf_cache.tar`     : google/siglip2-base-patch16-512 + laion/larger_clap_general + timm 缓存
  - `READY_HYFOLEY.json`       : 封包版本清单
"""
from __future__ import annotations

import argparse
import html
import json
import os
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

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

import colab_bridge  # type: ignore  # noqa: E402
from colab_cli.contents import ContentsClient  # type: ignore  # noqa: E402
from colab_drive_sfx import (  # noqa: E402
    allocate_colab_vm,
    ensure_gdrive_folder_and_rclone_conf,
    exec_on_colab,
    log,
    refresh_target_proxy,
    start_keepalive,
)

DRIVE_SUBDIR = "nc_gdrive:HunyuanFoley_XXL"

REMOTE_RCLONE_BOOT = f"""
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
subprocess.run(["rclone", "mkdir", "{DRIVE_SUBDIR}"], check=True)
out = subprocess.check_output(["rclone", "lsf", "{DRIVE_SUBDIR}"], text=True)
print("RCLONE_HY_READY files=" + str(len(out.splitlines())), flush=True)
"""


REMOTE_PACK_HYFOLEY_CODE = f"""
import gc, json, os, shutil, subprocess, sys, time
from pathlib import Path

PACK = "/content/Nightcrow_HyFoley"
WHEELS = os.path.join(PACK, "wheels")
REPOS = os.path.join(PACK, "repos")
HF_CACHE = os.path.join(PACK, "hf_cache")
TORCH_CACHE = os.path.join(PACK, "torch_cache")
HY_W = os.path.join(PACK, "hy_weights")

for d in (WHEELS, REPOS, HF_CACHE, TORCH_CACHE, HY_W):
    os.makedirs(d, exist_ok=True)

os.environ["HF_HOME"] = HF_CACHE
os.environ["TORCH_HOME"] = TORCH_CACHE
os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"

print("1/6 正在克隆 HunyuanVideo-Foley 与 descript-audiotools 官方仓库...", flush=True)
if not os.path.exists(os.path.join(REPOS, "HunyuanVideo-Foley")):
    subprocess.run(["git", "clone", "--depth", "1", "https://github.com/Tencent-Hunyuan/HunyuanVideo-Foley.git", os.path.join(REPOS, "HunyuanVideo-Foley")], check=True)
if not os.path.exists(os.path.join(REPOS, "audiotools")):
    subprocess.run(["git", "clone", "--depth", "1", "https://github.com/descriptinc/audiotools.git", os.path.join(REPOS, "audiotools")], check=True)

print("2/6 正在下载并锁定 Colab 原生 PyTorch ABI 的离线 Python 依赖轮子...", flush=True)
import numpy as np
import scipy
import torch, torchvision, torchaudio

constraints_txt = os.path.join(PACK, "torch_constraints.txt")
with open(constraints_txt, "w", encoding="utf-8") as cf:
    cf.write(f"torch=={{torch.__version__.split('+')[0]}}\\n")
    cf.write(f"torchvision=={{torchvision.__version__.split('+')[0]}}\\n")
    cf.write(f"torchaudio=={{torchaudio.__version__.split('+')[0]}}\\n")
    cf.write(f"numpy=={{np.__version__}}\\n")
    cf.write(f"scipy=={{scipy.__version__}}\\n")

base_pkgs = [
    "huggingface_hub>=0.27.0",
    "hf_transfer",
    "safetensors",
    "accelerate>=0.34.2",
    "diffusers>=0.31.0",
    "transformers>=4.49.0,<5.0.0",
    "timm>=1.0.12",
    "sentencepiece",
    "einops>=0.7.0",
    "av>=14.0.0",
    "pyyaml",
    "omegaconf",
    "easydict",
    "loguru",
    "soundfile",
    "librosa>=0.10.0",
    "argbind",
    "pyloudnorm",
    "julius",
    "ffmpy",
    "pystoi",
    "torch_stoi",
    "flatten-dict",
    "markdown2",
    "randomname",
    "importlib-resources",
]
with open(os.path.join(PACK, "offline_reqs.txt"), "w", encoding="utf-8") as rf:
    rf.write("\\n".join(base_pkgs) + "\\n")

subprocess.run(
    [sys.executable, "-m", "pip", "download", "-q", "-d", WHEELS, "-c", constraints_txt, "-r", os.path.join(PACK, "offline_reqs.txt")],
    check=True,
)
for fn in list(os.listdir(WHEELS)):
    low = fn.lower()
    if low.startswith(("torch-", "torchvision-", "torchaudio-", "nvidia_", "triton-", "numpy-", "scipy-")):
        os.remove(os.path.join(WHEELS, fn))

subprocess.run(
    [sys.executable, "-m", "pip", "install", "-q", "--no-index", "--find-links", WHEELS, "-c", constraints_txt, "-r", os.path.join(PACK, "offline_reqs.txt")],
    check=True,
)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-deps", "-e", os.path.join(REPOS, "audiotools")], check=True)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-deps", "-e", os.path.join(REPOS, "HunyuanVideo-Foley")], check=True)

print("3/6 正在高速拉取 HunyuanVideo-Foley-XXL (10.3GB) + 48kHz DAC VAE (1.5GB) + Synchformer 权重...", flush=True)
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="tencent/HunyuanVideo-Foley",
    local_dir=HY_W,
    allow_patterns=[
        "config.yaml",
        "hunyuanvideo_foley.pth",
        "vae_128d_48k.pth",
        "synchformer_state_dict.pth",
    ],
)

print("4/6 正在拉取并预热 SigLIP-2 视觉编码器与 CLAP 音频文本编码器...", flush=True)
snapshot_download(repo_id="google/siglip2-base-patch16-512")
snapshot_download(repo_id="laion/larger_clap_general", ignore_patterns=["*.h5", "*.msgpack", "*.ot"])

if os.path.join(REPOS, "HunyuanVideo-Foley") not in sys.path:
    sys.path.insert(0, os.path.join(REPOS, "HunyuanVideo-Foley"))

from transformers import AutoModel, AutoTokenizer, ClapTextModelWithProjection
from hunyuanvideo_foley.models.synchformer import Synchformer
_s = AutoModel.from_pretrained("google/siglip2-base-patch16-512")
_ct = AutoTokenizer.from_pretrained("laion/larger_clap_general")
_cm = ClapTextModelWithProjection.from_pretrained("laion/larger_clap_general")
_sy = Synchformer()
del _s, _ct, _cm, _sy
gc.collect()
torch.cuda.empty_cache()

manifest = {{
    "packed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "model": "tencent/HunyuanVideo-Foley-XXL (48kHz Stereo DAC-128d)",
    "colab_torch": torch.__version__,
    "archives": ["hyfoley_wheels_repos.tar", "hyfoley_xxl_weights.tar", "hyfoley_hf_cache.tar"],
}}
with open(os.path.join(PACK, "READY_HYFOLEY.json"), "w", encoding="utf-8") as mf:
    json.dump(manifest, mf, indent=2, ensure_ascii=False)

print("5/6 正在流式打包并直传至你的 Google 云盘 (`Nightcrow_AI_SFX/HunyuanFoley_XXL/`)...", flush=True)
t_up = time.time()
rclone_up_json = os.path.join(PACK, "READY_HYFOLEY.json")
subprocess.run(["rclone", "copyto", rclone_up_json, "{DRIVE_SUBDIR}/READY_HYFOLEY.json"], check=True)

arcs = [
    ("hyfoley_wheels_repos.tar", ["wheels", "repos", "torch_constraints.txt", "offline_reqs.txt", "READY_HYFOLEY.json"]),
    ("hyfoley_xxl_weights.tar", ["hy_weights"]),
    ("hyfoley_hf_cache.tar", ["hf_cache", "torch_cache"]),
]
for arc_name, members in arcs:
    t_a = time.time()
    mem_str = " ".join(members)
    subprocess.run(
        ["bash", "-lc", f"set -o pipefail; tar -cf - -C {{PACK}} {{mem_str}} | rclone rcat {DRIVE_SUBDIR}/{{arc_name}} --drive-chunk-size 128M"],
        check=True,
    )
    print(f"  [云盘封存完成] {{arc_name}} ({{time.time() - t_a:.1f}}s)", flush=True)

ls_out = subprocess.check_output(["rclone", "ls", "{DRIVE_SUBDIR}"], text=True)
print(f"HYFOLEY_PACK_COMPLETE ({{time.time() - t_up:.1f}}s):\\n" + ls_out, flush=True)
"""


REMOTE_IMPORT_HYFOLEY_CODE = f"""
import concurrent.futures, os, subprocess, sys, time

t0 = time.time()
PACK = "/content/Nightcrow_HyFoley"
if not os.path.exists(os.path.join(PACK, "READY_HYFOLEY.json")):
    print("正在从 Google Drive (`Nightcrow_AI_SFX/HunyuanFoley_XXL/`) 并行流式导入离线包...", flush=True)
    os.makedirs(PACK, exist_ok=True)

    def _stream_untar(arc_name: str) -> str:
        t_a = time.time()
        subprocess.run(
            ["bash", "-lc", f"set -o pipefail; rclone cat {DRIVE_SUBDIR}/{{arc_name}} | tar -xf - -C {{PACK}}"],
            check=True,
        )
        return f"{{arc_name}} ({{time.time() - t_a:.1f}}s)"

    arcs = ("hyfoley_wheels_repos.tar", "hyfoley_xxl_weights.tar", "hyfoley_hf_cache.tar")
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futs = [pool.submit(_stream_untar, a) for a in arcs]
        for f in concurrent.futures.as_completed(futs):
            print("  [Drive->Colab 解包完成] " + f.result(), flush=True)
else:
    print("检测到当前实例内存盘已有就绪的 Nightcrow_HyFoley 离线包，直接跳过重复解包！", flush=True)

WHEELS = os.path.join(PACK, "wheels")
REPOS = os.path.join(PACK, "repos")
HF_CACHE = os.path.join(PACK, "hf_cache")
TORCH_CACHE = os.path.join(PACK, "torch_cache")

os.environ["HF_HOME"] = HF_CACHE
os.environ["TORCH_HOME"] = TORCH_CACHE

subprocess.run(
    [
        sys.executable, "-m", "pip", "install", "-q",
        "--no-index", "--find-links", WHEELS,
        "-c", os.path.join(PACK, "torch_constraints.txt"),
        "-r", os.path.join(PACK, "offline_reqs.txt"),
    ],
    check=True,
)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-deps", "-e", os.path.join(REPOS, "audiotools")], check=True)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-deps", "-e", os.path.join(REPOS, "HunyuanVideo-Foley")], check=True)
print(f"HYFOLEY_ENV_READY ({{time.time() - t0:.1f}}s)", flush=True)
"""


REMOTE_RUN_HYFOLEY_JOBS_CODE = r"""
import gc, json, os, random, shutil, subprocess, sys, time, zipfile
from pathlib import Path
import numpy as np
import soundfile as sf
import torch
from torchvision import transforms
from torchvision.transforms import v2

PACK = "/content/Nightcrow_HyFoley"
REPOS = os.path.join(PACK, "repos")
HF_CACHE = os.path.join(PACK, "hf_cache")
TORCH_CACHE = os.path.join(PACK, "torch_cache")
HY_W = os.path.join(PACK, "hy_weights")

os.environ["HF_HOME"] = HF_CACHE
os.environ["TORCH_HOME"] = TORCH_CACHE

for r_sub in ("audiotools", "HunyuanVideo-Foley"):
    rp = os.path.join(REPOS, r_sub)
    if rp not in sys.path:
        sys.path.insert(0, rp)

torch.backends.cuda.matmul.allow_tf32 = True
torch.backends.cudnn.allow_tf32 = True

from transformers import AutoModel, AutoTokenizer, ClapTextModelWithProjection
from hunyuanvideo_foley.models.dac_vae.model.dac import DAC
from hunyuanvideo_foley.models.hifi_foley import HunyuanVideoFoley
from hunyuanvideo_foley.models.synchformer import Synchformer
from hunyuanvideo_foley.utils.config_utils import AttributeDict, load_yaml
from hunyuanvideo_foley.utils.feature_utils import encode_text_feat, encode_video_features
from hunyuanvideo_foley.utils.model_utils import denoise_process, load_state_dict

with open("/content/hy_jobs.json", "r", encoding="utf-8") as jf:
    spec = json.load(jf)

jobs = spec.get("jobs", [])
default_neg = spec.get("negative_prompt", "noisy, harsh, muffled, music, speech, voice")
out_dir = Path("/content/hy_sfx_out")
if out_dir.exists():
    shutil.rmtree(out_dir)
out_dir.mkdir(parents=True, exist_ok=True)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
cfg_path = os.path.join(HY_W, "config.yaml")
cfg = load_yaml(cfg_path)

print("=== [阶段 1/2] 提取全部任务的 CLAP 文本特征与 SigLIP-2/Synchformer 视觉特征 ===", flush=True)
clap_tokenizer = AutoTokenizer.from_pretrained("laion/larger_clap_general")
clap_model = ClapTextModelWithProjection.from_pretrained("laion/larger_clap_general").to(device).eval()

has_video = any(j.get("remote_video") for j in jobs)
if has_video:
    siglip2_preprocess = transforms.Compose([
        transforms.Resize((512, 512)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]),
    ])
    siglip2_model = AutoModel.from_pretrained("google/siglip2-base-patch16-512").to(device).eval()
    syncformer_preprocess = v2.Compose([
        v2.Resize(224, interpolation=v2.InterpolationMode.BICUBIC),
        v2.CenterCrop(224),
        v2.ToImage(),
        v2.ToDtype(torch.float32, scale=True),
        v2.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]),
    ])
    syncformer_model = Synchformer()
    syncformer_model.load_state_dict(torch.load(os.path.join(HY_W, "synchformer_state_dict.pth"), weights_only=False, map_location="cpu"))
    syncformer_model = syncformer_model.to(device).eval()
else:
    siglip2_preprocess = siglip2_model = syncformer_preprocess = syncformer_model = None

feat_helper = AttributeDict({
    "clap_tokenizer": clap_tokenizer,
    "clap_model": clap_model,
    "siglip2_preprocess": siglip2_preprocess,
    "siglip2_model": siglip2_model,
    "syncformer_preprocess": syncformer_preprocess,
    "syncformer_model": syncformer_model,
    "device": device,
})

prepared_jobs = []
for j in jobs:
    prompt = j["prompt"]
    neg = j.get("negative_prompt", default_neg)
    text_feat_res, _ = encode_text_feat([neg, prompt], feat_helper)
    text_feat = text_feat_res[1:]
    uncond_text_feat = text_feat_res[:1]
    max_tlen = cfg.model_config.model_kwargs.text_length
    if max_tlen < text_feat.shape[1]:
        text_feat = text_feat[:, :max_tlen]
        uncond_text_feat = uncond_text_feat[:, :max_tlen]
    t_feats = AttributeDict({"text_feat": text_feat, "uncond_text_feat": uncond_text_feat})

    vid_rel = j.get("remote_video", "")
    if vid_rel and os.path.exists(vid_rel):
        v_feats, vid_dur = encode_video_features(vid_rel, feat_helper)
        eff_dur = float(vid_dur)
        has_v = True
    else:
        v_feats = None
        eff_dur = float(j.get("duration", 2.0))
        has_v = False

    prepared_jobs.append((j, v_feats, t_feats, eff_dur, has_v))

del feat_helper, clap_tokenizer, clap_model, siglip2_model, syncformer_model
gc.collect()
torch.cuda.empty_cache()

print("=== [阶段 2/2] 常驻加载满血 HunyuanVideo-Foley-XXL (BF16) + 48kHz DAC VAE 批量生成 ===", flush=True)
# 先在 CPU 构建与加载 state_dict 再一次性转入 GPU BF16，彻底杜绝 GPU 峰值双份拷贝
foley_model = HunyuanVideoFoley(cfg, dtype=torch.bfloat16, device=torch.device("cpu"))
foley_model = load_state_dict(foley_model, os.path.join(HY_W, "hunyuanvideo_foley.pth"))
foley_model = foley_model.to(device=device, dtype=torch.bfloat16).eval()
gc.collect()
torch.cuda.empty_cache()

dac_model = DAC.load(os.path.join(HY_W, "vae_128d_48k.pth")).to(device)
dac_model.requires_grad_(False)
dac_model.eval()

infer_dict = AttributeDict({
    "foley_model": foley_model,
    "dac_model": dac_model,
    "device": device,
})

def save_clean_48k_wav(audio_t: torch.Tensor, sr: int, target_dur: float, dst: Path) -> None:
    arr = audio_t.detach().cpu().float().numpy()
    if arr.ndim == 3:
        arr = arr[0]
    if arr.ndim == 1:
        arr = arr[None, :]
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
        arr = arr * (0.85 / pk)
    sf.write(str(dst), arr.T, sr, subtype="PCM_16")

manifest_out = []
for j, v_feats, t_feats, eff_dur, has_v in prepared_jobs:
    jid = j["id"]
    steps = int(j.get("steps", 50))
    gs = float(j.get("guidance_scale", 5.0))
    seeds = j.get("seeds", [42])
    vid_rel = j.get("remote_video", "")

    if not has_v:
        # 纯文本录音棚模式：使用 HunyuanVideoFoley 原生可学习空视觉特征，避免黑底抠图误导！
        gen_dur = max(2.0, eff_dur)
        clip_len = max(8, int(round(gen_dur * 8)))
        t_sync = max(16, int(round(gen_dur * 25)))
        sync_len = ((t_sync - 16) // 8 + 1) * 8
        with torch.no_grad():
            empty_clip = foley_model.get_empty_clip_sequence(bs=1, len=clip_len).to(device)
            empty_sync = foley_model.get_empty_sync_sequence(bs=1, len=sync_len).to(device)
        v_feats_use = AttributeDict({"siglip2_feat": empty_clip, "syncformer_feat": empty_sync})
    else:
        gen_dur = eff_dur
        v_feats_use = v_feats

    for seed in seeds:
        s_int = int(seed)
        random.seed(s_int)
        np.random.seed(s_int % (2**31 - 1))
        torch.manual_seed(s_int)
        torch.cuda.manual_seed_all(s_int)
        t0 = time.time()
        audio, sr = denoise_process(
            v_feats_use,
            t_feats,
            gen_dur,
            infer_dict,
            cfg,
            guidance_scale=gs,
            num_inference_steps=steps,
            batch_size=1,
        )
        fname = f"{jid}_s{s_int}.wav"
        wav_path = out_dir / fname
        save_clean_48k_wav(audio, int(sr), eff_dur, wav_path)

        mp4_name = ""
        if has_v and vid_rel and os.path.exists(vid_rel):
            mp4_name = f"{jid}_s{s_int}.mp4"
            subprocess.run(
                [
                    "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", vid_rel, "-i", str(wav_path),
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest",
                    str(out_dir / mp4_name),
                ],
                check=True,
            )

        print(f"  [HyFoley-XXL OK] {fname} ({time.time() - t0:.2f}s, sr={sr})", flush=True)
        manifest_out.append({
            "id": jid,
            "category": j.get("category", jid),
            "label": j.get("label", jid),
            "engine": "HunyuanVideo-Foley-XXL (48kHz)" + (" [视频帧同步]" if has_v else " [纯文本录音棚]"),
            "seed": s_int,
            "duration": round(eff_dur, 2),
            "prompt": j["prompt"],
            "file": fname,
            "preview_mp4": mp4_name,
        })

with open(out_dir / "manifest.json", "w", encoding="utf-8") as mf:
    json.dump({"generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "items": manifest_out}, mf, ensure_ascii=False, indent=2)

zip_path = "/content/hy_sfx_results.zip"
if os.path.exists(zip_path):
    os.remove(zip_path)
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for p in sorted(out_dir.iterdir()):
        zf.write(p, arcname=p.name)
print(f"ALL_HYFOLEY_DONE: {len(manifest_out)} wavs -> {zip_path}", flush=True)
"""


def build_curated_html(out_dir: Path, keep_files: list[str] | None = None) -> Path:
    manifest_file = out_dir / "manifest.json"
    data = json.loads(manifest_file.read_text(encoding="utf-8"))
    items = data.get("items", [])
    if keep_files is not None:
        keep_set = set(keep_files)
        items = [it for it in items if it["file"] in keep_set]

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
            vid_block = (
                f'<video controls preload="metadata" src="{html.escape(mp4)}" style="width:100%;max-height:205px;border-radius:6px;margin-top:8px;background:#07080c"></video>'
                if mp4
                else ""
            )
            cards.append(
                f"""
                <div class="card">
                  <div class="meta">
                    <span class="badge">{eng}</span>
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
<title>《断晓》腾讯混元 HunyuanVideo-Foley-XXL (48kHz) 耳审精选试听台</title>
<style>
  body {{ background:#0b0d13; color:#e7eaf3; font-family:"Microsoft YaHei",system-ui,sans-serif; margin:0; padding:28px 36px 90px; }}
  h1 {{ margin:0 0 8px; font-size:24px; color:#f4f0ff; }}
  .sub {{ color:#9aa3b8; font-size:14px; margin-bottom:22px; line-height:1.65; }}
  .toolbar {{ position:sticky; top:12px; z-index:20; background:rgba(20,24,36,0.94); border:1px solid #353f5e; border-radius:10px; padding:12px 16px; display:flex; align-items:center; gap:12px; backdrop-filter:blur(8px); margin-bottom:22px; }}
  .btn {{ background:#7c5cff; color:#fff; border:none; border-radius:6px; padding:8px 16px; font-size:13px; font-weight:600; cursor:pointer; }}
  #pickOut {{ flex:1; background:#0d1018; color:#d7def0; border:1px solid #283048; border-radius:6px; padding:7px 10px; font-size:12px; }}
  h2 {{ border-left:4px solid #9d7bff; padding-left:12px; font-size:18px; margin:28px 0 14px; color:#dcd4ff; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(360px, 1fr)); gap:16px; }}
  .card {{ background:#141824; border:1px solid #262d42; border-radius:10px; padding:14px 16px; }}
  .meta {{ display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; font-size:12px; }}
  .badge {{ background:#2c1f54; color:#decfff; border:1px solid #593ea8; padding:3px 8px; border-radius:4px; font-weight:600; }}
  .seed {{ color:#7f89a3; }}
  .pick {{ display:flex; align-items:flex-start; gap:8px; cursor:pointer; margin-bottom:10px; }}
  .pick input {{ margin-top:3px; transform:scale(1.15); accent-color:#9d7bff; }}
  .title {{ font-size:15px; font-weight:600; }}
  audio {{ width:100%; height:36px; }}
  .prompt {{ margin-top:8px; font-size:12px; color:#8b95ad; line-height:1.45; word-break:break-word; }}
</style>
</head>
<body>
  <h1>《断晓》腾讯混元 HunyuanVideo-Foley-XXL（48kHz 双声道）精选试听台</h1>
  <div class="sub">Google Drive (<code>Nightcrow_AI_SFX/HunyuanFoley_XXL/</code>) 持久化离线包 -> Colab GPU 推理</div>
  <div class="toolbar">
    <button class="btn" onclick="copyPicks()">复制勾选的音效清单</button>
    <input id="pickOut" readonly placeholder="勾选下方满意的音效卡片后，点左侧按钮一键复制...">
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


def _upload_text_file(contents: ContentsClient, remote_path: str, text: str) -> None:
    fd, tmp_p = tempfile.mkstemp(prefix="hy_up_", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as wf:
            wf.write(text)
        contents.upload(tmp_p, remote_path)
    finally:
        if os.path.exists(tmp_p):
            os.remove(tmp_p)


def _download_text_if_exists(contents: ContentsClient, remote_path: str) -> str | None:
    fd, tmp_p = tempfile.mkstemp(prefix="hy_dl_", suffix=".tmp")
    os.close(fd)
    try:
        contents.download(remote_path, tmp_p)
        return Path(tmp_p).read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return None
    finally:
        if os.path.exists(tmp_p):
            os.remove(tmp_p)


def cmd_generate(args: argparse.Namespace) -> None:
    jobs_path = Path(args.jobs).resolve()
    spec = json.loads(jobs_path.read_text(encoding="utf-8"))
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    folder_id, rclone_conf = ensure_gdrive_folder_and_rclone_conf()
    log(f"📁 已连接 Google Drive 云盘目录 `Nightcrow_AI_SFX` (ID: {folder_id})")

    stop_evt = threading.Event()
    try:
        log(f"🚀 唤醒 Colab [{args.gpu}]，准备部署/导入 HunyuanVideo-Foley-XXL (48kHz)...")
        target, contents = allocate_colab_vm(args.gpu, rclone_conf)
        start_keepalive(target, stop_evt)

        exec_on_colab(target, "import os; os.makedirs('/content/hy_refs', exist_ok=True)", timeout=60)
        refresh_target_proxy(target)
        contents = ContentsClient(target)

        uploaded_refs: set[str] = set()
        for job in spec.get("jobs", []):
            lv = job.get("local_video", "")
            if lv:
                lv_path = Path(lv)
                if not lv_path.is_absolute():
                    lv_path = (jobs_path.parent / lv_path).resolve()
                if not lv_path.is_file():
                    raise FileNotFoundError(f"找不到参考动作视频: {lv_path}")
                remote_v = f"content/hy_refs/{lv_path.name}"
                if remote_v not in uploaded_refs:
                    log(f"📤 上传完整场景动作参考片 -> /{remote_v}")
                    contents.upload(str(lv_path), remote_v)
                    uploaded_refs.add(remote_v)
                job["remote_video"] = f"/{remote_v}"

        _upload_text_file(contents, "content/hy_jobs.json", json.dumps(spec, ensure_ascii=False, indent=2))
        _upload_text_file(contents, "content/hy_rclone_boot.py", REMOTE_RCLONE_BOOT)
        _upload_text_file(contents, "content/hy_pack.py", REMOTE_PACK_HYFOLEY_CODE)
        _upload_text_file(contents, "content/hy_import.py", REMOTE_IMPORT_HYFOLEY_CODE)
        _upload_text_file(contents, "content/hy_infer.py", REMOTE_RUN_HYFOLEY_JOBS_CODE)

        worker_code = f"""#!/usr/bin/env python3
import json, os, subprocess, sys, time, traceback

STATUS_PATH = "/content/hy_status.json"

def write_status(state: str, **extra):
    payload = {{"state": state, "updated_at": time.time()}}
    payload.update(extra)
    tmp = STATUS_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as wf:
        json.dump(payload, wf, ensure_ascii=False)
    os.replace(tmp, STATUS_PATH)

def run_step(label: str, script_path: str):
    print(f"\\n>>> [Worker] 开始执行: {{label}} ({{script_path}})", flush=True)
    subprocess.run([sys.executable, "-u", script_path], check=True)

try:
    write_status("running", step="rclone_boot")
    run_step("初始化 rclone 与 Google Drive 挂载", "/content/hy_rclone_boot.py")

    if {bool(args.auto_pack)!r}:
        out = subprocess.check_output(["rclone", "lsf", {DRIVE_SUBDIR!r}], text=True)
        files = set(line.strip() for line in out.splitlines() if line.strip())
        needed = {{"READY_HYFOLEY.json", "hyfoley_wheels_repos.tar", "hyfoley_xxl_weights.tar", "hyfoley_hf_cache.tar"}}
        if needed.issubset(files):
            print(">>> [Worker] ALREADY_PACKED: Google Drive 已有完整 HunyuanFoley_XXL 4 分卷离线包，跳过封包！", flush=True)
        else:
            write_status("running", step="pack_drive")
            run_step("首次拉取并流式封存 HunyuanFoley_XXL 至 Google Drive", "/content/hy_pack.py")

    write_status("running", step="import_drive")
    run_step("从 Google Drive 并行流式导入离线包与依赖", "/content/hy_import.py")

    write_status("running", step="infer_xxl")
    run_step("满血 HunyuanVideo-Foley-XXL (48kHz 双声道) 批量生成", "/content/hy_infer.py")

    write_status("done")
    print(">>> [Worker] WORKER_ALL_COMPLETE", flush=True)
except BaseException:
    tb = traceback.format_exc()
    print(">>> [Worker] FATAL ERROR:\\n" + tb, flush=True)
    write_status("error", error=tb)
    sys.exit(1)
"""
        _upload_text_file(contents, "content/hy_worker.py", worker_code)

        launch_code = """
import json, os, subprocess, sys
for p in ("/content/hy_status.json", "/content/hy_worker.log"):
    if os.path.exists(p):
        os.remove(p)
with open("/content/hy_status.json", "w", encoding="utf-8") as wf:
    json.dump({"state": "starting"}, wf)
lf = open("/content/hy_worker.log", "w", encoding="utf-8")
proc = subprocess.Popen(
    [sys.executable, "-u", "/content/hy_worker.py"],
    stdout=lf,
    stderr=subprocess.STDOUT,
    start_new_session=True,
)
print(f"HY_WORKER_STARTED pid={proc.pid}", flush=True)
"""
        log("⚡ 启动后台独立推理守护进程 `/content/hy_worker.py`（免疫 WebSocket 断连 & 零内核显存争抢）...")
        exec_on_colab(target, launch_code, timeout=60)

        printed_lines = 0
        t_start = time.time()
        while True:
            time.sleep(8.0)
            if time.time() - t_start > 3600:
                raise TimeoutError("HunyuanVideo-Foley-XXL 云端后台任务超过 60 分钟超时")
            try:
                refresh_target_proxy(target)
                contents = ContentsClient(target)
                log_txt = _download_text_if_exists(contents, "content/hy_worker.log")
                if log_txt:
                    lines = log_txt.splitlines()
                    if len(lines) > printed_lines:
                        for ln in lines[printed_lines:]:
                            print(f"  [HyWorker] {ln}", flush=True)
                        printed_lines = len(lines)

                st_txt = _download_text_if_exists(contents, "content/hy_status.json")
                if st_txt:
                    st = json.loads(st_txt)
                    state_val = st.get("state")
                    if state_val == "done":
                        break
                    if state_val == "error":
                        raise RuntimeError("云端 HyWorker 执行报错:\n" + str(st.get("error", "")))
            except RuntimeError:
                raise
            except Exception as poll_exc:
                log(f"  [轮询网络抖动自动重试] {poll_exc}")

        refresh_target_proxy(target)
        contents = ContentsClient(target)
        local_zip = out_dir / "hy_sfx_results.zip"
        log(f"📥 正在回传生成音频包 -> {local_zip}")
        contents.download("content/hy_sfx_results.zip", str(local_zip))
        with zipfile.ZipFile(local_zip, "r") as zf:
            zf.extractall(out_dir)
        index_html = build_curated_html(out_dir)
        log(f"🎉 原始 24 条音频已回传（待多模态耳审筛选）: {index_html}")
    finally:
        stop_evt.set()
        if not args.keep_warm:
            log("🛑 正在释放云端 GPU 实例确保 0.00 CU/hr...")
            colab_bridge.cmd_stop_all()


def main() -> None:
    p = argparse.ArgumentParser(description="HunyuanVideo-Foley-XXL Google Drive -> Colab 推理管线")
    sub = p.add_subparsers(dest="cmd", required=True)
    p_gen = sub.add_parser("generate", help="从 Google 云盘导入/封包并生成 48kHz 双声道音效")
    p_gen.add_argument("--jobs", required=True)
    p_gen.add_argument("--out-dir", required=True)
    p_gen.add_argument("--gpu", default="L4", choices=["L4", "G4", "A100", "T4"])
    p_gen.add_argument("--auto-pack", action="store_true")
    p_gen.add_argument("--keep-warm", action="store_true")

    args = p.parse_args()
    if args.cmd == "generate":
        cmd_generate(args)


if __name__ == "__main__":
    main()
