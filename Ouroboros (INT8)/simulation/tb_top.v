`timescale 1ns/1ps

//=============================================================================
// Simulation wrapper for latsr_cim_cell_tb
//
// This module is not intended for synthesis. It provides clock/reset
// generation and text reporting for RTL simulation.
//=============================================================================
module latsr_cim_cell_tb_sim;

    reg  clk;
    reg  rst_n;

    wire test_done;
    wire test_fail;

    //-------------------------------------------------------------------------
    // Clock generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
    end

    always #5 clk = ~clk;   // 100 MHz nominal simulation clock

    //-------------------------------------------------------------------------
    // Reset and test control
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("latsr_cim_cell_tb.vcd");
        $dumpvars(0, latsr_cim_cell_tb_sim);

        rst_n = 1'b0;

        // Hold reset for a few cycles.
        repeat (5) @(negedge clk);

        rst_n = 1'b1;

        // Wait for BIST completion.
        wait (test_done);

        // Allow final signals to settle before reporting.
        @(negedge clk);

        if (!test_fail) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("TEST FAILED");
        end

        $finish;
    end

    //-------------------------------------------------------------------------
    // Optional cycle-by-cycle trace
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            $strobe(
                "[%0t] phase=%0d slot_select=%b token=%0d stall=%b accum_out=%0d",
                $time,
                u_tb.phase,
                u_tb.slot_select,
                u_tb.input_token,
                u_tb.step_delay_stall,
                u_tb.accum_out
            );
        end
    end

    //-------------------------------------------------------------------------
    // Instantiate synthesizable BIST
    //-------------------------------------------------------------------------
    latsr_cim_cell_tb u_tb (
        .clk       (clk),
        .rst_n     (rst_n),
        .test_done (test_done),
        .test_fail (test_fail)
    );

endmodule