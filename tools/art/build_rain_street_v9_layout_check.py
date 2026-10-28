import json, re
ART = r"E:\00game\nightcrow-godot\tools\art"
SC = r"C:\Users\MECHREVO\AppData\Local\Temp\claude\E--00game\f7a4dfef-28e8-46af-b106-fb15126ee767\scratchpad"
s = open(ART + r"\make_rain_street_value_v8.py", encoding="utf-8").read()
a = s.index("# ---- B1 窄高砖楼")
b = s.index("# 广场边的石拱廊桥")
s = s[:a] + open(SC + r"\v9_block.py", encoding="utf-8").read() + "\n" + s[b:]


def rep(old, new):
    global s
    assert old in s, "MISSING: " + old[:90]
    s = s.replace(old, new, 1)


s = s.replace('"""雨夜河岸街：明暗草图 v8（结构参考图）。', '"""雨夜河岸街：明暗草图 v9（结构参考图）。\n\n'
              'v9：每栋楼一个身份（河岸货栈 / 行会会馆 / 商住楼 / 小酒馆）；竖向壁柱线、屋顶更陡更高；阳台按楼错开高度、栏杆分样式\n'
              '（货栈铸铁廊 / 会馆实心石矮墙 / 商住楼铸铁花栏 / 酒馆只有石檐）；钟楼一层不再整片染红，钟面中心亮边缘暗；\n'
              '其他暖灯偏黄降饱和；街面后墙底部一条冷蓝湿反光带；中景屋顶烟囱层；云缝月光；系船环只留一个；酒馆门边壁挂灯。', 1)

# 暖色：偏黄、降饱和，和钟楼朱红拉开
rep("GLASS, SHEEN, WARM = (12, 15, 22), (58, 70, 92), (236, 170, 90)", "GLASS, SHEEN, WARM = (12, 15, 22), (58, 70, 92), (232, 200, 132)")

# 中景：近景和远景之间一层雨雾半遮的屋顶和烟囱；云缝里一道很淡的月光
rep("m, d = mask(); d.rectangle([0, Y(240), W, Y(620)], fill=150); paste(solid((98, 112, 136)), m, 45)",
    '''m, d = mask(); d.rectangle([0, Y(240), W, Y(620)], fill=150); paste(solid((98, 112, 136)), m, 45)
m, d = mask()                                                    # 中景：雨雾半遮的屋顶和烟囱（比远景深、比近景浅）
mid = [(-2450, 360)]
for i, mx in enumerate(range(-2450, 300, 110)):
    top = 330 - (40 if i % 3 == 0 else 0) - (20 if i % 5 == 1 else 0)
    mid += [(mx, top), (mx + 55, top - 50), (mx + 110, top)]
mid += [(300, 700), (-2450, 700)]
d.polygon(P(mid), fill=255)
for cx in range(-2400, 260, 230):
    d.rectangle([X(cx), Y(230), X(cx + 24), Y(320)], fill=255)
paste(solid((64, 74, 96)), m, 2.0)
m, d = mask(); d.rectangle([0, Y(330), W, Y(620)], fill=120); paste(solid((84, 96, 120)), m, 40)
m, d = mask(); d.polygon(P([(-1290, -540), (-1210, -540), (-700, 260), (-980, 260)]), fill=40); paste(solid((150, 164, 190)), m, 30)''')

# 阳台：按楼分栏杆样式（货栈铸铁廊 / 会馆实心石矮墙 / 商住楼铸铁花栏 / 酒馆只有石檐 / 钟楼石栏）
rep('''        sd2.rectangle([X(x0), Y(y - 40), X(x1), Y(y - 32)], fill=255)                     # 低石栏的扶手
        for bx in range(int(x0) + 8, int(x1) - 4, 38):                                   # 稀疏的栏杆柱
            sd2.rectangle([X(bx), Y(y - 32), X(bx + 9), Y(y)], fill=255)
        paste(vgrad((86, 92, 108), (44, 48, 60), y - 40, y + 64), st, 0.4)''', '''        style = "iron" if x1 <= -1985 else "solid" if x1 <= -1560 else "floral" if x1 <= -900 else "ledge" if x1 <= -620 else "stone"
        if style == "stone":                                                             # 钟楼：稀疏石栏
            sd2.rectangle([X(x0), Y(y - 40), X(x1), Y(y - 32)], fill=255)
            for bx in range(int(x0) + 8, int(x1) - 4, 38):
                sd2.rectangle([X(bx), Y(y - 32), X(bx + 9), Y(y)], fill=255)
        elif style == "solid":                                                           # 会馆：实心石矮墙，上面一排浅浮雕尖拱
            sd2.rectangle([X(x0), Y(y - 34), X(x1), Y(y)], fill=255)
        paste(vgrad((86, 92, 108), (44, 48, 60), y - 40, y + 64), st, 0.4)
        if style == "solid":
            bl, bd = mask()
            for bx in range(int(x0) + 10, int(x1) - 20, 34):
                bd.polygon(P(arch_pts(bx + 12, y - 6, 18, 22)[0]), fill=255)
            paste(solid((52, 56, 70)), bl, 0.4)
        if style in ("iron", "floral"):                                                  # 铸铁栏杆：细、稀、低
            ir, idr = mask()
            idr.line([(X(x0), Y(y - 38)), (X(x1), Y(y - 38))], fill=255, width=2)
            step = 30 if style == "iron" else 44
            for bx in range(int(x0) + 6, int(x1), step):
                idr.line([(X(bx), Y(y - 38)), (X(bx), Y(y))], fill=255, width=2)
                if style == "floral":
                    idr.ellipse([X(bx + 12), Y(y - 30), X(bx + 30), Y(y - 12)], outline=255, width=2)
            paste(solid(IRON), ir, 0.3)''')

# 路灯：暖光偏黄；光晕降饱和
rep("paste(solid((255, 204, 128)), m, 0.5)", "paste(solid((248, 224, 168)), m, 0.5)")
rep("    hd.ellipse([X(x - 200), Y(y - 520), X(x + 200), Y(y - 120)], fill=(84, 54, 24))", "    hd.ellipse([X(x - 200), Y(y - 520), X(x + 200), Y(y - 120)], fill=(70, 60, 40))")
rep("    hd.ellipse([X(x - 180), Y(y - 8), X(x + 180), Y(y + 26)], fill=(104, 66, 28))", "    hd.ellipse([X(x - 180), Y(y - 8), X(x + 180), Y(y + 26)], fill=(86, 72, 46))")
rep('''for cx, cy in ((-2300, -65), (-1170, 195), (-760, 220)):
    hd.ellipse([X(cx - 110), Y(cy - 150), X(cx + 110), Y(cy + 150)], fill=(56, 34, 14))''', '''for cx, cy in ((-2190, -70), (-760, 220), (-1350, 470), (-990, 470), (-800, 500)):
    hd.ellipse([X(cx - 110), Y(cy - 150), X(cx + 110), Y(cy + 150)], fill=(46, 38, 22))''')
# 钟楼一层不再整片染红：去掉塔脚的大红光晕，只留玫瑰窗周围
rep("hd.ellipse([X(-420), Y(380), X(260), Y(640)], fill=(40, 12, 4))   # 红光渗进钟楼脚下的雾和湿地面\n", "")
# 街面后墙底部：冷蓝湿反光带（给黑衣角色衬底）
rep("img = np.clip(img + np.asarray(halo.filter(ImageFilter.GaussianBlur(40)), np.float32), 0, 255)",
    '''img = np.clip(img + np.asarray(halo.filter(ImageFilter.GaussianBlur(40)), np.float32), 0, 255)
cool = Image.new("RGB", (W, H)); cd = ImageDraw.Draw(cool)
for i in range(6):
    cd.rectangle([0, Y(530 + i * 8), W, Y(FLOOR)], fill=(4 + i * 2, 7 + i * 3, 11 + i * 4))
img = np.clip(img + np.asarray(cool.filter(ImageFilter.GaussianBlur(6)), np.float32), 0, 255)''')

# 钟面：中心亮、边缘暗（玻璃被里面的光透亮）
rep("m, d = mask(); d.ellipse([X(-120), Y(-570), X(120), Y(-330)], fill=255); paste(solid((210, 72, 38)), m)",
    '''m, d = mask(); d.ellipse([X(-120), Y(-570), X(120), Y(-330)], fill=255); paste(solid((150, 44, 26)), m)
for r_, col in ((100, (178, 56, 30)), (78, (206, 72, 36)), (52, (232, 104, 52)), (26, (250, 150, 90))):
    m, d = mask(); d.ellipse([X(-r_), Y(-450 - r_), X(r_), Y(-450 + r_)], fill=255); paste(solid(col), m, 6)''')

# 狮头系船环只留一个
rep("for lx in (-2050, -1300, -520):                                  # 狮头系船环", "for lx in (-1300,):                                               # 狮头系船环（只留一个）")
open(ART + r"\make_rain_street_value_v9.py", "w", encoding="utf-8").write(s)

# ---- 布局：阳台按楼错开高度；货栈三层装卸台挪到中轴；酒馆门边壁挂灯；路灯挪开大车门
LP = r"E:\00game\nightcrow-godot\assets\data\rain_street_layout.json"
L = json.load(open(LP, encoding="utf-8"))
sec = L["sections"][0]
remap = {(-2390, -1990, 300): [-2390, -1990, 310], (-2380, -2220, 20): [-2270, -2110, 30],
         (-1965, -1575, 300): [-1965, -1575, 285], (-1610, -1430, 300): [-1610, -1430, 285],
         (-1430, -920, 300): [-1430, -920, 305]}
for p in sec["platforms"]:
    k = tuple(p[:3])
    if k in remap:
        p[:3] = remap[k]
for l in sec["lamps"]:
    if l[2] == "street" and l[0] == -2190:
        l[0] = -2000
    if l[2] == "wall" and l[:2] == [-1500, 300]:
        l[1] = 285
    if l[2] == "wall" and l[:2] == [-1000, 300]:
        l[1] = 305
if [-640, 550, "wall"] not in sec["lamps"]:
    sec["lamps"].append([-640, 550, "wall"])
for sp in sec["spawns"]:
    if sp == [-1300, 300]:
        sp[1] = 305
surf = [(a, b, y) for a, b, y, _ in sec["platforms"]] + [(a, b, y) for a, b, y, _ in sec["blocks"]]
bad = [(A, B) for A in surf for B in surf if A is not B and A[1] > B[0] and A[0] < B[1] and 0 < B[2] - A[2] < 188]
unreach = [(a, b, y) for a, b, y, k in sec["platforms"] if not any(
    (B[2] > y and B[2] - y <= 300 and max(0, max(a, B[0]) - min(b, B[1])) <= 380) or
    (abs(B[2] - y) <= 60 and (B[0], B[1], B[2]) != (a, b, y) and max(0, max(a, B[0]) - min(b, B[1])) <= 450)
    for B in surf + [(-1e9, 1e9, 580)])]
print("headroom:", bad or "ok", " reach:", unreach or "ok")
js = json.dumps(L, ensure_ascii=False, indent=2)
js = re.sub(r'\[\s+([^\[\]{}]*?)\s+\]', lambda m: '[' + re.sub(r'\s*\n\s*', ' ', m.group(1)) + ']', js)
open(LP, "w", encoding="utf-8").write(js + "\n")
print("built v9")
