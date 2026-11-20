extends Node2D
## 「错拍」试炼场（DSH 线）。
##
## 世界：雨街钟楼广场的一段。全部资源只读复用，不改原版任何文件。
## 规则见 dsh/docs/玩法-错拍.md：
##   敌人逻辑跑在前面（影身），本体是 0.6 秒前的历史；玩家砍影身，躲本体。
##   连击缩短延迟 → 0 就是「合拍」；影斑可以换「预演 / 定格」；灯光 / 阴影改延迟。

const Config := preload("res://scripts/core/configuration.gd")
const PlayerScript := preload("res://dsh/scripts/offbeat_player.gd")
const ShadeScript := preload("res://dsh/scripts/offbeat_shade.gd")
const HudScript := preload("res://dsh/scripts/offbeat_hud.gd")
const FxScript := preload("res://dsh/scripts/offbeat_fx.gd")
const AudioScript := preload("res://dsh/scripts/offbeat_audio.gd")
const LampsScript := preload("res://dsh/scripts/offbeat_lamps.gd")
const RainScript := preload("res://dsh/scripts/offbeat_rain.gd")
const VignetteScript := preload("res://dsh/scripts/offbeat_vignette.gd")

const OFFBEAT_PATH := "res://dsh/data/offbeat.json"
const NEAR_KIT := "res://assets/image/rain_street/near_plaza_kit_20261101.png"
const SKY_TEX := "res://assets/image/rain_street/sky.png"

var ground_y: float = 580.0
var bounds_left: float = -1860.0
var bounds_right: float = 1860.0

var cfg: Dictionary = {}
var ob: Dictionary = {}
var settings_delay: Dictionary = {}
var settings_umbra: Dictionary = {}

var time: float = 0.0
var delay: float = 0.6
var delay_target: float = 0.6
var combo: int = 0
var max_combo: int = 0
var hit_count: int = 0
var combo_timer: float = 0.0
var umbra: int = 0
var umbra_max: int = 5
var preview_t: float = 0.0
var freeze_t: float = 0.0
var beats_time: float = 0.0
var total_time: float = 0.0

var wave_index: int = -1
var wave_state: String = "intro"
var wave_t: float = 0.0
var wave_label: String = ""
var hint: String = ""
var hint_t: float = 0.0

var shades: Array = []
var strikes_done: Dictionary = {}
var lamps: Array = [-1264.0, -403.0, 326.0, 1573.0]

var player: Node2D
var hud: Control
var fx: Node2D
var audio: Node
var camera: Camera2D
var backdrop: Node2D
var rain_layer: Control
var vignette: Control

var _death_t: float = 0.0
var _wave_clear_t: float = 0.0
var _ended: bool = false
var _prev: Dictionary = {}
var _hitstop_until_ms: int = 0


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _ready() -> void:
	cfg = Config.read()
	ob = _read_json(OFFBEAT_PATH)
	cfg["_offbeat"] = ob
	settings_delay = ob.get("delay", {})
	settings_umbra = ob.get("umbra", {})
	ground_y = 580.0
	delay = float(settings_delay.get("base", 0.6))
	delay_target = delay
	umbra_max = int(settings_umbra.get("max", 5))

	_make_backdrop()
	_make_layers()
	_make_camera()
	_make_player()
	_make_fx()
	_make_hud()
	_make_audio()
	_start_wave(0)


func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("错拍：缺少参数文件 " + path)
		return {}
	var v: Variant = JSON.parse_string(text)
	return v if v is Dictionary else {}


# ------------------------------------------------------------------ 搭场

func _make_backdrop() -> void:
	backdrop = Node2D.new()
	backdrop.name = "Backdrop"
	backdrop.z_index = -20
	add_child(backdrop)

	var sky := Sprite2D.new()
	var sky_tex := _load_tex(SKY_TEX)
	if sky_tex != null:
		sky.texture = sky_tex
		sky.centered = true
		sky.scale = Vector2(0.9, 0.9)
		sky.position = Vector2(200, -120)
		sky.z_index = -3
		backdrop.add_child(sky)

	var kit := Sprite2D.new()
	var kit_tex := _load_tex(NEAR_KIT)
	if kit_tex != null:
		var target_w := 6447.6
		var s := target_w / float(kit_tex.get_width())
		kit.texture = kit_tex
		kit.centered = true
		kit.scale = Vector2(s, s)
		var art_x0 := -2447.0
		var art_y0 := -698.0
		kit.position = Vector2(art_x0 + target_w * 0.5, art_y0 + float(kit_tex.get_height()) * s * 0.5)
		backdrop.add_child(kit)

	# 灯（暖色光池 + 光柱），同时也是玩法上的「光区」
	var lamp_draw = LampsScript.new()
	lamp_draw.name = "Lamps"
	lamp_draw.z_index = -1
	lamp_draw.lamps = lamps
	lamp_draw.ground_y = ground_y
	backdrop.add_child(lamp_draw)


func _make_layers() -> void:
	rain_layer = RainScript.new()
	rain_layer.name = "Rain"
	rain_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rain_canvas := CanvasLayer.new()
	rain_canvas.layer = 6
	rain_canvas.add_child(rain_layer)
	add_child(rain_canvas)

	vignette = VignetteScript.new()
	vignette.name = "Vignette"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vig_canvas := CanvasLayer.new()
	vig_canvas.layer = 12
	vig_canvas.add_child(vignette)
	add_child(vig_canvas)


func _make_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(0.62, 0.62)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()


func _make_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	player.z_index = 3
	player.trial = self
	add_child(player)
	player.setup(cfg, Vector2(-120.0, ground_y))
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	player.attack_ended.connect(_on_player_attack_ended)
	player.attack_started.connect(_on_player_attack_started)


func _make_fx() -> void:
	fx = FxScript.new()
	fx.name = "Fx"
	fx.z_index = 8
	fx.trial = self
	add_child(fx)


func _make_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)
	hud = HudScript.new()
	hud.name = "Hud"
	hud.trial = self
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(hud)


func _make_audio() -> void:
	audio = AudioScript.new()
	audio.name = "Audio"
	add_child(audio)


func _load_tex(path: String) -> Texture2D:
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = ResourceLoader.load(path) as Texture2D
	if tex != null:
		return tex
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


# ------------------------------------------------------------------ 波次

func _start_wave(index: int) -> void:
	var waves: Array = ob.get("waves", [])
	if index >= waves.size():
		wave_state = "done"
		wave_label = "三拍走完"
		hint = "你追上了时间"
		hint_t = 6.0
		_ended = true
		return
	wave_index = index
	wave_state = "fight"
	wave_t = 0.0
	var w: Dictionary = waves[index]
	wave_label = String(w.get("label", "第 %d 拍" % (index + 1)))
	hint = String(w.get("hint", ""))
	hint_t = 4.5
	strikes_done.clear()
	var labels: Array = w.get("shades", ["grunt"])
	var center: float = player.position.x
	for i in labels.size():
		var side := -1 if i % 2 == 0 else 1
		var offset := 520.0 + 130.0 * float(i / 2)
		var pos := Vector2(center + side * offset, ground_y)
		_spawn_shade(String(labels[i]), pos)


func _spawn_shade(label: String, pos: Vector2) -> void:
	var s = ShadeScript.new()
	s.name = "Shade_%s_%d" % [label, shades.size()]
	s.z_index = 2
	s.trial = self
	add_child(s)
	s.setup(ob, pos, label)
	shades.append(s)


func shades_alive() -> Array:
	var out: Array = []
	for s in shades:
		if is_instance_valid(s) and not s.is_dead() and not s.dead_removed:
			out.append(s)
	return out


func _tick_waves(delta: float) -> void:
	wave_t += delta
	if wave_state == "fight":
		var alive := shades_alive()
		if alive.is_empty():
			wave_state = "clear"
			_wave_clear_t = 0.0
			hint = "拍子过去了"
			hint_t = 1.6
			if audio != null:
				audio.play("clear")
	elif wave_state == "clear":
		_wave_clear_t += delta
		if _wave_clear_t >= 1.4:
			_start_wave(wave_index + 1)


# ------------------------------------------------------------------ 主循环

func _physics_process(delta: float) -> void:
	if Time.get_ticks_msec() < _hitstop_until_ms:
		Engine.time_scale = 0.18
	else:
		Engine.time_scale = 1.0
	time += delta
	total_time += delta
	if hint_t > 0.0:
		hint_t = maxf(0.0, hint_t - delta)
	_tick_skills()
	_tick_light()
	_tick_delay(delta)

	if wave_state == "fight" or wave_state == "clear":
		var alive := shades_alive()
		if freeze_t > 0.0:
			freeze_t = maxf(0.0, freeze_t - delta)
		else:
			for s in alive:
				s.tick(delta, player.position, delay)
		_resolve_enemy_attacks()

	_tick_waves(delta)
	_tick_camera(delta)
	if fx != null:
		fx.queue_redraw()


func _tick_camera(_delta: float) -> void:
	if camera == null or player == null:
		return
	var target_x := clampf(player.position.x, -800.0, 800.0)
	var target_y := clampf(player.position.y - 190.0, 150.0, 430.0)
	camera.position = camera.position.lerp(Vector2(target_x, target_y), 0.12)


func _tick_light() -> void:
	var lit := false
	for lamp_x in lamps:
		if absf(player.position.x - float(lamp_x)) < 250.0:
			lit = true
			break
	player.in_light = lit and player.position.y > ground_y - 30.0
	player.in_shadow = not player.in_light


func _tick_delay(delta: float) -> void:
	var base := float(settings_delay.get("base", 0.6))
	var target := base
	if player.in_light:
		target += float(settings_delay.get("lightOffset", -0.12))
	elif player.in_shadow:
		target += float(settings_delay.get("shadowOffset", 0.12))
	target = clampf(target, 0.0, 1.2)
	delay_target = target

	if preview_t > 0.0:
		preview_t = maxf(0.0, preview_t - delta)
		delay = 0.0
		beats_time += delta
		return
	if freeze_t > 0.0:
		beats_time += delta if delay <= 0.02 else 0.0
		return

	if combo_timer > 0.0:
		combo_timer = maxf(0.0, combo_timer - delta)
		if combo_timer <= 0.0:
			combo = 0
	else:
		combo = 0
		delay = move_toward(delay, target, delta * 2.6)
	delay = clampf(delay, 0.0, 1.2)
	if delay <= 0.02:
		beats_time += delta


func _resolve_enemy_attacks() -> void:
	var hurtbox := Rect2(player.position + Vector2(-26.0, -150.0), Vector2(52.0, 150.0))
	for s in shades_alive():
		var snap: Dictionary = s.present
		if snap.is_empty():
			continue
		if int(snap.get("state", -1)) != ShadeScript.S.STRIKE:
			continue
		var key: int = int(s.get_instance_id()) * 4096 + int(snap.get("seq", 0))
		if strikes_done.has(key):
			continue
		var box: Rect2 = s.present_attack_box(snap)
		if box.size.x > 0.0 and box.intersects(hurtbox):
			strikes_done[key] = true
			var dmg := float(s.data.get("damage", 9.0))
			player.hurt(dmg, float(snap.get("pos", s.present_pos).x))
			if audio != null:
				audio.play("hurt")
			if fx != null:
				fx.impact(player.position + Vector2(0, -80), Color(0.85, 0.24, 0.28))


func _tick_skills() -> void:
	var q := _just(KEY_Q)
	var e := _just(KEY_E)
	if q and umbra >= int(settings_umbra.get("previewCost", 1)) and preview_t <= 0.0:
		umbra -= int(settings_umbra.get("previewCost", 1))
		preview_t = float(settings_umbra.get("previewTime", 2.0))
		delay = 0.0
		combo = maxi(combo, 1)
		if fx != null:
			fx.ring(player.position + Vector2(0, -90), 150.0, Color(0.75, 0.62, 1.0))
		if audio != null:
			audio.play("parry")
		hint = "预演 · 这两秒没有延迟"
		hint_t = 1.6
	if e and umbra >= int(settings_umbra.get("freezeCost", 2)) and freeze_t <= 0.0:
		umbra -= int(settings_umbra.get("freezeCost", 2))
		freeze_t = float(settings_umbra.get("freezeTime", 1.2))
		if fx != null:
			fx.flash(Color(0.62, 0.5, 1.0), 0.35)
		if audio != null:
			audio.play("deflect")
		hint = "定格 · 全场停在影子里"
		hint_t = 1.6


func _just(key: int) -> bool:
	var now := Input.is_physical_key_pressed(key)
	var was := bool(_prev.get(key, false))
	_prev[key] = now
	return now and not was


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_F5:
			get_tree().reload_current_scene()


# ------------------------------------------------------------------ 规则回调

func beat_multiplier() -> float:
	if delay <= 0.02 or preview_t > 0.0:
		return float(ob.get("player", {}).get("beatMultiplier", 1.5))
	return 1.0


func on_shade_hit(shade: Node, damage: float, box: Rect2) -> void:
	combo += 1
	max_combo = maxi(max_combo, combo)
	hit_count += 1
	combo_timer = float(settings_delay.get("comboKeepSeconds", 2.5))
	umbra = mini(umbra_max, umbra + int(settings_umbra.get("gainPerHit", 1)))
	delay = maxf(0.0, delay - float(settings_delay.get("step", 0.1)))
	_hitstop_until_ms = Time.get_ticks_msec() + 52
	var hit_point := box.position + box.size * 0.5
	if fx != null:
		fx.hit_ghost(hit_point, shade.logic_pos + Vector2(0, -shade.present_height() * 0.55), damage, delay <= 0.02)
	if audio != null:
		audio.play("hit_light" if damage < 24.0 else "hit_heavy", -7.0)
		if shade.is_dead():
			audio.play("shade_die", -4.0)


func _on_player_attack_started(index: int) -> void:
	if audio == null:
		return
	if index >= 4:
		audio.play("dash", -8.0)
	else:
		audio.play("swing_l%d" % clampi(index, 1, 3), -5.0)


func _on_player_attack_ended(index: int, hit_any: bool) -> void:
	if not hit_any and index < 4 and fx != null:
		fx.whiff(Rect2(player.position + Vector2(-120.0, -170.0), Vector2(240.0, 170.0)))
		if hint_t <= 0.0:
			hint = "打不到本体 · 砍紫色的影身"
			hint_t = 1.4


func _on_player_damaged(_amount: float) -> void:
	combo = 0
	combo_timer = 0.0
	delay = delay_target
	if fx != null:
		fx.flash(Color(0.5, 0.08, 0.12), 0.28)


func _on_player_died() -> void:
	_death_t = 0.0
	wave_state = "dead"
	if fx != null:
		fx.flash(Color(0.05, 0.02, 0.1), 0.8)


func _process(delta: float) -> void:
	if wave_state == "dead":
		_death_t += delta
		if _death_t > 2.2:
			get_tree().reload_current_scene()


# ------------------------------------------------------------------ 给 HUD 用

func beat_ratio() -> float:
	return clampf(beats_time / maxf(0.001, total_time), 0.0, 1.0)


func delay_ratio() -> float:
	return clampf(delay / maxf(0.001, float(settings_delay.get("base", 0.6)) + 0.24), 0.0, 1.0)
