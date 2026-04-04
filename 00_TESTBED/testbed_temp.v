`timescale 1ns / 100ps
`define CYCLE 10.0



`define HCYCLE (`CYCLE/2)



`define MAX_CYCLE 10000000



`define RST_DELAY 2




`ifdef tb1
`define INFILE "../00_TESTBED/PATTERN/indata1.dat"



`define OPFILE "../00_TESTBED/PATTERN/opmode1.dat"



`define GOLDEN "../00_TESTBED/PATTERN/golden1.dat"



`elsif tb2
`define INFILE "../00_TESTBED/PATTERN/indata2.dat"



`define OPFILE "../00_TESTBED/PATTERN/opmode2.dat"



`define GOLDEN "../00_TESTBED/PATTERN/golden2.dat"



`elsif tb3
`define INFILE "../00_TESTBED/PATTERN/indata3.dat"



`define OPFILE "../00_TESTBED/PATTERN/opmode3.dat"



`define GOLDEN "../00_TESTBED/PATTERN/golden3.dat"



`else
`define INFILE "../00_TESTBED/PATTERN/indata0.dat"



`define OPFILE "../00_TESTBED/PATTERN/opmode0.dat"



`define GOLDEN "../00_TESTBED/PATTERN/golden0.dat"



`endif

`define SDFFILE "ipdc_syn.sdf"




module testbed;

  reg clk, rst_n;
  reg            i_op_valid;
  reg     [ 3:0] i_op_mode;
  wire           o_op_ready;
  reg            i_in_valid;
  reg     [23:0] i_in_data;
  wire           o_in_ready;
  wire           o_out_valid;
  wire    [23:0] o_out_data;

  reg     [23:0] indata_mem      [ 0:255];
  reg     [ 3:0] opmode_mem      [  0:63];
  reg     [23:0] golden_mem      [0:1023];

  integer        i;
  integer        num_ops;
  integer        num_golden;
  integer        op_idx;
  integer        golden_idx;
  integer        ready_pulse_cnt;
  integer        error_cnt;
  integer        load_idx;

  // ----------------------------------------------
  // Optional SDF
  // ----------------------------------------------
`ifdef SDF
  initial $sdf_annotate(`SDFFILE, u_ipdc);
  initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
`endif

  // ----------------------------------------------
  // Waveform
  // ----------------------------------------------
  initial begin
    $dumpfile("ipdc.vcd");
    $dumpvars(0, testbed);
  end

  // ----------------------------------------------
  // DUT
  // ----------------------------------------------
  ipdc u_ipdc (
      .i_clk      (clk),
      .i_rst_n    (rst_n),
      .i_op_valid (i_op_valid),
      .i_op_mode  (i_op_mode),
      .o_op_ready (o_op_ready),
      .i_in_valid (i_in_valid),
      .i_in_data  (i_in_data),
      .o_in_ready (o_in_ready),
      .o_out_valid(o_out_valid),
      .o_out_data (o_out_data)
  );

  // ----------------------------------------------
  // Pattern load
  // ----------------------------------------------
  initial $readmemb(`INFILE, indata_mem);
  initial $readmemb(`OPFILE, opmode_mem);
  initial $readmemb(`GOLDEN, golden_mem);

  // ----------------------------------------------
  // Helpers
  // ----------------------------------------------
  function is_x4;
    input [3:0] v;
    begin
      is_x4 = (^v === 1'bx);
    end
  endfunction

  function is_x24;
    input [23:0] v;
    begin
      is_x24 = (^v === 1'bx);
    end
  endfunction

  task send_one_op;
    input [3:0] mode;
    integer old_ready_cnt;
    begin
      old_ready_cnt = ready_pulse_cnt;

      // op_valid is only one cycle; inputs are sampled on falling edges
      @(negedge clk);
      i_op_valid = 1'b1;
      i_op_mode  = mode;
      i_in_valid = 1'b0;
      i_in_data  = 24'd0;

      @(negedge clk);
      i_op_valid = 1'b0;
      i_op_mode  = 4'd0;

      // load mode: stream 256 pixels, pause whenever o_in_ready = 0
      if (mode == 4'b0000) begin
        load_idx = 0;
        while (load_idx < 256) begin
          if (o_in_ready === 1'b1) begin
            i_in_valid = 1'b1;
            i_in_data  = indata_mem[load_idx];
            load_idx   = load_idx + 1;
          end else begin
            i_in_valid = 1'b0;
            i_in_data  = 24'd0;
          end
          @(negedge clk);
        end
        i_in_valid = 1'b0;
        i_in_data  = 24'd0;
      end

      // wait for the DUT to finish this operation
      while (ready_pulse_cnt == old_ready_cnt) @(posedge clk);

      // keep one clean half-cycle before next command
      @(negedge clk);
      i_op_valid = 1'b0;
      i_op_mode  = 4'd0;
      i_in_valid = 1'b0;
      i_in_data  = 24'd0;
    end
  endtask

  // ----------------------------------------------
  // Clock
  // ----------------------------------------------
  initial clk = 1'b0;
  always #(`HCYCLE) clk = ~clk;

  // ----------------------------------------------
  // Reset
  // ----------------------------------------------
  initial begin
    rst_n      = 1'b1;
    i_op_valid = 1'b0;
    i_op_mode  = 4'd0;
    i_in_valid = 1'b0;
    i_in_data  = 24'd0;

    #(0.25 * `CYCLE);
    rst_n = 1'b0;
    #((`RST_DELAY - 0.25) * `CYCLE);
    rst_n = 1'b1;
  end

  initial begin
    #(`MAX_CYCLE * `CYCLE);
    $display("--------------------------------------------------");
    $display("ERROR: Runtime exceeded!");
    $display("--------------------------------------------------");
    $finish;
  end
  // ----------------------------------------------
  // Count valid ops / golden entries
  // ----------------------------------------------
  initial begin
    num_ops    = 0;
    num_golden = 0;

    #1;
    for (i = 0; i < 64; i = i + 1) begin
      if (!is_x4(opmode_mem[i])) num_ops = num_ops + 1;
    end

    for (i = 0; i < 1024; i = i + 1) begin
      if (!is_x24(golden_mem[i])) num_golden = num_golden + 1;
    end
  end

  // ----------------------------------------------
  // Output / protocol monitor
  // outputs are registered on rising edge
  // ----------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      golden_idx      = 0;
      ready_pulse_cnt = 0;
      error_cnt       = 0;
    end else begin
      // Forbidden overlaps from the manual
      if (i_in_valid && o_op_ready) begin
        $display("[%0t] ERROR: i_in_valid && o_op_ready both high", $time);
        error_cnt = error_cnt + 1;
      end
      if (i_op_valid && o_op_ready) begin
        $display("[%0t] ERROR: i_op_valid && o_op_ready both high", $time);
        error_cnt = error_cnt + 1;
      end
      if (i_in_valid && o_out_valid) begin
        $display("[%0t] ERROR: i_in_valid && o_out_valid both high", $time);
        error_cnt = error_cnt + 1;
      end
      if (i_op_valid && o_out_valid) begin
        $display("[%0t] ERROR: i_op_valid && o_out_valid both high", $time);
        error_cnt = error_cnt + 1;
      end
      if (o_op_ready && o_out_valid) begin
        $display("[%0t] ERROR: o_op_ready && o_out_valid both high", $time);
        error_cnt = error_cnt + 1;
      end

      if (o_op_ready) ready_pulse_cnt = ready_pulse_cnt + 1;

      if (o_out_valid) begin
        if (golden_idx >= num_golden) begin
          $display("[%0t] ERROR: Extra output after golden is exhausted. out_data=%h", $time,
                   o_out_data);
          error_cnt = error_cnt + 1;
        end else if (o_out_data !== golden_mem[golden_idx]) begin
          $display("[%0t] ERROR: Output mismatch at golden[%0d]. got=%h expected=%h", $time,
                   golden_idx, o_out_data, golden_mem[golden_idx]);
          error_cnt = error_cnt + 1;
        end
        golden_idx = golden_idx + 1;
      end
    end
  end

  // ----------------------------------------------
  // Main stimulus
  // ----------------------------------------------
  initial begin
    #1;
    wait (rst_n === 1'b1);
    @(negedge clk);

    if (num_ops == 0) begin
      $display("--------------------------------------------------");
      $display("ERROR: No valid op modes found in %s", `OPFILE);
      $display("--------------------------------------------------");
      $finish;
    end

    for (op_idx = 0; op_idx < num_ops; op_idx = op_idx + 1) begin
      send_one_op(opmode_mem[op_idx]);
    end

    // give monitor a couple cycles to settle
    repeat (3) @(posedge clk);

    // final checks
    if (ready_pulse_cnt !== num_ops) begin
      $display("ERROR: ready pulse count mismatch. got=%0d expected=%0d", ready_pulse_cnt, num_ops);
      error_cnt = error_cnt + 1;
    end

    if (golden_idx !== num_golden) begin
      $display("ERROR: golden count mismatch. got=%0d expected=%0d", golden_idx, num_golden);
      error_cnt = error_cnt + 1;
    end

    $display("--------------------------------------------------");
    if (error_cnt == 0) begin
      $display("PASS");
      $display("  operations checked : %0d", num_ops);
      $display("  golden pixels      : %0d", num_golden);
    end else begin
      $display("FAIL");
      $display("  error count        : %0d", error_cnt);
      $display("  operations checked : %0d", num_ops);
      $display("  golden pixels seen : %0d / %0d", golden_idx, num_golden);
    end
    $display("--------------------------------------------------");

    $finish;
  end

endmodule
