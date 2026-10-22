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
  - **交付不用录屏**（用户 2026-10-19：“你以后交付也不需要录，我自己点验收就行”）。交付时附几张截图即可，用户自己打开游戏验收。
  - **需要新美术就写 GPT 提示词让用户去生图，不要自己用代码做粗糙素材**（用户 2026-10-19 原话：“以后你觉得需要gpt生图的，都给我生图，而不是自己制作粗糙的素材。希望你能够制作精细的素材再自己制作。”）。先拿到精细的 GPT 图，再由我们加工（抠图、对齐、无缝、调色）和接入；代码只用于加工/接入 GPT 图、程序特效和检验图。
  - **不要没事就让机器人打一整轮**（用户 2026-10-19 原话：“你以后不要没事干打一轮了”）。整轮机器人试玩和整轮录屏很费时间，只在改动确实影响整轮流程、或用户要求时才做；平时用对应的测试、截图或几秒的小片段验证。
- “眩晕连段”的理解：仓库设计文档的核心是**浮空连段**（挑起→空中连段→决定终结方向→撞墙/撞地/连锁击飞），代码里已有 STUNNED（眩晕）状态。本任务按“**打满失衡 → 眩晕 → 挑飞 → 浮空连段 → 方向终结 → 连锁击飞**”来做，两种理解都覆盖。交付时要向用户说明这个理解。
- 用户已否决：穹环/钟塔题材（“不好看”）、紫色背景（会吃掉角色的紫发和紫刀光）、旧 HANDOFF 的“260px/像素化”方向。
- 第三轮（§14）起：夜战镜头 zoom 0.5，角色在屏幕上约 85px；**角色不像素化**（描边 + 提对比），**只有背景**像素化（2 倍块 + 64 色）；地形多层平台、**不做坑**。

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

> 注意：沙盒可能被重置（2026-10-18 已发生两次：/data/tools、/data/work、未推送的改动全部丢失，仓库退回旧提交）。开工先检查，缺了就按下面重建；进度以 GitHub 的 `trial-wip` 为准：`git fetch origin trial-wip:refs/remotes/origin/trial-wip && git checkout -b trial origin/trial-wip`。所以**每个节点做完立刻推送**。

- 仓库：`cd /data/nightcrow-godot && git fetch origin && git merge --ff-only origin/main`（沙盒 git 没有 push 凭据）。
- Godot Linux：`/data/tools/godot` → 下载 `https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` 解压后软链。
- 渲染：`sudo dnf install -y xorg-x11-server-Xvfb mesa-libGL mesa-libEGL mesa-dri-drivers libXcursor libXinerama libXrandr libXi alsa-lib pulseaudio-libs`，然后 `Xvfb :99 &`、`DISPLAY=:99`。
- 首次：`/data/tools/godot --headless --path . --import`（会生成一些未跟踪的 `.import` 文件，不要提交）。
- 测试：`/data/work/runtests.sh`（逐个跑 `godot --headless --fixed-fps 60 --path . --script res://tests/<name>.gd`，输出 “N checks / M failures”）。基线 220/0：training 32、combat_feedback 52、framebaker_runtime 52、locomotion 12、action_flow 45、desktop_integration 27。另有 node 测试 `tests/*.mjs`（修改器）。
- 场景原图是会话附件，沙盒重置后用 `upload_file_to_sandbox` 重新上传（file_id 见 §5）。
- 体检/检查脚本：`/data/seq-audit/{common,measure,sheet}.py`（`BJ=路径` 可指定 battle.json）。

## 3. 交付通道（重要限制）

- **2026-10-19 起：沙盒 git 可以直接推送（二进制也行）**。方法：装 GitHub CLI（`/data/tools/gh_*/bin/gh`，从 github.com/cli/cli releases 下 linux_amd64 包），`gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key`（后台跑，把输出里的一次性验证码和 https://github.com/login/device 发给用户，让用户在自己的浏览器里授权），成功后 `gh auth setup-git`，之后 `git push origin 分支` 即可。凭证存在 `~/.config/gh/hosts.yml`，**沙盒重置后要让用户重新授权**。用户可在 GitHub 设置 → Applications → Authorized OAuth Apps → GitHub CLI 撤销。
- 下面是以前的限制（没有 git 凭据时的退路）：

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

### 7.8 选后视频原声（2026-10-19）

对应动作改用16份原声WAV，详情见 §15。实际命中、脚步、跳跃、敌人等缺少合适源片段的音效保留；玩法参数和分段变速不改。注意旧 §13 的“71份全为生成OGG”是替换前记录。

## 8. 节点清单（状态）

- [x] 节点 0：拉取更新、体检、计划获批、环境搭好
- [x] 节点 1：序列帧对位脚本 + battle.json 锚点/根位移 + 运行时根位移
- [x] 节点 2：手感参数（跑步/转身/跳跃/缓冲/判定框/顿帧）+ 序列帧横线瑕疵清理
- [x] 节点 3：战斗系统（敌人、失衡/眩晕、浮空连段、方向终结、连锁）+ 试玩关卡/HUD/评价（原节点 6 的大部分）
- [x] 节点 4：夜景场景（抠图/无缝/视差/特效，设计见 §11）
- [x] 节点 5：角色环境光（设计见 §12）
- [x] 节点 6：整合 + 整轮实机复查（镜头/遭遇战/HUD/主场景在节点 3，夜景在节点 4，环境光在节点 5）
- [x] 节点 7：测试全过 + 实机截图/录屏验证
- [x] 节点 8：合并到 main（PR #1）+ 用户说明（Windows 包不做，见 §9）
- 第二轮（§13，分支 trial-wip2）：
  - [x] 节点 9：环境分层视差
  - [x] 节点 10：角色画质（高清采样 + 代码修帧；修不了的见 `docs/GPT-重画清单.md`）
  - [x] 节点 11：手感大改（跑速、跳跃、落地轻重、招式变速、后摇取消、镜头前瞻）
  - [x] 节点 12：音效（`assets/audio/sfx_v3/`）
  - [x] 节点 13：整合、录屏、合并 main、试玩说明
- 第三轮（§14，分支 trial-wip3）：
  - [x] 节点 15：镜头 0.5（角色约 85px）+ 夜景屏幕容器 + 角色描边/提对比
  - [x] 节点 16：背景退后调色 + 2 倍像素化 + 64 色调色板
  - [x] 节点 17：多层地形（碰撞、单向平台、S+空格 下穿、影卒跨层 AI、出生点）
  - [x] 节点 18：地形美术（木栈道/石台/断桥/亭子，程序像素画）+ 亭子灯笼照亮角色
  - [x] 节点 19：测试、机器人整轮、录屏、文档、合并 main
- [x] 节点 20：选后视频原声接入、对应动作对时、删除27份已替换旧音效（§15）

## 9. 进度日志

> 第二轮的日志在 §13.4，第三轮的在 §14.4。

- 2026-10-19 节点20：本机由 `5c452fd` 快进到GitHub最新 `2e15334`，接入16份视频原声、清理27份已替换生成变体，44份无对应替换的变体逐字节保留；原声专项14+audio25+combat_feedback52+feel27+night_combat50，共168项0失败，无整轮机器人/录屏。完整说明与复建见§15。

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
  - 本地提交 2f32bac，已推送为 trial-wip 提交 893e4ba。
- 2026-10-18 节点 7 完成（测试 + 录屏）：
  - 全部测试 270/0（沙盒第二次被重置后重建环境再跑，结果一样）。
  - `tests/dev/bot_night.gd` 加 `BOT_TAIL=N`：打完 BOT_ENC 处封印后继续空跑 N 帧（把结算面板录进去）。
  - 录屏命令：`DISPLAY=:99 SEED=3 SKILL=0.8 BOT_ENC=3 BOT_TAIL=240 /data/tools/godot --path . --script res://tests/dev/bot_night.gd --resolution 1280x720 --fixed-fps 30 --write-movie /data/work/movie/demo.avi`（后台跑，Xvfb 下约 7 分钟，AVI 约 900MB）→ `ffmpeg -c:v libx264 -preset slow -crf 30 -pix_fmt yuv420p -c:a aac -b:a 112k -movflags +faststart`（crf 27 是 44MB，太大）。
  - 这一局：2 分 09 秒，0 死；三处封印 51.7s / 85.0s / 125.1s 清完；最高评价 S，第 1 轮结算 A（用时 1:45、最高连击 37、眩晕/挑飞 21/13、下砸/撞墙/连锁 6/4/12、弹刀 6、受击 6 次 72 伤害）。同样的 SEED 两次录制结果不完全一样（渲染时帧序有差别），无所谓。抽帧检查：开场标题、情境提示、浮空连段、“挑飞！眩晕！破防·眩晕！”、S 评价、封印解除横幅、结算面板都正常。成品 26MB（crf 30）。
  - 录屏文件不进仓库（太大），直接发给用户：`月下堤岸试玩录屏.mp4`。
  - 新增 `docs/试玩说明.md`（给用户看的：怎么更新、怎么启动、操作、眩晕连段、关卡、已知问题）和 `PULL_GITHUB.bat` / `下载GitHub更新.bat`（`git pull --ff-only origin main`；冲突时停下、不覆盖本机文件）。原来的 SYNC_GITHUB.bat 只会上传，GitHub 上更新时它会拒绝，所以用户需要这个下载入口。
  - 本地提交 9a3ec41，已推送为 trial-wip 提交 77e086a。
- 2026-10-18 节点 8 完成（交付）：
  - 开 PR #1（trial-wip → main，https://github.com/fornever123/nightcrow-godot/pull/1），用 merge 方式合并（保留每个节点的提交）。合并前 main 仍是 5c452fd，没有冲突。
  - Windows 打包没做：沙盒没有导出模板（约 1GB），而且 GitHub MCP 只能传文本。用户本机有 Godot exe，用 `下载GitHub更新.bat` 拉取后双击 OPEN_GAME.bat 就能玩。以后要打包的话，在用户本机用 Godot 编辑器导出，并把 `*.b64`、`*.json` 加进导出的“非资源文件”过滤。
  - 交付给用户：录屏 `月下堤岸试玩录屏.mp4`、`docs/试玩说明.md`、本文档。
  - **以后接手**：新需求在 main 上开新分支（例如 `trial-wip2`），照旧每个节点推送一次；先 `list_commits` 看用户有没有从本机上传新提交。

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

## 13. 第二轮：画质 + 手感大改 + 环境分层（2026-10-18 起，工作分支 `trial-wip2`，本地分支 `trial2`）

### 13.1 用户原话
“现在角色序列帧很多地方质量有些差，比如缺少帧画质低有糊边角色很糊什么的，你看看能不能帮我优化一下。然后移动速度太慢了，我需要你改一下游戏角色本身动作设置，比如音效和前后摇角色动作角色落地速度什么的，要大改，做一个适合的。然后环境也有问题，下面的水应该是近景，桥上面的水是中景，城堡是中景，山是远景，云是远景，月亮才是几乎不动的超远景。你先给我改动计划，然后再执行。”

### 13.2 体检（改之前）
- 角色贴图：运行时从 PNG 直接建 ImageTexture，**没有 mipmap**，过滤 linear，`displayScale 0.41`（攻击类再 ×1.19）→ 屏幕上缩小约 2.4 倍只做双线性采样 → 锯齿、细线闪烁、刀光边缘发毛；透明边缘的底色混进来 → 糊边。原图本身来自视频，偏软，部分帧有运动模糊（跑步第 4–6 帧腿和剑糊）。
- 缺帧：跑步只有 6 帧（10fps），转身 7/5 帧，起跳 9 帧（第 4 帧跳变）、落地 8 帧（第 4 帧跳变）、转身左→右第 2 帧跳变。攻击帧数够（13–31 帧，24fps），跳变主要是刀光烘焙在图里。
- 手感：跑速 186（穿过屏幕约 7 秒）；跳跃上升 0.53s/下落 0.48s（偏飘）；第三刀总长 1.25s、挑飞/蓄力 1.29s、冲刺斩 1.46s（后摇太长、不能取消）；落地动画 0.47s。
- 音效：只有 13 个通用音（combat_v2 9 个 + street_fight 4 个），没有脚步、没有分轻重的命中；`art/selected-video-audio/` 有 6 段原视频音轨（m4a，用户归档，尚未接入）。
- 环境：远景是一整张图（星空+月亮+云+海）**固定在屏幕上**，所以海面（包括步道下面的水）完全不动；中景是一整张（山+城堡+小镇+雾+桥）0.25 倍，所以山和城堡一起动。

### 13.3 计划（用户已确认：“OK，然后有很多动作游有些地方质量本身就很低，你看看能不能改，不能的话gpt”）
- 追加要求：逐个动作找出原图本身质量差的帧（崩坏、糊、缺件）；能用代码修就修（换相邻帧、补间、局部修补），修不了的列清单并写 GPT 提示词（每条单独一个代码块）让用户去出图。
- 用户追加（第二条）：“然后跑步动作可以不管，因为要重置”——跑步序列帧用户会重做，节点 10 **不做**跑步补间/跑步修帧；节点 11 的跑速照改，跑步动画帧率先按现有 6 帧临时匹配，等新跑步帧到了再按步幅重配。
- 节点 9 环境分层：拆成 月亮(固定) / 星空银河(0.01) / 云(0.05+风飘) / 山(0.12) / 城堡小镇(0.3) / 雾(0.36) / 桥(0.42) / 海面逐行视差（桥下 0.42 → 步道后沿 1.0；步道下面 1.0 → 屏幕底 1.25）/ 近景步道(1.0)。月光倒影跟着月亮不动，水波纹跟着海面动。拆图全用代码（亮度/颜色遮罩 + 拼接补洞），效果不好再给用户分层提示词。
- 节点 10 角色画质：高清采样着色器（按屏幕像素超采样、预乘透明度 → 去锯齿、去黑边/糊边）+ 轻微锐化 + 边缘收紧；跑步试光流补间到 12 帧、跳变帧补一张中间帧（效果不好就不用）。训练场同样受益。
- 节点 11 手感大改（直接改 battle.json，训练场也一起变）：跑速 ~340（跑步帧率随之 ~18fps，脚不打滑）、起步/急停更快；跳跃上升 ~0.34s、下落 ~0.26s、松键小跳、下落速度上限；落地分轻重（普通落地 0.1s 可立刻动，高落/下砸才播完整落地）；所有招式前摇加快、后摇分段加速并且能用 跳/冲刺/弹刀 提前取消（帧不删，只改各段播放速度）。
- 节点 12 音效：先分析 6 段原视频音轨，能用的切出来；不够的用代码合成。脚步（按跑步落脚帧）、起跳/二段跳、落地分轻重、每刀不同刀风、命中分轻/重/终结、弹刀、眩晕、挑飞、下砸、撞墙、连锁。声音存成 base64 文本（推送通道只能传文本）。
- 节点 13 整合：测试、机器人整轮、录屏、合并 main、更新试玩说明。

### 13.4 进度日志（第二轮）
- **节点 9 环境分层：完成**（提交见 trial-wip2）。
  - 新工具 `tools/art/make_night_layers_v2.py <远景> <中景>`：远景拆成 星空 sky / 月晕 halo / 月亮 moon / 云 clouds / 海面 sea；中景拆成 雪山 mountains / 城堡小镇 castle / 石桥 bridge；近景 near 沿用 v1。各层倍率写在 `layers.json` 的 `scroll`。
  - 云：GrabCut 分割（亮白 = 云种子，暗 = 天，银河和月亮强制当天），软边反混色；图块 1720 宽（原图 1280 + 440 空隙），两端带噪声渐隐；运行时 0.05 倍 + 每秒 3px 风飘。
  - 星空：挖掉云和月亮（含最亮的一圈月晕）后，按行插值的平滑底色 + 按行密度合成星点补洞；镜像重复（0.01 倍，走十几万像素才会看到镜像处）。
  - 月亮：上半边缘拟合圆（中心 1064,160，半径 95），被云遮的下半部分用上半部分对称补；月晕按径向中位数从天空里减掉，单独做加色贴图。
  - 海面：去掉原图月光带（用左边一段替换），256px 宽交叉淡化做成 1024 周期；`night_sea.gdshader` 逐行视差（地平线 0.12 → 桥脚 0.42 → 步道后沿 1.0；步道下 1.0 → 屏幕底 1.25）+ 程序月光带（固定在月亮下方，亮纹取自水波）。
  - 中景：GrabCut 分开“山/山丘”和“城堡/小镇/谷雾”（城堡框里用 偏蓝亮雪 = 山、灰白墙面/暖色窗 = 城堡 做种子，孤立的小块归城堡）；山层用避开城堡和钟楼的三段拼成 751 周期，被前景挡住的部分往下延伸融进谷雾；桥灯按实际灯心找出 8 个灯距（490px）做严格周期，桥灯从城堡层抹掉、归桥层。
  - 已知小瑕疵（可接受）：城堡两侧各有一小块山体被归进城堡层；天空里有几缕很小的薄云没分出来（跟星空一起几乎不动）。
  - 测试：test_backdrop 改成检查各层“贴图宽 = 周期”和“视差由远到近递增”；全套 271/0。旧的 far/mid 图层和 night_far 着色器已不用（GitHub 上删除）。
- **节点 10 角色画质：完成**（跑步按用户要求不处理，要整套重做）。
  - **高清采样**（所有序列帧精灵）：`assets/shaders/char_hq.gdshaderinc`（宏 `HQ_SAMPLE`，按“一个屏幕像素盖住多少贴图像素”取 n×n 点平均，n 自动 1–6；2 倍范围反锐化 `hq_sharp=0.8`；边缘收紧 `hq_edge=1.12`）。`char_hq.gdshader` 是默认材质（ArtCache.apply 在精灵没材质时自动挂），夜景玩家的 `char_light.gdshader` 也 include 了同一套。贴图加载时预乘透明度（`ArtCache.premultiply`），着色器用 `blend_premul_alpha` → 透明边不再混黑。注意：**不能把 TEXTURE 当参数传进自定义函数**（兼容渲染器报 custom_samplers 错），所以取样写成宏。
  - **代码修帧**：`tools/art/fix_frames.py`（不带参数 = 修 `TARGETS` 里全部；`PREVIEW=目录 ONLY=帧号 python3 tools/art/fix_frames.py 动作名` 只出“原图|修复后”对比图）。修的内容：① 白/灰特效（低饱和、大块、大量贴着透明区的连通块）在预乘空间高斯平滑 σ4 再收紧边缘，边缘带一点淡紫；**身体轮廓里面保持原样**（白光压在脸/胸口上的部分一模糊就成烟）；② 细横线（连通块判断 + 逐行找竖直厚度 ≤4 的长横段：底部 40px 带里 ≥40px、其他高度 ≥150px）；③ 孤立白色竖条、远离身体的小碎块；④ 身体外面的暗色/灰紫色半透明脏边。输出 `assets/image/fixed/<原路径>.webp.b64`（有损 webp q90 的 base64 文本），`battle.json` 的 `sprite.assetOverride = {原路径: 修复帧}`，ArtCache 加载原路径时自动换（读不出来就退回原图）。几乎没改动的帧（无特效、擦除 <300px）不存。现在 154 帧，约 6.6MB。
  - 修了哪些：一击 1、5–7、12；二击 0–10；三击 1–11；强普 9–19；冲刺左 1–13、右 1–34；格挡起手 8–9；格挡受击1 0–3、受击2 3–6、受击3 9–11；弹刀1 1–3、弹刀2 1–5、弹刀3 1–3、8–9；死亡 21–24、42–45、75–81；空中攻击 1–3（只擦脏边，紫色刀光本身质量好）。帧号从 0 数。
  - 换帧：强普（以及共用同一组帧的 charge_slash、attack_up）第 8 帧身体糊成一团 → 换成第 7 帧（多停一拍），等 GPT 重画。
  - **修不了、要 GPT 重画的**：清单和每条提示词在 `docs/GPT-重画清单.md`（转身两组、起跳 1 张、落地 3 张、冲刺右 9 张、冲刺左 2 张、强普 1 张、弹刀1/3 各 3 张、弹刀2 2 张）。图回来后：抠透明 → 按前后帧对齐脚底和身高 → 写进原路径或 assetOverride。
  - 开发工具：`tests/dev/char_gallery.gd`（MAT=none|hq、SHARP、EDGE、FRAMES="动作:帧,..."，每页 10 格）。
  - 测试：全套通过，无着色器报错。
- **节点 11 手感大改：完成**（数值都在 `assets/data/battle.json`，训练场和夜战共用；脚本 `/data/work/n11/data.py` 只是一次性改数用的）。
  - **移动**（`player.gd`，夜战 `player_factory` 和 `training.gd` 都调 `player.apply_movement_config(config, settings)`）：跑速 186→**340**、加速 6000、减速 7200（松手/反向用减速，急停 3 帧滑 5px）、空中操控 0.85；跑步动画 fps 18.28（= 跑速 / 步幅 18.6，脚不打滑；新跑步帧到了要按新步幅重算 `run.fps`）。
  - **跳跃**：jumpSpeed 1000、上升 0.34s、下落 0.26s（**修了旧 bug：普通跳的下落一直用的是上升重力**，现在 `_air_gravity()` 下落用 _fall_gravity）、下落速度上限 `maxFallSpeed 1300`（替代写死的 2400）。满跳 178px、21 帧到顶、滞空 0.63s。**松键小跳**：上升中松开跳键 → 重力 ×`jumpCutGravityScale 2.8`，最低约 80px；只认真实键盘（`_keyboard_frame`），机器人/注入帧不触发。空中攻击悬停结束和被击飞用 `airAttackGravity / knockGravity 1476`（= 旧下落重力，空连节奏不变）。起跳 fps 26.5、下落 fps 22。
  - **落地分轻重**：每次离地记最高点 `_peak_y` → 落地写 `last_fall_height`、`last_landing_heavy`（下砸，或落差 ≥ `heavyLandingHeight 260`，二段跳满高会算重落地）。轻落地：落地动画 ×`locomotion.lightLandingSpeed 2.2` 快放、第 `landingCancelFrame` 帧就能动；重落地：原速播、`heavyLandingCancelFrame 2`，并且 `heavyLandingLagFrames 7` 帧内走路 ×0.25（跳/出招可以直接取消）。节点 12 的落地音效要读 `last_landing_heavy`。
  - **招式分段变速**（帧不删，只改播放速度）：招式可写 `startupSpeed / activeSpeed / recoverySpeed / tailSpeed`（四段：前摇 / 判定 / 后摇到接招点 / 收招尾巴；tail 默认 = recovery），`settings.startupSpeedMultiplier / recoverySpeedMultiplier` 是全局倍率（现在 1）。`configuration.gd` 按四段重新算帧数，`move_definition.gd` 存 `phase_frame_ends`（物理帧）和 `phase_anim_ends`（动画秒，**必须 PackedFloat64Array**，Float32 会让命中帧错一帧），`anim_seconds(f)` / `anim_progress(f)` 分段线性映射；`character_view` 和冲刺斩位移曲线、根位移都改用它。没写速度的招式完全不变（parry_1、ranged_1）。
  - 各招速度（前摇/后摇/尾巴/提前收招延迟）：一击 1.45/1.25/1.6/4、二击 1.35/1.3/1.6/4、三击 1.0/1.5/1.8/4、强普 1.3/1.5/1.8/4、挑飞 1.4/1.5/1.8/4、空中挑 1.4/1.2/1.3、空中 1–3 段 1.4|1.2|1.0 / 1.2|1.2|1.5 / 1.3|1.3|1.7、冲刺斩 1.25/1.6/2.2/2（chainFrame 33→26）、冲刺斩左 1.2/1.5/1.5/2、格挡受击 1/2 后摇 1.4 尾巴 1.6、格挡受击 3 1.6/1.6、弹刀反应 1–3 1.5/1.6。结果：一击 0.55→0.43s、三击 1.25→0.92s、强普/挑飞 1.29→0.92s、冲刺斩 1.46→1.03s、格挡受击 3 1.5→0.98s。
  - **后摇取消**：非受击反馈的招式，后摇里随时可以 弹刀（L）或 冲刺（Shift+J，`_try_dash_cancel`）取消；接招窗口里也能冲刺取消；过了接招点 + `moveCancelDelay` 帧后按方向键直接收招走开（`_try_move_cancel`；打中过的话连段指针前进一格，接着按 J 是下一刀）。冲刺斩单独有 `_dash_recovery_cancel`：弹刀/跳 随时；过接招点后可冲刺 / K / J（J 从第一刀开始）；方向键收招。
  - **转身**：转身动画保留，播放 ×1.4（`locomotion.turnRight/turnLeft.playbackSpeed`）。
  - **镜头前瞻**：`camera.lookAhead 110`，速度超过半个跑速才往移动方向平滑偏移（打怪锁场时不影响）。
  - 测量工具：`tests/dev/feel_probe.gd`（无头跑，打印起步/急停/跳高/滞空/各招时长）。新测试 `tests/test_feel.gd`（27 项：跑速、急停、跳高范围、下落比上升快、下落上限、小跳、轻/重落地、各招整招时长上限、命中帧不早于原来的 60%、后摇可冲刺/弹刀/方向键取消、没写速度的招式不变）；改了 test_desktop_integration（步幅一致、speed ≥ 300）、test_training（动画播满且整招更短）、test_framebaker_runtime（tick 测试前清掉 light_1 的速度键）。
  - 验证：全套 training 36 / combat_feedback 52 / framebaker_runtime 52 / locomotion 12 / action_flow 45 / desktop_integration 28 / night_combat 50 / feel 27，全部 0 失败。机器人整轮：SEED 3 → 112.7s 清 3 场 0 死；SEED 7 → 115.6s 0 死（以前 126–139s）。录屏抽帧检查，跑/跳/空连/落地/取消没有画面问题。
- **节点 12 音效：完成**（新音效库 `assets/audio/sfx_v3/`，71 个变体，vorbis q5 44.1k 单声道，存成 `<事件>_<序号>.ogg.b64` 文本 + `manifest.json`；仓库只能推文本，所以用 base64）。
  - **素材**：`art/selected-video-audio/` 6 段原声（A=action_00014 刀风 11 段 + 低频闷响；D=冲刺攻击 3 段长刀风；G=左侧格挡 刀风 + 闷响；B=拔刀40 低频闷响 + 1.78–2.4s 金属“铮”尾音；X=死亡 0.7–2.2s 是人声（**不用**）、3.01s 倒地闷响；K=空中a 3 段刀风）。刀风全部切自原声（`make_sfx_v3.py` 的 `WHOOSH` 表），按招式变速/变调、峰值对齐到 0.05s；其余（脚步、起跳、落地、命中肉感、弹刀金属、格挡、眩晕、挑飞、下砸碎石、撞墙、连锁、影卒蓄力/挥击/消散、封场、清场、倒下、冲刺）用 numpy 代码合成，部分叠原声闷响/“铮”。
  - **再生成**：`python3 tools/audio/make_sfx_v3.py`（只写游戏文件）；`python3 tools/audio/make_sfx_v3.py <目录>` 额外写 wav 预览。工具库 `tools/audio/sfxlib.py`（解码/编码、滤波、包络、金属/铃声、混响、限幅、按 50ms RMS 归一）。每个事件的变体数、目标响度、总线、随机音高写在 `SPEC` 表。
  - **播放**（`scripts/presentation/audio_feedback.gd`）：启动时读 b64 → `AudioStreamOggVorbis.load_from_buffer`（静态缓存，训练场/夜战共用）；同一事件不连续挑同一个变体 + 小幅随机音高；音效库缺某个事件时退回旧的 13 个 wav（蓄力、手里剑仍用旧的）。配置在 `battle.json` 的 `audio`：`swingByMove`（招式 → 刀风）、`hitTier`（招式 → 轻/重/终结命中）、`footstepStride 56`（每跑 56px 一步，起跑先垫 0.6 步）、`gainDb`（按事件微调音量，dB，目前为空）。
  - **事件表**：刀风 = 玩家 `swing_cue` 信号（判定帧前 `swing_cue_lead_frames=3` 帧发，一招一次；弹刀/格挡反应/远程不出刀风）；冲刺斩起步另加 `dash`；起跳 `jump` / 二段跳 `jump_double`；落地 `land_light` / `land_heavy`（看 `player.last_landing_heavy`，下砸落地也走这里）；命中 `hit_light/heavy/finisher`（一击二击、空中 1/2 段、空中挑 = 轻；挑飞、冲刺斩 = 重；三击、强普、空中 3 段 = 终结）；被打 `hurt`（影卒）/ `hurt_heavy`（甲影）；弹刀 `parry`；格挡 `block`；破防眩晕 `stun`；挑飞 `launch`；下砸 `slam`；撞墙 `wall`；连锁 `chain`（层数越高音越高）；影卒 `shade_windup(_heavy)`（`shade.windup_started`）、`shade_swing(_heavy)`（`shade.strike_started`）、`shade_die`；封场 `seal`；清场 `clear`；倒下 `die`；脚步 `step`（地面、空闲状态、速度 > 0.45 跑速）。
  - **混音**：主总线加了硬限幅（`AudioEffectHardLimiter`，上限 -1 dB，`_ensure_limiter()`）——第一次录屏里命中 + 刀风 + 下砸叠在一起有 488 个削波采样，加限幅后 0 个；脚步在跑步时只有 -42 dB 太轻，`audio.gainDb.step = 6`。
  - **测试**：新 `tests/test_audio.gd`（25 项：清单每个变体都能加载、映射表完整、刀风在判定帧前 3 帧且只发一次、弹刀不出刀风、轻/重落地、站着没脚步 / 跑多远响几步、变体不连续重复、影卒信号、主总线有限幅）。`test_combat_feedback` 改成检查新事件名（hit_light / hit_finisher）。全套 training 36 / combat_feedback 52 / framebaker_runtime 52 / locomotion 12 / action_flow 45 / desktop_integration 28 / feel 27 / audio 25 / night_combat 50（共 327 项），全部 0 失败。机器人：SEED 3 → 112.7s 0 死；SEED 7 两次 138.6s 1 死 / 188.2s 2 死（**机器人结果每次会变**：`shade.gd` 的 `_rng.randomize()` 让出手冷却每次不同，SEED 只管机器人自己的决定；音效改动不碰玩法）。
  - **限制**：所有声音是分析原声 + 代码合成，没有人耳试听；用户试玩后觉得哪个不对，直接说事件名（或“第几刀的声音”），改 `SPEC`/`WHOOSH` 重新生成，或在 `audio.gainDb` 里调音量。
- **节点 13 整合：完成**
  - 录屏（带声音）：`SEED=3 SKILL=0.8 BOT_ENC=3`，1280×720 30fps，114.6s 清 3 场 0 死；音轨峰值 -1.0 dB、0 削波，50ms 响度中位 -31 dB / 最响 -7 dB；跑步脚步 -34 dB。把最响的 6 个起音时刻抽帧对照，起音那一帧正好是敌人受击白闪（音画对齐在 1 帧内）。
  - 全套测试见下方节点 12；试玩说明 `docs/试玩说明.md` 加了“第二轮更新”一节。
  - trial-wip2 通过 PR 合并进 main。

## 14. 第三轮：画风统一 + 角色变小 + 多层地形（2026-10-19，工作分支 `trial-wip3`）

### 14.1 用户原话
1. “我现在有的角色素材太糊但是生成的背景太精致怎么办，我希望改画风或者给其它解决方案。然后我希望地图有地形，光是一个屏幕就应该有纵深，角色大小能不能调成疯狂小人乱斗那种。先给我个计划”
2. （看了方案 1 / 2 / 1+2 三张样张后）“方案1+2吧，角色暂时不像素化，只像素化背景。角色大小就这么大，上下跳，暂时不用坑。”
3. 节点 15–19 连续做完、中途不用确认，最后一次性交付。

### 14.2 设计要点
- **只缩镜头、不缩世界**（`night_trial.gd` `ZOOM 0.5`、`CAM_Y 140`）：判定框、跑速、跳高、击退、身高全部不变，所以手感测试和战斗数值不用改。地面 floor_y 580 在屏幕上仍是第 580 行。文字/特效/UI 按 `1/ZOOM` 放大回原屏幕尺寸（`fx.text_scale`、`s.ui_scale`），特效 `fx_scale 1.25`；震屏幅度 ×0.75、像素对齐 2 屏幕像素；镜头前瞻 /ZOOM；`camera.position_snap = 1`（跟随位置对齐屏幕像素，内部 `_follow_pos` 不对齐，所以慢速平移不抖）。
- **夜景屏幕容器**（`night_backdrop.gd` `_scr`）：容器缩放 = 1/zoom，容器 1 单位 = 屏幕 1 像素，原来按 1280×720 写的摆放公式基本不用改；横向用虚拟镜头 `screen_left() = 镜头中心 x × zoom − 640`。近景步道、灯笼光也在容器里，但按世界比例（×zoom）显示。各层滚动对齐 `SNAP 2` 屏幕像素。
- **背景退后 + 像素化**（`assets/shaders/night_pixel.gdshader`，z −75，读屏幕纹理，只处理已经画好的夜景层）：按屏幕高度，`y_full 520` 以上全强度、`y_near 585` 以下 `near_amt 0.3`；去饱和 `desat 0.25`、往冷蓝灰 `pivot` 收对比 `flatten 0.17`、压暗 `dim 0.12`；2×2 块平均；量化到 64 色调色板（`tools/art/make_night_palette.py 截图… [--n 64]` 离线 k-means，保证灯笼火/萤火/月白在里面，写进着色器 `@@PALETTE@@` 段；截图用 `scene_shot.gd` 的 `BG=1 NOQ=1`）。
- **角色描边**（`char_light.gdshader`）：外圈 `ol_width 2` 屏幕像素深色描边（亮且偏蓝白的刀光不算轮廓，刀光外面不描）；`punch_con 1.08`、`punch_sat 1.12`；`hq_max_taps 8`（缩小一半后超采样点数要更多）。影卒（程序绘制）没有加描边，而是按 `ui_scale`（= 1/ZOOM）加粗轮廓光线、放大头顶血条/失衡条/预警符号。
- **地形**（`scripts/night/terrain.gd`，z −70，在像素化层之后，所以清楚、不被量化）：
  - 两种部件：**单向平台** platforms（plank 木栈道 / roof 亭顶 / slab 断桥石板，能从下面跳穿，S+空格 下穿）和 **实心石台** blocks（stone，从顶面实心到地面，侧面挡路）。没有坑，地面一直在。
  - 三段布局 `SECTIONS`（x 相对封印中心，y 是世界坐标，地面 580）：
    - 栈道：plank −760..−380 @440、380..760 @440、−180..180 @312；去下一处的路上 slab 1560..1800 @460、plank 1960..2160 @388。
    - 石阶：stone −1200..−700 @472、620..1200 @452；plank −260..260 @400；路上 stone 1700..1900 @512、slab 2040..2240 @420。
    - 亭子：stone −200..200 @488；slab −900..−560 / 560..900 @440；roof −264..264 @280；路上 plank 1600..1880 @452。
    - 每段有 7 个出生点 `spawns [x, 脚底y]`，`encounter._pick_spawn_point` 轮流取、跳过离玩家 <300 的。
  - 关卡间距（`night_trial.gd`）：`ARENA_HALF 1200`、`FIRST_ARENA_X 2500`、`ARENA_SPACING 3600`、`TRIGGER_BEFORE 1000`；第 i 处中心 `_center_of(i)`；`_ensure_terrain(i)` 建 i、i+1，拆 i−1 以前的。三段循环使用，第二轮从“栈道”重新开始。
  - 物理：玩家走 Godot 物理，石台 = 第 1 层实心碰撞体；平台 = `ONE_WAY_LAYER 32`（16 是弹丸、2 是玩家自己）单向碰撞体。玩家 `collision_mask = 1|32`、`one_way_mask = 32`。
  - 下穿（`player.gd`）：地面 + S（axis.y > 0.5）+ 跳 + `standing_on_one_way()` → `_try_drop_through`（去掉 32 层、velocity.y 60、土狼时间作废）；`_update_drop_through` 在脚底低于平台 30 / 回到平台上方 / 落地 / 超时 40 帧时恢复。`is_dropping_through()`。
  - 影卒不用物理：每帧问 `terrain.support_y(x, 脚底, 半宽, 忽略的y)`（脚下最高的面，台阶容差 `STEP 6`）、`push_out()`（石台侧面挡路，撞上算撞墙）。AI（`shade.gd`）：`_level_gap()` 判断目标在哪层；`_chase_level`：目标在上方且 |dx|<300 → 起跳 vy = −sqrt(2·2000·(高差+40))；在下方且站在单向平台上 → 下穿；`_hop_obstacle` 翻石台；只在地上出刀；`_separate` 只推同层（脚底差 ≤20）；下砸冲击波只掀同层（<40）。
  - 其他接入：复活落在 `solid_top`；玩家影子落在脚下的面上；落地尘土位置用地形；`_lamp_at()` 合并堤岸灯笼和亭子灯笼的光（`terrain.lantern_light`，`LANTERN_REACH 300`），角色走近亭子会被染暖。帮助文字加“S+空格 跳下木台”，情境提示 `&"drop"`。
  - 画法（节点 18）：全部代码画像素块，一格 `CELL 4` 世界单位 = 2 屏幕像素（和背景像素块一样大）；月亮在右上：顶面和右侧受光、左侧和下面暗。木栈道：粗立柱（12 宽）、雀替斜撑、中段横档、桥面板缝、梁头、柱脚石墩、桥面小木桶。石台：砖纹越往下越暗、压顶、右亮左暗、青苔。断桥：7 格厚板、参差断口、拱肩、56 宽石墩、碎石。亭子：瓦顶、翘角、屋脊、红柱、挂落、两盏灯笼 + 叠加光晕。颜色常量 `C_*` 在 terrain.gd 里，取自背景调色板附近，只略亮、对比略强。

### 14.3 验证方法
- 测试：`/data/work/runtests.sh`（默认列表已加 `terrain`）。新 `tests/test_terrain.gd` 48 项（layout 布局数据、queries 面查询、player_platform 玩家跳上/下穿木台、player_block 石台挡路、shade_platform / shade_chase 影卒站面/跳上/下穿/翻台、shade_launch 浮空落在台上、shade_block_wall 撞石台算撞墙、separate_levels 不同层不互推、arena_spawns 封印出生点）。
- 截图：`DISPLAY=:99 SHOT_DIR=… XS="2500,6100,9700" SHADES="-560,600" ONTOP=1 godot --path . --script res://tests/dev/scene_shot.gd --resolution 1280x720`（三段中心 2500/6100/9700；`ONTOP=1` 把角色/影卒放到最高的面上）。
- 机器人 `tests/dev/bot_night.gd` 会跨层：目标按“横距 + 2×高差”选同层优先；目标高 >40 且 |dx|<260 → 跳（高差 >120 用二段跳）；目标低且自己在木台上 → S+空格；地上推不动（被石台挡）→ 跳过去（路上也会）；最后打印 `NAV {jump_up, drop, hop}`。注意玩家脚底 = `global_position.y + foot_offset(84)`，影卒用 `level_y()`。

### 14.4 进度日志（第三轮）
- **节点 15 / 16：完成**（trial-wip3 提交 577973d）。样张阶段做过方案 1（缩小+描边）、方案 2（统一像素风）、方案 1+2 三张，用户选 1+2 但角色不像素化。
- **节点 17 / 18：完成**（trial-wip3 提交 acbb885）。全套 training 36 / combat_feedback 52 / framebaker_runtime 52 / locomotion 12 / action_flow 45 / desktop_integration 28 / feel 27 / audio 25 / night_combat 50 / terrain 48（共 375 项）0 失败。
- **节点 19：完成**。机器人整轮（SKILL 0.8）：SEED 7 → 139.1s 清 3 处 0 死（NAV 跳上 3 / 下穿 3 / 翻台 5）；SEED 11 → 142.4s 0 死（第二轮是 112–188s）。录屏 `月下堤岸试玩录屏-第三轮.mp4`（不进仓库，直接发给用户）。录屏这一局 147s、0 死，第 1 轮结算 A（2:07、最高连击 24、眩晕/挑飞 21/15、下砸/撞墙/连锁 8/1/2、弹刀 1、受击 8 次 104 伤害）；抽帧检查栈道/石阶/亭子三段、跨层追击、结算面板都正常。
  - 开 PR #3（trial-wip3 → main），merge 方式合并，合并提交 e3fc5bb；合并前 main 仍是 0417e86，没有冲突。**以后接手**：在 main 上开新分支（例如 `trial-wip4`），先 `list_commits` 看用户有没有从本机上传新提交。
  - 机器人 parry 统计这两局都是 0（第二轮 6 次）：机器人的决策顺序问题（计划队列里塞满了导航/出招），不是弹刀坏了——同一版本里机器人没出刀那次弹刀了 30 次，night_combat 的弹刀测试也全过。
- 已知/待定：跑步序列帧用户会重做（新帧到了要按新步幅重算 `run.fps`）；`docs/GPT-重画清单.md` 仍有效（角色没像素化）；坑、斜坡、镜头自动拉远拉近这一轮没做（用户说“暂时不用坑”）。

### 14.5 第四轮准备：像素画背景 + 地形重画（等用户的 GPT 图）
- 起因：用户问“为什么背景没有像素化”。原因是 `night_pixel.gdshader` 的 `block = 2.0`（每块只有 2×2 屏幕像素）太细，原图又是精细绘画，看起来像“稍微糊了点的画”而不是像素画。给过对比图（2 倍 / 3 倍 / 4 倍）和两个方案：① 调大像素块；② 用 GPT 重画真正的像素画。用户回“OK”并要求以后用 GPT 出图（§0）→ 走方案 ②。
- 决定：美术像素 = **3 屏幕像素**（4 倍时近景石墙、石灯笼只剩几个点，画不精细）。GPT 出 1536×1024，提示词写“相当于 512×341 的像素画放大 3 倍”，画布 1 像素 ≈ 屏幕 1 像素。
- 提示词：`docs/GPT-像素背景与地形提示词.md`（0 画风样张 + 1 天空 / 2 云 / 3 雪山 / 4 城堡小镇 / 5 石拱桥 / 6 海面 / 7 近景堤岸 / 8 木栈道部件 / 9 石台部件 / 10 断桥部件 / 11 亭子）。参考图在 `docs/视觉设计/ref/moon-embankment/`（orig-far / orig-mid / orig-near = 用户原来的三张，game-now = 第三轮游戏截图）。
- 流程：先让用户出第 0 张给我们确认画风 → 再出 1–11（都上传第 0 张作参考）→ 用户发回 → 我们接入（文档末尾“接入时”一节：检测像素格还原、抠洋红、无缝、关掉 shader 的像素化/量化只留退后调色、地形 `CELL` 改 6 世界单位、平台顶面对齐美术）。
- 状态：提示词已给用户，**等第 0 张**。新分支建议 `trial-wip4`。
- 另外提过但用户还没确认：把环境恢复（下载 Godot、装 Xvfb、runtests.sh、gh 登录）做成仓库里的一键脚本 `tools/dev/`。


## 15. 选后视频原声接入（节点20，2026-10-19）

用户新要求：“看看现在GitHub里面游戏文件，修改游戏音频，改成这些视频的音频，没有的不改，有些很老的音频要删”。本机已经快进同步38个提交至 `2e15334`，以当前夜景试玩和新版银行为基础；没有回退成旧训练场版本。

- 原声：`art/selected-video-audio/` 六段M4A原样留档，哈希逐份核对。运行用 `assets/audio/selected-video/` 16份32kHz双声道PCM WAV；只切片、4ms淡入/最多25ms淡出和固定增益，不滤波、变调、合成叠加。逐文件来源/秒数/哈希见运行目录manifest。
- 对应：地面三刀来自A对应三次挥剑，强化挑飞/蓄力出刀来自A强化动作；空中三刀来自K各次挥剑，兼容空中上挑用第一刀。左右冲刺D分别切片（左侧单独 `swing_dash_left`）；格挡/弹刀G；拔刀/收刀B；死亡X只取2.99–3.34s倒地片段并裁去领先空白，不含中间人声，在死亡事件发声，未调整150帧复活规则。
- 音画：原有 `swing_cue` 提前三帧；源刀风峰值处理到50ms，短前摇按实际cue提前量seek避免晚响。格挡/弹刀峰值约12ms。冲刺原片已包含位移声，`play_dash`不再叠另一个旧起步声。draw/sheathe跟随ActorSprite实际clip，只触发一次、被动作取消即停，转idle允许尾音结束；关闭脚步也不影响拔收刀声。
- 播放：仍由 `sfx_v3/manifest.json` 路由，加载器现在兼容直接WAV和旧OGG.b64。sourceVideo信息进入静态缓存；原声固定原音高，旧事件继续原有变体与音量规则。battle.json只改变 `audio.swingByMove.dash_slash_left`，其他配置语义完全一致。
- 清理：删除被覆盖的27份生成OGG.b64；无合适视频替代的44份变体字节完全不变。旧11个WAV仍用于13槽中的蓄力/远射及缺银行事件时兜底，连同LICENSE保留。原版帧、6份完整音轨均不删。
- 复建：`python tools/audio/apply_selected_video_audio.py`（Python3.11+标准库和FFmpeg）。旧 `make_sfx_v3.py` 最后自动调用它，不会把对应动作恢复成合成混搭；它会删除自己覆盖的旧生成变体，不碰原M4A或旧兜底WAV。
- 验证：新专项 `test_selected_audio.gd` 14项覆盖原WAV加载/双声道32k/缓存/两向冲刺只响一次/禁止变调/拔收刀取消/静音/清理；现有audio25、combat_feedback52、feel27、night_combat50，共168项0失败。另检验16WAV哈希、时长、无削波、起音峰值、27项删除与44项逐字节不变。没有整轮机器人和录屏。新专项在退场后等100ms让真实音频线程释放WAV播放对象，避免fixed-fps测试过早退出的ObjectDB提示。

## 16. 第四轮：照《疯狂小人战斗》重做手感 + 敌人 + 大招 + 音效（2026-10-19，分支 `trial-wip4`）

用户要求：手感照疯狂小人乱斗（震屏、顿帧、前后摇）；音频有问题要换；血条保留；击退和敌人按提案改；加大招；**键位先别动、镜头先不做**。

### 16.1 参考：《疯狂小人战斗》原版数据（30fps，换算成 60fps 要 ×2）
- 出手很快：地面拳 7 帧、上勾 8、空中拳 11、跑动拳 13；原版**没有输入缓冲**（我们保留 16 帧缓冲，手机/键盘更友好）。
- 击退：`Power = P + P×攻方重量 − P×受方重量 + 伤害%/100×ln(P)×P + Combo/4`——越打越飞得远。
- 顿帧极短：受击方≈1 帧、攻方 1–2 帧；**只有 Power>20 才震屏**（轻拳不震）。
- 伤害随连段递增、落地清零。

### 16.2 改了什么（节点 ①–⑤）
| 节点 | 内容 | 关键文件 |
|---|---|---|
| ① 手感 | 前摇/判定/后摇按上表重排（60fps）：轻1 5/3/4/8、轻2 4/3/6/10、轻3 4/5/14/14、蓄力 6/5/10/14、冲刺斩 7/8/12/12；顿帧 攻3–8/受4–10；**轻击不震屏**；输入缓冲 16 帧 | `tools/dev/apply_feel_v4.py`（直接改 battle.json，可重复跑） |
| ② 敌人 | 4 种影：影卒（普通）、甲影（重、霸体、会格挡）、影弓（远程，会后撤保持距离）、影爆（扔炸弹）；格挡/破防/翻滚/误伤；**百分比击退**（伤害% 越高飞越远，头顶显示 %）；尸体撞墙也算撞墙 | `scripts/night/shade.gd`、`shade_bolt.gd`、`shade_bomb.gd`、`night_trial.gd` 波次 |
| ③ 受击 | 主角轻击（击退速度<350）不倒地、直接恢复 + 12 帧无敌；重击倒地 20 帧 | `player.gd`：`soft_knock_threshold` / `soft_recover_invuln` / `hard_down_frames` |
| ④ 大招 | 打中/挨打攒能量（满 100）→ **J+K 同时按**（6 帧内）→ 暗屏定住全场 → 第 24 帧全屏斩：屏幕内所有影吃 50 伤害并挑飞，箭和炸弹斩碎；破格挡/霸体/翻滚；全程无敌 | `player.gd`（`ult_*`）、`scripts/night/ult_fx.gd`、`combat_hud.gd` 能量条 |
| ⑤ 音效 | 命中/受击/撞墙/砸地/脚步/跳跃/落地/影卒出手和死亡/眩晕全部换成 **Kenney CC0 真实录音叠层**（之前是代码合成，噪声“沙沙”多、拖尾长）；新增炸弹/放箭/破防/弹回/大招起手/大招斩 6 种声；同一帧同一声最多叠 2 层（横扫打一群不爆音），同类最多 3 个同时响 | `tools/audio/make_hits_v4.py`、`assets/audio/sfx_v3/`、`audio_feedback.gd` |

**用户选的 16 段视频原声（刀风、格挡、弹刀、死亡、拔刀/收刀）一律没动**，`make_hits_v4.py` 遇到带 `sourceVideo` 的条目会跳过。

### 16.3 敌人数值（`shade.gd` KINDS）
| 种类 | 血 | 伤害 | 击退 | 重量 | 格挡率 | 翻滚率 | 其他 |
|---|---|---|---|---|---|---|---|
| 影卒 | 90 | 8 | 260 | 1.0 | 0.2 | 0.15 | — |
| 甲影 | 220 | 15 | 420 | 0.6 | 0.35 | — | 霸体（轻击打不动） |
| 影弓 | 70 | 9 | 300 | — | — | 0.4 | 射程 760，保持 430–700；被贴脸先后撤 |
| 影爆 | 80 | 14 | 560 | — | — | 0.2 | 射程 640，保持 300–600 |

全局：`PCT_KNOCK 0.006`（每 1% 多 0.6% 击退）、`KNOCK_MUL_MAX 2.4`、连段每击伤害 +5%、翻滚 18 帧（无敌 14）、误伤 50%。

### 16.4 音效规格（`make_hits_v4.py`）
- 开头无静音、峰值在前 25ms 内（和顿帧同帧响）；轻击 ≤0.25s、重击 ≤0.4s、终结/砸地 ≤0.6s、大招 ≤0.9s。
- 响度（50ms RMS）：命中 −9～−11 dB、受击 −10～−11、刀风（视频原声）约 −16～−18、脚步 −28（battle.json 里再 +6）。
- Kenney 素材自动下载到 `KENNEY_DIR`（默认 `/data/sfxsrc`），授权见 `assets/audio/sfx_v3/LICENSE-Kenney.txt`（CC0，可商用）。
- 重新生成：`python3 tools/audio/make_hits_v4.py [预览目录]`；`make_sfx_v3.py` 结尾也会自动调用它。

### 16.5 测试 / 工具
- 全量：`bash tools/dev/runtests.sh` → **444 项全过**（新增 `tests/test_shades_v4.gd` 52 项；`test_audio` 加 3 项）。
- 截图：`DISPLAY=:99 SHOT_DIR=/data/shots /data/tools/godot --path . --script res://tests/dev/ult_shot.gd --resolution 1280x720 --fixed-fps 60`（headless 下截图会卡死，必须开 Xvfb）。注入按键要在 `await physics_frame` 之后设置。
- 沙盒被重置后：clone `trial-wip4` → `bash tools/dev/setup_sandbox.sh`（装 Godot、开 Xvfb :99、导入资源）。

### 16.6 没做 / 待定
- 镜头（用户说先不做）、键位（先不动）、跑步序列帧（用户重做中）。
- 大招按键 J+K 是临时的，等键位统一时再定。

### 16.7 角色特效 v1（程序特效，2026-10-21）
- **为什么用程序做**：GPT 画不出逐帧连贯的特效动画；命中/尘土/残影这类全部用代码画，风格统一可调。
- **像素画布** `scripts/presentation/pixel_fx.gd`：所有特效先画进半分辨率的小画布（1 格 = 2 屏幕像素，和背景像素块一样大），最近邻放大贴回世界 → 硬边像素风；淡出用拜耳抖动（`assets/shaders/fx_dither.gdshader`），碎成像素点而不是半透明。每帧按主镜头对齐（含震屏）。零件：STAR / BURST（爆闪，长短不一的尖刺）/ STREAK（斩线）/ RING（冲击环，粗→细，后半段碎成弧段，避免像准星）/ DISC / SPARK / CHUNK / PUFF / LINES（放射线，b<a 时往里收）/ CRACK。
- **配方** `scripts/presentation/impact_fx.gd`（接口兼容旧版）：`spawn_hit`（力度 `ImpactFX.power_of(mv)` 按伤害算；同一帧打中多只时只有第一只给全套）、`spawn_hurt`（橙红）、`spawn_parry`（白爆闪 + 横向长“镲”光 + 弹跳金属火星）、`spawn_block`、`spawn_break`、`spawn_deflect`、`spawn_wall_slam`、`spawn_ground_slam`（扁环 + 石屑 + 地裂）、`spawn_explosion`、`spawn_launch`、`spawn_kill`、`spawn_muzzle`、`spawn_dust/land/jump/dash/step`；`start_ghosts`（冲刺残影，前半段实心剪影）；`track_player`（蓄力往里收的光刺、可放时叮一下、跑步扬灰）；`track_dissolve`（影死后化黑烟火星）。调色板常量在文件顶部（尘土已调暗成夜色灰蓝）。
- **接入**：`night_trial.gd` 各战斗事件 → 对应 spawn；`fx.floor_at` 用地形高度让火星/石屑落地弹跳。训练场沿用旧调用（兼容）。
- **样片工具** `tests/dev/fx_reel.gd`：几只不动的影站主角前，按固定输入出招逐帧截图。`REEL=light,charge,launch,dash,ranged,jump,fx`（`fx` 段直接触发弹刀/格挡/挨打/破防/下砸/炸弹/撞墙/击杀），`SHOT_DIR`、`EVERY`。运行：`DISPLAY=:99 SHOT_DIR=/data/reel timeout 290 godot --path . --script res://tests/dev/fx_reel.gd --resolution 1280x720 --fixed-fps 60`。
- 地面攻击烘焙在帧里的白刀光已改成主角紫，见 16.8。

### 16.8 地面攻击刀光改紫（`tools/art/recolor_slash.py`，2026-10-21）
- **为什么不用分层素材**：`selected-original/*/effects` 和 desktop 帧不是同一拍，对不上位置；改成直接在现有帧里按“颜色 + 连通块”认出刀光再重新上色。
- **范围**：动画 attack_1/2/3、attack_2_start、attack_2_recovery、strong_attack、attack_up、charge_slash（共 138 张图，67 张有刀光/尘土）。空中攻击（air_attack_1/2/3、air_slash）的源图刀光本来就是紫色，不用改（冲刺斩见 16.9）。
- **认法**：低饱和且亮的像素做连通块 → 大块、边缘多挨透明、够粗 = 刀光（附近小碎块并进来）；贴地、不细长 = 尘土；孤立小杂点抹掉；衣服白边、刀身高光不动。
- **上色**：凸包认外缘（刀尖划过的路径），按到外缘/内缘的距离比上色：外缘固定宽白芯（略偏蓝 `efeaff`）→ 淡紫 → 紫 → 深紫并往里淡出，外缘加不规则刷痕，外侧一圈半透明紫晕（垫在角色下面）。尘土改浅灰蓝半透明。色阶和程序特效的紫一套。
- **存法**：新帧存 `assets/image/fixed-fx/<原路径>.webp.b64`（GitHub 推送只能传文本），battle.json `assetOverride` 指过去；`assetFxBase` 记原底图（重跑从这重来），`assetFxPad`=四周加的透明边（20px，给紫晕留地方），引用这些帧的 width/height/pivot 已同步换算，位置不变。
- **夜景描边**：`char_light.gdshader` 的深色描边原来只跳过“亮、偏蓝白”的像素，现在也跳过亮紫（b≥0.68、比 g 高 0.2、比 r 高 0.08），所以紫刀光、紫晕、尘土外面都不会描黑边。
- **重跑**：`python3 tools/art/recolor_slash.py preview [名字过滤]` 出预览到 /data/fxwork/recolor/；`write` 写帧并改 battle.json（可直接重跑）。

### 16.9 冲刺斩特效 v2（2026-10-21）
- **刀光改紫**：`recolor_slash.py` 加了 dash_right / dash_left（「冲刺攻击」44 张有特效）。冲刺帧的白色速度条压在身上，认法另起：纯白种子（亮且几乎不带色、够大够粗）往外长 5px；贴地且不细长 → 尘土，其他 → 刀光。压在身上的那部分刀光保持不透明（底下没有身体像素，变透明会露洞）。贴地那一截（`WAKE_TOP`/`WAKE_W`）渐变成浅灰蓝尘土，紫晕跟着淡。
- **残影**：新着色器 `assets/shaders/fx_ghost.gdshader`——只取身体轮廓（帧里的白芯 / 亮紫刀光 / 浅灰蓝尘土不画，头发的紫蓝不会被误认），平滑半透明（不再抖动成点），外轮廓一圈亮边、里面更深更透。`impact_fx.start_ghosts(src, 0.45, 16)`：按**走过的距离**每 16 屏幕像素留一个（一帧走太远就在路上补），不按时间——起步没动时不会叠成一坨；浅紫 → 深紫，0.32 秒淡完，越晚留的越淡。
- **一闪**：冲刺斩命中时 `impact_fx.spawn_dash_hit()`：从冲刺起点（`mark_dash_start`）到命中点前方 70px，一道细长亮线（`pixel_fx` 新零件 `K.SLIT`：白芯 / 浅紫 / 紫三层实色），整条停约 2 帧，再从尾端往刀尖收细消失；上下各一根细速度线往前滑，线上崩几粒紫碎光。一次冲刺打中好几个：同一条线往前接长、重新亮一下。
- **起步尘土**：帧里已烘焙尘土，`spawn_dash` 只留一小团贴地的（原来 3 团抖动点糊成一片），速度线 5 → 4 根。
- **样片**：`REEL=dash`（`tests/dev/fx_reel.gd`）。

### 16.10 顶级特效：辉光 + 重击冲击帧 + 命中收小（2026-10-22）
- **为什么自己做辉光**：渲染器是 gl_compatibility，WorldEnvironment 的 2D glow 靠不住，所以全用着色器 + SubViewport 自己做，两套：
  - **像素特效辉光**（`pixel_fx.gd` + `assets/shaders/fx_bloom.gdshader`）：像素特效小画布（1 格 = 2 屏幕像素）→ 再缩一半的 `bloom_vp` 里用 fx_bloom 取“亮的（亮度 ≥ 0.55 起）/ 亮紫的”像素做三圈模糊（半径 6 格、gain 2.0）→ `bloom` 精灵相加混合，**垫在像素特效下面**（特效本身保持硬边，柔光只露在外面）。白芯、金火花、紫斩线外面有一层柔光；尘土、墨点暗，不发光。`pfx.bloom_enabled` 可关。
  - **刀光辉光**（`impact_fx.track_glow(sprite)` + `assets/shaders/fx_glow_sprite.gdshader`）：给主角 ActorSprite 挂一个子精灵 `BladeGlow`，每帧同步贴图 / 翻转 / offset，region 四周多留 pad 给光晕；只取帧里**亮紫**的像素（头发的紫蓝偏暗、白衣服都不算），半径约 7 屏幕像素，相加混合。平时 `glow_base` 0.55 淡淡一层；打中时 `glow_hit(p)` 亮到 +0.45～0.9 再衰减（每秒 −3.2）。只在试玩关（`night_trial.gd`）挂。
- **重击冲击帧**（`impact_fx.impact_frame(p)`）：力度 `power_of(mv)` ≥ 0.6 的命中（第三刀、冲刺斩、蓄力斩、撞墙等）背景压暗：z −1 绝对（地形 −70 之上、角色 0 之下，和大招压暗同一层），角色、敌人、特效不压。普通重击 0.4 停 0.06s 再 0.16s 淡回；≥ 0.9（蓄力斩）0.52 停 0.09s 再 0.22s。顿帧（hitstop）数值没动。`impact_frames_enabled` 可关。
- **命中收小**：`spawn_hit(..., slim)`：冲刺斩传 slim=true——不画冲击环和放射线，爆闪 / 白点小 30%（“一闪”亮线顶替）。所有命中：金色爆闪 26+18p → 22+13p，同帧非第一只 0.75 → 0.65；冲击环 34+34p → 28+26p、变细；放射线变短；蓄力斩额外的白圈改浅紫、变小。`last_hit_plan` 记录不变（测试要 ≥ 5 层）。
- **空中攻击**：源图刀光本来就是紫的，不用改（16.8 已更正）。
- **样片**：`REEL=charge`（冲击帧最明显）、`light`、`dash`。

### 16.11 大招三段 + 普通攻击不规整化（2026-10-22）
**大招**（`scripts/presentation/ult_fx.gd`，J+K 同按；起手约 24 帧 → 全屏斩 → 逐个爆）
- **① 起手**：刀身点亮、绕身旋转的光丝（`pixel_fx` 新零件 `K.WISP`）、贴地风压、刀尖十字星；去掉了大招文字。
- **② 全屏一斩**：一道横贯全屏的笔刷月牙（`K.CRESCENT`，常量 `MAIN_R 3000 / MAIN_B 54 / MAIN_TILT 0.1 / MAIN_HALF 0.33 / MAIN_LIFE 0.5`），画在**角色身后**（`_back` 独立 PixelFx，z −1）；再补两道交叉的 X（交点 = 被打敌人的平均位置，延迟 0.05 / 0.09s）。出刀瞬间：**黑白两帧**（`BW_FRAMES 2`，`assets/shaders/fx_ult_ink.gdshader`：读屏幕，接近纸色的变纸、其余变墨）→ 全屏辉光闪（ult_fx 自身 ADD 材质）→ 背景压暗 → **画面沿刀痕错开**（`assets/shaders/fx_ult_split.gdshader`：圆内外两侧沿切线反向偏 `SPLIT_PX 10` 屏幕像素，中间一条亮缝），0.16–0.29s 合回。刀头带火星 + 星，尾巴碎成光点。
- **③ 逐个爆**：每只敌人身上先留一道细月牙刀痕，刀光扫过后按离主角远近依次爆（`pop_delay(i) = 0.16 + 0.1i`，且不早于刀光经过 + 0.08s）：白芯 + 爆闪 + 断环 + 紫白碎片 + 墨点 + 火花 + 两道亮线，敌人白闪。ult_fx 发 `popped(target, point)` → `night_trial._on_ult_pop`：刀声、震屏 5、这时才冒伤害数字（`_ult_collect` 期间伤害数字先存 `_ult_texts`，击杀特效不叠）。每只的顿帧 = 爆的那一刻。
- **月牙零件**：`impact_fx._crescent(center, r, b, c, d, life, delay, cols, s0, s1, edge, hairs, rough)`；刀头 0→s0 冲到头、s1 以后从尾巴擦掉；刃口小抖 + 内缘毛边 + 尾段刷毛；`crescent_span / crescent_point` 给外部算刀头位置。

**普通攻击不规整化**（`impact_fx.gd` / `pixel_fx.gd`）
- `spawn_hit(point, strength, up, dir, slim, style)`：新增 `style` = 招式 id（`night_trial` / `training` 都传 `mv.id`）。斩线从直条 `_streak` 换成小月牙 `_arc_cut`（穿过命中点，弧心在主角身后那侧，曲率每次小抖；长 (110+80p)、宽 (12+7p) 屏幕像素）。每招一种形状 × 每次随机 3 种变体（`last_hit_variant`；`debug_variant` ≥ 0 可强制）：

| 招式 | 斩痕 | 变体 |
|---|---|---|
| light_1 | 往下斜 | 单弧 / 加一道细平行弧 / 加一道分叉 |
| light_2 | 往上斜 | 同上 |
| light_3、air_light_3 | 大弧 | 大弧 + 分叉 / 小 X / 三道爪痕 |
| charge_1 | 特大弧 | + 平行弧 / + 交叉成 X / + 长分叉 + 两层断环 |
| up_strike、air_up | 竖直往上 | 单弧 / V 字 / 弧 + 分叉（保留往上飘的细线） |
| dash_slash(_left) | 细 | 细交叉 / 只一闪 / 两个小勾 |
| ranged_1 | 小 | 小星 + 火花 / 小爆闪 + 短弧 / 火花 + 小弧 |
| air_light_1/2 | 陡斜 | 两种往下陡 / 一种往上陡 |

- **消失方式**（`Fx.mode`，每个零件随机）：月牙 0 从尾巴擦 / 1 两头往中间收 / 2 原地变细碎掉；火花 0 淡出 / 1 闪着灭 / 2 缩成点（各 50 / 25 / 25%）。
- **冲击环 → 断环**：`_ring` 自动切 2–4 段，长短、缺口、粗细、消失快慢都不同。
- **爆闪不对称**：刺数 ±1，打击方向那半边长、背后短，总有一根特别长的往前戳，偶尔一根很短。
- **火花**大小不一（0.6 / 1 / 1.5 / 2.2 倍）、拖尾长短不一。**放射线**只往打击方向一片随机撒，长短不一（`_lines(..., fwd, spread)`）。
- `last_hit_plan` 名字不变（flash / cut / spark / ink / ring / lines），测试仍要 ≥ 5 层。
- **样片**：`REEL=hits`（不走输入，8 招 × 3 变体依次在主角前方打出来，每个 16 帧）、`REEL=ult`、`light`、`charge`。
