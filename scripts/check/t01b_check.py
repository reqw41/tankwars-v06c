import sys; sys.path.insert(0,'scripts')
from emu16 import DS_SEG, diff_bbox, pascal_string
from graph_env import gcall, make_graph_emu, clear_vram, WRAP
# Line endpoints
e=make_graph_emu(); clear_vram(e); gcall(e,0x1DC2,[4]); gcall(e,0x1C86,[20,10,80,50])
print('line ends',e.pixel(20,10),e.pixel(80,50),'mid',e.pixel(50,30),'bbox',diff_bbox(bytes(64000),e.vram()))
# Bar exact extent
e=make_graph_emu(); clear_vram(e); gcall(e,0x1131,[1,14]); gcall(e,0x1CCE,[10,10,50,40])
print('bar bbox',diff_bbox(bytes(64000),e.vram()), e.pixel(9,10),e.pixel(10,10),e.pixel(50,40),e.pixel(51,40))
# globals diff for hypotheses
def gdiff(off,args,seg=0x1827):
    e=make_graph_emu(); before=e.read_bytes(DS_SEG,0,0xFFFF)
    try: r=gcall(e,off,args,seg=seg)
    except Exception as ex: print(hex(off),'EXC',ex); return
    after=e.read_bytes(DS_SEG,0,0xFFFF)
    ch=[(hex(i),before[i],after[i]) for i in range(len(before)) if before[i]!=after[i]]
    print(hex(seg),hex(off),args,'ax',hex(r['ax']),'changed',ch[:12],'vram',diff_bbox(bytes(64000),e.vram()))
gdiff(0x1496,[2,0,4]); gdiff(0x11ea,[1,0,3]); gdiff(0x16e3,[10,20,100,50]); gdiff(0x06ca,[DS_SEG,0x4000])
e=make_graph_emu(); e.write_bytes(DS_SEG,0x4000,pascal_string("abc"))
gdiff(0x0293,[DS_SEG,0x4000],seg=WRAP)
print('--- circle?')
for args in ([100,80,15],[15,80,100]):
    e=make_graph_emu(); clear_vram(e); gcall(e,0x1DC2,[7]); gcall(e,0x11EA,args)
    print(args, diff_bbox(bytes(64000),e.vram()))
print('--- IntToStr? push result ptr first')
e=make_graph_emu(); e.write_bytes(DS_SEG,0x4400,bytes(16))
r=gcall(e,0x0293,[DS_SEG,0x4400,12345&0xffff,0],seg=WRAP); print('sp-based', e.read_bytes(DS_SEG,0x4400,8))
