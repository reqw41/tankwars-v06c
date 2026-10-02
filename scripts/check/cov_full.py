import sys,struct,csv,collections
sys.path.insert(0,"scripts")
from emu16 import relocated_image
img=relocated_image()
named={r['address'].lower() for r in csv.DictReader(open('re/rtl/rtl_names.csv'),delimiter=';')}
LIB={0x1637,0x1651,0x166F,0x1691,0x175E,0x17A3,0x17AF,0x17C5,0x1827,0x1BE7,0x1C5B}
# full ranges (image paragraphs, Ghidra = +0x1000)
ranges=[(0x1000,0x1035),(0x1062,0x1632)]
for l in open('re/ovl_map.txt'):
    if l.startswith('ovl'):
        p=l.split(); seg=int(p[-1],16); size=int(p[5]); ranges.append((seg+0x1000, seg+0x1000+(size+15)//16))
calls=collections.Counter()
for a,b in ranges:
    for i in range((a-0x1000)*16,(b-0x1000)*16-4):
        if img[i]==0x9A:
            off,seg=struct.unpack_from('<HH',img,i+1)
            if seg in LIB: calls[(seg,off)]+=1
tot=sum(calls.values()); un=[(c,f"{s:04x}:{o:04x}") for (s,o),c in calls.items() if f"{s:04x}:{o:04x}" not in named]
print('total',tot,'unnamed sites',sum(c for c,_ in un)); print(sorted(un,reverse=True)[:15])
