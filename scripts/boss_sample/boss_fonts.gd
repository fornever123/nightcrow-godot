extends RefCounted
## Boss 小样专属字体加载工具：统一使用项目内置思源宋体与哥特西文字体，严禁使用 SystemFont。
## 注意：不持有 static Resource 缓存，避免无头测试退出时产生资源引用残留告警。

const SERIF_SC := "res://assets/fonts/yg_title/NotoSerifSC-VF.ttf"
const GOTHIC_PIRATA := "res://assets/fonts/gothic/PirataOne-Regular.ttf"
const GOTHIC_CINZEL := "res://assets/fonts/gothic/Cinzel-VF.ttf"


static func load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Font:
			return res
	if FileAccess.file_exists(path):
		var ff := FontFile.new()
		ff.data = FileAccess.get_file_as_bytes(path)
		return ff
	push_error("BossFonts 无法加载字体：" + path)
	return null


static func chinese_serif() -> Font:
	return load_font(SERIF_SC)


static func gothic_title() -> Font:
	return load_font(GOTHIC_PIRATA)


static func gothic_roman() -> Font:
	return load_font(GOTHIC_CINZEL)
