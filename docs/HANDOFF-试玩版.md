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

## 7. 战斗设计（实施时同步更新）

（待节点 3 填写）

## 8. 节点清单（状态）

- [x] 节点 0：拉取更新、体检、计划获批、环境搭好
- [x] 节点 1：序列帧对位脚本 + battle.json 锚点/根位移 + 运行时根位移
- [x] 节点 2：手感参数（跑步/转身/跳跃/缓冲/判定框/顿帧）+ 序列帧横线瑕疵清理
- [ ] 节点 3：战斗系统（敌人、失衡/眩晕、浮空连段、方向终结、连锁）
- [ ] 节点 4：夜景场景（抠图/无缝/视差/特效）
- [ ] 节点 5：角色环境光
- [ ] 节点 6：试玩场景整合（镜头、遭遇战、HUD、主场景）
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

## 10. 仍待用户拍板的旧事项（本任务不阻塞）

主题名“凝时天都”是否确定；是否更新仓库旧《视觉设计规范》；HUD 布局（`/data/ui/hud-mock.png`）；主角名字；文档放 Notion 还是仓库；格挡特效（`/data/vfx/parry/`）是否放进 assets。
