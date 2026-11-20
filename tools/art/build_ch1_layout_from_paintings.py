#!/usr/bin/env python3
"""
从第一章「影街与司辰母钟楼」24 张商业成图的像素坐标 (px_x, px_y) 1:1 精确生成：
  1. assets/image/rain_street/ch1_shadow_street/manifest.json（校准每张成图的 ground_px）
  2. assets/data/ch1_shadow_street_layout.json（全部台阶斜坡 slopes、可跳平台 platforms、真实灯位 lamps、出生点 spawns，零空气墙 blocks）

坐标映射与 scripts/night/street_layered.gd::_draw_ch1_tile() 严格同构：
  k       = (x1 - x0) / width_px
  world_x = x0 + px_x * k
  world_y = FLOOR + (px_y - ground_px) * k   (FLOOR = 580.0)
"""

from __future__ import annotations
import json
import os
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "assets/image/rain_street/ch1_shadow_street/manifest.json"
LAYOUT_PATH = ROOT / "assets/data/ch1_shadow_street_layout.json"

FLOOR = 580.0
FIRST_X = 4400.0
SPACING = 6400.0

# 24 张成图的逐像素实测地形几何（全部在原图 1672x1056 或 1672x1236 像素空间标定）
# slopes_px:    [px_x0, px_y0, px_x1, px_y1, style, solid_bool]
# platforms_px: [px_x0, px_x1, px_y, style]
# lamps_px:     [px_x, px_y, kind("wall"|"street"), rise_px]
# spawns_px:    [px_x, px_y]  （竞技场刷怪落脚点，严格落在地面或平台上）
TILE_SPECS: dict[str, dict] = {
    # ---------------- 1-1A / 1-1B 第 1 处封印（接在 11-12 起点入口街门洞 x≈2038 右侧） ----------------
    "s1_1a_left": {
        "ground_px": 816.0,
        "slopes_px": [
            # 左侧八角书报亭石基座（从门洞羽化右缘 px_x=76 起抬升 21px，门洞内保持平整 580）
            [76, 816, 110, 795, "steps", True],
            [110, 795, 310, 795, "steps", True],
            [310, 795, 362, 816, "steps", True],
            # 右侧门廊三折青石台阶（平滑抬升后回落接缝，绝不卡脚）
            [1520, 816, 1605, 786, "steps", True],
            [1605, 786, 1650, 786, "steps", True],
            [1650, 786, 1672, 816, "steps", True],
        ],
        "platforms_px": [
            [12, 322, 446, "roof"],       # 书报亭铜檐顶
            [342, 798, 566, "plank"],     # 左铺布雨棚
            [996, 1380, 566, "plank"],    # 右裁缝铺布雨棚
            [336, 794, 442, "slab"],      # 左二楼铁栏石阳台
            [996, 1284, 442, "slab"],     # 右二楼铁栏石阳台
        ],
        "lamps_px": [
            [282, 540, "wall", 0],
            [890, 565, "wall", 0],
            [1558, 816, "street", 292],
        ],
        "spawns_px": [[620, 816], [1180, 816], [560, 442]],
    },
    "s1_1a_center": {
        "ground_px": 812.0,
        "slopes_px": [
            # 右侧拱门五级青石台阶：踏上石阶 -> 拱门石坪 -> 右侧顺阶而下
            [1162, 812, 1258, 760, "steps", True],
            [1258, 760, 1552, 760, "steps", True],
            [1552, 760, 1642, 812, "steps", True],
        ],
        "platforms_px": [
            [326, 446, 696, "plank"],     # 黑漆空马车驭手踏座
            [196, 406, 602, "plank"],     # 黑漆空马车顶棚
            [64, 404, 472, "slab"],       # 二楼华尔兹暖窗铁艺阳台底面
            [782, 996, 530, "roof"],      # 5:59 街心八角钟亭顶檐
            [1120, 1652, 458, "slab"],    # 右侧石拱门上方石栏露台踏面
        ],
        "lamps_px": [
            [466, 575, "wall", 0],
            [255, 400, "wall", 0],
        ],
        "spawns_px": [[620, 812], [1390, 760], [1360, 428]],
    },
    "s1_1a_right": {
        "ground_px": 824.0,
        "slopes_px": [
            # 左侧停摆茶座五级石阶外廊（茶桌石廊高 52px，左右顺滑上下阶）
            [18, 824, 112, 772, "steps", True],
            [112, 772, 734, 772, "steps", True],
            [734, 772, 836, 824, "steps", True],
        ],
        "platforms_px": [
            [1055, 1180, 656, "slab"],    # 5:59 里程石碑墩顶（单向可跳不挡平跑）
            [842, 958, 608, "slab"],      # 中段石壁挑檐踏脚石
            [1196, 1300, 608, "slab"],    # 拱门西侧壁龛挑檐
            [22, 820, 468, "slab"],       # 茶座二楼长石栏露台踏面
            [1140, 1650, 468, "slab"],    # 右侧拱门楼二层挑檐廊
        ],
        "lamps_px": [
            [745, 598, "wall", 0],
            [385, 292, "wall", 0],
        ],
        "spawns_px": [[420, 772], [1360, 824], [420, 468]],
    },
    "s1_1b_left": {
        "ground_px": 812.0,
        "slopes_px": [
            # 左侧候车高月台（门洞内 px_x<=76 保持平整 580，走出门洞即顺滑踏上高月台 px_y=780）
            [76, 812, 128, 780, "steps", True],
            [128, 780, 755, 780, "steps", True],
            [755, 780, 815, 812, "steps", True],
        ],
        "platforms_px": [
            [320, 624, 694, "plank"],     # 候车木长椅与皮箱堆踏台
            [296, 928, 426, "roof"],      # 5:59 候车铁艺雨棚顶
            [16, 296, 392, "slab"],       # 左侧站房石栏屋檐
            [976, 1668, 468, "plank"],    # 停摆老电车首节车顶
            [896, 1668, 294, "plank"],    # 电车架空受电弓铸铁龙门架踏面
        ],
        "lamps_px": [
            [422, 558, "wall", 0],
            [968, 690, "wall", 0],
            [1320, 560, "wall", 0],
        ],
        "spawns_px": [[520, 780], [1260, 812], [1300, 468]],
    },
    "s1_1b_right": {
        "ground_px": 812.0,
        "slopes_px": [
            # 右侧东天桥八级青石台阶（单向可踏阶而上，同时不挡地面冲刺）
            [1385, 812, 1595, 692, "steps", False],
            [1595, 692, 1666, 692, "steps", False],
        ],
        "platforms_px": [
            [6, 584, 548, "plank"],       # 老电车第二节车厢顶
            [6, 790, 488, "roof"],        # 站台延伸铁艺雨棚
            [786, 1424, 488, "plank"],    # 跨街木构天桥走廊桥面
            [796, 1414, 278, "roof"],     # 跨街天桥石板坡屋脊
        ],
        "lamps_px": [
            [260, 625, "wall", 0],
            [1428, 632, "wall", 0],
        ],
        "spawns_px": [[420, 812], [1080, 812], [1100, 488]],
    },

    # ---------------- J1 街口高低分流岔路 ----------------
    "j_fork_center": {
        "ground_px": 812.0,
        "slopes_px": [
            # 左侧大型折返石阶（从街面 px_x=615 一路沿画中石阶拾级登顶至 px_y=562 平台）
            [8, 562, 156, 562, "steps", False],
            [156, 562, 616, 812, "steps", False],
        ],
        "platforms_px": [
            [16, 224, 368, "slab"],       # 石阶顶端三楼高台
            [236, 424, 458, "slab"],      # 石阶中段侧翼石阳台
            [696, 996, 488, "slab"],      # 街心挂钟楼二层铁栏阳台
            [1006, 1544, 395, "slab"],    # 右侧过街石拱门顶胸墙步道
        ],
        "lamps_px": [
            [842, 668, "wall", 0],
            [1365, 705, "wall", 0],
        ],
        "spawns_px": [],
    },

    # ---------------- 1-2A 飞鸦玻璃花房顶 ----------------
    "s1_2a_left": {
        "ground_px": 804.0,
        "slopes_px": [],
        "platforms_px": [
            [12, 304, 492, "slab"],       # 西侧石砌屋顶露台
            [310, 686, 528, "plank"],     # 铸铁天桥栏杆步道
            [706, 1020, 505, "roof"],     # 八角发光玻璃鸦笼花房腰檐
            [1210, 1650, 520, "slab"],    # 东侧老虎窗石板挑檐
        ],
        "lamps_px": [
            [345, 660, "wall", 0],
            [860, 635, "wall", 0],
        ],
        "spawns_px": [[520, 804], [860, 505], [1380, 804]],
    },
    "s1_2a_center": {
        "ground_px": 758.0,
        "slopes_px": [
            # 中央双烟囱石砌屋脊微阶
            [734, 758, 780, 726, "steps", True],
            [780, 726, 930, 726, "steps", True],
            [930, 726, 976, 758, "steps", True],
        ],
        "platforms_px": [
            [6, 668, 482, "plank"],       # 左翼发光玻璃花房铁艺外廊（严丝合缝贴齐铁栏底座）
            [1108, 1666, 482, "plank"],   # 右翼发光玻璃花房铁艺外廊（中间留出高空下砸断口）
            [42, 580, 228, "roof"],       # 左玻璃穹顶冠梁
            [1220, 1658, 265, "roof"],    # 右玻璃穹顶冠梁
        ],
        "lamps_px": [
            [340, 415, "wall", 0],
            [1420, 425, "wall", 0],
        ],
        "spawns_px": [[360, 482], [855, 726], [1380, 482]],
    },
    "s1_2a_right": {
        "ground_px": 808.0,
        "slopes_px": [],
        "platforms_px": [
            [6, 734, 492, "plank"],       # 温室西段铁艺外廊（贴齐画中铁栏底沿）
            [732, 874, 385, "slab"],      # 中央黄铜百叶通风塔顶
            [874, 1434, 492, "plank"],    # 温室东段碎裂玻璃外廊
            [1434, 1576, 405, "slab"],    # 东端黄铜通风塔顶
            [60, 1420, 228, "roof"],      # 温室拱顶主钢梁
        ],
        "lamps_px": [
            [480, 430, "wall", 0],
            [1340, 718, "wall", 0],
        ],
        "spawns_px": [[420, 492], [1080, 808], [1160, 492]],
    },

    # ---------------- 1-2B 百表当铺夹巷 ----------------
    "s1_2b_left": {
        "ground_px": 818.0,
        "slopes_px": [],
        "platforms_px": [
            [726, 1274, 646, "slab"],     # 过街石拱门下层连廊（踏面精准对齐石栏杆底座）
            [40, 680, 560, "slab"],       # 左修表铺二层石挑檐
            [1310, 1650, 560, "slab"],    # 右铺二层石挑檐
            [696, 1300, 368, "slab"],     # 过街石拱门上层石栏天桥踏面
            [40, 680, 355, "slab"],       # 左楼三层挑檐
            [1310, 1650, 355, "slab"],    # 右楼三层挑檐
        ],
        "lamps_px": [
            [528, 622, "wall", 0],
        ],
        "spawns_px": [[460, 818], [1000, 646], [1000, 368]],
    },
    "s1_2b_center": {
        "ground_px": 812.0,
        "slopes_px": [],
        "platforms_px": [
            [556, 840, 522, "roof"],      # 百表当铺凸窗铜屋檐
            [840, 1530, 486, "slab"],     # 东侧深巷石拱护栏连桥踏面
            [176, 544, 386, "slab"],      # 西侧深巷高层石拱连桥踏面
            [550, 1214, 295, "slab"],     # 当铺主楼三层屋檐
        ],
        "lamps_px": [
            [898, 608, "wall", 0],
            [695, 645, "wall", 0],
        ],
        "spawns_px": [[420, 812], [1140, 812], [1180, 486]],
    },
    "s1_2b_right": {
        "ground_px": 816.0,
        "slopes_px": [],
        "platforms_px": [
            [586, 1084, 636, "plank"],    # 下层铆接铸铁过街桁架桥踏面
            [1386, 1654, 565, "roof"],    # 右转角钟表橱窗铜檐
            [26, 584, 585, "slab"],       # 左楼二层挑檐
            [1086, 1650, 478, "slab"],    # 右楼二层挑檐
            [586, 1084, 486, "plank"],    # 上层铆接铸铁过街桁架桥踏面
            [26, 584, 378, "slab"],       # 左楼三层挑檐
        ],
        "lamps_px": [
            [1290, 668, "wall", 0],
            [1500, 685, "wall", 0],
        ],
        "spawns_px": [[420, 816], [835, 636], [835, 486]],
    },

    # ---------------- S1 无主校时表坊（肉鸽中场休整室） ----------------
    "s1_rest_center": {
        "ground_px": 988.0,
        "slopes_px": [],
        "platforms_px": [
            [586, 1174, 832, "plank"],    # 表坊中央长条修表木案台台面
            [8, 396, 628, "plank"],       # 左侧二层木栏夹层回廊踏面
        ],
        "lamps_px": [
            [842, 745, "wall", 0],
            [265, 520, "wall", 0],
        ],
        "spawns_px": [],
    },

    # ---------------- E1 漏光校晷小广场（召影加赛场） ----------------
    "e1_court_center": {
        "ground_px": 992.0,
        "slopes_px": [
            # 广场中心八角黄铜日晷三级圆坛（驱时白光柱底座）
            [520, 992, 626, 946, "steps", True],
            [626, 946, 1046, 946, "steps", True],
            [1046, 946, 1152, 992, "steps", True],
        ],
        "platforms_px": [
            [86, 514, 642, "slab"],       # 左侧弧形石柱回廊露台踏面
            [1156, 1586, 642, "slab"],    # 右侧弧形石柱回廊露台踏面
        ],
        "lamps_px": [
            [98, 668, "wall", 0],
            [1572, 668, "wall", 0],
            [836, 860, "wall", 0],
        ],
        "spawns_px": [[360, 992], [1310, 992], [300, 642], [1370, 642]],
    },

    # ---------------- 1-3A 逆影铸铁飞廊 ----------------
    "s1_3a_left": {
        "ground_px": 812.0,
        "slopes_px": [],
        "platforms_px": [
            [120, 485, 602, "slab"],      # 西 1 桥墩承台（掉下底层可借桥墩跳回高架桥面）
            [760, 1105, 602, "slab"],     # 西 2 桥墩承台
            [1255, 1605, 602, "slab"],    # 西 3 桥墩承台
            [6, 502, 366, "plank"],       # 上层铸铁高架桥西端（精准贴齐铆接铁栏桥面钢板）
            [698, 1666, 366, "plank"],    # 上层铸铁高架桥主跨（502..698 为真实断口）
        ],
        "lamps_px": [
            [362, 652, "wall", 0],
        ],
        "spawns_px": [[300, 366], [1160, 366], [930, 812]],
    },
    "s1_3a_center": {
        "ground_px": 812.0,
        "slopes_px": [],
        "platforms_px": [
            [16, 365, 602, "slab"],       # 中 1 桥墩承台
            [660, 1005, 602, "slab"],     # 中 2 桥墩承台（挂灯墩）
            [1230, 1575, 602, "slab"],    # 中 3 桥墩承台
            [6, 415, 366, "plank"],       # 高架左跨桥面（415..525 断口）
            [525, 1075, 366, "plank"],    # 高架中跨桥面（1075..1185 断口）
            [1185, 1666, 366, "plank"],   # 高架右跨桥面
        ],
        "lamps_px": [
            [872, 682, "wall", 0],
            [380, 540, "wall", 0],
        ],
        "spawns_px": [[800, 366], [1420, 366], [830, 812]],
    },
    "s1_3a_right": {
        "ground_px": 812.0,
        "slopes_px": [],
        "platforms_px": [
            [20, 355, 602, "slab"],       # 东 1 桥墩承台
            [555, 895, 602, "slab"],      # 东 2 桥墩承台
            [1250, 1655, 598, "slab"],    # 母钟楼外墙齿轮廊台
            [6, 905, 366, "plank"],       # 高架东段西桥面（905..1195 断口）
            [1195, 1666, 366, "plank"],   # 高架东段接入母钟楼桥面
        ],
        "lamps_px": [
            [735, 680, "wall", 0],
            [908, 290, "wall", 0],
            [1188, 290, "wall", 0],
            [1498, 665, "wall", 0],
        ],
        "spawns_px": [[520, 366], [1420, 366], [520, 812]],
    },

    # ---------------- 1-3B 司辰铸钟残廊 ----------------
    "s1_3b_left": {
        "ground_px": 990.0,
        "slopes_px": [
            # 断裂青铜巨型音叉石基座（顺滑上下阶）
            [148, 990, 236, 922, "steps", True],
            [236, 922, 434, 922, "steps", True],
            [434, 922, 522, 990, "steps", True],
        ],
        "platforms_px": [
            [486, 1668, 652, "plank"],    # 铸钟工坊中层铁艺检修走廊踏面
            [8, 464, 488, "slab"],        # 西墙高层石廊
            [520, 1650, 412, "plank"],    # 顶部行车钢梁
        ],
        "lamps_px": [
            [230, 605, "wall", 0],
        ],
        "spawns_px": [[860, 990], [1080, 652]],
    },
    "s1_3b_center": {
        "ground_px": 990.0,
        "slopes_px": [],
        "platforms_px": [
            [86, 514, 815, "plank"],      # 半陷地面的青铜擒纵巨轮外圈踏面
            [1240, 1584, 812, "slab"],    # 倾倒裂口巨钟钟肩踏面
            [460, 1668, 652, "plank"],    # 中层铁艺检修长廊（与左翼同高贯通）
        ],
        "lamps_px": [
            [888, 735, "wall", 0],
        ],
        "spawns_px": [[760, 990], [1120, 990], [1060, 652]],
    },
    "s1_3b_right": {
        "ground_px": 990.0,
        "slopes_px": [],
        "platforms_px": [
            [860, 1244, 862, "slab"],     # 坠地青铜巨钟舌踏台
            [6, 1380, 652, "plank"],      # 中层铁艺检修长廊（与中段同高贯通）
            [6, 1340, 432, "plank"],      # 上层悬钟桁架铁廊踏面
        ],
        "lamps_px": [
            [378, 868, "wall", 0],
        ],
        "spawns_px": [[560, 990], [720, 652], [680, 432]],
    },

    # ---------------- 1-3C 司辰母钟楼正门前庭 ----------------
    "s1_3c_left": {
        "ground_px": 816.0,
        "slopes_px": [
            # 画中双折黄铜铸铁外楼梯（单向斜坡：既可从地面拾级登顶，也不阻挡地面疾跑穿过火盆）
            [495, 816, 715, 656, "steps", False],
            [715, 656, 915, 656, "steps", False],
            [915, 656, 1185, 488, "steps", False],
        ],
        "platforms_px": [
            [24, 910, 522, "slab"],       # 左侧大齿轮上方石栏走廊踏面
            [1185, 1668, 488, "plank"],   # 楼梯顶端铜管外廊（精准贴齐铁栏底座）
        ],
        "lamps_px": [
            [625, 768, "wall", 0],
            [1055, 768, "wall", 0],
        ],
        "spawns_px": [[420, 816], [1380, 488], [820, 656]],
    },
    "s1_3c_right": {
        "ground_px": 816.0,
        "slopes_px": [
            # 司辰母钟楼青铜总枢巨门六级正阶
            [460, 816, 596, 752, "steps", True],
            [596, 752, 976, 752, "steps", True],
            [976, 752, 1106, 816, "steps", True],
        ],
        "platforms_px": [
            [346, 474, 618, "slab"],      # 巨门西侧青铜方尖碑座顶
            [1096, 1224, 618, "slab"],    # 巨门东侧青铜方尖碑座顶
            [196, 384, 592, "slab"],      # 西侧中层壁龛台踏面
            [1196, 1664, 592, "slab"],    # 东侧中层挂灯露台踏面
            [196, 584, 362, "slab"],      # 巨门左上挂灯高台踏面
            [990, 1384, 362, "slab"],     # 巨门右上高台踏面
        ],
        "lamps_px": [
            [312, 255, "wall", 0],
            [1238, 538, "wall", 0],
        ],
        "spawns_px": [[786, 752], [280, 816], [1380, 816], [390, 362]],
    },

    # ---------------- 1-4 巨钟背影盘旋阶（塔内登顶走廊） ----------------
    "s1_4_center": {
        "ground_px": 990.0,
        "slopes_px": [
            # 5:59 暗朱红磨砂巨钟背面三折盘旋长阶
            [96, 990, 620, 725, "steps", False],
            [620, 725, 775, 725, "steps", False],
            [775, 725, 1105, 565, "steps", False],
            [1105, 565, 1285, 565, "steps", False],
            [1285, 565, 1666, 402, "steps", False],
        ],
        "platforms_px": [],
        "lamps_px": [
            [118, 725, "wall", 0],
            [585, 815, "wall", 0],
            [225, 405, "wall", 0],
        ],
        "spawns_px": [],
    },
    "s1_4_upper": {
        "ground_px": 990.0,
        "slopes_px": [
            # 母钟擒纵天轴中枢盘旋阶 + 中央黄铜天轴圆盘 + 登顶阶
            [56, 990, 565, 718, "steps", False],
            [565, 718, 1110, 718, "steps", False],
            [1110, 718, 1666, 472, "steps", False],
        ],
        "platforms_px": [],
        "lamps_px": [
            [118, 755, "wall", 0],
            [698, 865, "wall", 0],
            [1025, 865, "wall", 0],
            [1445, 785, "wall", 0],
        ],
        "spawns_px": [],
    },
}

CH1_ARENA_TRIPLETS: dict[str, list[str]] = {
    "1-1A": ["s1_1a_left", "s1_1a_center", "s1_1a_right"],
    "1-1B": ["s1_1b_left", "s1_1b_right", "s1_1a_right"],
    "1-2A": ["s1_2a_left", "s1_2a_center", "s1_2a_right"],
    "1-2B": ["s1_2b_left", "s1_2b_center", "s1_2b_right"],
    "1-3A": ["s1_3a_left", "s1_3a_center", "s1_3a_right"],
    "1-3B": ["s1_3b_left", "s1_3b_center", "s1_3b_right"],
    "1-3C": ["s1_3a_left", "s1_3c_left", "s1_3c_right"],
    "E1": ["s1_2b_left", "e1_court_center", "s1_2b_right"],
}

# 起点入口街（x <= 2018.2）隐形阳台湿边碰撞与壁灯（与 rain_street_layout.json 完全一致；11-17 背景线画面重构换成新近景 N1～N3 的阳台和灯）
ENTRY_LAYERED_PLATFORMS: list[list] = [
    [-3353.8, -2406.1, 137.7, "slab", {"layered": True}],
    [-3827.7, -3536.1, 256.8, "slab", {"layered": True}],
    [-4510.5, -3988.1, 208.2, "slab", {"layered": True}],
    [-4923.6, -4534.8, 205.8, "slab", {"layered": True}],
    [-5610.1, -5269.9, 213.1, "slab", {"layered": True}],
    [-5944.2, -5658.7, 145.0, "slab", {"layered": True}],
    [-6596.7, -6165.3, 249.5, "slab", {"layered": True}],
    [-6985.5, -6712.1, 255.6, "slab", {"layered": True}],
    [-7775.2, -7544.4, 236.2, "slab", {"layered": True}],
]

ENTRY_LAYERED_LAMPS: list[list] = [
    [-2697.7, 324.9, "wall", 0, {"layered": True}],
    [-3062.2, 324.9, "wall", 0, {"layered": True}],
    [-3499.6, 349.1, "wall", 0, {"layered": True}],
    [-4101.0, 341.9, "wall", 0, {"layered": True}],
    [-5397.5, 354.0, "wall", 0, {"layered": True}],
    [-6121.6, 367.4, "wall", 0, {"layered": True}],
    [-6668.3, 324.9, "wall", 0, {"layered": True}],
    [-6738.8, 361.3, "wall", 0, {"layered": True}],
    [-7456.9, 324.9, "wall", 0, {"layered": True}],
    [-7562.6, 367.4, "wall", 0, {"layered": True}],
]


def r1(v: float) -> float:
    return round(float(v), 1)


def project_tile(
    tile_id: str,
    x0: float,
    x1: float,
    section_center: float,
    manifest: dict,
    include_spawns: bool,
    out_slopes: list,
    out_platforms: list,
    out_lamps: list,
    out_spawns: list,
) -> None:
    spec = TILE_SPECS[tile_id]
    meta = manifest[tile_id]
    w_px = float(meta["width_px"])
    g_px = float(spec["ground_px"])
    k = (x1 - x0) / w_px

    def wx(px_x: float) -> float:
        return x0 + px_x * k

    def wy(px_y: float) -> float:
        return FLOOR + (px_y - g_px) * k

    for sx0, sy0, sx1, sy1, style, is_solid in spec["slopes_px"]:
        opts: dict = {"ch1_hidden": True}
        if is_solid:
            opts["solid"] = True
        out_slopes.append([
            r1(wx(sx0) - section_center),
            r1(wy(sy0)),
            r1(wx(sx1) - section_center),
            r1(wy(sy1)),
            style,
            opts,
        ])

    for px0, px1, py, style in spec["platforms_px"]:
        out_platforms.append([
            r1(wx(px0) - section_center),
            r1(wx(px1) - section_center),
            r1(wy(py)),
            style,
            {"ch1_hidden": True},
        ])

    for lx, ly, kind, rise_px in spec["lamps_px"]:
        out_lamps.append([
            r1(wx(lx) - section_center),
            r1(wy(ly)),
            kind,
            int(round(rise_px * k)),
        ])

    if include_spawns:
        for spx, spy in spec["spawns_px"]:
            sx_rel = wx(spx) - section_center
            # 封印墙位于 ±2400，刷怪点严格限制在 [-2180, +2180]
            if -2180.0 <= sx_rel <= 2180.0:
                out_spawns.append([int(round(sx_rel)), r1(wy(spy))])


def build_section_dict(name: str, code: str, slot_idx: int, manifest: dict) -> dict:
    c0 = FIRST_X
    c1 = FIRST_X + SPACING
    c2 = FIRST_X + SPACING * 2.0
    centers = {0: c0, 1: c1, 2: c2}
    center = centers[slot_idx]

    slopes: list = []
    platforms: list = []
    lamps: list = []
    spawns: list = []

    if slot_idx == 0:
        # 出生前廊完整保留 11-12 起点入口街（6 处湿边阳台单向台面 + 2 盏暖光壁灯）
        for ep in ENTRY_LAYERED_PLATFORMS:
            platforms.append(json.loads(json.dumps(ep)))
        for el in ENTRY_LAYERED_LAMPS:
            lamps.append(json.loads(json.dumps(el)))

    # 当前封印场 3 块不重样横拼（第 0 槽左端从 c0-2460=1960 起无缝垫在入口街门洞右缘羽化带后方）
    a_l = (center - 2460.0) if slot_idx == 0 else (center - 2440.0)
    a_r = center + 2440.0
    w3 = (a_r - a_l) / 3.0
    triplet = CH1_ARENA_TRIPLETS[code]
    two_level = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level" / "layout_1a.json"
    if code == "1-1A" and slot_idx == 0 and two_level.exists():
        # 11-18 背景线：1-1A 换成“上下两层街”样板角（新图由 street_layered.gd 画），台面 / 灯 / 刷怪点由
        # tools/art/ch1_1a_two_level_layout.py 从新图量出，这里直接读，不再投影旧三联画
        tl = json.loads(two_level.read_text(encoding="utf-8"))
        slopes += tl.get("slopes", [])
        platforms += tl.get("platforms", [])
        lamps += tl.get("lamps", [])
        spawns += [list(sp) for sp in tl.get("spawns", [])]
    else:
        for ti, tid in enumerate(triplet):
            tx0 = a_l + w3 * ti
            tx1 = a_l + w3 * (ti + 1)
            project_tile(tid, tx0, tx1, center, manifest, True, slopes, platforms, lamps, spawns)

    # 段后衔接走廊
    if slot_idx == 0:
        # J1 街口高低分流岔路 [c0+2440 .. c1-2440]
        j1_new = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level" / "layout_j1.json"
        if j1_new.exists():
            # 11-18 背景线：J1 换成和 1-1A 样板角同比例的新图（street_layered.gd 画），行由 ch1_1a_two_level_layout.py 量出
            jl = json.loads(j1_new.read_text(encoding="utf-8"))
            slopes += jl.get("slopes", [])
            platforms += jl.get("platforms", [])
            lamps += jl.get("lamps", [])
        else:
            project_tile("j_fork_center", c0 + 2440.0, c1 - 2440.0, center, manifest, False, slopes, platforms, lamps, spawns)
    elif slot_idx == 1:
        # S1 无主校时表坊 [c1+2440 .. c2-2440]
        project_tile("s1_rest_center", c1 + 2440.0, c2 - 2440.0, center, manifest, False, slopes, platforms, lamps, spawns)
    elif slot_idx == 2:
        # 1-4 巨钟背影盘旋阶下段 + 上段 [c2+2440 .. c2+6360]
        s4_l = c2 + 2440.0
        s4_m = s4_l + 1960.0
        s4_r = s4_m + 1960.0
        project_tile("s1_4_center", s4_l, s4_m, center, manifest, False, slopes, platforms, lamps, spawns)
        project_tile("s1_4_upper", s4_m, s4_r, center, manifest, False, slopes, platforms, lamps, spawns)

    # 将刷怪点按右/左交替排序，确保波次节奏自然
    right_sp = [s for s in spawns if s[0] >= 0]
    left_sp = [s for s in spawns if s[0] < 0]
    interleaved: list = []
    for i in range(max(len(right_sp), len(left_sp))):
        if i < len(right_sp):
            interleaved.append(right_sp[i])
        if i < len(left_sp):
            interleaved.append(left_sp[i])

    return {
        "name": name,
        "ch1_code": code,
        "buildings": [],
        "arches": [],
        "blocks": [],
        "slopes": slopes,
        "platforms": platforms,
        "spawns": interleaved,
        "lamps": lamps,
        "foreground": [],
    }


def render_verified_sheets(manifest: dict, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    keys = list(manifest.keys())
    W_CELL, H_CELL = 836, 618
    for sheet_idx in range(4):
        sub = keys[sheet_idx * 6 : (sheet_idx + 1) * 6]
        canvas = Image.new("RGB", (W_CELL * 2, H_CELL * 3), (12, 14, 20))
        for idx, tid in enumerate(sub):
            meta = manifest[tid]
            spec = TILE_SPECS[tid]
            im = Image.open(ROOT / meta["tex"].replace("res://", "")).convert("RGBA")
            bg = Image.new("RGBA", im.size, (20, 26, 38, 255))
            comp = Image.alpha_composite(bg, im).convert("RGB")
            d = ImageDraw.Draw(comp)
            w, h = comp.size
            g_px = float(spec["ground_px"])
            # Ground walk line (gold)
            d.line([(0, int(round(g_px))), (w, int(round(g_px)))], fill=(255, 200, 40), width=4)
            # Slopes / stairs (bright lime green)
            for sx0, sy0, sx1, sy1, _st, is_solid in spec["slopes_px"]:
                col = (50, 255, 100) if is_solid else (160, 255, 80)
                d.line([(sx0, sy0), (sx1, sy1)], fill=col, width=7)
            # One-way platforms (bright cyan)
            for px0, px1, py, _st in spec["platforms_px"]:
                d.line([(px0, py), (px1, py)], fill=(0, 235, 255), width=7)
            # Lamps (warm orange circle)
            for lx, ly, kind, rise in spec["lamps_px"]:
                ly_head = ly - rise
                d.ellipse([(lx - 12, ly_head - 12), (lx + 12, ly_head + 12)], outline=(255, 160, 40), width=4)
            d.rectangle([(6, 6), (520, 44)], fill=(0, 0, 0))
            d.text((12, 12), f"{tid} g_px={g_px} | cyan=platform lime=stairs", fill=(255, 255, 255))
            small = comp.resize((w // 2, h // 2), Image.Resampling.LANCZOS)
            canvas.paste(small, ((idx % 2) * W_CELL, (idx // 2) * H_CELL))
        canvas.save(out_dir / f"verified_sheet_{sheet_idx + 1}.png")


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    for tid, spec in TILE_SPECS.items():
        if tid in manifest:
            manifest[tid]["ground_px"] = float(spec["ground_px"])
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    sec_1_1a = build_section_dict("1-1 灯影空轿街", "1-1A", 0, manifest)
    sec_1_1b = build_section_dict("1-1B 停摆电车雨站", "1-1B", 0, manifest)
    sec_1_2a = build_section_dict("1-2A 飞鸦玻璃花房顶", "1-2A", 1, manifest)
    sec_1_2b = build_section_dict("1-2B 百表当铺夹巷", "1-2B", 1, manifest)
    sec_1_3a = build_section_dict("1-3A 逆影铸铁飞廊", "1-3A", 2, manifest)
    sec_1_3b = build_section_dict("1-3B 司辰铸钟残廊", "1-3B", 2, manifest)
    sec_1_3c = build_section_dict("1-3C 司辰母钟楼正门前庭", "1-3C", 2, manifest)
    sec_e1_s0 = build_section_dict("E1 漏光校晷小广场", "E1", 0, manifest)
    sec_e1 = build_section_dict("E1 漏光校晷小广场", "E1", 1, manifest)
    sec_e1_s2 = build_section_dict("E1 漏光校晷小广场", "E1", 2, manifest)

    layout = {
        "note": (
            "第一章「影街与司辰母钟楼」正式分层关卡布局（由 tools/art/build_ch1_layout_from_paintings.py "
            "根据全部 24 张商业成图的真实像素台阶、月台、马车、电车、雨棚、阳台、玻璃花房、高架桥、铸钟廊、"
            "校时表坊、日晷圆坛与母钟盘旋阶 1:1 映射生成，零空气墙 blocks，零灰盒残留）。"
        ),
        "arenaHalf": 2400,
        "arenaSpacing": 6400,
        "layered": {
            "anchorRel": -2688,
            "k": 0.75,
            "cropPx": 1500,
            "ch1ShadowStreet": True,
            "ch1DryX": 2018.0,
        },
        "backdrop": {
            "daylight": {"enabled": False, "gain": 0.0, "beads": False},
            "front": [],
            "ledgeSheen": 1.05,
            "lampGlow": 0.95,
        },
        "floors": {"ground": 580, "f2": 300, "f3": 20, "roof": -260},
        "sections": [sec_1_1a, sec_1_2b, sec_1_3b],
        "routeVariants": {
            "1-1B": sec_1_1b,
            "1-2A": sec_1_2a,
            "1-2B": sec_1_2b,
            "1-3A": sec_1_3a,
            "1-3B": sec_1_3b,
            "1-3C": sec_1_3c,
            "E1": sec_e1,
            "E1_S0": sec_e1_s0,
            "E1_S2": sec_e1_s2,
        },
    }
    LAYOUT_PATH.write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    verify_dir = os.environ.get("CH1_VERIFY_OUT", "")
    if verify_dir:
        render_verified_sheets(manifest, Path(verify_dir))
    print(f"CH1_LAYOUT_BUILT: {len(manifest)} tiles calibrated -> {LAYOUT_PATH}")


if __name__ == "__main__":
    main()
