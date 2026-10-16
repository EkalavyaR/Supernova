`timescale 1ns / 1ps
// Select the tone with the TONE define below (10 / 500 / 990) or from the
// Outputs: cic2048_<TONE>.txt        (sampled on clk3, 1 per output period) -> fft_2.m
//          cic2048_<TONE>_valid.txt  (logged on the out_valid strobe)

`ifndef TONE
  `define TONE 10
`endif

module cic_tb();
 reg data [0:4096025];

 reg clk,clk2,clk3,clk4, reset,enable;
 wire outready,outready2;
 wire clip;

 reg signed [1:0] bits;

 wire signed [19:0] cicout; // 20-bit CIC output
 wire signed [19:0] firout; // not used in Task 1
 assign firout = 20'sd0;

 reg [8*64:1] fin_name, fout_clk3, fout_valid;
 initial begin
  $sformat(fin_name,   "hz%0d.mem",              `TONE);
  $sformat(fout_clk3,  "cic2048_%0d.txt",        `TONE);
  $sformat(fout_valid, "cic2048_%0d_valid.txt",  `TONE);
  $readmemh(fin_name, data); // input data
 end

 initial begin
  clk=0;
  clk2=0;
  clk3=0;
  bits=0;
  enable=0;
  reset = 1;
  #51 reset = 0;
  enable=1;
 end

 always #50 clk=~clk;
 always #25600 clk2=~clk2;   // (unused in Task 1)
 always #102400 clk3=~clk3;  // output rate fs/2048 (period = 2048 clk)

 integer i;
 initial i = 0;

 integer fd1,fd2,fd3,fd4;
 initial begin
  fd1 = $fopen("bits.txt","w");
  fd2 = $fopen(fout_valid,"w");    // logged on out_valid strobe
  fd3 = $fopen("fircomp.txt","w"); // unused in Task 1
  fd4 = $fopen(fout_clk3,"w");     // sampled on clk3 
 end

 // RACE FIX: 'bits' is driven with a NON-blocking assignment, so the DUT (which samples
 // on the same posedge) always sees the previous value, independent of simulator ordering.
 always @(posedge clk) begin
  if (i < 4096026) begin
   if(i%2==0)begin
    bits <= {1'b0,data[i]};
   end else begin
    bits <= {2{data[i]}};
   end
   i <= i + 1;
  end else begin
   #200;
   $finish;
  end
 end

 always @(posedge clk) begin
  $fwrite(fd1, "%d\n", bits);
 end
 always @(posedge clk) begin
  if(outready) begin
   $fwrite(fd2, "%d\n", $signed(cicout)); 
  end
 end
 always @(posedge clk2) begin
  $fwrite(fd3, "%d\n", $signed(firout));
 end
 always @(posedge clk3) begin
  $fwrite(fd4, "%d\n", $signed(cicout));  // 20-bit output logged on clk3
 end

 //cic instantiation 
 cic_decimator #(
     .N(3),
     .R(2048),
     .M(1),
     .IN_WIDTH(2),
     .OUT_W(20),
     .GAIN_NUM(7),
     .GAIN_FRAC(1)
 ) cic_inst (
     .clk(clk),
     .rst_n(~reset),       // active-high reset -> active-low
     .in_valid(enable),
     .in_data(bits),
     .out_valid(outready),
     .out_data_w(cicout),
     .clip(clip)
 );
endmodule
