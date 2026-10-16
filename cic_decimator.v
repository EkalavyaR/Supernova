`timescale 1ns / 1ps
//   fs  --> [N integrators] --> (down-sample by R) --> [N combs] --> scale/round/sat --> 20 bit
//   * Output stage: gain GAIN_NUM / 2^GAIN_FRAC, round-half-up, saturate to OUT_W.
//     With gain 1 a full-scale (+/-1) input maps to +/-2^(OUT_W-1).
//     (The benchmark tones peak at ~0.28 of full scale, so gain 3.5 is safe and
//      uses the 20-bit range; 'clip' pulses if a sample is ever saturated.)

module cic_decimator #(
    parameter integer N         = 3,      
    parameter integer R         = 2048,   
    parameter integer M         = 1,      
    parameter integer IN_WIDTH  = 2,      // as the input is signed 
    parameter integer OUT_W     = 20,     // output width 
    parameter integer GAIN_NUM  = 7,      // output gain numerator   
    parameter integer GAIN_FRAC = 1       // output gain = GAIN_NUM / 2^GAIN_FRAC
)(
    input  wire                        clk,
    input  wire                        rst_n,         
    input  wire                        in_valid,      
    input  wire signed [IN_WIDTH-1:0]  in_data,
    output reg                         out_valid,     
    output reg  signed [OUT_W-1:0]     out_data_w,    // decimated, scaled and saturated output 
    output reg                         clip           // 1-clk pulse if output saturated past 20 bit value
);
    
    localparam integer LOG2RM = $clog2(R*M);
    localparam integer BMAX   = IN_WIDTH + N*LOG2RM;              // Hogenauer bound
    localparam integer CNT_W  = (R > 1) ? $clog2(R) : 1;
    localparam integer GW     = BMAX + 9;                         // headroom for gain < 2^8
    localparam integer SH     = N*LOG2RM - (OUT_W-1) + GAIN_FRAC;

    reg signed [BMAX-1:0] int_reg [0:N-1];
    wire signed [BMAX-1:0] in_extended = {{(BMAX-IN_WIDTH){in_data[IN_WIDTH-1]}}, in_data};
    integer i;
    //integrators
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) int_reg[i] <= {BMAX{1'b0}};
        end else if (in_valid) begin
            int_reg[0] <= int_reg[0] + in_extended;
            for (i = 1; i < N; i = i + 1)
                int_reg[i] <= int_reg[i] + int_reg[i-1];          
        end
    end
    //down-sampler
    reg  [CNT_W-1:0] rate_cnt;
    wire             strobe = in_valid && (rate_cnt == R-1);      

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                rate_cnt <= {CNT_W{1'b0}};
        else if (in_valid) begin
            if (strobe)            rate_cnt <= {CNT_W{1'b0}};
            else                   rate_cnt <= rate_cnt + 1'b1;
        end
    end

    // combs
    // cw[0] = decimated last-integrator sample, cw[k+1] = output of comb stage k.
    // comb_dly[k*M + m] = m-th delay element of comb stage k.
    reg  signed [BMAX-1:0] comb_dly [0:N*M-1];
    wire signed [BMAX-1:0] cw       [0:N];
    assign cw[0] = int_reg[N-1];

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_comb
            assign cw[g+1] = cw[g] - comb_dly[g*M + (M-1)];
        end
    endgenerate

    reg signed [BMAX-1:0] raw;           // comb output, held between strobes
    reg                   raw_valid;
    integer k, m;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw       <= {BMAX{1'b0}};
            raw_valid <= 1'b0;
            for (k = 0; k < N*M; k = k + 1) comb_dly[k] <= {BMAX{1'b0}};
        end else begin
            raw_valid <= 1'b0;
            if (strobe) begin
                for (k = 0; k < N; k = k + 1) begin
                    comb_dly[k*M] <= cw[k];                       // stage input -> delay line
                    for (m = 1; m < M; m = m + 1)
                        comb_dly[k*M + m] <= comb_dly[k*M + m - 1];
                end
                raw       <= cw[N];
                raw_valid <= 1'b1;
            end
        end
    end

    // gain, round-half-up, saturate,
    localparam signed [GW-1:0] ROUND = {{(GW-1){1'b0}}, 1'b1} << (SH-1);
    localparam signed [GW-1:0] MAXV  =  ({{(GW-1){1'b0}}, 1'b1} << (OUT_W-1)) - 1;
    localparam signed [GW-1:0] MINV  = -({{(GW-1){1'b0}}, 1'b1} << (OUT_W-1));

    wire signed [GW-1:0] raw_ext = {{(GW-BMAX){raw[BMAX-1]}}, raw};
    wire signed [GW-1:0] prod    = raw_ext * GAIN_NUM;            
    wire signed [GW-1:0] scaled  = (prod + ROUND) >>> SH;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data_w <= {OUT_W{1'b0}};
            out_valid    <= 1'b0;
            clip         <= 1'b0;
        end else begin
            out_valid <= raw_valid;
            clip      <= 1'b0;
            if (raw_valid) begin
                if (scaled > MAXV) begin
                    out_data_w <= MAXV[OUT_W-1:0];
                    clip         <= 1'b1;
                end else if (scaled < MINV) begin
                    out_data_w <= MINV[OUT_W-1:0];
                    clip         <= 1'b1;
                end else begin
                    out_data_w <= scaled[OUT_W-1:0];
                end
            end
        end
    end
endmodule
