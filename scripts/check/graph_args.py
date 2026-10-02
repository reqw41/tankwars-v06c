import sys,csv,struct,re,collections
sys.path.insert(0,"scripts")
from emu16 import relocated_image
img=relocated_image()
rows=[r for r in csv.DictReader(open('re/rtl/rtl_names.csv'),delimiter=';') if r['unit'] in('Graph','GraphWrap')]
# game call counts
cnt=collections.Counter()
for m in re.finditer(rb'\x9a(..)(..)',img,re.S):
    off,seg=struct.unpack('<HH',m.group(1)+m.group(2)); cnt[f"{seg:04x}:{off:04x}"]+=1
for r in rows:
    s,o=(int(x,16) for x in r['address'].split(':')); p=(s-0x1000)*16+o
    code=img[p:p+400]
    si=re.search(rb'\xbe(..)',code[:60],re.S)
    ret=re.search(rb'\xca(..)|\xcb',code,re.S)
    n=struct.unpack('<H',ret.group(1))[0] if ret and ret.group(1) else (0 if ret else None)
    print(f"{r['address']} {r['name']:28} calls={cnt[r['address']]:4} retf={n} si={(hex(struct.unpack('<H',si.group(1))[0]) if si else '-')}")
