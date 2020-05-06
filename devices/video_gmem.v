`timescale 1ns / 1ps

module axi_video_gmem
    #(
        parameter
        WIDTH = 800,
        HEIGHT = 480
    )
    (
           input async_reset,
           input sys_clock,
           input video_clock,

           // mem interface

           input [31: 0] i_gmem_addr,
           output reg [31: 0] or_vaddr,
           output [31: 0] o_vlen,
           output reg or_vreq,
           input i_vbusy,
           input [63: 0] i_vdata,
           input i_vvalid,
           output w_vready,

           // lcd logic

           input i_lcd_de,
           input i_lcd_vsync,
           output reg [23:0] or_lcd_data
       );
(*mark_debug="true"*)wire[23: 0] lcd_monitor;
assign lcd_monitor = or_lcd_data;
// four line buf bytes, 3 bytes one pixel
localparam LINED = WIDTH * 3;
// total gmem bytes, 2 line
localparam TOTALD = LINED * HEIGHT;
// bram size, 2 line, four pixel per unit
localparam BRSIZE = WIDTH / 4;
// bram step
localparam BRSTEP = BRSIZE / 2;

(*mark_debug="true"*)reg [ 8: 0] r_br_addra, r_br_addrb;
(*mark_debug="true"*)reg [191: 0] r_br_dina;
wire[191: 0] w_br_doutb;
reg         r_br_wea;
(*mark_debug="true"*)wire [ 1: 0] w_tik_tok;

// one frame is a sync clock
wire frame_sync;
assign frame_sync = async_reset & i_lcd_vsync;

// input logic
assign o_vlen = LINED ; // lock to 1 line data one batch
assign w_vready = 1'b1;

localparam S_WAIT = 1'b0;
localparam S_DATA = 1'b1;
reg s_state;
(*mark_debug="true"*)reg [ 1: 0] r_wpos_idx;
(*mark_debug="true"*)reg [ 8: 0] r_woff_walker;
reg r_br_wea_follow;

assign w_tik_tok[0] = r_br_addra < BRSTEP;

always@(posedge sys_clock or negedge async_reset) begin
    if (!async_reset) begin
        r_wpos_idx <= 0;
        r_woff_walker <= 0;
        r_br_wea_follow <= 0;
        r_br_wea <= 0;
        r_br_addra <= 0;
        s_state <= S_WAIT;
        or_vaddr <= i_gmem_addr;
    end else begin
        // addr increment logic
        if (r_br_wea_follow ^ r_br_wea) begin
            // inc by 1 when wea is 1
            if(r_br_addra < BRSIZE - 1)begin
                r_br_addra <= r_br_addra + 1;
            end else begin
                r_br_addra <= 0;
            end
            r_br_wea_follow <= r_br_wea;
        end
        // state control
        case(s_state)
            S_WAIT:begin
                r_woff_walker <= 0;
                if(w_tik_tok[0] ^ w_tik_tok[1]) begin
                    or_vreq <= 1'b1;
                    if (i_vbusy) begin
                        s_state <= S_DATA;
                    end
                end
            end
            S_DATA:begin
                or_vreq <= 1'b0;
                if(i_vvalid) begin
                    case(r_wpos_idx)
                        2'b00: begin
                            r_br_dina[63: 0] <= i_vdata;
                        end
                        2'b01: begin
                            r_br_dina[127:64] <= i_vdata;
                        end
                        2'b10: begin
                            r_br_dina[191:128] <= i_vdata;
                        end
                    endcase
                    if (r_wpos_idx < 2) begin
                        r_wpos_idx <= r_wpos_idx + 1;
                    end else begin
                        r_wpos_idx <= 0;
                        r_br_wea <= ~r_br_wea;
                        if (r_woff_walker < BRSTEP - 1) begin
                            r_woff_walker <= r_woff_walker + 1;
                        end else begin
                            s_state <= S_WAIT;
                            if (or_vaddr < TOTALD - LINED) begin
                                or_vaddr <= or_vaddr + LINED;
                            end else begin
                                or_vaddr <= i_gmem_addr;
                            end
                        end
                    end
                end
            end
        endcase
    end
end

// output logic
reg [ 2: 0] r_rpos_idx;
reg [ 9: 0] r_roff_walker;

assign w_tik_tok[1] = r_br_addrb < BRSTEP;

always@(posedge video_clock or negedge frame_sync) begin
    if (!frame_sync) begin
        r_br_addrb <= 0;
        r_roff_walker <= 0;
        r_rpos_idx <= 0;
    end else begin
        if (i_lcd_de) begin
            case (r_rpos_idx)
                0: begin
                    or_lcd_data <= w_br_doutb[23: 0];
                end
                1: begin
                    or_lcd_data <= w_br_doutb[47: 24];
                end
                2: begin
                    or_lcd_data <= w_br_doutb[71: 48];
                end
                3: begin
                    or_lcd_data <= w_br_doutb[95: 72];
                end
                4: begin
                    or_lcd_data <= w_br_doutb[119: 96];
                end
                5: begin
                    or_lcd_data <= w_br_doutb[143:120];
                end
                6: begin
                    or_lcd_data <= w_br_doutb[167:144];
                end
                7: begin
                    or_lcd_data <= w_br_doutb[191:168];
                end
            endcase
            if(r_rpos_idx < 7)begin
                r_rpos_idx <= r_rpos_idx + 1;
            end else begin
                r_rpos_idx <= 0;
                if (r_br_addrb < BRSIZE - 1) begin
                    r_br_addrb <= r_br_addrb + 1;
                end else begin
                    r_br_addrb <= 0;
                end
            end
        end
    end
end

blk_mem_gen_0 bmem(
    .clka(sys_clock),
    .wea(r_br_wea ^ r_br_wea_follow),
    .addra(r_br_addra),
    .dina(r_br_dina),
    .clkb(video_clock),
    .addrb(r_br_addrb),
    .doutb(w_br_doutb)
);

endmodule
