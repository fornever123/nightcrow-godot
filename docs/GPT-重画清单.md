# 需要用 GPT 重画的序列帧（节点 10 质检结论）

代码能修的（白色刀光/尘土的马赛克台阶边、细横线、白色竖条、碎点、灰紫色脏边）已经用 `tools/art/fix_frames.py` 修好，见 `docs/HANDOFF-试玩版.md` §13.4。
下面这些是**画面本身坏了**（身体残缺、剑弯了、拖影/重影、头糊成一团），代码修不了，需要重画。

用法：每条提示词单独发给 GPT，把里面列出的参考图（都是仓库里的文件）一起上传。
画好的图发回来就行，对齐位置、缩放、接进游戏由我来做。

| # | 动作 | 坏帧（仓库路径） | 问题 | 现在的临时处理 |
|---|---|---|---|---|
| 1 | 左→右转身 turn_left_right | `assets/image/desktop-actions/跑步左向转右/frame_00002.png` – `frame_00007.png` | 第 2 张头部一团黑糊；3–7 张剑弯成弯刀、有拖影 | 原样（跑步要整套重做，转身可以跟着一起重做） |
| 2 | 右→左转身 turn_right_left | `assets/image/desktop-actions/跑步右向转左/frame_00001.png` – `frame_00005.png` | 剑弯成弯刀，第 5 张有拖影 | 同上 |
| 3 | 起跳 jump | `assets/image/desktop-actions/跳向上/frame_00005.png` | 从下蹲直接糊到空中，腿有重影 | 原样 |
| 4 | 落地 land | `assets/image/desktop-actions/跳落地动作/frame_00003.png` – `frame_00005.png` | 拖影、重影 | 原样 |
| 5 | 冲刺攻击（向右）dash_right | `assets/image/desktop-actions/冲刺攻击/frame_00025.png` – `frame_00033.png` | 白色方块碎片，身体碎掉 | 已平滑刀光边缘，身体还是碎的 |
| 6 | 冲刺攻击（向左）dash_left | `assets/image/desktop-actions/冲刺攻击/frame_00006.png` – `frame_00007.png` | 同上 | 同上 |
| 7 | 强普挑飞 strong_attack | `assets/image/desktop-actions-clean/a3挑飞加后摇（强普）/frame_00009.png` | 身体糊成一团、飘在空中 | 已换成前一张（frame_00008）多停一拍 |
| 8 | 弹刀 1 parry_react_1 | `assets/image/desktop-actions/弹刀1/frame_00008.png` – `frame_00010.png` | 身体缺块、手浮在空中 | 原样 |
| 9 | 弹刀 3 parry_react_3 | `assets/image/desktop-actions/弹刀3/frame_00006.png` – `frame_00008.png` | 身体残缺、头上有紫色色块 | 原样 |
| 10 | 弹刀 2 parry_react_2 | `assets/image/desktop-actions/弹刀2/frame_00005.png` – `frame_00006.png` | 脸上有白色条纹 | 已擦掉头顶的白色竖条，脸上的还在 |

通用要求（每条提示词里都写了）：同一个角色、同一画风；和参考图同朝向、同比例；全身、透明背景 PNG；不要地面/阴影/文字；剑是笔直的细长剑、剑身紫色发光，不要弯、不要动态模糊/残影；姿势要能和前后帧接上。

## 提示词（每条单独发）

### 1. 左→右转身（7 张里的后 6 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 起点（面朝左跑）：assets/image/desktop-actions/跑步左向转右/frame_00001.png
- 原来坏掉的转身帧（只参考动作走向，不要照抄糊块和弯剑）：assets/image/desktop-actions/跑步左向转右/frame_00002.png 到 frame_00007.png
请画 6 张“跑步中从面朝左转身到面朝右”的过渡帧，接在起点后面，每张单独输出一张图：先刹车、重心下沉，再转腰转头，最后一张已经面朝右、准备向右跑。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。
```

### 2. 右→左转身（5 张全部）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 起点（面朝右）：assets/image/desktop-actions/跑步左向转右/frame_00007.png
- 终点（面朝左）：assets/image/desktop-actions/跑步左向转右/frame_00001.png
- 原来坏掉的转身帧（只参考动作走向）：assets/image/desktop-actions/跑步右向转左/frame_00001.png 到 frame_00005.png
请画 5 张“跑步中从面朝右转身到面朝左”的过渡帧，每张单独输出一张图：先刹车、重心下沉，再转腰转头，最后一张已经面朝左、准备向左跑。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。
```

### 3. 起跳（1 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 前一张（起跳前下蹲）：assets/image/desktop-actions/跳向上/frame_00004.png
- 后一张（已经在空中）：assets/image/desktop-actions/跳向上/frame_00006.png
- 要替换的坏帧：assets/image/desktop-actions/跳向上/frame_00005.png
请重画坏帧这一张：起跳离地的瞬间，双腿蹬直、脚尖刚离地，身体向上伸展，头发和衣摆被往下带，持剑姿势和前后两张一致。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。
```

### 4. 落地（3 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 前一张（快落地）：assets/image/desktop-actions/跳落地动作/frame_00002.png
- 后一张（缓冲完站起）：assets/image/desktop-actions/跳落地动作/frame_00006.png
- 要替换的坏帧：assets/image/desktop-actions/跳落地动作/frame_00003.png 到 frame_00005.png
请重画这 3 张，每张单独输出一张图：脚着地 → 膝盖弯曲下蹲缓冲到最低 → 开始站起。持剑姿势和前后两张一致。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。
```

### 5. 冲刺攻击·向右（9 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 前一张（贴地冲出）：assets/image/desktop-actions/冲刺攻击/frame_00024.png
- 后一张（向上的月牙刀光）：assets/image/desktop-actions/冲刺攻击/frame_00034.png
- 要替换的坏帧（只参考动作走向，白色方块和碎掉的身体不要照抄）：assets/image/desktop-actions/冲刺攻击/frame_00025.png 到 frame_00033.png
请画 9 张，每张单独输出一张图：面朝右贴地高速冲刺，身体前倾、剑拖在身后 → 冲到位后拔剑向前横斩，白色刀光从身后扫到身前 → 接到后一张的上挑月牙刀光。如果 9 张很难保持一致，先画 5 张关键帧也可以。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。刀光是白色、边缘光滑柔和、外圈带一点淡紫，不要方块马赛克。
```

### 6. 冲刺攻击·向左（2 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 前一张：assets/image/desktop-actions/冲刺攻击/frame_00005.png
- 后一张：assets/image/desktop-actions/冲刺攻击/frame_00008.png
- 要替换的坏帧：assets/image/desktop-actions/冲刺攻击/frame_00006.png、frame_00007.png
请重画这 2 张，每张单独输出一张图：面朝左冲刺中挥剑，白色刀光从身后扫到身前，身体完整、不要碎块。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。刀光是白色、边缘光滑柔和、外圈带一点淡紫，不要方块马赛克。
```

### 7. 强普挑飞（1 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 前一张（下蹲蓄力）：assets/image/desktop-actions-clean/a3挑飞加后摇（强普）/frame_00008.png
- 后一张（白色月牙刀光往上挑）：assets/image/desktop-actions/a3挑飞加后摇（强普）/frame_00010.png
- 要替换的坏帧：assets/image/desktop-actions-clean/a3挑飞加后摇（强普）/frame_00009.png
请重画坏帧这一张：从下蹲蓄力往上挑剑的中间一瞬，脚还踩在地上，身体开始起身前冲，剑从身前低处往上挑到腰部高度，刀光刚出现一小段。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。刀光是白色、边缘光滑柔和、外圈带一点淡紫，不要方块马赛克。
```

### 8. 弹刀 1（3 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 前一张（剑竖在身前弹开对方，有火花）：assets/image/desktop-actions/弹刀1/frame_00007.png
- 后一张（反手把剑挥出去）：assets/image/desktop-actions/弹刀1/frame_00011.png
- 要替换的坏帧：assets/image/desktop-actions/弹刀1/frame_00008.png 到 frame_00010.png
请重画这 3 张，每张单独输出一张图：弹开之后手腕回收、剑收到身侧，转腰蓄力，准备反手挥出。剑一直握在手里，手和身体要连着，身体完整。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。
```

### 9. 弹刀 3（3 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 前一张（剑竖在身前格挡）：assets/image/desktop-actions/弹刀3/frame_00005.png
- 后一张（挥出白色斜劈刀光）：assets/image/desktop-actions/弹刀3/frame_00009.png
- 要替换的坏帧：assets/image/desktop-actions/弹刀3/frame_00006.png 到 frame_00008.png
请重画这 3 张，每张单独输出一张图：格挡后把剑举过头顶蓄力 → 准备斜着劈下。身体完整，头上不要有色块。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。
```

### 10. 弹刀 2（2 张）

```
参考图（都在仓库 fornever123/nightcrow-godot 里，请一起上传）：
- 角色设定：assets/image/desktop-actions/待机/frame_00001.png
- 前一张：assets/image/desktop-actions/弹刀2/frame_00004.png
- 后一张：assets/image/desktop-actions/弹刀2/frame_00007.png
- 要替换的坏帧：assets/image/desktop-actions/弹刀2/frame_00005.png、frame_00006.png
请重画这 2 张，每张单独输出一张图：把剑竖着举在身侧格挡，剑身上闪过一道白光（白光只在剑上，不要盖住脸和身体）。
要求：同一个角色、同一画风（Q版日系动漫、黑色描边、赛璐璐上色），朝向和人物大小比例跟参考图一致；全身入画，透明背景 PNG，不要地面、阴影、文字；剑是一把笔直的细长剑、剑身紫色发光，不能弯，不要动态模糊、残影、拖影；姿势要能和前后两张自然接上。
```
