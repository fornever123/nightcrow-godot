extends Node2D
## 第三轮节点 17/18：多层地形 —— 单向平台（能从下面跳上去、按住 S 再按跳往下穿）+ 实心石台。
## 不做坑：地面 floor_y 一直都在，掉下来也只是回到堤岸上。
##
## 两种部件：
##   platforms  单向平台 {x0, x1, y, style}：plank 木栈道 / roof 亭子屋檐 / slab 断桥石板
##   blocks     实心石台 {x0, x1, y, style}：从顶面一直实心到地面，侧面挡路
##
## 玩家走 Godot 物理：石台 = 第 1 层实心碰撞体；平台 = ONE_WAY_LAYER 层的单向碰撞体。
## 影卒不用物理（见 shade.gd），每帧问这里：support_y() 脚下最高的面、push_out() 石台侧面挡路。
## 两边用的是同一份数据，所以玩家和敌人站的面永远一致。
##
## 画法（节点 18）：全部用代码画像素块，一格 CELL = 4 世界单位 = 屏幕 2 像素（和背景像素块一样大），
## 月亮在右上方：顶面和右侧受光，左侧和下面暗，投影偏左。地形画在背景像素化那层之后（z −70），
## 所以和角色一样清楚、不被量化，但颜色取自背景调色板附近，只略亮一点、对比略强一点。

const ONE_WAY_LAYER := 32           ## 单向平台的物理层（第 6 层；16 已被弹丸占用，2 是玩家自己）
const STEP := 6.0                   ## 脚底比面低这么多以内仍算“站在这个面上”（台阶容差）
const CELL := 4.0
const PLATFORM_THICK := 16.0

## 每一段地形 = 一处封印竞技场（中心 ±1200）+ 它后面去下一处的那段路（中心 +1200 ~ +2400）。
## x 相对封印中心；y 是世界坐标（地面 580；一层约 440，二层约 312）。
## spawns：这一处的出生点 [x, 脚底 y]，按“右、左、右、左…”交替排，敌人会站在平台上出来。
const SECTIONS := [
	{   # 第 1 处「栈道」：左右两段木栈道，中间一段更高的
		"name": "栈道",
		"blocks": [],
		"platforms": [[-760, -380, 440, "plank"], [380, 760, 440, "plank"], [-180, 180, 312, "plank"],
			[1560, 1800, 460, "slab"], [1960, 2160, 388, "plank"]],
		"spawns": [[1020, 580], [-1020, 580], [600, 440], [-600, 440], [0, 312], [880, 580], [-880, 580]],
	},
	{   # 第 2 处「石阶」：左右两座石台，中间一段悬空木台
		"name": "石阶",
		"blocks": [[-1200, -700, 472, "stone"], [620, 1200, 452, "stone"], [1700, 1900, 512, "stone"]],
		"platforms": [[-260, 260, 400, "plank"], [2040, 2240, 420, "slab"]],
		"spawns": [[1000, 452], [-1000, 472], [780, 452], [0, 400], [-860, 472], [300, 580], [-420, 580]],
	},
	{   # 第 3 处「亭子 / 断桥」：中间石台上一座亭子（亭顶能站），两边断桥石板
		"name": "亭子",
		"blocks": [[-200, 200, 488, "stone"]],
		"platforms": [[-900, -560, 440, "slab"], [560, 900, 440, "slab"], [-264, 264, 280, "roof"],
			[1600, 1880, 452, "plank"]],
		"spawns": [[1040, 580], [-1040, 580], [720, 440], [-720, 440], [0, 488], [420, 580], [-420, 580]],
	},
]

var floor_y: float = 580.0
var platforms: Array = []           ## [{x0, x1, y, style}]
var blocks: Array = []
var _built: Dictionary = {}         ## 段序号 → [节点…]


# ---------------------------------------------------------------- 搭建

static func layout(index: int) -> Dictionary:
	return SECTIONS[posmod(index, SECTIONS.size())]


## 确保第 index 段（中心 center）已经生成；已生成就什么都不做
func ensure_section(index: int, center: float) -> void:
	if _built.has(index):
		return
	var nodes: Array = []
	var lay := layout(index)
	for b in lay.blocks:
		nodes.append(add_block(center + float(b[0]), center + float(b[1]), float(b[2]), String(b[3]), index))
	for p in lay.platforms:
		nodes.append(add_platform(center + float(p[0]), center + float(p[1]), float(p[2]), String(p[3]), index))
	_built[index] = nodes


## 早于 keep_from 的段全部拆掉（走远了，省节点）
func free_sections_before(keep_from: int) -> void:
	for k in _built.keys():
		if int(k) < keep_from:
			for n in _built[k]:
				if is_instance_valid(n):
					n.queue_free()
			_built.erase(k)
	platforms = platforms.filter(func(p): return int(p.section) >= keep_from)
	blocks = blocks.filter(func(b): return int(b.section) >= keep_from)


func spawn_points(index: int, center: float) -> Array:
	var out: Array = []
	for s in layout(index).spawns:
		out.append(Vector2(center + float(s[0]), float(s[1])))
	return out


func add_platform(x0: float, x1: float, y: float, style: String = "plank", section: int = -1) -> Node2D:
	var d := {"x0": x0, "x1": x1, "y": y, "style": style, "section": section}
	platforms.append(d)
	var body := StaticBody2D.new()
	body.collision_layer = ONE_WAY_LAYER
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(x1 - x0, PLATFORM_THICK)
	cs.shape = rect
	cs.one_way_collision = true
	cs.one_way_collision_margin = 2.0
	cs.position = Vector2((x0 + x1) * 0.5, y + PLATFORM_THICK * 0.5)
	body.add_child(cs)
	var piece := Piece.new()
	piece.terrain = self
	piece.data = d
	piece.add_child(body)
	add_child(piece)
	return piece


func add_block(x0: float, x1: float, y: float, style: String = "stone", section: int = -1) -> Node2D:
	var d := {"x0": x0, "x1": x1, "y": y, "style": style, "section": section, "solid": true}
	blocks.append(d)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var bottom := floor_y + 40.0
	rect.size = Vector2(x1 - x0, bottom - y)
	cs.shape = rect
	cs.position = Vector2((x0 + x1) * 0.5, (y + bottom) * 0.5)
	body.add_child(cs)
	var piece := Piece.new()
	piece.terrain = self
	piece.data = d
	piece.add_child(body)
	add_child(piece)
	# 石台画在平台前面（亭子的柱子要立在石台上）—— 挪到最前
	move_child(piece, 0)
	return piece


# ---------------------------------------------------------------- 查询（影卒 / 影子 / 出生点 / 测试用）

## 脚下最高的面：横向和 [x−foot, x+foot] 重叠、且面不高于 feet_y − STEP。都没有就是地面。
## ignore_y：正在往下穿的那块单向平台的高度（NAN = 不忽略）
func support_y(x: float, feet_y: float, foot: float = 10.0, ignore_y: float = NAN) -> float:
	var best := floor_y
	for b in blocks:
		if x + foot > b.x0 and x - foot < b.x1 and b.y >= feet_y - STEP and b.y < best:
			best = b.y
	for p in platforms:
		if x + foot > p.x0 and x - foot < p.x1 and p.y >= feet_y - STEP and p.y < best:
			if is_finite(ignore_y) and absf(p.y - ignore_y) < 1.0:
				continue
			best = p.y
	return best


## x 处最高的面（出生、复活、测试用）
func top_at(x: float, foot: float = 10.0) -> float:
	return support_y(x, -1.0e9, foot)


## x 处实心的最高面（只看石台，不看单向平台）
func solid_top(x: float, foot: float = 10.0) -> float:
	var best := floor_y
	for b in blocks:
		if x + foot > b.x0 and x - foot < b.x1 and b.y < best:
			best = b.y
	return best


## 脚底正好踩在一块单向平台上（可以往下穿）→ 返回那块平台的高度，否则 NAN
func one_way_at(x: float, feet_y: float, foot: float = 10.0) -> float:
	var s := support_y(x, feet_y, foot)
	if absf(s - feet_y) > STEP + 1.0:
		return NAN
	for p in platforms:
		if absf(p.y - s) < 0.5 and x + foot > p.x0 and x - foot < p.x1:
			for b in blocks:
				if absf(b.y - s) < 0.5 and x + foot > b.x0 and x - foot < b.x1:
					return NAN   # 同一高度下面还有实心石台：穿不下去
			return s
	return NAN


## 石台侧面挡路：身体 [x−hw, x+hw] 和石台重叠、并且脚在台面以下 → 推出去。
## 返回 Vector2(新的 x, 撞到哪一侧)：side +1 = 石台在右边（撞右墙）、−1 = 在左边、0 = 没撞。
func push_out(x: float, hw: float, feet_y: float) -> Vector2:
	var side := 0
	for b in blocks:
		if feet_y <= b.y + STEP:
			continue
		if x + hw > b.x0 and x - hw < b.x1:
			if x < (b.x0 + b.x1) * 0.5:
				x = b.x0 - hw
				side = 1
			else:
				x = b.x1 + hw
				side = -1
	return Vector2(x, side)


## 亭子檐下灯笼的暖光照到 p 点的强度和方向（和 night_backdrop.lantern_light 同一格式：x 强度，(y,z) 指向灯笼）
const LANTERN_REACH := 300.0
func lantern_light(p: Vector2) -> Vector3:
	var best := Vector3.ZERO
	for c in get_children():
		if not (c is Piece):
			continue
		for lp in c.lantern_points():
			var d: Vector2 = lp - p
			var dist := d.length()
			var w := clampf(1.0 - dist / LANTERN_REACH, 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w) * 0.9
			if w > best.x:
				var dir := d / maxf(dist, 0.001)
				best = Vector3(w, dir.x, dir.y)
	return best


## 两点之间是不是同一层（给 AI / 冲击波用）
static func same_level(a_feet: float, b_feet: float, tol: float = 40.0) -> bool:
	return absf(a_feet - b_feet) < tol


# ---------------------------------------------------------------- 绘制

## 月光夜景配色（取自背景调色板附近，略提亮）
const C_WOOD_LIT := Color(0.64, 0.64, 0.70)
const C_WOOD := Color(0.33, 0.27, 0.28)
const C_WOOD_ALT := Color(0.29, 0.24, 0.26)
const C_WOOD_HI := Color(0.42, 0.36, 0.36)
const C_WOOD_DARK := Color(0.16, 0.14, 0.18)
const C_WOOD_DEEP := Color(0.09, 0.085, 0.12)
const C_STONE_CAP := Color(0.63, 0.67, 0.76)
const C_STONE_CAP2 := Color(0.45, 0.49, 0.59)
const C_STONE := Color(0.30, 0.33, 0.43)
const C_STONE_ALT := Color(0.27, 0.30, 0.40)
const C_STONE_HI := Color(0.36, 0.40, 0.50)
const C_STONE_DARK := Color(0.15, 0.17, 0.25)
const C_STONE_LIT := Color(0.52, 0.57, 0.68)
const C_MOSS := Color(0.24, 0.36, 0.33)
const C_MOSS_LIT := Color(0.40, 0.53, 0.45)
const C_TILE := Color(0.19, 0.22, 0.32)
const C_TILE_LIT := Color(0.40, 0.45, 0.57)
const C_RIDGE := Color(0.58, 0.62, 0.72)
const C_PILLAR := Color(0.36, 0.15, 0.15)
const C_PILLAR_LIT := Color(0.56, 0.27, 0.24)
const C_LAMP := Color(1.0, 0.66, 0.34)
const C_LAMP_HOT := Color(1.0, 0.86, 0.58)
const C_SHADOW := Color(0.01, 0.015, 0.045)


static func hash01(a: int, b: int) -> float:
	var n := (a * 374761393 + b * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


class Piece extends Node2D:
	var terrain   ## 所属的 terrain.gd（不标类型：要调它自己的函数）
	var data: Dictionary
	var _glow: Node2D

	func _ready() -> void:
		if String(data.style) == "roof":
			# 亭子檐下的两盏灯笼：暖光用叠加混合单独画（不进量化）
			_glow = Node2D.new()
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			_glow.material = m
			_glow.draw.connect(_draw_glow)
			add_child(_glow)

	func _draw() -> void:
		var x0: float = data.x0
		var x1: float = data.x1
		var y: float = data.y
		var fy: float = terrain.floor_y
		match String(data.style):
			"stone":
				_draw_block(x0, x1, y, fy)
			"slab":
				_draw_slab(x0, x1, y, fy)
			"roof":
				_draw_roof(x0, x1, y, fy)
			_:
				_draw_plank(x0, x1, y, fy)

	# 一格一格画：坐标都按 4 单位对齐
	func _c(x: float, y: float, w: float, h: float, col: Color) -> void:
		draw_rect(Rect2(snappedf(x, 4.0), snappedf(y, 4.0), snappedf(w, 4.0), snappedf(h, 4.0)), col)

	func _ground_shadow(x0: float, x1: float, fy: float, k: float) -> void:
		# 月亮在右上：投影往左偏
		_c(x0 - 20.0, fy - 4.0, x1 - x0, 8.0, Color(C_SHADOW, 0.30 * k))
		_c(x0 - 8.0, fy - 4.0, x1 - x0 - 8.0, 4.0, Color(C_SHADOW, 0.25 * k))

	# ---- 木栈道：月光照亮的顶边、木板缝、横梁、立柱到地面、斜撑 ----
	func _draw_plank(x0: float, x1: float, y: float, fy: float) -> void:
		var sd := int(x0)
		_ground_shadow(x0 + 8.0, x1 - 8.0, fy, 0.9)
		# 立柱：两端各一根，中间每 ~190 一根（12 宽：暗 / 中 / 受光三格）
		var posts: Array = [snappedf(x0 + 12.0, 4.0)]
		var n := maxi(1, int(round((x1 - x0 - 48.0) / 190.0)))
		for i in range(1, n):
			posts.append(snappedf(x0 + 12.0 + (x1 - x0 - 36.0) * float(i) / float(n), 4.0))
		posts.append(snappedf(x1 - 24.0, 4.0))
		var top := y + 20.0                      # 桥面（含横梁）底边
		var rail := snappedf(top + (fy - top) * 0.55, 4.0)
		for i in posts.size():
			var px: float = posts[i]
			if i + 1 < posts.size():
				var nx: float = posts[i + 1]
				# 中段横档
				_c(px + 12.0, rail, nx - px - 12.0, 4.0, C_WOOD_DARK)
				_c(px + 12.0, rail + 4.0, nx - px - 12.0, 4.0, Color(C_WOOD_DEEP, 0.6))
			_c(px, top, 4.0, fy - top, C_WOOD_DEEP)
			_c(px + 4.0, top, 4.0, fy - top, C_WOOD)
			_c(px + 8.0, top, 4.0, fy - top, C_WOOD_HI)
			for k in range(int(top / 4.0) + 3, int(fy / 4.0) - 2, 7):    # 木纹
				_c(px + 4.0, float(k) * 4.0, 4.0, 4.0, C_WOOD_DARK)
			# 斜撑（雀替）：柱子两侧各一道两格粗的台阶斜线，撑到桥面底下
			for side in [-1.0, 1.0]:
				if (side < 0.0 and i == 0) or (side > 0.0 and i == posts.size() - 1):
					continue
				for s in 4:
					var bx: float = (px + 12.0 + float(s) * 4.0) if side > 0.0 else (px - 4.0 - float(s) * 4.0)
					var by := top + 16.0 - float(s) * 4.0
					_c(bx, by, 4.0, 8.0, C_WOOD_DARK if s < 3 else C_WOOD)
					_c(bx, by, 4.0, 4.0, C_WOOD_ALT)
			# 柱脚石墩
			_c(px - 4.0, fy - 12.0, 20.0, 12.0, C_STONE_ALT)
			_c(px - 4.0, fy - 12.0, 20.0, 4.0, C_STONE_HI)
			_c(px + 12.0, fy - 12.0, 4.0, 12.0, C_STONE_LIT)
			# 横梁伸出桥面的梁头
			_c(px - 4.0, y + 16.0, 20.0, 4.0, C_WOOD_DARK)
		# 桥面：顶边受光 → 木板面（一块一块、缝深色）→ 下沿 → 横梁
		_c(x0 - 4.0, y, x1 - x0 + 8.0, 4.0, C_WOOD_LIT)
		var bx2 := x0 - 4.0
		var k2 := 0
		while bx2 < x1 + 4.0:
			var bl := 28.0 + 4.0 * float(int(terrain.hash01(sd, k2) * 5.0))
			bl = minf(bl, x1 + 4.0 - bx2)
			var col: Color = C_WOOD if k2 % 2 == 0 else C_WOOD_ALT
			if terrain.hash01(k2, sd) > 0.8:
				col = C_WOOD_HI
			_c(bx2, y + 4.0, bl, 8.0, col)
			_c(bx2, y + 12.0, bl, 4.0, col.darkened(0.25))
			_c(bx2, y + 4.0, 4.0, 12.0, C_WOOD_DEEP)          # 缝
			if terrain.hash01(sd + 7, k2) > 0.5:
				_c(bx2 + 8.0, y + 8.0, 4.0, 4.0, C_WOOD_LIT.darkened(0.35))   # 钉子
			bx2 += bl
			k2 += 1
		_c(x0 - 4.0, y + 4.0, 4.0, 12.0, C_WOOD_DEEP)
		_c(x1, y + 4.0, 4.0, 12.0, C_WOOD_HI)                 # 右端受光
		_c(x0, y + 16.0, x1 - x0, 4.0, C_WOOD_DEEP)            # 横梁
		_c(x0 + 4.0, y + 20.0, x1 - x0 - 8.0, 4.0, Color(C_WOOD_DEEP, 0.45))   # 桥面下的阴影
		# 桥面上偶尔一圈缆绳 / 木桶 —— 不挡路，只是让它像“码头栈道”
		if x1 - x0 >= 300.0:
			var rx := snappedf(x0 + 24.0 + (x1 - x0 - 80.0) * terrain.hash01(sd, 3), 4.0)
			_c(rx, y - 8.0, 16.0, 8.0, C_WOOD_DARK)
			_c(rx + 4.0, y - 12.0, 8.0, 4.0, C_WOOD_DARK)
			_c(rx + 4.0, y - 8.0, 8.0, 4.0, C_WOOD_ALT)
			_c(rx + 12.0, y - 8.0, 4.0, 4.0, C_WOOD_HI)

	# ---- 石台：砖纹、亮色压顶、右侧受光、左侧暗边、青苔 ----
	func _draw_block(x0: float, x1: float, y: float, fy: float) -> void:
		var sd := int(x0)
		_ground_shadow(x0 - 8.0, x0 + 24.0, fy, 1.0)
		var body_top := y + 8.0
		_c(x0, body_top, x1 - x0, fy - body_top, C_STONE_DARK)
		var row := 0
		var ry := body_top
		while ry < fy:
			var rh := minf(16.0, fy - ry)
			var off := 16.0 if row % 2 == 1 else 0.0
			var bx := x0 - off
			var k := 0
			while bx < x1:
				var bw := 32.0 if terrain.hash01(sd + row, k) > 0.25 else 24.0
				var l := maxf(bx, x0)
				var r := minf(bx + bw - 4.0, x1)
				if r > l:
					var hsh: float = terrain.hash01(k + 31, row + sd)
					var col: Color = C_STONE if hsh > 0.4 else C_STONE_ALT
					if hsh > 0.9:
						col = C_STONE_HI
					col = col.darkened(clampf((ry - body_top) / maxf(fy - body_top, 1.0), 0.0, 1.0) * 0.22)   # 越往下越暗
					_c(l, ry, r - l, rh - 4.0, col)
					_c(l, ry, r - l, 4.0, col.lightened(0.08))          # 每块砖顶边一线亮
					if hsh < 0.12 and r - l > 12.0:
						_c(l + 8.0, ry + 4.0, 4.0, 4.0, C_STONE_DARK)   # 小裂缝
						_c(l + 12.0, ry + 8.0, 4.0, 4.0, C_STONE_DARK)
				bx += bw
				k += 1
			ry += 16.0
			row += 1
		# 两侧：右边受光、左边暗
		_c(x1 - 4.0, body_top, 4.0, fy - body_top, C_STONE_LIT)
		_c(x0, body_top, 4.0, fy - body_top, C_STONE_DARK)
		_c(x0 + 4.0, body_top, 4.0, fy - body_top, Color(C_STONE_DARK, 0.5))
		# 压顶：两格，左右各挑出一格
		_c(x0 - 4.0, y, x1 - x0 + 8.0, 4.0, C_STONE_CAP)
		_c(x0 - 4.0, y + 4.0, x1 - x0 + 8.0, 4.0, C_STONE_CAP2)
		_c(x1, y, 4.0, 8.0, C_STONE_CAP)
		_c(x0 - 4.0, y + 4.0, 4.0, 4.0, C_STONE_DARK)
		_c(x0, y + 8.0, x1 - x0, 4.0, Color(C_STONE_DARK, 0.7))      # 压顶下的阴影线
		# 青苔：压顶上几簇、下面挂几缕
		var mx := x0 + 8.0
		var m := 0
		while mx < x1 - 8.0:
			var hv: float = terrain.hash01(sd + 99, m)
			if hv > 0.62:
				var w := 8.0 + 4.0 * float(int(hv * 10.0) % 3)
				_c(mx, y, w, 4.0, C_MOSS_LIT if hv > 0.8 else C_MOSS)
				_c(mx + 4.0, y + 4.0, w - 4.0, 4.0, C_MOSS)
				var drip := 4.0 * float(1 + int(hv * 13.0) % 3)
				_c(mx + 4.0, y + 8.0, 4.0, drip, C_MOSS)
			mx += 20.0
			m += 1
		# 底部贴地：一行深色接触阴影
		_c(x0, fy - 4.0, x1 - x0, 4.0, Color(C_SHADOW, 0.55))

	# ---- 断桥石板：参差断口、拱肩、中间石墩 ----
	func _draw_slab(x0: float, x1: float, y: float, fy: float) -> void:
		var sd := int(x0) + 5
		_ground_shadow(x0 + 24.0, x1 - 24.0, fy, 0.8)
		var mid := snappedf((x0 + x1) * 0.5, 4.0)
		var pier_w := 56.0
		var thick := 28.0
		var top := y + thick
		var pl := mid - pier_w * 0.5
		# 石墩：一层层石块，右侧受光、左侧暗，越往下越暗
		var r := 0
		var py := top
		while py < fy:
			var dk := clampf((py - top) / maxf(fy - top, 1.0), 0.0, 1.0) * 0.25
			_c(pl, py, pier_w, 16.0, C_STONE.darkened(dk))
			_c(pl, py, pier_w, 4.0, C_STONE_DARK)
			var jx := pl + (20.0 if r % 2 == 0 else 32.0)
			_c(jx, py + 4.0, 4.0, 12.0, C_STONE_DARK)
			_c(pl + 4.0, py + 4.0, 12.0, 4.0, C_STONE_HI.darkened(dk))
			py += 16.0
			r += 1
		_c(pl + pier_w - 4.0, top, 4.0, fy - top, C_STONE_LIT)
		_c(pl, top, 4.0, fy - top, C_STONE_DARK)
		_c(pl - 8.0, fy - 8.0, pier_w + 16.0, 8.0, C_STONE_ALT)     # 墩脚
		_c(pl - 8.0, fy - 8.0, pier_w + 16.0, 4.0, C_STONE_HI)
		# 拱肩：石墩顶上往两边一级级挑出，像断掉的拱
		for s in 5:
			var w := pier_w + 16.0 * float(5 - s)
			_c(mid - w * 0.5, top + float(s) * 4.0, w, 4.0, C_STONE_ALT if s % 2 == 0 else C_STONE)
			_c(mid - w * 0.5, top + float(s) * 4.0, 4.0, 4.0, C_STONE_DARK)
			_c(mid + w * 0.5 - 4.0, top + float(s) * 4.0, 4.0, 4.0, C_STONE_LIT)
		# 板身：7 格厚。一列一列画，两端断口一级级缩进，底边参差
		var x := x0
		var k := 0
		while x < x1:
			var dl: float = minf(x - x0, x1 - x) / 4.0   # 离断口几格
			var jag := int(terrain.hash01(sd, k) * 4.0)
			var rows := 7
			if dl < 1.0:
				rows = 3 + jag % 2
			elif dl < 2.0:
				rows = 4 + jag % 2
			elif dl < 4.0:
				rows = 5 + jag % 2
			elif terrain.hash01(k, sd) > 0.8:
				rows = 6
			var blk := int(float(k) / 7.0)                 # 第几块石头（7 格一块）
			var shade: float = terrain.hash01(blk, sd + 3)
			for rr in rows:
				var col := C_STONE if shade > 0.45 else C_STONE_ALT
				if rr == 0:
					col = C_STONE_CAP
				elif rr == 1:
					col = C_STONE_CAP2
				elif rr == rows - 1:
					col = C_STONE_DARK
				elif rr == 2:
					col = col.lightened(0.06)
				_c(x, y + float(rr) * 4.0, 4.0, 4.0, col)
			if k % 7 == 6 and rows >= 5:
				_c(x, y + 8.0, 4.0, float(rows - 3) * 4.0, C_STONE_DARK)    # 石块之间的缝
			x += 4.0
			k += 1
		# 断口：右端受光、左端暗；断面上几粒碎石
		_c(x1 - 4.0, y, 4.0, 8.0, C_STONE_LIT)
		_c(x0, y + 4.0, 4.0, 8.0, C_STONE_DARK)
		_c(x1 - 8.0, y + 16.0, 4.0, 4.0, C_STONE_DARK)
		_c(x0 + 4.0, y + 16.0, 4.0, 4.0, C_STONE_DARK)
		# 青苔：顶上一两簇，往下挂几缕
		for m in 2:
			var mx := snappedf(x0 + 20.0 + (x1 - x0 - 60.0) * terrain.hash01(sd, 77 + m), 4.0)
			_c(mx, y, 12.0 + 4.0 * float(m), 4.0, C_MOSS_LIT if m == 0 else C_MOSS)
			_c(mx + 4.0, y + 4.0, 8.0, 4.0, C_MOSS)
			_c(mx + 4.0, y + 8.0, 4.0, 4.0 * float(2 + m), C_MOSS)
		# 墩脚碎石
		_c(pl - 24.0, fy - 8.0, 12.0, 8.0, C_STONE_ALT)
		_c(pl - 20.0, fy - 12.0, 4.0, 4.0, C_STONE_HI)
		_c(pl + pier_w + 16.0, fy - 4.0, 8.0, 4.0, C_STONE_ALT)

	# ---- 亭子：瓦片屋顶（顶上那道屋脊能站）、翘角、两根柱子、檐下挂灯笼 ----
	func _draw_roof(x0: float, x1: float, y: float, fy: float) -> void:
		var cx := snappedf((x0 + x1) * 0.5, 4.0)
		var base_y: float = terrain.solid_top(cx, 40.0)
		var eave := y + 44.0
		_ground_shadow(x0 + 40.0, x1 - 40.0, base_y, 0.7)
		# 柱子：立在下面的石台（或地面）上
		var pl := snappedf(x0 + 36.0, 4.0)
		var pr := snappedf(x1 - 44.0, 4.0)
		for px in [pl, pr]:
			_c(px - 4.0, eave, 4.0, base_y - eave, C_PILLAR.darkened(0.35))
			_c(px, eave, 4.0, base_y - eave, C_PILLAR)
			_c(px + 4.0, eave, 4.0, base_y - eave, C_PILLAR_LIT)
			_c(px - 8.0, base_y - 12.0, 20.0, 12.0, C_STONE_CAP2)   # 柱础
			_c(px - 8.0, base_y - 12.0, 20.0, 4.0, C_STONE_CAP)
			_c(px + 8.0, base_y - 12.0, 4.0, 12.0, C_STONE_LIT)
		# 檐下横枋 + 挂落（镂空花格）
		_c(pl, eave, pr - pl + 8.0, 8.0, C_PILLAR)
		_c(pl, eave, pr - pl + 8.0, 4.0, C_PILLAR_LIT)
		var lx := pl + 12.0
		var j := 0
		while lx < pr - 4.0:
			_c(lx, eave + 8.0, 4.0, 4.0 if j % 2 == 0 else 8.0, C_PILLAR)
			lx += 8.0
			j += 1
		_c(pl + 8.0, eave + 16.0, pr - pl - 8.0, 4.0, Color(C_PILLAR, 0.8))
		# 屋面：从屋脊往下一行行变宽，最外两格往上翘
		var rows := 9
		for r in rows:
			var ry := y + 8.0 + float(r) * 4.0
			var spread := 4.0 + float(r) * 6.0
			var l := snappedf(x0 - spread, 4.0)
			var rr := snappedf(x1 + spread, 4.0)
			var xx := l
			while xx < rr:
				# 筒瓦：每 8 单位一道亮、一道暗；右半边受光更多
				var lit := (int(xx / 4.0) % 2 == 0)
				var col: Color = C_TILE_LIT if lit else C_TILE
				if lit and xx < cx:
					col = C_TILE_LIT.lerp(C_TILE, 0.45)
				if r == rows - 1:
					col = C_WOOD_DEEP
				elif r == rows - 2:
					col = C_TILE.darkened(0.2) if not lit else C_TILE
				_c(xx, ry, 4.0, 4.0, col)
				xx += 4.0
		# 翘角：最外两端往上翘起三格
		for side in [-1.0, 1.0]:
			var ex := (x0 - 4.0 - 8.0 * 6.0) if side < 0.0 else (x1 + 8.0 * 6.0)
			ex = snappedf(ex, 4.0)
			for s in 4:
				var col := C_RIDGE if s == 3 else C_TILE_LIT
				_c(ex + side * float(s) * 4.0, y + 36.0 - float(s) * 4.0, 4.0, 4.0, col)
			_c(ex + side * 12.0, y + 20.0, 4.0, 4.0, C_RIDGE)
		# 屋脊：能站的那条（两格），两头带一点鸱吻
		_c(x0, y, x1 - x0, 4.0, C_RIDGE)
		_c(x0, y + 4.0, x1 - x0, 4.0, C_TILE)
		for i in range(int(x0 / 4.0) + 2, int(x1 / 4.0) - 2, 6):
			_c(float(i) * 4.0, y + 4.0, 4.0, 4.0, C_TILE_LIT)
		_c(x0 - 4.0, y - 8.0, 8.0, 12.0, C_RIDGE.darkened(0.25))
		_c(x0 - 8.0, y - 12.0, 4.0, 8.0, C_RIDGE.darkened(0.25))
		_c(x1 - 4.0, y - 8.0, 8.0, 12.0, C_RIDGE)
		_c(x1 + 4.0, y - 12.0, 4.0, 8.0, C_RIDGE)
		# 灯笼（实体部分；光晕在 _glow 里叠加）
		for lxp in [pl - 20.0, pr + 20.0]:
			var ly := eave + 4.0
			_c(lxp + 4.0, ly, 4.0, 12.0, C_WOOD_DEEP)
			_c(lxp - 4.0, ly + 12.0, 20.0, 4.0, C_WOOD_DEEP)
			_c(lxp - 4.0, ly + 16.0, 20.0, 20.0, C_LAMP)
			_c(lxp, ly + 16.0, 12.0, 20.0, C_LAMP_HOT)
			_c(lxp - 4.0, ly + 24.0, 20.0, 4.0, Color(0.85, 0.42, 0.2))
			_c(lxp - 4.0, ly + 36.0, 20.0, 4.0, C_WOOD_DEEP)
			_c(lxp + 4.0, ly + 40.0, 4.0, 8.0, Color(0.85, 0.42, 0.2))

	func lantern_points() -> Array:
		if String(data.style) != "roof":
			return []
		var pl := snappedf(float(data.x0) + 36.0, 4.0)
		var pr := snappedf(float(data.x1) - 44.0, 4.0)
		var ly := float(data.y) + 44.0 + 30.0
		return [Vector2(pl - 14.0, ly), Vector2(pr + 26.0, ly)]

	func _draw_glow() -> void:
		for p in lantern_points():
			for i in 6:
				var r := 18.0 + float(i) * 22.0
				_glow.draw_circle(p, r, Color(1.0, 0.55, 0.25, 0.05 * (1.0 - float(i) / 6.0)))
