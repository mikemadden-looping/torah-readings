"""Fit Torah words to the 245x42 tikkun lines measured from column images.

words: list of (book, chapter, verse, index_in_verse, letters)
pet:   set of word indexes that must begin a line (after an open break)
meas:  counts.json from lw2.py (per line: gaps, ink mass; None gaps = blank line)
"""
import json, numpy as np
KMAX=16; INF=1e18

def gap_cost(g,k):
    if g is None: return 0.0 if k==0 else 60.0
    if k==0: return 60.0
    s=sorted(g,reverse=True)
    if k-1>len(s): return 40.0+5*(k-1-len(s))
    chosen=s[:k-1]; rest=s[k-1:]
    M=np.median(chosen) if chosen else (s[0] if s else 10)
    return float(sum(max(0.0,0.6*M-x) for x in chosen)+1.5*sum(max(0.0,x-0.45*M) for x in rest))

def seg_profile(pos,k):
    # measured relative word widths, right to left, splitting at the k-1 widest gaps
    if pos is None or k<1: return None
    x0,x1=pos[0],pos[1]; gaps=pos[2:]
    if k==1: return np.array([1.0])
    if len(gaps)<k-1: return None
    top=sorted(sorted(gaps,key=lambda g:-g[1])[:k-1])
    segs=[];cur=x0
    for gx,gw in top: segs.append(gx-cur); cur=gx+gw
    segs.append(x1+1-cur)
    a=np.array(segs[::-1],float); return a/a.sum() if a.sum()>0 else None

def align(letters, pet, meas, B=220, passes=3, wM=1.0, widths=None, wS=30.0):
    N=len(letters)
    poss=[p for r in meas for p in r['pos']]
    ww=np.asarray(widths if widths is not None else letters,float)
    gaps=[g for r in meas for g in r['gaps']]; mass=np.array([m for r in meas for m in r['mass']],float)
    L=len(gaps)
    C=np.array([[gap_cost(g,k) for k in range(KMAX+1)] for g in gaps])
    P=np.concatenate([[0],np.cumsum(letters)]).astype(float)
    nxt=np.full(N+2,N+1,np.int64)          # next petucha position > s
    pl=sorted(p for p in pet if 0<p<=N)
    j=len(pl)-1
    for s in range(N,-1,-1):
        while j>=0 and pl[j]>s: j-=1
        nxt[s]=pl[j+1] if j+1<len(pl) else N+1
    blank=np.array([g is None for g in gaps])
    PROF=[[seg_profile(poss[i],k) for k in range(KMAX+1)] for i in range(L)]
    def run(alpha, center=None, B=B):
        if center is None:
            est=np.cumsum([0]+[int(np.argmin(C[i])) for i in range(L)]).astype(float)
            est=(est*N/est[-1]).astype(int)
        else:
            est=np.asarray(center,np.int64)
        W=2*B+1
        lo=np.maximum(0,est-B)
        dp=np.full(W,INF); dp[0-lo[0]]=0
        backs=np.zeros((L,W),np.int32)
        for i in range(L):
            s=lo[i]+np.arange(W); valid=(dp<INF)&(s<=N)
            nd=np.full(W,INF); nb=np.full(W,-1,np.int32)
            for k in range(KMAX+1):
                e=s+k
                ok=valid&(e<=N)&((k<2)|(e<=nxt[np.minimum(s,N)]))
                if not ok.any(): continue
                c=dp+C[i][k]
                if alpha is not None and alpha[i] and k>0 and not blank[i]:
                    let=P[np.minimum(e,N)]-P[np.minimum(s,N)]
                    c=c+wM*((mass[i]/alpha[i]-let)/(0.06*let+1.5))**2
                if wS and k>=2 and not blank[i]:
                    prof=PROF[i][k]
                    if prof is None: c=c+wS*0.8
                    else:
                        ix=np.minimum(s[:,None]+np.arange(k),N-1)
                        pw=ww[ix]; pw=pw/pw.sum(1,keepdims=True)
                        c=c+wS*np.abs(pw-prof).sum(1)
                ei=e-lo[i+1]; ok&=(ei>=0)&(ei<W)
                idx=np.where(ok)[0]
                better=c[idx]<nd[ei[idx]]
                tgt=ei[idx][better]; src=idx[better]
                # several sources can hit one target in a single k-step? no: ei = s+k-lo is injective in s
                nd[tgt]=c[src]; nb[tgt]=src
            dp=nd; backs[i]=nb
        starts=np.zeros(L+1,np.int64); e=N; starts[L]=N
        for i in range(L-1,-1,-1):
            si=backs[i][e-lo[i+1]]; s=lo[i]+si; starts[i]=s; e=s
        return starts, float(dp[N-lo[L]])
    starts,cost=run(None, None, 900)
    for _ in range(passes):
        alpha=[]
        for c in range(L//42):
            r=[mass[i]/(P[starts[i+1]]-P[starts[i]]) for i in range(c*42,c*42+42)
               if not blank[i] and P[starts[i+1]]-P[starts[i]]>=20]
            alpha+=[float(np.median(r)) if r else None]*42
        starts,cost=run(alpha, starts, 160)
    return starts.tolist(), cost
