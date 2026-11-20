extends Node
## 战斗音效。两套声音：
##  - 商业 3A 混合合成音效库 sfx_aaa_v5（tools/audio/make_sfx_aaa_v5.py 生成：
##    192kHz/24-bit 真实冷兵器物理母带 + 模态谐振 + 紫电裂口 FM 合成，48kHz 立体声母带），
##    按五路混音总线（Impact / Blade / Warning / Motion 侧链让路 / UI）分层输出，
##    旧版 sfx_v3 完整保留在磁盘备查；
##  - 旧的 13 个 wav（CLIPS，配置 audio.events 可替换）：音效库缺了某个事件时兜底。
## 招式 → 刀风、招式 → 命中档位都写在 battle.json 的 audio.swingByMove / audio.hitTier。
const Feel := preload("res://scripts/core/feel_scale.gd")
@export var enabled: bool = true
@export var max_voices: int = 14
const BUS_IMPACT := &"SFX_Impact"     ## 命中 / 弹刀 / 破壳 / 撞墙 / 裂口：打击核心，永不压低
const BUS_BLADE := &"SFX_Blade"       ## 主角挥刀破风 / 出鞘归鞘：挥刀声为主，独立不让路
const BUS_WARNING := &"SFX_Warning"   ## 敌招蓄力预警 / 崩弦放箭：听声辨招独立频段
const BUS_MOTION := &"SFX_Motion"     ## 脚步 / 起跳 / 轻落地：受 Impact 侧链压缩自动轻微让路
const BUS_UI := &"SFX_UI"             ## 封场钟鸣 / 破晓清音
const BUS_VOLUME_DB := {
	BUS_IMPACT: 0.0,
	BUS_BLADE: 0.0,
	BUS_WARNING: 0.0,
	BUS_MOTION: -2.0,
	BUS_UI: 0.0,
}
const BUS_BY_KEY := {
	&"hit": BUS_IMPACT,
	&"launch": BUS_IMPACT,
	&"wall": BUS_IMPACT,
	&"blade_hit": BUS_IMPACT,
	&"parry": BUS_IMPACT,
	&"shuriken_hit": BUS_IMPACT,
	&"swing": BUS_BLADE,
	&"blade_swing": BUS_BLADE,
	&"shuriken_throw": BUS_BLADE,
	&"jump": BUS_MOTION,
	&"land": BUS_MOTION,
	&"charge_start": BUS_BLADE,
	&"charge_release": BUS_IMPACT,
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
const SAME_FRAME_MAX := 2          ## 同一物理帧同一事件最多响几次（横扫打中一群不叠成爆音）
const SAME_FRAME_STEP_DB := -5.0   ## 同帧第二下压低多少
const KEY_VOICE_MAX := 3           ## 同一事件同时最多几个声音（再多掐掉最老的）
const BANK_DIR := "res://assets/audio/sfx_aaa_v5/"
const LEGACY_BANK_DIR := "res://assets/audio/sfx_v3/"
const BANK_BUS := {
	"impact": BUS_IMPACT,
	"blade": BUS_BLADE,
	"warning": BUS_WARNING,
	"motion": BUS_MOTION,
	"ui": BUS_UI,
}
## 音效库只解码一次（重开关卡 / 切训练场不再重复解码）
static var _bank_cache: Dictionary = {}
static var _bank_is_aaa_cache: bool = false
var _is_aaa_bank: bool = false
var _voices: Array[AudioStreamPlayer] = []
var _same_frame: Dictionary = {}     ## 事件 → 上次发声的物理帧
var _same_frame_n: Dictionary = {}   ## 事件 → 这一帧已响几次
var _clips: Dictionary = {}
var _trim: Dictionary = {}
var _bus: StringName = BUS_IMPACT
var _repeat_frame: Dictionary = {}
var _repeat_steps: Dictionary = {}
var _bank: Dictionary = {}          ## key → {"streams": [AudioStream], "bus": StringName, "jitter": float}
var _last_pick: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var events: Dictionary = {}
var volume: float = 1.0
var last_event: String = ""
var gain_db: Dictionary = {}        ## audio.gainDb：按事件微调音量（dB）
var swing_by_move: Dictionary = {}  ## audio.swingByMove：招式 id → 刀风事件
var hit_tier: Dictionary = {}       ## audio.hitTier：招式 id → light / heavy / finisher
var footstep_stride: float = 56.0   ## 跑多少像素响一次脚步（= 跑速 × 半个步频）
var _player: Node2D = null
var _step_dist: float = 0.0
var _was_running: bool = false
var steps_played: int = 0
var _stance_key: String = ""
var _stance_voice: AudioStreamPlayer


func configure(data: Dictionary) -> void:
	enabled = bool(data.get("enabled",true))
	volume = float(data.get("masterVolume",0.9))*float(data.get("sfxVolume",0.9))
	events = data.get("events",{})
	gain_db = data.get("gainDb", {})
	swing_by_move = data.get("swingByMove", {})
	hit_tier = data.get("hitTier", {})
	footstep_stride = float(data.get("footstepStride", footstep_stride))


func _ready() -> void:
	_ensure_buses()
	refresh_clips()
	_load_bank()


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
	if FileAccess.file_exists(absolute):
		match absolute.get_extension().to_lower():
			"wav":
				return AudioStreamWAV.load_from_file(absolute)
			"ogg":
				return AudioStreamOggVorbis.load_from_file(absolute)
			"mp3":
				return AudioStreamMP3.load_from_file(absolute)
	# Exported builds keep the imported AudioStream, not a disk WAV path.
	if ResourceLoader.exists(path):
		var loaded := ResourceLoader.load(path)
		if loaded is AudioStream:
			return loaded
	return null


func _load_bank() -> void:
	if not _bank_cache.is_empty():
		_bank = _bank_cache
		_is_aaa_bank = _bank_is_aaa_cache
		return
	var bank_dir := BANK_DIR
	var text := FileAccess.get_file_as_string(bank_dir + "manifest.json")
	if text.is_empty():
		bank_dir = LEGACY_BANK_DIR
		text = FileAccess.get_file_as_string(bank_dir + "manifest.json")
	var manifest: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not (manifest is Dictionary):
		push_warning("audio: 没有找到音效库 %smanifest.json，用旧音效" % BANK_DIR)
		return
	_is_aaa_bank = String(manifest.get("version", "")).begins_with("sfx_aaa_")
	var clips: Dictionary = manifest.get("clips", {})
	for key in clips:
		var spec: Dictionary = clips[key]
		var streams: Array = []
		for f in spec.get("files", []):
			var path := bank_dir + String(f)
			var stream: AudioStream
			if path.ends_with(".ogg.b64"):
				var raw := Marshalls.base64_to_raw(FileAccess.get_file_as_string(path).strip_edges())
				if raw.is_empty():
					continue
				stream = AudioStreamOggVorbis.load_from_buffer(raw)
			else:
				stream = _load_clip(path)
				if stream == null and ResourceLoader.exists(path):
					var loaded := ResourceLoader.load(path)
					if loaded is AudioStream:
						stream = loaded
			if stream != null:
				streams.append(stream)
		if streams.is_empty():
			push_warning("audio: 音效库 %s 读不出来" % key)
			continue
		var entry := {
			"streams": streams,
			"bus": BANK_BUS.get(String(spec.get("bus", "impact")), BUS_IMPACT),
			"jitter": float(spec.get("pitchJitter", 0.03)),
			"peak_offset": float(spec.get("peakOffsetSeconds", 0.05)),
			"pre_aligned": bool(spec.get("preAlignedSwing", false)) or spec.has("sourceVideo"),
		}
		if spec.has("sourceVideo"):
			entry["source_video"] = String(spec.sourceVideo)
		_bank[String(key)] = entry
	_bank_cache = _bank
	_bank_is_aaa_cache = _is_aaa_bank


func bank_size() -> int:
	return _bank.size()


func has_bank(key: String) -> bool:
	return _bank.has(key)


static func trim_db_for(key: StringName) -> float:
	var spec: Dictionary = CLIPS.get(key, {})
	if spec.is_empty():
		return 0.0
	return clampf(minf(float(spec["target"]) - float(spec["tr"]),
			HEADROOM_DB - float(spec["peak"])), -12.0, 0.0)


# ---------------------------------------------------------------- 玩家动作
## 刀风：玩家在判定帧前 swing_cue_lead_frames 帧发 swing_cue → 这里（刀风峰值正好对上出刀）
func play_swing_of(mv: Resource, stage: int = -1) -> void:
	if mv == null or _is_ranged(mv) or mv.is_parry_move():
		return
	var key := String(swing_by_move.get(String(mv.id), ""))
	if key.is_empty():
		return  # 受击反馈 / 弹刀反应这类“招式”不出刀风
	# Short startups may emit at frame zero rather than three frames early.
	# Seek the raw whoosh forward just enough to keep its peak at the active frame.
	var offset := 0.0
	if bool(_bank.get(key, {}).get("pre_aligned", false)):
		var cue_lead := float(_player.get("swing_cue_lead_frames")) if is_instance_valid(_player) else 3.0
		var lead := minf(float(mv.startup_frames), cue_lead) / 60.0
		offset = maxf(0.0, float(_bank[key].peak_offset) - lead)
	if not _play_bank(key, 0.0, 0.0, offset):
		play_swing(Feel.from_move(mv), stage)


func play_swing(strength: float = 0.5, stage: int = -1) -> void:
	var pitch := -0.06 + strength * 0.12
	_play_clip("swing", pitch, -1.0 + strength * 2.0)


## 冲刺斩起步的“呼”（刀风另算）
func play_dash() -> void:
	# 冲刺斩母带本身已融合瞬步破风与剃刀横掠，避免与 swing_dash 叠双层刀风。
	if bool(_bank.get("swing_dash", {}).get("pre_aligned", false)):
		return
	_play_bank("dash")


func play_jump(double_jump: bool = false) -> void:
	if not _play_bank("jump_double" if double_jump else "jump"):
		_play_clip("jump", 0.06 if double_jump else -0.03, 0.0)


func play_land(heavy: bool = false) -> void:
	if not _play_bank("land_heavy" if heavy else "land_light"):
		_play_clip("land", 0.0, 1.0)


func play_step() -> void:
	if _play_bank("step"):
		steps_played += 1


func play_charge_start() -> void:
	if _play_bank("charge_start"):
		last_event = "charge_start"
		return
	_play_clip("charge_start", 0.0, 0.0)


func play_charge_release(charged: bool) -> void:
	if _play_bank("charge_release", -0.04 if charged else 0.0, 1.5 if charged else -1.5):
		last_event = "charge_release"
		return
	_play_clip("charge_release", -0.05 if charged else 0.0,
			1.5 if charged else 0.0)


func play_ranged() -> void:
	if _play_bank("ranged_throw"):
		last_event = "shuriken_throw"
		return
	_play_clip("shuriken_throw", 0.08, 0.0)


# ---------------------------------------------------------------- 命中 / 防守
func play_hit(strength: float = 0.5, launched: bool = false) -> void:
	_play_clip("launch" if launched else "hit",
			BARE_PITCH + strength * 0.04, _impact_gain_db(strength))


func play_blade_hit(strength: float = 0.5, launched: bool = false) -> void:
	_play_clip("launch" if launched else "blade_hit", strength * 0.02, _impact_gain_db(strength))


## 弹刀（完美招架；满势阈值 >= 0.80 自动切重型大弹刀母带，保持 last_event = "parry"）
func play_parry(strength: float = 0.7) -> void:
	var key := "parry_heavy" if (strength >= 0.80 and has_bank("parry_heavy")) else "parry"
	if _play_bank(key, 0.0, lerpf(-1.8, 0.0, clampf(strength, 0.0, 1.0))):
		last_event = "parry"
		return
	_play_clip("parry", PARRY_PITCH, lerpf(-3.5, 0.0, clampf(strength, 0.0, 1.0)))


## 格挡（按住 L 挡下）
func play_block() -> void:
	if not _play_bank("block"):
		_play_clip("parry", PARRY_PITCH - 0.2, -3.0)


## 破防 / 白金凝壳崩碎「破晓」
func play_stun() -> void:
	if not _play_bank("stun"):
		_play_clip("parry", PARRY_PITCH, 0.0)


## 玩家被打
func play_hurt(strength: float = 0.5) -> void:
	if not _play_bank("hurt_heavy" if strength >= 0.6 else "hurt", 0.0, _impact_gain_db(strength)):
		play_hit(strength, false)


func play_shuriken_hit(strength: float = 0.5) -> void:
	if _play_bank("ranged_hit", 0.0, _impact_gain_db(strength)):
		last_event = "shuriken_hit"
		return
	_play_clip("shuriken_hit", strength * 0.02, _impact_gain_db(strength))


func play_wall(strength: float = 0.7) -> void:
	if not _play_bank("wall", -0.06 + strength * 0.08, _impact_gain_db(strength)):
		_play_clip("wall", strength * 0.06, _impact_gain_db(strength))


## 冲击/砸地/裂口三档智能分流：<0.45 二连微震，0.45..1.02 重砸溅水，>1.02 紫电空间裂口崩裂
func play_slam(strength: float = 1.0) -> void:
	var key := "slam"
	var db := _impact_gain_db(strength)
	if strength < 0.45 and has_bank("impact_accent_light"):
		key = "impact_accent_light"
		db = 0.0
	elif strength > 1.02 and has_bank("rift_burst"):
		key = "rift_burst"
		db = lerpf(-1.0, 0.5, clampf((strength - 1.0) / 0.3, 0.0, 1.0))
	if _play_bank(key, 0.0, db):
		last_event = "slam"
		return
	play_wall(0.9)


## 被挑飞（眩晕中挑得更高时）
func play_launch() -> void:
	_play_bank("launch")


func play_chain(level: int = 1) -> void:
	if not _play_bank("chain", 0.05 * float(clampi(level - 1, 0, 4)), 0.0):
		play_hit(0.75)


func play_shade_die() -> void:
	_play_bank("shade_die")


func play_shade_windup(heavy: bool = false) -> void:
	_play_bank("shade_windup_heavy" if heavy else "shade_windup")


func play_shade_swing(heavy: bool = false) -> void:
	_play_bank("shade_swing_heavy" if heavy else "shade_swing")


## 第四轮：炸弹爆炸
func play_bomb(strength: float = 1.0) -> void:
	if not _play_bank("bomb", 0.0, _impact_gain_db(strength)):
		play_slam(strength)


## 第四轮：影弓放箭
func play_shade_shot() -> void:
	if not _play_bank("shade_shot"):
		play_shade_swing(false)


## 第四轮：格挡被砸开 / 打回去（箭、炸弹）
func play_guard_break() -> void:
	if not _play_bank("guard_break"):
		play_stun()


func play_deflect() -> void:
	if not _play_bank("deflect"):
		play_parry(0.9)


## 第四轮：大招（起手蓄势 / 斩出）
func play_ult_start() -> void:
	if not _play_bank("ult_start"):
		play_charge_start()


func play_ult_slash() -> void:
	if not _play_bank("ult_slash"):
		play_slam(1.2)


func play_seal() -> void:
	if not _play_bank("seal"):
		_play_clip("wall", 0.0, -3.0)


func play_clear() -> void:
	_play_bank("clear")


func play_die() -> void:
	_play_bank("die")


func _impact_gain_db(strength: float) -> float:
	return lerpf(IMPACT_GAIN_MIN_DB, 0.0, clampf(strength, 0.0, 1.0))


enum ImpactKind {
	AUTO,    ## 看招式数据自己判（默认）
	BLADE,   ## 近战兵器命中
	BARE,    ## 徒手 / 身体撞（怪的攻击）
	RANGED,  ## 投掷物命中
}


## 命中档位：audio.hitTier 里写了就用写的，没写按力度分（≥0.8 终结，≥0.45 重，其余轻）
func hit_tier_of(mv: Resource) -> String:
	if mv == null:
		return "light"
	var tier := String(hit_tier.get(String(mv.id), ""))
	if not tier.is_empty():
		return tier
	var k := Feel.from_move(mv)
	return "finisher" if k >= 0.8 else ("heavy" if k >= 0.45 else "light")


func play_impact(mv: Resource, kind: ImpactKind = ImpactKind.AUTO) -> void:
	var k := Feel.from_move(mv)
	if kind == ImpactKind.AUTO:
		kind = ImpactKind.RANGED if _is_ranged(mv) else ImpactKind.BLADE
	match kind:
		ImpactKind.RANGED:
			play_shuriken_hit(k)
		ImpactKind.BARE:
			play_hurt(k)
		_:
			if not _play_bank("hit_" + hit_tier_of(mv)):
				play_blade_hit(k, _launches(mv))


func _is_ranged(mv: Resource) -> bool:
	return mv != null and mv.has_method(&"is_ranged") and bool(mv.call(&"is_ranged"))


func _launches(mv: Resource) -> bool:
	if mv == null:
		return false
	var v: Variant = mv.get(&"forces_launch")
	return bool(v) if v != null else false


# ---------------------------------------------------------------- 脚步
## 跟住玩家：地面上跑起来（不出招）按跑过的距离响脚步，起跑先垫半步。
func attach_player(p: Node2D) -> void:
	_player = p
	_step_dist = 0.0
	_was_running = false
	_stance_key = ""


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_sync_stance_audio()
	if footstep_stride <= 0.0:
		return
	var body := _player as CharacterBody2D
	var running := body != null and body.is_on_floor() and int(_player.get(&"state")) == 0 \
			and absf(body.velocity.x) > 0.45 * float(_player.get(&"speed"))
	if not running:
		_was_running = false
		return
	if not _was_running:
		_was_running = true
		_step_dist = footstep_stride * 0.6
	_step_dist += absf(body.velocity.x) * delta
	if _step_dist >= footstep_stride:
		_step_dist = fmod(_step_dist, footstep_stride)
		play_step()


## Cosmetic draw/sheathe follows the actual displayed clip, including cancellation.
func _sync_stance_audio() -> void:
	var view := _player.get_node_or_null("Visual/ActorSprite")
	if view == null:
		return
	var key := String(view.get("clip_name"))
	if key == _stance_key:
		return
	_stance_key = key
	if is_instance_valid(_stance_voice) and key != "idle":
		_stance_voice.stop()
		_release_voice(_stance_voice)
		_stance_voice = null
	if key in ["draw", "sheathe"] and _play_bank(key):
		_stance_voice = _voices.back()


# ---------------------------------------------------------------- 播放
func _play_bank(key: String, pitch: float = 0.0, volume_db: float = 0.0, offset: float = 0.0) -> bool:
	var entry: Dictionary = _bank.get(key, {})
	if entry.is_empty():
		return false
	_bus = entry["bus"]
	if not enabled or volume <= 0:
		return false
	var streams: Array = entry["streams"]
	var i := 0
	if streams.size() > 1:
		i = _rng.randi_range(0, streams.size() - 2)
		if i >= int(_last_pick.get(key, -1)):
			i += 1   # 不连续两次挑同一个变体
	_last_pick[key] = i
	last_event = key
	var jitter: float = entry["jitter"]
	var p := pitch + (_rng.randf_range(-jitter, jitter) if jitter > 0.0 else 0.0)
	if entry.has("source_video"):
		p = 0.0
	var gain := volume_db + _configured_gain_db(key) + _repeat_trim(StringName(key))
	var now := Engine.get_physics_frames()
	if int(_same_frame.get(key, -1)) == now:
		_same_frame_n[key] = int(_same_frame_n.get(key, 1)) + 1
		if int(_same_frame_n[key]) > SAME_FRAME_MAX:
			return true   # 已经响过了，再叠只会更糊更炸
		gain += SAME_FRAME_STEP_DB
	else:
		_same_frame[key] = now
		_same_frame_n[key] = 1
	_cap_key_voices(key)
	if not _play_stream(streams[i], p, gain, offset):
		return false
	_voices.back().set_meta(&"bank_key", key)
	return true


func _cap_key_voices(key: String) -> void:
	var same: Array[AudioStreamPlayer] = []
	for v in _voices:
		if is_instance_valid(v) and String(v.get_meta(&"bank_key", "")) == key:
			same.append(v)
	while same.size() >= KEY_VOICE_MAX:
		var old: AudioStreamPlayer = same.pop_front()
		old.stop()
		_release_voice(old)


func _play_clip(key: String, pitch: float = 0.0, volume_db: float = 0.0) -> bool:
	_bus = bus_for(key)
	if not enabled or volume <= 0 or not _clips.has(key):
		return false
	last_event = key
	var k := StringName(key)
	var gain := volume_db + float(_trim.get(k, 0.0)) + _repeat_trim(k)
	return _play_stream(_clips[key], pitch, gain)


func _play_stream(stream: AudioStream, pitch: float, volume_db: float, offset: float = 0.0) -> bool:
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
	voice.play(offset)
	return true


func _configured_gain_db(key: String) -> float:
	var g := float(gain_db.get(key, 0.0))
	# battle.json 旧版为拉响塑料脚步写了 {"step": 6}；sfx_aaa_v5 已完成母带响度标定，不再叠加历史补偿。
	if _is_aaa_bank and key == "step" and is_equal_approx(g, 6.0):
		return 0.0
	return g


func _ensure_buses() -> void:
	for n in BUS_VOLUME_DB.keys():
		var bus_name: StringName = n
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
		AudioServer.set_bus_volume_db(idx, float(BUS_VOLUME_DB[bus_name]))
	_ensure_motion_ducking()
	_ensure_limiter()


## 动态混音让路：当 SFX_Impact 爆发命中/弹刀/碎壳时，SFX_Motion（脚步/起跳）自动轻微瞬态让路，
## 而 SFX_Blade（挥刀破风）独立不压低，保证「挥刀声为主、打击咬合清晰、混音永不糊成一团」。
func _ensure_motion_ducking() -> void:
	var motion_idx := AudioServer.get_bus_index(BUS_MOTION)
	var impact_idx := AudioServer.get_bus_index(BUS_IMPACT)
	if motion_idx < 0 or impact_idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(motion_idx):
		if AudioServer.get_bus_effect(motion_idx, i) is AudioEffectCompressor:
			return
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 3.2
	comp.attack_us = 1500.0
	comp.release_ms = 90.0
	comp.sidechain = BUS_IMPACT
	AudioServer.add_bus_effect(motion_idx, comp)


## 总线上的硬限幅：几个重音效同一帧叠在一起（命中 + 刀风 + 下砸）时不爆音
func _ensure_limiter() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	if master < 0:
		return
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	lim.release = 0.12
	AudioServer.add_bus_effect(master, lim)


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
	_stance_key = ""
	_stance_voice = null
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
