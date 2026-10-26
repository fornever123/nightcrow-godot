"""画「鸦羽止」首帧用的姿势参考图：居合架势、严格侧视、面朝右，Q 版约 3.5 头身。

只是给 AI 生图当姿势参考（灰色人偶 + 刀鞘），不是游戏素材。
近侧（左半身）深灰，远侧（右半身）浅灰。
输出：tools/art/src/ult/feather/pose_ref_iai.png（1672×941，和 AI 出图同尺寸）
"""
from pathlib import Path

from PIL import Image, ImageDraw

W, H = 1672, 941
S = 2  # 超采样
OUT = Path(__file__).parent / "src/ult/feather/pose_ref_iai.png"

NEAR = (70, 70, 78)
FAR = (150, 150, 160)
BODY = (95, 95, 104)
SHEATH = (15, 15, 18)
HILT = (40, 40, 46)
BG = (255, 255, 255)

img = Image.new("RGB", (W * S, H * S), BG)
d = ImageDraw.Draw(img)


def p(x, y):
    return (x * S, y * S)


def limb(a, b, w, col):
    d.line([p(*a), p(*b)], fill=col, width=int(w * S))
    for c in (a, b):
        r = w * S / 2
        d.ellipse([c[0] * S - r, c[1] * S - r, c[0] * S + r, c[1] * S + r], fill=col)


def poly(pts, col):
    d.polygon([p(*q) for q in pts], fill=col)


# 关键点（屏幕坐标，地面 y = 872）
hip_far, hip_near = (548, 640), (520, 646)
knee_f, ankle_f = (705, 700), (748, 846)          # 前腿（右腿，远侧）：膝深弯
knee_b, ankle_b = (418, 748), (336, 832)          # 后腿（左腿，近侧）：几乎蹬直
sh_far, sh_near = (628, 476), (604, 484)          # 躯干前倾约 25°
head = (664, 366)
HEAD_R = 92

# --- 远侧：右腿、右臂（从身前斜伸去握刀柄，手肘抬起） ---
limb(hip_far, knee_f, 58, FAR)
limb(knee_f, ankle_f, 46, FAR)
poly([(724, 828), (812, 846), (816, 874), (724, 874)], FAR)  # 前脚，脚掌踩实
elbow_r, hand_r = (718, 514), (690, 598)
limb(sh_far, elbow_r, 38, FAR)
limb(elbow_r, hand_r, 32, FAR)

# --- 躯干 + 骨盆 + 头 ---
poly([(sh_near[0] - 46, sh_near[1] - 10), (sh_far[0] + 40, sh_far[1] - 18), (hip_far[0] + 44, hip_far[1] + 6), (hip_near[0] - 44, hip_near[1] + 10)], BODY)
d.ellipse([p(474, 600)[0], p(474, 600)[1], p(596, 690)[0], p(596, 690)[1]], fill=BODY)  # 骨盆
limb((618, 470), (636, 436), 36, BODY)  # 脖子（略前伸，头压低）
d.ellipse([p(head[0] - HEAD_R, head[1] - HEAD_R)[0], p(head[0] - HEAD_R, head[1] - HEAD_R)[1],
           p(head[0] + HEAD_R, head[1] + HEAD_R)[0], p(head[0] + HEAD_R, head[1] + HEAD_R)[1]], fill=BODY)
poly([(head[0] + HEAD_R - 6, head[1] + 4), (head[0] + HEAD_R + 16, head[1] + 22), (head[0] + HEAD_R - 8, head[1] + 30)], BODY)  # 鼻尖：标出朝右
d.line([p(head[0] + 34, head[1] + 2), p(head[0] + 72, head[1] + 2)], fill=(30, 30, 34), width=6 * S)  # 眼线：平视前方

# --- 近侧：左腿（后腿蹬直、脚跟抬起）、左臂（握鞘口，拇指压护手） ---
limb(hip_near, knee_b, 60, NEAR)
limb(knee_b, ankle_b, 48, NEAR)
poly([(306, 830), (350, 824), (394, 864), (394, 876), (352, 876), (310, 852)], NEAR)  # 后脚：前脚掌着地、脚跟抬起
# --- 刀：刀鞘斜插左腰，鞘尾朝后下；刀柄朝前上 ---
mouth = (606, 626)
tail = (262, 716)
limb(mouth, tail, 18, SHEATH)
guard_c = (618, 622)
d.ellipse([p(guard_c[0] - 9, guard_c[1] - 22)[0], p(guard_c[0] - 9, guard_c[1] - 22)[1],
           p(guard_c[0] + 9, guard_c[1] + 22)[0], p(guard_c[0] + 9, guard_c[1] + 22)[1]], fill=HILT)  # 护手
limb((626, 619), (744, 588), 15, HILT)  # 刀柄

elbow_l, hand_l = (540, 566), (598, 628)
limb(sh_near, elbow_l, 40, NEAR)
limb(elbow_l, hand_l, 34, NEAR)
limb(hand_l, (614, 612), 12, NEAR)  # 拇指压在护手上

# 远侧右手画在刀柄上面（握住）
limb((680, 602), (700, 596), 30, FAR)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.resize((W, H), Image.LANCZOS).save(OUT)
print(OUT)
