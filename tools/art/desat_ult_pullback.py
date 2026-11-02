# 第十二张去色：只在眼睛、宝石、剑刃、发尾留紫，其余饱和度压到 12%
import sys
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
src,dst=sys.argv[1],sys.argv[2]
im=Image.open(src).convert('RGB'); W,H=im.size
a=np.asarray(im).astype(np.float32)/255
lum=(a*[0.299,0.587,0.114]).sum(-1,keepdims=True)
m=Image.new('L',(W,H),0); d=ImageDraw.Draw(m)
d.ellipse([862,338,978,428],fill=255)    # left eye
d.ellipse([1058,368,1172,462],fill=255)  # right eye
d.ellipse([1320,235,1385,305],fill=255)  # hair gem
d.ellipse([995,585,1060,655],fill=255)   # chest gem
d.ellipse([290,590,380,680],fill=255)    # guard gem
d.polygon([(0,640),(380,640),(900,941),(0,941)],fill=170)  # blade glow
d.polygon([(1040,450),(1230,430),(1230,560),(1080,560)],fill=130)  # hair ends right
d.polygon([(760,250),(860,250),(880,460),(780,470)],fill=110)      # hair ends left
m=np.asarray(m.filter(ImageFilter.GaussianBlur(12))).astype(np.float32)[...,None]/255
out=np.clip(lum+(a-lum)*(0.12+0.88*m),0,1)
Image.fromarray((out*255+0.5).astype(np.uint8)).save(dst)
