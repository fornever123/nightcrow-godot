#!/usr/bin/env python3
"""把 GPT 画的手绘背景图（或分层图）锁色 + 转成统一格子的像素画。
所有图层都用同一个“像素宽”处理，保证全场景像素颗粒一样大（像素画第一条规矩）。
用法：python3 tools/art/pixelize_keyart.py 输入.png 输出.png [像素宽=480] [颜色数=24] [key]
  像素宽：整张图缩成多少个像素宽（480 ≈ 720p 下每格 2.7 屏幕像素；640 = 每格 2 像素）
  key：输入是品红 #FF00FF 底的分层图时加这个参数，品红变透明、边缘不留粉边、透明度只取 0/1
输出：输出.png 为真实像素尺寸（游戏用），另存 输出_preview.png 为最近邻放大 3 倍的预览。
"""
import cv2, numpy as np, sys

def lock(img, tgt=268.0, keep=0.5):   # LAB 色相 268 = 石板灰蓝（208 偏青发绿，用户否了）
    """冷色相转到石板灰蓝、饱和度降到 keep 倍；暖色（灯光）只轻降。与 keyart_check.py 相同。"""
    L, a, b = cv2.split(cv2.cvtColor(img, cv2.COLOR_BGR2LAB))
    C = np.hypot(a, b); hue = np.degrees(np.arctan2(b, a)) % 360; cool = np.clip(-b / 8, 0, 1)
    hue2 = hue + (((tgt - hue + 180) % 360) - 180) * 0.85 * cool
    C2 = C * (1 - (1 - keep) * cool) * (1 - 0.1 * (1 - cool))
    lab = cv2.merge([L, (C2 * np.cos(np.radians(hue2))).astype(np.float32), (C2 * np.sin(np.radians(hue2))).astype(np.float32)])
    return np.clip(cv2.cvtColor(lab, cv2.COLOR_LAB2BGR), 0, 1)

def main():
    src, dst = sys.argv[1], sys.argv[2]
    PW = int(sys.argv[3]) if len(sys.argv) > 3 else 480
    K = int(sys.argv[4]) if len(sys.argv) > 4 else 24
    KEY = len(sys.argv) > 5 and sys.argv[5] == 'key'
    im = cv2.imread(src).astype(np.float32) / 255; H, W = im.shape[:2]
    alpha = np.ones((H, W), np.float32)
    if KEY:   # 品红距离 → 透明；边缘去粉（减掉混进来的品红）
        d = np.linalg.norm(im - np.array([1, 0, 1], np.float32), axis=2)
        alpha = np.clip((d - 0.25) / 0.35, 0, 1)
        g = im[..., 1:2]; im = np.where(alpha[..., None] < 1, np.concatenate([np.minimum(im[..., :1], g + 0.08), im[..., 1:2], np.minimum(im[..., 2:], g + 0.08)], 2), im)
    im = lock(im)
    ph = round(H * PW / W)
    pre = cv2.resize(im * alpha[..., None], (PW, ph), interpolation=cv2.INTER_AREA)
    a = cv2.resize(alpha, (PW, ph), interpolation=cv2.INTER_AREA)
    sm = np.clip(pre / np.maximum(a, 1e-4)[..., None], 0, 1)
    bl = cv2.GaussianBlur(sm, (0, 0), 0.8); sm = np.clip(sm + 0.6 * (sm - bl), 0, 1)   # 轻锐化，边缘更利
    solid = a >= 0.5
    lab = cv2.cvtColor(sm.astype(np.float32), cv2.COLOR_BGR2LAB)[solid].reshape(-1, 3)
    _, lbl, cen = cv2.kmeans(lab, K, None, (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 40, 0.1), 4, cv2.KMEANS_PP_CENTERS)
    q = np.zeros((ph, PW, 3), np.float32); q[solid] = cen[lbl.ravel()]
    q = cv2.cvtColor(q, cv2.COLOR_LAB2BGR); q[~solid] = 0
    out = np.dstack([(np.clip(q, 0, 1) * 255).astype(np.uint8), (solid * 255).astype(np.uint8)])
    cv2.imwrite(dst, out if KEY else out[..., :3])
    prev = cv2.resize(out, (PW * 3, ph * 3), interpolation=cv2.INTER_NEAREST)
    cv2.imwrite(dst.rsplit('.', 1)[0] + '_preview.png', prev if KEY else prev[..., :3])
    print(f'{PW}x{ph} 像素，{K} 色 -> {dst}')

if __name__ == '__main__':
    main()
