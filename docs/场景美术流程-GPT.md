# 用 GPT 做顶级场景美术：流程 v2（三方评审后，2026-10-25，方案阶段）

v1（“整轮画成一幅长卷再拆层”）经美术总监、GPT 出图、引擎接入三个子智能体评审后推翻重写。v1 备份在会话临时目录，结论记录见 `docs/天穹残响-重设计v2.md`。

---

## 0. 三方评审的共同结论（v1 错在哪）

1. **长卷和视差冲突（三方都指出）。** 地面层一轮走 5400 像素时，0.15 的远景只走 810、0.01 的天空只走 54。整幅长卷是在“一个镜头位置”画的，拆层后各层错开，**构图只在那一个位置成立**；两处回潮区之间远景只差 270 像素，长卷各段画的不同远景会互相打架，后面几段画的远景大部分永远看不到。
2. **回潮区开打时镜头固定一屏**（视野 2560 世界单位 > 竞技场 2480）。所以每处回潮区真正被长时间看的，是一张固定构图——应该专门画好这张“英雄画面”。
3. **草图是工程图不是构图。** 只有高度没有明暗、光路、斜线、节奏，GPT 会把拼贴的毛病忠实画出来；arena1 草图左右平台几乎镜像，正是被否过的构图。
4. **GPT 的编辑会重画整张图**：“左 1/4 保持不变”像素级做不到；“编辑拆层”各层会错位、洋红边、辉光丢失（成功率约 30%）。必须由程序把要保留的原像素贴回去、用蒙版拆层。
5. **拼贴示意不好看的具体原因**：全是横条没有斜线；远山比云海亮（空气透视反了）；左上 40% 空；青光没落到桥面（光路断了）；比例乱（拱洞比角色小、塔像贴纸）；矮墙等距排列。

## 1. 定调图为什么好看（以后每张画的验收标准）

- **明暗三段**：天空暗（亮度 20～45）、中段云海亮（60～85，峰值 >140）、桥立面和前景暗（5～35）。战斗带落在亮的中段，暗色角色压在亮底上。
- **一条光路**：月亮 + 巨环（全图最强反差）→ 环下青光云 → 桥面水洼倒影（全图第二亮）。
- **色彩 90 / 5 / 5**：九成靛蓝和中性灰，青光、暖窗各不到 3%，两种强调色不挨着，没有紫。
- **三块不对称**：左重（小镇崖斜落）、中空、右重（断塔 + 巨环）；斜线都指向中右的战斗区。
- **约 7 层纵深**：越远越亮、越蓝、反差越小；云海顶线起伏，不是直线。
- **平台有来历**：都是同一座桥的遗骸；桥面露出约 9% 画高的顶面，像舞台地板，还当镜子。

## 2. 新结构：按“层”画，不按“世界”画

| 层 | 视差 | 内容 | 循环 |
|---|---|---|---|
| 天空 | 0（贴在屏幕上） | 夜空、月亮、碎巨环、环下青光云 | 只要一张，巨环永远在右上 |
| 远景 | 约 0.1 | 远山 + 远处云海，低反差 | 一条 ≥2560 像素的循环条，各处共用 |
| 中景 | 约 0.5 | 每处回潮区一个独有地标（小镇崖 / 驿塔 / 渡槽……） | 三处地标在中景层里相距 900 像素，循环 2700 |
| 可玩层 | 1.0 | 桥面、桥立面、平台 | 一轮 5400 = 3 张 1280 的战斗画面 + 3 段 520 的过渡 |
| 前景 | 约 1.4 | 4～6 个剪影零件 | 程序按格子摆，不重复 |

- 各层循环周期互相错开（避开 2、3/2 这类简单比例），不会同时重复。
- **英雄画面**：每处回潮区锁镜头时，各层的偏移设成“合成后正好等于那张英雄画”。第 1 处的英雄画就是实战定调图（乘 0.88 正好盖住一屏）。路上各层自然错开，有视差。

## 3. 怎么画每一张英雄画面（第 2、3 处）

1. **先出 3 张灰度构图缩略图**（我按游戏坐标画，5 档明度，构图各不相同；符合第 1 节的原则：三块不对称、中心留空且亮、有斜线和光路）。**由用户选 1 张。**
   - 验收：眯眼能分出三大块明暗；贴上主角剪影 0.5 秒内能看清；不对称、没有镜像。
2. **把选中的缩略图做成彩色草图**：颜色从定调图吸（青靛、中性灰，不偏紫），亮度分布对齐定调图。
3. **拼画布**：天空（已有，原像素）+ 远景（已有，按这个镜头位置取的那一段，原像素）+ 中景左边和上一处重叠的 380 像素（已有，原像素）+ 新地标和可玩层的彩色草图。——**画布里大部分是定调图来源的真像素，本身就是风格锚。**
4. **GPT 编辑**：只把草图部分画成成品（提示词见第 7 节）。每次抽 2～3 张选 1 张；失败就回到原画布重抽，不在坏图上连续修。
5. **程序收尾**：把原像素部分贴回去，在重叠区找差异最小的走线羽化；按定调图同深度区域做颜色分布匹配。
6. **拆层**：前层（可玩层、中景地标）= 原像素 + 程序蒙版（画草图时同时导出一张“物件 ID 图”当初始蒙版，再按边缘精修）；被挡住的后层部分 = 让 GPT 出一张“去掉前面物件、补全背后”的空背景板，只取被挡住的那块。辉光、雾、倒影都不抠，留在后层或在引擎里做。
7. **碰撞**：按最终画面描（脚本按列找平台亮顶边），和草图数据对比，偏差超过 6 世界单位就报警。

过渡段（两处之间 520 像素）同理：画布 = 前一处英雄画的右边 + 草图 + 后一处的左边，背景按那个镜头位置先贴好，GPT 只画可玩层。

## 4. 像素化

- 推荐 **2 像素格**（世界画在 640×360 上，最近邻放大）；主角约 42 格高。3 像素格会把巨环青光吃成灰、主角脸糊，不推荐。
- 不做全局减色；如要减色按层减、每层 ≥48 色，锁定青光、暖灯、月白。
- 引擎里用 SubViewport 做低分辨率世界画布，界面保持高清；镜头和各层位移对齐到格子，亚像素余数加到容器位置上平滑滚动。像素格大小做成常量，切片时现场对比 2 和 3。
- 贴图离线缩到最终格子（1 纹素 = 1 格），最近邻、关 mipmap、无损导入。

## 5. 引擎里的“美”

层间雾（两条，战斗带里透明度 ≤0.15，加拜耳抖动防色带）、战斗带背光（径向渐变加色，开打时变亮）、水洼倒影（桥面那一条单独拷屏，映出腿、刀光；巨环青光用天空贴图假做反射）、巨环光纹呼吸（离线抠青色发光遮罩，沿环跑一道光脉冲）、主角和敌人冷色轮廓光、云丝、鸦群、驿塔暖灯闪。

## 6. 顺序

0. **一页规则单**：各层亮度区间、10 个从定调图取的颜色、视差表、锁镜头位置、禁用项 → 用户确认。
1. **垂直切片（先做，约 7 人日）**：只用定调图，在游戏里做出天空 / 远景 / 中景 / 可玩层拆分、2 像素格、雾、背光、倒影、光纹；碰撞按定调图描（断拱、木台约高 396～428 要二段跳；远边矮墙顶约高 140，可做一层台阶）。验收：第 1 处锁镜头截图和定调图并排不输；录 10 秒移动视频看视差。
2. 切片过了，再按第 3 节画第 2、3 处英雄画面和过渡段。
3. 远景循环条：从定调图远景扩画到 2 屏宽，错开半幅修中缝。

## 7. 待用户决定
- **要不要每次附定调图当风格参考？** GPT 评审建议附（防颜色、细节一段段漂移）；但你说过不要参考图。v2 的画布里大部分本来就是定调图来源的真像素，可以先**不附**试；漂移明显再附。
- 先做垂直切片（要改代码，需要你说“干活”），还是先出第 2 处的 3 张构图缩略图？

---

## 8. 第二轮评审后的定稿修改（2026-10-25）

**画布与出图**
- 草图占画布 30～50%，连成一两块、挨着真像素；草图带三档明暗、雾的渐变、水洼高光形状、少量结构线（铺石分格、拱圈），**不画纹理**。
- **可玩层也要真像素锚**：第 2 处画布左侧 380 像素的桥面、立面直接用第 1 处右端的真像素（桥面是重复结构，这是场景自己的像素，不是参考图）。
- 出图后：先用天空区域把输出和原画布对齐（GPT 常有 1～3% 缩放、平移）；拿 GPT 重画过的真像素区和原图对比，拟合一个颜色变换，套到新画部分上；贴回真像素的蒙版向外扩 20～30 像素再羽化。
- 每次抽 2～3 张选 1 张；失败回原画布重抽。
- 空背景板：先由程序把要去掉的物件涂成周围颜色的模糊块，再让 GPT“把模糊区画完”，模型看不到原物件就不会留残影。

**各层**
- 天空：视差 0（底板不动），另加几条 0.02～0.04 的云丝带风飘，从巨环前后穿过，有相对运动就显得远。
- 远景：视差 0.1，循环 2700（5 轮一循环，共 15 种偏移，离线拼一张 15 格对照图验收），**不放地标**，任何偏移都成立；定调图里又小又雾的渡槽、古堡放这一层。
- 中景：视差 0.5，循环 2700，和一轮同步，三处英雄画面都对得上；偏移常量取偶数对齐 2 像素格。第 3 处画布左右两边都要锁原像素（右边 380 = 第 1 处中景最左边）。地标之间补低反差的次级石岛、云中断柱，不留空屏。
- 前景：零件挂在每段数据上（像 SECTIONS），英雄画面里手摆写死，只有路上随机。
- 地标摆法：英雄画面里地标 x < 800 不碰巨环；穿过巨环的只能是细塔尖；粗体块低于 y 300；暖灯等识别部位高于最高平台顶（约 y 210）或错开平台；中景亮度 40～60、不描边，平台 20～40、带描边，两者之间夹一条雾；青色轮廓光都在朝巨环的右上侧。
- 三处共用天空和远景，所以每张英雄画面的亮区和光路位置要刻意错开。

**像素与引擎**
- 确定 2 像素格（现有代码本来就按 2 写：SNAP、地形格、pixel_fx、night_pixel、震屏都是 2）。可玩层 2700 宽超过 2048，切 2 块，切口放在过渡段。
- 垂直切片先做不碰 `night_trial.gd` 的最小版：离线把定调图拆 5 层、缩到 2 像素格、被挡部分先用程序粗补；`night_backdrop.gd` 加长卷模式（接口不变），运行时把镜头 `position_snap` 设为 2；关掉旧调色板量化；`terrain.gd` 加按画描的碰撞。这一版是“背景像素、角色高清”，最后再加 SubViewport 外壳对比整个世界一起像素化。
- 绝影不改镜头 zoom，像素化对大招的风险比上一轮估计的小。

**第 2 处回潮区的三个构图方向（灰度缩略图：`docs/视觉设计/blockin/arena2_thumbs.png`）**
- A「绳索斜线」：驿塔在左偏中，塔尖很高；绳桥从塔斜落到巨环下方的小石针，鸦沿绳飞，把视线从左上引到巨环。平台 = 长堤上层拱廊的断段、倒下的柱段。
- B「环下孤塔」：驿塔放低放右，正好在巨环下面被“戴冠”，环—塔—水洼一条竖光轴；左边一座坍塌门楼，门楼顶就是二层。平台 = 门楼、掉落的拱石、断石碑。
- C「渡槽来水」：巨大断渡槽从左上斜沉进云海，断口一道被青光照亮的细瀑落进桥面水洼，是一条新光路；驿塔留给第 3 处。平台 = 掉到桥面上的槽段、槽墩。

---

## 9. 第 2 处回潮区（C 渡槽来水）英雄画面：画布与提示词（2026-10-25）

文件（`docs/视觉设计/blockin/`）：
- `arena2_C_canvas.png`：编辑画布（1672×941 = 游戏一屏 × 1.306）。
  - **真像素**：天空 + 碎巨环 + 月亮（天空层，固定在屏幕上）、远山（远景层，比第 1 处多走 180 屏幕像素）、远处云海带、左下约 30% 的桥面和拱（取自定调图里干净的一段）。
  - **草图**（定调图吸的颜色、三档明暗、不画纹理）：左上暗色崖岩（渡槽的来处，崖脚早早没进云雾）、从崖上斜落到右下的巨大断渡槽（断成三段，墩没入云海，右上沿一道青边）、断口细瀑、往右延续的桥面（成组矮墙、不规则水洼，大的在瀑布下方）、桥立面和拱、一层平台（掉在桥面上的一段槽，槽里有积水）、二层平台（方墩顶上架着一段槽）、几只鸦、右下前景断柱 + 蕨叶、左上垂藤。
- `arena2_C_ids.png`：物件 ID 图（每个物件一种纯色），**不给 GPT**，出图后拆层当蒙版用。
- `arena2_C_check.png`：画布上放三个主角（地面、一层、二层）+ 灰度，检查可读性：三个位置背后都是亮的云雾，灰度下清楚。

平台高度（游戏屏幕坐标，地面 580）：一层槽段顶 470（x 120～370），二层墩顶 360（x 860～1020）；中间 x 440～840 留空。

### 编辑提示词（输入：arena2_C_canvas.png，不附其他图）

```
This image is a work-in-progress game background. Some parts are finished painting; the rest is a flat-color block-in.

FINISHED — keep exactly as they are: the night sky with its stars, the moon, the shattered stone ring and its teal-lit clouds in the upper right; the distant mountains and the sea of clouds across the middle; and the stone causeway deck and arched bridge in the bottom-left part of the image (about the left 30%, from the deck down).

BLOCK-IN — repaint completely as finished painting: the dark rocky cliff in the upper left, the long broken aqueduct that descends diagonally from that cliff to the lower right with its piers, the thin waterfall at its broken lower end, the stone deck continuing to the right with its low parapet blocks and puddles, the bridge face and arches below it, the two platforms, the small crows, the dark foreground shape in the bottom-right corner and the dark ivy strands at the top-left edge. These shapes are placeholders, not the final style. Paint every one of them with the same brushwork, edge softness, detail density, palette and lighting as the finished parts, so the whole image looks like one painting made in one go: high-end anime film background art, simplified clean shapes, soft cel shading, a deep quiet night. No flat or untextured area may remain.

LAYOUT IS FIXED: keep the position, size and outline of every block-in shape, especially the top edge of the deck, the tops of the two platforms, the diagonal line of the aqueduct and the outline of the cliff. Do not move, resize, add or remove shapes. Do not add any new object anywhere. Same image size and framing; do not crop, zoom or shift.

WHAT THE SHAPES ARE
- Cliff (upper left): a dark weathered rock cliff at middle distance, hazier and lower in contrast than the deck, with no outlines; its lower part dissolves into soft mist well above the deck line. A few old stone blocks show where the aqueduct leaves the cliff.
- Aqueduct (the long diagonal band): a colossal ancient stone aqueduct channel on tall slender piers, broken into three sections with gaps between them, sinking diagonally toward the lower right into the sea of clouds. It is at middle distance: no outlines, hazier and bluer the farther right it goes, its piers fading into the clouds. Its upper right edges catch the soft teal light of the ring. Its outline against the sky stays clean, with no glow around it.
- Waterfall: a thin stream of water pouring from the broken lower end of the aqueduct down into the clouds, softly lit teal by the ring, with a little spray where it falls.
- Deck (the band across the lower part, right of the finished deck): the same rain-wet stone causeway as in the finished bottom-left part, same stone size, wear and color, with low broken parapet blocks in small groups along its far edge. The pale shapes on the deck are shallow puddles mirroring the sky; the largest one, under the waterfall, reflects its teal light.
- Bridge face: the same dark weathered stone with round arches as in the finished bottom-left part, clouds visible through the arches.
- Platform 1 (the box on the deck at the left): a fallen section of the aqueduct channel lying on the deck, its flat top a walkable stone surface with a slightly lighter worn edge, a thin line of rainwater in its channel. Thin dark outline like the deck.
- Platform 2 (the T shape at the right): a square stone pier of the aqueduct standing on the deck, with a short broken piece of channel resting flat on top; the flat top is a walkable surface with a slightly lighter worn edge. Thin dark outline like the deck.
- Crows: three small black crows flying along the aqueduct.
- Bottom-right corner: a near-black foreground silhouette of a broken column with ferns. Top-left edge: a few near-black hanging ivy strands.

LIGHT: the teal light of the ring and the silver moonlight come from the upper right, as in the finished sky. They light the top faces of the deck and platforms and the upper right edges of the aqueduct, and reflect in the puddles. The open middle behind the deck stays calm and bright: a clear stage for characters.

AVOID: changing the finished parts; any seam or lighting change where block-in meets finished painting; a second moon or ring; characters, text, logos, UI, border; purple or magenta tint; neon, glowing particles, sparkles, magic effects; chains or metal catwalks; thick black outlines on distant things; photorealism, 3D render look, pixel art.
```

### 出图后（我来做）
1. 用天空区域把输出和画布对齐（GPT 常有 1～3% 缩放、平移）。
2. 用 GPT 重画过的真像素区和原图对比，拟合颜色变换，套到新画部分。
3. 真像素部分贴回原图（蒙版按草图外扩 20～30 像素再羽化）。
4. 按 ID 图拆出中景（崖 + 渡槽 + 瀑布）、可玩层（桥面 + 平台）、前景；被挡住的后层用“模糊块 → GPT 补完”的空背景板补。
5. 合成主角、转灰度验收；描平台碰撞。
