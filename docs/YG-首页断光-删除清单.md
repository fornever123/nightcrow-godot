# YG 做的首页「断晓 · 断光」—— 全部改动与删除清单

> 这份文档只为一件事：**把 YG 这次做的首页完整摘掉，不伤到别的东西。**
> 所有新文件、每处改过的旧文件、以及撤回步骤都写在这里。
> 凡是这次加的代码和资源，文件名或文件头都带 `[YG-MARK]`；`project.godot` 里加的几行也带 `[YG-MARK]`。
> 搜 `YG-MARK` 就能把这次的东西全找出来。

做的事：把 `E:\.0download\code_artifact (1).html`（WebGL2 首页「断晓 · 断光」，2026-11-03 那一版，183,857 字节）
**在 Godot 4.7.2 里重新实现了一遍**，并设为游戏启动首页。网页那条管线（7 个着色器 pass、雨滴/火星粒子、一刀两断的合成、
泛光、色调映射）逐行翻译成了 Godot 的 SubViewport 链 + canvas_item 着色器 + MultiMesh 粒子。

---

## 1. 新增的文件（删掉即回到原状）

### 首页本体
| 路径 | 作用 |
|---|---|
| `scenes/yg_title_duanguang.tscn` | 首页场景（根节点挂 `yg_title_app.gd`） |
| `scripts/ui/yg_title/yg_title_app.gd` | 总控：时间轴、状态机、键鼠输入、菜单/设置/确认、转场进游戏 |
| `scripts/ui/yg_title/yg_title_sim.gd` | 模拟：雨滴、悬珠、火星、刀口、收尾演出、鼠标交互 |
| `scripts/ui/yg_title/yg_title_stage.gd` | 渲染：SubViewport 链 + 全部 uniform |
| `scripts/ui/yg_title/yg_title_ui.gd` | 界面：章节铭文、副标题、菜单、设置面板、确认、提示、结束卡 |
| `scripts/ui/yg_title/yg_cut_half.gd` | 菜单字的斜切半片图层 |
| `scripts/ui/yg_title/yg_title_audio.gd` | 声音：启动时合成雨声床和几个音效（删掉本文件后其余代码不会报错，只是没声音） |

### 着色器（网页版 7 个 pass 的逐行翻译）
| 路径 | 对应网页版 |
|---|---|
| `assets/shaders/yg_title/yg_noise.gdshaderinc` | `HDR` 头里的噪声函数 |
| `assets/shaders/yg_title/yg_light.gdshader` | `FS_LIGHT`（昼光层） |
| `assets/shaders/yg_title/yg_shadow.gdshader` | `FS_SHADOW`（影层） |
| `assets/shaders/yg_title/yg_comp.gdshader` | `FS_COMP`（合成：一刀两断、撕裂带、昼夜互换） |
| `assets/shaders/yg_title/yg_bloom_down.gdshader` | `FS_DOWN` |
| `assets/shaders/yg_title/yg_bloom_up.gdshader` | `FS_UP` |
| `assets/shaders/yg_title/yg_final.gdshader` | `FS_FINAL`（色散 / ACES / 冲击帧 / 闪白 / 暗角 / 颗粒） |
| `assets/shaders/yg_title/yg_part.gdshader` | `VS_PART` + `FS_PART`（悬珠 / 雨 / 火星 / 光片） |
| `assets/shaders/yg_title/yg_cut_text.gdshader` | 菜单字的斜切（网页版 CSS `clip-path`） |

### 字标图（从网页版 base64 里原样抠出来的两张 GPT 字）
| 路径 | 作用 |
|---|---|
| `assets/image/yg_title/mark_whole.webp` | 整瓷版「断晓」（刀还没落时用） |
| `assets/image/yg_title/mark_cut.webp` | 白瓷影子版（切开的那张，影层用） |
| `assets/image/yg_title/yg_title_icon.ico` | 桌面快捷方式用的图标（拿整瓷字标裁的 256×256 多尺寸 ico） |
| `assets/image/yg_title/*.import` | Godot 导入配置（会自动生成，删不删都行） |

### 字体（11-05 适配时加，打包进游戏）
| 路径 | 作用 |
|---|---|
| `assets/fonts/yg_title/NotoSerifSC-VF.ttf` | Noto Serif SC 可变字体（25 MB，SIL OFL 1.1），首页中文和拉丁字都用它 |
| `assets/fonts/yg_title/说明.txt` | 来源与许可说明 |

### 首页运行时写的存档（在 `user://`，不在工程里）
| 文件 | 内容 |
|---|---|
| `user://yg_title.cfg` | 首页自己的设置：画质 / 雨量 / 镜头震动（只有首页用，删掉无害） |
| `user://settings.cfg` | 和暂停菜单共用：`[audio] master`、`[display] fullscreen`（UI 线如果也用了它，就别删） |

### 自查和文档
| 路径 | 作用 |
|---|---|
| `tests/dev/yg_title_shot.gd` | 定步快进截图脚本（`fast_forward(秒)`，和网页版 `?at=秒` 对齐） |
| `docs/YG-首页断光-删除清单.md` | 本文件 |

> `.runtime/` 下的一次性东西（`yg-ref/`网页版对照截图、`yg-title-shots/` 实机截图、`yg-title-dbg/` 分量诊断、
> `crop*.png`、`lum.py`、`diff.py`、`yg_flow.gd`、`yg_dbg.gd`、`probe_*/`）都在 gitignore 里，删不删无所谓。

---

## 2. 工程外面加的东西（桌面快捷方式）

| 位置 | 内容 |
|---|---|
| `桌面\断晓 · 启动游戏.lnk`（本机 `C:\Users\MECHREVO\Desktop\断晓 · 启动游戏.lnk`） | 双击 = `engine\Godot_v4.7.2-stable_win64.exe --path <仓库根>`，工作目录是仓库根，图标用 `assets/image/yg_title/yg_title_icon.ico`；快捷方式的「备注」里写了 `[YG-MARK]` 和删除方法 |

删除：把这个 `.lnk` 直接删掉即可（不在 git 里，也不影响工程）。

---

## 3. 改过的旧文件（只有一处）

`project.godot`

1. 文件最上面加了 4 行注释，全部以 `; [YG-MARK]` 开头。
2. `run/main_scene` 从 `"res://scenes/rain_trial.tscn"` 改成了 `"res://scenes/yg_title_duanguang.tscn"`。

**撤回**：把 `run/main_scene` 改回 `"res://scenes/rain_trial.tscn"`，再删掉那 4 行注释；然后删掉第 1 节的文件即可。

除此之外**没有改任何别的文件**（`pause_menu.gd`、`rain_trial.tscn`、各线的脚本一律没碰）。

---

## 4. 一键删除（PowerShell，在仓库根目录跑）

```powershell
# 1) main_scene 改回去
(Get-Content project.godot -Raw) -replace 'run/main_scene="res://scenes/yg_title_duanguang.tscn"','run/main_scene="res://scenes/rain_trial.tscn"' |
  Set-Content project.godot -Encoding UTF8
# 2) 删掉这次加的文件和目录
Remove-Item scenes/yg_title_duanguang.tscn -Force
Remove-Item scripts/ui/yg_title -Recurse -Force
Remove-Item assets/shaders/yg_title -Recurse -Force
Remove-Item assets/image/yg_title -Recurse -Force
Remove-Item assets/fonts/yg_title -Recurse -Force
Remove-Item tests/dev/yg_title_shot.gd -Force
Remove-Item docs/YG-首页断光-删除清单.md -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) '断晓 · 启动游戏.lnk') -Force
# 3) 收尾：删掉 project.godot 顶部 4 行 [YG-MARK] 注释
```

删完搜一遍 `YG-MARK`，应该一条都不剩。

---

## 5. 和网页版的差异（照实记，方便以后对）

有意为之、观感上看不出来的：
- **泛光**：网页版是逐级回注（`bloom[i-1] += up(bloom[i])`），这里是每级各自升采样后叠加。少 5 个 backbuffer，糊的层次略有差别。
- **矢量字标分支**：网页版 `?logo=vec` 那套矢量骨架（`GLYPH` / `strokePolys`）没搬；这里只用 GPT 那两张 webp，也就是网页版的默认样子。
- **`uTitle`**：网页版拿它做白瓷倒角高度图，GPT 模式下它其实是全黑、所有相关项恒为 0，所以这里直接去掉了。
- **dpr**：~~这里用 1.0~~ → 11-05 起按窗口真实像素渲染（1080p 全屏 = 1.5 倍，开 F7 超采样再 ×2，上限 3 倍），泛光链仍按 1280×720 算，光晕大小不变。
- **声音**：网页版 WebAudio 现场合成，这里是启动时合成成 WAV 再播，音色接近但不完全一样。
- **存档**：~~「继续」看 `user://yg_title_save.dat`~~ → 11-05 拿掉了「继续」（没有存档系统，点了等于重新开局），换成「操作说明」。
- **「退出」**：网页版是显示结束卡（网页关不掉自己），这里直接退出游戏。
- **F7 超采样**：11-05 起首页跟着生效（设置页也能开关，存 `user://graphics.cfg`）。
- **11-05 改好看**（没加新文件，改的都是上面列过的 YG 文件，改处带 `[YG-MARK] 11-05 改好看` 注释）：去掉四角框线 / 章节铭文 / 右上快捷键 / 底部玩法提示 / DEMO 版本号；字标中心 0.42H → 0.385H、字标略缩，菜单挂到副标题下 7.5u、字放大加粗、底下垫羽化暗底，选中改成两侧紫菱 + 字下银线；设置 / 说明 / 确认页去掉方框，改成羽化暗底 + 上下渐隐细线；昼光层去掉同心圆光环和悬空碎石、残碑描边压到 1/4、灰雾减半、两侧压暗、刀口以下压暗，开场光从光源处由暖金一圈圈铺开；影层倒影描边 .22 → .04、离刀口越远越暗、字倒影收短减弱；悬珠冻住后淡出的比例 42% → 60%，远处小珠更暗。
- **11-05 适配另加**：手柄（十字键 / 左摇杆选，A / Start 确认，B 返回，提示随设备换）；字体打包；设置页加主音量 / 全屏 / 超采样 / 操作方式并存盘；菜单出来就后台加载试玩，收黑后换场景、root 下挂 `YgTitleFadeIn` 黑幕 0.6 秒淡出自删；同一次运行第二次进首页跳过开场；菜单字斜切改用本地坐标（非 16:9 窗口不再切偏）；设置页鼠标点哪行改哪行（原来点了没反应）。

---

## 6. 自查记录

**2026-11-05（适配）**：1280×720 / 1920×1080 / 1680×1050 / 2560×1080 / 1080p+超采样 全套截图无报错；流程脚本（手柄跳开场 → 摇杆选「操作说明」→ A 进 / B 出 → 设置里改主音量并写进 `user://settings.cfg` → 开始 → 进 `rain_trial` → 黑幕约 0.57 秒后消失 → 再回首页直接到菜单）全过。RTX 4060 上 1080p 每帧约 4.7 ms，开超采样约 6.6 ms。

**2026-11-03**：

- 对照截图：网页版同源文件按 `?at=秒` 定格（`.runtime/yg-ref/html_06_6_ui.png`），Godot 版 `fast_forward(6.6)`（`.runtime/yg-title-shots/08_待机.png`）。
- 亮度对齐：上半区平均灰度 113.5 / 113.4，下半区 24.1 / 24.7（网页版 / Godot 版）。
- 差分图 `.runtime/diff_66.png`：除了粒子随机位置、UI（网页版截图时菜单还在 CSS 过渡里）和颗粒噪声，字标、刀口、远山、断碑位置重合。
- 流程：`菜单 → 开始游戏 → 收刀动画 → scenes/rain_trial.tscn` 实测通过（`.runtime/yg_flow.gd`）。
- 分辨率：1280×720 全套跑过，无着色器报错、无脚本报错。
