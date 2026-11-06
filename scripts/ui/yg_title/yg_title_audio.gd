extends Node
## [YG-MARK] 由 YG 新增（首页「断晓 · 断光」WebGL 版移植到 Godot）。
##
## 首页声音。11-05 起全部换成真实录音（原来是启动时代码合成的滤波噪声 / 正弦音）：
##   雨声床   assets/audio/yg_title/rain_bed.ogg + rain_near.ogg（OpenGameArt CC0，见同目录 LICENSE.txt）
##   界面音   assets/audio/yg_title/ui_move.ogg / ui_back.ogg（Kenney Interface Sounds，CC0）
##   出刀相关 直接用大招线的 assets/audio/ult/*.ogg（刀鸣 / 斩线 / 冲击 / 碎裂 / 推鲤口 / 收刀）
## 雨走单独的总线 YgTitleRain（运行时建、离开首页时删），上面挂一个低通：
## 开场雨停在半空时雨声被“抽走”，斩开后再放开；进游戏那一刀后像沉进影水里一样闷下去。
## 开场 / 进游戏 / 退出这几处的一次性声音由本脚本自己看 sim 的时间轴来放，app 只管菜单音。
##
## 删除方法：见 docs/YG-首页断光-删除清单.md（删掉本文件即可，其余代码会跳过声音）。

const BUS := "YgTitleRain"
const DIR := "res://assets/audio/yg_title/"
const ULT := "res://assets/audio/ult/"
# 名字 → [文件, 增益 dB, 从第几秒开始放]
const SFX := {
	"eye": [ULT + "ult_eye.ogg", 0.0, 0.0],           # 雨停在半空：刀鸣
	"rise": [ULT + "ult_rise.ogg", -9.0, 0.0],        # 刀口闪光，斩之前吸一口气
	"slash": [ULT + "ult_cut_2.ogg", -1.0, 0.0],      # 开场 / 进游戏那一刀：斩线拉开
	"impact": [ULT + "ult_impact.ogg", -2.0, 0.0],    # 一刀两断
	"shatter": [ULT + "ult_cut_3.ogg", -6.0, 0.0],    # 慢半拍到的碎裂
	"sheathe": [ULT + "ult_sheathe.ogg", -3.0, 0.0],  # 退出：刀口合上时收刀“咔”
	"confirm": [ULT + "ult_push.ogg", -10.0, 0.22],   # 进设置 / 说明：拇指推鲤口
	"tick": [DIR + "ui_move.ogg", -8.0, 0.0],         # 换选项
	"back": [DIR + "ui_back.ogg", -10.0, 0.0],        # 返回
}
const PLAYER_CUTS := ["ult_cut_0.ogg", "ult_cut_1.ogg", "ult_cut_2.ogg", "ult_cut_3.ogg"]
const LP_OPEN := 20000.0
const LP_CLOSED := 320.0       # 雨冻住时
const LP_UNDER := 650.0        # 进游戏沉进影水时
const EYE_T := 2.2             # 开场：雨大半停住、雨声快抽空的时候（freeze 1.25～2.95）
const RISE_T := 3.45           # 开场：刀口闪光（glint_a 3.35）之后，斩（slash_a 3.72）之前
const SHEATHE_T := 0.93        # 退出：咔（文件里 0.42 秒）落在刀口合上（约 1.35 秒）

var sim: RefCounted

var _bed: AudioStreamPlayer
var _near: AudioStreamPlayer
var _lp: AudioEffectLowPassFilter
var _pool: Array[AudioStreamPlayer] = []
var _streams := {}
var _rain_gain := 0.0
var _cutoff := LP_OPEN
var _prev_it := 0.0
var _prev_fin_t := 0.0
var _prev_hit := false
var _cut_i := 0
var _shatter_t := -1.0
var muted := false


func setup(s: RefCounted) -> void:
	sim = s
	for key in SFX:
		_streams[key] = load(str(SFX[key][0]))
	for f in PLAYER_CUTS:
		_streams[f] = load(ULT + f)
	_make_bus()
	_bed = _loop_player(DIR + "rain_bed.ogg")
	_near = _loop_player(DIR + "rain_near.ogg")
	_near.play(randf() * 30.0)    # 两层错开起点，听不出同一处循环
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_prev_it = sim.it


func _exit_tree() -> void:
	# 停掉并放开流（直接退出游戏时音频线程还拿着，会报“资源还在用”）
	for p in [_bed, _near] + _pool:
		if p:
			p.stop()
			p.stream = null
	var i := AudioServer.get_bus_index(BUS)
	if i > 0:
		AudioServer.remove_bus(i)


func _make_bus() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
		AudioServer.add_bus_effect(i, AudioEffectLowPassFilter.new())
	_lp = AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter
	_lp.cutoff_hz = LP_OPEN


func _loop_player(path: String) -> AudioStreamPlayer:
	var st := load(path) as AudioStreamOggVorbis
	st.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = BUS
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	if sim == null or _bed == null:
		return
	_timeline()
	var target := 0.0
	var close := 0.0          # 0 = 雨声全开，1 = 全闷
	var shut := LP_CLOSED
	match sim.state:
		"intro":
			var fr := 0.0
			if sim.it >= float(sim.TL["freeze_a"]):
				fr = clampf((sim.it - float(sim.TL["freeze_a"])) / (float(sim.TL["freeze_b"]) - float(sim.TL["freeze_a"])), 0.0, 1.0)
			target = 0.55 * (1.0 - fr * 0.85)
			close = fr
			if sim.cut_done:
				target = 0.5
				close = 0.0
		"leave":
			target = 0.5 * (1.0 - sim.fin_fade)
			close = sim.fin_open
			shut = LP_UNDER
		"exit":
			target = 0.5 * (1.0 - sim.fin_fade)
		"card":
			target = 0.0
		_:
			target = 0.5 * float(sim.rain_percent) / 100.0 + 0.06
	if muted:
		target = 0.0
	var vol: float = float(sim.volume) / 100.0
	# 雨冻住时收得快，放开时慢一点（像耳朵重新听见）
	_rain_gain = lerpf(_rain_gain, target * vol, clampf(delta * 1.5, 0.0, 1.0))
	var want := LP_OPEN * pow(shut / LP_OPEN, close)
	_cutoff = lerpf(_cutoff, want, clampf(delta * (6.0 if want < _cutoff else 2.2), 0.0, 1.0))
	_lp.cutoff_hz = _cutoff
	var g := _rain_gain / 0.5
	var db := -80.0 if g <= 0.002 else linear_to_db(g) - 8.0
	_bed.volume_db = db
	_near.volume_db = db - 3.0
	if _shatter_t >= 0.0:
		_shatter_t -= delta
		if _shatter_t < 0.0:
			play("shatter")


## 开场 / 进游戏 / 退出的一次性声音（跳过开场时时间会一下跨过去，那时不补放）
func _timeline() -> void:
	var it: float = sim.it
	if sim.state == "intro" and it - _prev_it < 0.2:
		if _prev_it < EYE_T and it >= EYE_T:
			play("eye")
		if _prev_it < RISE_T and it >= RISE_T:
			play("rise")
	_prev_it = it
	var ft: float = sim.fin_t
	if sim.state == "leave" and sim.fin_hit and not _prev_hit:
		play("impact")
	if sim.state == "exit" and _prev_fin_t < SHEATHE_T and ft >= SHEATHE_T:
		play("sheathe")
	_prev_hit = sim.fin_hit
	_prev_fin_t = ft


func play(name: String) -> void:
	if muted:
		return
	var key := name
	var db := 0.0
	var from := 0.0
	match name:
		"slash":
			# 开场 / 进游戏那一刀固定用斩线；菜单里玩家自己划的刀轮换四声，轻一点
			if sim.state != "intro" and sim.state != "leave":
				key = PLAYER_CUTS[_cut_i % PLAYER_CUTS.size()]
				_cut_i += 1
				db = -7.0
		"slash_big":
			key = "impact"
			_shatter_t = 0.08
	if not _streams.has(key):
		return
	if SFX.has(key):
		db += float(SFX[key][1])
		from = float(SFX[key][2])
	for p in _pool:
		if not p.playing:
			p.stream = _streams[key]
			p.volume_db = db + linear_to_db(maxf(float(sim.volume) / 100.0, 0.001))
			p.play(from)
			return


func toggle_mute() -> void:
	muted = not muted
