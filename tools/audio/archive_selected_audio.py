"""Archive selected videos' original AAC tracks without re-encoding."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output(args, encoding="utf-8", stderr=subprocess.PIPE)


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def probe(path):
    return json.loads(run(
        "ffprobe", "-v", "error", "-select_streams", "a", "-show_streams",
        "-show_format", "-of", "json", str(path),
    ))


def pcm_hash(path):
    return run(
        "ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0", "-vn",
        "-c:a", "pcm_s32le", "-f", "hash", "-hash", "sha256", "-",
    ).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=(
        Path(__file__).resolve().parents[2] / "art" / "selected-video-audio"
    ))
    args = parser.parse_args()
    videos = sorted(args.source.glob("*.mp4"))
    if not videos:
        raise RuntimeError("No selected MP4 files found")
    args.output.mkdir(parents=True, exist_ok=True)
    entries = []
    for source in videos:
        info = probe(source)
        tracks = info["streams"]
        if len(tracks) != 1 or tracks[0]["codec_name"] != "aac":
            raise RuntimeError(f"Expected one original AAC track: {source.name}")
        target = args.output / f"{source.stem}.m4a"
        source_hash = sha256(source)
        expected_pcm = pcm_hash(source)
        if not target.exists():
            with tempfile.TemporaryDirectory(dir=args.output) as scratch:
                temporary = Path(scratch) / target.name
                run("ffmpeg", "-v", "error", "-nostdin", "-n", "-i", str(source),
                    "-map", "0:a:0", "-vn", "-c:a", "copy", str(temporary))
                if pcm_hash(temporary) != expected_pcm:
                    raise RuntimeError(f"Decoded audio mismatch: {source.name}")
                temporary.rename(target)
        result_pcm = pcm_hash(target)
        result_info = probe(target)["streams"][0]
        if result_pcm != expected_pcm or sha256(source) != source_hash:
            raise RuntimeError(f"Audio or source integrity mismatch: {source.name}")
        original = tracks[0]
        entries.append({
            "source_video": source.name,
            "source_sha256": source_hash,
            "source_audio_stream_index": original["index"],
            "source_audio_duration_seconds": original.get("duration"),
            "audio_file": target.name,
            "audio_sha256": sha256(target),
            "audio_duration_seconds": result_info.get("duration"),
            "codec": result_info["codec_name"],
            "sample_rate": int(result_info["sample_rate"]),
            "channels": result_info["channels"],
            "decoded_pcm_s32le_sha256": result_pcm.removeprefix("SHA256="),
            "decoded_audio_matches_source": True,
        })
        print(f"Verified {target.name}: identical decoded audio", flush=True)
    manifest = {
        "purpose": "Original audio from the six selected action reference videos; archive only",
        "source_directory": str(args.source.resolve()),
        "selection": "Direct MP4 children only; excludes processed duplicates and other versions",
        "method": "ffmpeg -map 0:a:0 -vn -c:a copy (AAC in M4A; no re-encoding)",
        "verification": "Decoded PCM s32le SHA256 matches source; source file hash unchanged",
        "ffmpeg_version": run("ffmpeg", "-version").splitlines()[0],
        "files": entries,
    }
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    print(f"Archived and verified {len(entries)} audio files")


if __name__ == "__main__":
    main()
