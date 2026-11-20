"""把修改器刚导入的 FrameBaker 序列绑定到「跑步」，走修改器自己的保存接口。

流程（和 UI 上「动作工坊 → 替换上方当前动作 → 保存」等价）：
1. GET  /api/config          读 battle.json
2. 把 characters[0].sprite.animations.run 换成导入回来的 clip（loop=true）
3. POST /api/config          校验 + 备份 + 写盘

用法：python tools/art/bind_run_clip.py --import-id <uuid> --axis 跑步_v5v6
"""
from __future__ import annotations

import argparse
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = "http://127.0.0.1:4329"
CLIP_DIR = ROOT / "assets" / "image" / "imports" / "framebaker"


def get(path: str) -> dict:
    with urllib.request.urlopen(BASE + path, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def post(path: str, payload: dict) -> dict:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(BASE + path, data=data, method="POST",
                                headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:  # 校验失败时打印细节
        return json.loads(e.read().decode("utf-8"))


def build_clip(import_id: str, axis: str, meta_path: Path | None) -> dict:
    folder = CLIP_DIR / import_id
    pngs = sorted(folder.glob("*.png"))
    if not pngs:
        raise SystemExit(f"没找到导入的帧：{folder}")
    # 修改器导入时只搬 PNG，元数据得从本地那份 .frames.json 读
    src = meta_path or (ROOT / ".runtime" / "action-audit" / "merge_v5v6" / "run_merged.frames.json")
    meta = json.loads(Path(src).read_text(encoding="utf-8"))["meta"]
    frames = [{
        "asset": f"image/imports/framebaker/{import_id}/{p.name}",
        "width": meta["cellWidth"], "height": meta["cellHeight"],
        "pivotX": meta["originX"], "pivotY": meta["originY"],
        "durationTicks": 1, "sourceFrame": i,
    } for i, p in enumerate(pngs)]
    return {
        "name": "跑步（即梦 v5+v6 合体）",
        "fps": meta["fps"],
        "loop": True,
        "holdLast": False,
        "effectsBaked": False,
        "source": {"collection": "imports/framebaker", "animation": "跑步",
                   "firstFrame": 1, "lastFrame": len(frames)},
        "sourceName": axis,
        "timingSource": "FrameBaker import",
        "sourceFacing": 1,
        "frameBaker": {"app": "FrameBaker", "format": "sequence",
                       "originX": meta["originX"], "originY": meta["originY"],
                       "cellWidth": meta["cellWidth"], "cellHeight": meta["cellHeight"],
                       "importId": import_id},
        "frames": frames,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--import-id", required=True)
    ap.add_argument("--axis", default="跑步_v5v6_v58_v68")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--meta", default=None, help="本地 .frames.json 路径（默认取 .runtime 里那份）")
    args = ap.parse_args()

    clip = build_clip(args.import_id, args.axis, Path(args.meta) if args.meta else None)
    print(f"新 run 剪辑：{len(clip['frames'])} 帧 @ {clip['fps']}fps，"
          f"画布 {clip['frames'][0]['width']}x{clip['frames'][0]['height']}，"
          f"pivot ({clip['frames'][0]['pivotX']}, {clip['frames'][0]['pivotY']})")

    cfg = get("/api/config")["config"]
    anims = cfg["characters"][0]["sprite"]["animations"]
    old = anims.get("run", {})
    print(f"原来的 run：{len(old.get('frames', []))} 帧 @ {old.get('fps')}fps，loop={old.get('loop')}")
    anims["run"] = clip
    if args.dry:
        print("（--dry，不写盘）")
        return

    res = post("/api/config", cfg)
    if res.get("ok"):
        print(f"已保存：{res.get('message')}  备份={res.get('backup')}")
        v = res.get("validation", {})
        print(f"校验：ok={v.get('ok')}  error={v.get('error', 0)}  warning={v.get('warning', 0)}")
    else:
        print("保存失败：")
        print(json.dumps(res, ensure_ascii=False, indent=2)[:4000])


if __name__ == "__main__":
    main()
