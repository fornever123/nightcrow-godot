#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 capture_rain_redesign.gd 存的 HDR 线性半精度帧（.rawh）转成 sRGB PNG。用法：python -I rain_redesign_raw2png.py <目录>"""
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

d = Path(sys.argv[1])
for fp in sorted(d.glob("*.rawh")):
    b = fp.read_bytes()
    w, h = struct.unpack("<II", b[:8])
    a = np.frombuffer(b[8:], dtype=np.float16).reshape(h, w, 4)[..., :3].astype(np.float32)
    a = np.clip(a, 0.0, 1.0)
    s = np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1 / 2.4) - 0.055)
    Image.fromarray((s * 255 + 0.5).astype(np.uint8), "RGB").save(fp.with_suffix(".png"))
    fp.unlink()
print("ok", d)
