extends RefCounted
## FrameBaker durationTicks are source-fps ticks; old frames occupy one tick.
static func duration_ticks(frame: Dictionary) -> float:
	var value: Variant = frame.get("durationTicks", 1.0)
	if not (value is float or value is int):
		return 1.0
	var ticks := float(value)
	return ticks if is_finite(ticks) and ticks > 0.0 else 1.0

static func ticks_before(frames: Array, boundary: int) -> float:
	var ticks := 0.0
	for i in mini(maxi(boundary, 0), frames.size()):
		ticks += duration_ticks(frames[i])
	return ticks

## Nonlooping clips return -1 after exhaustion unless the caller requests a held pose.
static func frame_at(clip: Dictionary, seconds: float, fps: float = -1.0, hold_last: bool = true, allow_loop: bool = true) -> int:
	var frames: Array = clip.get("frames", [])
	if frames.is_empty():
		return -1
	var ticks := maxf(seconds, 0.0) * (float(clip.get("fps", 24.0)) if fps < 0.0 else fps)
	var total := ticks_before(frames, frames.size())
	if allow_loop and bool(clip.get("loop", false)):
		var loop_start := clampi(int(clip.get("loopFrame", 0)), 0, frames.size() - 1)
		var before := ticks_before(frames, loop_start)
		if ticks >= total:
			ticks = before + fposmod(ticks - before, total - before)
	elif ticks >= total - 0.0000001:
		return frames.size() - 1 if hold_last else -1
	var end := 0.0
	for i in frames.size():
		end += duration_ticks(frames[i])
		if ticks < end - 0.0000001:
			return i
	return frames.size() - 1 if hold_last else -1
