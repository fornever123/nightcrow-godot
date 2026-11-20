extends SceneTree
## C1 + C2 首领战「断潮」全量自动化回归测试：
##   · 字体合规（禁用 SystemFont，全量 NotoSerifSC / PirataOne / Cinzel）
##   · GodotStateCharts 三轨并行状态机 & WigglyAppendage2D 无头物理长尾
##   · 单屏宽幅实心哥特断柱决斗台 + 5:59 发光巨钟 + 湿石镜面倒影 + 二阶段裂钟破晓金光
##   · 白金凝壳（免疫轻击挑飞、弹刀/绕背碎壳、破壳 0.15s 慢放、真挑飞无 3 秒强制翻身）
##   · 越打飞越远 + 冲刺追斩 + 轰撞两侧石柱大伤 + 落地气浪重披白壳
##   · 单轮 >=35% 血「断甲重创」爆出额外改造核（绝不锁血）
##   · 半血二阶段「红裂口」弹刀/重斩染紫反杀
##   · 既有兼容机制（亮相、空连给跳、短闪强化、红白刀、钉尾与拽回、胜负结算）
##
## 运行：godot --headless --fixed-fps 60 --path . --script res://tests/test_boss_sample.gd

const Shade := preload("res://scripts/night/shade.gd")
const Scene := preload("res://scripts/boss_sample/boss_sample.gd")

var stage
var p
var boss
var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	call_deferred("run")


func wait(n: int) -> void:
	for _i in n:
		await physics_frame


## 将首领、玩家与场地重置到干净的一阶段满白金凝壳对峙状态
func reset(boss_active := false, broken := false) -> void:
	paused = false
	Engine.time_scale = 1.0
	stage.won = false
	stage._slowmo_token += 1
	boss.skip_intro()
	boss.reset_boss_state()
	if stage.backdrop != null and stage.backdrop.has_method(&"reset_phase"):
		stage.backdrop.reset_phase()
	boss.active = boss_active
	boss.state = Shade.State.IDLE
	boss.hitstop_frames = 0
	boss.juggle_count = 0
	boss.combo_taken = 0
	boss.velocity = Vector2.ZERO
	boss._steps = []
	boss._cur = {}
	boss.cooldown = 9999
	boss.hp = boss.max_hp
	boss.total_damage_taken = 0.0
	boss.facing = -1
	boss.position = Vector2(stage.arena_center, boss.ground_y())
	boss.position.y = boss.ground_y()
	if broken:
		boss._shatter_shell(boss.global_position, 0)
		Engine.time_scale = 1.0
		stage._slowmo_token += 1
		boss.state = Shade.State.IDLE
		boss.hitstop_frames = 0
		boss.velocity = Vector2.ZERO
	p.reset_state(Vector2(stage.arena_center - 200.0, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	p.invuln_frames = 0
	p.hp = p.max_hp
	p.attack_damage_mul = 1.0
	if stage.frozen_rig != null:
		stage.frozen_rig.reset_state()
	stage.dodge._heavy = 0
	stage.dodge._left = 0
	stage.dodge._cool = 0
	await wait(2)


func start_at_strike(id: StringName) -> void:
	boss._start_string(id)
	boss.state_frames = int(boss.spec.windup) - 1
	await physics_frame


func run() -> void:
	stage = Scene.new()
	root.add_child(stage)
	await process_frame
	await wait(3)
	p = stage.player
	boss = stage.boss

	check(boss != null and is_equal_approx(boss.max_hp, 2000.0), "断潮最大生命 2000")
	check(Shade.KINDS[Shade.Kind.BRUTE].hp < 1000.0, "普通甲影KINDS表未被污染")

	await test_intro()
	await test_fonts_and_addons()
	await test_c2_clock_duel_arena()
	await test_platinum_shell_and_break()
	await test_escalating_fling_pursuit_pillar_and_reforge()
	await test_armor_sever_35pct_no_hp_lock()
	await test_phase2_red_rift_dyed_purple()
	await test_jump_rewards()
	await test_red_and_dodge()
	await test_nail_and_tether()
	await test_c3_new_skills_and_hd_art()
	await test_c4_rooftop_frozen_hp_anti_air_and_rewind()
	await test_body_and_reach()
	await test_lose_and_win()

	# 退出前彻底清理场景与基类静态缓存，确保 0 资源与节点泄漏
	paused = false
	Engine.time_scale = 1.0
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	await process_frame
	await wait(3)
	Shade._font = null
	Shade._flat_mats.clear()

	print("BOSS_SAMPLE_TESTS: %d checks / %d failures" % [checks, failures.size()])
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)


# ---------------------------------------------------------------- 1. 亮相、字体合规、插件栈与 C2 巨钟决斗台

func test_intro() -> void:
	check(boss.intro_frames > 0, "开场处于母钟塔顶高空天降俯冲亮相")
	check(boss.position.y < boss._intro_ground and boss.spawn_frames == 0, "亮相起点在塔顶高空且 100% 实心不透明（根除地底穿模与半透重影）")
	check(not boss.is_open(), "亮相期间不是破口空档")
	var hp0: float = boss.hp
	check(not boss.take_hit(p.up_strike_move, 1, boss.global_position, 0.0, true, 1.0, p), "亮相期间不可受击")
	check(is_equal_approx(boss.hp, hp0) and boss.state != Shade.State.LAUNCHED, "亮相期间不掉血不挑飞")
	var time0: float = stage.fight_time
	await wait(4)
	check(is_equal_approx(stage.fight_time, time0), "亮相期间战斗计时暂停")
	var done := [0]
	var on_done := func(): done[0] += 1
	boss.intro_done.connect(on_done)
	boss.skip_intro()
	check(boss.intro_frames == 0 and done[0] == 1, "可跳过亮相并发出 intro_done")
	check(is_equal_approx(boss.position.y, boss._intro_ground), "亮相结束稳稳落在决斗台面")
	boss.intro_done.disconnect(on_done)


func test_fonts_and_addons() -> void:
	await reset()
	# 1) 字体检查：严禁 SystemFont
	var bar_script_src := FileAccess.get_file_as_string("res://scripts/boss_sample/boss_bar.gd")
	check(not bar_script_src.contains("SystemFont"), "boss_bar.gd 已彻底清理 SystemFont")
	var bar: Control = stage.get_node_or_null("BossBarLayer/BossBar")
	check(bar != null, "BossBar 已挂载")
	if bar != null:
		check(bar.font_cn != null and not (bar.font_cn is SystemFont), "BossBar 中文使用 NotoSerifSC-VF.ttf 而非 SystemFont")
		check(bar.font_gothic != null and not (bar.font_gothic is SystemFont), "BossBar 哥特字体加载成功")
		check(bar.font_roman != null and not (bar.font_roman is SystemFont), "BossBar 罗马刻度字体 Cinzel-VF 加载成功")

	# 2) 旧版强制 3 秒翻身与三段穿墙换场已移除
	check(not boss.has_method(&"_escape"), "已彻底移除 3 秒强制空中翻身 _escape")
	check(not stage.has_method(&"_break_through"), "已彻底移除三段撞墙换场 _break_through")
	check(is_equal_approx(boss.half_h, 140.0), "断潮碰撞半高提升至 140（配合角冠蝎尾构成 ~280px 屏幕剪影）")

	# 3) GodotStateCharts 并行三轨状态树验证
	check(boss.state_chart != null and boss.state_chart is StateChart, "断潮已挂载 GodotStateCharts")
	check(boss.state_chart.get_child_count() == 1 and boss.state_chart.get_child(0) is ParallelState, "StateChart 拥有唯一 ParallelState 根节点 BossBrain")
	check(boss._sc_phase1.active and not boss._sc_phase2.active, "StateChart 初始处于 Phase1")
	check(boss._sc_shell_intact.active and not boss._sc_shell_broken.active, "StateChart 初始处于 ShellIntact")
	check(boss._sc_rift_idle.active and not boss._sc_rift_active.active, "StateChart 初始处于 RiftIdle")

	# 4) WigglyAppendage2D 无头物理长尾验证
	check(boss.wiggly_tail != null and boss.wiggly_tail is WigglyAppendage2D, "断潮已挂载 WigglyAppendage2D 物理长尾")
	check(boss.wiggly_tail.only_process_when_visible == false, "WigglyAppendage2D 设 only_process_when_visible = false 支持无头解算")
	await wait(4)
	check(boss.wiggly_tail.points.size() > boss.wiggly_tail.segment_count, "WigglyAppendage2D 已生成细分长尾顶点（%d 个）" % boss.wiggly_tail.points.size())
	boss.facing = 1
	boss.position.x += 160.0
	await wait(4)
	boss.facing = -1
	boss.position.x -= 160.0
	await wait(4)
	var tail_finite := true
	for pt: Vector2 in boss.wiggly_tail.points:
		if is_nan(pt.x) or is_nan(pt.y) or is_inf(pt.x) or is_inf(pt.y):
			tail_finite = false
	check(tail_finite, "WigglyAppendage2D 在左右转向与位移后全部顶点有限无 NaN")


func test_c2_clock_duel_arena() -> void:
	await reset()
	var back = stage.backdrop
	check(back != null, "BossBackdrop 已挂载")
	check(is_equal_approx(stage.FIGHT_HALF, 2400.0) and is_equal_approx(stage.seal_x.y - stage.seal_x.x, 4800.0), "决斗天廊升级为 4800u 全尺寸 2.5 屏宽幅舞台（对齐主游戏标准）")
	check(stage.terrain.blocks.is_empty() and stage.terrain.platforms.size() == 5 and is_equal_approx(stage.terrain.support_y(stage.arena_center, 0.0), stage.floor_y), "中央 3124u 钟前主决斗桥 100% 平整贯通，两侧悬挂真石阶斜坡与哥特翼台")
	check(back._clock_mat != null and back._mirror_mat != null and back.clock_rig != null, "5:59 暗朱红磨砂母钟 7 层光学总成与湿青石板薄镜倒影着色器均已就绪")
	check(back.CLOCK_RADIUS >= 640.0, "5:59 暗朱红母钟直径 1320u 完整入画压顶（R=%.0f）" % back.CLOCK_RADIUS)
	var rig = back.clock_rig
	check(rig._frame_sprite != null and rig._glass_sprite != null and rig._minute_sprite != null and rig._hour_sprite != null and rig._gear_sprites.size() >= 3 and rig._shards.size() == 24, "母钟哥特铁窗花外框、磨砂红玻璃、十米分针/时针、三层青铜齿轮与 24 块崩裂红玻璃残片全部挂载")
	var angles: Vector2 = back.get_clock_angles()
	check(absf(angles.x - (-PI * 0.5 + TAU * (359.0 / 720.0))) < 0.08, "时针停驻于 5:59")
	check(absf(angles.y - (-PI * 0.5 + TAU * (59.0 / 60.0))) < 0.12, "分针死卡在 59 分（距 XII 仅差一格并周期蓄压震颤）")
	check(not back.phase2_cracked and is_equal_approx(back.crack_amount, 0.0), "初始常态母钟完好呈暗朱红超载心跳")

	# 验证红钟五重核心动效切换（常态卡死 -> 时间倒流狂转 -> 钟窗崩裂 24 残片悬停 -> 碎钟时间倒流螺旋重拼 -> 6:00 破晓）
	var m0: float = rig.minute_angle
	back.set_rewind_visual(1.0)
	await wait(14)
	check(rig.rewind_amt > 0.45 and rig.minute_angle < m0 - 0.5, "动效三：时间倒流触发十米分针高速逆时针疯转与扇形残影")
	back.set_rewind_visual(0.0)
	back.trigger_phase2_shatter()
	await wait(26)
	check(back.phase2_cracked and rig.shatter_amt > 0.65 and rig._shards[0].node.visible, "动效四：暗朱红磨砂钟窗轰然崩裂，24 块厚红玻璃残片低重力悬停自转")
	var shat_before_rew: float = rig.shatter_amt
	back.set_rewind_visual(1.0)
	await wait(24)
	check(rig.shatter_amt < shat_before_rew - 0.35, "组合奇观：碎钟态触发时间倒流时，24 块红玻璃残片沿螺旋轨迹倒吸重拼回表盘！")
	back.trigger_victory_dawn()
	await wait(20)
	check(rig.dawn_calm > 0.30, "动效五：终局一剑贯通 6:00，超载暗朱红警戒光平息散尽")
	back.reset_phase()


# ---------------------------------------------------------------- 2. C1 机制一：白金凝壳（防轻击挑飞、弹刀/绕背碎壳、0.15s 慢放、真挑飞）

func test_platinum_shell_and_break() -> void:
	await reset()
	# 1) 有白金凝壳时：正面轻击不进硬直，上挑无法挑飞并触发提示
	var hp0: float = boss.hp
	var sh0: float = boss.shell
	boss.take_hit(p.light_combo[0], 1, boss.global_position, 0.0, false, 1.0, p)
	var mitigated_dmg: float = hp0 - boss.hp
	check(boss.state == Shade.State.IDLE, "有白金凝壳时正面轻击不打断断潮")
	check(boss.shell < sh0 and boss.shell > 85.0, "正面轻击仅微弱削减凝壳（剩余 %.1f）" % boss.shell)

	var held_cnt := [0]
	var on_held := func(): held_cnt[0] += 1
	boss.armor_held.connect(on_held)
	boss.take_hit(p.up_strike_move, 1, boss.global_position, 0.0, true, 1.0, p)
	check(boss.state != Shade.State.LAUNCHED and held_cnt[0] == 1, "有白金凝壳时免疫挑飞并发出凝壳提示")
	boss.armor_held.disconnect(on_held)

	# 2) 迎面弹刀 / 碰刀大幅碎壳 + 破壳瞬间 0.15s 慢放
	await reset()
	var slowmo_seen := [false]
	var shattered_cnt := [0]
	var on_shatter := func(_pt: Vector2):
		shattered_cnt[0] += 1
	boss.shell_shattered.connect(on_shatter)
	boss.global_position.x = p.global_position.x + 170.0
	boss.facing = -1
	p._set_facing(1)

	await start_at_strike(&"triple")
	boss._blade_age = 0
	boss.state = Shade.State.STRIKE
	boss._cur = boss._steps[0]
	boss._strike_check()
	check(boss.shell <= 65.0 and not boss.is_shell_broken, "三连第 1 刀迎面碰刀大幅削减白金凝壳（剩余 %.1f）" % boss.shell)

	boss._step = 1
	boss.on_parried(p)
	check(boss.shell <= 30.0 and not boss.is_shell_broken, "三连第 2 刀弹刀继续大幅碎壳（剩余 %.1f）" % boss.shell)

	boss._step = 2
	boss.state = Shade.State.STRIKE
	boss.on_parried(p)
	await process_frame
	slowmo_seen[0] = Engine.time_scale < 0.5
	check(shattered_cnt[0] == 1 and boss.is_shell_broken and boss._sc_shell_broken.active, "三连末刀弹刀彻底震碎白金凝壳，StateChart 切入 ShellBroken")
	check(slowmo_seen[0] and is_equal_approx(stage.last_slowmo_duration, 0.15), "破壳瞬间触发 0.15s 慢放（time_scale=%.2f）" % Engine.time_scale)
	check(boss.state == Shade.State.LAUNCHED, "末刀弹刀破壳直接把断潮震飞上天")
	await create_timer(0.20, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "0.15s 破壳慢放结束后自动恢复常速")
	boss.shell_shattered.disconnect(on_shatter)

	# 3) 绕背偷袭大幅碎壳 -> 破口期刀刀真伤 + 真挑飞（超 3 秒不强制翻身！）
	await reset()
	boss.facing = -1   # 断潮面朝左，右侧（+X）是它后背
	p.global_position.x = boss.global_position.x + 120.0
	p._set_facing(-1)
	boss.take_hit(p.light_combo[0], -1, boss.global_position, 0.0, false, 1.7, p)
	check(boss.shell <= 45.0 and not boss.is_shell_broken, "第 1 刀重背刺大幅碎壳（剩余 %.1f）" % boss.shell)
	boss.take_hit(p.light_combo[1], -1, boss.global_position, 0.0, false, 1.0, p)
	check(boss.is_shell_broken and boss._sc_shell_broken.active, "第 2 刀连续绕背偷袭直接破壳")
	Engine.time_scale = 1.0
	stage._slowmo_token += 1

	var hp_before_true: float = boss.hp
	boss.take_hit(p.light_combo[0], -1, boss.global_position, 0.0, false, 1.0, p)
	var true_dmg: float = hp_before_true - boss.hp
	check(true_dmg > mitigated_dmg * 2.2, "破口期刀刀真伤（真伤 %.1f vs 有壳 %.1f）" % [true_dmg, mitigated_dmg])

	boss.hp = 50000.0
	boss.max_hp = 50000.0
	boss.take_hit(p.up_strike_move, 1, boss.global_position, 0.0, true, 1.0, p)
	check(boss.state == Shade.State.LAUNCHED, "破口期可被 W+J 真挑飞上天")

	# 连续托举超过 210 帧（3.5 秒，远超旧版 180 帧强制翻身），验证绝无生硬强制翻身！
	var stayed_air_210 := true
	for f in 210:
		if boss.hitstop_frames <= 0 and f % 12 == 10:
			boss.juggle_count = 2
			boss.take_hit(p.air_combo[0], 1, boss.global_position, 0.0, false, 1.0, p)
		await physics_frame
		if boss.state != Shade.State.LAUNCHED:
			stayed_air_210 = false
			break
	check(stayed_air_210, "破口真挑飞持续连击 >3.5 秒（210 帧）仍稳居空中，无 3 秒生硬强制翻身")
	boss.max_hp = 2000.0


# ---------------------------------------------------------------- 3. C1 机制二：越打飞越远 + 冲刺追斩 + 轰撞石柱 + 落地气浪重披白壳

func test_escalating_fling_pursuit_pillar_and_reforge() -> void:
	await reset(false, true)
	boss.hp = 20000.0
	boss.max_hp = 20000.0
	boss.position = Vector2(stage.arena_center - 500.0, boss.ground_y())
	boss.take_hit(p.up_strike_move, 1, boss.global_position, 0.0, true, 1.0, p)
	check(boss.state == Shade.State.LAUNCHED, "进入空中破口连段")

	# 1) 越打飞越远：连续三轮空连末刀收尾，弹射速度逐轮递增
	boss.take_hit(p.air_combo[2], 1, boss.global_position, 0.0, false, 1.0, p)
	var v1: float = boss.last_fling_speed
	boss.position.x = stage.arena_center - 500.0
	boss.take_hit(p.air_combo[2], 1, boss.global_position, 0.0, false, 1.0, p)
	var v2: float = boss.last_fling_speed
	boss.position.x = stage.arena_center - 500.0
	boss.take_hit(p.air_combo[2], 1, boss.global_position, 0.0, false, 1.0, p)
	var v3: float = boss.last_fling_speed
	check(v1 > 450.0 and v2 > v1 + 200.0 and v3 > v2 + 200.0, "越打飞越远：三轮连段弹射速度递增（%.0f -> %.0f -> %.0f）" % [v1, v2, v3])

	# 2) 冲刺追斩：高速弹飞中途用冲刺斩截停托起续连
	var pursuits := [0]
	var on_pursuit := func(_pt: Vector2, cnt: int): pursuits[0] = cnt
	boss.pursuit_slashed.connect(on_pursuit)
	boss.position = Vector2(stage.arena_center, boss.ground_y() - 180.0)
	boss.velocity = Vector2(920.0, 120.0)
	if p.dash_move != null:
		boss.take_hit(p.dash_move, 1, boss.global_position, 0.0, false, 1.0, p)
		check(pursuits[0] >= 1 and absf(boss.velocity.x) < 300.0 and boss.velocity.y < -250.0, "冲刺追斩成功截停远飞首领并重新托起续连")
	boss.pursuit_slashed.disconnect(on_pursuit)

	# 3) 轰撞两侧哥特实心石柱：高额反弹大伤、石柱裂光，绝不穿墙换场！
	var pillar_hits := []
	var on_wall := func(sp: float, dmg: float, _pt: Vector2): pillar_hits.append([sp, dmg])
	boss.wall_slam.connect(on_wall)
	boss.position = Vector2(stage.seal_x.y - 95.0, boss.ground_y() - 200.0)
	boss.velocity = Vector2(1280.0, -140.0)
	boss.driven_frames = 14
	boss.hitstop_frames = 0
	var hp_pre_pillar: float = boss.hp
	await wait(5)
	check(pillar_hits.size() == 1 and float(pillar_hits[0][1]) >= 150.0, "横轰撞上右侧哥特断柱造成高额大伤（%.1f）" % (float(pillar_hits[0][1]) if not pillar_hits.is_empty() else 0.0))
	check(boss.hp < hp_pre_pillar - 140.0, "撞柱真实扣血")
	check(boss.velocity.x < -200.0, "撞上哥特断柱后向场内反弹（vx=%.0f）" % boss.velocity.x)
	check(is_equal_approx(stage.seal_x.y, stage.arena_center + stage.FIGHT_HALF), "单屏实心石柱稳固不换场")
	check(stage.backdrop._pillar_glow_r > 0.0, "右侧哥特断柱触发发光裂纹与碎石反馈")
	boss.wall_slam.disconnect(on_wall)

	# 4) 落地起身震开气浪、重新披上满额白金凝壳
	boss.max_hp = 2000.0
	boss.hp = 1600.0
	var wave_cnt := [0]
	var on_wave := func(_pt: Vector2): wave_cnt[0] += 1
	boss.shell_reforged_wave.connect(on_wave)
	boss.position = Vector2(stage.arena_center, boss.ground_y() - 120.0)
	boss.velocity = Vector2(0.0, 900.0)
	boss.bounces = 1
	boss.hitstop_frames = 0
	p.global_position = Vector2(stage.arena_center - 110.0, stage.floor_y - p.foot_offset)
	p.velocity = Vector2.ZERO
	var frames_waited := 0
	while boss.is_shell_broken and frames_waited < 120:
		await physics_frame
		frames_waited += 1
	check(not boss.is_shell_broken and is_equal_approx(boss.shell, boss.max_shell), "落地起身重新披上满额白金凝壳（%d 帧）" % frames_waited)
	check(boss._sc_shell_intact.active, "StateChart 切回 ShellIntact")
	check(wave_cnt[0] == 1, "起身瞬间释放重铸气浪信号")
	check(p.global_position.x < stage.arena_center - 150.0 or p.velocity.x < -100.0, "贴身贪刀玩家被重铸气浪震退")
	boss.shell_reforged_wave.disconnect(on_wave)


# ---------------------------------------------------------------- 4. C1 机制三：单轮 35% 血「断甲重创」爆核（绝不锁血）

func test_armor_sever_35pct_no_hp_lock() -> void:
	await reset(false, true)
	var severs := []
	var on_sever := func(_pt: Vector2, cores: int): severs.append(cores)
	boss.armor_severed.connect(on_sever)

	# 2000 血的 35% = 700 伤害
	boss._apply_damage(520.0)
	check(not boss.is_breach_severed() and boss.core_drops == 0, "单轮破口累计 520 伤害（26%）尚未触发断甲重创")
	boss._apply_damage(210.0)
	check(boss.is_breach_severed() and boss.core_drops == 1 and severs.size() == 1, "单轮破口累计 730 伤害（>=35%）触发「断甲重创」并掉落额外改造核 +1")
	boss._apply_damage(300.0)
	check(boss.core_drops == 1, "同一轮破口内不重复刷核")
	check(is_equal_approx(boss.hp, 2000.0 - 1030.0), "跨越 35% 断甲线与 50% 二阶段线时真实扣血至 970，绝不锁血！")

	# 验证一击满血秒杀也绝不锁血
	await reset(false, true)
	boss._apply_damage(2500.0)
	check(boss.hp <= 0.0, "单次超额伤害直穿到底，绝无锁血保护")
	boss.armor_severed.disconnect(on_sever)


# ---------------------------------------------------------------- 5. C1 机制四 + C2 二阶段：50% 血裂钟金光 + 红裂口弹刀/重斩染紫反杀

func test_phase2_red_rift_dyed_purple() -> void:
	await reset()
	var p2_signals := [0]
	var on_p2 := func(): p2_signals[0] += 1
	boss.phase2_started.connect(on_p2)

	# 打进 50% 半血（<= 1000 HP）
	boss._apply_damage(1020.0)
	await wait(4)
	check(boss.is_phase2 and boss._sc_phase2.active and p2_signals[0] == 1, "HP <= 50% 进入破晓二阶段，StateChart 切入 Phase2")
	check(stage.backdrop.phase2_cracked and stage.backdrop.crack_amount > 0.0, "二阶段 5:59 大钟盘轰然震裂，透出破晓金光（crack=%.2f）" % stage.backdrop.crack_amount)
	boss.phase2_started.disconnect(on_p2)

	# 方式 A：断潮挥爪撕开危险红裂口，玩家【弹刀】将其染紫反炸断潮！
	var dyed_events := []
	var on_dyed := func(_pt: Vector2, dmg: float): dyed_events.append(dmg)
	boss.rift_dyed_exploded.connect(on_dyed)

	boss.shell = boss.max_shell
	boss.is_shell_broken = false
	boss.state_chart.send_event(&"shell_reforged")
	boss.facing = -1
	boss.position = Vector2(stage.arena_center + 120.0, boss.ground_y())
	p.reset_state(Vector2(stage.arena_center - 95.0, stage.floor_y - p.foot_offset))
	p._set_facing(1)

	await start_at_strike(&"red_rift")
	await wait(3)
	check(boss.rift_state == boss.Rift.ACTIVE and boss._sc_rift_active.active, "断潮二阶段挥爪撕开危险红黑裂口（RiftActive）")

	var hp_before_purple: float = boss.hp
	p._start_move(p.parry_move, false)
	await wait(3)
	check(dyed_events.size() == 1 and boss.dyed_rift_count == 1, "玩家对红裂口弹刀成功将其「染紫」反炸！")
	check(boss.rift_state == boss.Rift.PURPLE, "裂口状态变为紫裂反噬（Rift.PURPLE）")
	check(boss.hp <= hp_before_purple - boss.RIFT_PURPLE_DAMAGE + 0.1, "紫裂反杀对断潮造成 %.0f 高额反噬真伤" % boss.RIFT_PURPLE_DAMAGE)
	check(boss.is_shell_broken and boss.state == Shade.State.LAUNCHED, "紫裂反杀直接炸碎白金凝壳并将断潮炸飞上天")

	# 方式 B：玩家用【重斩】（蓄力斩 / 短闪重刀）将红裂口染紫反杀！
	await wait(28)
	boss.state = Shade.State.IDLE
	boss.velocity = Vector2.ZERO
	boss.position = Vector2(stage.arena_center + 120.0, boss.ground_y())
	boss.hp = 950.0
	boss._reforge_shell()
	p.reset_state(Vector2(stage.arena_center - 95.0, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	boss.open_red_rift(Vector2(stage.arena_center - 30.0, boss.global_position.y - 40.0))
	await physics_frame
	check(boss.rift_state == boss.Rift.ACTIVE, "第二次开启红裂口")

	var hp_before_heavy: float = boss.hp
	stage.dodge.arm_heavy()
	boss.take_hit(p.charge_move if p.charge_move != null else p.light_combo[2], 1, boss.rift_pos, 0.5, false, p.attack_damage_mul, p)
	check(dyed_events.size() == 2 and boss.dyed_rift_count == 2, "重斩同样将红裂口染紫反炸断潮")
	check(boss.hp <= hp_before_heavy - boss.RIFT_PURPLE_DAMAGE + 0.1 and boss.is_shell_broken, "重斩染紫造成满额反炸真伤并破除白壳")
	boss.rift_dyed_exploded.disconnect(on_dyed)

	# 方式 C：若对红裂口置之不理，到时间赤黑爆炸伤人
	await reset()
	boss._enter_phase2()
	p.hp = p.max_hp
	p.invuln_frames = 0
	boss.open_red_rift(p.global_position)
	boss.rift_timer = 2
	await wait(4)
	check(boss.rift_state == boss.Rift.NONE and p.hp < p.max_hp, "未处理的红裂口超时引爆伤及贴身玩家并闭合")


# ---------------------------------------------------------------- 6. 既有兼容机制：空连给跳、红光与短闪、钉尾与拽回、身位与结算

func _hit(ar, target_node, mv, pt) -> void:
	ar.force_new_swing = true
	ar._on_hit_confirmed(target_node, mv, pt)


func _frame(a: Array, axis := Vector2.ZERO):
	var x := preload("res://scripts/core/input_buffer.gd").Frame.new()
	var acts: Array[StringName] = []
	for v in a:
		acts.append(v)
	x.actions = acts
	x.pressed_this_frame = acts.duplicate()
	x.axis = axis
	return x


func test_jump_rewards() -> void:
	await reset(false, true)
	var ar = stage.air_rules
	check(ar.dodge == stage.dodge, "AirRules 关联 Dodge")
	var pt: Vector2 = boss.global_position
	p.global_position.y -= 400.0
	p.bonus_air_jumps = 0
	ar.last_source = &""
	ar.given.clear()
	ar._swing_is_flash = false
	_hit(ar, boss, p.air_combo[0], pt)
	_hit(ar, boss, p.air_combo[1], pt)
	check(p.bonus_air_jumps == 0, "空a1、空a2 不给跳")
	stage.dodge._air_used = true
	_hit(ar, boss, p.air_combo[2], pt)
	check(p.bonus_air_jumps == 1 and not stage.dodge._air_used, "空a3 给跳并归还空中短闪")

	# 真按键破口挑飞接空中三连
	await reset(false, true)
	boss.hp = 50000.0
	boss.max_hp = 50000.0
	boss.global_position.x = p.global_position.x + 145.0
	boss.facing = -1
	p._set_facing(1)
	var hits: Array = []
	var on_hit := func(_t, m, _q): hits.append(String(m.id))
	p.hit_confirmed.connect(on_hit)
	p.set_injected_frame(_frame([&"jump"]))
	await physics_frame
	boss.take_hit(p.up_strike_move, 1, boss.global_position, 0.0, true, 1.0, p)
	for f in 70:
		var a: Array[StringName] = []
		var dx: float = boss.global_position.x - p.global_position.x
		if f % 6 == 0:
			a.append(&"attack_light")
		p._set_facing(1 if dx > 0.0 else -1)
		p.set_injected_frame(_frame(a, Vector2(signf(dx) if absf(dx) > 110.0 else 0.0, 0.0)))
		await physics_frame
	p.hit_confirmed.disconnect(on_hit)
	p.set_injected_frame(_frame([]))
	var air_hits := hits.filter(func(h): return h.begins_with("air_light"))
	check(air_hits.size() >= 3, "破口挑飞后真按键可稳定打出空中三连（%d 下）" % air_hits.size())
	boss.max_hp = 2000.0


func test_red_and_dodge() -> void:
	await reset()
	boss.global_position.x = p.global_position.x + 170.0
	boss.facing = -1
	boss._start_string(&"sweep")
	boss._blade_age = 0
	var hp0: float = p.hp
	boss._strike_check()
	check(p.hp < hp0, "红光横扫不可拼刀")

	await reset()
	await wait(15)
	boss.global_position.x = p.global_position.x + 170.0
	boss.facing = -1
	boss._start_string(&"sweep")
	stage.dodge.request(1)
	await physics_frame
	hp0 = p.hp
	boss._strike_check()
	check(is_equal_approx(p.hp, hp0) and stage.dodge.is_heavy(), "短闪穿过红光无伤并使下一刀变重")


func test_nail_and_tether() -> void:
	await reset(true, true)
	boss.facing = -1
	boss._start_string(&"nail")
	check(boss.nail_phase == boss.Nail.AIM, "钉尾进入瞄准")
	var hp0: float = p.hp
	while boss.state == Shade.State.WINDUP:
		await physics_frame
	await wait(4)
	check(boss.nail_phase == boss.Nail.STUCK and p.hp < hp0, "钉尾命中原地不动的主角并插入地面")

	# 尾刃钉地期间破口打飞过远触发拽回重摔
	await reset(false, true)
	boss._start_string(&"nail")
	boss.state_frames = int(boss.spec.windup) - 1
	p.global_position.x = boss.nail_point.x - 500.0
	await wait(12)
	check(boss.nail_phase == boss.Nail.STUCK, "走开躲过钉尾后尾刃钉在地面")
	var nail_x: float = boss.nail_point.x
	boss.state = Shade.State.LAUNCHED
	boss.position = Vector2(nail_x + boss.TETHER_LEN - 30.0, boss.ground_y() - 220.0)
	boss.velocity = Vector2(1300.0, -100.0)
	var slams := []
	var on_slam := func(d: float, q: Vector2): slams.append([d, q])
	boss.tether_slam.connect(on_slam)
	var f := 0
	while slams.is_empty() and f < 120:
		await physics_frame
		f += 1
	check(slams.size() == 1 and boss.yanks >= 1 and boss.state == Shade.State.LAUNCHED, "飞超尾长被拽回重摔并弹在半空继续追击")
	boss.tether_slam.disconnect(on_slam)


func test_c3_new_skills_and_hd_art() -> void:
	await reset()
	# 1) 高清双层场景与 18 帧 B1_单刃 图集就绪验证
	check(stage.backdrop.has_hd_arena_art(), "断晷水门远景/长堤/左右哥特断柱高清成图全部加载就绪")
	check(boss.has_hd_sprite_atlas(), "断潮 18 帧 B1_单刃 高清精灵图集与轮廓闪光遮罩加载就绪")

	# 2) 悬雨凝珠交互斩落验证
	var cut_drops: int = stage.backdrop.slash_rain_at(Vector2(stage.arena_center, stage.floor_y - 300.0), 420.0, Vector2.RIGHT)
	check(cut_drops > 0 and stage.backdrop.count_falling_rain() > 0, "刀锋掠过可斩断悬雨凝珠时间锁使其坠落（斩落 %d 颗）" % cut_drops)

	# 3) 「一线 · 瞬狱绝影」（horizon_cut）：居合蓄势压暗结界、瞬穿全场、弹刀重创 66% 白壳
	await reset()
	boss.position = Vector2(stage.arena_center + 280.0, boss.ground_y())
	boss.facing = -1
	p.reset_state(Vector2(stage.arena_center - 80.0, stage.floor_y - p.foot_offset))
	p._set_facing(1)
	boss._start_string(&"horizon_cut")
	await wait(16)
	check(boss._pick_atlas_frame() in [64, 65, 66, 67, 68, 69] and boss.eclipse_want > 0.25, "断晷一线切入极低伏居合 H3 连续帧 [64..69] 并压暗蚀光结界")
	var start_bx: float = boss.global_position.x
	boss.state_frames = int(boss.spec.windup) - 1
	await wait(4)
	check(boss.global_position.x < p.global_position.x - 100.0 and absf(boss.global_position.x - start_bx) >= 400.0, "一线瞬穿至主角身后远端并留下空间切线")
	check(bool(boss._horizon_scar.get("active", false)), "一线残留延迟次元白线刀痕")

	var sh_before: float = boss.shell
	var hp_p0: float = p.hp
	p._start_move(p.parry_move, false)
	await wait(3)
	check(boss.shell <= sh_before - 60.0 and is_equal_approx(p.hp, hp_p0), "弹反一线次元白线无伤并单次重创 >=65%% 白金凝壳（剩余 %.1f）" % boss.shell)

	# 4) 「尾月 · 裂水波」（sweep）：激射贴地裂水刃波 + Shift 短闪穿波攒重刀
	await reset()
	await wait(12)
	boss.position = Vector2(stage.arena_center + 380.0, boss.ground_y())
	boss.facing = -1
	p.reset_state(Vector2(stage.arena_center - 160.0, stage.floor_y - p.foot_offset))
	boss._start_string(&"sweep")
	boss.state_frames = int(boss.spec.windup) - 1
	await wait(4)
	check(boss._waves.size() >= 1, "尾月横扫激射出贴地骨白裂水刃波")
	# 将裂水刃波移近主角并用短闪穿过
	var hp_wave0: float = p.hp
	stage.dodge.request(1)
	await physics_frame
	if not boss._waves.is_empty():
		boss._waves[0]["pos"] = Vector2(p.global_position.x + 25.0, boss.feet_y())
	await wait(2)
	check(is_equal_approx(p.hp, hp_wave0) and stage.dodge.is_heavy(), "Shift 短闪穿过裂水刃波无伤并攒出强化重刀")

	# 5) 「悬雨 · 千针落」（rain_needles）：举刃向天帧 [5] 号令雨针 + 主角挥刀半空斩碎雨针
	await reset()
	boss.position = Vector2(stage.arena_center + 320.0, boss.ground_y())
	boss.facing = -1
	boss._start_string(&"rain_needles")
	await wait(2)
	check(boss._pick_atlas_frame() == 74, "坠针凝滞切入悬针号令帧 [74]")
	boss.state_frames = int(boss.spec.windup) - 1
	await wait(4)
	check(boss._rain_needles.size() >= 5, "坠针凝滞召唤出多枚刻度飞针（%d 枚）" % boss._rain_needles.size())
	# 将一枚激活雨针置于主角刀锋前方，主角弹刀/挥刀将其半空斩碎
	if not boss._rain_needles.is_empty():
		boss._rain_needles[0]["delay"] = 0
		boss._rain_needles[0]["pos"] = p.global_position + Vector2(60.0, -52.0)
		boss._rain_needles[0]["dir"] = Vector2(-0.25, 0.96).normalized()
	p._start_move(p.parry_move, false)
	await wait(2)
	check(boss.needles_cut >= 1, "主角挥刀/弹刀可在半空直接斩碎骨白雨针（已斩 %d 枚）" % boss.needles_cut)

	# 6) 二阶段觉醒必杀「断潮 · 破晓一刀」（sever_tide）：瞬步连斩并撕开红裂口
	await reset(true)
	boss._enter_phase2()
	boss.position = Vector2(stage.arena_center + 240.0, boss.ground_y())
	boss.facing = -1
	p.reset_state(Vector2(stage.arena_center - 420.0, stage.floor_y - p.foot_offset))
	boss._start_string(&"sever_tide")
	for step_i in 3:
		boss.state_frames = int(boss.spec.windup) - 1
		await wait(10 if step_i < 2 else 4)
	check(boss.rift_state == boss.Rift.ACTIVE, "二阶段觉醒必杀「破晓一刀」收尾撕开危险红黑裂口供玩家染紫反杀")


func test_c4_rooftop_frozen_hp_anti_air_and_rewind() -> void:
	await reset()
	# 1) 4800u 司辰母钟楼 · 钟前校时天廊（三联不重样法线受光成图 + 真斜坡翼台）检查
	check(stage.BOSS_NAME == "司辰母钟楼" and stage.ARENA_TITLE.begins_with("钟前校时天廊"), "舞台正名为「司辰母钟楼 · 钟前校时天廊 · 5:59」")
	check(stage.FIGHT_HALF >= 2400.0, "4800u 全尺寸宽幅天廊（FIGHT_HALF=%.0f）彻底根除局促窄盒" % stage.FIGHT_HALF)
	check(stage.backdrop._ctex_p1 != null and stage.backdrop._ctex_p1.normal_texture != null and stage.backdrop._player_light != null and stage.backdrop._lamps.size() == 2, "三联厚涂天廊法线 CanvasTexture、双翼煤气风灯与实时战斗 PointLight2D 光源组全部就绪")
	check(boss._vfx_tex != null and boss._atlas_tex.get_height() >= 5000, "底层动作与特效测试资源挂载正常")
	var bar_ctrl = stage.get_node_or_null("BossBarLayer/BossBar")
	check(bar_ctrl != null and bar_ctrl.has_gothic_hud_art(), "BossBar 节点挂载无报错")

	# 左翼盘旋阶高台 (y=223.4) 与右翼断链台 (y=286.4) + 真石阶斜坡物理支撑验证
	var left_xi_x: float = stage.arena_center - stage.FIGHT_HALF + 145.0
	var right_v_x: float = stage.arena_center + stage.FIGHT_HALF - 145.0
	var right_stair_mid_y: float = stage.terrain.support_y(stage.arena_center + 1611.2, 350.0)
	check(is_equal_approx(stage.terrain.support_y(left_xi_x, 180.0), stage.XI_MONUMENT_Y) and is_equal_approx(stage.terrain.support_y(right_v_x, 220.0), stage.V_MONUMENT_Y) and right_stair_mid_y > stage.V_MONUMENT_Y + 40.0 and right_stair_mid_y < stage.floor_y - 40.0, "左右双翼哥特高台与像素级真石阶斜坡物理支撑精准对齐")

	boss._start_string(&"backstep_pierce")
	await wait(18)
	check(boss._step == 1 and bool(boss._cur.get("pincer", false)), "差合技「错时退步 · 双针返刺」完成闪避后跃并切入合刺")

	# 立体高碑技 + 「弹针奉还 · 轰下石碑」验证！
	await reset(true, false)
	boss._start_string(&"spire_dive")
	check(boss.is_perched_on_monument() and boss._rain_needles.size() >= 5, "立体技「登碑悬针」跃上罗马字碑高台并俯射扇形刻度针")
	if not boss._rain_needles.is_empty():
		boss._rain_needles[0]["delay"] = 0
		boss._rain_needles[0]["pos"] = p.global_position + Vector2(52.0, -48.0)
	p._start_move(p.parry_move, false)
	await wait(18)
	check(not boss.is_perched_on_monument() and is_equal_approx(boss.feet_y(), stage.floor_y), "精准弹刀触发「弹针奉还」，刻度飞针超音速反钉首领胸口将其从罗马字碑直接轰坠地面！")

	# 双向时间倒流机制一：「5:59 过去锚点 · 斩断断轨自爆」验证！
	await reset(true, false)
	boss.spawn_chrono_anchor()
	check(boss.chrono_anchor_active, "司晷原地布下「5:59 过去残影锚点」")
	boss.shatter_chrono_anchor(p)
	check(not boss.chrono_anchor_active and boss.is_shell_broken and is_equal_approx(boss.shell, 0.0), "玩家一刀劈碎过去锚点触发「时间断轨自爆」，当场炸空司晷整管驻时棱壳！")

	# 双向时间倒流机制二：「逆时捉影（倒流玩家 2 秒前位置）+ 超音速迎面崩刃」验证！
	await reset(true, false)
	var past_px: float = stage.arena_center - 300.0
	p.reset_state(Vector2(past_px, stage.floor_y - p.foot_offset))
	boss.stamp_player_rewind_snare()
	p.global_position.x = stage.arena_center + 80.0
	p._start_move(p.parry_move, false)
	boss.player_snare_timer = 1
	await wait(2)
	check(absf(p.global_position.x - past_px) < 12.0 and boss.is_shell_broken and boss.state == Shade.State.HITSTUN and boss.state_frames >= 40, "司晷将玩家强行倒流回 2 秒前纯白时痕位置，迎面弹刀触发超音速崩刃并进入 >=40 帧真实大硬直！")

	# 验证完整连段 `_strike_check` 路径触发超音速迎面崩刃零空字典报错 + Shift 最后 16 帧扯断时痕 + 断壳爆核 +12% 真伤生效
	await reset(true, false)
	boss.position = Vector2(stage.arena_center + 200.0, boss.ground_y())
	p.reset_state(Vector2(stage.arena_center - 160.0, stage.floor_y - p.foot_offset))
	boss._start_string(&"player_snare")
	boss._step = 1
	boss._begin_step()
	boss.state_frames = int(boss.spec.windup) - 1
	p._start_move(p.parry_move, false)
	await wait(3)
	check(boss.is_shell_broken and boss._cur.is_empty(), "完整连段出刀帧触发超音速迎面崩刃安全收束且零空字典异常")

	await reset(true, false)
	boss.stamp_player_rewind_snare()
	boss.player_snare_timer = 12
	stage.dodge.request(1)
	await wait(3)
	check(not boss.player_snare_active and stage.dodge.is_heavy(), "最后 16 帧窗口按 Shift 短闪可直接扯断时间银弦并武装闪身重刃")

	await reset()

	# 2) 65%「驻时白血」零减速抢回 + 二次受击碎白血 + 弹刀 100% 满抢回
	var rig = stage.frozen_rig
	check(rig != null, "驻时白血组件 FrozenHpRig 已挂载")
	var base_speed: float = p.max_run_speed if "max_run_speed" in p else 1.0
	p.hp = p.max_hp - 40.0
	await wait(1)
	check(is_equal_approx(rig.frozen_hp, 26.0), "受击扣 40 血转化 65%% = 26.0 驻时白血（实测 %.1f）" % rig.frozen_hp)
	if "max_run_speed" in p:
		check(is_equal_approx(p.max_run_speed, base_speed), "驻时白血期间移速 0 惩罚")

	# 二次受击：旧 26 白血当场碎裂清零，仅保留新 20 伤的 65% = 13.0
	p.hp -= 20.0
	await wait(1)
	check(rig.shatter_count >= 1 and is_equal_approx(rig.frozen_hp, 13.0), "二次受击旧白血当场碎裂清零，仅保留新伤 65%% = 13.0（实测 %.1f）" % rig.frozen_hp)

	# 普攻抢回部分白血并延长停留时间，随后精准弹刀瞬间 100% 抢回全部剩余白血！
	var hp_pre_rally: float = p.hp
	var hold_pre: float = rig.hold_left
	var r1: float = rig.rally_from_attack(10.0, false)
	check(r1 > 4.0 and p.hp > hp_pre_rally and rig.hold_left > hold_pre, "出刀命中抢回白血并延长驻留窗口")
	var rem_frozen: float = rig.frozen_hp
	var r_full: float = rig.rally_full_on_parry()
	check(is_equal_approx(r_full, rem_frozen) and is_equal_approx(rig.frozen_hp, 0.0), "精准弹刀瞬间 100%% 抢回全部驻时白血")

	# 3) 格斗防空技「逆影升龙 · 截空斩」（anti_air）及空中弹反奖励
	await reset(true, false)
	boss.cooldown = 0
	boss._anti_air_cool = 0
	boss.position = Vector2(stage.arena_center + 140.0, boss.ground_y())
	p.global_position = Vector2(stage.arena_center - 40.0, stage.floor_y - 260.0)
	p.velocity = Vector2(0.0, -50.0)
	await wait(2)
	check(boss._string_id == &"anti_air", "玩家跳在首领头顶滞空时触发格斗防空技「逆影升龙 · 截空斩」")
	var sh_aa0: float = boss.shell
	p.bonus_air_jumps = 0
	boss.on_parried(p)
	check(boss.shell <= sh_aa0 - 44.0 and p.bonus_air_jumps >= 1 and boss._pick_atlas_frame() == 75, "空中弹反升龙斩重削 >=45%% 棱壳、返还二段跳并打出崩针大硬直帧 [75]")

	# 4) 战死 `5:59` 触底回溯白幕死寂演出（严禁改 Engine.time_scale！）
	await reset()
	var rw = stage.death_rewind
	check(rw != null, "5:59 触底回溯层 DeathRewindFx 已挂载")
	var dummy := Node2D.new()
	stage.add_child(dummy)
	rw.trigger_rewind([dummy], 48, null)
	check(rw.active and dummy.process_mode == Node.PROCESS_MODE_DISABLED and is_equal_approx(Engine.time_scale, 1.0), "战死回溯原帧冻结目标节点且严守 Engine.time_scale == 1.0")
	rw._process(0.20)
	check(AudioServer.is_bus_mute(0), "5:59 白幕定格期间静音主音频总线保持死寂")
	rw._process(0.80)
	check(not rw.active and not AudioServer.is_bus_mute(0) and dummy.process_mode != Node.PROCESS_MODE_DISABLED, "5:59 回溯收束后完整恢复节点与音频总线状态")
	dummy.queue_free()
	await process_frame


func test_body_and_reach() -> void:
	await reset(false)
	p.global_position.x = boss.global_position.x - 10.0
	await wait(2)
	check(absf(p.global_position.x - boss.global_position.x) >= boss.half_w + 20.0, "地面主角不会卡进断潮体内")
	p.global_position.x = boss.global_position.x - 125.0
	await wait(2)
	stage.dodge.request(1)
	await wait(12)
	check(p.global_position.x > boss.global_position.x + boss.half_w, "Shift 短闪可顺利穿到断潮背后进行背刺")

	await reset(true, true)
	boss.state = Shade.State.DOWN
	boss.down_frames = 20
	boss.take_hit(p.up_strike_move, 1, boss.global_position, 0.0, true, 1.0, p)
	check(boss.state == Shade.State.DOWN, "断潮倒地期间不会被无限上挑锁死，保证起身重铸白壳")


func test_lose_and_win() -> void:
	await reset(false, true)
	boss.yanks = 2
	boss.core_drops = 1
	boss.dyed_rift_count = 2
	boss.hp = 0.0
	boss._die(1)
	await physics_frame
	check(stage.won, "击败断潮标记胜利")
	check(Engine.time_scale < 1.0, "击杀瞬间慢放")
	await create_timer(stage.RESULT_DELAY + 0.3, true, false, true).timeout
	check(stage._result != null and is_instance_valid(stage._result), "弹出首领战结算面板")
	if stage._result != null:
		check(int(stage._result.summary.get("yanks", 0)) == 2, "结算面板记录拽回次数")
		check(int(stage._result.summary.get("cores", 0)) == 1, "结算面板记录断甲改造核数量")
		check(int(stage._result.summary.get("purple_rifts", 0)) == 2, "结算面板记录红裂口染紫反杀次数")
	check(paused, "结算面板暂停世界")
	check(stage.grade() in ["S", "A", "B", "C", "D"], "结算评级有效")
	stage.hits_taken = 0
