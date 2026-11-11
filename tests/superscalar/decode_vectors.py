"""Generate independent encode-to-decode vectors; no substitute DUT.

Encoding table follows RV32I v2.1. Expected operands/immediates come from the
inputs to the encoder, not extraction expressions copied from the RTL decoder.
Run from the repository root; check_decode.sh consumes the generated file.
"""
from pathlib import Path

# Name, encoding format, opcode, funct3, funct7.
OPS = [
    ("LUI", "U", 0x37, 0, 0), ("AUIPC", "U", 0x17, 0, 0),
    ("JAL", "J", 0x6f, 0, 0), ("JALR", "I", 0x67, 0, 0),
]
OPS += [(n, "R", 0x33, f, g) for n, f, g in [
    ("ADD", 0, 0), ("SUB", 0, 32), ("SLL", 1, 0), ("SLT", 2, 0),
    ("SLTU", 3, 0), ("XOR", 4, 0), ("SRL", 5, 0), ("SRA", 5, 32),
    ("OR", 6, 0), ("AND", 7, 0)]]
OPS += [(n, "I", 0x13, f, 0) for n, f in [
    ("ADDI", 0), ("SLTI", 2), ("SLTIU", 3), ("XORI", 4), ("ORI", 6), ("ANDI", 7)]]
OPS += [(n, "H", 0x13, f, g) for n, f, g in [
    ("SLLI", 1, 0), ("SRLI", 5, 0), ("SRAI", 5, 32)]]
OPS += [(n, "B", 0x63, f, 0) for n, f in [
    ("BEQ", 0), ("BNE", 1), ("BLT", 4), ("BGE", 5), ("BLTU", 6), ("BGEU", 7)]]
OPS += [(n, "I", 0x03, f, 0) for n, f in [
    ("LB", 0), ("LH", 1), ("LW", 2), ("LBU", 4), ("LHU", 5)]]
OPS += [(n, "S", 0x23, f, 0) for n, f in [("SB", 0), ("SH", 1), ("SW", 2)]]


def encode(spec, rd, rs1, rs2, imm):
    _, fmt, opcode, f3, f7 = spec
    word = opcode
    if fmt in ("R", "I", "H", "U", "J"):
        word |= rd << 7
    if fmt in ("R", "I", "H", "S", "B"):
        word |= rs1 << 15 | f3 << 12
    if fmt == "R":
        word |= rs2 << 20 | f7 << 25
    elif fmt == "H":
        word |= imm << 20 | f7 << 25
    elif fmt == "I":
        word |= (imm & 4095) << 20
    elif fmt == "U":
        word |= imm & 0xfffff000
    elif fmt == "S":
        word |= rs2 << 20 | (imm & 31) << 7 | ((imm & 4095) >> 5) << 25
    elif fmt in ("B", "J"):
        # Deposit bits using an architectural immediate-bit -> instruction-bit map.
        mapping = ({12: 31, 11: 7, **{i: i + 20 for i in range(5, 11)},
                    **{i: i + 7 for i in range(1, 5)}} if fmt == "B" else
                   {20: 31, 11: 20, **{i: i for i in range(12, 20)},
                    **{i: i + 20 for i in range(1, 11)}})
        for src, dst in mapping.items():
            word |= ((imm >> src) & 1) << dst
        if fmt == "B":
            word |= rs2 << 20
    return word


def main():
    destination = Path("build/decode/vectors.txt")
    destination.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    covered = set()
    with destination.open("w", encoding="ascii", newline="\n") as out:
        def emit(word, name, rs1=0, rs2=0, rd=0, u1=0, u2=0, wr=0,
                 serial=0, imm=0, fault="FAULT_NONE", address=0):
            nonlocal count
            out.write(f"{word:08x} OP_{name} {rs1} {rs2} {rd} {u1} {u2} {wr} "
                      f"{serial} {imm & 0xffffffff:08x} {int(fault != 'FAULT_NONE')} "
                      f"{fault} {address:08x}\n")
            covered.add(name)
            count += 1

        def illegal(word):
            emit(word, "ILLEGAL", serial=1, fault="FAULT_ILLEGAL", address=word)

        def legal(spec, rd=5, rs1=9, rs2=17, imm=0):
            name, fmt, opcode, _, _ = spec
            u1 = int(fmt in ("R", "I", "H", "S", "B"))
            u2 = int(fmt in ("R", "S", "B"))
            dest = rd if fmt not in ("S", "B") else 0
            emit(encode(spec, rd, rs1, rs2, imm), name,
                 rs1 if u1 else 0, rs2 if u2 else 0, dest, u1, u2, int(dest != 0),
                 int(opcode in (0x6f, 0x67, 0x63, 0x03, 0x23)),
                 imm if fmt != "R" else 0)

        for spec in OPS:
            fmt = spec[1]
            # Exercise every register index independently, including x0 and x31.
            for reg in range(32):
                legal(spec, rd=reg)
                legal(spec, rs1=reg)
                legal(spec, rs2=reg)
            # Exhaust signed I/S/B immediates and all shift amounts. U/J use
            # boundaries and each individual bit to expose permutation mistakes.
            values = {"R": [0], "I": range(-2048, 2048), "S": range(-2048, 2048),
                      "B": range(-4096, 4096, 2), "H": range(32),
                      "U": [0, 0xfffff000] + [1 << b for b in range(12, 32)],
                      "J": [-1048576, -2, 0, 2, 1048574]
                           + [1 << b for b in range(1, 20)]}
            for imm in values[fmt]:
                legal(spec, imm=imm)

        # Every OP funct7/funct3 combination: all extensions/reserved forms fail.
        r_table = {(s[4], s[3]): s for s in OPS if s[1] == "R"}
        h_table = {(s[4], s[3]): s for s in OPS if s[1] == "H"}
        for f7 in range(128):
            for f3 in range(8):
                word = f7 << 25 | 17 << 20 | 9 << 15 | f3 << 12 | 5 << 7 | 0x33
                if (f7, f3) in r_table:
                    legal(r_table[f7, f3])
                else:
                    illegal(word)
            for f3 in (1, 5):
                word = f7 << 25 | 31 << 20 | 9 << 15 | f3 << 12 | 5 << 7 | 0x13
                if (f7, f3) in h_table:
                    legal(h_table[f7, f3], imm=31)
                else:
                    illegal(word)

        for opcode in (0x03, 0x23, 0x63, 0x67):
            legal_f3 = {s[3] for s in OPS if s[2] == opcode}
            for f3 in set(range(8)) - legal_f3:
                illegal(0xfff00000 | 9 << 15 | f3 << 12 | 5 << 7 | opcode)
        supported = {s[2] for s in OPS} | {0x0f, 0x73}
        for opcode in set(range(128)) - supported:
            illegal(0xdeadbe80 | opcode)

        # FENCE ignores all twelve fm/pred/succ bits and the encoded rd/rs1.
        for upper in range(4096):
            emit(upper << 20 | 31 << 15 | 31 << 7 | 0x0f, "FENCE", serial=1)
        for f3 in range(1, 8):
            illegal(f3 << 12 | 0x0f)  # Includes FENCE.I.

        for upper in range(4096):
            word = upper << 20 | 0x73
            if upper < 2:
                emit(word, "ECALL" if upper == 0 else "EBREAK", serial=1,
                     fault="FAULT_ECALL" if upper == 0 else "FAULT_BREAKPOINT")
            else:
                illegal(word)
        for base in (0x73, 0x100073):
            for reg in range(1, 32):
                illegal(base | reg << 7)
                illegal(base | reg << 15)
            for f3 in range(1, 8):
                illegal(base | f3 << 12)
        # Known assembly word, independent of the encoder above, then illegal
        # and legal again to exercise clearing of the default fault record.
        for word in (0x00700293, 0xffffffff, 0x00700293):
            if word == 0xffffffff:
                illegal(word)
            else:
                emit(word, "ADDI", rd=5, u1=1, wr=1, imm=7)
    assert len(covered - {"ILLEGAL"}) == 40
    print(f"Generated {count} decoder vectors covering all 40 operations")


if __name__ == "__main__":
    main()
