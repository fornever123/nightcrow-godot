# 《断晓》两人 GitHub 协作规范（主控审核制）

本项目采用 **「主线保护 + 个人分支开发 + Pull Request（PR）审核合入」** 模式，以项目负责人（仓库 Owner）为主控，确保代码稳定、零误覆盖、零场景冲突。

---

## 一、分工与文件归属红线（防冲突核心）

Godot 的 `.tscn` 场景文件与大型 `.json` 文件一旦两人同时修改极易产生难解冲突，因此按模块清晰划分归属：

### 1. 战斗玩法主责（协作者）
- **可直接独立开发的文件**：
  - `scripts/gameplay/**`（主角核心操作手感、连段、挑飞、弹刀、闪避、受击等；*避开大招过场时间轴段落*）
  - `scripts/night/shade*.gd`（敌人 AI、行为树、受击与硬直）
  - `scripts/night/night_trial.gd`（通用战斗循环与判定）
  - `scripts/roguelike/**`、`scenes/roguelike/**`、`data.pandora`、`pandora/**`（肉鸽构筑、天赋与锦囊玩法）
  - `scripts/boss_sample/**`（Boss 招式逻辑与 AI）
  - `tests/test_night_combat.gd`、`tests/test_roguelike.gd`、`tests/test_boss_sample.gd` 等玩法测试
- **需提前沟通再改的共享文件**：
  - `assets/data/battle.json`：**只允许调整战斗数值、帧数、判定框段**，严禁修改 `characters[0].sprite.animations` 动作序列帧路径段。
  - `scripts/night/rain_trial.gd`（涉及波次与场景衔接）。
  - `scenes/*.tscn`（如需新增节点或挂脚本，建议先用代码动态挂载或在群里打招呼再改 `.tscn`）。

### 2. 项目主控（Owner / 美术、UI、场景与总装）
- 负责 `main` 分支最终 PR 审查与合入、世界观与总体方向（`docs/剧情与主题规划.md`、`docs/项目规划.md`）；
- 负责首页与 UI（`scripts/ui/**`、`scenes/*title*.tscn`、`scripts/night/combat_hud.gd`）、场景背景与地形美术（`street_*.gd`、`terrain.gd`、`assets/image/rain_street/**`）、主角序列帧与刀光（`assets/image/desktop-actions*/**`、`battle.json` 动画段）、大招演出（`ult_fx.gd`）、音效资产（`assets/audio/**`）、`project.godot` 与打包导出（`export_presets.cfg`）。

---

## 二、日常 Git 开发流程（4 步走）

### 第 1 步：开工前永远先拉最新 `main` 并切自己的功能分支
```bash
git checkout main
git pull origin main
git checkout -b dev/combat-功能简述
# 例如：git checkout -b dev/combat-parry-window
```
> **严禁直接在 `main` 分支开发或强推 (`git push --force`)。**

### 第 2 步：本地开发与自测
- 改完逻辑后，运行对应无窗口测试确保零报错：
  ```bash
  bash tools/dev/runtests.sh night_combat roguelike boss_sample
  ```
- 若改动了手感或数值，请在实机启动 `OPEN_GAME.bat` / `OPEN_RAIN_TRIAL.bat` 亲自打一局确认。

### 第 3 步：小步提交并推送到自己的远端分支
```bash
git status
git add <你改动的文件>
git commit -m "combat: 简明中文或英文说明本次改动"
git push -u origin dev/combat-功能简述
```

### 第 4 步：在 GitHub 提 Pull Request（PR）等待主控合入
1. 打开 GitHub 仓库页面，点击 **Compare & pull request**，目标分支选 `main`；
2. 按 PR 模板填清「改了什么 / 动了哪些文件 / 测试是否全绿」；
3. 等待主控试玩审查并在 GitHub 上点 **Squash and merge** 合入 `main`；
4. 合入后删除旧功能分支，下个任务从最新 `main` 重新切新分支。

---

## 三、协作避坑铁律

1. **不要上传过程垃圾**：`.gitignore` 已屏蔽草稿、废案归档、`.mp4/.avi` 过程视频与 `.godot/` 缓存，请勿用 `git add -f` 强行把大视频或临时备份塞进 Git。
2. **禁止使用 C# / .NET 插件**：本项目严格使用 Godot 4.7.2 Standard 纯 GDScript。
3. **跨模块需求先沟通**：战斗玩法需要新动画事件、新 UI 提示或新音效触发点时，先在 PR 或聊天里约定接口字段，再各自实现。
