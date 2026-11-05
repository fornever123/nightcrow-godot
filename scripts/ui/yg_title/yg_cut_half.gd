extends Control
## [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
## 菜单字的「上半片」或「下半片」：靠材质里的裁切着色器丢掉另一半，
## 片与片之间错开一点点，还原网页版 CSS clip-path 的斜切效果。
## 删除方法：见 docs/YG-首页断光-删除清单.md。

var label_text := ""
var num_text := ""
var font_serif: Font
var font_gothic: Font
var unit := 7.2
var ctr := Vector2.ZERO
var label_col := Color(1, 1, 1, 1)
var num_col := Color(1, 1, 1, 1)
var label_spacing := 0.68
var label_size := 2.25


func _draw() -> void:
	if font_serif == null:
		return
	var fs := int(round(label_size * unit))
	var sp := label_spacing * float(fs)
	var w := 0.0
	for i in label_text.length():
		w += font_serif.get_string_size(label_text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sp
	w -= sp
	var x := ctr.x - w * 0.5
	var y := ctr.y + fs * 0.34
	for i in label_text.length():
		var ch := label_text.substr(i, 1)
		draw_string(font_serif, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)
		x += font_serif.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sp
	if num_text != "":
		var nfs := int(round(1.02 * unit))
		var nsp := 0.18 * float(nfs)
		var nw := 0.0
		for i in num_text.length():
			nw += font_gothic.get_string_size(num_text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x + nsp
		nw -= nsp
		var nx := ctr.x - w * 0.5 - 2.2 * unit - nw
		var ny := ctr.y + nfs * 0.34
		for i in num_text.length():
			var ch := num_text.substr(i, 1)
			draw_string(font_gothic, Vector2(nx, ny), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, num_col)
			nx += font_gothic.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x + nsp
