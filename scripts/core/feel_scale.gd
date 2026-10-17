extends RefCounted
## 打击感强度的单一真源 —— 把"物理量"翻译成 0..1 的强度。
##
## 【为什么值得单独一个文件】同一个 0..1 以前是**在每个调用点各写一遍**：
##     clampf(mv.shake_amount / 15.0, 0.25, 1.0)      → 6 处
##     clampf(impact_speed / 900.0, 0.2, 1.0)         → 6 处
## 而这一对数被**音效、震屏、粒子**三组消费者共用。于是：
##   · 想把重击调得更炸（15.0 → 12.0），只改到一处 → 震屏变重了、音效没变；
##   · 想给某个招式单独加强，只能去改调用点 —— 招式数据反倒不是真源了。
## 现在全项目只允许这一个文件出现这两个除数。契约测试会扫源码，
## 别处再写一遍就红（tests/verify_contracts.gd F 组）。
##
## 【为什么不放进 MoveDefinition】招式数据只该存"作者填的原值"，
## 归一化是**表现层**的约定（"多响算满"随时会调），两者生命周期不同；
## 撞墙强度更是和招式无关 —— 它来自被抛飞的速度。
##
## 【为什么不用 class_name】用 class_name 就要依赖 `.godot/global_script_class_cache.cfg`，
## 而这个缓存由编辑器刷新 —— headless 跑测试时刚建的新类可能还不在缓存里，
## 报的是 "Identifier not found"，排查起来像见鬼。所以统一 `preload` 一个短名。

## 震屏量到这个值 = 满强度。15.0 正好是 charge_1 满蓄力的震屏量。
const SHAKE_FULL := 15.0
## 最轻的一刀也要有反馈，强度不归零。"轻击完全没声音"比"轻击轻一点"糟得多。
const SHAKE_FLOOR := 0.25
## 撞击速度到这个值 = 满强度（满蓄力斩打进墙的实测速度约 900 px/s）。
const WALL_FULL_SPEED := 900.0
## 撞墙的下限抬得比命中高：撞墙是本作的核心机制，再轻也得听得见。
const WALL_FLOOR := 0.2


## 招式 → 强度。
##
## 【为什么 duck-typing】调用点的 `mv` 静态类型是 Resource（信号签名如此），
## 缺 shake_amount 的资源给最轻档而不是崩 —— 反馈强度不值得把游戏搞挂。
static func from_move(mv: Resource) -> float:
	if mv == null:
		return SHAKE_FLOOR
	var v: Variant = mv.get(&"shake_amount")
	return from_shake(float(v)) if v != null else SHAKE_FLOOR


static func from_shake(shake_amount: float) -> float:
	return clampf(shake_amount / SHAKE_FULL, SHAKE_FLOOR, 1.0)


static func from_wall_speed(impact_speed: float) -> float:
	return clampf(impact_speed / WALL_FULL_SPEED, WALL_FLOOR, 1.0)
