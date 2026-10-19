extends Node2D
## 大招的全屏表现（世界坐标，跟着镜头）：
##   begin()  —— 背景和地形压暗（角色、敌人不暗：暗层画在地形之上、角色之下）
##   slash()  —— 几道横贯全屏的剑气 + 一下暖白闪光，然后暗层慢慢退掉
## 颜色只用暖白 / 金 / 橙（不用紫、不用高饱和蓝）。

const VIEW := Vector2(2560.0, 1440.0)    ## 镜头 ZOOM 0.5 → 世界里一屏的大小
const CORE := Color(1.0, 0.97, 0.88)
const GLOW := Color(1.0, 0.72, 0.38)

var dark := 0.0
var dark_target := 0.0
var flash := 0.0
var slashes: Array = []        ## {y, ang, t, life, delay, w, dir}
var _dim: Node2D


func _ready() -> void:
	z_index = 20                    # 剑气画在所有东西前面（包括近景 15）
	_dim = Node2D.new()
	_dim.z_as_relative = false
	_dim.z_index = -1               # 地形 −70 之上、角色 0 之下
	add_child(_dim)
	_dim.draw.connect(_draw_dim)


func begin() -> void:
	dark_target = 1.0
	slashes.clear()


## center_y = 剑气中心高度（玩家胸口）；dir = 玩家朝向；extra_ys = 被砍中的敌人高度（各补一道）
func slash(center_y: float, dir: int, extra_ys: Array = []) -> void:
	flash = 1.0
	dark_target = 0.0
	var ys := [center_y, center_y - 70.0, center_y + 60.0]
	for y in extra_ys.slice(0, 2):     # 最多再补两道，多了一屏全是线
		ys.append(float(y))
	var i := 0
	for y in ys:
		slashes.append({"y": y, "ang": (0.035 if i % 2 == 0 else -0.05) * float(dir), "t": 0.0,
			"life": 0.34 + 0.04 * float(i % 3), "delay": 0.02 * float(i), "w": 16.0 if i == 0 else 9.0, "dir": dir})
		i += 1


func busy() -> bool:
	return dark > 0.001 or flash > 0.001 or not slashes.is_empty()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.get_screen_center_position()
	dark = move_toward(dark, dark_target, delta * (5.0 if dark_target > dark else 1.6))
	flash = maxf(0.0, flash - delta * 3.5)
	for s in slashes:
		s.t += delta
	slashes = slashes.filter(func(s): return s.t < s.delay + s.life)
	queue_redraw()
	_dim.queue_redraw()


func _draw_dim() -> void:
	if dark <= 0.001:
		return
	_dim.draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color(0.015, 0.02, 0.04, 0.62 * dark))


func _draw() -> void:
	var half := VIEW.x * 0.6
	for s in slashes:
		var t: float = s.t - s.delay
		if t < 0.0:
			continue
		var p := t / float(s.life)
		# 前 18% 从一侧扫到另一侧，之后变细淡出
		var sweep := clampf(p / 0.18, 0.0, 1.0)
		var fade := 1.0 - clampf((p - 0.18) / 0.82, 0.0, 1.0)
		var d := float(s.dir)
		var a := Vector2(-half * d, 0.0)
		var b := a.lerp(Vector2(half * d, 0.0), 1.0 - pow(1.0 - sweep, 3.0))
		var rot := Transform2D(float(s.ang), Vector2(0.0, float(s.y) - global_position.y))
		a = rot * a
		b = rot * b
		var w: float = float(s.w) * (0.35 + 0.65 * fade) * (1.0 + 0.6 * (1.0 - sweep))
		draw_line(a, b, Color(GLOW, 0.14 * fade), w * 3.6)
		draw_line(a, b, Color(GLOW, 0.4 * fade), w * 1.8)
		draw_line(a, b, Color(CORE, 0.95 * fade), w)
		# 刀尖一点亮光
		if sweep < 1.0:
			draw_circle(b, w * 1.6, Color(CORE, 0.9))
	if flash > 0.001:
		draw_rect(Rect2(-VIEW * 0.6, VIEW * 1.2), Color(1.0, 0.93, 0.78, 0.28 * flash * flash))
