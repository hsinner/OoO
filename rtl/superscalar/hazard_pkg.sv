package hazard_pkg;
  localparam int SOURCES = 8;    // Four lanes, two architectural sources each.
  localparam int PRODUCERS = 16; // Four lanes in EX, MEM, WB and C.
  typedef struct packed {
    logic used;
    logic [4:0] rs;
    logic busy;
    logic [31:0] fallback_value; // R snapshot maintained by commit refresh.
  } source_t;
  typedef struct packed {
    logic valid, writes_rd, killed, fault, ready;
    logic [4:0] rd;
    logic [31:0] value;
  } producer_t;
endpackage
