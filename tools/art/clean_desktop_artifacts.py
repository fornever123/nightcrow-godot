"""Conservatively remove detached near-white noise and thin canvas-edge lines.

Run with the existing image-analysis environment:
  E:\\sprite-video-lab-models\\venv\\Scripts\\python.exe tools/art/clean_desktop_artifacts.py

Uses the already-installed OpenCV 4.11.0 / NumPy 1.26.4 and Pillow 12.3.0; it
does not install packages. Source crops remain untouched. Only alpha is cleared
for a component that passes the conservative noise/edge-line checks.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "assets/image/desktop-actions"
CLEAN_ROOT = ROOT / "assets/image/desktop-actions-clean"
AUDIT_PATH = ROOT / "docs/desktop-actions-cleanup.json"
MAP_PATH = ROOT / ".runtime/desktop-clean-map.json"
GROUPS = ["a1", "a2", "a2加前摇", "a2加后摇", "a3", "a3挑飞加后摇（强普）"]
ALPHA_THRESHOLD = 32


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bbox_distance(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    dx = max(0, ax - (bx + bw), bx - (ax + aw))
    dy = max(0, ay - (by + bh), by - (ay + ah))
    return math.hypot(dx, dy)


def find_components(rgba: np.ndarray) -> tuple[list[dict], np.ndarray]:
    alpha = rgba[:, :, 3]
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        (alpha >= ALPHA_THRESHOLD).astype(np.uint8), connectivity=8
    )
    components: list[dict] = []
    for label in range(1, count):
        x, y, width, height, area = (int(value) for value in stats[label])
        pixels = rgba[labels == label, :3]
        if len(pixels):
            low = pixels.min(axis=1)
            high = pixels.max(axis=1)
            mean = pixels.mean(axis=1)
            near_white_gray_ratio = float(((high - low <= 85) & (mean >= 128)).mean())
        else:
            near_white_gray_ratio = 0.0
        components.append({
            "label": label,
            "bbox": [x, y, width, height],
            "area": area,
            "nearWhiteOrGrayRatio": round(near_white_gray_ratio, 4),
        })
    return components, labels


def cleanup_frame(source: Path, destination: Path) -> dict:
    original_hash = sha256(source)
    with Image.open(source) as image:
        rgba = np.array(image.convert("RGBA"))
    height, width = rgba.shape[:2]
    components, labels = find_components(rgba)
    if not components:
        if destination.exists():
            destination.unlink()
        return {"source": source.relative_to(ROOT).as_posix(), "changed": False,
                "width": width, "height": height, "sourceSha256": original_hash,
                "removedComponents": []}

    primary = max(components, key=lambda item: item["area"])
    px, py, pw, ph = primary["bbox"]
    primary_bbox = (px, py, pw, ph)
    primary_area = primary["area"]
    min_distance = max(20.0, ph * 0.15)
    removed: list[dict] = []

    for component in components:
        if component["label"] == primary["label"]:
            continue
        x, y, w, h = component["bbox"]
        bbox = (x, y, w, h)
        distance = bbox_distance(primary_bbox, bbox)
        small = component["area"] < primary_area * 0.15
        isolated = distance > min_distance
        near_white_gray = component["nearWhiteOrGrayRatio"] >= 0.75
        touches_border = x == 0 or y == 0 or x + w >= width or y + h >= height
        thin_limit = max(2, round(height * 0.004))
        thin = min(w, h) <= thin_limit
        elongated = max(w, h) >= max(80, round(max(width, height) * 0.20))

        reason = None
        if small and isolated and near_white_gray:
            reason = "detached_small_near_white_or_gray_component"
        elif small and touches_border and thin and elongated:
            reason = "isolated_thin_long_canvas_border_line"

        if reason:
            removed.append({
                "bbox": [x, y, w, h],
                "area": component["area"],
                "nearWhiteOrGrayRatio": component["nearWhiteOrGrayRatio"],
                "distanceFromPrimaryPx": round(distance, 2),
                "reason": reason,
                "alphaThreshold": ALPHA_THRESHOLD,
            })

    if not removed:
        if destination.exists():
            destination.unlink()
        return {"source": source.relative_to(ROOT).as_posix(), "changed": False,
                "width": width, "height": height, "sourceSha256": original_hash,
                "primaryBbox": list(primary_bbox), "primaryArea": primary_area,
                "removedComponents": []}

    cleaned = rgba.copy()
    removed_mask = np.zeros(labels.shape, dtype=bool)
    for component in removed:
        x, y, w, h = component["bbox"]
        # The mask is limited to this candidate's label; RGB and all retained
        # RGBA samples remain exactly as decoded from the source PNG.
        label = next(item["label"] for item in components if item["bbox"] == component["bbox"])
        removed_mask |= labels == label
    cleaned[:, :, 3][removed_mask] = 0
    destination.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(cleaned, mode="RGBA").save(destination, format="PNG", compress_level=6)

    with Image.open(destination) as output_image:
        output = np.array(output_image.convert("RGBA"))
    assert output.shape == rgba.shape, f"canvas dimensions changed: {destination}"
    assert np.array_equal(output[~removed_mask], rgba[~removed_mask]), f"retained pixels changed: {destination}"
    assert np.array_equal(output[removed_mask, :3], rgba[removed_mask, :3]), f"RGB changed while clearing alpha: {destination}"
    assert np.all(output[removed_mask, 3] == 0), f"candidate alpha not cleared: {destination}"
    assert sha256(source) == original_hash, f"source changed during cleanup: {source}"

    return {
        "source": source.relative_to(ROOT).as_posix(),
        "cleaned": destination.relative_to(ROOT).as_posix(),
        "changed": True,
        "width": width,
        "height": height,
        "sourceSha256": original_hash,
        "cleanedSha256": sha256(destination),
        "primaryBbox": list(primary_bbox),
        "primaryArea": primary_area,
        "removedComponents": removed,
        "pixelValidation": "retained RGBA byte-identical; changed pixels only have candidate alpha set to zero",
    }


def main() -> None:
    if cv2.__version__ != "4.11.0":
        print(f"notice: running with OpenCV {cv2.__version__}; validated environment is 4.11.0")
    rows: list[dict] = []
    frame_count = 0
    for group in GROUPS:
        source_dir = SOURCE_ROOT / group
        assert source_dir.is_dir(), f"missing source action directory: {source_dir}"
        sources = sorted(source_dir.glob("*.png"), key=lambda path: path.name)
        assert sources, f"no PNGs found in {source_dir}"
        frame_count += len(sources)
        for source in sources:
            destination = CLEAN_ROOT / group / source.name
            rows.append(cleanup_frame(source, destination))

    replacements = []
    for row in rows:
        if row["changed"]:
            replacements.append({
                "source": row["source"],
                "asset": row["cleaned"],
                "width": row["width"],
                "height": row["height"],
                "sameCanvas": True,
                "pivotTransform": "unchanged; frame metadata remains valid",
                "removedComponents": row["removedComponents"],
            })

    summary = {
        "groups": GROUPS,
        "sourceFrameCount": frame_count,
        "changedFrameCount": len(replacements),
        "unchangedFrameCount": frame_count - len(replacements),
        "removedComponentCount": sum(len(row["removedComponents"]) for row in rows),
        "opencvVersion": cv2.__version__,
        "numpyVersion": np.__version__,
        "pillowVersion": Image.__version__ if hasattr(Image, "__version__") else "unknown",
        "alphaThreshold": ALPHA_THRESHOLD,
        "policy": "Delete only detached small near-white/gray components or isolated, thin, long canvas-border lines; ambiguous colored and large components are preserved.",
        "frames": rows,
    }
    mapping = {
        "sourceRoot": "assets/image/desktop-actions",
        "cleanedRoot": "assets/image/desktop-actions-clean",
        "replacements": replacements,
    }
    AUDIT_PATH.parent.mkdir(parents=True, exist_ok=True)
    MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    AUDIT_PATH.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    MAP_PATH.write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: summary[key] for key in (
        "sourceFrameCount", "changedFrameCount", "unchangedFrameCount", "removedComponentCount",
        "opencvVersion", "numpyVersion", "pillowVersion")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
