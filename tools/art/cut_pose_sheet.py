"""把抠好的姿势精灵表按连通块切成单张（小碎块归给最近的姿势）。用法：python cut_pose_sheet.py 抠图.png 输出目录"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ni

sheet = Image.open(sys.argv[1]).convert("RGBA")
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
rgba = np.array(sheet)
mask = rgba[:, :, 3] > 8
lab, n = ni.label(mask, structure=np.ones((3, 3)))
sizes = ni.sum(mask, lab, range(1, n + 1))
big = [i + 1 for i, s in enumerate(sizes) if s > 2000]
slices = ni.find_objects(lab)
big.sort(key=lambda i: slices[i - 1][1].start)
owner = {}
for i in range(1, n + 1):
    cx = (slices[i - 1][1].start + slices[i - 1][1].stop) / 2
    owner[i] = i if i in big else min(big, key=lambda b: abs(cx - (slices[b - 1][1].start + slices[b - 1][1].stop) / 2))
info = []
for k, b in enumerate(big):
    keep = np.isin(lab, [i for i, o in owner.items() if o == b])
    ys, xs = np.where(keep)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    cell = rgba.copy()
    cell[~keep] = 0
    Image.fromarray(cell[y0:y1, x0:x1]).save(out / f"p{k + 1}.png")
    info.append({"name": f"p{k + 1}", "x0": int(x0), "x1": int(x1), "y0": int(y0), "y1": int(y1)})
    print(info[-1])
(out / "cut.json").write_text(json.dumps(info, indent=1), encoding="utf-8")
