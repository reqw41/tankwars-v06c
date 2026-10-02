import sys,csv,struct,re,collections
sys.path.insert(0,"scripts")
from emu16 import relocated_image
img=relocated_image()
rows={r['address']:r for r in csv.DictReader(open('re/rtl/rtl_names.csv'),delimiter=';')}
ranges=[(0x1000,0x1035),(0x1062,0x1632)]
for l in open('re/ovl_map.txt'):
    if l.startswith('ovl'):
        p=l.split(); seg=int(p[-1],16); ranges.append((seg+0x1000, seg+0x1000+(int(p[5])+15)//16))
cnt=collections.Counter()
for a,b in ranges:
    for i in range((a-0x1000)*16,(b-0x1000)*16-4):
        if img[i]==0x9A:
            off,seg=struct.unpack_from('<HH',img,i+1)
            if seg in (0x1827,0x175e): cnt[f"{seg:04x}:{off:04x}"]+=1
for k,c in sorted(cnt.items()):
    s,o=(int(x,16) for x in k.split(':')); p=(s-0x1000)*16+o
    code=img[p:p+120]
    end=re.search(rb'\xca..|\xcb',code,re.S)
    body=code[:end.end()] if end else code
    sis=[hex(struct.unpack('<H',m.group(1))[0]) for m in re.finditer(rb'\xbe(..)',body,re.S)]
    n=struct.unpack('<H',body[-2:])[0] if end and body[-3]==0xca else 0
    print(f"{k} {rows.get(k,{}).get('name','?'):26} game_calls={c:4} retf={n:3} SI={sis}")
