import sys, math
sys.path.insert(0,"scripts")
from real48 import float_to_regs, almost_equal
from emu16 import Emu16, call_far, result_real
S=0x1C5B
def L(v): v&=0xffffffff; return v&0xffff, v>>16
def R(ax,dx):
    v=(ax&0xffff)|((dx&0xffff)<<16); return v-(1<<32) if v>=1<<31 else v
def bin(off,a,b):
    ax,bx,dx=float_to_regs(a); cx,si,di=float_to_regs(b)
    return result_real(call_far(Emu16(),S,off,ax=ax,bx=bx,dx=dx,cx=cx,si=si,di=di))
def un(off,a):
    ax,bx,dx=float_to_regs(a); return result_real(call_far(Emu16(),S,off,ax=ax,bx=bx,dx=dx))
def toint(off,a):
    ax,bx,dx=float_to_regs(a); r=call_far(Emu16(),S,off,ax=ax,bx=bx,dx=dx); return R(r['ax'],r['dx'])
print('LongDiv  -7,2 ->', end=' ')
for a,b in [(-7,2),(7,2),(7,-2),(-7,-2),(1000000,7)]:
    ax,dx=L(a); cx,bx=L(b); r=call_far(Emu16(),S,0x0A2D,ax=ax,dx=dx,cx=cx,bx=bx)
    print(f"{a}/{b}: ax:dx={R(r['ax'],r['dx'])} cx:bx={R(r['cx'],r['bx'])}", end=' | ')
print()
for a,b in [(1e6,1e6),(1e30,1e-5),(123456.789,-0.001),(3e38,1.0)]:
    print('mul',a,b,bin(0x113D,a,b),a*b, '| add',bin(0x112B,a,b),a+b)
print('div 1/3', bin(0x1143,1.0,3.0), 1/3)
for v in [40000.0,-70000.5,2.5,-2.5,0.5,1e9]:
    print('trunc/round',v,toint(0x1155,v),toint(0x115B,v))
for v in [100.0,-1000.0,1e4]:
    print('sin/cos',v,un(0x1276,v),math.sin(v),un(0x1263,v),math.cos(v))
for v in [1e6,2.0,1e-4]:
    print('sqrt',v,un(0x1204,v),math.sqrt(v), 'atan',un(0x144D,v),math.atan(v))
