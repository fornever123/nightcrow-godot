extends RefCounted
## 《断晓》全局开源商用哥特 / 石刻 / 狂草 / 重宋字体加载器（SIL OFL 1.1，零系统字体依赖）。
## - PirataOne-Regular.ttf：维多利亚尖角哥特黑体（大评级字母 S/A/B/C/D、哥特装饰铭文标题）
## - Cinzel-VF.ttf：古典刀锋石刻衬线可变字体（连击数字、计时/百分比数字、西文副标与按键徽章）
## - MaShanZheng-Regular.ttf：凌厉毛笔狂草行书（“弹刀！”“破晓！”战斗爆发字、段位名）
## - NotoSerifSC-VF.ttf：思源宋体可变字体（中文菜单、正文提示、重宋横幅，并作为西文/狂草字体的中文回退）

const PIRATA_ONE_PATH := "res://assets/fonts/gothic/PirataOne-Regular.ttf"
const CINZEL_PATH := "res://assets/fonts/gothic/Cinzel-VF.ttf"
const MASHANZHENG_PATH := "res://assets/fonts/gothic/MaShanZheng-Regular.ttf"
const NOTO_SERIF_PATH := "res://assets/fonts/yg_title/NotoSerifSC-VF.ttf"


static func all_font_paths() -> PackedStringArray:
	return PackedStringArray([
		PIRATA_ONE_PATH,
		CINZEL_PATH,
		MASHANZHENG_PATH,
		NOTO_SERIF_PATH,
	])


## 思源宋体可变字重（200..900）：用于中文菜单、说明正文、重宋横幅（900）
static func serif(weight: int = 400) -> Font:
	var base: FontFile = load(NOTO_SERIF_PATH)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": clampi(weight, 200, 900)}
	return fv


## 维多利亚尖角哥特黑体：用于 S/A/B/C/D 评级大字母、Intermissio / Lux Scissa 铭文
static func blackletter(fallback_weight: int = 700) -> Font:
	var base: FontFile = load(PIRATA_ONE_PATH)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.fallbacks = [serif(fallback_weight)]
	return fv


## 古典刀锋石刻衬线可变字体（400..900）：用于连击数、计时/百分比、西文副标与按键名，混排中文自动回退重宋
static func cinzel(weight: int = 600, italic: bool = false, fallback_weight: int = -1) -> Font:
	var base: FontFile = load(CINZEL_PATH)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": clampi(weight, 400, 900)}
	if italic:
		fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.16, 1.0), Vector2.ZERO)
	var fb_w := weight if fallback_weight < 0 else fallback_weight
	fv.fallbacks = [serif(fb_w)]
	return fv


## 石刻数字（默认微斜，替代原 Georgia 斜体数字）
static func digits(weight: int = 700, italic: bool = true) -> Font:
	return cinzel(weight, italic, weight)


## 凌厉毛笔狂草行书：用于“弹刀！”“破晓！”等战斗弹出字与段位名，生僻标点回退重宋
static func brush(fallback_weight: int = 700) -> Font:
	var base: FontFile = load(MASHANZHENG_PATH)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.fallbacks = [serif(fallback_weight)]
	return fv
