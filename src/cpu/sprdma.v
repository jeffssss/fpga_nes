///////////////////////////////////////////////////////////////////////////////////////////////////
// Module Name: sprdma
//
// Author:      Brian Bennett (brian.k.bennett@gmail.com)
// Create Date: 02/19/2012
//
// Description:
//
// Sprite DMA control block for an fpga-based NES emulator.  Designed for a Spartan 3E FPGA.
//
///////////////////////////////////////////////////////////////////////////////////////////////////
module sprdma
(
  input  wire        clk_in,         // 50MHz system clock signal
  input  wire        rst_in,         // reset signal
  input  wire [15:0] cpumc_a_in,     // cpu address bus in (to snoop cpu writes of 0x4014)
  input  wire [ 7:0] cpumc_din_in,   // cpumc din bus in (to snoop cpu writes of 0x4014)
  input  wire [ 7:0] cpumc_dout_in,  // cpumc dout bus in (to receive sprdma read data)
  input  wire        cpu_r_nw_in,    // cpu write enable (to snoop cpu writes of 0x4014)
  input  wire        cpumc_rdy_in,   // indicates if the cpumc is rdy for mem requests
  output wire        active_out,     // high when sprdma is active (de-assert cpu ready signal)
  output reg  [15:0] cpumc_a_out,    // cpu address bus out (for dma cpu mem reads/writes)
  output reg  [ 7:0] cpumc_d_out,    // cpu data bus out (for dma mem writes)
  output reg         cpumc_r_nw_out, // cpu r_nw signal out (for dma mem writes)
  output reg         cpumc_req       // initiate memory request to cpumc
);

// Symbolic state representations.
localparam [1:0] S_READY    = 2'h0,
                 S_ACTIVE   = 2'h1,
                 S_COOLDOWN = 2'h2;

reg [ 1:0] q_state, d_state; // current fsm state
reg [15:0] q_addr,  d_addr;  // current cpu address to be copied to sprite ram
reg [ 1:0] q_cnt,   d_cnt;   // counter to manage stages of dma copies
reg [ 7:0] q_data,  d_data;  // latch for data read from cpu mem

// Update FF state.
always @(posedge clk_in)
  begin
    if (rst_in)
      begin
        q_state <= S_READY;
        q_addr  <= 16'h0000;
        q_cnt   <= 2'h0;
        q_data  <= 8'h00;
      end
    else
      begin
        q_state <= d_state;
        q_addr  <= d_addr;
        q_cnt   <= d_cnt;
        q_data  <= d_data;
      end
  end

always @*
  begin
    // Default regs to current state.
    d_state = q_state;
    d_addr  = q_addr;
    d_cnt   = q_cnt;
    d_data  = q_data;

    // Default to no memory action.
    cpumc_a_out    = 16'h00;
    cpumc_d_out    = 8'h00;
    cpumc_r_nw_out = 1'b1;
    cpumc_req      = 1'b0;

    if (q_state == S_READY)
      begin
        // Detect write to 0x4014 to begin DMA.
        if ((cpumc_a_in == 16'h4014) && !cpu_r_nw_in)
          begin
            d_state = S_ACTIVE;
            d_addr  = { cpumc_din_in, 8'h00 };
          end
      end
    else if (q_state == S_ACTIVE)
      begin
        case (q_cnt)
          2'h0:
            begin
              cpumc_a_out = q_addr;
              cpumc_req   = 1'b1;
              d_cnt       = 2'h1;
            end
          2'h1:
            begin
              cpumc_a_out = q_addr;
              d_data      = cpumc_dout_in;

              if (cpumc_rdy_in)
                d_cnt     = 2'h2;
            end
          2'h2:
            begin
              cpumc_a_out    = 16'h2004;
              cpumc_d_out    = q_data;
              cpumc_r_nw_out = 1'b0;
              d_cnt          = 2'h0;

              if (q_addr[7:0] == 8'hff)
                d_state = S_COOLDOWN;
              else
                d_addr = q_addr + 1;
            end
        endcase
      end
    else if (q_state == S_COOLDOWN)
      begin
        if (cpu_r_nw_in)
          d_state = S_READY;
      end
  end

assign active_out = (q_state == S_ACTIVE);

endmodule
