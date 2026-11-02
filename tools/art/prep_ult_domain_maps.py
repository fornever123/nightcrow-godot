"""大招开场 v11（通用领域展开）的试验底图（10-31）：用户要开场不运镜、换什么地图都差不多是那个效果。
效果只需要两样东西：当前游戏画面 + 她脚下的位置（地面线）。线稿痕迹用 Sobel 现算（游戏里换成 shader 实时算），
这里先给三张不同的地图各算一份，放进 Remotion public/domain/：
  rain    雨夜河岸街（开场 v10 用的那一帧 + 她的单独图层）
  night   云桥夜景样机（图里本来就有她的几个站位，选地面上那个，把她的单独图层盖上去）
  day     云桥白天样机（同上）
只读原图，不改原图。
10-31 补（开场 v12 = v10 镜头升起版做成通用）：每张图再切出两块 3D 用的贴图，只靠地面线 F = 脚下 y - 10：
  {map}_floor.png / _floor_edges.png   F 往下 BAND 行（游戏里看得见的那一窄条地面）竖着拉成 FLOOR_D 深的躺平地面，
                                       和 v10 的 street.png 一个做法（竖向拉长 + 竖向糊一点，像湿地面的倒影）
  {map}_face.png / _face_edges.png     F+BAND 往下到画面底：地面边沿往下折的立面（河岸石墙、桥栏、桥拱……）
"""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = r'E:/00game'
OUT = ROOT + '/ult-slash-remotion/public/domain/'
os.makedirs(OUT, exist_ok=True)
HER = Image.open(ROOT + '/ult-slash-remotion/public/opening/her.png').convert('RGBA')
HER = HER.crop(HER.getbbox())  # 170×152，脚在底边
CC = ROOT + '/nightcrow-godot/docs/视觉设计/layers/cloud_causeway/'

MAPS = {
    # 名字: (画面, 她脚下 (x, y), 她的高度（None = 原图里已经有单独图层）)
    'rain': (ROOT + '/ult-slash-remotion/public/opening/bg.png', (500, 582), None),
    'night': (CC + 'mock_night_ingame.png', (640, 580), 104),
    'day': (CC + 'mock_full_ingame.png', (600, 582), 104),
}


def edges(img):
    g = np.asarray(img.convert('L').filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32)
    gx = np.zeros_like(g); gy = np.zeros_like(g)
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]
    gy[1:-1, :] = g[2:, :] - g[:-2, :]
    m = np.hypot(gx, gy)
    m = np.clip((m - 10) / 40, 0, 1) ** 0.8
    a = (m * 255).astype(np.uint8)
    rgba = np.zeros(g.shape + (4,), np.uint8)
    rgba[..., :3] = (238, 240, 255)
    rgba[..., 3] = a
    return Image.fromarray(rgba)


BAND = 16
FLOOR_D = 170


def floor_tex(bg, F):
    strip = bg.crop((0, F, 1280, F + BAND)).resize((1280, FLOOR_D), Image.BICUBIC)
    return strip.filter(ImageFilter.GaussianBlur(1.2))


for name, (path, (fx, fy), her_h) in MAPS.items():
    bg = Image.open(path).convert('RGB').resize((1280, 720))
    bg.save(OUT + f'{name}_bg.png')
    edges(bg).save(OUT + f'{name}_edges.png')
    F = fy - 10
    fl = floor_tex(bg, F)
    fl.save(OUT + f'{name}_floor.png')
    edges(fl).save(OUT + f'{name}_floor_edges.png')
    face = bg.crop((0, F + BAND, 1280, 720))
    face.save(OUT + f'{name}_face.png')
    edges(face).save(OUT + f'{name}_face_edges.png')
    if her_h is None:
        Image.open(ROOT + '/ult-slash-remotion/public/opening/her.png').save(OUT + f'{name}_her.png')
    else:
        k = her_h / HER.height
        h = HER.resize((round(HER.width * k), her_h), Image.LANCZOS)
        layer = Image.new('RGBA', (1280, 720))
        layer.alpha_composite(h, (round(fx - h.width * 0.5), fy - h.height))
        layer.save(OUT + f'{name}_her.png')
    print(name, 'ok')
