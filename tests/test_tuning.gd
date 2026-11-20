extends SceneTree
## 修改器的游戏端：tuning.json 叠加、敌人和波次搬进数据文件后默认值不变、清单里每个旋钮都真的改到游戏。
const Tuning := preload("res://scripts/core/tuning.gd")
const Encounters := preload("res://scripts/core/encounters.gd")
const Config := preload("res://scripts/core/configuration.gd")
const Factory := preload("res://scripts/night/player_factory.gd")
const Shade := preload("res://scripts/night/shade.gd")
const RainStreet := preload("res://scripts/night/rain_street.gd")
const TRIAL := "res://scenes/rain_trial.tscn"
const CATALOG := "res://tools/modifier/catalog.json"

## 搬数据之前 shade.gd 里的 KINDS 原样，用来核对一项都没变（值和类型）。
const OLD_KINDS := {
	Shade.Kind.GRUNT: {"name": "影卒", "hp": 90.0, "poise": 40.0, "half_w": 24.0, "half_h": 60.0, "speed": 230.0,
		"range": 132.0, "windup": 16, "strike": 6, "recover": 18, "damage": 8.0, "knock": 260.0,
		"cool_min": 25, "cool_max": 60, "stun": 60, "armor": false, "lunge": 300.0,
		"weight": 1.0, "guard": 0.2, "roll": 0.15, "guard_frames": 22, "down": 24, "ranged": false},
	Shade.Kind.BRUTE: {"name": "甲影", "hp": 220.0, "poise": 110.0, "half_w": 36.0, "half_h": 76.0, "speed": 120.0,
		"range": 175.0, "windup": 26, "strike": 8, "recover": 30, "damage": 15.0, "knock": 420.0,
		"cool_min": 45, "cool_max": 90, "stun": 80, "armor": true, "lunge": 200.0,
		"weight": 0.6, "guard": 0.35, "roll": 0.0, "guard_frames": 34, "down": 20, "ranged": false},
	Shade.Kind.ARCHER: {"name": "影弓", "hp": 70.0, "poise": 34.0, "half_w": 22.0, "half_h": 58.0, "speed": 210.0,
		"range": 760.0, "windup": 24, "strike": 6, "recover": 20, "damage": 9.0, "knock": 300.0,
		"cool_min": 50, "cool_max": 100, "stun": 50, "armor": false, "lunge": 0.0,
		"weight": 1.1, "guard": 0.0, "roll": 0.4, "guard_frames": 0, "down": 24, "ranged": true,
		"keep_min": 430.0, "keep_max": 700.0},
	Shade.Kind.BOMBER: {"name": "影爆", "hp": 80.0, "poise": 36.0, "half_w": 26.0, "half_h": 56.0, "speed": 170.0,
		"range": 640.0, "windup": 28, "strike": 6, "recover": 24, "damage": 14.0, "knock": 560.0,
		"cool_min": 70, "cool_max": 120, "stun": 50, "armor": false, "lunge": 0.0,
		"weight": 1.15, "guard": 0.0, "roll": 0.2, "guard_frames": 0, "down": 24, "ranged": true,
		"keep_min": 300.0, "keep_max": 600.0},
}
const G := Shade.Kind.GRUNT
const B := Shade.Kind.BRUTE
const A := Shade.Kind.ARCHER
const X := Shade.Kind.BOMBER
## 搬数据之前 rain_street.gd 里的 WAVES 原样。
const OLD_WAVES: Array = [
	[
		{"label": "雨中影卒", "spawns": [G, G, G], "max_attackers": 2},
		{"label": "楼上的冷箭", "spawns": [G, A, A, G], "reinforce": [G, G], "reinforce_at": 2, "max_attackers": 2},
	],
	[
		{"label": "甲影过桥", "spawns": [B, G, A], "max_attackers": 2},
		{"label": "桥上影爆", "spawns": [X, G, A, X], "reinforce": [B], "reinforce_at": 2, "max_attackers": 2},
	],
	[
		{"label": "影潮上岸", "spawns": [G, G, B, A], "max_attackers": 2},
		{"label": "四面八方", "spawns": [B, A, X, G, A], "reinforce": [G, X, G], "reinforce_at": 3, "max_attackers": 3},
	],
]
## 这几招的这一段动画时长为 0，界面上显示“这招没有这一段”，改了不会有变化。
const NO_SEGMENT := ["air_plunge/startup", "air_plunge/recovery", "air_light_2/recovery", "air_light_3/startup", "ranged_1/tail"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func run() -> void:
	test_apply_values()
	test_defaults_unchanged()
	test_disabled_without_opt_in()
	await test_moves_and_player_knobs()
	test_enemy_knobs()
	await test_stage_knobs()
	await test_scene_overrides()
	Tuning.test_values = {}
	Shade.KINDS = Encounters.kinds(Shade.KIND_IDS)
	print("TUNING_TESTS: ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


func test_apply_values() -> void:
	var data := {"a": {"b": 1.0}, "moves": [{"id": "x", "damage": 2.0, "box": {"w": 3.0}}], "list": [1, 2]}
	Tuning.apply_values("doc", data, {
		"doc/a/b": 5.0,
		"doc/moves/x/damage": 6.0,
		"doc/moves/x/box/w": 7.0,
		"doc/moves/x/newKey": 8.0,
		"doc/list": [9],
		"other/a/b": 100.0,
		"doc/moves/nobody/damage": 100.0,
		"doc/a/b/c": 100.0,
	})
	check(data.a.b == 5.0, "按键写入")
	check(data.moves[0].damage == 6.0, "数组按 id 写入")
	check(data.moves[0].box.w == 7.0, "数组里继续走嵌套键")
	check(data.moves[0].newKey == 8.0, "缺的最后一段能新建")
	check(data.list == [9], "整个数组替换")
	check(data.moves.size() == 1, "找不到 id 时跳过，不新建元素")


func same_typed(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not same_typed(a[k], b[k]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same_typed(a[i], b[i]):
				return false
		return true
	return a == b


func test_defaults_unchanged() -> void:
	check(same_typed(Shade.KINDS, OLD_KINDS), "KINDS 的键、值、类型和搬之前完全相同")
	check(same_typed(Encounters.waves(Shade.KIND_IDS), OLD_WAVES), "波次的值和类型和搬之前完全相同")
	var rules := Encounters.rules()
	check(int(rules.parryWindow) == 12 and is_equal_approx(rules.waveHeal, 25.0) and is_equal_approx(rules.roundHpMul, 1.2)
			and is_equal_approx(rules.ultGainHit, 0.8) and is_equal_approx(rules.ultGainHurt, 1.2), "规则默认值和原常量相同")


func test_disabled_without_opt_in() -> void:
	# runtests 用无头启动，这里必须读不到 tuning.json，测试才看得到默认值。
	check(not Tuning.enabled(), "无头测试不叠加")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.PATH))
	check(same_typed(Config.read(), raw), "没有开启时 Config.read 就是原始 battle.json")


## 把对象上的脚本变量逐层展开成文字，用来判断改动有没有落到对象上。节点和贴图这类引用不展开（每次搭建都不是同一个）。
func snapshot(o: Object) -> String:
	return JSON.stringify(flatten(o), "", true)


func flatten(v: Variant, depth := 0) -> Variant:
	if depth > 6:
		return "..."
	if v == null:
		return "null"
	if v is Object:
		if v is Node and depth > 0:
			return "<node>"
		if v is Texture2D or v is Script or v is PackedScene:
			return "<ref>"
		var out := {}
		for p in v.get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				out[p.name] = flatten(v.get(p.name), depth + 1)
		return out
	if v is Array:
		var list := []
		for e in v:
			list.append(flatten(e, depth + 1))
		return list
	if v is Dictionary:
		var out := {}
		for k in v:
			out[str(k)] = flatten(v[k], depth + 1)
		return out
	return str(v)


func bumped(value: Variant) -> Variant:
	if value is bool:
		return not value
	return float(value) * 2.0 + 7.0


## 展开清单里招式页的每一项，得到 [路径, 值, 显示名]。
func move_cases(catalog: Dictionary, battle: Dictionary) -> Array:
	var page: Dictionary = {}
	for p in catalog.pages:
		if p.get("template", "") == "moves":
			page = p
	var sources := {}
	for m in battle.moves:
		sources[m.id] = m
	var cases: Array = []
	for mv in page.moves:
		for section in page.sections:
			if not allowed(section, mv.id):
				continue
			for item in section.items:
				if not allowed(item, mv.id) or (item.get("excludeBurst", false) and mv.get("burst", false)):
					continue
				var source: Dictionary = sources[mv.id]
				if item.has("phase"):
					if NO_SEGMENT.has("%s/%s" % [mv.id, item.phase]):
						continue
					var key: String = "%sSpeed" % item.phase
					cases.append(["battle/moves/%s/%s" % [mv.id, key], float(source.get(key, source.get("recoverySpeed", 1.0) if item.phase == "tail" else 1.0)) * 0.5 + 0.01, "%s / %s" % [mv.label, item.label]])
					continue
				var at: Variant = source
				for part in String(item.key).split("/"):
					at = at.get(part, null) if at is Dictionary else null
				if at == null:
					at = item.get("default")
				if at == null:
					continue
				cases.append(["battle/moves/%s/%s" % [mv.id, item.key], bumped(at), "%s / %s" % [mv.label, item.label]])
	return cases


func allowed(rule: Dictionary, id: String) -> bool:
	if rule.has("only") and not rule.only.has(id):
		return false
	if rule.has("exclude") and rule.exclude.has(id):
		return false
	return true


func catalog_items(catalog: Dictionary, prefix: String) -> Array:
	var items: Array = []
	for p in catalog.pages:
		for section in p.get("sections", []):
			for item in section.items:
				if item.has("path") and String(item.path).begins_with(prefix):
					items.append(item)
	return items


func resolve(data: Dictionary, path: String) -> Variant:
	var at: Variant = data
	var parts := path.split("/")
	for i in range(1, parts.size()):
		if at is Array:
			var found: Variant = null
			for e in at:
				if e is Dictionary and String(e.get("id", "")) == parts[i]:
					found = e
			at = found
		elif at is Dictionary:
			at = at.get(parts[i], null)
		else:
			return null
	return at


func test_moves_and_player_knobs() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	var battle: Dictionary = Config.read()
	check(not move_cases(catalog, battle).is_empty(), "清单里有招式项")
	var base_moves: Dictionary = Config.moves(battle)
	var base_snap := {}
	for id in base_moves:
		base_snap[id] = snapshot(base_moves[id])
	for c in move_cases(catalog, battle):
		var data: Dictionary = Tuning.apply_values("battle", battle.duplicate(true), {c[0]: c[1]})
		if String(c[0]).contains("/projectile/"):
			continue   # 远射的飞行参数由 player_factory 交给玩家，下面搭玩家时检查
		var moved: Dictionary = Config.moves(data)
		var id: String = String(c[0]).split("/")[2]
		check(snapshot(moved[id]) != base_snap[id], "招式旋钮无效：%s（%s）" % [c[2], c[0]])

	# 主角：用 player_factory 真的搭一个玩家。sprite/guard 是出招时再读 meta，单独比。
	Factory.register_input()
	var base_player := Factory.build(battle, base_moves, Vector2.ZERO)
	var base_props := snapshot(base_player)
	var again := Factory.build(battle, Config.moves(battle), Vector2.ZERO)
	var again_props := snapshot(again)
	check(again_props == base_props, "对照：什么都不改，两次搭出来的玩家要一样")
	if again_props != base_props:
		print("对照差异：", first_difference(base_props, again_props))
	again.free()
	for key in ["speed", "life"]:
		var path := "battle/moves/ranged_1/projectile/%s" % key
		var data: Dictionary = Tuning.apply_values("battle", battle.duplicate(true), {path: 123.0})
		var built := Factory.build(data, Config.moves(data), Vector2.ZERO)
		check(snapshot(built) != base_props, "远射旋钮没到玩家：%s" % path)
		built.free()
	for prefix in ["battle/characters/player/", "battle/runtime/"]:
		for item in catalog_items(catalog, prefix):
			var path: String = item.path
			var value: Variant = bumped(resolve(battle, path))
			var data: Dictionary = Tuning.apply_values("battle", battle.duplicate(true), {path: value})
			var built := Factory.build(data, Config.moves(data), Vector2.ZERO)
			if path.contains("/sprite/guard/"):
				var key := path.get_file()
				var guard: Dictionary = (built.get_meta("character", {}) as Dictionary).get("sprite", {}).get("guard", {})
				check(is_equal_approx(float(guard.get(key, -1.0)), float(value)), "格挡旋钮没进玩家数据：%s" % path)
			else:
				check(snapshot(built) != base_props, "主角旋钮无效：%s（%s）" % [item.label, path])
			built.free()
	base_player.free()
	await process_frame


func first_difference(a: String, b: String) -> String:
	for i in mini(a.length(), b.length()):
		if a[i] != b[i]:
			return "%s ⇄ %s" % [a.substr(maxi(i - 60, 0), 120), b.substr(maxi(i - 60, 0), 120)]
	return "长度不同"


func test_enemy_knobs() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	var page: Dictionary = {}
	for p in catalog.pages:
		if p.get("template", "") == "enemies":
			page = p
	for kind in page.kinds:
		for section in page.sections:
			for item in section.items:
				if not allowed(item, kind.id):
					continue
				var enum_id: int = Shade.KIND_IDS[kind.id]
				var before: Variant = OLD_KINDS[enum_id].get(item.key)
				check(before != null, "敌人旋钮在默认数据里找不到：%s/%s" % [kind.id, item.key])
				if before == null:
					continue
				var value: Variant = (not before) if before is bool else float(before) * 2.0 + 7.0
				Tuning.test_values = {"encounters/kinds/%s/%s" % [kind.id, item.key]: value}
				var after: Variant = Encounters.kinds(Shade.KIND_IDS)[enum_id][item.key]
				check(after != before, "敌人旋钮无效：%s / %s" % [kind.label, item.label])
				check(typeof(after) == typeof(before), "敌人旋钮类型变了：%s / %s" % [kind.label, item.label])
	Tuning.test_values = {}


func test_stage_knobs() -> void:
	# 整关实例化一次，确认全局项和规则真的到了舞台、镜头、玩家上。
	Tuning.test_values = {
		"battle/feedback/hitstopMultiplier": 1.5,
		"battle/feedback/shakeMultiplier": 2.5,
		"battle/feedback/squashStrength": 0.9,
		"battle/feedback/parryHitstop": 0.4,
		"battle/feedback/effectsEnabled": false,
		"battle/ui/showDamageNumbers": false,
		"battle/ui/showMoveHints": false,
		"battle/camera/maxShake": 77.0,
		"battle/camera/shakeDecay": 21.0,
		"battle/camera/followLerp": 0.5,
		"battle/camera/lookAhead": 300.0,
		"encounters/rules/parryWindow": 33,
		"encounters/rules/waveHeal": 99.0,
		"encounters/rules/ultGainHit": 3.0,
		"encounters/rules/ultGainHurt": 4.0,
		"encounters/kinds/grunt/hp": 777.0,
		"encounters/waves": [[{"label": "只有一波", "spawns": ["brute"], "max_attackers": 1}], [], []],
	}
	var stage: Node = load(TRIAL).instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	await process_frame
	var p: Node = stage.player
	check(is_equal_approx(p.hitstop_multiplier, 1.5), "顿帧总倍率到了玩家")
	check(is_equal_approx(stage.shake_mul, 2.5), "震屏总倍率到了舞台")
	check(is_equal_approx(p.squash_strength, 0.9), "主角形变强度到了玩家")
	check(p.parry_hitstop_frames == roundi(0.4 * 60 * 1.5), "弹刀顿帧到了玩家")
	check(stage.fx.enabled == false, "命中特效开关到了特效层")
	check(stage.fx.damage_numbers_enabled == false, "伤害数字开关到了特效层")
	check(stage.hud.help_visible == false, "操作提示开关到了 HUD")
	check(is_equal_approx(stage.camera.max_shake, 77.0), "震屏上限到了镜头")
	check(is_equal_approx(stage.camera.shake_decay, 21.0), "震屏回稳到了镜头")
	check(is_equal_approx(stage.camera.follow_smoothing, 0.5 * 60.0), "镜头跟随到了镜头")
	check(is_equal_approx(stage.camera.look_ahead, 300.0 / stage.zoom_level), "镜头前瞻到了镜头")
	check(stage.PARRY_WINDOW == 33 and typeof(stage.PARRY_WINDOW) == TYPE_INT, "弹刀窗口到了舞台且是 int")
	check(int(p._guard_config().get("parryWindowFrames", 0)) == 33, "弹刀窗口到了玩家")
	check(is_equal_approx(stage.WAVE_HEAL, 99.0), "清波回血到了舞台")
	check(is_equal_approx(stage.ULT_GAIN_HIT, 3.0) and is_equal_approx(stage.ULT_GAIN_HURT, 4.0), "大招能量倍率到了舞台")
	check(is_equal_approx(float(Shade.KINDS[Shade.Kind.GRUNT].hp), 777.0), "关卡开始时刷新了敌人数值")
	check(stage.round_waves[0].size() == 1 and stage.round_waves[0][0].spawns == [Shade.Kind.BRUTE], "波次改动到了舞台")
	check(stage.round_waves[0][0].max_attackers is int, "波次的出刀上限是 int")
	stage.free()
	await process_frame


func test_scene_overrides() -> void:
	# 修改器的场景页：段按名字找，默认文档里没有的 backdrop 能新建，别的路径照旧跳过。
	var data := {"sections": [{"name": "甲", "platforms": []}]}
	Tuning.apply_values("layout", data, {
		"layout/sections/甲/platforms": [[0, 10, 300, "ring"]],
		"layout/sections/乙/platforms": [[0, 10, 300, "ring"]],
		"layout/backdrop/far/scroll": 0.5,
	})
	check(data.sections[0].platforms == [[0, 10, 300, "ring"]], "数组能按 name 写入")
	check(data.sections.size() == 1, "找不到段时跳过，不新建")
	check(data.backdrop.far.scroll == 0.5, "缺的中间键会新建")

	var plain: Dictionary = RainStreet._read_layout()
	check(not plain.has("backdrop"), "默认布局没有 backdrop")
	var first := String(plain.sections[0].name)
	var image := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.save_png("user://tuning_scene_layer.png")
	Tuning.test_values = {
		"layout/sections/%s/platforms" % first: [[100, 400, 300, "ring"]],
		"layout/sections/%s/spawns" % first: [[120, 300]],
		"layout/sections/%s/lamps" % first: [[100, 580, "street", 200]],
		"layout/sections/%s/foreground" % first: [[50, "sign"]],
		"layout/sections/%s/art" % first: {"near": "user://tuning_scene_layer.png", "x0": 0, "y0": 0, "width": 100, "water_y": 665},
		"layout/backdrop/far/tex": "user://tuning_scene_layer.png",
		"layout/backdrop/far/scroll": 0.5,
		"layout/backdrop/far/top": -100,
		"layout/backdrop/sky/shift": 12,
		"layout/backdrop/rain/drops": 11,
		"layout/backdrop/rain/through": 0,
		"layout/backdrop/rain/speed": 900,
		"layout/backdrop/depth": [{"tex": "user://tuning_scene_layer.png", "scroll": 0.6, "bottom": 400}],
	}
	var layout: Dictionary = RainStreet._read_layout()
	check(layout.sections[0].platforms == [[100, 400, 300, "ring"]], "改动叠到关卡布局上")
	check(layout.sections[0].spawns == [[120, 300]], "出生点叠到关卡布局上")
	var backdrop: Node2D = RainStreet.StreetBackdrop.new()
	backdrop.layout = layout
	root.add_child(backdrop)
	check(backdrop.far_scroll == 0.5 and backdrop.far_top == -100.0, "远景参数到了背景")
	check(backdrop.sky_shift == 12.0, "天空参数到了背景")
	check(backdrop._rain.amount == 11, "雨量真的进了粒子")
	check(is_equal_approx(backdrop._rain.process_material.initial_velocity_max, 990.0), "雨速真的进了粒子")
	check(backdrop.rain_drops == 11 and backdrop.rain_through == 1 and backdrop.rain_speed == 900.0, "雨的参数到了背景，雨量至少 1")
	check(backdrop._far_tex != null and backdrop._far_tex.get_width() == 4, "没导入过的 PNG 也能当远景")
	check(backdrop._depth_rows.size() == 1 and float(backdrop._depth_rows[0].scroll) == 0.6, "背街层可增删")
	check(backdrop._art_texture(layout.sections[0].art) != null, "新成图能读到")
	backdrop.queue_free()
	await process_frame
	Tuning.test_values = {}
	var back: Node2D = RainStreet.StreetBackdrop.new()
	check(back.far_scroll == RainStreet.StreetBackdrop.FAR_SCROLL and back.rain_drops == RainStreet.StreetBackdrop.RAIN_DROPS, "不改就是原来的常量")
	back.free()
	DirAccess.remove_absolute("user://tuning_scene_layer.png")
