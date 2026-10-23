import json, sys
from PIL import Image, ImageDraw, ImageFont
exec(open('lw2.py').read().split("if __name__")[0])
S=json.load(open('starts_sef.json'))['starts']; Wd=json.load(open('words_sef.json'))['words']
font=ImageFont.truetype('StamAshkenazCLM.ttf',24)
def sheet(col, k0, n, out):
    p=f'../ext/yg/columns/Torah_Scroll_Col_{col:03d}_of_245.jpg'
    m=ink(p); pitch,y0=grid(m); im=Image.open(p).convert('RGB'); w=im.size[0]
    H=int(n*(pitch+30)); canvas=Image.new('RGB',(w,H),'white'); d=ImageDraw.Draw(canvas)
    for j in range(n):
        k=k0+j; crop=im.crop((0,int(y0+k*pitch),w,int(y0+(k+1)*pitch)))
        y=int(j*(pitch+30)); canvas.paste(crop,(0,y))
        i=(col-1)*42+k; txt=' '.join(Wd[S[i]:S[i+1]])
        d.text((w-4,y+int(pitch)+2),txt,font=font,fill=(200,0,0),anchor='ra',direction='rtl')
        d.text((2,y+int(pitch)+4),str(k+1),fill=(0,0,255))
    canvas.save(out)
col,k0,n=map(int,sys.argv[1:4]); sheet(col,k0,n,sys.argv[4])
