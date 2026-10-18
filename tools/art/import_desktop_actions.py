"""Archive and prepare the user-selected desktop action sequences.

Original PNG and FrameBaker JSON files are copied byte-for-byte. Runtime files
are lossless alpha crops only; every clip shares the display scale derived from
the median standing alpha height in the first idle frame.
"""
from __future__ import annotations

import hashlib
import argparse
import json
import math
import shutil
import statistics
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
COLLECTION = "desktop-actions-20261018"
ARCHIVE = ROOT / "art/game-ready-sequences" / COLLECTION
DESKTOP_SOURCE = Path(r"C:\Users\MECHREVO\Desktop\实际应用到游戏的序列帧")
SOURCE = DESKTOP_SOURCE
RUNTIME = ROOT / "assets/image/desktop-actions"
REPORT = ROOT / "docs/desktop-actions-import.json"
PATCH = ROOT / ".runtime/desktop-actions-patch.json"
PROJECT_ID = "f185d603-1f17-43cb-8319-1e42e5527122"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def alpha_box_and_root(path: Path) -> tuple[tuple[int, int, int, int] | None, tuple[float, float] | None]:
    """Get alpha bounds and a stable estimate of the lowest visible foot row."""
    with Image.open(path) as image:
        alpha = image.getchannel("A")
        bounds = alpha.getbbox()
        if not bounds:
            return None, None
        binary = alpha.point(lambda value: 255 if value >= 32 else 0)
        root_bounds = binary.getbbox() or bounds
        # The bottommost alpha can include a one-pixel accent. Use a small
        # horizontal band and its median x to keep the trajectory stable.
        y_bottom = root_bounds[3] - 1
        band_top = max(root_bounds[1], y_bottom - 4)
        pixels = binary.crop((root_bounds[0], band_top, root_bounds[2], y_bottom + 1)).load()
        xs = [bounds[0] + x for y in range(y_bottom + 1 - band_top)
              for x in range(root_bounds[2] - root_bounds[0]) if pixels[x, y]]
        root_x = float(statistics.median(root_bounds[0] + x for y in range(y_bottom + 1 - band_top)
                                         for x in range(root_bounds[2] - root_bounds[0]) if pixels[x, y])) if xs else (root_bounds[0] + root_bounds[2]) / 2
        return bounds, (root_x, float(y_bottom))


def list_source_dirs() -> list[Path]:
    dirs = sorted(path for path in SOURCE.iterdir() if path.is_dir())
    assert len(dirs) == 24, f"expected 24 action directories, got {len(dirs)}"
    return dirs


def get_sequence(directory: Path) -> dict:
    if directory.name == "跳向上":
        manifest_path = directory / "跳.frames.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        names = manifest["files"][:9]
        return {"manifestPath": manifest_path, "manifest": manifest,
                "frames": [directory / "png" / name for name in names],
                "fps": float(manifest["fps"]), "fpsSource": "跳.frames.json (17fps); jump-up frames 000-008"}

    if directory.name == "跳落地动作":
        jump_manifest = json.loads((SOURCE / "跳向上" / "跳.frames.json").read_text(encoding="utf-8-sig"))
        frames = sorted(directory.glob("*.png"), key=lambda path: path.name)
        return {"manifestPath": None, "manifest": jump_manifest, "frames": frames,
                "fps": float(jump_manifest["fps"]), "fpsSource": "跳.frames.json (17fps); landing frames 009-016"}

    manifests = sorted(directory.glob("*.frames.json"))
    if manifests:
        manifest_path = manifests[0]
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        png_dir = directory / "png"
        names = manifest["files"]
        frames = [png_dir / name for name in names]
        return {"manifestPath": manifest_path, "manifest": manifest, "frames": frames,
                "fps": float(manifest["fps"]), "fpsSource": "FrameBaker .frames.json"}

    assert directory.name == "在空中下坠期间动画", f"unmapped sequence without JSON: {directory.name}"
    frames = sorted((directory / "png").glob("*.png"), key=lambda path: path.name)
    if not frames:
        frames = sorted(directory.glob("*.png"), key=lambda path: path.name)
    assert len(frames) == 8, f"expected 8 fall frames, got {len(frames)}"
    return {"manifestPath": None, "manifest": None, "frames": frames,
            "fps": 1000.0 / 60.0, "fpsSource": "fallback: preview.gif reports 60ms per frame; no .frames.json"}


def infer_origin(sequence: dict) -> tuple[float, float]:
    manifest = sequence["manifest"]
    if manifest:
        return float(manifest["originX"]), float(manifest["originY"])
    # The fall sequence has no source origin metadata. Its stable foot estimate
    # is used as the anchor, with per-frame deltas retained separately.
    roots = [alpha_box_and_root(frame)[1] for frame in sequence["frames"]]
    roots = [root for root in roots if root]
    return float(statistics.median(root[0] for root in roots)), float(statistics.median(root[1] for root in roots))


def archive_sources(dirs: list[Path]) -> tuple[list[dict], dict[str, dict]]:
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    sequences: dict[str, dict] = {}
    for directory in dirs:
        sequence = get_sequence(directory)
        assert all(path.is_file() for path in sequence["frames"]), f"missing PNG in {directory.name}"
        sequences[directory.name] = sequence
        for source_file in sequence["frames"]:
            rel = source_file.relative_to(SOURCE)
            destination = ARCHIVE / rel
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source_file.resolve() != destination.resolve():
                shutil.copy2(source_file, destination)
            assert destination.read_bytes() == source_file.read_bytes(), f"archive changed PNG bytes: {source_file}"
            assert sha256(destination) == sha256(source_file), f"archive SHA-256 differs for PNG: {source_file}"
            records.append({"source": str(source_file), "archive": destination.relative_to(ROOT).as_posix(),
                            "sha256": sha256(source_file), "bytes": source_file.stat().st_size,
                            "kind": "png"})
        manifest_path = sequence["manifestPath"]
        if manifest_path:
            destination = ARCHIVE / manifest_path.relative_to(SOURCE)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if manifest_path.resolve() != destination.resolve():
                shutil.copy2(manifest_path, destination)
            assert destination.read_bytes() == manifest_path.read_bytes(), f"archive changed JSON bytes: {manifest_path}"
            assert sha256(destination) == sha256(manifest_path), f"archive SHA-256 differs for JSON: {manifest_path}"
            records.append({"source": str(manifest_path), "archive": destination.relative_to(ROOT).as_posix(),
                            "sha256": sha256(manifest_path), "bytes": manifest_path.stat().st_size,
                            "kind": "frames-json"})
    assert sum(record["kind"] == "png" for record in records) == 734
    return records, sequences


def build_runtime(sequences: dict[str, dict], scale: float) -> tuple[dict, dict]:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    (RUNTIME / ".gdignore").write_text("", encoding="utf-8")
    frame_data: dict[str, list[dict]] = {}
    audits: dict[str, dict] = {}
    for action_name, sequence in sequences.items():
        origin_x, origin_y = infer_origin(sequence)
        measurements = [alpha_box_and_root(path) for path in sequence["frames"]]
        raw_roots = [root or (origin_x, origin_y) for _, root in measurements]
        stable_roots = [
            (float(statistics.median(point[0] for point in raw_roots[max(0, i - 2):i + 3])),
             float(statistics.median(point[1] for point in raw_roots[max(0, i - 2):i + 3])))
            for i in range(len(raw_roots))
        ]
        output_frames: list[dict] = []
        roots: list[dict] = []
        for index, source_frame in enumerate(sequence["frames"]):
            bounds, _ = measurements[index]
            if not bounds:
                output_frames.append({"blank": True, "durationTicks": 1,
                                      "sourceRootX": stable_roots[index][0], "sourceRootY": stable_roots[index][1]})
                roots.append({"sourceFrame": index, "x": origin_x, "y": origin_y,
                              "rawX": origin_x, "rawY": origin_y,
                              "deltaX": 0.0, "deltaY": 0.0, "estimated": True})
                continue
            left, top, right, bottom = bounds
            with Image.open(source_frame) as image:
                cropped = image.crop(bounds)
                relative = Path(action_name) / f"frame_{index + 1:05d}.png"
                destination = RUNTIME / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                cropped.save(destination, format="PNG", compress_level=6)
                # Verify that re-encoding preserved every RGBA sample.
                with Image.open(destination) as result:
                    assert result.mode == image.mode and result.size == cropped.size
                    assert result.tobytes() == cropped.tobytes(), f"pixel loss in {destination}"
            raw_x, raw_y = raw_roots[index]
            root_x, root_y = stable_roots[index]
            frame = {"asset": (Path("image/desktop-actions") / relative).as_posix(),
                     "width": right - left, "height": bottom - top,
                     "pivotX": round(origin_x - left, 4), "pivotY": round(origin_y - top, 4),
                     "durationTicks": 1, "sourceRootX": round(root_x, 4), "sourceRootY": round(root_y, 4),
                     "sourceRootDeltaX": round(root_x - origin_x, 4),
                     "sourceRootDeltaY": round(root_y - origin_y, 4)}
            output_frames.append(frame)
            roots.append({"sourceFrame": index, "x": round(root_x, 4), "y": round(root_y, 4),
                          "rawX": round(raw_x, 4), "rawY": round(raw_y, 4),
                          "deltaX": round(root_x - origin_x, 4), "deltaY": round(root_y - origin_y, 4),
                          "estimated": True})
        frame_data[action_name] = output_frames
        all_dx = [row["deltaX"] for row in roots]
        all_dy = [row["deltaY"] for row in roots]
        audits[action_name] = {
            "frameCount": len(output_frames), "fps": sequence["fps"], "fpsSource": sequence["fpsSource"],
            "alphaHeight": {"min": min(box[3] - box[1] for box, _ in measurements if box),
                            "median": statistics.median(box[3] - box[1] for box, _ in measurements if box),
                            "max": max(box[3] - box[1] for box, _ in measurements if box),
                            "firstFrameBounds": list(measurements[0][0]) if measurements[0][0] else None},
            "canvas": (list(sequence["manifest"].get("cellWidth", 0) and
                            [sequence["manifest"]["cellWidth"], sequence["manifest"]["cellHeight"]])
                       if sequence["manifest"] else list(Image.open(sequence["frames"][0]).size)),
            "origin": {"x": origin_x, "y": origin_y, "source": "FrameBaker .frames.json" if sequence["manifest"] else "estimated median visible feet"},
            "rootMotionEstimate": {"method": "median x of alpha>=32 pixels in bottom 5-pixel band; lowest visible row for y; 5-frame temporal median stabilizes trajectory",
                                   "rawMinDeltaX": min(row["rawX"] - origin_x for row in roots),
                                   "rawMaxDeltaX": max(row["rawX"] - origin_x for row in roots),
                                   "minDeltaX": min(all_dx), "maxDeltaX": max(all_dx),
                                   "minDeltaY": min(all_dy), "maxDeltaY": max(all_dy), "frames": roots},
        }
    return frame_data, audits


def clip(action: str, start: int, end: int, *, key: str | None = None,
         source_facing: int | None = None, fps_override: float | None = None) -> dict:
    """Build an inclusive 1-based slice from the original source sequence."""
    sequence = _SEQUENCES[action]
    fps = fps_override if fps_override is not None else sequence["fps"]
    frame_list = _FRAME_DATA[action][start - 1:end]
    assert len(frame_list) == end - start + 1, (action, start, end)
    # Source range is also recorded as 0-based, inclusive, for editor and audit use.
    result = {"name": key or action, "fps": fps, "loop": False, "holdLast": True,
              "effectsBaked": True, "source": {"collection": COLLECTION, "animation": action,
              "firstFrame": start, "lastFrame": end},
              "sourceName": action, "sourceFrameStart": start - 1, "sourceFrameEnd": end - 1,
              "sourceDuration": len(frame_list) / fps, "timingSource": sequence["fpsSource"],
              "sourceTransformApplied": True,
              "frames": [dict(frame) for frame in frame_list]}
    if source_facing is not None:
        result["sourceFacing"] = source_facing
    return result


_SEQUENCES: dict[str, dict] = {}
_FRAME_DATA: dict[str, list[dict]] = {}


def make_patch(frame_data: dict, audits: dict, display_scale: float) -> dict:
    global _SEQUENCES, _FRAME_DATA
    _SEQUENCES = _SEQUENCES or {}
    _FRAME_DATA = frame_data
    clips: dict[str, dict] = {}
    full_source_names = ["拔刀", "冲刺攻击", "待机", "弹刀1", "弹刀2", "弹刀3",
                         "格挡_前组01", "格挡_前组02", "格挡_前组03", "空中攻击", "跑步",
                         "跑步右向转左", "跑步左向转右", "收刀", "死亡", "跳落地动作", "跳向上",
                         "在空中下坠期间动画", "a1", "a2", "a2加后摇", "a2加前摇", "a3", "a3挑飞加后摇（强普）"]
    aliases = {
        "idle": clip("待机", 1, len(frame_data["待机"]), key="idle"),
        "run": clip("跑步", 1, len(frame_data["跑步"]), key="run"),
        "turn_left_right": clip("跑步左向转右", 1, len(frame_data["跑步左向转右"]), key="turn_left_right"),
        "turn_right_left": clip("跑步右向转左", 1, len(frame_data["跑步右向转左"]), key="turn_right_left"),
        "jump": clip("跳向上", 1, 9, key="jump"),
        "fall": clip("在空中下坠期间动画", 1, 8, key="fall"),
        "land": clip("跳落地动作", 1, 8, key="land"),
        "attack_1": clip("a1", 1, len(frame_data["a1"]), key="attack_1"),
        "attack_2": clip("a2", 1, len(frame_data["a2"]), key="attack_2"),
        "attack_3": clip("a3", 1, len(frame_data["a3"]), key="attack_3"),
        "attack_2_start": clip("a2加前摇", 1, len(frame_data["a2加前摇"]), key="attack_2_start"),
        "attack_2_recovery": clip("a2加后摇", 1, len(frame_data["a2加后摇"]), key="attack_2_recovery"),
        "strong_attack": clip("a3挑飞加后摇（强普）", 1, len(frame_data["a3挑飞加后摇（强普）"]), key="strong_attack"),
        "air_attack_1": clip("空中攻击", 1, 18, key="air_attack_1"),
        "air_attack_2": clip("空中攻击", 19, 30, key="air_attack_2"),
        "air_attack_3": clip("空中攻击", 31, 56, key="air_attack_3"),
        "dash_left": clip("冲刺攻击", 1, 21, key="dash_left", source_facing=-1),
        "dash_right": clip("冲刺攻击", 22, 56, key="dash_right", source_facing=1),
        "guard_start": clip("格挡_前组01", 1, len(frame_data["格挡_前组01"]), key="guard_start"),
        "guard_hold": clip("格挡_前组02", 1, len(frame_data["格挡_前组02"]), key="guard_hold"),
        "guard_hit_1": clip("弹刀1", 1, len(frame_data["弹刀1"]), key="guard_hit_1"),
        "guard_hit_2": clip("弹刀2", 1, len(frame_data["弹刀2"]), key="guard_hit_2"),
        "guard_hit_3": clip("弹刀3", 1, len(frame_data["弹刀3"]), key="guard_hit_3"),
        "parry_react_1": clip("弹刀1", 1, len(frame_data["弹刀1"]), key="parry_react_1"),
        "parry_react_2": clip("弹刀2", 1, len(frame_data["弹刀2"]), key="parry_react_2"),
        "parry_react_3": clip("弹刀3", 1, len(frame_data["弹刀3"]), key="parry_react_3"),
        "draw": clip("拔刀", 1, len(frame_data["拔刀"]), key="draw"),
        "sheathe": clip("收刀", 1, len(frame_data["收刀"]), key="sheathe"),
        "death": clip("死亡", 1, len(frame_data["死亡"]), key="death"),
    }
    clips.update(aliases)
    # All 24 original directories remain available in the editor as full source clips.
    for source_name in full_source_names:
        clips[f"source_{source_name}"] = clip(source_name, 1, len(frame_data[source_name]), key=f"source_{source_name}")
    return {"sprite": {"displayScale": display_scale, "worldScale": 1.0,
                        "animations": clips,
                        "preloadAnimations": ["idle", "run", "jump", "fall", "land", "attack_1", "attack_2", "attack_3"]},
            "audit": {"collection": COLLECTION, "sourceProjectId": PROJECT_ID,
                      "sourceRootMotion": audits, "sourceDirectories": full_source_names}}


def main() -> None:
    parser = argparse.ArgumentParser(description="Import the 24 desktop action directories and rebuild their runtime patch.")
    parser.add_argument("--source", type=Path,
                        help="source directory; defaults to the original Desktop folder, then the checked-in archive")
    args = parser.parse_args()
    global SOURCE
    if args.source is not None:
        SOURCE = args.source if args.source.is_absolute() else ROOT / args.source
    elif DESKTOP_SOURCE.is_dir():
        SOURCE = DESKTOP_SOURCE
    else:
        SOURCE = ARCHIVE
    SOURCE = SOURCE.resolve()
    if not SOURCE.is_dir():
        parser.error(f"source directory does not exist: {SOURCE}")
    dirs = list_source_dirs()
    records, sequences = archive_sources(dirs)
    idle_bounds, _ = alpha_box_and_root(sequences["待机"]["frames"][0])
    idle_height = idle_bounds[3] - idle_bounds[1]
    display_scale = 168.0 / idle_height
    global _SEQUENCES
    _SEQUENCES = sequences
    frame_data, audits = build_runtime(sequences, display_scale)
    patch = make_patch(frame_data, audits, display_scale)
    patch["audit"].update({"source": str(SOURCE), "displayScaleBasis": {
        "action": "待机", "frame": 1, "alphaBounds": list(idle_bounds),
        "alphaHeight": idle_height, "targetHeight": 168, "displayScale": display_scale},
        "sourceFileCount": len(records), "pngCount": sum(row["kind"] == "png" for row in records),
        "sourceFrames": sum(len(sequence["frames"]) for sequence in sequences.values()),
        "sourceTimingConflict": {"axes": ["跑步", "跑步左向转右", "跑步右向转左"],
                                 "database": "tools/framebaker/storage/framebaker.db animation_axes.fps",
                                 "databaseFps": 4, "exportJsonFps": 4,
                                 "previewGif": "60ms/frame is generated preview timing; not used as authoritative fps"},
        "scaleReviewNotes": [
            "displayScale 0.41076 maps idle frame 1 alpha height 409px to 168px; per-action body size differs and a single scale is not asserted as visually correct for every clip.",
            "fall runtime review: visible body bbox is 982px high, approximately 403px at the shared idle scale; root will derive a separate non-destructive runtime scale while keeping source clips at source origin.",
            "a1 frame 1 alpha bbox is 720px high due to an isolated white speck; reviewed body is approximately 344px high, so bbox-based scale should reject that speck."
        ],
        "sourceFiles": records})
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    write_json(ARCHIVE / "manifest.json", {"collection": COLLECTION, "source": str(SOURCE),
                                            "sourceProjectId": PROJECT_ID, "pngCount": 734,
                                            "directories": [{"name": name, "frames": len(seq["frames"]),
                                                             "fps": seq["fps"], "fpsSource": seq["fpsSource"]}
                                                            for name, seq in sequences.items()],
                                            "files": records})
    (ARCHIVE / "README.md").write_text(
        "# 桌面动作原片归档\n\n"
        f"来源：`{SOURCE}`；FrameBaker 项目 `{PROJECT_ID}`。\n\n"
        "共 24 个动作目录、734 张 PNG。原始 PNG 与 `.frames.json` 按字节原样归档，SHA-256 与字节数见 `manifest.json`。\n"
        "运行副本只裁掉透明边界，不缩放、不绘制、不降分辨率；固定锚点由来源 originX/Y 减裁剪左上角得到，\n"
        "根运动用独立的 sourceRoot 估算轨迹记录，便于审计与后续接入。所有动作合成图设置 `effectsBaked=true`。\n"
        "统一基准倍率仅按待机第1帧透明边界高度标定为168px，不代表每个动作身体尺寸都正确；fall与a1尺寸异常见桌面导入审计。\n"
        "运行时显示倍率与战斗碰撞 worldScale 分开。\n"
        "重建：fresh clone 可直接运行 `python tools/art/import_desktop_actions.py --source art/game-ready-sequences/desktop-actions-20261018`，再运行 configure 脚本重建 battle 配置；来源就是归档目录时会跳过自复制，并逐文件校验字节与 SHA-256。未指定 `--source` 时优先读取原桌面目录，找不到时回退到此归档。\n"
        "跑步与转身 FPS 已通过 FrameBaker SQLite 项目的 animation_axes.fps 核对为4；GIF 60ms是预览节奏。\n"
        "下坠素材无 `.frames.json`，仅按 preview.gif 的60ms/帧显式回退。跳起与落地共享跳动作的17FPS。\n",
        encoding="utf-8")
    write_json(PATCH, patch)
    write_json(REPORT, patch["audit"])
    print(json.dumps({"displayScale": display_scale, "idleAlphaBounds": idle_bounds,
                      "directories": len(sequences), "sourceFrames": patch["audit"]["sourceFrames"],
                      "archiveRecords": len(records), "animations": len(patch["sprite"]["animations"]),
                      "runtimePngs": sum(1 for _ in RUNTIME.rglob("*.png"))}, ensure_ascii=False))


if __name__ == "__main__":
    main()
