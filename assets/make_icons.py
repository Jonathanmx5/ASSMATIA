import sys
from PIL import Image, ImageDraw
def render(size, bg, pad=0.1, out=None):
    S=4; W=size*S
    img=Image.new('RGBA',(W,W),bg)
    d=ImageDraw.Draw(img)
    k=W/120*(1-2*pad); o=W*pad
    P=lambda x,y:(o+x*k,o+y*k)
    w=7*k
    for pts,col in [([(20,100),(60,18),(100,100)],'#FF7A6B'),([(31,100),(60,40),(89,100)],'#FFC24B'),([(42,100),(60,62),(78,100)],'#4CC9A6')]:
        q=[P(*p) for p in pts]
        d.line(q,fill=col,width=int(w),joint='curve')
        for x,y in q: d.ellipse([x-w/2,y-w/2,x+w/2,y+w/2],fill=col)
    x,y=P(60,86); r=6*k; d.ellipse([x-r,y-r,x+r,y+r],fill='#5DB7F0')
    img=img.resize((size,size),Image.LANCZOS)
    img.save(out)
render(1024,'#FFFFFF',pad=.05,out='assets/icon_full.png')
render(1024,(0,0,0,0),pad=.15,out='assets/icon_fg.png')   # adaptive foreground (safe zone)
render(512,(0,0,0,0),pad=.02,out='assets/logo_a8.png')     # in-app logo
