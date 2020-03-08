`timescale 1ns / 1ps

module axi_master_v4_write_aligned
       #(
           parameter
           D_POWER = 3'b010, // 8bit pertransfer, 64b op
           D_WIDTH = 8*(1<<D_POWER),
           B_WIDTH = 1<<D_POWER
       )
       (
           input async_reset,
           input sys_clock,
           // ---- user
           input [31: 0] i_addr,
           input [31: 0] i_len,
           input i_req,
           output reg or_busy,
           input [D_WIDTH - 1: 0] i_data,
           input i_valid,
           output o_ready,
           // ---- axi
           // Master write addr
           output reg [31: 0] or_aw_addr,
           output reg [7: 0] or_aw_len,                    // Burst Length: 0-255
           output [2: 0] o_aw_size,                   // Burst Size: Fixed 2'b011
           output reg or_aw_valid,
           input i_aw_ready,
           // Master write data
           output reg [D_WIDTH - 1: 0] or_w_data,
           output o_w_last,
           output reg or_w_valid,
           output reg [B_WIDTH-1:0] or_w_strb,
           input i_w_ready,
           // Master write resp
           input [1: 0] i_b_resp,
           input i_b_valid,
           output reg or_b_ready
       );

// --- const output
assign o_aw_size = D_POWER;

// --- state machine
localparam S_IDLE = 2'b00;
localparam S_ADDR = 2'b01;
localparam S_DATA = 2'b11;
localparam S_RESP = 2'b10;
reg [1: 0] s_state;

// --- pair signal
reg[1:0] r_eat;

// --- debug signal
reg[31:0] d_ready_cnter, d_eat_cnter;

// --- inner signals
reg[31: 0] r_addr, r_len;
reg r_pre_load;
wire w_jump_running;
assign w_jump_running = r_len > 0?i_w_ready:1'b0;

assign o_ready = w_jump_running | (r_eat[0] ^ r_eat[1]);
assign o_w_last = or_aw_len == 0?or_w_valid:1'b0;

wire [ 7: 0] next_burst_len, next_burst;
wire [11: 0] next_burst_4k;
assign next_burst_len = r_len[31:D_POWER] > 255 ? 255 : r_len[D_POWER+7:D_POWER];
assign next_burst_4k = 12'hFFF - r_addr[11:0];
assign next_burst = next_burst_4k > next_burst_len ? next_burst_len : next_burst_4k[7:0];

always @ (posedge sys_clock or negedge async_reset) begin
    if (!async_reset) begin
        r_eat <= 2'b0;
        s_state <= S_IDLE;
        or_aw_valid <= 0;
        or_aw_addr <= 0;
        or_aw_len <= 0;
        or_b_ready <= 1'b0;
        or_w_strb <= {B_WIDTH{1'b1}};
        or_busy <= 1'b1;
        or_w_valid <= 1'b0;
        
        d_eat_cnter <= 0;
        d_ready_cnter <= 0;
    end else begin
        if(o_ready & i_valid) begin
            r_eat[0] <= r_eat[1];
            or_w_data <= i_data;
            d_eat_cnter <= d_eat_cnter + 1;
        end else if (w_jump_running & ~i_valid) begin
            r_eat[1] <= ~r_eat[1];
        end
        if(i_w_ready & ~o_ready) begin
            d_ready_cnter <= d_ready_cnter + 1;
        end
        case(s_state)
            S_IDLE: begin
                if(i_req) begin
                    or_busy <= 1'b1;
                    r_addr <= i_addr;
                    r_len <= i_len;
                    r_eat[1] <= ~r_eat[1];
                    s_state <= S_ADDR;
                end else begin
                    or_busy <= 1'b0;
                end
            end
            S_ADDR: begin
                or_aw_valid <= 1'b1;
                or_aw_addr <= r_addr;
                or_aw_len <= next_burst;
                if(i_aw_ready) begin
                    r_addr[31:D_POWER] <= r_addr[31:D_POWER] + or_aw_len + 1;
                    s_state = S_DATA;
                end
            end
            S_DATA: begin
                or_aw_valid <= 1'b0;
                if(i_w_ready & or_w_valid) begin
                    or_w_valid <= i_valid & o_ready;
                    if(or_aw_len > 0)begin
                        or_aw_len <= or_aw_len - 1;
                    end else begin
                        or_b_ready <= 1'b1;
                        s_state <= S_RESP;
                    end
                    if(r_len > 0) begin
                        r_len[31:D_POWER] <= r_len[31:D_POWER] - 1;
                    end
                end else if (~o_ready) begin
                    or_w_valid <= 1'b1;
                end else begin
                    or_w_valid <= 1'b0;
                end
            end
            S_RESP: begin
                or_w_valid <= 1'b0;
                if (i_b_valid) begin
                    or_b_ready <= 1'b0;
                    s_state <= r_len > 0?S_ADDR : S_IDLE;
                end
            end
        endcase
    end
end

endmodule