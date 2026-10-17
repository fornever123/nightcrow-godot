extends Node
## C-drive audio mix; file overrides and volume now come from the shared modifier JSON.
const Feel := preload("res://scripts/core/feel_scale.gd")
@export var enabled: bool = true
@export var max_voices: int = 12
const BUS_IMPACT := &"SFX_Impact"   ## 命中 / 撞墙 / 击飞：打击感的核心，永不压低
const BUS_MOTION := &"SFX_Motion"   ## 跳跃 / 落地 / 挥空 / 蓄力 / 投掷：可让路
const BUS_UI := &"SFX_UI"
const BUS_VOLUME_DB := {
	BUS_IMPACT: 0.0,
	BUS_MOTION: -4.0,
	BUS_UI: 0.0,
}
const BUS_BY_KEY := {
	&"hit": BUS_IMPACT,
	&"launch": BUS_IMPACT,
	&"wall": BUS_IMPACT,
	&"blade_hit": BUS_IMPACT,
	&"parry": BUS_IMPACT,
	&"shuriken_hit": BUS_IMPACT,
	&"swing": BUS_MOTION,
	&"blade_swing": BUS_MOTION,
	&"shuriken_throw": BUS_MOTION,
	&"jump": BUS_MOTION,
	&"land": BUS_MOTION,
	&"charge_start": BUS_MOTION,
	&"charge_release": BUS_MOTION,
}
const HEADROOM_DB := -0.5
const IMPACT_GAIN_MIN_DB := -2.5
const BARE_PITCH := -0.15
const PARRY_PITCH := 0.30
const CLIPS := {
	&"blade_hit": {"file": "combat_v2/blade_crisp.wav", "tr": -12.3, "peak": -0.3, "target": -11.5},
	&"parry": {"file": "combat_v2/blade_crisp.wav", "tr": -12.3, "peak": -0.3, "target": -11.5},
	&"hit": {"file": "street_fight/hit.wav", "tr": -14.8, "peak": -0.0, "target": -11.5},
	&"shuriken_hit": {"file": "street_fight/launch.wav", "tr": -13.2, "peak": -0.0, "target": -11.5},
	&"launch": {"file": "combat_v2/launch.wav", "tr": -10.2, "peak": -0.0, "target": -11.5},
	&"wall": {"file": "combat_v2/wall.wav", "tr": -17.5, "peak": -0.0, "target": -14.0},
	&"swing": {"file": "combat_v2/swing.wav", "tr": -12.2, "peak": -6.0, "target": -19.5},
	&"blade_swing": {"file": "combat_v2/swing.wav", "tr": -12.2, "peak": -6.0, "target": -19.5},
	&"shuriken_throw": {"file": "street_fight/swing.wav", "tr": -15.2, "peak": -8.4, "target": -19.5},
	&"jump": {"file": "combat_v2/jump.wav", "tr": -18.8, "peak": -6.6, "target": -19.5},
	&"land": {"file": "combat_v2/land.wav", "tr": -20.7, "peak": -0.0, "target": -19.5},
	&"charge_start": {"file": "combat_v2/charge_start.wav", "tr": -20.9, "peak": -5.4, "target": -21.0},
	&"charge_release": {"file": "combat_v2/charge_release.wav", "tr": -12.3, "peak": -0.0, "target": -16.0},
}
const REPEAT_WINDOW_FRAMES := 10   ## 距上次发声多少物理帧内算"连续"
const REPEAT_STEP_DB := -2.5       ## 每连续一次压多少
const REPEAT_MAX_STEPS := 3        ## 最多压几档（防止密集连击把音量压没）
var _voices: Array[AudioStreamPlayer] = []
var _clips: Dictionary = {}
var _trim: Dictionary = {}
var _bus: StringName = BUS_IMPACT
var _repeat_frame: Dictionary = {}
var _repeat_steps: Dictionary = {}
var events: Dictionary = {}
var volume: float = 1.0
var last_event: String = ""
func configure(data: Dictionary) -> void:
	enabled = bool(data.get("enabled",true))
	volume = float(data.get("masterVolume",0.9))*float(data.get("sfxVolume",0.9))
	events = data.get("events",{})
func _ready() -> void:
	_ensure_buses()
	refresh_clips()
func refresh_clips() -> void:
	_clips = {}
	for key in CLIPS:
		var spec: Dictionary = CLIPS[key]
		var asset := String(events.get(String(key),""))
		var path := "res://assets/" + (asset if not asset.is_empty() else "audio/%s" % spec["file"])
		var clip := _load_clip(path)
		if clip is AudioStream:
			_clips[key] = clip
		else:
			push_warning("audio: 素材加载失败 %s" % path)
		_trim[key] = trim_db_for(key)
func _load_clip(path: String) -> AudioStream:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	match absolute.get_extension().to_lower():
		"wav": return AudioStreamWAV.load_from_file(absolute)
		"ogg": return AudioStreamOggVorbis.load_from_file(absolute)
		"mp3": return AudioStreamMP3.load_from_file(absolute)
	return null
static func trim_db_for(key: StringName) -> float:
	var spec: Dictionary = CLIPS.get(key, {})
	if spec.is_empty():
		return 0.0
	return clampf(minf(float(spec["target"]) - float(spec["tr"]),
			HEADROOM_DB - float(spec["peak"])), -12.0, 0.0)
func play_swing(strength: float = 0.5, stage: int = -1) -> void:
	var pitch := -0.06 + strength * 0.12
	_play_clip("swing", pitch, -1.0 + strength * 2.0)
func play_hit(strength: float = 0.5, launched: bool = false) -> void:
	_play_clip("launch" if launched else "hit",
			BARE_PITCH + strength * 0.04, _impact_gain_db(strength))
func play_blade_hit(strength: float = 0.5, launched: bool = false) -> void:
	_play_clip("launch" if launched else "blade_hit", strength * 0.02, _impact_gain_db(strength))
func play_parry(strength: float = 0.7) -> void:
	_play_clip("parry", PARRY_PITCH, lerpf(-3.5, 0.0, clampf(strength, 0.0, 1.0)))
func play_shuriken_hit(strength: float = 0.5) -> void:
	_play_clip("shuriken_hit", strength * 0.02, _impact_gain_db(strength))
func play_wall(strength: float = 0.7) -> void:
	_play_clip("wall", strength * 0.06, _impact_gain_db(strength))
func play_jump(double_jump: bool = false) -> void:
	_play_clip("jump", 0.06 if double_jump else -0.03, 0.0)
func play_land() -> void:
	_play_clip("land", 0.0, 1.0)
func play_charge_start() -> void:
	_play_clip("charge_start", 0.0, 0.0)
func play_charge_release(charged: bool) -> void:
	_play_clip("charge_release", -0.05 if charged else 0.0,
			1.5 if charged else 0.0)
func play_ranged() -> void:
	_play_clip("shuriken_throw", 0.08, 0.0)
func _impact_gain_db(strength: float) -> float:
	return lerpf(IMPACT_GAIN_MIN_DB, 0.0, clampf(strength, 0.0, 1.0))
enum ImpactKind {
	AUTO,    ## 看招式数据自己判（默认）
	BLADE,   ## 近战兵器命中
	BARE,    ## 徒手 / 身体撞（怪的攻击）
	RANGED,  ## 投掷物命中
}
func play_impact(mv: Resource, kind: ImpactKind = ImpactKind.AUTO) -> void:
	var k := Feel.from_move(mv)
	if kind == ImpactKind.AUTO:
		kind = ImpactKind.RANGED if _is_ranged(mv) else ImpactKind.BLADE
	match kind:
		ImpactKind.RANGED:
			play_shuriken_hit(k)
		ImpactKind.BARE:
			play_hit(k, false)
		_:
			play_blade_hit(k, _launches(mv))
func play_swing_of(mv: Resource, stage: int = -1) -> void:
	if _is_ranged(mv) or (mv != null and mv.is_parry_move()):
		return
	play_swing(Feel.from_move(mv), stage)
func _is_ranged(mv: Resource) -> bool:
	return mv != null and mv.has_method(&"is_ranged") and bool(mv.call(&"is_ranged"))
func _launches(mv: Resource) -> bool:
	if mv == null:
		return false
	var v: Variant = mv.get(&"forces_launch")
	return bool(v) if v != null else false
func _play_clip(key: String, pitch: float = 0.0, volume_db: float = 0.0) -> bool:
	_bus = bus_for(key)
	if not enabled or volume <= 0 or not _clips.has(key):
		return false
	last_event = key
	var k := StringName(key)
	var gain := volume_db + float(_trim.get(k, 0.0)) + _repeat_trim(k)
	return _play_stream(_clips[key], pitch, gain)
func _play_stream(stream: AudioStream, pitch: float, volume_db: float) -> bool:
	if not enabled or stream == null:
		return false
	_trim_voices()
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.bus = _bus
	voice.process_mode = Node.PROCESS_MODE_ALWAYS
	voice.pitch_scale = 1.0 + pitch
	voice.volume_db = volume_db + linear_to_db(maxf(volume,0.0001))
	voice.finished.connect(_release_voice.bind(voice))
	add_child(voice)
	_voices.append(voice)
	voice.play()
	return true
func _ensure_buses() -> void:
	for n in BUS_VOLUME_DB.keys():
		var bus_name: StringName = n
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
		AudioServer.set_bus_volume_db(idx, float(BUS_VOLUME_DB[bus_name]))
func bus_for(key: String) -> StringName:
	return BUS_BY_KEY.get(StringName(key), BUS_IMPACT)
func _repeat_trim(key: StringName) -> float:
	var now := Engine.get_physics_frames()
	if now - int(_repeat_frame.get(key, -999)) > REPEAT_WINDOW_FRAMES:
		_repeat_steps[key] = 0
	elif int(_repeat_steps.get(key, 0)) < REPEAT_MAX_STEPS:
		_repeat_steps[key] = int(_repeat_steps.get(key, 0)) + 1
	_repeat_frame[key] = now
	return float(_repeat_steps.get(key, 0)) * REPEAT_STEP_DB
func _exit_tree() -> void:
	for c in get_children():
		var voice := c as AudioStreamPlayer
		if voice != null:
			voice.stop()
			voice.stream = null
	_voices.clear()
	_clips.clear()
func stop_all() -> void:
	for voice in _voices.duplicate():
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
			remove_child(voice)
			voice.queue_free()
	_voices.clear()
	_repeat_frame.clear()
	_repeat_steps.clear()
	last_event = ""
func _trim_voices() -> void:
	while _voices.size() >= max_voices:
		var voice: AudioStreamPlayer = _voices.pop_front()
		if is_instance_valid(voice):
			voice.stop()
			remove_child(voice)
			voice.queue_free()
func _release_voice(voice: AudioStreamPlayer) -> void:
	_voices.erase(voice)
	if is_instance_valid(voice):
		voice.queue_free()
