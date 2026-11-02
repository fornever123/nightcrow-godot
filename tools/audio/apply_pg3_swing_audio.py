"""Ground three-hit swings from the user's 普攻三段.mp4 (2026-11-01).

Archives the video's AAC track unchanged, then cuts swing_l1/2/3 the same way
as apply_selected_video_audio.py: cutting, short edge fades and constant gain
only, native sample rate, swing peak 50 ms after the clip start. The older
selected-video swings stay on disk; only the bank routing changes.

    python -I tools/audio/apply_pg3_swing_audio.py --source "E:/.0download/普攻三段.mp4"
"""
from array import array
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "assets/audio/sfx_v3"
OUT = ROOT / "assets/audio/swing-pg3"
ARCHIVE = ROOT / "art/swing-pg3-audio"
AUDIO_NAME = "普攻三段.m4a"
SR, CHANNELS = 44100, 2
# Source seconds, matched to the slash arcs in the video: 1 rising cut at 0.25s,
# 2 forward cut at 0.70s, 3 big downward sweep at 1.50s. The small whoosh at
# 1.21s is the turn before the third cut and is left out. (begin, end, fade_out)
SPECS = {
    "swing_l1": (.22, .64, .025),
    "swing_l2": (.66, 1.17, .040),
    "swing_l3": (1.48, 2.40, .080),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def window_peak(powers, seconds):
    """Peak RMS window and its center time, using one-millisecond steps."""
    width = min(len(powers), max(1, round(seconds * SR)))
    energy = sum(powers[:width])
    best, best_start = energy, 0
    stride = SR // 1000
    for start in range(stride, len(powers) - width + 1, stride):
        energy += sum(powers[start + width - stride:start + width])
        energy -= sum(powers[start - stride:start])
        if energy > best:
            best, best_start = energy, start
    return math.sqrt(max(best, 0) / width), (best_start + width / 2) / SR


def archive(source):
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    target = ARCHIVE / AUDIO_NAME
    if not target.exists():
        subprocess.check_call(["ffmpeg", "-v", "error", "-i", str(source), "-map", "0:a:0",
                               "-vn", "-c:a", "copy", str(target)])
    pcm = [subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
                                    "-f", "s32le", "-"]) for path in (source, target)]
    if pcm[0] != pcm[1]:
        raise ValueError("Archived audio does not decode to the source audio")
    info = {
        "purpose": "Original audio of the user's ground three-hit reference video; archive only",
        "source_video": str(source),
        "source_sha256": sha(source.read_bytes()),
        "method": "ffmpeg -map 0:a:0 -vn -c:a copy (AAC in M4A; no re-encoding)",
        "audio_file": AUDIO_NAME,
        "audio_sha256": sha(target.read_bytes()),
        "decoded_pcm_s32le_sha256": sha(pcm[1]),
        "decoded_audio_matches_source": True,
    }
    (ARCHIVE / "manifest.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return target, info


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="E:/.0download/普攻三段.mp4")
    source, info = archive(Path(parser.parse_args().source))
    raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(source), "-map", "0:a:0",
                                   "-ar", str(SR), "-ac", str(CHANNELS), "-f", "f32le", "-"])
    samples = array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = BANK / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    rows = []
    for key, (begin, end, fade_out_s) in SPECS.items():
        first, last = round(begin * SR), min(round(end * SR), len(samples) // CHANNELS)
        powers = [sum(samples[i * CHANNELS + c] ** 2 for c in range(CHANNELS)) / CHANNELS
                  for i in range(first, last)]
        _, original_peak = window_peak(powers, .020)
        cut_frames = max(0, round((original_peak - .05) * SR))
        first += cut_frames
        powers = powers[cut_frames:]
        _, peak_offset = window_peak(powers, .020)
        loudness, _ = window_peak(powers, .050)
        excerpt = samples[first * CHANNELS:last * CHANNELS]
        peak = max(abs(v) for v in excerpt)
        gain = min(10 ** (-19 / 20) / max(loudness, 1e-9), 10 ** (-1 / 20) / max(peak, 1e-9))
        count = len(excerpt) // CHANNELS
        fade_in, fade_out = round(.004 * SR), min(round(fade_out_s * SR), count // 4)
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
        manifest["clips"][key] = {
            "files": [f"../swing-pg3/{key}.wav"],
            "bus": "motion",
            "pitchJitter": 0.0,
            "sourceVideo": AUDIO_NAME,
            "peakOffsetSeconds": round(peak_offset, 6),
        }
        rows.append({
            "event": key, "source": (ARCHIVE / AUDIO_NAME).relative_to(ROOT).as_posix(),
            "sourceSha256": info["audio_sha256"],
            "requestedRangeSeconds": [begin, end],
            "actualRangeSeconds": [first / SR, last / SR],
            "peakOffsetSeconds": round(peak_offset, 6),
            "gainDb": round(20 * math.log10(gain), 4),
            "fadeInSeconds": fade_in / SR, "fadeOutSeconds": fade_out / SR,
            "asset": target.relative_to(ROOT / "assets").as_posix(),
            "sha256": sha(target.read_bytes()), "pcmSha256": sha(pcm.tobytes()),
            "durationSeconds": count / SR, "sampleRate": SR, "channels": CHANNELS,
        })
        print(f"Prepared {key}: {count / SR:.3f}s, peak {peak_offset:.3f}s, gain {20 * math.log10(gain):+.1f} dB", flush=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    report = {
        "method": "Native 44.1kHz stereo PCM WAV; isolated source excerpts, gain and edge fades only",
        "pitchChanges": False, "synthesizedLayers": False,
        "clips": rows,
        "replaces": {key: f"../selected-video/{key}.wav (kept on disk)" for key in SPECS},
    }
    (OUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
