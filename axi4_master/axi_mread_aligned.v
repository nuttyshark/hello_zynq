module axi_master_v4_read
(
    input async_reset,
    input sys_clock,
    // Master read addr
    output reg [31: 0] or_ar_addr,
    output reg [7: 0] or_ar_len,
    output [2: 0] o_ar_size,
    output reg or_ar_valid,
    input i_ar_ready,
    // Master read data
    input [D_WIDTH - 1: 0] i_r_data,
    input [1: 0] i_r_resp,
    input i_r_last,
    input i_r_valid,
    output reg or_r_ready
);
endmodule