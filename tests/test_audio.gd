extends SceneTree
## 第二轮音效（节点 12）：新音效库加载、招式 → 刀风/命中档位映射、刀风提前 3 帧发声、
## 轻/重落地、脚步按跑过的距离响、变体不连续重复、影卒蓄力/出手信号。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
var stage: Node2D
var p: CharacterBody2D
var audio: Node
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func frame(actions: Array[StringName] = [], edges: Array[StringName] = [], axis := Vector2.ZERO) -> Buffer.Frame:
	var f := Buffer.Frame.new()
	f.actions = actions; f.pressed_this_frame = edges; f.axis = axis
	return f

func step(count: int, input: Buffer.Frame = null) -> void:
	p.set_injected_frame(frame() if input == null else input)
	var target: int = p.tick_count + count
	while p.tick_count < target:
		await process_frame

func fresh() -> void:
	stage._reset()
	p.clear_input_queue()
	await step(6)

func wait_land(limit: int = 240) -> void:
	var n := 0
	await step(2)
	while not p.is_on_floor() and n < limit:
		await step(1)
		n += 1
	await step(1)

func run() -> void:
	stage = load("res://scenes/training.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	stage.config.runtime.autoReload = false
	p = stage.player
	audio = stage.audio
	await step(8)

	# ---- 音效库
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/sfx_v3/manifest.json"))
	var clips: Dictionary = manifest.get("clips", {})
	check(clips.size() >= 30, "音效清单里有 30 种以上事件（实际 %d）" % clips.size())
	var missing: Array[String] = []
	var short: Array[String] = []
	var total := 0
	for key in clips:
		if not audio.has_bank(key):
			missing.append(key)
			continue
		var streams: Array = audio._bank[key]["streams"]
		total += streams.size()
		if streams.size() != (clips[key]["files"] as Array).size():
			missing.append(key)
		for st in streams:
			if st == null or (st as AudioStream).get_length() < 0.04:
				short.append(key)
	check(missing.is_empty(), "清单里每个事件的全部变体都加载成功 %s" % [missing])
	check(short.is_empty(), "每个变体都是有效的声音 %s" % [short])
	check(total >= 60, "一共 60 个以上变体（实际 %d）" % total)
	check(audio.bank_size() == clips.size(), "bank_size 与清单一致")

	# ---- 映射表
	var swing_map: Dictionary = stage.config.audio.get("swingByMove", {})
	var bad: Array[String] = []
	for mid in swing_map:
		if not audio.has_bank(String(swing_map[mid])):
			bad.append(mid)
	for mv in [p.light_combo, p.air_combo]:
		for m in mv:
			if not swing_map.has(String(m.id)):
				bad.append(String(m.id))
	for m in [p.up_strike_move, p.air_up_move, p.dash_move, p.charge_move]:
		if m != null and not swing_map.has(String(m.id)):
			bad.append(String(m.id))
	check(bad.is_empty(), "每个挥刀招式都有对应刀风，且刀风都在音效库里 %s" % [bad])
	check(audio.hit_tier_of(stage.moves.light_1) == "light", "第一刀 → 轻命中")
	check(audio.hit_tier_of(stage.moves.light_3) == "finisher", "第三刀 → 终结命中")
	check(audio.hit_tier_of(p.dash_move) == "heavy", "冲刺斩 → 重命中")
	for tier in ["light", "heavy", "finisher"]:
		check(audio.has_bank("hit_" + tier), "命中档位 hit_%s 有声音" % tier)

	# ---- 刀风提前 3 帧
	await fresh()
	var cue := {"frame": -1, "move": null, "n": 0}
	var on_cue := func(mv: Resource, _i: int):
		cue.frame = p.move_frame; cue.move = mv; cue.n += 1
	p.swing_cue.connect(on_cue)
	await step(1, frame([&"attack_light"], [&"attack_light"]))
	var l1: Resource = stage.moves.light_1
	var n := 0
	while p.current_move == l1 and p.move_frame < l1.startup_frames + 2 and n < 60:
		await step(1)
		n += 1
	check(cue.move == l1 and cue.frame == maxi(l1.startup_frames - p.swing_cue_lead_frames, 0),
			"第一刀刀风在判定帧前 %d 帧发出（实际第 %d 帧，判定第 %d 帧）" % [p.swing_cue_lead_frames, cue.frame, l1.startup_frames])
	check(cue.n == 1, "一招只发一次刀风")
	await step(30)
	p.swing_cue.disconnect(on_cue)

	# 弹刀不出刀风
	await fresh()
	audio.last_event = ""
	await step(1, frame([&"parry"], [&"parry"]))
	await step(12, frame([&"parry"]))
	check(not audio.last_event.begins_with("swing"), "弹刀 / 格挡不出刀风（实际 %s）" % audio.last_event)
	await step(20)

	# ---- 跳跃 / 落地
	await fresh()
	await step(1, frame([&"jump"], [&"jump"]))
	check(audio.last_event == "jump", "起跳有声音（实际 %s）" % audio.last_event)
	await wait_land()
	check(audio.last_event == "land_light", "小跳落地 → 轻落地（实际 %s）" % audio.last_event)
	var hh: float = p.heavy_landing_height
	p.heavy_landing_height = 10.0
	await fresh()
	await step(1, frame([&"jump"], [&"jump"]))
	await step(10, frame([&"jump"]))
	await wait_land()
	check(audio.last_event == "land_heavy", "高处落地 → 重落地（实际 %s）" % audio.last_event)
	p.heavy_landing_height = hh

	# ---- 脚步
	await fresh()
	var s0: int = audio.steps_played
	await step(60)
	check(audio.steps_played == s0, "站着不动没有脚步声")
	var x0: float = p.position.x
	await step(60, frame([&"move_right"], [], Vector2.RIGHT))
	var dist: float = p.position.x - x0
	var steps: int = audio.steps_played - s0
	var expect := int((dist + audio.footstep_stride * 0.6) / audio.footstep_stride)
	check(steps >= expect - 1 and steps <= expect + 1, "跑 %.0fpx 响 %d 步（按步幅应约 %d 步）" % [dist, steps, expect])
	await step(30)

	# ---- 变体不连续重复
	var picks: Array[int] = []
	for i in 40:
		audio._play_bank("hit_light")
		picks.append(int(audio._last_pick["hit_light"]))
	var repeats := 0
	var seen := {}
	for i in picks.size():
		seen[picks[i]] = true
		if i > 0 and picks[i] == picks[i - 1]:
			repeats += 1
	check(repeats == 0 and seen.size() >= 2, "同一事件连续触发不会两次挑同一个变体")
	audio.stop_all()
	check(audio._voices.size() <= audio.max_voices, "同时发声数不超过上限")

	# ---- 影卒蓄力 / 出手信号
	var sh: Node = Shade.new()
	check(sh.has_signal(&"windup_started") and sh.has_signal(&"strike_started"), "影卒有蓄力 / 出手音效信号")
	sh.free()
	for key in ["shade_windup", "shade_windup_heavy", "shade_swing", "shade_swing_heavy", "shade_die", "seal", "clear", "die", "stun", "launch", "slam", "chain", "block", "parry", "hurt", "hurt_heavy", "dash", "step", "wall"]:
		if not audio.has_bank(key):
			failures.append("缺少事件 " + key)
	check(failures.is_empty() or not failures[-1].begins_with("缺少"), "夜战用到的事件全部有声音")

	print("AUDIO_TESTS: %d checks / %d failures" % [checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)
