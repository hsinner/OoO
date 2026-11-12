"""Independent Python integer oracle for the real SystemVerilog ALU."""
from pathlib import Path
import random

MASK = 0xffffffff
OPS = "ADD ADDI AUIPC SUB LUI AND ANDI OR ORI XOR XORI SLL SLLI SRL SRLI SRA SRAI SLT SLTI SLTU SLTIU".split()
OTHER = "ILLEGAL BEQ BNE BLT BGE BLTU BGEU JAL JALR LB LH LW LBU LHU SB SH SW FENCE ECALL EBREAK".split()


def signed(value):
    return value if value < 0x80000000 else value - (1 << 32)


def expected(op, a, b):
    # Python unbounded integers make truncation explicit. Division implements
    # right shifts independently of the SV shift expressions, including floor
    # division for negative arithmetic-shift operands.
    shift = b % 32
    if op in ("ADD", "ADDI", "AUIPC"):
        value = a + b
    elif op == "SUB":
        value = a - b
    elif op == "LUI":
        value = b
    elif op in ("AND", "ANDI"):
        value = a & b
    elif op in ("OR", "ORI"):
        value = a | b
    elif op in ("XOR", "XORI"):
        value = a ^ b
    elif op in ("SLL", "SLLI"):
        value = a * (2 ** shift)
    elif op in ("SRL", "SRLI"):
        value = a // (2 ** shift)
    elif op in ("SRA", "SRAI"):
        value = signed(a) // (2 ** shift)
    elif op in ("SLT", "SLTI"):
        value = int(signed(a) < signed(b))
    elif op in ("SLTU", "SLTIU"):
        value = int(a < b)
    else:
        value = 0
    return value & MASK


def main():
    path = Path("build/alu/vectors.txt")
    path.parent.mkdir(parents=True, exist_ok=True)
    boundaries = [0, 1, 2, 7, 9, 31, 32, 33, 0x7ffffffe, 0x7fffffff,
                  0x80000000, 0x80000001, 0xfffffffe, MASK, 0xaaaaaaaa, 0x55555555]
    rng = random.Random(0x32a1)
    count = 0
    with path.open("w", encoding="ascii", newline="\n") as out:
        def emit(op, a, b):
            nonlocal count
            out.write(f"OP_{op} {a:08x} {b:08x} {expected(op, a, b):08x}\n")
            count += 1

        for op in OPS:
            for a in boundaries:
                for b in boundaries:
                    emit(op, a, b)
            for _ in range(256):
                emit(op, rng.getrandbits(32), rng.getrandbits(32))
        for op in ("SLL", "SLLI", "SRL", "SRLI", "SRA", "SRAI"):
            for a in boundaries:
                for shift in range(32):
                    for upper in (0, 0xffffffe0):
                        emit(op, a, upper | shift)
        for op in OTHER:
            emit("ADD", 7, 9)  # Nonzero result before default checks stale output.
            emit(op, MASK, MASK)
        # Explicit oracle sanity checks using independently stated expectations.
        assert expected("ADD", MASK, 1) == 0
        assert expected("SRA", 0x80000001, 1) == 0xc0000000
        assert expected("SLTU", 0x80000000, MASK) == 1
    print(f"Generated {count} ALU vectors (seed 0x32a1)")


if __name__ == "__main__":
    main()
