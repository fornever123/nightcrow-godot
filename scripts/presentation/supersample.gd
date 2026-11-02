extends Node
## 2 倍超采样（自动加载 Supersample，F7 开 / 关，记在 user://graphics.cfg）。
## 打开时：整个游戏画面（世界层 + 所有 CanvasLayer）改画到一张 2 倍大小的 SubViewport 上（和主窗口共用 World2D，
##   2D 坐标仍按 1280×720 设计尺寸），主窗口只画一张把它缩小一半的图（双线性正好是 2×2 平均）。
##   游戏节点不搬家：输入、物理、镜头、get_viewport() 都照旧在主窗口；CanvasLayer 只是用 custom_viewport 换了画到哪。
## 主角黑描边按渲染像素算（char_light 用 dFdx），2 倍下会细一半，所以打开时把关卡 light_mat 的 ol_width 乘 2。
## headless 下什么都不做。环境变量 NIGHTCROW_SSAA=0/1 可临时覆盖存档里的开关（截图对比用）。

const CFG := "user://graphics.cfg"
const FACTOR := 2
const DISPLAY_BIT := 1 << 19          ## 只有缩小显示的那张图在这一层；打开时主窗口只画这一层

var enabled: bool = false
var _sub: SubViewport
var _layer: CanvasLayer
var _rect: TextureRect
var _scene: Node                      ## 已经补过描边宽度的关卡（换关卡 / 重开后重新找）
var _scene_mat: ShaderMaterial
var _scene_ol: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var on := false
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		on = bool(cfg.get_value("graphics", "supersample", false))
	var env := OS.get_environment("NIGHTCROW_SSAA")
	if env != "":
		on = env == "1"
	get_tree().node_added.connect(_on_node_added)
	RenderingServer.frame_pre_draw.connect(_sync)
	set_enabled(on)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		set_enabled(not enabled)
		var cfg := ConfigFile.new()
		cfg.load(CFG)
		cfg.set_value("graphics", "supersample", enabled)
		cfg.save(CFG)
		print("Supersample: ", "on" if enabled else "off")
		get_viewport().set_input_as_handled()


func set_enabled(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	enabled = on
	var root := get_tree().root
	if on and _sub == null:
		_build()
	if _sub != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		_layer.visible = on
	root.canvas_cull_mask = DISPLAY_BIT if on else 0xFFFFFFFF
	for n in _all_layers(root):
		if n is CanvasLayer:
			_route(n)
		else:
			_order(n)
	_fix_outline()
	_sync()


func _build() -> void:
	var root := get_tree().root
	_sub = SubViewport.new()
	_sub.name = "SupersampleView"
	_sub.world_2d = root.world_2d
	_sub.disable_3d = true
	_sub.msaa_2d = root.msaa_2d
	_sub.canvas_cull_mask = 0xFFFFFFFF & ~DISPLAY_BIT
	_sub.size_2d_override_stretch = true
	add_child(_sub)
	_layer = CanvasLayer.new()
	_layer.name = "SupersampleDisplay"
	_layer.layer = 128
	add_child(_layer)
	_rect = TextureRect.new()
	_rect.texture = _sub.get_texture()
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visibility_layer = DISPLAY_BIT
	_layer.add_child(_rect)


## 每帧画之前：2 倍画布的尺寸跟窗口走、镜头变换照抄主窗口（含震屏）
func _sync() -> void:
	if not enabled or _sub == null:
		return
	var root := get_tree().root
	var design := root.get_visible_rect().size
	var px_per_unit := root.get_final_transform().x.length()   # 设计单位 → 窗口像素（窗口拉大 / 全屏时 > 1）
	var want := Vector2i((design * px_per_unit * FACTOR).round())
	if _sub.size != want:
		_sub.size = want
	_sub.size_2d_override = Vector2i(design.round())
	_sub.canvas_transform = root.canvas_transform
	_rect.position = Vector2.ZERO
	_rect.size = design
	if _scene == null or not is_instance_valid(_scene):
		_fix_outline()


func _on_node_added(n: Node) -> void:
	if n is CanvasLayer:
		_route.call_deferred(n)
	elif n is SubViewport and n != _sub:
		_order.call_deferred(n)


## 场景里别的 SubViewport（命中像素特效画布、它的辉光画布……）默认和 2 倍画布平级，谁先画不一定，
## 2 倍画布先画就会用到它们上一帧的图（命中特效晚一帧）。打开时把它们挂成 2 倍画布的子视口：引擎先画子、后画父
func _order(vp: SubViewport) -> void:
	if not is_instance_valid(vp) or not vp.is_inside_tree() or vp == _sub or _sub == null:
		return
	var host := vp.get_parent().get_viewport()
	if host != get_tree().root:
		return     # 套在别的 SubViewport 里的，跟着外层走
	RenderingServer.viewport_set_parent_viewport(vp.get_viewport_rid(),
		(_sub if enabled else host).get_viewport_rid())


## 主窗口里的 CanvasLayer：打开时改画到 2 倍画布，关掉时还原。自己的显示层、别的 SubViewport 里的层不动
func _route(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree() or n == _layer:
		return
	var cl := n as CanvasLayer
	if cl.get_viewport() != get_tree().root:
		return
	# 引擎不接受设回空（报 Cannot set viewport to nullptr），关掉时显式指回主窗口，效果和默认一样
	cl.custom_viewport = _sub if enabled else get_tree().root
	# 引擎在层离开场景树时按“当前画到的视口”断开父节点信号，而连接是进树时按主窗口建的；
	# 离开前先还原成主窗口，免得每次重开 / 退出都报 disconnect 错误
	if enabled and not cl.tree_exiting.is_connected(_unroute):
		cl.tree_exiting.connect(_unroute.bind(cl), CONNECT_ONE_SHOT)


func _unroute(cl: CanvasLayer) -> void:
	if is_instance_valid(cl) and cl.custom_viewport == _sub:
		cl.custom_viewport = get_tree().root


## 2 倍画布（测帧时间用；关着时为空）
func view() -> SubViewport:
	return _sub if enabled else null


## 主窗口里的 CanvasLayer 和第一层 SubViewport（不往 SubViewport 里面找）
func _all_layers(from: Node) -> Array:
	var out := []
	for c in from.get_children():
		if c == _sub:
			continue
		if c is SubViewport:
			out.append(c)
			continue
		if c is CanvasLayer:
			out.append(c)
		out.append_array(_all_layers(c))
	return out


## 关卡的主角材质：描边宽度按渲染像素算，打开超采样时乘 FACTOR
func _fix_outline() -> void:
	if _scene != null and is_instance_valid(_scene) and _scene_mat != null:
		_scene_mat.set_shader_parameter("ol_width", _scene_ol)
	_scene = null
	_scene_mat = null
	var scene: Node = null
	for c in get_tree().root.get_children():
		if c != self and c.get("light_mat") is ShaderMaterial:
			scene = c
	if scene == null:
		return
	var m: ShaderMaterial = scene.get("light_mat")
	_scene = scene
	_scene_mat = m
	_scene_ol = float(m.get_shader_parameter("ol_width"))
	if enabled:
		m.set_shader_parameter("ol_width", _scene_ol * FACTOR)
