from pathlib import Path
import cv2, numpy as np
from PIL import Image, ImageDraw
import argparse
parser=argparse.ArgumentParser(description='Remove the gray plate from extracted first4 trial frames; no image generation.')
parser.add_argument('--work-dir', type=Path, required=True)
ROOT=parser.parse_args().work_dir
OUT=ROOT/'transparent'
OUT.mkdir(exist_ok=True)
records=[]
for p in sorted((ROOT/'01-raw').glob('*.png')):
    rgb=np.array(Image.open(p).convert('RGB'))
    h,w=rgb.shape[:2]
    plate=np.median(rgb[:,::6],axis=1,keepdims=True).astype(np.float32)
    delta=np.abs(rgb.astype(np.float32)-plate).max(2)
    hard=(delta>13).astype(np.uint8)
    n,labels,stats,_=cv2.connectedComponentsWithStats(hard,8)
    pick=1+np.argmax(stats[1:,4])
    x,y,bw,bh,area=stats[pick]
    valid=np.zeros((h,w),np.uint8)
    valid[max(0,y-12):min(h,y+bh+12),max(0,x-20):min(w,x+bw+20)]=1
    support=((delta>7)&(valid>0)).astype(np.uint8)
    contours,_=cv2.findContours(support,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    solid=np.zeros((h,w),np.uint8)
    for contour in contours:
        if cv2.contourArea(contour)>24:cv2.drawContours(solid,[contour],-1,1,-1)
    edge=cv2.dilate(solid,np.ones((3,3),np.uint8))>0
    alpha=np.clip((delta-4)/12,0,1)*edge
    alpha[solid>0]=1
    result=np.dstack([rgb,np.rint(alpha*255).astype(np.uint8)])
    soft=(alpha>0)&(alpha<1)
    bg=np.broadcast_to(plate,rgb.shape)
    result[soft,:3]=np.clip((rgb[soft]-(1-alpha[soft,None])*bg[soft])/alpha[soft,None],0,255).astype(np.uint8)
    result[alpha==0]=0
    im=Image.fromarray(result); im.save(OUT/p.name)
    records.append((p.name,im.getbbox()))
    print(p.name,im.getbbox(),flush=True)
import json
(ROOT/'bounds.json').write_text(json.dumps(records))
thumbs=[]
for idx in range(0,len(records),4):
    name,box=records[idx];im=Image.open(OUT/name).crop(box)
    im.thumbnail((220,220))
    bg=Image.new('RGBA',(240,250),'#655776');bg.alpha_composite(im,((240-im.width)//2,15));ImageDraw.Draw(bg).text((8,232),str(idx+1),fill='white');thumbs.append(bg)
sheet=Image.new('RGB',(240*7,250*((len(thumbs)+6)//7)))
for i,im in enumerate(thumbs):sheet.paste(im,(i%7*240,i//7*250))
sheet.save(ROOT/'matte-sheet.jpg')
