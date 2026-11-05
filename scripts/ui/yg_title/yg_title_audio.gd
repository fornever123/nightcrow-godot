extends Node
## [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
##
## 首页声音：网页版用 WebAudio 现场合成，这里改成启动时合成成 WAV 再播放
## （雨声床 / 出刀 / 选择 / 确认 / 拒绝 / 雨珠坠落 / 悬珠触碰）。
## 音量跟着 sim 的状态走，和网页版 update() 里的 rain / still / drone 目标一致。
##
## 删除方法：见 docs/YG-首页断光-删除清单.md（删掉本文件即可，其余代码会跳过声音）。

const RATE := 22050

var sim: RefCounted

var _rain: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _streams := {}
var _rain_gain := 0.0
var muted := false


func setup(s: RefCounted) -> void:
	sim = s
	_build_streams()
	_rain = AudioStreamPlayer.new()
	_rain.stream = _streams["rain"]
	_rain.volume_db = -60.0
	add_child(_rain)
	_rain.play()
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func _process(delta: float) -> void:
	if sim == null or _rain == null:
		return
	var target := 0.0
	match sim.state:
		"intro":
			var fr := 0.0
			if sim.it >= float(sim.TL["freeze_a"]):
				fr = clampf((sim.it - float(sim.TL["freeze_a"])) / (float(sim.TL["freeze_b"]) - float(sim.TL["freeze_a"])), 0.0, 1.0)
			target = (1.0 - fr) * 0.55
			if sim.cut_done:
				target = 0.5
		"leave", "exit":
			target = 0.5 * (1.0 - sim.fin_fade)
		"card":
			target = 0.0
		_:
			target = 0.5 * float(sim.rain_percent) / 100.0 + 0.06
	if muted:
		target = 0.0
	var vol: float = float(sim.volume) / 100.0
	_rain_gain = lerpf(_rain_gain, target * vol, clampf(delta * 1.5, 0.0, 1.0))
	_rain.volume_db = -60.0 if _rain_gain <= 0.001 else linear_to_db(_rain_gain * 0.5)


func play(name: String) -> void:
	if muted or not _streams.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = linear_to_db(clampf(float(sim.volume) / 100.0, 0.0, 1.0) * 0.9)
			p.play()
			return


func toggle_mute() -> void:
	muted = not muted


# ---------------------------------------------------------------- 合成
func _build_streams() -> void:
	_streams["rain"] = _wav(_rain_loop())
	_streams["slash"] = _wav(_slash())
	_streams["slash_big"] = _wav(_slash_big())
	_streams["tick"] = _wav(_tick())
	_streams["confirm"] = _wav(_confirm())
	_streams["deny"] = _wav(_deny())
	_streams["drip"] = _wav(_drip())
	_streams["touch"] = _wav(_touch())


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	w.data = bytes
	if w is AudioStreamWAV:
		w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return w


func _rain_loop() -> PackedFloat32Array:
	var n := RATE * 3
	var out := PackedFloat32Array()
	out.resize(n)
	var s1 := 0.0
	var s2 := 0.0
	for i in n:
		var w := randf() * 2.0 - 1.0
		s1 += 0.33 * (w - s1)
		s2 += 0.02 * (s1 - s2)
		var y := (s1 - s2) * 0.55
		# 首尾各 0.15 秒交叉淡化，接成循环不炸
		out[i] = y
	var fade := int(RATE * 0.15)
	for i in fade:
		var t := float(i) / fade
		out[i] = out[i] * t + out[n - fade + i] * (1.0 - t)
	return out


func _slash() -> PackedFloat32Array:
	var dur := 0.22
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 26.0)
		var w := randf() * 2.0 - 1.0
		lp += 0.5 * (w - lp)
		var y := (w - lp * 0.6) * env * 0.5
		y += sin(TAU * 1210.0 * t) * env * 0.05
		y += sin(TAU * 2437.0 * t) * env * 0.03
		out[i] = y
	return out


func _slash_big() -> PackedFloat32Array:
	var dur := 0.55
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 9.0)
		var w := randf() * 2.0 - 1.0
		lp += 0.35 * (w - lp)
		var y := (w - lp * 0.5) * env * 0.7
		y += sin(TAU * (95.0 - t * 60.0) * t) * exp(-t * 4.0) * 0.35
		out[i] = y
	return out


func _tick() -> PackedFloat32Array:
	var n := int(RATE * 0.07)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 2650.0 * t) * exp(-t * 45.0) * 0.12
	return out


func _confirm() -> PackedFloat32Array:
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 1580.0 * t) * exp(-t * 9.0) * 0.12 + sin(TAU * 2370.0 * t) * exp(-t * 11.0) * 0.08
	return out


func _deny() -> PackedFloat32Array:
	var n := int(RATE * 0.26)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * (130.0 - t * 40.0) * t) * exp(-t * 14.0) * 0.4
	return out


func _drip() -> PackedFloat32Array:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 2600.0 - t * 1400.0
		out[i] = sin(TAU * f * t) * exp(-t * 13.0) * 0.16
	return out


func _touch() -> PackedFloat32Array:
	var n := int(RATE * 0.18)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 3100.0 * t) * exp(-t * 26.0) * 0.09
	return out
