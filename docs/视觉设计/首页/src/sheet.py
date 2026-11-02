# 把每个方向的 f0 定稿 + f1~f3 进场关键帧拼成一张：上面大图，下面三格小图 + 说明。候选名对比图直接复制。
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(sys.argv[1])
frames = root / "_frames"
font = ImageFont.truetype("C:/Windows/Fonts/NotoSerifSC-VF.ttf", 20)
names = {"A": "A_钟停五点五十九_悬雨", "B": "B_一刀_时间重新流动", "C": "C_睁眼"}
caps = {
    "A": ["① 黑屏，一声钟，朱红钟面亮起", "② 雨和街淡入，塔顶雨珠悬停，字标浮出", "③ 按开始：一刀斩断光弦，雨砸落、黑羽散"],
    "B": ["① 昼光：整屏暖白，雨停成珠，字完整", "② 一刀横斩，冷紫刀光", "③ 光断开、字错开，夜落下，雨重新落"],
    "C": ["① 黑屏，只有雨，一点紫光", "② 眼睛从一条缝横向睁开", "③ 竖排字标从上往下写出"],
}
for d, name in names.items():
    big = Image.open(frames / f"{d}-f0.png").convert("RGB")
    tw, th = 416, 234
    sheet = Image.new("RGB", (1280, 720 + 16 + th + 44), (10, 11, 16))
    sheet.paste(big, (0, 0))
    dr = ImageDraw.Draw(sheet)
    for i in range(3):
        t = Image.open(frames / f"{d}-f{i+1}.png").convert("RGB").resize((tw, th), Image.LANCZOS)
        x = i * (tw + 16)
        sheet.paste(t, (x, 736))
        dr.text((x + 4, 736 + th + 8), caps[d][i], font=font, fill=(170, 178, 194))
    sheet.save(root / f"{name}.png")
shutil.copy(frames / "N-f0.png", root / "N_候选游戏名字标.png")
print("ok")
