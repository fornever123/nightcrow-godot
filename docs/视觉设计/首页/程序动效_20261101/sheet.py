# 把 frames/ 里的关键帧拼成每个方向一张总览图（大图 = 菜单打开的定稿画面，下面四格 = 进场 / 开始的关键帧）。
from PIL import Image, ImageDraw, ImageFont
import os

D = os.path.dirname(os.path.abspath(__file__))
FONT = r'C:/Users/MECHREVO/AppData/Local/Microsoft/Windows/Fonts/NotoSansSC-Regular.ttf'
SPEC = {
    '1': ('方向一_悬雨钟楼', [('0_intro1', '① 黑场淡入雨街，一缕昼光垂下'), ('1_intro2', '② 光绕钟一圈半，雨停成珠，字浮出'),
                          ('4_go', '③ 开始：一刀斩断光弦'), ('5_go2', '④ 雨砸下、黑羽炸开、分针跳到 6:00')]),
    '2': ('方向二_光弦断幕', [('0_intro1', '① 黑里昼光丝弦垂下，雨冻成珠'), ('1_intro2', '② 字由光写出'),
                          ('2_cut', '③ 冷紫一刀：下半截碎成黑羽，雨开始落'), ('4_go', '④ 开始：再一刀斩尽上面的光')]),
    '3': ('方向三_五点五十九', [('0_intro1', '① 朱红钟面亮起，秒针卡在 59 发抖'), ('1_intro2', '② 光弦缠上钟顶，旁边的雨停住'),
                           ('4_go', '③ 开始：斩断光弦，钟面一亮'), ('5_go2', '④ 分针跳到 VI:00，黑羽散，雨落')]),
}
for k, (title, keys) in SPEC.items():
    big = Image.open(f'{D}/frames/d{k}_3_menu.png').convert('RGB').resize((1280, 720))
    sh = Image.new('RGB', (1280, 1004), (10, 11, 16))
    sh.paste(big, (0, 0))
    dr = ImageDraw.Draw(sh)
    dr.text((16, 730), title.replace('_', ' · ') + '（定稿画面：菜单打开）', font=ImageFont.truetype(FONT, 28), fill=(225, 225, 232))
    for i, (f, cap) in enumerate(keys):
        sh.paste(Image.open(f'{D}/frames/d{k}_{f}.png').convert('RGB').resize((320, 180)), (i * 320, 780))
        dr.text((i * 320 + 8, 968), cap, font=ImageFont.truetype(FONT, 15), fill=(190, 194, 206))
    sh.save(f'{D}/{title}.png')
    print(title)
