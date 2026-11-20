# 《断晓》(Nightcrow) — Godot 4.7.2 主工程

PC / Steam 2D 横版快剑动作肉鸽游戏（纯 GDScript，Forward+ 渲染）。

- **两人协作规范与分工边界（协作者必读）**：[`CONTRIBUTING.md`](CONTRIBUTING.md)
- **世界观与核心叙事准绳**：[`docs/剧情与主题规划.md`](docs/剧情与主题规划.md)
- **项目实况与留白边界**：[`docs/项目规划.md`](docs/项目规划.md)
- **工程进度总账**：[`docs/项目进程.md`](docs/项目进程.md)

---

## 一、新电脑 5 分钟跑起游戏

### 1. 克隆仓库
```bash
git clone https://github.com/fornever123/nightcrow-godot.git
cd nightcrow-godot
```

### 2. 放置 Godot 4.7.2 引擎（仅首次需要）
本仓库不托管引擎二进制，请下载 **Godot 4.7.2 Standard（Win64，纯 GDScript 版，不要下 .NET/C# 版）**，将解压出的两个文件放进 `engine/` 目录：
- `engine/Godot_v4.7.2-stable_win64.exe`
- `engine/Godot_v4.7.2-stable_win64_console.exe`

*(具体说明另见 [`engine/README.md`](engine/README.md))*

### 3. 启动游戏与编辑器
- **直接游玩主流程**：双击根目录 `OPEN_GAME.bat`
- **直进第一章影街试玩**：双击 `OPEN_RAIN_TRIAL.bat`
- **打开 Boss 技术测试场**：双击 `OPEN_BOSS_SAMPLE.bat`
- **打开 Godot 编辑器**：用 `Godot_v4.7.2-stable_win64.exe` 导入并打开根目录的 `project.godot`（首次打开会自动生成本地 `.godot/` 导入缓存，约需 15–30 秒）
- **可视化手感修改器**：双击 `OPEN_MODIFIER.bat`（需本机已装 Python 3 或 Node.js，自动打开 `http://127.0.0.1:4330`）

---

## 二、运行自动化回归测试

在 Git Bash / WSL / 终端中执行：
```bash
# 运行核心战斗与肉鸽回归套件（无窗口）
bash tools/dev/runtests.sh night_combat roguelike boss_sample terrain
```

> **注意**：`runtests.sh` 会将任何非白名单的 `ERROR:` / `SCRIPT ERROR:` / `Parse Error:` 判为失败。提交 PR 前请务必跑通你所改模块对应的测试套件。

---

## 三、核心目录结构

| 目录 / 文件 | 用途 |
| :--- | :--- |
| `scripts/gameplay/` | 主角核心战斗逻辑、出招状态机、连段/弹刀/取消判定 |
| `scripts/night/` | 敌人 AI (`shade*.gd`)、战斗循环 (`night_trial.gd` / `rain_trial.gd`)、背景与地形 (`street_*.gd` / `terrain.gd`) |
| `scripts/roguelike/` + `data.pandora` | 极简《万象棋》双引擎肉鸽系统（开局选核心 · 升级给天赋 · 合成给锦囊） |
| `scripts/boss_sample/` | Boss 战技术原型与招式逻辑 |
| `scripts/ui/` | 标题首页 (`yg_zhanzhong/`)、选角、选章、设置与暂停菜单 |
| `assets/data/battle.json` | 角色招式帧数、伤害判定与动画序列帧配置 |
| `assets/image/` & `assets/audio/` | 现役游戏美术贴图、序列帧与音效 |
| `tests/` | 无窗口逻辑回归测试套件 |
| `docs/` | 世界观总纲、项目规划与进度总账 |
