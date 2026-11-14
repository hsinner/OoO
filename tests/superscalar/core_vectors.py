"""Independent RV32I architectural oracle and directed integration program.

No RTL enums/helpers are imported. Program encoders only produce binary input;
the oracle decodes those words again and executes one instruction at a time.
"""
from pathlib import Path
import random

OUT = Path('build/core-vectors')
OUT.mkdir(parents=True, exist_ok=True)
MASK = (1 << 32) - 1

def sx(x, width):
    return x - (1 << width) if x & (1 << (width - 1)) else x

def it(op, rd, f, rs, imm):
    return ((imm & 4095) << 20) | rs << 15 | f << 12 | rd << 7 | op

def rt(rd, f, a, b, high=0):
    return high << 25 | b << 20 | a << 15 | f << 12 | rd << 7 | 0x33

def st(f, a, b, imm):
    return ((imm & 4095) >> 5) << 25 | b << 20 | a << 15 | f << 12 | (imm & 31) << 7 | 0x23

def bt(f, a, b, offset):
    x = offset & 8191
    return (x >> 12) << 31 | ((x >> 5) & 63) << 25 | b << 20 | a << 15 | f << 12 | ((x >> 1) & 15) << 8 | ((x >> 11) & 1) << 7 | 0x63

def jt(rd, offset):
    x = offset & ((1 << 21) - 1)
    return (x >> 20) << 31 | ((x >> 1) & 1023) << 21 | ((x >> 11) & 1) << 20 | ((x >> 12) & 255) << 12 | rd << 7 | 0x6f

program = []
def emit(word):
    program.append(word)
    return (len(program) - 1) * 4

# Four independent instructions, dependencies inside a packet, and WAW chains.
for r, imm in [(1,-1),(2,1),(3,31),(4,0x400),(5,-128),(6,7),(7,12),(8,13)]:
    emit(it(0x13,r,0,0,imm))
emit(0x80000000 | 9 << 7 | 0x37)
emit(1 << 12 | 10 << 7 | 0x17)
for f in range(8):
    emit(rt(11+f,f,1,2))
emit(rt(19,0,2,1,0x20))
emit(rt(20,5,9,3,0x20))
for f in [0,2,3,4,6,7]:
    emit(it(0x13,21,f,1,-2))
for f, imm in [(1,31),(5,31),(5,0x41f)]:
    emit(it(0x13,22,f,9,imm))
emit(it(0x13,0,0,0,99))
# Every load/store width, signedness, offset, x0 load and load-use dependency.
emit(st(2,4,9,0))
emit(st(0,4,5,1))
emit(st(1,4,1,2))
for f, off in [(0,1),(4,1),(1,2),(5,2),(2,0)]:
    emit(it(3,23,f,4,off)); emit(rt(24,0,23,2))
emit(it(3,0,2,4,0))
emit(0x0ff0000f)
# Both outcomes for each conditional branch; taken skips observable writes.
for f, a, b in [(0,1,1),(1,1,2),(4,1,2),(5,2,1),(6,2,1),(7,1,2),
                (0,1,2),(1,1,1),(4,2,1),(5,1,2),(6,1,2),(7,2,1)]:
    emit(bt(f,a,b,8)); emit(it(0x13,25,0,25,1))
emit(it(0x13,26,0,0,3))
loop = len(program)*4
emit(it(0x13,26,0,26,-1)); emit(bt(1,26,0,loop-len(program)*4))
emit(jt(27,8)); emit(st(2,4,1,8))
# JALR clears bit 0 and redirects into the middle of a fetch block.
target = (len(program)+3)*4
emit(it(0x13,28,0,0,target|1)); emit(it(0x67,29,0,28,0)); emit(st(2,4,1,8))
emit(it(0x13,30,0,29,1))
# Independent deterministic instruction mix stresses forwarding and scoreboarding.
rng = random.Random(20261114)
for _ in range(400):
    rd,a,b = [rng.randrange(1,32) for _ in range(3)]
    f = rng.randrange(8)
    if rng.randrange(2):
        emit(rt(rd,f,a,b,0x20 if f in (0,5) and rng.randrange(2) else 0))
    else:
        imm = rng.randrange(-2048,2048)
        if f in (1,5): imm = rng.randrange(32) | (0x400 if f==5 and rng.randrange(2) else 0)
        emit(it(0x13,rd,f,a,imm))
# Faults resume at PC+4 in this test EEI. No faulting instruction retires.
emit(it(0x13,4,0,0,0x400)); emit(4 << 12 | 3 << 7 | 0x37)
for word in [it(3,5,2,4,1),st(1,4,1,1),it(3,0,2,3,0),st(2,3,1,0),
             jt(6,2),0xffffffff,0x00000073,0x00100073]:
    emit(word); emit(it(0x13,7,0,7,1))
if_error_pc = emit(it(0x13,8,0,8,1))
emit(it(0x13,9,0,9,1))
terminal_pc = emit(0x00100073)

regs = [0]*32
mem = bytearray(4096)
pc = 0
rows = []
coverage = set()
for step in range(10000):
    word = program[pc//4]
    op,rd,f,a,b,hi = word&127,(word>>7)&31,(word>>12)&7,(word>>15)&31,(word>>20)&31,word>>25
    av,bv = regs[a],regs[b]
    imm=sx(word>>20,12)
    value=0; write=False; fault=0; addr=0; memory=0; mw=0; mask=0; data=0; nxt=pc+4
    if pc==if_error_pc: fault,addr=2,pc
    elif op==0x37: value=word&0xfffff000; write=True; coverage.add('LUI')
    elif op==0x17: value=pc+(word&0xfffff000); write=True; coverage.add('AUIPC')
    elif op in (0x13,0x33):
        rhs=imm&MASK if op==0x13 else bv
        sh=rhs%32
        if f==0: value=av-rhs if op==0x33 and hi==32 else av+rhs
        elif f==1: value=av*(2**sh)
        elif f==2: value=int(sx(av,32)<sx(rhs,32))
        elif f==3: value=int(av<rhs)
        elif f==4: value=av^rhs
        elif f==5: value=sx(av,32)//(2**sh) if hi==32 else av//(2**sh)
        elif f==6: value=av|rhs
        elif f==7: value=av&rhs
        write=True; coverage.add(('ALU',op,f,hi if f==5 or (op==0x33 and f==0) else 0))
    elif op in (3,0x23):
        if op==0x23: imm=sx(((word>>25)<<5)|((word>>7)&31),12)
        addr=(av+imm)&MASK
        size={0:1,1:2,2:4,4:1,5:2}[f]
        memory=1; mw=int(op==0x23); mask=((1<<size)-1)<<(addr%4)
        coverage.add(('MEM',op,f))
        if addr%size: fault=7 if mw else 5
        elif addr+size>len(mem): fault=8 if mw else 6
        elif mw:
            mem[addr:addr+size]=(bv & ((1<<(size*8))-1)).to_bytes(size,'little')
            data=(bv*(256**(addr%4)))&MASK
        else:
            raw=int.from_bytes(mem[addr:addr+size],'little')
            value=sx(raw,size*8) if f in (0,1) else raw
            data=value&MASK; write=True
    elif op==0x63:
        off=sx(((word>>31)<<12)|(((word>>7)&1)<<11)|(((word>>25)&63)<<5)|(((word>>8)&15)<<1),13)
        yes={0:av==bv,1:av!=bv,4:sx(av,32)<sx(bv,32),5:sx(av,32)>=sx(bv,32),6:av<bv,7:av>=bv}[f]
        coverage.add(('BR',f,yes))
        if yes: nxt=pc+off
        if nxt%4: fault,addr=1,nxt
    elif op in (0x6f,0x67):
        off=sx(((word>>31)<<20)|(((word>>12)&255)<<12)|(((word>>20)&1)<<11)|(((word>>21)&1023)<<1),21)
        nxt=pc+off if op==0x6f else (av+imm)&0xfffffffe
        value=pc+4; write=True; coverage.add('JAL' if op==0x6f else 'JALR')
        if nxt%4: fault,addr=1,nxt
    elif op==0x0f: coverage.add('FENCE')
    elif word==0x73: fault=9; coverage.add('ECALL')
    elif word==0x100073: fault=4; coverage.add('EBREAK')
    else: fault,addr=3,word
    value &= MASK
    if fault:
        rows.append([1,pc,word,0,0,0,fault,addr,0,0,0,0])
        nxt=pc+4
    else:
        write=write and rd!=0
        # Decoder normalizes rd for instructions that do not write a register.
        rows.append([0,pc,word,int(write),rd if write else 0,value,0,addr,memory,mw,mask,data])
        if write: regs[rd]=value
    if pc==terminal_pc: break
    pc=nxt&MASK
else: raise AssertionError('oracle failed to terminate')
assert len(coverage) == 46, "40 operations plus both outcomes of six branches"
assert {row[6] for row in rows if row[0]} == set(range(1,10)), "all symbolic fault classes"
(OUT/'program.hex').write_text(''.join(f'{w:08x}\n' for w in program))
(OUT/'expected.txt').write_text(''.join(' '.join(f'{x& MASK:x}' for x in row)+'\n' for row in rows))
(OUT/'memory.hex').write_text(''.join(f'{b:02x}\n' for b in mem))
config = f'localparam int PROGRAM_WORDS={len(program)}, IF_ERROR_PC={if_error_pc}, TERMINAL_PC={terminal_pc}, EXPECTED_EVENTS={len(rows)};\n'
if not (OUT/'config.svh').exists() or (OUT/'config.svh').read_text()!=config:
    (OUT/'config.svh').write_text(config)
print(f'Generated {len(program)} words, {len(rows)} architectural events, {len(coverage)} coverage keys')
