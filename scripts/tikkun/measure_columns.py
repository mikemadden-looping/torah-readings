import numpy as np, json
from PIL import Image
def ink(path):
    a=np.asarray(Image.open(path).convert('RGB')).astype(int)
    r,g,b=a[...,0],a[...,1],a[...,2]
    m=(r<90)&(g<90)&(b<110)&(np.abs(b-r)<50)
    # scanner shadows: vertical bands that are dark down most of the page
    shadow=m[60:].mean(0)>0.35
    if shadow.any():
        # widen the masked band a little
        sh=np.convolve(shadow.astype(int),np.ones(7,int),'same')>0
        m[:,sh]=False
    return m
def grid(m):
    p=m.sum(1).astype(float)
    start=next(i for i in range(45,len(p)) if p[i]>2)
    p=np.concatenate([p,np.zeros(1600)])
    best=None
    for pitch in np.arange(25.0,34.0,0.02):
        for off in range(-6,7):
            y0=start+off
            sc=sum(p[int(y0+(k+0.5)*pitch)-3:int(y0+(k+0.5)*pitch)+4].sum() for k in range(42)) \
              -3*sum(p[max(0,int(y0+k*pitch)-1):int(y0+k*pitch)+2].sum() for k in range(43))
            if best is None or sc>best[0]: best=(sc,pitch,y0)
    return best[1],best[2]
POS=[]
def raw_gaps(m,pitch,y0,core=(0.33,0.78)):
    m=np.concatenate([m,np.zeros((1600,m.shape[1]),bool)]); out=[]
    for k in range(42):
        a=int(y0+k*pitch+core[0]*pitch); b=int(y0+k*pitch+core[1]*pitch)
        xs=np.where(m[a:b].sum(0)>0)[0]
        if len(xs)==0: out.append(None); POS.append(None); continue
        g=[int(xs[i+1]-xs[i]-1) for i in range(len(xs)-1) if xs[i+1]-xs[i]>1]
        out.append(g)
        POS.append([int(xs[0]),int(xs[-1])]+[[int(xs[i]+1),int(xs[i+1]-xs[i]-1)] for i in range(len(xs)-1) if xs[i+1]-xs[i]>1])
    return out
def count(g):
    if g is None: return 0
    if not g: return 1
    s=sorted(g); 
    # Otsu split between letter gaps and word gaps
    best=None
    for t in range(2,max(s)+1):
        lo=[x for x in s if x<t]; hi=[x for x in s if x>=t]
        if not hi: break
        if not lo: v=0
        else:
            w0,w1=len(lo),len(hi); v=w0*w1*(np.mean(hi)-np.mean(lo))**2
        if best is None or v>best[0]: best=(v,t)
    if best is None: return 1
    t=max(best[1],5)
    hi=[x for x in s if x>=t]
    # word gaps in a justified line are similar; drop outliers far below the median
    if hi:
        med=np.median(hi); t=max(t, 0.55*med)
    return 1+sum(1 for x in g if x>=t)
if __name__=='__main__':
    res=[]
    for c in range(1,246):
        m=ink(f"../ext/yg/columns/Torah_Scroll_Col_{c:03d}_of_245.jpg"); pitch,y0=grid(m)
        G=raw_gaps(m,pitch,y0)
        mm=np.concatenate([m,np.zeros((1600,m.shape[1]),bool)])
        mass=[int(mm[int(y0+k*pitch+0.15*pitch):int(y0+k*pitch+0.9*pitch)].sum()) for k in range(42)]
        res.append({'col':c,'lines':[count(g) for g in G],'gaps':G,'mass':mass,'pos':POS[-42:]})
    json.dump(res,open('counts.json','w'))
    print('measured', sum(sum(r['lines']) for r in res))
