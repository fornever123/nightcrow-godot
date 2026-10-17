# AI 生图提示词包 · 前端美术方向

适用工具：**GPT 生图** 与 **Gemini 生图**。本文件只负责提示词，不负责执行。
状态说明：本文替代 `视觉设计规范.md` 中依赖题材的部分（钟塔 / 鸦巢等主题已作废）。玩法内核未定，本轮只定**不随题材变化**的视觉地基。
提示词以英文为主——两个模型的绘画语料都以英文为主，英文出图质量更稳定。中文只作为意图说明。

---

## 零、先说清一件事：这个角色在画面上的真实约束

> **2026-10-15 修正**：本节原按「角色只有 220 px 高」撰写，该前提**已被实测推翻**。角色源图真实细节约 1000 px，推荐显示尺寸为 **380–430 px**（详见 `角色显示尺寸.md`）。下表已按新尺寸更新。

角色是**黑紫 + 白挑染**，画法是**硬边赛璐璐 + 粗深色描边**，显示高度建议 380–430 px（占屏高 35%–40%）。这推导出四条硬规则，所有提示词都建立在这四条上：

| 约束 | 原因 | 对背景的要求 |
|---|---|---|
| 角色整体偏暗 | 深色衣服 + 黑发 | 背景**不能也太暗**，否则角色融进去 |
| 角色唯一的强色彩是紫 | 头发、护甲、宝石、刀光 | 背景**去紫、降饱和**，把紫留成「只有玩家有」 |
| 角色最亮的是白色挑染与白护甲 | 面积很小 | 背景最亮值不得高于角色的白色，否则亮点被抢 |
| 角色占屏高约 39% | 尺寸已放大 | 背景**可以承载中等细节**——砖缝、雕饰、纹样都撑得住。但背景仍是大面积，整体仍须**大块面可读**，不能碎 |

### 尺寸变化后，提示词里要改的一句

原来因为角色太小，提示词里写了「大块面、无细节、极简」。现在角色占屏 39%，背景可以更精致。把提示词中描述细节密度的句子替换为：

```
Surfaces may carry moderate detail — masonry joints, carved ornament, weathered stains —
as long as every shape still reads as one large simple block when the image is viewed at
1920x1080. Detail must never break the silhouette of the architecture.
```

同时**「中央留空」这一条继续保留**——它不是尺寸问题，是战斗可读性问题。

### 一个必须让你知道的取舍

角色是硬边赛璐璐 + 粗描边。**背景的画法决定了角色素材将来要不要重做**：

- 选 **T1 / T4 / T5**（图形化、有描边）→ 角色素材可以继续用，风格自洽。
- 选 **T2 厚涂电影** → 背景会很漂亮，但角色需要重新按厚涂风格做一遍，否则像两个游戏拼接。角色放大到 400 px 后内部细节更多，兼容性比原来略好，但冲突依然存在。
- 选 **T3 明暗极简** → 角色必须加一圈亮轮廓光（shader 实现）。**尺寸变大后这个方向的相对优势下降**：大面积近黑背景会显得「空」而不是「压抑」，也浪费了角色新获得的细节表现力。

这条不是反对 T2 或 T3，而是提前把成本说清楚。

---

## 一、提示词写法：和 Midjourney 时代完全不同

GPT 与 Gemini 是**指令跟随模型**，理解的是完整句子和明确约束，不是关键词堆叠。写法要整体换掉。

### 1. 不要堆质量标签

`masterpiece, best quality, 8k, ultra detailed, trending on artstation` 这类词在新模型上**没有作用，甚至会让画面变脏**。它们没有信息量。真正有用的信息是：

- 笔触（brushwork / flat fill / hatching）
- 边缘硬度（hard-edged / crisp / feathered）
- 阴影数量（exactly one hard shadow tone / two-tone）
- 材质（stone grain / damp stain / paper texture）

### 2. 用固定顺序写简报

```
① 形式与尺寸   这是什么图，多少比例
② 场景         画的是什么，具体到有几个什么东西
③ 渲染方式     怎么画的 ← 决定画风，最重要的一段
④ 镜头         视角、机位、有没有透视变形
⑤ 光线         光源数量、方向、软硬
⑥ 色彩         明度分组、饱和策略
⑦ 构图留白     哪里必须有东西，哪里必须空
⑧ 排除项       不要什么
```

### 3. 八、排除项必须写，而且写全

不写就一定出现。固定带上：

```
no people, no characters, no creatures, no figures, no silhouettes of people,
no text, no letters, no numbers, no watermark, no signature, no logo,
no UI elements, no frames, no borders, no split panels, no multiple views
```

### 4. 必须显式要求「中央留空」

模型默认会把细节撒满整张图，而战斗画面中央必须干净。每个背景提示词里都要写明中央多少比例是空的。

### 5. 用语言量化明度层次——这是让画面有纵深的诀窍

不要只说「有层次感」。要写成可执行的分组，例如：

```
Three clearly separated depth layers: the nearest layer is the lightest and most detailed,
the middle layer drops in contrast and detail, the furthest layer is the darkest and simplest.
```

### 6. 一致性靠「风格锚图 + 参考图指令」，不靠重复提示词

**这是整套流程里最重要的一条。** 一个游戏要几十张风格一致的图，靠反复改提示词是做不到的。正确做法：

1. 先出 **1 张风格锚图**（定调图）。
2. 之后每一张都把它作为参考图喂进去，写「保持风格完全不变，只换场景」。
3. Gemini 在这方面特别强，可以把上一张直接引用为参考，连续产出同一套风格。

### 7. 迭代用「编辑」，不要重新生成

让模型做定点修改，而不是重新画：

```
只有这些改动，其余一律不动：把左侧三分之一压暗一级；去掉左起第二根柱子；保持中央为空。
```

Gemini 的定点编辑能力很强，改图比重新生成划算得多。

### 8. 先出灰度版，验明度，再上色

专业流程是**先做明度草图**。把灰度版和角色合成看一眼：角色的深色身体在中明度背景上是否读得出来。明度不成立，颜色再好看也白费。

### 9. 一次出 4 个变体，挑一个

不要试图一次调好。两个模型都支持一次多图，出 4 张挑，比反复微调一张快得多。

### 10. 判断标准：缩到 1920×1080 再看

生成图原尺寸好看不代表能用。**必须缩到游戏实际尺寸，和角色合成后再判断。** 细纹样在这个尺寸会消失或变成噪点。

### 11. 尺寸与比例两边都要写

提示词里写出来，同时把工具的尺寸/比例参数也设好。背景统一 2560×1440 生成，实际用 1920×1080，视差层再补到 3840×1080。

### 12. 透明与文字

- **透明背景**：GPT 生图若界面提供「透明背景」选项就选它，可直接得到带 alpha 的 PNG。拿不到透明，就让模型给**纯品红底 #FF00FF**（不要绿底，角色本身有绿边残留历史），再用你工程里已有的抠像工具键出。
- **文字不要指望模型**。中文尤其不稳定。设计稿里可以用文字判断版式，但**正式素材的文字一律程序渲染**。

---

## 二、五个美术方向（本轮要生成的就是这五张）

差异放在**明度结构 + 渲染方式**两个维度上——这两个最能分出胜负。

| 方向 | 明度结构 | 渲染方式 | 代价 |
|---|---|---|---|
| **T1 图形赛璐璐** | 中明度背景 | 平面色块 + 粗描边 | 与角色最搭；形状弱会显廉价 |
| **T2 厚涂电影** | 中明度 + 强体积光 | 数字厚涂，无描边 | 好看，但**角色将来要重做**才对得上 |
| **T3 明暗极简** | 近黑背景 | 极少明度层，光就是内容 | 角色必须加强轮廓光，否则消失 |
| **T4 装饰线条** | 中明度、双色调 | 线条主导、纹样化 | 最有辨识度；纹样要克制否则乱 |
| **T5 明快反差** | 高明度背景 | 海报式平涂 + 硬阴影 | 可爱角色配残酷战斗的反差；离开暗黑气质 |

**注意**：五个方向的场景内容刻意保持一致（夜间石砌大厅 + 柱 + 高窗 + 地面 + 悬浮平台），这样对比的只有画法本身。等选定方向后，再把题材套上去。

---

## 三、背景提示词（5 张，逐条可复制）

### T1 · 图形赛璐璐

```
A side-scrolling action game stage background, painted as flat graphic cel-shaded anime background art.

Scene: a vast stone hall at night — thick square pillars, tall pointed windows with lattice mullions, a wide stone floor slab across the lower third, two floating stone platforms.

Rendering: every architectural edge carries a thick dark outline; surfaces are filled with flat color blocks; each surface has exactly one hard-edged shadow tone. No gradients, no soft airbrushing, no texture painting. Shapes are simplified and geometric — like high-end anime background art painted for television, but with cleaner and bolder silhouettes.

Camera: straight-on side view, eye level, no perspective distortion, the floor line perfectly horizontal.

Lighting: cool moonlight from the upper right produces hard-edged shadow shapes across the pillars and floor. Shadow edges are crisp, never feathered.

Color: the environment is almost monochrome — desaturated slate blue-grey and near-black, mid-value stone floor. Chroma is used sparingly; one distant warm light serves as the single accent.

Composition: the central 60% of the frame is calm and uncluttered — no detail, no props, no decorative pattern there. All interest is pushed to the outer thirds and upper corners.

Depth: three clearly separated depth layers — near-black silhouette pinnacles in the far distance, mid-value architecture in the middle distance, the lit floor and platforms in the foreground. Each layer further back is simpler and lower in contrast.

Format: 16:9 landscape, 2560x1440.

Exclusions: no people, no characters, no creatures, no figures, no text, no letters, no watermark, no logo, no UI elements, no frames, no borders, no split panels, no multiple views.
```

### T2 · 厚涂电影

```
A side-scrolling action game stage background, painted in a cinematic digital painting style.

Scene: the interior of a ruined gothic nave at night — clustered columns receding into darkness, broken tracery windows high on the walls, a broad stone floor with fallen rubble kept to the far edges.

Rendering: digital oil painting with visible brushwork. Soft atmospheric edges in the distance; crisper brush detail only in the foreground. Rich texture — stone grain, damp stains, drifting dust. No hard outlines anywhere.

Camera: side view, slightly low angle.

Lighting: one strong light source from the upper left, with volumetric light shafts between the columns, deep shadow on the right side, and warm bounce light skimming along the floor. Aerial perspective pushes the far columns toward the sky colour.

Color: mostly desaturated — cold blue-grey stone against warm ochre light. Strong contrast between lit and shadow areas.

Composition: large calm negative space across the central 60% of the frame. All visual interest concentrated in the outer thirds and the upper area. Do not scatter small details across the middle.

Depth: clearly readable far, mid and near layers, with progressively reduced contrast and detail toward the back.

Format: 16:9 landscape, 2560x1440.

Exclusions: no people, no characters, no creatures, no figures, no text, no letters, no watermark, no logo, no UI elements, no frames, no borders, no split panels, no multiple views.
```

### T3 · 明暗极简

```
A side-scrolling action game stage background rendered as extreme chiaroscuro.

Scene: an enormous dark interior where almost everything is near-black. Only a few architectural shapes are visible, each picked out by a single hard light: a shaft of pale light falling from a high window onto the floor, a row of faintly glowing lanterns receding into darkness at the far right, a thin cold line of light tracing the outline of a distant arch.

Rendering: very few values — near-black, one deep mid grey, one bright light shape. Large flat regions of darkness carry no texture detail at all. The edges of lit shapes are crisp.

Camera: side view, eye level.

Lighting: two or three strong local light sources, nothing else. The light shapes themselves are the main visual content; everything unlit stays solid dark.

Color: essentially monochrome with a single hue shift — cold blue in the shadows, pale warm gold in the light.

Composition: the central band of the frame is a calm dark expanse with nothing in it. Light shapes sit in the left and right thirds.

Format: 16:9 landscape, 2560x1440.

Exclusions: no people, no characters, no creatures, no figures, no text, no letters, no watermark, no logo, no UI elements, no frames, no borders, no split panels, no multiple views.
```

### T4 · 装饰线条

```
A side-scrolling action game stage background drawn in an ornamental linework style.

Scene: an immense vaulted interior whose architecture is covered in fine decorative tracery — interlaced geometric patterns, feather and quill motifs, repeating rosettes carved into every surface.

Rendering: drawing-first. Strong contour lines carry the entire structure; flat colour washes sit beneath the lines. The result should read closer to a hand-illustrated engraving or a tapestry design than to a painted scene. Hatching is used for shadow.

Camera: side view, eye level, flat and graphic, no perspective drama.

Lighting: light selects which panels of pattern are bright and which fall into a two-tone shadow. No soft gradients.

Color: a restrained two-tone palette — deep ink blue-black for lines and shadow, one pale cool tone for light, plus a single accent hue used only on a few small areas.

Composition: the central band is deliberately plain. The ornate pattern is arranged as a frame around the outer edges so that the middle stays empty and calm.

Format: 16:9 landscape, 2560x1440.

Exclusions: no people, no characters, no creatures, no figures, no text, no letters, no watermark, no logo, no UI elements, no frames, no borders, no split panels, no multiple views.
```

### T5 · 明快反差

```
A side-scrolling action game stage background in a bright, punchy, stylized comic-art style.

Scene: an ornate courtyard in broad daylight — pale stone balustrades, hanging banners, a wide sunlit terrace, a fountain at the far right, distant spires against a vivid blue sky with bold stylized clouds.

Rendering: strong graphic shapes, confident dark contour lines, flat colour with exactly one hard secondary tone per surface, minimal gradients. Bold and poster-like. Colours are saturated but values are grouped so that large simple shapes dominate.

Camera: side view, slightly low angle.

Lighting: bright hard sunlight from the upper right producing clean, hard-edged cast shadows. High key overall.

Color: vivid sky blue, warm cream stone, and strong chromatic accents used in only a few small places.

Composition: the central 60% of the frame is open terrace and sky — clean, empty, no props. Interest sits at the left and right thirds.

Format: 16:9 landscape, 2560x1440.

Exclusions: no people, no characters, no creatures, no figures, no text, no letters, no watermark, no logo, no UI elements, no frames, no borders, no split panels, no multiple views.
```

---

## 四、灰度验明度（重要的辅助提示词）

拿到上色版之后，先别急着用。追加这条，让模型出灰度版，检查角色的深色身体能不能读出来。

```
Render this exact same image again as a monochrome grayscale value study — no colour at all, identical composition and shapes. Make the value structure extremely clear: the foreground floor and platforms are the lightest large shapes, the middle distance sits around mid grey, and the far layer is the darkest. Keep the whole middle of the frame as one calm unbroken value.
```

**判断方法**：把灰度背景和角色帧合成，缩到 1920×1080。如果角色的轮廓要靠猜，这个方向就淘汰。

---

## 五、UI 提示词（模板 + 三种填充）

UI 要在选定的背景方向之后定，但要和背景同源。下面先给一个**模板**，方括号处替换。

```
A game HUD design sheet on a plain background — a flat 2D UI design mock, shown straight-on. This is not a screenshot of a game and must not contain any scene.

Arrange one coherent HUD kit with generous spacing:
- top-left: a player status cluster — a portrait frame with a sharply cut corner, a thin horizontal health bar beneath it, and a circular gauge below that
- top-right: a wide boss health bar
- top-centre: a short row of small progress pips
- bottom-left: one large numeral placeholder and one small label placeholder

Style: [风格块]

Rules: all shapes must share ONE shape language — choose a single corner treatment and repeat it on every panel. Thin, consistent stroke weight. Flat fills only. No photographs, no 3D rendering, no bevels, no drop shadows, no glossy highlights.

Palette: [色板块]

Leave the middle of the image completely empty.

Format: 1:1 square, 2048x2048.

Exclusions: no people, no characters, no screenshots, no scene background, no letters or words (use abstract placeholder blocks instead), no watermark, no logo.
```

### 风格块与色板块的三种填充

**配 T1 图形赛璐璐**
```
Style block: flat colour panels with thick dark outlines, hard-edged, sharply cut corners at 45 degrees, geometric and terse.
Palette block: near-black panel fill, one deep desaturated blue-grey, and a single pale lilac accent line.
```

**配 T3 明暗极简**
```
Style block: minimal thin-line outlines on near-black, generous empty space, only light shapes and thin strokes — almost no filled panels at all.
Palette block: near-black background, one pale warm gold for light elements, one cold blue for structure.
```

**配 T5 明快反差**
```
Style block: bold poster-like panels, confident thick dark outlines, hard-edged shadows, playful chunky proportions.
Palette block: warm cream panel fills, vivid sky blue accents, and one strong warm highlight colour.
```

---

## 六、一致性提示词（第 2 批及以后必用）

选定方向后，用它当**风格锚图**，之后每张新场景都这样写。这比重新描述风格可靠得多。

```
Use the attached image as the visual style reference.

Keep its rendering style, line weight, palette, shadow treatment, value structure and lighting logic EXACTLY the same. Do not change the style in any way.

Now render a different scene in that identical style: [新场景描述].

Same camera setup, same level of detail, same amount of empty space in the centre of the frame.

Format: 16:9 landscape, 2560x1440.

Exclusions: no people, no characters, no creatures, no figures, no text, no letters, no watermark, no logo, no UI elements, no frames, no borders.
```

### 定点改图（Gemini 尤其擅长）

```
Using the attached image, make only these changes and change nothing else:
- [改动一]
- [改动二]
Do not alter the style, palette, lighting direction or composition otherwise.
```

---

## 七、素材类提示词（后面会用到）

### 透明素材（机关 / 平台块 / 道具）

```
A single game asset on a fully transparent background: [物件描述].

Centred, straight side view, no perspective twist. Cel-shaded with a thick dark outline and exactly one hard shadow tone. Readable as a silhouette at small size.

Format: 1:1 square, 1024x1024, PNG with alpha.

Exclusions: no background, no ground shadow, no text, no character, no extra objects, no watermark.
```

若工具不给透明背景，把首句换成：

```
A single game asset on a flat solid magenta background (#FF00FF), chroma-key ready: [物件描述].
```

### 发光特效（命中 / 撞击 / 弹刀）

**必须要求纯黑底**——不用抠图，游戏里用叠加模式直接叠上去。

```
A single 2D hit effect sprite on a pure black background: [效果描述].

Flat graphic style with crisp hard edges, a bright core and a thin outer edge line — no soft airbrush glow, no blur, no lens flare.

Format: 1:1 square, 1024x1024.

Exclusions: no background scenery, no characters, no text, no watermark, no border.
```

### 羽毛粒子

```
A single bird feather on a pure black background, side view, slightly curved, seen flat.

Flat graphic cel-shaded style, thick dark outline, one hard shadow tone, dark violet with a pale edge highlight.

Format: square, 512x512. Exclusions: no text, no watermark, no other objects.
```

---

## 八、拿到图之后要做的处理（不是生成，但必须做）

1. **缩到 1920×1080 再判断**，不要在原尺寸下评价。
2. **和角色帧合成**，做灰度对比，检查角色是否读得出来。
3. **分层做视差**：先出一张完整场景，再用工程里已有的 SAM2 / RVM 按深度切成远、中、近三层。这比分别生成三层再拼可靠。
4. **亮度校验**：中景层的平均明度不得高于站立层。高于就压暗。
5. **色相校验**：背景中不得出现饱和紫。出现就降饱和或转色相。

---

## 九、本轮需要你做的

1. 把第三节的 5 条背景提示词分别丢给 GPT 和 Gemini，**每条出 4 张**。
2. 挑出你觉得最像「一个真正的游戏」的方向，告诉我编号（可以选两个）。
3. 我再给选定方向做灰度校验、出第 2 批场景、UI 套件和特效。
4. 如果你有已经喜欢的参考游戏或画师，告诉我，我可以把方向再收窄一轮。
