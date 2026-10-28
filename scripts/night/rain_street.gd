extends "res://scripts/night/night_trial.gd"
## 「雨夜河岸街」（2026-10-27，阶段一：能玩的灰盒地图）：
## 三层连通的临河街道，竞技场 4800 宽（约 2.4 屏），镜头横竖都跟，角色放大到约 110 屏幕像素。
## 战斗流程、敌人、大招、评价全部沿用 night_trial.gd，只换参数、地形布局、夜景和镜头。
## 布局数据：assets/data/rain_street_layout.json（楼层 地面 580 / 二层 300 / 三层 20 / 屋顶 -260）。
## 美术流程见对话里的五阶段计划：这张灰盒图之后会导出成结构参考图交给 GPT 照着画。

const StreetBackdrop := preload("res://scripts/night/street_backdrop.gd")
const LAYOUT_PATH := "res://assets/data/rain_street_layout.json"
const STREET_ZOOM := 0.65           ## 角色约 168 × 0.65 ≈ 110 屏幕像素
const FEET_ROW_GROUND := 560.0      ## 站在街面上时，脚在屏幕第几行（河面露一点在下面）
const FEET_ROW_UPPER := 470.0       ## 站在楼上时，脚放得高一点，上下都看得到
const SPAWN_REACH := 1500.0         ## 出生点离玩家最远多少（约 1.5 屏）

const WAVES: Array = [
	[   # ① 钟楼广场：先教近战，再教“跳上楼收拾影弓”
		{"label": "雨中影卒", "spawns": [G, G, G], "max_attackers": 2},
		{"label": "楼上的冷箭", "spawns": [G, A, A, G], "reinforce": [G, G], "reinforce_at": 2, "max_attackers": 2},
	],
	[   # ② 廊桥：甲影在地面压、影弓和影爆在桥上
		{"label": "甲影过桥", "spawns": [B, G, A], "max_attackers": 2},
		{"label": "桥上影爆", "spawns": [X, G, A, X], "reinforce": [B], "reinforce_at": 2, "max_attackers": 2},
	],
	[   # ③ 河岸石阶：高潮，楼上楼下一起来
		{"label": "影潮上岸", "spawns": [G, G, B, A], "max_attackers": 2},
		{"label": "四面八方", "spawns": [B, A, X, G, A], "reinforce": [G, X, G], "reinforce_at": 3, "max_attackers": 3},
	],
]

var layout: Dictionary = {}
var _cam_feet: float = 580.0        ## 镜头按这一层取景（站稳才更新，跳跃不晃镜头）
var _arrows: Node2D


func _init() -> void:
	layout = _read_layout()
	zoom_level = STREET_ZOOM
	arena_half = float(layout.get("arenaHalf", 2400))
	arena_spacing = float(layout.get("arenaSpacing", 6400))
	first_arena_x = START_X + 1700.0 + arena_half
	trigger_before = arena_half - 200.0          # 进竞技场 200 就合上封印
	round_waves = WAVES
	stage_title = PackedStringArray(["雨夜河岸街", "往右走 · 楼上楼下都有影子"])
	cam_y = _cam_y_for(580.0)


static func _read_layout() -> Dictionary:
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		push_error("缺少关卡布局：" + LAYOUT_PATH)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _make_terrain() -> Node2D:
	var t: Node2D = Terrain.new()
	t.sections = layout.get("sections", [])
	return t


func _make_backdrop() -> Node2D:
	var b: Node2D = StreetBackdrop.new()
	b.layout = layout
	b.first_x = first_arena_x
	b.spacing = arena_spacing
	b.actors = func() -> Array:
		var out: Array = [player]
		out.append_array(get_tree().get_nodes_in_group(&"shade"))
		return out
	return b


func _stage_ready() -> void:
	encounter.high_kinds = [A]
	encounter.spawn_reach = SPAWN_REACH
	_cam_feet = floor_y
	camera.lock_y = _cam_y_for(floor_y)
	camera.global_position.y = camera.lock_y
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	_arrows = Arrows.new()
	_arrows.stage = self
	layer.add_child(_arrows)
	_queue_hint(&"floors", "楼有三层：W/空格 跳上阳台和屋檐，S+空格 跳下去", 6.0)
	print("RAIN_STREET_READY")


## 脚站在 feet 这一层时镜头中心的世界 y
func _cam_y_for(feet: float) -> float:
	var row := FEET_ROW_GROUND if feet >= floor_y - 40.0 else FEET_ROW_UPPER
	var y := feet - (row - 360.0) / STREET_ZOOM
	return minf(y, floor_y - (FEET_ROW_GROUND - 360.0) / STREET_ZOOM)   # 不往河面下面看


func _process(delta: float) -> void:
	super(delta)
	if config.is_empty() or player == null:
		return
	# 竖直跟随：站稳了才换取景的那一层；跳得比这一层高出半屏、或者掉到下面去了，也跟上
	var feet: float = player.global_position.y + player.foot_offset
	if player.is_on_floor():
		_cam_feet = feet
	elif feet < _cam_feet - 420.0:
		_cam_feet = feet + 420.0
	elif feet > _cam_feet + 60.0:
		_cam_feet = feet
	if camera.follow_target == player:
		camera.lock_y = _cam_y_for(_cam_feet)
	if _arrows != null:
		_arrows.queue_redraw()


func _draw() -> void:
	super()
	if not debug_boxes or terrain == null:
		return
	# F1 调试：所有能站的面（单向平台 = 黄线，石阶 = 橙框）和出生点
	for p in terrain.platforms:
		draw_line(Vector2(p.x0, p.y), Vector2(p.x1, p.y), Color(1.0, 0.9, 0.2, 0.9), 4.0)
	for b in terrain.blocks:
		draw_rect(Rect2(b.x0, b.y, b.x1 - b.x0, floor_y - b.y), Color(1.0, 0.55, 0.2, 0.9), false, 3.0)
	if phase == Phase.FIGHT:
		for sp in encounter.spawn_points:
			draw_circle(sp, 14.0, Color(1.0, 0.3, 0.3, 0.8))


## 屏幕外的影：在屏幕边上画一个指向它的箭头（颜色分种类）
class Arrows extends Node2D:
	var stage

	func _draw() -> void:
		if stage == null:
			return
		var view := get_viewport_rect().size
		for s in stage.get_tree().get_nodes_in_group(&"shade"):
			if not is_instance_valid(s) or not s.is_alive():
				continue
			var p: Vector2 = (s as Node2D).get_global_transform_with_canvas().origin
			if p.x > 0.0 and p.x < view.x and p.y > 0.0 and p.y < view.y:
				continue
			var c := view * 0.5
			var d := (p - c).normalized()
			var m := 34.0
			var e := Vector2(clampf(p.x, m, view.x - m), clampf(p.y, m + 40.0, view.y - m))
			var col := Color(0.7, 0.85, 1.0)
			match int(s.kind):
				2:
					col = Color(1.0, 0.65, 0.25)   # 影弓
				3:
					col = Color(1.0, 0.35, 0.3)    # 影爆
				1:
					col = Color(0.95, 0.95, 0.95)  # 甲影
			var side := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([e + d * 18.0, e - d * 10.0 + side * 12.0, e - d * 10.0 - side * 12.0]), Color(col, 0.9))
			draw_arc(e, 20.0, 0.0, TAU, 24, Color(col, 0.35), 2.0)
