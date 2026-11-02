"""Enemy hits and player hurts from Freesound #323525 "Bloody Blade" (2026-11-01).

The user picked this recording and asked for it as is: no layering, no
synthesis, no reverb, no pitch change. Every hit/hurt key gets the same cut
of the one recording. Only gain and length differ between tiers; the lengths
follow the short-hit caps in tests/test_audio.gd. Processing is a 35 Hz
high-pass (the file carries a drifting DC offset), a cut at the blade
contact 0.10 s into the file, constant gain, a 2 ms fade-in and a tail fade.

    python -I tools/audio/apply_bloody_blade_hits.py --source "E:/.0download/323525__kreastricon62__bloody-blade.wav"
"""
from array import array
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "assets/audio/sfx_v3"
OUT = ROOT / "assets/audio/hit-bloody-blade"
ARCHIVE = ROOT / "art/hit-bloody-blade-audio"
SOURCE_NAME = "323525__kreastricon62__bloody-blade.wav"
SOURCE_SHA = "bb2b6b2f7eb523201b046d994b6b29364f4174a57d31ff7dafff6c3e2ff6bb0d"
SR = 44100
CONTACT = 0.100  # 0-0.1s is a faint swish before the blade lands; the game has its own swing
# key: (target 50 ms RMS dB, length s, fade-out s).
# The user wants the swing to lead and the hit to sit under it ("挥刀声音为主，击中声音其次").
# Swings play at about -23 dB per channel (-19 dB clips on the -4 dB motion bus), hits on
# the 0 dB impact bus with up to -2.5 dB strength gain. The user then asked for hits at
# half again ("击中再小一倍", -6 dB), so they land 8-12 dB under the swing.
SPECS = {
    "hit_light": (-33.0, .25, .06),
    "hit_heavy": (-32.0, .40, .08),
    "hit_finisher": (-31.0, .56, .10),
    # Player hurts match the enemy hit tiers (user: "主角被打也降低成和怪物受击一样").
    "hurt": (-33.0, .29, .06),
    "hurt_heavy": (-32.0, .40, .08),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def max_rms(samples, seconds):
    width = max(1, round(seconds * SR))
    squares = [v * v for v in samples]
    energy = sum(squares[:width])
    best = energy
    for i in range(width, len(squares)):
        energy += squares[i] - squares[i - width]
        best = max(best, energy)
    return math.sqrt(max(best, 0) / width)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="E:/.0download/" + SOURCE_NAME)
    source = Path(parser.parse_args().source)
    if sha(source.read_bytes()) != SOURCE_SHA:
        raise ValueError("Source is not the registered Freesound #323525 file")
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    archived = ARCHIVE / SOURCE_NAME
    if not archived.exists():
        shutil.copyfile(source, archived)
    raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(archived),
                                   "-af", "highpass=f=35,highpass=f=35", "-ar", str(SR), "-ac", "1", "-f", "f32le", "-"])
    samples = array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    cut = samples[round(CONTACT * SR):]
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = BANK / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    rows = []
    for key, (target, length, fade_out_s) in SPECS.items():
        excerpt = cut[:round(length * SR)]
        count = len(excerpt)
        loudness = max_rms(excerpt, .050)
        peak = max(abs(v) for v in excerpt)
        gain = min(10 ** (target / 20) / max(loudness, 1e-9), 10 ** (-1 / 20) / max(peak, 1e-9))
        fade_in, fade_out = round(.002 * SR), min(round(fade_out_s * SR), count // 3)
        pcm = array("h")
        for i in range(count):
            edge = min(1.0, i / fade_in, (count - 1 - i) / fade_out)
            pcm.append(round(max(-1.0, min(1.0, excerpt[i] * gain * edge)) * 32767))
        if sys.byteorder != "little":
            pcm.byteswap()
        target_path = OUT / f"{key}.wav"
        with wave.open(str(target_path), "wb") as output:
            output.setparams((1, 2, SR, 0, "NONE", "not compressed"))
            output.writeframes(pcm.tobytes())
        old = manifest["clips"].get(key, {})
        manifest["clips"][key] = {
            "files": [f"../hit-bloody-blade/{key}.wav"],
            "bus": "impact",
            "pitchJitter": 0.0,
            "sourceRecording": "Freesound #323525 Bloody Blade (Kreastricon62, CC0)",
        }
        rows.append({
            "event": key, "source": archived.relative_to(ROOT).as_posix(), "sourceSha256": SOURCE_SHA,
            "rangeSeconds": [CONTACT, CONTACT + count / SR],
            "gainDb": round(20 * math.log10(gain), 4), "rms50Db": round(20 * math.log10(loudness * gain), 2),
            "peakDb": round(20 * math.log10(peak * gain), 2),
            "fadeInSeconds": fade_in / SR, "fadeOutSeconds": fade_out / SR,
            "asset": target_path.relative_to(ROOT / "assets").as_posix(),
            "sha256": sha(target_path.read_bytes()), "durationSeconds": count / SR,
            "replaces": old.get("files", []),
        })
        print(f"Prepared {key}: {count / SR:.3f}s, gain {20 * math.log10(gain):+.1f} dB, "
              f"rms50 {20 * math.log10(loudness * gain):.1f} dB, peak {20 * math.log10(peak * gain):.1f} dB", flush=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    report = {
        "method": "Native 44.1kHz mono PCM WAV; 35 Hz high-pass (x2) for the DC offset, cut at the contact, gain and edge fades only",
        "pitchChanges": False, "synthesizedLayers": False, "layered": False,
        "license": "CC0 1.0 (https://freesound.org/people/Kreastricon62/sounds/323525/)",
        "clips": rows,
    }
    (OUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
