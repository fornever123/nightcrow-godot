"""调跑步的播放帧率 + 配套跑速，让步频正常又不滑步。

原理：新循环 16 帧 = 两步，一步 ≈ 82 世界像素。
  步频（步/秒） = fps / 8
  不滑步要求    = 跑速 ÷ fps = 82 / 8 = 10.25 世界像素/帧
所以 fps 定了，跑速就跟着定：speed = 10.25 * fps。

用法：python tools/art/tune_run_speed.py --fps 30 [--dry]
"""
from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "assets" / "data" / "battle.json"
BACKUP_DIR = ROOT / "assets" / "data" / "backups"
STRIDE_PER_FRAME = 82.0 / 8.0      # 世界像素/帧


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fps", type=float, required=True)
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    ch = cfg["characters"][0]
    run = ch["sprite"]["animations"]["run"]
    old_fps, old_speed = run.get("fps"), ch.get("speed")
    new_speed = round(STRIDE_PER_FRAME * args.fps, 1)
    steps_per_s = args.fps / 8.0

    print(f"fps {old_fps} → {args.fps}；跑速 {old_speed} → {new_speed}"
          f"（步频 {steps_per_s:.2f} 步/秒 ≈ {steps_per_s * 60:.0f} 步/分）")
    if args.dry:
        print("（--dry，不写盘）")
        return

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    backup = BACKUP_DIR / f"before-run-fps-{stamp}.json"
    shutil.copy2(CONFIG, backup)
    print(f"备份：{backup.relative_to(ROOT)}")

    run["fps"] = float(args.fps)
    ch["speed"] = new_speed
    CONFIG.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("已写入 assets/data/battle.json")


if __name__ == "__main__":
    main()
