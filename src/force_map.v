`timescale 1ns / 1ps
//====================================================================
// force_map  v2 —— 删除可变除法，用常数比较器+温度计码替代
//   数学映射与原版一致：vel = 127 * ((raw-dead)/(raw_max-dead))^0.6
//   4级流水线，每级一个时钟周期
//====================================================================
module force_map #(
    parameter integer ADC_W = 12
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [ADC_W-1:0]     raw,
    input  wire [ADC_W-1:0]     dead,
    input  wire [ADC_W-1:0]     raw_max,
    output reg  [6:0]           velocity
);
    localparam integer PW = ADC_W + 8;  // 20位

    // 第一级：差值及分母保护
    reg [ADC_W-1:0] num_r, span_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            num_r  <= 0;
            span_r <= 1;
        end else begin
            num_r  <= (raw > dead) ? (raw - dead) : 0;
            span_r <= (raw_max > dead) ? (raw_max - dead) : 1;
        end
    end

    wire [PW-1:0] num_ext  = {{8{1'b0}}, num_r};
    wire [PW-1:0] span_ext = {{8{1'b0}}, span_r};

    // 第二级：常数乘法 num*255 和 span*(16*j)
    reg [PW-1:0] prod_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) prod_r <= 0;
        else        prod_r <= (num_ext << 8) - num_ext;  // num*255
    end

    wire [PW-1:0] threshold [1:15];
    genvar g;
    generate
        for (g = 1; g <= 15; g = g + 1) begin : GEN_THRESHOLD
            // Exact CSD shift/add form, no constant DSP multipliers.
            wire[PW-1:0]threshold_logic;
            if(g==1)assign threshold_logic=span_ext<<4;
            else if(g==2)assign threshold_logic=span_ext<<5;
            else if(g==3)assign threshold_logic=(span_ext<<5)+(span_ext<<4);
            else if(g==4)assign threshold_logic=span_ext<<6;
            else if(g==5)assign threshold_logic=(span_ext<<6)+(span_ext<<4);
            else if(g==6)assign threshold_logic=(span_ext<<7)-(span_ext<<5);
            else if(g==7)assign threshold_logic=(span_ext<<7)-(span_ext<<4);
            else if(g==8)assign threshold_logic=span_ext<<7;
            else if(g==9)assign threshold_logic=(span_ext<<7)+(span_ext<<4);
            else if(g==10)assign threshold_logic=(span_ext<<7)+(span_ext<<5);
            else if(g==11)assign threshold_logic=(span_ext<<7)+(span_ext<<5)+(span_ext<<4);
            else if(g==12)assign threshold_logic=(span_ext<<8)-(span_ext<<6);
            else if(g==13)assign threshold_logic=(span_ext<<8)-(span_ext<<5)-(span_ext<<4);
            else if(g==14)assign threshold_logic=(span_ext<<8)-(span_ext<<5);
            else assign threshold_logic=(span_ext<<8)-(span_ext<<4);
            reg [PW-1:0] threshold_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) threshold_r <= 0;
                else        threshold_r <= threshold_logic;
            end
            assign threshold[g] = threshold_r;
        end
    endgenerate

    // 第三级：并行比较，温度计码
    reg [15:1] ge_r;
    generate
        for (g = 1; g <= 15; g = g + 1) begin : GEN_COMPARE
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) ge_r[g] <= 1'b0;
                else        ge_r[g] <= (prod_r >= threshold[g]);
            end
        end
    endgenerate

    // 温度计码 → 索引 idx[3:0]
    wire [3:0] idx;
    assign idx[3] = ge_r[8];
    assign idx[2] = (ge_r[4] & ~ge_r[8]) | ge_r[12];
    assign idx[1] = (ge_r[2]  & ~ge_r[4])  |
                    (ge_r[6]  & ~ge_r[8])  |
                    (ge_r[10] & ~ge_r[12]) |
                     ge_r[14];
    assign idx[0] = (ge_r[1]  & ~ge_r[2])  |
                    (ge_r[3]  & ~ge_r[4])  |
                    (ge_r[5]  & ~ge_r[6])  |
                    (ge_r[7]  & ~ge_r[8])  |
                    (ge_r[9]  & ~ge_r[10]) |
                    (ge_r[11] & ~ge_r[12]) |
                    (ge_r[13] & ~ge_r[14]) |
                     ge_r[15];

    // 第四级：力度表
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) velocity <= 0;
        else begin
            case (idx)
                4'd0:  velocity <= 7'd0;
                4'd1:  velocity <= 7'd28;
                4'd2:  velocity <= 7'd42;
                4'd3:  velocity <= 7'd54;
                4'd4:  velocity <= 7'd65;
                4'd5:  velocity <= 7'd75;
                4'd6:  velocity <= 7'd84;
                4'd7:  velocity <= 7'd93;
                4'd8:  velocity <= 7'd101;
                4'd9:  velocity <= 7'd108;
                4'd10: velocity <= 7'd115;
                4'd11: velocity <= 7'd121;
                4'd12: velocity <= 7'd124;
                4'd13: velocity <= 7'd126;
                4'd14: velocity <= 7'd127;
                4'd15: velocity <= 7'd127;
                default: velocity <= 7'd0;
            endcase
        end
    end
endmodule
