extends Node
## 截弦 · 程序合成音效（现场生成 PCM，不新增音频文件）。
## 音色一族：纸、木、弦、印。

const RATE := 22050

var clips: Dictionary = {}
var voices: Array = []
var _idx: int = 0


func _ready() -> void:
	for i in 18:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		voices.append(p)
	_build_all()


func play(key: String, db: float = -7.0, pitch: float = 1.0) -> void:
	if not clips.has(key):
		return
	var p: AudioStreamPlayer = voices[_idx]
	_idx = (_idx + 1) % voices.size()
	p.stream = clips[key]
	p.volume_db = db
	p.pitch_scale = clampf(pitch * randf_range(0.97, 1.03), 0.55, 1.8)
	p.play()


# ------------------------------------------------------------------ 合成

func _stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return s


func _make(dur: float, freq: Callable, amp: Callable, noise_mix: float = 0.0, lp: float = 0.5) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	var filtered := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := float(freq.call(t))
		phase += f / float(RATE)
		if phase > 1.0:
			phase -= floor(phase)
		var tone := sin(phase * TAU)
		var raw := randf() * 2.0 - 1.0
		filtered = lerpf(filtered, raw, clampf(lp, 0.01, 1.0))
		var v := (tone * (1.0 - noise_mix) + filtered * noise_mix) * float(amp.call(t))
		v = clampf(v, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 30000.0))
	return _stream(bytes)


func _exp(t: float, tau: float) -> float:
	return exp(-t / maxf(0.0001, tau))


func _atk(t: float, a: float) -> float:
	return clampf(t / maxf(0.0001, a), 0.0, 1.0)


func _build_all() -> void:
	# 挥刀：干纸破风
	clips["swing"] = _make(0.16, func(t): return 900.0 - 2600.0 * t,
		func(t): return _atk(t, 0.012) * _exp(t, 0.075) * 0.55, 0.85, 0.35)
	# 挥空：更轻的纸响
	clips["whiff"] = _make(0.11, func(t): return 700.0 - 1800.0 * t,
		func(t): return _atk(t, 0.008) * _exp(t, 0.05) * 0.30, 0.95, 0.25)
	# 截断：弦崩 + 裂纸
	clips["cut"] = _make(0.30, func(t): return 2600.0 * _exp(t, 0.05) + 420.0,
		func(t): return _atk(t, 0.004) * (_exp(t, 0.09) * 0.9 + _exp(t, 0.26) * 0.25), 0.55, 0.6)
	# 朱弦被弹开：铮
	clips["bounce"] = _make(0.22, func(t): return 1500.0 + 900.0 * sin(t * 90.0),
		func(t): return _atk(t, 0.003) * _exp(t, 0.10) * 0.5, 0.45, 0.75)
	# 弦绷紧：一声细亮的「绷」
	clips["taut"] = _make(0.10, func(t): return 2200.0 - 600.0 * t,
		func(t): return _atk(t, 0.004) * _exp(t, 0.045) * 0.22, 0.15, 0.8)
	# 夺招：纸符入手
	clips["take"] = _make(0.26, func(t): return 1200.0 + 1400.0 * t,
		func(t): return _atk(t, 0.006) * _exp(t, 0.10) * 0.40, 0.35, 0.7)
	# 放招：纸裂三声
	clips["art"] = _make(0.34, func(t): return 800.0 + 2200.0 * t,
		func(t): return _atk(t, 0.01) * _exp(t, 0.14) * (0.55 + 0.35 * sin(t * 120.0)), 0.6, 0.55)
	# 落章：闷鼓 + 印
	clips["stamp"] = _make(0.55, func(t): return 120.0 * _exp(t, 0.12) + 60.0,
		func(t): return _atk(t, 0.003) * _exp(t, 0.22) * 0.9, 0.35, 0.15)
	# 受击：低闷 + 纸裂
	clips["hurt"] = _make(0.42, func(t): return 220.0 * _exp(t, 0.12) + 70.0,
		func(t): return _atk(t, 0.004) * _exp(t, 0.18) * 0.9, 0.55, 0.2)
	# 闪步：风声
	clips["dash"] = _make(0.20, func(t): return 400.0 + 300.0 * t,
		func(t): return _atk(t, 0.02) * _exp(t, 0.09) * 0.32, 0.95, 0.45)
	# 跳 / 落
	clips["jump"] = _make(0.14, func(t): return 520.0 + 700.0 * t,
		func(t): return _atk(t, 0.006) * _exp(t, 0.07) * 0.22, 0.7, 0.6)
	clips["land"] = _make(0.16, func(t): return 160.0 - 60.0 * t,
		func(t): return _atk(t, 0.004) * _exp(t, 0.06) * 0.45, 0.5, 0.15)
	# 纸片落地
	clips["paper"] = _make(0.20, func(t): return 1600.0 + 400.0 * sin(t * 40.0),
		func(t): return _atk(t, 0.01) * _exp(t, 0.07) * (0.4 + 0.4 * sin(t * 260.0)), 0.9, 0.7)
	# 折名钟
	clips["bell"] = _make(1.10, func(t): return 660.0 if t < 0.5 else 990.0,
		func(t): return _atk(t, 0.006) * _exp(t, 0.42) * 0.34, 0.08, 0.9)
	# 判官登场：锣
	clips["gong"] = _make(1.40, func(t): return 150.0 + 40.0 * sin(t * 7.0),
		func(t): return _atk(t, 0.01) * _exp(t, 0.6) * (0.55 + 0.3 * sin(t * 60.0)), 0.35, 0.12)
	# 断幕：弦齐鸣
	clips["break"] = _make(0.90, func(t): return 300.0 + 1800.0 * t,
		func(t): return _atk(t, 0.01) * _exp(t, 0.3) * 0.55, 0.45, 0.65)
	# 空弦散架
	clips["collapse"] = _make(0.60, func(t): return 240.0 - 140.0 * t,
		func(t): return _atk(t, 0.01) * _exp(t, 0.26) * 0.7, 0.8, 0.3)
	# 教学提示
	clips["hint"] = _make(0.16, func(t): return 1050.0,
		func(t): return _atk(t, 0.005) * _exp(t, 0.06) * 0.16, 0.05, 0.9)
