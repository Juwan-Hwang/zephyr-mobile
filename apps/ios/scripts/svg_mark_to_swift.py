#!/usr/bin/env python3
# 把 app-icon.svg 里的标志路径（M/L/A/Z）转成 SwiftUI Path 代码（圆弧→三次贝塞尔，归一化到 164×142 标志框）。
# 用法：python3 scripts/svg_mark_to_swift.py > /tmp/mark.txt，粘贴进 Widgets/Views/ZephyrMarkShape.swift。
import re, math
d="M206.08 56.99 L47.45 56.99 A1.45 1.45 0 0 0 46.01 58.44 A164.00 164.00 0 0 0 67.30 137.82 A1.35 1.35 0 0 0 69.14 138.31 L206.61 58.95 A1.05 1.05 0 0 0 206.08 56.99 Z M49.92 199.01 L208.55 199.01 A1.45 1.45 0 0 0 209.99 197.56 A164.00 164.00 0 0 0 188.70 118.18 A1.35 1.35 0 0 0 186.86 117.69 L49.39 197.05 A1.05 1.05 0 0 0 49.92 199.01 Z"
VB=(46,57,164,142)
toks=re.findall(r'[MLAZ]|-?[\d.]+',d)
def arc_to_cubics(x1,y1,rx,ry,phi,fa,fs,x2,y2):
    # endpoint -> center (phi=0)
    dx=(x1-x2)/2; dy=(y1-y2)/2
    x1p,y1p=dx,dy
    lam=(x1p**2)/(rx**2)+(y1p**2)/(ry**2)
    if lam>1: rx*=math.sqrt(lam); ry*=math.sqrt(lam)
    num=rx*rx*ry*ry-rx*rx*y1p*y1p-ry*ry*x1p*x1p
    den=rx*rx*y1p*y1p+ry*ry*x1p*x1p
    co=math.sqrt(max(0,num/den))
    if fa==fs: co=-co
    cxp=co*rx*y1p/ry; cyp=-co*ry*x1p/rx
    cx=cxp+(x1+x2)/2; cy=cyp+(y1+y2)/2
    def ang(ux,uy,vx,vy):
        a=math.atan2(ux*vy-uy*vx, ux*vx+uy*vy); return a
    t1=ang(1,0,(x1p-cxp)/rx,(y1p-cyp)/ry)
    dt=ang((x1p-cxp)/rx,(y1p-cyp)/ry,(-x1p-cxp)/rx,(-y1p-cyp)/ry)
    if not fs and dt>0: dt-=2*math.pi
    if fs and dt<0: dt+=2*math.pi
    n=max(1,math.ceil(abs(dt)/(math.pi/2)))
    seg=dt/n; out=[]
    for i in range(n):
        a1=t1+i*seg; a2=a1+seg
        k=4/3*math.tan((a2-a1)/4)
        p1=(cx+rx*math.cos(a1), cy+ry*math.sin(a1))
        p2=(cx+rx*math.cos(a2), cy+ry*math.sin(a2))
        c1=(p1[0]-k*rx*math.sin(a1), p1[1]+k*ry*math.cos(a1))
        c2=(p2[0]+k*rx*math.sin(a2), p2[1]-k*ry*math.cos(a2))
        out.append((c1,c2,p2))
    return out
def n(p): return ((p[0]-VB[0])/VB[2],(p[1]-VB[1])/VB[3])
def f(v): return f"{v:.5f}"
def pt(p): q=n(p); return f"p({f(q[0])}, {f(q[1])})"
lines=[];i=0;cur=None
while i<len(toks):
    t=toks[i]
    if t=='M': cur=(float(toks[i+1]),float(toks[i+2])); lines.append(f"path.move(to: {pt(cur)})"); i+=3
    elif t=='L': cur=(float(toks[i+1]),float(toks[i+2])); lines.append(f"path.addLine(to: {pt(cur)})"); i+=3
    elif t=='A':
        rx,ry,phi,fa,fs,x,y=[float(v) for v in toks[i+1:i+8]]
        for c1,c2,p2 in arc_to_cubics(cur[0],cur[1],rx,ry,phi,int(fa),int(fs),x,y):
            lines.append(f"path.addCurve(to: {pt(p2)}, control1: {pt(c1)}, control2: {pt(c2)})")
        cur=(x,y); i+=8
    elif t=='Z': lines.append("path.closeSubpath()"); i+=1
print("\n".join(lines))
