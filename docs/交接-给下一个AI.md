# 交接 · 给下一个接手的 AI（2026-10-23 晚）

> 先读这一份，再按需查细节文档。细节都在仓库里：
> - `docs/HANDOFF-试玩版.md`：整个试玩版的历史与设计，**§19～§21 是最近三次的工作**。
> - `docs/开发交接.md`：最早期的工程结构、修改器、测试命令。
> - `docs/美术方案-10分.md`：背景美术方案，**§9 是当前的「月下东方园林湖」**。
> - `AGENTS.md`：仓库规则。
>
> 本文和这些文档冲突时，以本文为准（本文最新）。

---

## 1. 用户与协作方式（必读）

- 用户：卢佳宝，GitHub `fornever123`。全程**简体中文**，常用手机看回复：**短段落、少表格**。不懂编程，需要“双击就能用”的入口。
- 项目：`E:\00game\nightcrow-godot`。Godot **4.7.2** + GDScript，GL Compatibility，窗口 1280×720。主场景是夜景试玩关 `scenes/night_trial.tscn`，F3 切到木桩训练场。
- 双击入口：
  - `OPEN_GAME.bat`：开游戏。
  - `OPEN_MODIFIER.bat`：开修改器（Vue+Pixi，和游戏共用 `assets/data/battle.json`）。
  - `上传更新到GitHub.bat`：上传到 GitHub。
  - `下载GitHub更新.bat`：从 GitHub 下载更新。
- 规矩：
  - 做大事前先给计划。
  - **需要新美术就写 GPT 提示词给用户，由用户去生图**，不要自己用代码做粗糙素材。每条提示词单独放一个代码块，说明写在代码块外。
  - 代码只负责加工和接入 GPT 图、程序特效、检验图。
  - 评价用户发来的图之前，先读图、做合成检验。
  - 交付不录屏，给几张截图即可，用户自己点开验收。
  - 不要没事就让机器人打一整轮。
  - “夜鸦”只是角色昵称，**不要用作游戏名、题材或玩法依据**。
  - 用户要求过：大招做完要**用独立的子智能体只看截图审核**是否达到商业级。
  - 用户提过“5 小时额度用到 70% 就停”。AI 看不到额度，已告诉用户由他喊停。
- 用户的审美取向（从对话中得出）：
  - 要“商业级、华丽”。
  - 背景是像素风，角色保持**高清 Q 版**（不像素化）。
  - 紫色只给主角。
  - 用户否决过：穹环/钟塔题材、紫色背景、水城方案，以及“月亮”和角色无关的命名。

## 2. 版本与交付通道（非常重要）

- **云端没有 GitHub 推送权限**：
  - `add_repo` 要求用户在 claude.ai 绑定 GitHub 账号。
  - `gh` 设备登录会被代理拒绝。
  - GitHub 公开仓库能 clone（只读）。
- **当前的交付方法**：
  1. 在云端提交。
  2. 用 `git bundle create out.bundle <用户本机当前提交>..main` 打包。
  3. 用远程设备工具把包写到用户电脑 `E:\00game\nightcrow-godot\.runtime\ai-update.bundle`。
  4. 用户双击根目录的 `APPLY_AI_UPDATE.bat`。它会 `git fetch` 包 → `merge --ff-only` → 调 `tools/github-sync.ps1` 上传 GitHub。
  - 这个 bat 已加入 `.gitignore`，不进仓库。
- **先确认用户本机在哪个提交**：用远程设备工具 stage `E:\00game\nightcrow-godot\.git\logs\HEAD`，看最后一行。
  - 写本文时用户本机在 `24e6083`（千刃 v1）。
  - 用户还没双击最新的包（包里是到 `b32a1a0` 为止的提交，以及本交接提交）。
  - GitHub main 还停在 `bb47137`。用户之前两次上传都没成功，原因未知，可能是凭据或网络。
- **不要改写用户本机已有的历史**：`d09820f`、`42bc4b5`、`24d4f32`、`266fa74`、`f2d9f6d`、`24e6083` 都已经在用户电脑上。改哈希会让快进失败。
  - `d09820f` 是用户本人的提交：它没上传过，是用用户的 `.git/index` 和 reflog 按原哈希重建的。
- **千万别提交 Godot 生成的 `.uid` / `.import`**（云端跑 Godot 会生成几百个）。用户本机已经有自己未跟踪的同名文件，提交了会让快进报“untracked files would be overwritten”。
  - 云端已把它们写进 `.git/info/exclude`。
  - `git add` 一律写明确路径，不要用 `-A`。
- 提交身份：Claude `<noreply@anthropic.com>`（hook 要求），提交说明末尾加 attribution 行。
- 用户本机的远程设备工具：
  - 只授权了 `E:\00game\nightcrow-godot`。
  - **没有 device_bash**（不能在用户电脑上执行命令），只能 stage（读）和 commit（写）文件。
  - 如果直接往已跟踪路径写文件，会和快进冲突，所以只写到 `.runtime/`（已忽略）或通过 bundle 交付。

## 3. 云端复现环境

```bash
git clone https://github.com/fornever123/nightcrow-godot.git   # 只有到 bb47137；本地新提交要从用户的 bundle 或本机拿
# Godot：
curl -sSL -o g.zip https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip && unzip g.zip
# 渲染截图要虚拟屏：
Xvfb :99 -screen 0 1280x720x24 &
godot --headless --path . --import
GODOT=<godot路径> bash tools/dev/runtests.sh          # 全量 18 个脚本 646 项，当前 0 失败
```

- **拿到最新代码**：最新提交不在 GitHub 上。两种办法：
  - 让用户先双击 `APPLY_AI_UPDATE.bat`，再从 GitHub clone。
  - 从用户电脑 stage `.runtime/ai-update.bundle`，在 `bb47137` 的 clone 上依次 fetch 历次 bundle。
  - 也可以按第 2 节的方法从用户 `.git/index` 重建。
- 截图工具：
  - `tests/dev/scene_shot.gd`：场景静帧。用法：`XS="400" SHADES="-180,200" SHOT_DIR=…`。
  - `tests/dev/ult_shot.gd`：**按主角的 ult_frame 截图**。`SHOTS="12,40,…"` 自定义帧号，`STATES=1` 打印敌人状态。
  - `tests/dev/fx_reel.gd`：特效样片。
- npm 外网不通（registry 在 noProxy 里，DNS 失败）；GitHub 可以 clone。字体是从 google/fonts 稀疏 clone 拿的。

## 4. 目前完成了什么（本轮对话）

1. **三条开发线合并**：
   - 合进来的三条：GitHub main（手感、光影）、trial-wip4（程序特效、紫刀光、旧大招分镜）、用户本机提交（原始冲刺帧、连续击退）。
   - 敌人规则：**保留连续击退，不再有失衡和眩晕**。挑飞改为任何上挑把地面敌人打上天都计分（24 分）。
   - 详见 HANDOFF §19。
2. **大招重做（当前名字仍叫「千刃」，用户已决定改名「绝影」，见第 5 节）**：
   - 代码：`scripts/night/ult_fx.gd`（整个重写）、`player.gd` 的 `ult_*`、`night_trial.gd` 的千刃段、`camera_shake.gd` 的 `base_offset`、着色器 `fx_ult_shock` / `fx_ult_grade(dim)` / `fx_ult_sil`（切入带遮罩、raw、pop_all）。
   - 时间轴（60fps），全部可在 player.gd 的 @export 调整：
     - 0～35 起势
     - 36～71 切入（**已用用户 GPT 出的正式立绘** `assets/image/ult/cutin.png`，冒出带子、边缘渐隐）
     - 72～115 十斩
     - 121～139 残心
     - 140～149 全黑刀缝
     - 150 全屏 X 巨斩，敌人白剪影定格 10 帧
     - 160 一齐爆开，伤害数字这时才出
     - 214 结束
   - 伤害：每只影 = 30 + 15 × 挨的刀数。大招期间隐藏敌人血条。
   - 子智能体审核：第 1 轮“未达到”，第 2 轮“接近”。之后按第 2 轮意见做了 v3，并换上正式立绘，**还没送第 3 轮审核**。
   - 详见 HANDOFF §20、§21。
3. **背景换成「月下东方园林湖」**：
   - 定调图已通过：`docs/视觉设计/ref/lake/keyart_v1.png`。
   - **中景·湖对岸已接入**：3 段 GPT 图用 `tools/art/make_lake_mid.py` 拼成循环长条，替换 layers.json 的 `castle`，并加了湖面倒影。旧石桥层设置了 `hidden`。

## 5. 正在进行、下一步要做的

### 5.1 大招改名「绝影」+ 重新设计特效（用户刚定，**代码还没改**）

- 名字定为 **「绝影」**（一招斩尽所有影；正好也是评价最高级 S 的名字）。
- 用户的话：“刀光你重新想一个好看一点的版本，你重新设计一下大招的动作特效”。
- 已给用户的新设计：
  1. **抹刃**：起手，切入立绘里两指抹剑，紫电从护手窜到剑尖。
  2. **影步十斩**：带雷丝的紫电月牙刀光，落点炸出黑紫羽毛。
  3. **影裂**：敌人身上是黑色撕裂口，边缘冒紫电，取代现在的白线刀痕。
  4. **绝**：收刀时所有裂口一起亮起，紫色锁链闪电在敌人之间跳一圈。
  5. **一线**：全黑后，一道横贯全屏的雷光一线劈开画面，画面错开，敌人像黑玻璃一样碎裂成羽毛，满屏落羽，盖出总伤害。
- 已给用户 6 条 GPT 提示词（聊天记录里有原文；用户出图后会发来）：
  - ① 题字「绝影」（白宣纸黑墨，抠成白字 + 紫描边，生成方式参考 `tools/art/make_ult_title.py`）
  - ② 紫电刀光 6 种（3×2 网格，纯黑底，加法叠加）
  - ③ 紫电闪电 4 道（纯黑底）
  - ④ 羽毛 12 片（4×3 网格，洋红底，要抠图）
  - ⑤ 影裂 4 种（2×2，洋红底）
  - ⑥ 终结「一线」全屏雷光斩（纯黑底）
- 接入要做的事：
  - **纯黑底的素材**：按网格切片后用 `CanvasItemMaterial` 的 ADD 混合直接叠加，不用抠图。
  - **洋红底的素材**：参考 `tools/art/make_ult_cutin.py`，只抠和边缘连通的品红，加上被包住的纯品红小块；不能按颜色全图抠，否则剑光和眼睛的紫色会被抠掉。
  - 把 ult_fx 里程序画的斩线（`_trails`）、刀痕（`_marks`）、X 巨斩、爆开分别换成这些贴图并做动画（遮罩擦出、缩放、抖动、碎裂）。
  - 印章改成「绝」字（`make_ult_title.py` 会同时输出 seal.png）。
  - 提示文字里的“千刃”全部改成“绝影”：ult_fx 注释、night_trial 的提示、HANDOFF。
  - 如果 GPT 写的题字有错字，就用 Ma Shan Zheng 字体（OFL）跑 `make_ult_title.py` 生成。
- 做完后**再起一个独立子智能体只看截图审核**（第 2 轮审核意见在 HANDOFF §21），截图发给用户。

### 5.2 背景剩下的层（`docs/美术方案-10分.md` §9）

- 还没换的层：
  - 远山：现在是旧雪山，会从树缝里露出白色。
  - 近景石板堤：现在是旧“月下堤岸”步道。
  - 前景芦苇、垂柳剪影。
  - 平台地形：木栈道、石台。
- 用户要求**图要比屏幕长很多、能循环**，所以每层都让 GPT **分 3 段出**：第 2 段附第 1 段，要求左边缘接上；第 3 段要求两头都接上，首尾相连。
- 下一张应出“远山”。提示词还没给用户，可以仿照中景那段（参考聊天记录或 §9）。
- 拼接工具 `make_lake_mid.py` 可以改参数复用：`GRID_W`、`COLORS`、`OVERLAP`、`HORIZON`，并写到对应的 layer。

### 5.3 其他待办

- 用户之前选了“修好 3 个问题”，已经完成。当初列的“完善方向”（主菜单/暂停/设置、手柄、新关卡/Boss、Windows 打包）**都还没做**，用户没要求。
- GitHub 上传为什么一直失败，还没查。需要用户双击 bat 后截图。

## 6. 关键文件速查

| 东西 | 位置 |
|---|---|
| 唯一战斗配置 | `assets/data/battle.json`（修改器也读写它） |
| 主角 | `scripts/gameplay/player.gd`（大招参数在 `@export_group("大招（第四轮）")`） |
| 敌人「影」 | `scripts/night/shade.gd`（连续击退 `knock_mul()`；`bars_hidden`） |
| 关卡 / 波次 / 事件路由 | `scripts/night/night_trial.gd`、`encounter.gd` |
| 大招演出 | `scripts/night/ult_fx.gd` |
| 特效库 | `scripts/presentation/impact_fx.gd`、`pixel_fx.gd` |
| 夜景分层 | `scripts/night/night_backdrop.gd` + `assets/scenery/moon_embankment/layers.json`（图层为 `*.webp.b64`） |
| 评价 | `scripts/night/style_meter.gd` |
| 大招素材 | `assets/image/ult/`（title、seal、cutin） |
| 美术加工脚本 | `tools/art/make_lake_mid.py`、`make_ult_cutin.py`、`make_ult_title.py`、`keyart_check.py`（定调图检查）；用户原图在 `tools/art/src/` |
