// SPDX-FileCopyrightText: © 2021-2024 Uri Shaked <uri@wokwi.com>
// SPDX-License-Identifier: MIT

`default_nettype none

module spell_mem_internal (
    input wire rst_n,
    input wire clk,
    input wire select,
    input wire [7:0] addr,
    input wire [7:0] data_in,
    input wire memory_type_data,
    input wire write,
    output wire [7:0] data_out,
    output reg data_ready
);

  localparam data_mem_size = 32;

  wire code_mem_lo_sel = !memory_type_data && addr[7] == 1'b0;
  wire code_mem_hi_sel = !memory_type_data && addr[7] == 1'b1;

  reg code_mem_ready;
  reg [4:0] code_mem_init_addr;

  wire [4:0] code_mem_addr = code_mem_ready ? addr[6:2] : code_mem_init_addr;
  wire [31:0] code_mem_lo_do;
  wire [31:0] code_mem_hi_do;
  reg [31:0] data_in_dword;
  wire [31:0] code_mem_di = code_mem_ready ? data_in_dword : 32'hffffffff;
  wire [31:0] code_mem_do = code_mem_lo_sel ? code_mem_lo_do : code_mem_hi_do;

  wire [4:0] word_index = {addr[1:0], 3'b000};
  wire [7:0] code_mem_out = code_mem_do[word_index+:8];
  reg [7:0] data_mem_out;
  wire [7:0] data_out_byte = memory_type_data ? data_mem_out : code_mem_out;
  assign data_out = data_ready ? data_out_byte : 8'bx;


  wire we = select && write;
  reg  prev_we;

  rf_top code_mem_lo (
      .clk(clk),
      .w_addr(code_mem_addr),
      .w_data(code_mem_di),
      .w_ena(~code_mem_ready || (we && code_mem_lo_sel)),
      .ra_addr(code_mem_addr),
      .ra_data(code_mem_lo_do),
      .rb_addr(5'b0)
  );

  rf_top code_mem_hi (
      .clk(clk),
      .w_addr(code_mem_addr),
      .w_data(code_mem_di),
      .w_ena(~code_mem_ready || (we && code_mem_hi_sel)),
      .ra_addr(code_mem_addr),
      .ra_data(code_mem_hi_do),
      .rb_addr(5'b0)
  );

  localparam data_mem_bits = $clog2(data_mem_size);
  reg [7:0] data_mem[data_mem_size-1:0];
  wire [data_mem_bits-1:0] data_addr = addr[data_mem_bits-1:0];

  always @(*) begin
    case (addr[1:0])
      2'b00: data_in_dword = {code_mem_do[31:8], data_in};
      2'b01: data_in_dword = {code_mem_do[31:16], data_in, code_mem_do[7:0]};
      2'b10: data_in_dword = {code_mem_do[31:24], data_in, code_mem_do[15:0]};
      2'b11: data_in_dword = {data_in, code_mem_do[23:0]};
    endcase
  end

  integer i;

  always @(posedge clk) begin
    if (~rst_n) begin
      data_ready   <= 0;
      data_mem_out <= 0;
      for (i = 0; i < data_mem_size; i++) data_mem[i] <= 8'h00;
      code_mem_ready <= 0;
      code_mem_init_addr <= 0;
      prev_we <= 1'b0;
    end else begin
      prev_we <= we;

      if (!code_mem_ready) begin
        code_mem_init_addr <= code_mem_init_addr + 1;
        if (code_mem_init_addr == 5'b11111) begin
          code_mem_ready <= 1;
        end
      end else if (!select) begin
        data_ready <= 1'b0;
      end else if (we && ~prev_we && ~memory_type_data) begin
        // For code memory writes, we first need to read the 32-bit word,
        // modify the relevant byte, and write it back.
        data_ready <= 1'b0;
      end else begin
        data_ready <= 1'b1;
        if (write) begin
          if (memory_type_data && addr < data_mem_size) begin
            data_mem[data_addr] <= data_in;
          end
        end else begin
          data_mem_out <= 8'h00;
          if (memory_type_data && addr < data_mem_size) begin
            data_mem_out <= data_mem[data_addr];
          end
        end
      end
    end
  end
endmodule
