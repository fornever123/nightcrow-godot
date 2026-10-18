# 总交接（HANDOFF）· 试玩版任务 · 写给下一个接手的 AI

> 这是当前**最新、最高优先级**的交接文档。读完它，就等于读完了整段对话。
> 与 `docs/视觉设计/HANDOFF-美术.md`（2026-10-15，旧）冲突时，以本文为准；旧文里的协作规则、提示词写法仍有效。
> 每完成一个节点，必须更新本文的「§8 节点清单」「§9 进度日志」（战斗相关同时更新 §7），并同步到 GitHub。

---

## 0. 用户与协作规则（必读）

- 用户：卢佳宝。全程**简体中文**；常用**手机**看回复（短段落、少宽表格）；不懂编程，需要“双击就能用”的入口。
- 本轮用户原话（按时间）：
  1. “首先你看这个项目里面github上的更新，做出了大更新，替换了大部分序列帧和动作，我需要你大优化这个序列帧在游戏中的位置和使用时候的手感什么的，然后再放进这个场景里面，做无缝循环有效的demo。你先给我详细完整的计划”
  2. （看完计划后）“OK，然后我希望你能改仓库，想改什么改什么，权限应该有。然后我希望你自己调整战斗，让这个战斗符合我之前的主题（眩晕连段）的同时要好玩。你最后直接交给我一个试玩版。转身动画保留，但是你可以最大限度的更改。”
  3. “然后我希望你做好角色融入环境光线”
  4. “你要做一个完整的handoff，你每完成一个节点就写入，这个handoff要下一个接手你的ai能够直接相当于在这个对话一样完整的干好任何事情，知道任何需要的东西。”
- 授权：**可以随意改仓库代码和数据、自己调战斗、直接交付试玩版**（之前“不改代码、不调战斗”的规矩对本任务解除）。
- 仍然有效的老规矩：
  - 做大事前先给计划（本任务计划已获批，见 §6）。
  - **不用 AI 生图工具**。可以用代码画图、程序特效、合成检验图。需要新图时只写提示词给用户，每条提示词单独一个代码块，说明写在代码块外。
  - 评价用户发来的图之前，先读图并做合成检验。被纠正时直接认错。
  - 不用“夜鸦”当游戏名/题材/玩法依据（只是角色昵称）。配置里“夜鸦剑士”“夜鸦 · 木桩训练场”是历史遗留，不要在新内容里扩散。
  - 图片/文件要以文件形式发给用户。最终回复简短、适合手机看。
- “眩晕连段”的理解：仓库设计文档的核心是**浮空连段**（挑起→空中连段→决定终结方向→撞墙/撞地/连锁击飞），代码里已有 STUNNED（眩晕）状态。本任务按“**打满失衡 → 眩晕 → 挑飞 → 浮空连段 → 方向终结 → 连锁击飞**”来做，两种理解都覆盖。交付时要向用户说明这个理解。
- 用户已否决：穹环/钟塔题材（“不好看”）、紫色背景（会吃掉角色的紫发和紫刀光）、旧 HANDOFF 的“260px/像素化”方向（现在角色约 168px、不像素化、linear 采样）。

## 1. 项目基本事实

- GitHub：`fornever123/nightcrow-godot`（公开，main）。用户本机路径 `E:/00game/nightcrow-godot`。
- 沙盒工作副本：`/data/nightcrow-godot`（基线提交 `5c452fd`，2026-10-18）。
- Godot **4.7.2**，GDScript，GL Compatibility，窗口 1280×720。
- 入口：`project.godot` → `scenes/training.tscn` → `scripts/training.gd`（木桩训练场）。（试玩版完成后主场景改为夜景试玩，见 §8）
- 用户的双击入口：`OPEN_GAME.bat`（`engine/Godot_v4.7.2-stable_win64.exe --path .`；引擎 exe 只在用户本机，不在 Git 里）、`OPEN_MODIFIER.bat`（修改器，Vue+Pixi，`tools/battle-editor`，与游戏共用 `assets/data/battle.json`）、`SYNC_GITHUB.bat` / `上传更新到GitHub.bat`（**只上传**；GitHub 上有新提交时会拒绝，需先拉取）。
- 关键脚本：
  - `scripts/gameplay/player.gd`（状态机 NEUTRAL/ATTACK/LAUNCHED/DOWN/DEAD；输入缓冲、土狼 6 帧、跳跃缓冲 6 帧；三段普攻 `light_combo`、按住 J 蓄力、W+J 上挑、空中三连 `air_combo`、Shift+J 冲刺斩 `_process_dash_attack`、L 格挡/弹刀、转身 `_start_turn/_advance_locomotion`；**根位移** `_root_motion_step/_move_with_root_motion`（节点 1 新增））。
  - `scripts/gameplay/dummy.gd`（木桩：IDLE/HIT/LAUNCHED/DOWN/STUNNED/RESPAWNING；浮空伤害倍率 `1+0.2*min(juggle,4)`；撞墙二次伤害；stun 落地后转眩晕；信号 damaged/wall_slam/launched_state_changed/died/parried）。
  - `scripts/presentation/character_view.gd`（播放序列帧；攻击时帧号 = `Timeline.frame_at(clip, move_frame/60, move.animation_fps)`）、`art_cache.gd`（运行时从 `res://assets/` 读 PNG 字节→ImageTexture，**不走 Godot 导入**）。
  - `scripts/core/configuration.gd`（battle.json → MoveDefinition；`syncAnimation` 时 startup/active/recovery 由 activeFrameStart/End、chainFrame 按动画帧推导）、`move_definition.gd`。
- 贴图摆放（`art_cache.gd apply`）：缩放 = (frame.width/纹理宽)×displayScale；offset = -(pivotX×纹理宽/width, pivotY×纹理高/height)；角色节点位置 + foot_offset(84) = 脚底。`sourceFacing=-1` 原图朝左会翻转；`authoredTurn` 的转身片不随朝向翻转（像素里自己转）。
- battle.json：`characters[0]`（speed、acceleration 4800、jumpSpeed 642.2、maxJumps 2、hurtbox 50×156）；`sprite.displayScale=168/409`；`sprite.animations` 57 段（`source_*` 为原片 24 段，不要改）；每帧 `asset,width,height,pivotX,pivotY,durationTicks,…`；`sprite.locomotion`（turnRight/turnLeft 的 flipFrame/cancelFrame、landingCancelFrame）；`moves` 19 个；`stage.bounds` 左右 24/1256、floorY 580；`runtime.attackBufferFrames`。
- 原版帧归档 `art/game-ready-sequences/…`（不要改）；运行副本 `assets/image/desktop-actions*/`、`assets/image/selected-original/`。
- 其他文档：`docs/开发交接.md`、`docs/桌面动作接入说明.md`、`docs/游戏规划.md`、`docs/玩法内核候选方案.md`。

## 2. 沙盒环境（如何复现）

> 注意：沙盒可能被重置（2026-10-18 发生过一次：/data/tools、/data/work、交接文档全部丢失，仓库退回旧提交）。开工先检查，缺了就按下面重建。

- 仓库：`cd /data/nightcrow-godot && git fetch origin && git merge --ff-only origin/main`（沙盒 git 没有 push 凭据）。
- Godot Linux：`/data/tools/godot` → 下载 `https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` 解压后软链。
- 渲染：`sudo dnf install -y xorg-x11-server-Xvfb mesa-libGL mesa-libEGL mesa-dri-drivers libXcursor libXinerama libXrandr libXi alsa-lib pulseaudio-libs`，然后 `Xvfb :99 &`、`DISPLAY=:99`。
- 首次：`/data/tools/godot --headless --path . --import`（会生成一些未跟踪的 `.import` 文件，不要提交）。
- 测试：`/data/work/runtests.sh`（逐个跑 `godot --headless --fixed-fps 60 --path . --script res://tests/<name>.gd`，输出 “N checks / M failures”）。基线 220/0：training 32、combat_feedback 52、framebaker_runtime 52、locomotion 12、action_flow 45、desktop_integration 27。另有 node 测试 `tests/*.mjs`（修改器）。
- 场景原图是会话附件，沙盒重置后用 `upload_file_to_sandbox` 重新上传（file_id 见 §5）。
- 体检/检查脚本：`/data/seq-audit/{common,measure,sheet}.py`（`BJ=路径` 可指定 battle.json）。

## 3. 交付通道（重要限制）

- GitHub MCP（服务器名 “GitHub”）登录的是用户本人 `fornever123`，可用 `push_files` / `create_or_update_file` / `list_commits`，但**只能传文本**；`mcp_run_tool` 的 `arguments_file_path` ≤1 MiB。
  - 二进制图（场景图层）以 **base64 文本**存进仓库，运行时 `Marshalls.base64_to_raw` + `Image.load_*_from_buffer` 解码。
  - battle.json 约 1MB+，推送时用紧凑 JSON 或拆分，确保参数文件 <1 MiB。
  - 推送前先 `list_commits` 确认 main 没被用户更新；有更新先合并。
- **工作分支是 `trial-wip`**（每个节点推一次，本地分支叫 `trial`）；最终交付时再合到 main。推送辅助脚本 `/data/work/mkpush.py <分支> <提交说明> <文件…>` → `/data/work/push_N.json`，再 `mcp_run_tool GitHub push_files arguments_file_path=...`（沙盒被重置的话照 §2 重写这个脚本：读文件 → battle.json 用 `separators=(',',':')` 压缩 → 按 <880KB 分块）。
- 用户本机需拉取新提交才能用 OPEN_GAME.bat 玩到（他本机有 Godot exe）。另尝试打包 Windows 试玩 zip（导出模板很大，见 §8 节点 8 记录）。

## 4. 体检结论（改之前，2026-10-18）

- 动作切换时身体横跳（躯干中心相对锚点，朝前为正，新测量法）：待机 -12；跑 +6~19；起跳 +17→+77；下落 +40~53；落地 +102→-22→+91；第一刀 -16→+35；第二刀 +27→+135；第三刀 +24→+120；强化挑飞 +6→+96；冲刺右 +59→+80→-75；格挡反馈 -38→-17。原因：锚点用导出原点，攻击把前冲画进图里但角色坐标不动，招式结束被拉回。
- 跑步 6 帧 4fps（1.5 秒一圈），着地脚每帧后退约 18.6px → 不滑步速度 ≈ 18.6×fps；原速度 170 → 脚滑约 2.3 倍。
- 转身 `turn_left_right` 原 13 帧 4fps（3.25 秒，里面转了两次：0–6、7–12），flip 2 / cancel 3。`turn_right_left` 5 帧。
- 19 招攻击框全是 `{x:100,y:-90,200×136}`，与新刀光不匹配。输入缓冲 36 帧（0.6 秒）偏长。
- 高度：待机约 128（躯干测量盒）/168（显示），跑 112，格挡 173。

## 5. 场景素材（用户用 GPT 出的三张，1672×941，会话附件）

- 远景 file_id `eca8dab9-144d-4d0b-a4ee-30258ae88076`：宝蓝夜空、银河、右上大月亮、两侧积云、地平线约 58%（y≈545）、湖面亮蓝带月光带；不需要无缝（固定）。
- 中景 file_id `58fc0374-2515-4d8b-96f9-54e348f4f126`：洋红底；雪山、城堡、右侧钟楼小镇、雾、底部贯穿全宽石拱桥+路灯；内容 33–59% 高度；左右边缘基本无缝。
- 近景 file_id `6fc5b889-b30f-40d8-a0e2-cc6273d0bfda`：洋红底；路面 55–59%、石墙 59–65.6%；正中石灯笼；草和白黄小花（**有几朵偏粉的花，抠图要保护**）；左右边缘基本无缝。
- 上传后路径：`/data/.agent-service/files/<file_id>/image.png`。
- 抠图方法（`/data/demo-night/gpt/key.py`）：洋红度 = min(R,B)−G，alpha 阈值 0.22–0.62，MinFilter(3)，反推前景色并去溢色。

## 6. 获批的总计划

A. 序列帧位置：统一锚点（脚底贴地、躯干中心对齐碰撞盒），带位移的招式把画里的前冲提取成真实位移（根位移）；可重跑脚本 `tools/art/align_sequences.py`。
B. 手感：跑步帧率与速度按着地脚绑定；转身保留但大改（提速、早翻转、早取消、只用有效段）；起跳不自己前冲；缓冲 36→约 10；顿帧分级；攻击框按刀光。
C. 战斗（“眩晕连段”）：见 §7。
D. 场景：三张图抠图、无缝、对齐地面；远景固定、中景慢视差、近景 1×；水面倒影、湿路面反光、雾、萤火、花瓣、流星、灯笼火光。
E. 角色融入环境光：夜色环境色调、月光轮廓光、石灯笼暖光、接地阴影、路面倒影；刀光保持亮。
F. 交付：独立夜景试玩场景（设为主场景，训练场保留）、全部测试通过、GitHub 更新、中文说明（+ 尽量给 Windows 试玩包）。

## 7. 战斗设计（节点 3 定稿；改数值时同步改这里）

### 7.1 对“眩晕连段”的理解（交付时要跟用户说明）
打满失衡 → 眩晕 → 挑飞 → 浮空连段 → 方向终结（S+J 下砸 / 按住前方+J 横扫）→ 撞墙 / 连锁击飞。
评价系统让这条主线最值钱：普通命中只给一点分（同一招连用递减），眩晕/挑飞/下砸/撞墙/连锁/弹刀给大分。

### 7.2 操作（试玩关卡）
| 键 | 作用 |
|---|---|
| A/D | 移动（转身动画保留） |
| W / 空格 | 跳，可二段 |
| J | 地面三连斩；按住蓄力 |
| W+J | 挑飞（`launcher_cancel`：地面轻攻击后摇一开始就能直接接 W+J） |
| 空中 J | 空中连斩（每下把敌人托住，越连托得越低 = 浮空衰减） |
| 空中 S+J | 下砸终结（急坠，落地冲击波掀起周围地面的影，敌人反弹可续） |
| 空中按住前方+J | 横扫终结（空中至少出过一刀后才触发；敌人以 1150 速度横飞，撞墙伤害 ×2、可撞飞别的影） |
| L | 弹刀（敌人刀尖白星亮时按）；按住 = 格挡（伤害 ×0.2） |
| K | 远射；Shift+J 冲刺斩 |
| R / F1 / H / F3 | 从头开始 / 判定框 / 隐藏说明 / 去木桩训练场（训练场 F3 返回） |

### 7.3 敌人（`scripts/night/shade.gd`，程序绘制，不用新美术）
| | 影卒 GRUNT | 甲影 BRUTE |
|---|---|---|
| 生命 / 失衡上限 | 110 / 46 | 250 / 120 |
| 前摇 / 出刀 / 收招（帧） | 30 / 8 / 38 | 46 / 10 / 56 |
| 伤害 / 攻击距离 | 8 / 132 | 16 / 175 |
| 眩晕时长 | 150 帧 | 170 帧 |
| 特性 | — | 前摇+出刀时霸体（打不断，身上橙光闪）；普通连锁只能撞个踉跄 |

- 失衡值 = 招式伤害 × `POISE_MUL`（第三刀 2.0、蓄力 2.4、冲刺 1.8…）；90 帧不挨打开始回落；弹刀 +55。
- 打满 → 眩晕：原地发晕（头顶转星、失衡条闪），受伤 ×1.25；眩晕中挑飞 vy ≥ 1008（更高）。
- 浮空：每下 juggle_count+1，伤害 +8%/下（最多 8 层）；托起高度 max(110, 430−34×次数)；超过 12 次不再托起。
- 下砸落地：+6 伤害、冲击波半径 230、反弹 −620；横扫：撞墙伤害 = 速度 × 招式撞墙系数 × 0.045 ×2。
- 连锁：飞行速度 ≥ 480 的影碰到别的影 → 对方被撞飞（伤害 5+速度×0.012，+30 失衡），可以一串。
- 出刀判定在 STRIKE 第 2 帧；`PARRY_CUE = 10`：前摇最后 10 帧刀尖亮白星（弹刀提示）。
- 同时出刀的数量受波次 `max_attackers` 限制（不会被围殴到读不清）。

### 7.4 玩家侧改动（`scripts/gameplay/player.gd`，训练场默认值不变）
- `root_motion_block_group`：根位移只把角色推到敌人身前（half_w + 40），不会穿过去；训练场为空 = 不生效。
- `launcher_cancel`、`finisher_intent`/`combat_intent()`（&"slam"/&"drive"）、`PLUNGE_SPEED 1250`、`plunge_landed` 信号。
- 连段方向以“按下 J 那一帧”的方向为准；地面招式后摇里起跳 = 立即结束招式，空中可马上出刀。
- 试玩场景专属：`can_die`、`getup_invuln_frames 40`、`wall_damage_scale 0`（被打飞落地不额外扣血）、弹刀窗口 8→12 帧（只改场景内角色 meta 副本，battle.json 不变）。

### 7.5 关卡流程（`scripts/night/night_trial.gd` + `encounter.gd`）
- 一路往右走，三处“月光封印”（竞技场全宽 1240，中心间距 1750，走到中心前 240 合上）。
  1. 影卒来袭 2G（1 只出刀）→ 影卒围攻 3G + 剩 1 只时增援 1G（2 只出刀）
  2. 甲影现身 B+2G
  3. 影潮 G,B,G + 剩 2 只时增援 B,G
- 每清一波回 25 血；三处打完出本轮结算（用时/最高连击/眩晕挑飞/下砸撞墙连锁/弹刀/受击），下一轮影子生命 ×1.2。
- 倒下 150 帧后从本波重来；每波最后一只死时 0.3 倍慢动作 0.45 秒；身后的路被封住。
- 情境提示（只出一次）：移动 / 失衡条 / 弹刀 / 眩晕 / 浮空 / 甲影 / 连锁。

### 7.6 评价（`scripts/night/style_meter.gd`）
- D 起手 / C 连贯 / B 凌厉 / A 华丽 / S 绝影，阈值 0/35/80/150/230，上限 320。一整套“眩晕→挑飞→空中→下砸”≈ B。
- 事件分：眩晕 18、破霸体 14、挑飞 10、下砸 22、撞墙 16、连锁 12、弹刀 20、击杀 6、空中击杀 14、每次托起 1.5；普通命中 4（最近 5 下里同一招重复：×0.7/0.45/0.25/0.12）。
- 连击窗口 2.4 秒（有敌人浮空/眩晕时计时 ×0.45）；挨打 = 连击清零、分数 ×0.5−20。

### 7.7 验证
- `tests/test_night_combat.gd`（41 项）：主场景/项目名、整套下砸连段（≤8 下眩晕、挑飞 vy≤−1008、托起≥2、砸地、评价≥B）、横扫撞墙、连锁（甲影不被撞飞）、弹刀窗口（白星刚亮/出刀前 1 帧能弹，太早只是格挡，不防会被砍）、评价规则、第一处封印波次流程。
- 开发工具 `tests/dev/`：`bot_night.gd`（机器人整轮试玩，SKILL 0.6 时一轮 126–150 秒、死 0–1 次）、`capture_night.gd`（事件截图）、`shade_gallery.gd`（敌人各状态图鉴）。

## 8. 节点清单（状态）

- [x] 节点 0：拉取更新、体检、计划获批、环境搭好
- [x] 节点 1：序列帧对位脚本 + battle.json 锚点/根位移 + 运行时根位移
- [x] 节点 2：手感参数（跑步/转身/跳跃/缓冲/判定框/顿帧）+ 序列帧横线瑕疵清理
- [x] 节点 3：战斗系统（敌人、失衡/眩晕、浮空连段、方向终结、连锁）+ 试玩关卡/HUD/评价（原节点 6 的大部分）
- [x] 节点 4：夜景场景（抠图/无缝/视差/特效，设计见 §11）
- [x] 节点 5：角色环境光（设计见 §12）
- [x] 节点 6：整合 + 整轮实机复查（镜头/遭遇战/HUD/主场景在节点 3，夜景在节点 4，环境光在节点 5）
- [ ] 节点 7：测试全过 + 实机截图/录屏验证
- [ ] 节点 8：GitHub 推送 + Windows 包（如可行）+ 用户说明

## 9. 进度日志

- 2026-10-18 节点 0：pull 到 5c452fd；体检（§4）；计划获批（§6）；装 Godot 4.7.2 Linux 与 Xvfb；基线测试 220/0。
- 2026-10-18 沙盒被重置一次，按 §2 重建（本文也是重写的）。
- 2026-10-18 节点 1 完成：
  - 新增 `tools/art/align_sequences.py`（可重复运行；原始 pivotX 保存在每帧 `pivotXAuthored`，脚本永远从原始值算）。测量法：按 displayScale 缩放到世界像素，排除白色刀光/尘土（min(RGB)>165 且低饱和），5×5 开运算去掉细剑，取最大连通块，躯干中心 = 身体高度 40%–80% 段的像素 x 中位数；3 帧中值平滑去测量毛刺。
  - 模式：`const`（idle/run/fall/guard_hold/空中三刀/air_slash，整段统一平移，取中位数）、`lock`（jump/land/draw/sheathe/death，逐帧平移）、`turn`（两段转身，逐帧精确锁）、`root`（其余所有招式：逐帧平移 + 写 `animations.<名>.rootMotionX`）。每段动画写 `alignment` 字段（模式、对齐前偏移、残差）。
  - `turn_left_right` 裁成原片前 7 帧（`trimmedFrom` 记录来源 `source_跑步左向转右` 0–7）。
  - 根位移结果（世界像素，末帧）：第一刀 +44、第二刀 +93（峰值 108）、第三刀 +38（峰值 85）、强化挑飞/蓄力/上挑 +89、冲刺右 -130、冲刺左 -94（冲刺另有 movementTimeline 210，相加；节点 2 会补滑行距离）、格挡反馈 ±20。
  - 运行时：`MoveDefinition.root_motion_x/root_motion_scale`（battle.json 招式可写 `rootMotionScale`），`configuration.gd` 从动画读取；`player.gd` 新增 `_root_motion_step`（本帧根位移 = rootMotionX[帧(move_frame+1)] − rootMotionX[帧(move_frame)]，帧号算法与 character_view 一致）与 `_move_with_root_motion`（只作用一帧，不留惯性；撞墙停）；冲刺斩在 movementTimeline 之外叠加根位移。
  - 测试仍 220/0。
- 2026-10-18 节点 2 完成：
  - 新增 `tools/art/clean_lines.py`：源视频带进来的“横贯画面的直线”（上挑/强化挑飞第 9–10 帧最明显，还有 a2 前摇第 1 帧的地平线等）→ 写成 `sprite.assetCleanup = {资源路径: [[x,y,w,h],…]}`，`art_cache.get_texture` 加载时用 `fill_rect` 抹透明。**原 PNG 不改**（GitHub 通道传不了二进制）。141 帧、541 个矩形。判定：竖向厚度<17 的细长直线（≥120px、高≤26、逐列中心 y 标准差≤3、碰左右边或长≥25% 画宽）+ 粗光束（厚<48、≥400px、很直）。已核对第一刀刀光尖端不会误删。
  - 新增 `tools/art/tune_feel.py`（写绝对值，可重复运行；顺序：align_sequences → clean_lines → tune_feel）：
    - 跑步 fps 4→10，速度 = 步幅 18.6 × 10 = 186（原 170），脚不打滑。
    - 转身 fps 18；turnRight（turn_left_right）flip 3 / cancel 4；turnLeft（turn_right_left）flip 2 / cancel 3；landingCancelFrame 2。
    - 输入缓冲保持 C 盘原值 36 帧（试过 15，顿帧里按的下一刀会丢，三个测试挂了）。顿帧也保持 C 盘原值（轻 6/7、6/8，第三刀 11/15，蓄力 13/16，上挑 9/11，冲刺 11/15）——终结技加重放到节点 3。
    - 判定框按出刀帧像素重算（先应用 assetCleanup；alpha>110、9×9 开运算、只取身前 x>10、百分位裁剪、有 HITBOX_MIN 下限），原值存 `hitboxAuthored`。第一刀 249×195、第二刀 250×135、第三刀 233×205、蓄力 240×214、上挑 200×230、空中 180–190 宽、冲刺 190×170。
    - 攻击中按方向键的走位倍率 `movementSpeedMultiplier`：轻攻击 1→0.3、蓄力/上挑 0.2、远程 0.45、弹刀 0.3（前冲交给根位移，不再“滑着砍”）；空中保持 0.6。
    - 冲刺斩时间轴 = 原值 + 抵消画里身体落后于脚的部分（右 339.6、左 303.8；原值存 `movementTimelineAuthored`），净位移约 210。
  - 测试更新：test_desktop_integration 帧率检查改为 run 10 / 转身 18 / 7 帧，并新增跑速=186 检查；test_combat_feedback “轻攻击走位 C 盘速度”改为“走位倍率≤0.35 且有根位移”。全部 221/0。
  - 已推送为 trial-wip 提交 ff6c2e9。
- 2026-10-18 节点 3 完成（设计和数值全在 §7）：
  - 新增 `scripts/night/`：shade.gd（敌人）、style_meter.gd（评价）、encounter.gd（波次）、combat_hud.gd（HUD，全部 _draw 画）、player_factory.gd（和训练场同一套建角色参数 + 注册按键）、night_trial.gd；新增 `scenes/night_trial.tscn`。
  - `project.godot`：主场景改为 `res://scenes/night_trial.tscn`，`config/name` 改为“月下堤岸 · 试玩版”。
  - `tools/battle-editor/server.js`：编辑器启动预览时显式打开 `res://scenes/training.tscn`（热重载/心跳都在训练场里；主场景换了不影响编辑器）。test_editor.mjs 需要编辑器服务在跑，沙盒里没跑。
  - `scripts/training.gd`：F3 返回试玩，说明文字加“F3 返回试玩”（其余不动）。
  - night_trial 的 `backdrop` 变量为空时画占位天空/地面 → 节点 4 接夜景。
  - 新测试 test_night_combat 41/0；全部 262/0。临时调试脚本已删，有用的三个移到 `tests/dev/`。
  - 本地提交 d0b5115，已推送为 trial-wip 提交 488e27e。
- 2026-10-18 节点 4 完成（细节全在 §11）：
  - 新增 `tools/art/make_night_layers.py`、`assets/scenery/moon_embankment/{far,mid,near}.webp.b64 + layers.json`、`assets/shaders/{night_far,night_reflect,night_fog}.gdshader`、`scripts/night/night_backdrop.gd`；`night_trial.gd` 加 `_build_backdrop()`。
  - 新增开发工具 `tests/dev/scene_shot.gd`（静帧截图）。
  - 截图检查：x=300/1400/2600 三处构图、月亮/云无噪点、接缝看不出、灯笼/倒影/雾正常；capture_night 战斗截图里影卒在亮海面上轮廓清楚，封印墙和底部提示框不挡战斗。近景倒影原来太淡被月光路盖住 → strength 0.72、tint_amt 0.38。
  - test_night_combat 加 6 项夜景检查（47 项）；全部 268/0；无头模式加载 webp/着色器无报错。
  - 本地提交 64f9149，已推送为 trial-wip 提交 fe8727f。
- 2026-10-18 节点 5 完成（细节全在 §12）：
  - 新增 `assets/shaders/char_light.gdshader`（冷色环境 + 右上月光边缘光 + 灯笼暖光），`night_trial.gd` 加 `_build_lighting()/_update_lighting()/_draw_player_shadow()`；`night_backdrop.gd` 加 `lantern_flicker()`、`lantern_light()`、`LANTERN_REACH`；`shade.gd` 加 `lamp`、朝灯一侧暖边 + 斗篷暖色 + 背向灯笼的长影。
  - `tests/dev/scene_shot.gd` 加 `NOLIGHT=1`（关光照对比）、`SHADES="-230,170"`（放静止影卒）、`FACE=-1`（朝左）、`POSE="招式:帧"`（定格）。
  - 调参过程：第一版去饱和 0.14 + 暗部抬蓝 → 角色发灰发平；改为去饱和 0.08、抬升只作用在最暗处、月光边 0.85、宽 2.5px。影子一开始被叉开的双脚挡住、步道顶面在画面里只有约 12px 高 → 改成“贴地接触影 40×3.5 + 外圈淡影 60×6.5”。影卒暖边在黑斗篷上太暗 → 3px 实线 + 7px 外发光。
  - 坑：着色器自定义函数里不能直接用 TEXTURE；把 TEXTURE 当 sampler 参数传进函数会在无头模式报 `custom_samplers` ERROR → 现在全部在 fragment 里直接采样。**无头测试不编译着色器**，改着色器后必须用 Xvfb 跑 scene_shot 并 grep `SHADER ERROR`。
  - test_night_combat 加 2 项（材质已挂、灯笼暖光近强远零）→ 49 项；全部 270/0。
  - 本地提交 93bb1d6，已推送为 trial-wip 提交 0aebbe3。
  - 挑飞（attack_up）序列帧自带的大白刀光弧是不透明像素，靠 alpha 分不出来；`POSE="attack_up:10"` 定格对比开/关光照，差别很小（只是更偏冷），灰白笔触是原图本身 → 不做“发光像素例外”。
- 2026-10-18 节点 6 完成（整合 + 整轮实机复查）：
  - 机器人整轮（BOT_ENC=3，无头 60fps）：SEED 7/SKILL 0.6 → 128.9s 0 死；SEED 11/SKILL 0.4 → 179.8s 死 2 次仍通关；SEED 3/SKILL 0.8 → 136.6s 0 死。每处封印约 35–50 秒，一轮约 2–3 分钟。
  - Xvfb 整轮截图（capture_night，SEED 3 SKILL 0.8）：眩晕/挑飞/下砸/连锁/波次横幅/封印解除/第 1 轮结算面板都正常；结算 A（用时 1:47、最高连击 28、眩晕/挑飞 24/12、下砸/撞墙/连锁 4/4/8、弹刀 6）。
  - **修 bug**：镜头快速移动（冲刺等）时远景层晚一帧，屏幕右边露出约 12px 底色。原因是夜景 `_process` 在镜头更新之前读位置 → `night_backdrop` 设 `process_priority = 100`（在镜头之后更新）+ 远景改成 region 左右各多 48px、`TEXTURE_REPEAT_MIRROR` 兜底。
  - 开发工具修正：capture_night 的整轮结算截图条件原来写成 `encounter_index == 2`（实际截到的是第 2 处封印的横幅）→ 改为 `encounter_index % ROUND.size() == 0`，并且截完最后一张才退出；bot_night/capture_night 每帧缓存 `snap = style.stats.duplicate()`，第 3 处封印的统计不再被整轮重置成 0。
  - 已知、不改：挑飞刀光是原图的灰白笔触（见节点 5）；结算面板会挡住角色上半身约 1 秒（角色可以继续走）。
  - 全部测试 270/0。

## 10. 仍待用户拍板的旧事项（本任务不阻塞）

主题名“凝时天都”是否确定；是否更新仓库旧《视觉设计规范》；HUD 布局（`/data/ui/hud-mock.png`）；主角名字；文档放 Notion 还是仓库；格挡特效（`/data/vfx/parry/`）是否放进 assets。

## 11. 夜景「月下堤岸」（节点 4 定稿）

### 11.1 素材与再生成
- 原图 = §5 的三张（远景 eca8dab9…、中景 58fc0374…、近景 6fc5b889…，都在 `/data/.agent-service/files/<id>/image.png`；沙盒重置后需要用户重新发或从会话附件取）。
- 再生成：`python3 tools/art/make_night_layers.py <远景> <中景> <近景>` → 覆盖 `assets/scenery/moon_embankment/` 下的 `far/mid/near.webp.b64` 与 `layers.json`。
  - 远景：直接缩放到 1280×720，测地平线 horizonY=417。
  - 中景/近景：缩放到 720 高 → 洋红抠图（去溢色；半透明边缘 G≤max(R,B) 去绿边）→ 裁到有内容的行 → 在 [0.8W, W−120] 搜周期 P + 最小误差竖向切缝拼接（羽化 2px）→ webp → base64。
  - 当前结果：mid period 1026、top 191、1026×236；near period 1125、top 267、1125×207。
- 为什么存 base64：推送通道只能传文本（§3）。运行时 `NightBackdrop.load_b64_texture()`（Marshalls → `Image.load_webp_from_buffer`，静态缓存）解码。**以后如果做导出包**：仓库目前没有 `export_presets.cfg`；建导出预设时要把 `*.b64, *.json` 加进“非资源文件包含过滤”，否则夜景加载失败（会自动退回占位背景）。

### 11.2 关键坐标（世界坐标，屏幕 1280×720，镜头竖直固定 360）
- 近景图块：石板顶面从第 131 行开始，**脚踩第 139 行**（`NEAR_STAND_ROW`）→ `near_top() = floor_y − 139 = 441`；墙底第 205 行（世界 y≈646），下面是倒影和海。
- 灯笼火光在近景图块 (639, 61)，每 1125px 一盏；`nearest_lantern(x)` 返回离 x 最近那盏的世界坐标（节点 5 环境光用）。
- 中景桥灯：图块第 203 行，x = 65,124,184,245,307,368,731,791,848,908。

### 11.3 层次（z_index，全部在角色后面，除了花瓣）
| z | 内容 | 滚动 |
|---|---|---|
| −100 | 远景（`night_far.gdshader`：海面扭动、局部高对比小亮点才闪的星星、月光路偶尔亮点；月亮/云不加噪点） | 固定在屏幕 |
| −98 | 流星（加色混合，第一颗 4 秒，之后每 5–11 秒一颗） | 屏幕 |
| −96 | 中景倒影（flip_v，取最后 46 行，`night_reflect` strength 0.32） | 0.25 |
| −94 | 中景（region x = fposmod(cl×0.25 − MARGIN, P)） | 0.25 |
| −93 | 桥灯光点 | 0.25 |
| −92 | 地平线雾（FastNoiseLite 无缝噪声 768×96，`night_fog`，在 horizon−70，另外每秒自己飘 9px） | 0.4 |
| −91 | 近景倒影（墙面第 131 行以后，翻转后贴在墙底下；strength 0.72、tint (0.1,0.16,0.34)、tint_amt 0.38） | 1 |
| −90 | 近景步道 | 1 |
| −80 | 灯笼光晕 + 地面暖光圈 + 萤火虫（每 220px 一格程序生成；加色） | 1 |
| 15 | 花瓣 9 片（很淡，在角色前面） | 屏幕 |

- 无限滚动：Sprite2D + `region_enabled` + `texture_repeat`，region 宽 = 屏宽 + 2×MARGIN(48)。远景也是 region（−48 起、镜像重复）。
- `process_priority = 100`：夜景必须在镜头之后更新（节点 6 修的“远景晚一帧露边”）。
- `night_trial._build_backdrop()` 在 `_build_camera()` 之后调用并 `move_child(b, 0)`；`ok=false` 时删掉夜景，退回占位天空/地面（游戏照样能玩）。

### 11.4 验证方法
- 静帧：`DISPLAY=:99 SHOT_DIR=/data/work/shots XS="300,1400,2600" /data/tools/godot --path . --script res://tests/dev/scene_shot.gd --resolution 1280x720` → `scene_x<x>.png`。
- 战斗：`DISPLAY=:99 SHOT_DIR=… SEED=3 godot --path . --script res://tests/dev/capture_night.gd --resolution 1280x720`（眩晕/挑飞/下砸/连锁/波次自动截图）。
- 测试：test_night_combat 里 `test_backdrop()`（加载成功、尺寸 = 周期、步道对齐 floor_y、灯笼可查、夜景在最底层）。

## 12. 角色环境光（节点 5 定稿）

只在试玩关卡生效（训练场的角色没有材质，完全不变）。夜景加载失败（`backdrop == null`）时也不挂。

### 12.1 玩家：`assets/shaders/char_light.gdshader`（挂在 `Visual/ActorSprite`，`night_trial.light_mat`）
- 冷色环境：去饱和 `desat` 0.08 → 乘 `ambient` (0.85, 0.9, 1.0) → 最暗处抬一点蓝 `shadow_lift` (0, 0.012, 0.04)×(1−亮度)²。
- 月光边缘光：月亮固定在屏幕右上，`moon_dir` (0.86, −0.5)。往这个方向偏 1 倍和 2.2 倍宽度采样 alpha，外面是透明就是“迎光的边”，用 screen 混合叠 `moon_col` (0.74, 0.86, 1.0)×0.85。宽度 `RIM_PX` = 2.5 屏幕像素，脚本每帧按精灵的全局缩放换算成贴图像素（`px`）。
- 灯笼暖光：`warm` = `backdrop.lantern_light(身体中心).x × 0.85`（0..1，含火苗跳动，半径 `LANTERN_REACH` 330，smoothstep 衰减），`warm_dir` = 指向灯笼的方向。朝灯一侧 7 倍宽度的“宽漫反射” + 1 倍宽度的暖边；越暖环境色越接近白、去饱和越少。
- 镜像：精灵 `get_global_transform().x.x < 0` 时 `flip = −1`，把屏幕方向换成贴图方向（转身动画会自己抵消父节点翻面，结果照样对）。
- 序列帧每帧是一张整图（没有图集 region），所以贴图外面直接算透明。

### 12.2 影子（`night_trial._draw_player_shadow()`，画在关卡节点自己的 _draw 里，z 0，在角色下面、夜景上面）
- 步道顶面在画面里只有约 572–588 这一条，所以影子很扁：贴地接触影（中心 floor_y+2，40×3.5，alpha 0.8）+ 外圈淡影（floor_y+3，60×6.5，alpha 0.45），中心往左偏 3–5px（月亮在右上）。离地越高越小越淡（300px 淡到最低）。
- 靠近灯笼：再加一道背向灯笼拉长的淡影（长 56+50w，alpha 0.35w）。
- 影卒的影子在 `shade.gd._draw()` 里自己画（原有接地影 + 新加的灯笼长影）。

### 12.3 影卒（`shade.gd`，程序绘制）
- 原有：右侧月光描边 `RIM`。
- 新增 `lamp: Vector3`（night_trial 每帧 `_update_lighting()` 里填 `backdrop.lantern_light(影卒位置)`）：朝灯一侧 3px 暖边 + 7px 外发光、兜帽同侧暖边、整件斗篷叠 0.16×强度的暖色。

### 12.4 验证
- `NOLIGHT=1` 对比开/关；`SHADES="-230,170" XS=760` 看灯笼左边的影卒；`FACE=-1` 看朝左；`POSE="attack_up:10"` 定格某招式某帧。结论截图：离灯远时角色偏冷、右侧有月光边；在灯笼左/右时对应一侧变暖；双脚之间能看到贴地影。
