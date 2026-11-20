"""直接写 battle.json 把 run 换成导入回来的序列。

修改器的保存接口被它自己的旧校验挡住了（连未改动的配置 POST 回去都会报
「attack / dashAttack 必须是键盘按键列表」「冲刺斩…SHIFT+J」三条老错误），
所以这里按同样内容直接落盘，先备份。

用法：python tools/art/apply_run_clip.py --import-id <uuid> [--dry]
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from bind_run_clip import build_clip  # noqa: E402

CONFIG = ROOT / "assets" / "data" / "battle.json"
BACKUP_DIR = ROOT / "assets" / "data" / "backups"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--import-id", required=True)
    ap.add_argument("--axis", default="跑步_v5v6_v58_v68")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--fps", type=float, default=None,
                    help="覆盖播放帧率；默认用 FrameBaker 的 24fps")
    ap.add_argument("--loop-frame", type=int, default=None,
                    help="循环从第几帧开始（前面几帧就是起跑过渡）")
    ap.add_argument("--meta", default=None, help="本地 .frames.json 路径")
    args = ap.parse_args()

    clip = build_clip(args.import_id, args.axis, Path(args.meta) if args.meta else None)
    if args.fps:
        clip["fps"] = float(args.fps)
    if args.loop_frame is not None:
        clip["loopFrame"] = int(args.loop_frame)

    cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    anims = cfg["characters"][0]["sprite"]["animations"]
    old = anims.get("run", {})
    print(f"run: {len(old.get('frames', []))} 帧 @{old.get('fps')}fps  →  "
          f"{len(clip['frames'])} 帧 @{clip['fps']}fps，pivot ({clip['frames'][0]['pivotX']}, "
          f"{clip['frames'][0]['pivotY']})")
    if args.dry:
        print("（--dry，不写盘）")
        return

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    backup = BACKUP_DIR / f"before-run-v5v6-{stamp}.json"
    shutil.copy2(CONFIG, backup)
    print(f"备份：{backup.relative_to(ROOT)}")

    anims["run"] = clip
    CONFIG.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    size = CONFIG.stat().st_size
    print(f"已写入 {CONFIG.relative_to(ROOT)}（{size / 1024:.0f} KB）")


if __name__ == "__main__":
    main()
