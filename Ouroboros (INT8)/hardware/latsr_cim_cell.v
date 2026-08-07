//=============================================================================
// Project Ouroboros / LAST-R
// Module: latsr_cim_cell_tb
//
// Synthesizable self-checking BIST for latsr_cim_cell.
//
// Test sequence overview:
// -----------------------
//   1. Program shadow slots using background writes.
//   2. Attempt an illegal active-slot write and verify it is ignored.
//   3. Execute with token = 4 through slots 1, 2, and 3.
//   4. Move to token = 7, Slot 1.
//   5. Assert thermal step_delay_stall and verify accum_out holds.
//   6. While stalled, update inactive Slot 2 with a new weight.
//   7. While still stalled, change slot_select and input_token.
//   8. Release stall and verify the newly programmed Slot 2 is used.
//   9. Verify reserved slot_select = 2'b11 falls back to Slot 1.
//
// This module has only clock, reset, test_done, and test_fail ports, making
// it usable as a synthesizable BIST wrapper.
//=============================================================================

module latsr_cim_cell_tb (
    input  wire clk,
    input  wire rst_n,
    output wire test_done,
    output wire test_fail
);

    //-------------------------------------------------------------------------
    // Test phase encoding
    //-------------------------------------------------------------------------
    localparam PH_IDLE                          = 6'd0;

    // Shadow-slot programming phases
    localparam PH_SET_ACTIVE_SLOT2              = 6'd1;
    localparam PH_WRITE_SLOT1                   = 6'd2;
    localparam PH_WRITE_SLOT1_DONE              = 6'd3;
    localparam PH_WRITE_SLOT3                   = 6'd4;
    localparam PH_WRITE_SLOT3_DONE              = 6'd5;

    localparam PH_SET_ACTIVE_SLOT1              = 6'd6;
    localparam PH_WRITE_SLOT2                   = 6'd7;
    localparam PH_WRITE_SLOT2_DONE              = 6'd8;

    // Attempt to write active Slot 1; should be ignored.
    localparam PH_PROTECT_ACTIVE_WRITE          = 6'd9;
    localparam PH_PROTECT_ACTIVE_WRITE_DONE     = 6'd10;

    // Normal temporal weight flipping checks
    localparam PH_DRIVE_SLOT1_TOKEN4            = 6'd11;
    localparam PH_CHECK_SLOT1_DRIVE_SLOT2       = 6'd12;
    localparam PH_CHECK_SLOT2_DRIVE_SLOT3       = 6'd13;
    localparam PH_CHECK_SLOT3_DRIVE_SLOT1_T7    = 6'd14;

    // Thermal stall checks
    localparam PH_CHECK_PRE_STALL_ASSERT_STALL  = 6'd15;
    localparam PH_CHECK_HOLD_WRITE_SLOT2        = 6'd16;
    localparam PH_CHECK_HOLD_WRITE_DONE         = 6'd17;
    localparam PH_CHECK_HOLD_SWITCH_CONTEXT     = 6'd18;
    localparam PH_CHECK_HOLD_RELEASE_STALL      = 6'd19;

    // Post-stall execution with updated Slot 2
    localparam PH_CHECK_RELEASED_DRIVE_RESERVED = 6'd20;

    // Reserved slot_select fallback check
    localparam PH_CHECK_RESERVED                = 6'd21;

    localparam PH_DONE                          = 6'd22;

    //-------------------------------------------------------------------------
    // Phase counter
    //-------------------------------------------------------------------------
    reg [5:0] phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PH_IDLE;
        end else if (phase != PH_DONE) begin
            phase <= phase + 6'd1;
        end
    end

    //-------------------------------------------------------------------------
    // DUT interface signals
    //-------------------------------------------------------------------------
    reg  signed [7:0]  input_token;
    reg         [1:0]  slot_select;
    reg  signed [7:0]  weight_data_in;
    reg         [1:0]  weight_slot_target;
    reg                weight_write_en;
    reg                step_delay_stall;

    wire signed [7:0]  selected_weight;
    wire signed [15:0] accum_out;

    //-------------------------------------------------------------------------
    // DUT instantiation
    //-------------------------------------------------------------------------
    latsr_cim_cell dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .input_token        (input_token),
        .slot_select        (slot_select),
        .weight_data_in     (weight_data_in),
        .weight_slot_target (weight_slot_target),
        .weight_write_en    (weight_write_en),
        .step_delay_stall   (step_delay_stall),
        .selected_weight    (selected_weight),
        .accum_out          (accum_out)
    );

    //-------------------------------------------------------------------------
    // Stimulus sequencing
    //
    // The stimulus is combinational as a function of phase. At each rising
    // clock edge, the DUT samples the stimulus associated with the current
    // phase. The checker below validates accum_out in the following phase.
    //-------------------------------------------------------------------------
    always @* begin
        // Safe defaults
        slot_select        = 2'b00;
        input_token        = 8'sd0;
        weight_data_in     = 8'sd0;
        weight_slot_target = 2'b00;
        weight_write_en    = 1'b0;
        step_delay_stall   = 1'b0;

        case (phase)

            //-----------------------------------------------------------------
            // Move active execution slot to Slot 2 so Slot 1 and Slot 3 can
            // be programmed through the inactive-slot background interface.
            //-----------------------------------------------------------------
            PH_SET_ACTIVE_SLOT2: begin
                slot_select = 2'b01;
            end

            // Program Slot 1 = +3 while Slot 2 is active.
            PH_WRITE_SLOT1: begin
                slot_select        = 2'b01;
                weight_slot_target = 2'b00;
                weight_data_in     = 8'sd3;
                weight_write_en    = 1'b1;
            end

            PH_WRITE_SLOT1_DONE: begin
                slot_select = 2'b01;
            end

            // Program Slot 3 = +5 while Slot 2 is active.
            PH_WRITE_SLOT3: begin
                slot_select        = 2'b01;
                weight_slot_target = 2'b10;
                weight_data_in     = 8'sd5;
                weight_write_en    = 1'b1;
            end

            PH_WRITE_SLOT3_DONE: begin
                slot_select = 2'b01;
            end

            //-----------------------------------------------------------------
            // Move active execution slot to Slot 1 so Slot 2 can be programmed.
            //-----------------------------------------------------------------
            PH_SET_ACTIVE_SLOT1: begin
                slot_select = 2'b00;
            end

            // Program Slot 2 = -2 while Slot 1 is active.
            // 8'shFE is -2 in two's complement INT8.
            PH_WRITE_SLOT2: begin
                slot_select        = 2'b00;
                weight_slot_target = 2'b01;
                weight_data_in     = 8'shFE;
                weight_write_en    = 1'b1;
            end

            PH_WRITE_SLOT2_DONE: begin
                slot_select = 2'b00;
            end

            //-----------------------------------------------------------------
            // Active-slot write protection check:
            // Slot 1 is active, so this write to Slot 1 should be ignored.
            //-----------------------------------------------------------------
            PH_PROTECT_ACTIVE_WRITE: begin
                slot_select        = 2'b00;
                weight_slot_target = 2'b00;
                weight_data_in     = 8'sd9;
                weight_write_en    = 1'b1;
            end

            PH_PROTECT_ACTIVE_WRITE_DONE: begin
                slot_select = 2'b00;
            end

            //-----------------------------------------------------------------
            // Normal execution and temporal weight flipping
            //-----------------------------------------------------------------

            // Slot 1 active, token = 4. Expected next result: 4 * 3 = 12.
            PH_DRIVE_SLOT1_TOKEN4: begin
                slot_select = 2'b00;
                input_token = 8'sd4;
            end

            // Check Slot 1 result while driving Slot 2.
            PH_CHECK_SLOT1_DRIVE_SLOT2: begin
                slot_select = 2'b01;
                input_token = 8'sd4;
            end

            // Check Slot 2 result while driving Slot 3.
            PH_CHECK_SLOT2_DRIVE_SLOT3: begin
                slot_select = 2'b10;
                input_token = 8'sd4;
            end

            // Check Slot 3 result while moving to Slot 1 with token = 7.
            PH_CHECK_SLOT3_DRIVE_SLOT1_T7: begin
                slot_select = 2'b00;
                input_token = 8'sd7;
            end

            //-----------------------------------------------------------------
            // Thermal step-delay stall behavior
            //-----------------------------------------------------------------

            // Check 7 * Slot1 = 21, then assert stall.
            PH_CHECK_PRE_STALL_ASSERT_STALL: begin
                slot_select      = 2'b00;
                input_token      = 8'sd7;
                step_delay_stall = 1'b1;
            end

            // While stalled, update inactive Slot 2 to -4.
            // 8'shFC is -4 in two's complement INT8.
            PH_CHECK_HOLD_WRITE_SLOT2: begin
                slot_select        = 2'b00;
                input_token        = 8'sd7;
                step_delay_stall   = 1'b1;
                weight_slot_target = 2'b01;
                weight_data_in     = 8'shFC;
                weight_write_en    = 1'b1;
            end

            // Complete background write while still stalled.
            PH_CHECK_HOLD_WRITE_DONE: begin
                slot_select      = 2'b00;
                input_token      = 8'sd7;
                step_delay_stall = 1'b1;
            end

            // While still stalled, switch context to Slot 2 and token = 10.
            // accum_out must still hold the old value.
            PH_CHECK_HOLD_SWITCH_CONTEXT: begin
                slot_select      = 2'b01;
                input_token      = 8'sd10;
                step_delay_stall = 1'b1;
            end

            // Release stall. At the next active clock edge, the DUT should
            // compute 10 * Slot2(-4) = -40.
            PH_CHECK_HOLD_RELEASE_STALL: begin
                slot_select      = 2'b01;
                input_token      = 8'sd10;
                step_delay_stall = 1'b0;
            end

            //-----------------------------------------------------------------
            // Verify post-stall execution, then reserved slot_select fallback.
            //-----------------------------------------------------------------

            // Check -40, then drive reserved slot_select = 2'b11.
            PH_CHECK_RELEASED_DRIVE_RESERVED: begin
                slot_select = 2'b11;
                input_token = 8'sd4;
            end

            // Check reserved fallback result: should use Slot 1 = +3.
            PH_CHECK_RESERVED: begin
                slot_select = 2'b11;
                input_token = 8'sd4;
            end

            PH_DONE: begin
                // Hold idle.
            end

            default: begin
                // Defaults already assigned above.
            end

        endcase
    end

    //-------------------------------------------------------------------------
    // Output checker
    //
    // The check happens in the phase after the DUT has registered the result.
    // fail_q is sticky; once set, test_fail remains asserted.
    //-------------------------------------------------------------------------
    reg fail_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fail_q <= 1'b0;
        end else begin
            case (phase)

                // 4 * Slot1(+3) = 12
                PH_CHECK_SLOT1_DRIVE_SLOT2: begin
                    if (accum_out != 16'sd12) begin
                        fail_q <= 1'b1;
                    end
                end

                // 4 * Slot2(-2) = -8
                PH_CHECK_SLOT2_DRIVE_SLOT3: begin
                    if (accum_out != 16'shFFF8) begin
                        fail_q <= 1'b1;
                    end
                end

                // 4 * Slot3(+5) = 20
                PH_CHECK_SLOT3_DRIVE_SLOT1_T7: begin
                    if (accum_out != 16'sd20) begin
                        fail_q <= 1'b1;
                    end
                end

                // 7 * Slot1(+3) = 21
                PH_CHECK_PRE_STALL_ASSERT_STALL: begin
                    if (accum_out != 16'sd21) begin
                        fail_q <= 1'b1;
                    end
                end

                // Stall engaged: accum_out must hold 21.
                PH_CHECK_HOLD_WRITE_SLOT2: begin
                    if (accum_out != 16'sd21) begin
                        fail_q <= 1'b1;
                    end
                end

                // Still stalled while background write occurs.
                PH_CHECK_HOLD_WRITE_DONE: begin
                    if (accum_out != 16'sd21) begin
                        fail_q <= 1'b1;
                    end
                end

                // Still stalled after context switch.
                PH_CHECK_HOLD_SWITCH_CONTEXT: begin
                    if (accum_out != 16'sd21) begin
                        fail_q <= 1'b1;
                    end
                end

                // Still stalled just before release.
                PH_CHECK_HOLD_RELEASE_STALL: begin
                    if (accum_out != 16'sd21) begin
                        fail_q <= 1'b1;
                    end
                end

                // Stall released: 10 * updated Slot2(-4) = -40.
                PH_CHECK_RELEASED_DRIVE_RESERVED: begin
                    if (accum_out != 16'shFFD8) begin
                        fail_q <= 1'b1;
                    end
                end

                // Reserved slot_select fallback should use Slot1: 4 * 3 = 12.
                PH_CHECK_RESERVED: begin
                    if (accum_out != 16'sd12) begin
                        fail_q <= 1'b1;
                    end
                end

                default: begin
                    // No check in this phase.
                end

            endcase
        end
    end

    //-------------------------------------------------------------------------
    // BIST status outputs
    //-------------------------------------------------------------------------
    assign test_done = (phase == PH_DONE);
    assign test_fail = fail_q;

endmodule