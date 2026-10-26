"""Replace matched bank events with clean cuts from the archived video audio.

Only editing is cutting, short edge fades and constant gain. No synthesized
layers, filtering, resampling, random alternate actions or pitch changes.
"""
from array import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "assets/audio/sfx_v3"
OUT = ROOT / "assets/audio/selected-video"
ARCHIVE = ROOT / "art/selected-video-audio"
SR, CHANNELS = 32000, 2
SOURCE = {
    "A": "mmh3_action_00014.m4a", "K": "空中a.m4a",
    "D": "mmh3_冲刺攻击_v2.m4a", "G": "mmh3_左侧格挡_v5.m4a",
    "B": "mmh3_拔刀40.m4a", "X": "mmh3_死亡_v1.m4a",
}
# The original 24 FPS frame ranges are documented in selected-original-segments.
# Short swing excerpts are aligned to the existing three-frame swing cue.
SPECS = {
    "swing_l1": ("A", .82, 1.13),
    "swing_l2": ("A", 1.31, 1.66),
    "swing_l3": ("A", 2.05, 2.40),
    "swing_up": ("A", 5.61, 5.96),
    "swing_charge": ("A", 5.61, 5.96),
    "swing_air1": ("K", .28, .64),
    "swing_air2": ("K", .75, 1.04),
    # The third source whoosh leads the third visual segment slightly.
    "swing_air3": ("K", 1.08, 1.55),
    "swing_air_up": ("K", .28, .64),
    "swing_dash": ("D", 1.14, 1.58),
    "swing_dash_left": ("D", .10, .62),
    "block": ("G", 1.75, 2.13),
    "parry": ("G", 5.99, 6.55),
    # Use the body landing, excluding the spoken passage at 0.7–2.2 seconds.
    "die": ("X", 2.99, 3.34),
    "draw": ("B", 0.0, 2.42),
    "sheathe": ("B", 124 / 24, 6.575),
}
# Events routed to a chosen replacement instead of their video cut. The cut is
# still written to selected-video/ for the archive, but the bank plays this.
MANIFEST_OVERRIDES = {
    # 2026-10-26: user picked the layered parry A2; see assets/audio/parry/README.md.
    "parry": {"files": ["../parry/parry_a2.wav"], "bus": "impact", "pitchJitter": 0.0, "peakOffsetSeconds": 0.005},
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def window_peak(powers, seconds):
    """Peak RMS window and its center time, using one-millisecond steps."""
    width = min(len(powers), max(1, round(seconds * SR)))
    if not width:
        raise ValueError("Empty source audio")
    energy = sum(powers[:width])
    best, best_start = energy, 0
    stride = SR // 1000
    for start in range(stride, len(powers) - width + 1, stride):
        energy += sum(powers[start + width - stride:start + width])
        energy -= sum(powers[start - stride:start])
        if energy > best:
            best, best_start = energy, start
    return math.sqrt(max(best, 0) / width), (best_start + width / 2) / SR


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = BANK / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    archive_manifest = json.loads((ARCHIVE / "manifest.json").read_text(encoding="utf-8"))
    archive_hashes = {row["audio_file"]: row["audio_sha256"] for row in archive_manifest["files"]}
    decoded = {}
    rows, obsolete = [], []
    for key, (source_key, begin, end) in SPECS.items():
        source = ARCHIVE / SOURCE[source_key]
        if sha(source.read_bytes()) != archive_hashes[source.name]:
            raise ValueError(f"Archive hash mismatch: {source.name}")
        if source_key not in decoded:
            raw = subprocess.check_output([
                "ffmpeg", "-v", "error", "-i", str(source), "-map", "0:a:0",
                "-ar", str(SR), "-ac", str(CHANNELS), "-f", "f32le", "-",
            ])
            samples = array("f")
            samples.frombytes(raw)
            if sys.byteorder != "little":
                samples.byteswap()
            decoded[source_key] = samples
        samples = decoded[source_key]
        first, last = round(begin * SR), min(round(end * SR), len(samples) // CHANNELS)
        powers = [sum(samples[i * CHANNELS + c] ** 2 for c in range(CHANNELS)) / CHANNELS
                  for i in range(first, last)]
        _, original_peak = window_peak(powers, .020)
        is_swing = key.startswith("swing_")
        # Preserve native rate; remove only lead-in before this isolated whoosh.
        target_peak = .05 if is_swing else .012
        align_onset = is_swing or key in ("block", "parry", "die")
        cut_frames = max(0, round((original_peak - target_peak) * SR)) if align_onset else 0
        first += cut_frames
        powers = powers[cut_frames:]
        _, peak_offset = window_peak(powers, .020)
        loudness, _ = window_peak(powers, .050)
        excerpt = samples[first * CHANNELS:last * CHANNELS]
        peak = max(abs(v) for v in excerpt)
        target_db = -19 if is_swing else (-20 if key in ("draw", "sheathe") else -14)
        gain = min(10 ** (target_db / 20) / max(loudness, 1e-9),
                   10 ** (-1 / 20) / max(peak, 1e-9))
        count = len(excerpt) // CHANNELS
        fade_in, fade_out = round(.004 * SR), min(round(.025 * SR), count // 4)
        pcm = array("h")
        for i in range(count):
            edge = min(1.0, i / max(fade_in, 1), (count - 1 - i) / max(fade_out, 1))
            for channel in range(CHANNELS):
                pcm.append(round(max(-1.0, min(1.0, excerpt[i * CHANNELS + channel] * gain * edge)) * 32767))
        if sys.byteorder != "little":
            pcm.byteswap()
        target = OUT / f"{key}.wav"
        with wave.open(str(target), "wb") as output:
            output.setparams((CHANNELS, 2, SR, 0, "NONE", "not compressed"))
            output.writeframes(pcm.tobytes())
        old = manifest["clips"].get(key, {})
        for name in old.get("files", []):
            old_file = (BANK / name).resolve()
            if old_file.parent == BANK.resolve() and old_file.name.startswith(key + "_") and old_file.name.endswith(".ogg.b64"):
                obsolete.append(old_file)
        manifest["clips"][key] = {
            "files": [f"../selected-video/{key}.wav"],
            "bus": "motion" if is_swing or key in ("draw", "sheathe") else "impact",
            "pitchJitter": 0.0,
            "sourceVideo": source.name,
            "peakOffsetSeconds": round(peak_offset, 6),
        }
        rows.append({
            "event": key, "source": source.relative_to(ROOT).as_posix(),
            "sourceSha256": archive_hashes[source.name],
            "requestedRangeSeconds": [begin, end],
            "actualRangeSeconds": [first / SR, last / SR],
            "peakOffsetSeconds": round(peak_offset, 6),
            "gainDb": round(20 * math.log10(gain), 4),
            "fadeInSeconds": fade_in / SR, "fadeOutSeconds": fade_out / SR,
            "asset": target.relative_to(ROOT / "assets").as_posix(),
            "sha256": sha(target.read_bytes()), "pcmSha256": sha(pcm.tobytes()),
            "durationSeconds": count / SR, "sampleRate": SR, "channels": CHANNELS,
        })
        print(f"Prepared {key}: {count / SR:.3f}s, peak {peak_offset:.3f}s", flush=True)
    for key, entry in MANIFEST_OVERRIDES.items():
        manifest["clips"][key] = dict(entry)
    # Keep the public event key, but retire its unused additional synthetic rush.
    for name in manifest["clips"].get("dash", {}).get("files", []):
        path = (BANK / name).resolve()
        if path.parent == BANK.resolve() and path.name.startswith("dash_") and path.name.endswith(".ogg.b64"):
            obsolete.append(path)
    manifest["clips"]["dash"] = dict(manifest["clips"]["swing_dash"])
    manifest["note"] = "Base events: make_sfx_v3.py; selected original video overrides: apply_selected_video_audio.py. gainDb remains configurable."
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    # Delete only known replaced generated variants, never source archives or WAV fallbacks.
    for path in obsolete:
        path.unlink(missing_ok=True)
    config_path = ROOT / "assets/data/battle.json"
    config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    config["audio"]["swingByMove"]["dash_slash_left"] = "swing_dash_left"
    config_path.write_text(json.dumps(config, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    report = {
        "method": "Native 32kHz stereo PCM WAV; isolated source excerpts, gain and edge fades only",
        "pitchChanges": False, "synthesizedLayers": False,
        "clips": rows,
        "aliases": {"dash": "swing_dash (startup layer suppressed; one recording per dash)"},
        "overrides": {key: entry["files"][0] for key, entry in MANIFEST_OVERRIDES.items()},
        "replacedGeneratedFiles": sorted({f"{key}_{i}.ogg.b64" for key in (*SPECS, "dash") if key not in ("draw", "sheathe", "swing_dash_left")
                                          for i in range(1 if key == "die" else 2)}),
        "retained": "Unmatched footsteps, jumps, landings, impacts, enemy, UI, charge and ranged audio; original M4A archive",
    }
    (OUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(rows)} source audio clips; removed {len(obsolete)} replaced generated variants")


if __name__ == "__main__":
    main()
