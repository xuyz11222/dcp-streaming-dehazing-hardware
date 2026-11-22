import sys
import numpy as np
from PIL import Image

if len(sys.argv) != 5:
    raise SystemExit("usage: raw_to_png.py W H in.raw out.png")

w, h = int(sys.argv[1]), int(sys.argv[2])
a = np.fromfile(sys.argv[3], np.uint8)
if a.size < w * h * 3:
    raise SystemExit("short raw")
Image.fromarray(a[:w*h*3].reshape(h, w, 3)).save(sys.argv[4])
print(sys.argv[4])
