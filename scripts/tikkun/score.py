import json, numpy as np, runpy
A=runpy.run_path('align3.py')
meas=json.load(open('counts.json')); S=json.load(open('starts_sef.json'))['starts']; Wd=json.load(open('words_sef.json'))['words']
LW=json.load(open('letterw.json'))
poss=[p for r in meas for p in r['pos']]
ww=np.array([sum(LW.get(c,1000) for c in w)+150*len(w) for w in Wd],float)
sc=[]
for i in range(len(S)-1):
    s,e=S[i],S[i+1]; n=e-s
    if n<2: sc.append(None); continue
    prof=A['seg_profile'](poss[i],n)
    sc.append(1.0 if prof is None else float(np.abs(ww[s:e]/ww[s:e].sum()-prof).sum()))
json.dump(sc,open('linescores.json','w'))
cols=[np.mean([x for x in sc[c*42:c*42+42] if x is not None]) for c in range(245)]
print('bad columns (>0.12):',[ (c+1,round(cols[c],2)) for c in range(245) if cols[c]>0.12])
good=[x for x in sc if x is not None]
print('lines', len(good), 'fit<0.10:', sum(x<0.10 for x in good), 'fit>0.20:', sum(x>0.20 for x in good))
