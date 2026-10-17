class_name Palette
extends RefCounted
## 全局配色 —— **V3 双色硬剪影**（见 docs/art_style_board.html）。
##
## 【V3 是什么】
## 角色是【近黑剪影 + 一块身份色】；环境压到三档冷灰；全屏唯一的高饱和色
## 留给命中特效。混战里玩家只看得见轮廓和位移，所以这一版把"剪影可辨"
## 推到极限 —— 代价是必须靠特效和关卡品味撑住画面，不能靠贴图细节。
##
## 【三条铁律，改配色时别破】
##   1. 环境色饱和度必须≈0。任何暖色/高饱和环境色都会立刻毁掉剪影。
##   2. 角色身上只允许：剪影黑 + 一块身份色 + 极少量白（眼/靶心/刃口）。
##   3. 受击白闪/眩晕闪烁靠 modulate 相乘实现（见 dummy.gd）。
##      纯黑角色会让白闪【静默失效】—— 所以浅色面必须存在。
##
## 【改配色要改两个地方】
##   .tscn 里每个 ColorRect 用的是字面量颜色（场景文件引用不了脚本常量）。
##   本文件的常量给运行时代码（特效/弹丸/HUD/HP 条）用；场景的值给静态美术用。
##   两边必须一致，否则特效和角色会对不上色。

# ---------------------------------------------------------------- 环境（三档冷灰，饱和度≈0）
## 最远的底色（天空 / 全屏底）
const SKY := Color(0.051, 0.059, 0.086)
## 远景色块（视差最慢）
const FAR := Color(0.078, 0.094, 0.149)
## 中景色块
const MID := Color(0.110, 0.125, 0.188)
## 近景色块（视差最快）
const NEAR := Color(0.137, 0.165, 0.239)
## 地面以下的实心填充
const GROUND_FILL := Color(0.059, 0.071, 0.106)

# ---------------------------------------------------------------- 地形
## 地形主体的面
const TERRAIN := Color(0.110, 0.125, 0.188)
## 地形暗部（下缘/侧向阴影）
const TERRAIN_DARK := Color(0.078, 0.094, 0.149)
## 地形顶面亮边 —— V3 里这是【撞墙目标】的视觉引导，别调暗
const TERRAIN_EDGE := Color(0.227, 0.290, 0.400)
## 更亮的顶面细线（可撞面的最亮一档）
const TERRAIN_HILITE := Color(0.369, 0.451, 0.608)

# ---------------------------------------------------------------- 角色
## 剪影主体。刻意不是纯黑（#000）：留一点点值才和更暗的背景拉得开层次
const SILHOUETTE := Color(0.020, 0.024, 0.039)
## 剪影的次级面（脚/内侧），只比主体亮一档 —— V3 禁止内部线条
const SILHOUETTE_SOFT := Color(0.063, 0.075, 0.122)
## 结构性白色标记（眼 / 靶心 / 刃口 / 铆钉）。受击白闪靠它承载
const PAPER := Color(0.910, 0.925, 0.957)

## 玩家身份色（青）。四名玩家按 P1..P4 区分
const PLAYER := Color(0.184, 0.878, 0.816)
const PLAYER_DARK := Color(0.106, 0.612, 0.565)
const PLAYER_LIGHT := Color(0.498, 0.961, 0.941)
## 玩家的"眼睛"，唯一的亮部
const PLAYER_EYE := Color(0.910, 0.925, 0.957)
## 朝向标记
const PLAYER_MARK := Color(0.184, 0.878, 0.816)

## 木桩身份色（暖琥珀）。刻意和玩家的青互补
const DUMMY := Color(1.000, 0.541, 0.239)
const DUMMY_DARK := Color(0.541, 0.239, 0.078)
const DUMMY_LIGHT := Color(1.000, 0.761, 0.302)
## 木桩的靶心/绑带
const DUMMY_BAND := Color(1.000, 0.639, 0.361)

# ---------------------------------------------------------------- 四人身份色（V3 的核心机制）
## 四个玩家靠这一块色区分，轮廓完全一致也能认出来。
## 但色盲玩家需要形状辅助，所以每个玩家的头型/武器形状也要有差异（M1 之后做）。
const IDENTITY_P1 := Color(0.184, 0.878, 0.816)
const IDENTITY_P2 := Color(1.000, 0.541, 0.239)
const IDENTITY_P3 := Color(0.655, 0.420, 1.000)
const IDENTITY_P4 := Color(1.000, 0.824, 0.247)

# ---------------------------------------------------------------- 反馈（全屏唯一的高饱和）
## 命中闪白 —— 也是 V3 特效的主色
const HIT_FLASH := Color(1.0, 1.0, 1.0)
## 命中强调色（V3 用巨型白星 + 这一色做描边）
const IMPACT := Color(1.0, 1.0, 1.0)
## 蓄力 / 上挑的能量色
const ENERGY := Color(1.0, 1.0, 1.0)
## 危险/撞墙强调色。V3 里这是环境之外唯一的暖色
const ACCENT_DANGER := Color(1.000, 0.302, 0.180)
## 伤害数字
const DAMAGE_TEXT := Color(0.910, 0.925, 0.957)
## 撞墙伤害数字（更烫）
const WALL_TEXT := Color(1.000, 0.302, 0.180)

# ---------------------------------------------------------------- UI（极简：只留必要信息）
const UI_TEXT := Color(0.910, 0.925, 0.957)
const UI_DIM := Color(0.357, 0.404, 0.522)
const UI_ACCENT := Color(0.184, 0.878, 0.816)
const UI_PANEL := Color(0.051, 0.059, 0.086, 0.88)
const UI_BORDER := Color(0.165, 0.188, 0.267)

## HP 条三档。V3 里不用绿色（不在调色板内），改用 白 → 琥珀 → 橙红
const HP_HIGH := Color(0.910, 0.925, 0.957)
const HP_MID := Color(1.000, 0.761, 0.302)
const HP_LOW := Color(1.000, 0.302, 0.180)


## 把颜色往黑里推，用于暗部。
static func darken(c: Color, amount: float) -> Color:
	return c.lerp(Color(0, 0, 0, c.a), clampf(amount, 0.0, 1.0))


static func lighten(c: Color, amount: float) -> Color:
	return c.lerp(Color(1, 1, 1, c.a), clampf(amount, 0.0, 1.0))


## 带透明度的变体，用于视差色块和辉光。
static func fade(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)
