import json, runpy, time
A=runpy.run_path('align3.py')
T=json.load(open('/home/claude/torah-readings/scripts/torah-words.json'))
LW=json.load(open('letterw.json'))
words=[];pet=set();keys=[]
for bi,b in enumerate(['Genesis','Exodus','Leviticus','Numbers','Deuteronomy']):
    for ci,ch in enumerate(T[b]):
        for vi,v in enumerate(ch):
            wi=0
            for w in v.split():
                if w=='P': pet.add(len(words)); continue
                if w=='S': continue
                words.append(w); keys.append((bi,ci+1,vi+1,wi)); wi+=1
meas=json.load(open('counts.json'))
W=[sum(LW.get(c,1000) for c in w)+150*len(w) for w in words]
t0=time.time(); starts,cost=A['align']([len(w) for w in words],pet,meas,widths=W); print('words',len(words),'secs',round(time.time()-t0))
ls=set(starts[i] for i in range(len(starts)-1) if starts[i+1]>starts[i])
print('petuchot ok', sum(1 for p in pet if p in ls or p==len(words)),'/',len(pet))
json.dump({'starts':starts},open('starts_sef.json','w'))
json.dump({'words':words,'keys':keys},open('words_sef.json','w'))
