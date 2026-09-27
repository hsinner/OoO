#include "Vooo_core.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <deque>
#include <iostream>
#include <random>
#include <stdexcept>

// Independent architectural interpreter: no DUT internal state is consulted.
struct Expected { uint32_t pc, instruction, rd, value; bool fault; };
static uint32_t arithmetic_right(uint32_t a, unsigned n) {
    if (!n) return a;
    return (a >> n) | ((a & 0x80000000u) ? (~0u << (32-n)) : 0u);
}
static Expected interpret(uint32_t ins, uint32_t pc, std::array<uint32_t,32>& r) {
    unsigned opcode=ins&127, rd=(ins>>7)&31, f=(ins>>12)&7;
    uint32_t a=r[(ins>>15)&31], b=r[(ins>>20)&31], out=0;
    unsigned high=ins>>25;
    bool bad=false;
    if (opcode==0x37) out=ins&0xfffff000u;
    else if (opcode==0x17) out=pc+(ins&0xfffff000u);
    else if (opcode==0x13 || opcode==0x33) {
        bool imm=opcode==0x13;
        if (imm) b=(ins>>20) | ((ins>>31) ? 0xfffff000u : 0u);
        bad=imm ? ((f==1 && high!=0) || (f==5 && high!=0 && high!=32))
                : (high!=0 && !(high==32 && (f==0 || f==5)));
        switch(f) {
            case 0: out=(!imm && high==32) ? a-b : a+b; break;
            case 1: out=a<<(b&31); break;
            case 2: out=(a^0x80000000u)<(b^0x80000000u); break;
            case 3: out=a<b; break;
            case 4: out=a^b; break;
            case 5: out=(ins&(1u<<30)) ? arithmetic_right(a,b&31) : a>>(b&31); break;
            case 6: out=a|b; break;
            case 7: out=a&b; break;
        }
    } else bad=true;
    if (!bad && rd) r[rd]=out;
    return {pc,ins,rd,out,bad};
}
static uint32_t addi(unsigned rd,unsigned rs,int imm) {
    return ((uint32_t(imm)&4095)<<20)|(rs<<15)|(rd<<7)|0x13;
}
int main(int argc,char** argv) {
    Verilated::commandArgs(argc,argv);
    Vooo_core dut;
    std::mt19937 rng(0x52495343);
    unsigned retired=0, cycles=0;
    bool saw_ooo=false, saw_full=false;
    try {
      // Multiple resets exercise cold start and recovery from terminal faults.
      for (unsigned scenario=0; scenario<18; ++scenario) {
        dut.rst_i=1; dut.instruction_valid_i=0; dut.retire_ready_i=0;
        dut.clk_i=0; dut.eval(); dut.clk_i=1; dut.eval(); dut.rst_i=0;
        std::array<uint32_t,32> regs{};
        std::deque<Expected> expected;
        std::deque<unsigned> issue_order;
        unsigned sent=0, received=0;
        const unsigned total=scenario==0 ? 9 : 1201;
        bool pending=false;
        uint32_t instruction=0;
        bool stalled=false;
        Expected held{};
        for (unsigned local=0; received<total && local<100000; ++local) {
          if (!pending && sent<total && (rng()%5!=0)) {
            if (sent==total-1) {
              const uint32_t illegal[]={0xffffffffu,0x00000073u,0x00002083u,
                0x02000033u,0x02001013u,0x02005013u,0x40001033u,0x00000063u};
              instruction=illegal[scenario%8];
            } else if (scenario==0) {
              const uint32_t directed[]={addi(1,0,10),addi(2,1,1),addi(3,0,7),
                addi(1,0,99),addi(4,2,-1),addi(0,1,2),addi(5,0,0),addi(6,1,0)};
              instruction=directed[sent];
            } else {
              unsigned rd=rng()%32, rs1=rng()%32, rs2=rng()%32, f=rng()%8;
              unsigned kind=rng()%5;
              if (kind==0) instruction=(rng()&0xfffff000u)|(rd<<7)|((rng()%2)?0x37:0x17);
              else if (kind<=2) {
                unsigned imm=rng()%4096;
                if (f==1) imm=rng()%32;
                if (f==5) imm=(rng()%32)|((rng()%2)*1024);
                instruction=(imm<<20)|(rs1<<15)|(f<<12)|(rd<<7)|0x13;
              } else {
                unsigned high=(f==0||f==5) ? (rng()%2)*32 : 0;
                instruction=(high<<25)|(rs2<<20)|(rs1<<15)|(f<<12)|(rd<<7)|0x33;
              }
            }
            pending=true;
          }
          dut.instruction_valid_i=pending;
          dut.instruction_i=instruction; dut.pc_i=0x80000000u+4*sent;
          // A long initial stall fills the ROB; random stalls follow.
          dut.retire_ready_i=local>30 && rng()%4!=0;
          dut.clk_i=0; dut.eval();
          bool push=pending && dut.instruction_ready_o;
          bool pop=dut.retire_valid_o && dut.retire_ready_i;
          if (stalled && (!dut.retire_valid_o || dut.retire_pc_o!=held.pc ||
              dut.retire_instruction_o!=held.instruction || dut.retire_rd_o!=held.rd ||
              dut.retire_value_o!=held.value || bool(dut.retire_fault_o)!=held.fault))
            throw std::runtime_error("retirement payload changed while stalled");
          stalled=dut.retire_valid_o && !dut.retire_ready_i;
          if (stalled) held={dut.retire_pc_o,dut.retire_instruction_o,dut.retire_rd_o,
                            dut.retire_value_o,bool(dut.retire_fault_o)};
          if (pending && !dut.instruction_ready_o) saw_full=true;
          if (dut.issue_valid_o) {
            unsigned tag=dut.issue_tag_o;
            auto found=issue_order.begin();
            while (found!=issue_order.end() && *found!=tag) ++found;
            if (found==issue_order.end()) throw std::runtime_error("issue without allocation or duplicate issue");
            if (found!=issue_order.begin()) saw_ooo=true;
            issue_order.erase(found);
          }
          if (pop) {
            if (expected.empty()) throw std::runtime_error("unexpected retirement");
            auto e=expected.front(); expected.pop_front();
            if (dut.retire_pc_o!=e.pc || dut.retire_instruction_o!=e.instruction ||
                bool(dut.retire_fault_o)!=e.fault || dut.retire_rd_o!=e.rd ||
                (!e.fault && dut.retire_value_o!=e.value)) {
              std::cerr<<"scenario="<<scenario<<" received="<<received<<" pc="<<std::hex<<e.pc
                       <<" instruction="<<e.instruction<<" expected="<<e.value
                       <<" actual="<<dut.retire_value_o<<std::dec<<"\n";
              throw std::runtime_error("retirement mismatch");
            }
            ++received; ++retired;
          }
          if (push) {
            auto e=interpret(instruction,dut.pc_i,regs);
            expected.push_back(e);
            if (!e.fault) issue_order.push_back(sent%8);
            ++sent; pending=false;
          }
          dut.clk_i=1; dut.eval(); ++cycles;
        }
        if (received!=total) throw std::runtime_error("timeout / lost instruction");
        if (!dut.halted_o) throw std::runtime_error("fault did not halt");
        for (unsigned n=0;n<8;n++) {
          dut.clk_i=0; dut.eval();
          if (dut.retire_valid_o || dut.instruction_ready_o || dut.issue_valid_o)
            throw std::runtime_error("activity after halt");
          dut.clk_i=1; dut.eval();
        }
      }
      // Put younger work behind a fault; it may execute but must never retire.
      dut.rst_i=1; dut.clk_i=0; dut.eval(); dut.clk_i=1; dut.eval(); dut.rst_i=0;
      std::array<uint32_t,32> regs{};
      std::deque<Expected> expected;
      const uint32_t program[]={addi(1,0,1),addi(2,1,1),addi(3,2,1),
                               0xffffffffu,addi(1,0,77),addi(4,0,88),addi(5,4,1),addi(6,0,99)};
      unsigned sent=0, received=0;
      for (unsigned local=0;local<150;++local) {
        dut.instruction_valid_i=sent<8;
        dut.instruction_i=program[sent<8 ? sent : 7]; dut.pc_i=4*sent;
        dut.retire_ready_i=local>30;
        dut.clk_i=0; dut.eval();
        bool push=dut.instruction_valid_i && dut.instruction_ready_o;
        if (dut.retire_valid_o && dut.retire_ready_i) {
          if (received>=4 || expected.empty()) throw std::runtime_error("younger retirement after fault");
          auto e=expected.front(); expected.pop_front();
          if (dut.retire_pc_o!=e.pc || bool(dut.retire_fault_o)!=e.fault ||
              (!e.fault && dut.retire_value_o!=e.value)) throw std::runtime_error("ordered fault mismatch");
          ++received; ++retired;
        }
        if (push) {
          if (sent<=3) expected.push_back(interpret(program[sent],4*sent,regs));
          ++sent;
        }
        dut.clk_i=1; dut.eval(); ++cycles;
      }
      if (sent!=8 || received!=4 || !dut.halted_o) throw std::runtime_error("fault suffix coverage missing");
      // Reset again with a pending execution result, then verify no stale retirements.
      dut.rst_i=1; dut.clk_i=0; dut.eval(); dut.clk_i=1; dut.eval(); dut.rst_i=0;
      dut.instruction_valid_i=1; dut.instruction_i=addi(1,0,123); dut.pc_i=0;
      dut.clk_i=0; dut.eval(); dut.clk_i=1; dut.eval();
      dut.instruction_valid_i=0;
      dut.clk_i=0; dut.eval(); dut.clk_i=1; dut.eval();
      dut.rst_i=1; dut.clk_i=0; dut.eval(); dut.clk_i=1; dut.eval(); dut.rst_i=0;
      for (unsigned n=0;n<12;n++) {
        dut.clk_i=0; dut.eval();
        if (dut.retire_valid_o || dut.issue_valid_o || dut.halted_o || !dut.instruction_ready_o)
          throw std::runtime_error("reset failed to cancel in-flight work");
        dut.clk_i=1; dut.eval();
      }
      if (!saw_ooo || !saw_full) throw std::runtime_error("required coverage missing");
      std::cout<<"PASS: "<<retired<<" retirements, "<<cycles
               <<" cycles; OoO issue, backpressure, wraparound, faults and resets observed.\n";
    } catch (const std::exception& e) { std::cerr<<"FAIL: "<<e.what()<<"\n"; return 1; }
    dut.final();
}
