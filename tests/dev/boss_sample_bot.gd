extends SceneTree
## 开发工具：用真实输入（不直接调受击函数）把 Boss 小样打一遍，看流程通不通、一场多久。
## 机器人的反应是写死的，只能说明规则走得通，不代表手感。
## 不加 --headless 时按 SHOT_DIR 截图：
##   engine/Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --path . --script res://tests/dev/boss_sample_bot.gd
## 环境变量 BOT_SKILL=0..1：机器人去碰刀 / 短闪的比例（默认 1）。
## BOT_MODE=mash：贴身一直按 J；BOT_MODE=edge：站在普攻刀尖一直按 J。
const Buffer := preload("res://scripts/core/input_buffer.gd")
const Shade := preload("res://scripts/night/shade.gd")
const Scene := preload("res://scripts/boss_sample/boss_sample.gd")

var stage
var p
var boss
var f := 0
var stats := {"launch": 0, "clash": 0, "final": 0, "dodged": 0, "hurt": 0, "wall": 0, "max_hits": 0, "nails": 0, "nail_hurt": 0, "yanks": 0}
var _air_frames := 0
var _fight_frames := 0
var shots := {}
var _hits := 0
var _max_combo := 0
var _air_step := 0
var _wait_land := false
var _prev_state := -1
var _section_log: Array = []
var skill := 1.0
var rng := RandomNumberGenerator.new()
var _decide_serial := -1
var _react := true
var _section_frame := 0
var _last_hp := -1.0
var _stuck := 0
var mode := ""                      ## BOT_MODE：空 = 正常打；mash = 贴身狂按 J；edge = 站刀尖狂按 J


func _initialize() -> void:
	call_deferred("run")


func frame(actions: Array[StringName], edges: Array[StringName], axis := Vector2.ZERO) -> Buffer.Frame:
	var x := Buffer.Frame.new()
	x.actions = actions
	x.pressed_this_frame = edges
	x.axis = axis
	return x


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or shots.has(name):
		return
	shots[name] = true
	var d := OS.get_environment("SHOT_DIR")
	if d == "":
		d = ProjectSettings.globalize_path("res://.runtime/shots_boss")
	DirAccess.make_dir_recursive_absolute(d)
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(d + "/%s.png" % name)
	print("SHOT ", name)


func run() -> void:
	rng.seed = 7
	var s := OS.get_environment("BOT_SKILL")
	if s != "":
		skill = float(s)
	mode = OS.get_environment("BOT_MODE")
	stage = Scene.new()
	root.add_child(stage)
	await process_frame
	p = stage.player
	boss = stage.boss
	boss.clashed.connect(func(_i: int, is_final: bool):
		stats.clash += 1
		if is_final:
			stats.final += 1
			shot("clash_final"))
	boss.dodged_through.connect(func(_p: Vector2): stats.dodged += 1)
	boss.nail_landed.connect(func(_p: Vector2):
		stats.nails += 1
		shot("nail_stuck"))
	boss.strike_landed.connect(func(_p: Vector2):
		if boss.nail_phase == boss.Nail.STUCK and boss.state == Shade.State.STRIKE:
			stats.nail_hurt += 1)
	boss.tether_slam.connect(func(d: float, _q: Vector2):
		stats.yanks += 1
		print("  拽回 伤害 %.0f 第 %d 段" % [d, stage.section + 1])
		shot("tether_slam"))
	boss.launched_high.connect(func(_p: Vector2): stats.launch += 1)
	boss.wall_slam.connect(func(_s: float, d: float, _q: Vector2):
		stats.wall += 1
		print("  撞墙 速度 %.0f 伤害 %.0f 第 %d 段 还差 %.0f" % [_s, d, stage.section + 1, stage.wall_damage_left()]))
	p.hit_confirmed.connect(func(_t, _m, _q):
		_hits += 1
		_max_combo = maxi(_max_combo, _hits))
	var last_section := 0
	while f < 60 * 240:
		await physics_frame
		f += 1
		_drive()
		if boss.intro_frames <= 0:
			_fight_frames += 1
			if boss.state == Shade.State.LAUNCHED:
				_air_frames += 1
		if stage.won or stage.phase == stage.Phase.FALLEN:
			break
		if boss.nail_phase == boss.Nail.AIM and boss.state_frames == 30:
			shot("nail_aim")
		if boss.yanking:
			shot("yank")
		if f % 120 == 0:
			print("  %3d 秒 Boss 血 %4.0f 计数 %2d 状态 %d 招 %s 玩家血 %3.0f 玩家状态 %d 距离 %.0f 高差 %.0f 场面 %d" % [f / 60, boss.hp, boss.juggle_count, boss.state, boss._string_id, p.hp, p.state, boss.global_position.x - p.global_position.x, boss.global_position.y - p.global_position.y, stage.phase])
		if f % 60 == 0:
			if boss.hp == _last_hp:
				_stuck += 1
				if _stuck == 5:
					print("STUCK boss pos %s vel %s state %d sf %d ground_y %.0f target_ok %s cool %s | p pos %s vel %s state %d floor %s | breaking %s section %d" % [
						str(boss.global_position), str(boss.velocity), boss.state, boss.state_frames, float(boss.ground_y()), str(boss._target_ok()), str(boss.get(&"cooldown")),
						str(p.global_position), str(p.velocity), p.state, str(p.is_on_floor()), str(stage.breaking), stage.section])
			else:
				_stuck = 0
			_last_hp = boss.hp
		if stage.section != last_section:
			last_section = stage.section
			_section_log.append([stage.section, int(f / 60)])
			_section_frame = f
		if f == 90:
			shot("start")
		if boss.state == Shade.State.WINDUP and boss.state_frames == 24:
			shot("red" if boss.blade_kind() == boss.Blade.RED else "white")
		if boss.state == Shade.State.LAUNCHED and boss.juggle_count == 8:
			shot("juggle")
		if stage.breaking:
			shot("break")
		if stage.section == 1 and f - _section_frame == 100:
			shot("section2")
		if stage.section == 2 and f - _section_frame == 100:
			shot("section3")
	print("BOT 结果：%s %d 秒 Boss 血 %.0f / 玩家血 %.0f 换场 %s 挨打 %d 最长连段 %d %s" % [
		"赢" if stage.won else ("输" if stage.phase == stage.Phase.FALLEN else "没打完"),
		int(stage.fight_time), boss.hp, p.hp, str(_section_log), stage.hits_taken, _max_combo, str(stats)])
	print("  打飞时间占比 %.0f%% 打完的招 %d 到第 %d 段" % [100.0 * _air_frames / maxf(_fight_frames, 1.0), boss.strings_finished, stage.section + 1])
	if stage.won:
		await create_timer(2.0, true, false, true).timeout
		await shot("result")
	else:
		await create_timer(0.6, true, false, true).timeout
	quit()


func _drive() -> void:
	var dx: float = boss.global_position.x - p.global_position.x
	var dir := 1 if dx > 0.0 else -1
	var abs_dx := absf(dx)
	var acts: Array[StringName] = []
	var edges: Array[StringName] = []
	var axis := Vector2.ZERO
	if boss.state != Shade.State.LAUNCHED:
		_hits = 0
		_air_step = 0
	if p.state == p.State.LAUNCHED or p.state == p.State.DOWN or p.state == p.State.DEAD:
		p.set_injected_frame(frame(acts, edges))
		return
	if mode != "":
		# mash：贴上去一直按 J；edge：站在普攻刀尖（约 300）一直按 J。用户 11-07 说“能直接靠普攻控死”
		var keep := 300.0 if mode == "edge" else 200.0
		if abs_dx > keep + 20.0:
			axis = Vector2(float(dir), 0.0)
		elif abs_dx < keep - 40.0 and mode == "edge":
			axis = Vector2(-float(dir), 0.0)
		if f % 8 == 0 and abs_dx < 360.0:
			p._set_facing(dir)
			acts.append(&"attack_light")
			edges.append(&"attack_light")
		p.set_injected_frame(frame(acts, edges, axis))
		return
	match boss.state:
		Shade.State.WINDUP, Shade.State.STRIKE:
			var serial: int = boss.strings_finished * 100 + boss._step
			if serial != _decide_serial:
				_decide_serial = serial
				_react = rng.randf() < skill
			var left: int = int(boss.spec.windup) - int(boss.state_frames)
			if boss.blade_kind() == boss.Blade.NAIL:
				# 钉尾：看地面标记，走开；朝 Boss 走，拔尾时正好够得着
				var nx: float = float(boss.nail_point.x) - p.global_position.x
				if _react and absf(nx) < float(boss.NAIL_RADIUS) + 60.0:
					axis = Vector2(float(dir), 0.0)
				p.set_injected_frame(frame(acts, edges, axis))
				return
			if boss.state == Shade.State.WINDUP and boss.blade_kind() == boss.Blade.RED:
				if left == 6 and _react:
					stage.dodge.request(dir)
				axis = Vector2(float(dir), 0.0) if abs_dx > 260.0 else Vector2.ZERO
			elif boss.state == Shade.State.WINDUP:
				# 白光：靠近，算好时间挥刀（出手 5 帧）
				if abs_dx > 200.0:
					axis = Vector2(float(dir), 0.0)
				if left == 6 and _react:
					p._set_facing(dir)
					acts.append(&"attack_light")
					edges.append(&"attack_light")
		Shade.State.RECOVER, Shade.State.IDLE, Shade.State.APPROACH, Shade.State.HITSTUN, Shade.State.DOWN:
			if abs_dx > 190.0:
				axis = Vector2(float(dir), 0.0)
			elif f % 10 == 0 and p.is_on_floor():
				# 贴身就挑飞
				p._set_facing(dir)
				acts.append_array([&"aim_up", &"jump", &"attack_light"] as Array[StringName])
				edges.append_array([&"aim_up", &"jump", &"attack_light"] as Array[StringName])
				axis = Vector2(0.0, -1.0)
		Shade.State.LAUNCHED:
			# 追上去空连；连够了往前打飞
			var dy: float = boss.global_position.y - p.global_position.y
			var near_ground: bool = float(boss.ground_y()) - float(boss.position.y) < 60.0
			if abs_dx > 150.0:
				axis.x = float(dir)
			if dy < -70.0 and f % 12 == 0:
				acts.append(&"jump")
				edges.append(&"jump")
			if f % 11 == 0 and abs_dx < 260.0 and absf(dy) < 190.0:
				acts.append(&"attack_light")
				edges.append(&"attack_light")
				_air_step += 1
				p._set_facing(dir)
				var want_drive: bool = (boss.air_left() < 0.3 or near_ground or boss.nail_phase == boss.Nail.STUCK) and _air_step >= 2 and not p.is_on_floor()
				if want_drive:
					axis.x = float(p.facing)
	p.set_injected_frame(frame(acts, edges, axis))
