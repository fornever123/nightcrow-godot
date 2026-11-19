extends Node2D
## 画面重构样板：一层雨。freeze = true 时，雨滴落进白光柱就被钉在半空（白光驱逐时间），
## 停一会儿再放回天上重新落。

var host                        ## rd_sample：提供 cam_x() 与 shaft_hit(p)
var count := 400
var speed := Vector2(-110.0, 1500.0)
var length_px := Vector2(26.0, 46.0)
var width := 1.6
var color := Color(0.62, 0.7, 0.8, 0.28)
var bottom := 580.0
var top := -360.0
var span := 1300.0              ## 镜头左右各覆盖多宽
var freeze := false
var bead_color := Color(0.95, 0.98, 1.0, 0.95)

var _pos: PackedVector2Array
var _len: PackedFloat32Array
var _spd: PackedFloat32Array
var _held: PackedFloat32Array   ## <0 在落；>=0 被光钉住了多久
var _life: PackedFloat32Array
var _thr: PackedFloat32Array    ## 每滴雨要进到光柱多深才被钉住（让雨珠铺满整道光，而不是排在光的边上）
var _rng := RandomNumberGenerator.new()


func setup() -> void:
	_rng.seed = hash(name)
	_pos.resize(count); _len.resize(count); _spd.resize(count); _held.resize(count); _life.resize(count); _thr.resize(count)
	var cx: float = host.cam_x()
	for i in count:
		_pos[i] = Vector2(cx + _rng.randf_range(-span, span), _rng.randf_range(top, bottom))
		_len[i] = _rng.randf_range(length_px.x, length_px.y)
		_spd[i] = _rng.randf_range(0.8, 1.15)
		_held[i] = -1.0
		_life[i] = _rng.randf_range(5.0, 11.0)
		_thr[i] = _rng.randf_range(0.05, 1.6)


func _respawn(i: int, cx: float) -> void:
	_pos[i] = Vector2(cx + _rng.randf_range(-span, span), top - _rng.randf_range(0.0, 200.0))
	_held[i] = -1.0


func _process(dt: float) -> void:
	var cx: float = host.cam_x()
	var v := speed
	for i in count:
		var p := _pos[i]
		if _held[i] >= 0.0:
			_held[i] += dt
			if _held[i] > _life[i]:
				_respawn(i, cx)
			continue
		p += v * _spd[i] * dt
		if p.x < cx - span:
			p.x += span * 2.0
		elif p.x > cx + span:
			p.x -= span * 2.0
		_pos[i] = p
		if p.y > bottom:
			_respawn(i, cx)
		elif freeze and host.shaft_hit(p) > _thr[i]:
			_held[i] = 0.0
	queue_redraw()


func _draw() -> void:
	var dir := speed.normalized()
	var streaks := PackedVector2Array()
	var beads := PackedVector2Array()
	var bead_cols := PackedColorArray()
	var t := Time.get_ticks_msec() / 1000.0
	for i in count:
		var p := _pos[i]
		if _held[i] >= 0.0:
			# 被钉住的雨珠：短、亮、微微闪；刚被钉住时从雨丝缩成珠
			var k := clampf(_held[i] / 0.18, 0.0, 1.0)
			var l := lerpf(_len[i] * 0.6, 3.5, k)
			beads.append(p - dir * l)
			beads.append(p)
			var tw := 0.75 + 0.25 * sin(t * 2.3 + float(i) * 1.7)
			var fade := clampf((_life[i] - _held[i]) / 0.6, 0.0, 1.0)
			var c := bead_color
			c.a *= tw * fade
			bead_cols.append(c)
		else:
			streaks.append(p - dir * _len[i])
			streaks.append(p)
	if streaks.size() > 0:
		draw_multiline(streaks, color, width)
	if beads.size() > 0:
		draw_multiline_colors(beads, bead_cols, width + 1.0)
