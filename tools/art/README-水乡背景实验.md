# 纯代码绘制背景实验（月下水乡）

不用 AI 生图，用 Python（numpy + pycairo + OpenCV）一笔一笔"算"出来的分层视差背景。

| 文件 | 作用 |
|---|---|
| `paint_water_town.py` | 画 15 层：天空/远山/宝塔/孔明灯/雾/白墙黑瓦民居+倒影/月光水路/三孔石拱桥+灯笼/乌篷船/垂柳/背光雾/河堤步道+石灯笼/灯光/萤火/前景剪影。输出 `layers/*.png`（直通透明）+ `layers.json`（视差系数、是否加色）+ `comp.png` 合成图。约 25 秒。 |
| `pixelize_preview.py` | 放角色眯眼测试（`with_char_1280.jpg`、`squint.jpg`）+ 像素版（640×360、40 色、3 倍最近邻放大）。 |
| `remotion_preview/` | 用 Remotion 把分层做成 8 秒视差平移视频（灯光闪烁、雾飘、萤火）。 |

```bash
python3 tools/art/paint_water_town.py /data/bgtest
python3 tools/art/pixelize_preview.py /data/bgtest
# Remotion（沙盒的 TypeScript 7 没有 ts.sys，需要 tsshim 垫一下）
cp /data/bgtest/layers/* tools/art/remotion_preview/public/   # 先建 public/
cd tools/art/remotion_preview && ln -sfn /vercel/sandbox/node_modules node_modules
NODE_OPTIONS="--require $PWD/tsshim.cjs" remotion render src/index.ts Parallax out.mp4 --browser-executable /usr/local/bin/chromium
```

画布 2560×1080，视口 1920；角色站立线 y=862。调色板见 `docs/美术方案-10分.md`。
自评约 6/10：氛围、分层、光影、倒影可用；造型细节、材质笔触、手绘感离商业 10 分还差很远。
