"""分层背景进游戏（11-12 用户“做进游戏先”）：把分层试验的素材拷进游戏素材目录。

源：source-art/rain-layer-test-20261108/（先跑 tools/art/rain_layer_test_prep.py 出图）
目标：assets/image/rain_street/layered/
站立层只用到成图第 1500 像素（大楼和右边那座塔之间的街缝），右边 28 像素羽化，接上钟楼广场成图的左沿。
游戏里怎么摆见 scripts/night/street_layered.gd。
"""
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "source-art" / "rain-layer-test-20261108"
DST = ROOT / "assets" / "image" / "rain_street" / "layered"
STAND_CROP = 1500
FEATHER = 28

COPY = ["far", "mid", "sky_tower", "near_a", "arch_b", "arch_c", "fg_crane", "fg_chain",
        "mh_a1", "mh_a2", "mh_a3", "mh_b1", "mh_b2", "mh_b3"]


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    for n in COPY:
        shutil.copyfile(SRC / f"{n}.png", DST / f"{n}.png")
    shutil.copyfile(SRC / "mid_houses.json", DST / "mid_houses.json")
    a = np.array(Image.open(SRC / "stand.png").convert("RGBA")).astype(np.float32)
    a = a[:, :STAND_CROP].copy()
    ramp = np.linspace(1.0, 0.0, FEATHER)
    a[:, STAND_CROP - FEATHER:, 3] *= ramp[None, :]
    Image.fromarray(a.clip(0, 255).astype(np.uint8)).save(DST / "stand_entry.png")
    # 左边镜像接长的那张用整张（左右边缘天然接得上）
    shutil.copyfile(SRC / "stand.png", DST / "stand.png")
    print("exported", len(COPY) + 2, "images ->", DST)
    print(json.dumps({"stand_entry": [STAND_CROP, a.shape[0]]}))


if __name__ == "__main__":
    main()
