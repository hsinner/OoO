// Buffered single-owner data bridge; owner persists through response consumption.
module memory_adapter (
  input logic clk_i, rst_i,
  input logic load_request_valid_i,
  input rv32_pkg::mem_request_t load_request_i,
  output logic load_request_ready_o,
  output logic load_response_valid_o,
  output rv32_pkg::mem_response_t load_response_o,
  input logic load_response_ready_i,
  input logic store_request_valid_i,
  input rv32_pkg::mem_request_t store_request_i,
  output logic store_request_ready_o,
  output logic store_response_valid_o,
  output rv32_pkg::mem_response_t store_response_o,
  input logic store_response_ready_i,
  output logic request_valid_o,
  output rv32_pkg::mem_request_t request_o,
  input logic request_ready_i,
  input logic response_valid_i,
  input rv32_pkg::mem_response_t response_i,
  output logic response_ready_o,
  output logic idle_o
);
  import rv32_pkg::*;
  typedef struct packed {
    logic [1:0] phase; // idle, held external request, wait response, held response
    logic store;
    mem_request_t request;
    mem_response_t response;
  } state_t;
  state_t q,d;
  always_comb begin
    idle_o=q.phase==0;
  end
  always_comb begin
    store_request_ready_o=q.phase==0 && !rst_i;
  end
  always_comb begin
    load_request_ready_o=q.phase==0 && !store_request_valid_i && !rst_i;
  end
  always_comb begin
    request_valid_o=q.phase==1 && !rst_i;
  end
  always_comb begin
    request_o=q.request;
  end
  always_comb begin
    response_ready_o=q.phase==2 && !rst_i;
  end
  always_comb begin
    store_response_valid_o=q.phase==3 && q.store && !rst_i;
  end
  always_comb begin
    load_response_valid_o=q.phase==3 && !q.store && !rst_i;
  end
  always_comb begin
    store_response_o=q.response;
  end
  always_comb begin
    load_response_o=q.response;
  end
  always_comb begin
    d=q;

    // Store priority is defensive; serialized integration must not have both.

    if (store_request_valid_i && store_request_ready_o) begin
      d.request=store_request_i; d.store=1; d.phase=1;
    end else if (load_request_valid_i && load_request_ready_o) begin
      d.request=load_request_i; d.store=0; d.phase=1;
    end
    if (request_valid_o && request_ready_i) d.phase=2;
    if (response_valid_i && response_ready_o) begin d.response=response_i; d.phase=3; end
    if ((store_response_valid_o && store_response_ready_i) ||
        (load_response_valid_o && load_response_ready_i)) d.phase=0;
    if (rst_i) d='0; // External endpoint must participate in reset.
  end
  always_ff @(posedge clk_i) begin
    q <= d;
  end
endmodule
