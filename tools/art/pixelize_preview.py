import cv2, numpy as np, sys
D = sys.argv[1] if len(sys.argv) > 1 else '/data/bgtest'
SPR = sys.argv[2] if len(sys.argv) > 2 else 'assets/image/characters/nightcrow/idle/frame_0001.png'
im = cv2.imread(D + '/comp.png').astype(np.float32) / 255
spr = cv2.imread(SPR, -1).astype(np.float32) / 255
a = spr[..., 3]; ys, xs = np.where(a > 0.1); spr = spr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
s = 135 / spr.shape[0]; spr = cv2.resize(spr, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
h, w = spr.shape[:2]; x0, y0 = 760, 862 - h + 2
withc = im.copy(); al = spr[..., 3:]
withc[y0:y0 + h, x0:x0 + w] = spr[..., :3] * al + withc[y0:y0 + h, x0:x0 + w] * (1 - al)
cv2.imwrite(D + '/with_char_1280.jpg', cv2.resize((withc * 255).astype(np.uint8), (1280, 720), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 92])
# 眯眼测试：大幅模糊 + 去色
sq = cv2.GaussianBlur(cv2.cvtColor((withc * 255).astype(np.uint8), cv2.COLOR_BGR2GRAY), (0, 0), 9)
cv2.imwrite(D + '/squint.jpg', cv2.resize(sq, (640, 360), interpolation=cv2.INTER_AREA))
# 像素版：640x360 面积平均 → 40 色 → 最近邻放大
small = cv2.resize(im, (640, 360), interpolation=cv2.INTER_AREA)
Z = small.reshape(-1, 3).astype(np.float32)
crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
_, lab, cen = cv2.kmeans(Z, 40, None, crit, 3, cv2.KMEANS_PP_CENTERS)
q = cen[lab.flatten()].reshape(small.shape)
big = cv2.resize(q, (1920, 1080), interpolation=cv2.INTER_NEAREST)
cv2.imwrite(D + '/pixel.png', (big * 255).astype(np.uint8))
cv2.imwrite(D + '/pixel_1280.png', cv2.resize((big * 255).astype(np.uint8), (1280, 720), interpolation=cv2.INTER_NEAREST))
cv2.imwrite(D + '/pixel_crop.png', (big[420:900, 900:1760] * 255).astype(np.uint8))
print('ok')
