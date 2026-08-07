//=============================================================================
// Project Ouroboros / LAST-R
// Module: latsr_cim_cell
//
// Architectural intent:
// ---------------------
// This is the minimum compute-in-memory synaptic cell for the LAST-R
// "volatile AI-RAM matrix". It contains a small local "revolver cylinder"
// of three shadow weight registers:
//
//   weight_slot_1 : base / general weights
//   weight_slot_2 : coding weights
//   weight_slot_3 : reasoning weights
//
// The 2-bit slot_select bus performs temporal weight multiplexing. The MUX
// is purely combinational, so switching from one weight plane to another is
// zero-additional-latency at RTL. The selected weight is multiplied with the
// incoming INT8 token, and the 16-bit product is registered into accum_out.
//
// Background weight streaming:
// ----------------------------
// weight_data_in, weight_slot_target, and weight_write_en allow an external
// HBM/PCIe weight-streaming engine to update a shadow slot while another
// slot is actively being used for execution.
//
// For deterministic recursive execution, this RTL implementation ignores
// writes targeting the currently active slot. This prevents a background
// stream from corrupting a weight plane in the middle of a recursive pass.
// If the compiler guarantees inactive-slot writes only, this protection can
// be removed or relaxed.
//
// Thermal step-delay stall:
// -------------------------
// step_delay_stall models a compiler-inserted NOP for thermal mitigation.
// When high:
//   - accum_out is held.
//   - Multiplier operands are gated to zero to reduce switching power.
//   - Shadow-register background writes remain allowed, because weight top-up
//     is intentionally decoupled from the active compute pipeline.
//
// In physical implementation, compute_en should feed integrated clock gating
// cells and, if available, multiplier power-gating controls.
//=============================================================================

module latsr_cim_cell (
    input  wire               clk,                 // CIM clock domain
    input  wire               rst_n,               // Async active-low reset

    // INT8 activation/token input
    input  wire signed [7:0]  input_token,

    // Temporal weight multiplexing control
    // 00 = slot 1, 01 = slot 2, 10 = slot 3, 11 = reserved/fallback slot 1
    input  wire        [1:0]  slot_select,

    // Background shadow-register streaming interface
    input  wire signed [7:0]  weight_data_in,
    input  wire        [1:0]  weight_slot_target,
    input  wire               weight_write_en,

    // Compiler-driven thermal step-delay stall
    input  wire               step_delay_stall,

    // Observable selected weight, useful for debug and downstream connectivity
    output wire signed [7:0]  selected_weight,

    // Registered INT8 x INT8 product
    output reg  signed [15:0] accum_out
);

    //-------------------------------------------------------------------------
    // Revolver cylinder shadow registers
    //-------------------------------------------------------------------------
    reg signed [7:0] weight_slot_1;   // Base/general weights
    reg signed [7:0] weight_slot_2;   // Coding weights
    reg signed [7:0] weight_slot_3;   // Reasoning weights

    //-------------------------------------------------------------------------
    // Active slot normalization
    //
    // slot_select == 2'b11 is reserved. For deterministic hardware behavior,
    // it is treated as Slot 1.
    //-------------------------------------------------------------------------
    wire [1:0] active_slot = (slot_select == 2'b11) ? 2'b00 : slot_select;

    //-------------------------------------------------------------------------
    // Background weight streaming
    //
    // Writes are synchronous. A write is accepted only if it does not target
    // the currently active execution slot. This protects recursive execution
    // from asynchronous weight corruption.
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_slot_1 <= 8'sd0;
            weight_slot_2 <= 8'sd0;
            weight_slot_3 <= 8'sd0;
        end else begin
            if (weight_write_en && (weight_slot_target != active_slot)) begin
                case (weight_slot_target)
                    2'b00: weight_slot_1 <= weight_data_in;
                    2'b01: weight_slot_2 <= weight_data_in;
                    2'b10: weight_slot_3 <= weight_data_in;
                    default: begin
                        // Reserved target: ignore.
                    end
                endcase
            end
        end
    end

    //-------------------------------------------------------------------------
    // Execution MUX: zero-latency temporal weight switching
    //
    // This MUX is combinational. The selected weight is available to the
    // multiplier in the same cycle; the only pipeline delay is the intentional
    // output register accum_out.
    //-------------------------------------------------------------------------
    assign selected_weight =
          (active_slot == 2'b00) ? weight_slot_1
        : (active_slot == 2'b01) ? weight_slot_2
        : (active_slot == 2'b10) ? weight_slot_3
        :                           weight_slot_1;

    //-------------------------------------------------------------------------
    // Thermal step-delay / compute enable
    //
    // step_delay_stall active-high => compute disabled for this cycle.
    //-------------------------------------------------------------------------
    wire compute_en = ~step_delay_stall;

    //-------------------------------------------------------------------------
    // Multiplier operand gating
    //
    // During thermal stall, force multiplier inputs to zero. This does not
    // physically power down the multiplier in RTL, but it prevents input
    // toggling from propagating through the multiply logic. In a physical
    // implementation, compute_en should also control clock gating and/or
    // power gating.
    //-------------------------------------------------------------------------
    wire signed [7:0] token_to_mult  = compute_en ? input_token     : 8'sd0;
    wire signed [7:0] weight_to_mult = compute_en ? selected_weight : 8'sd0;

    //-------------------------------------------------------------------------
    // Signed INT8 multiplication
    //
    // INT8 range:
    //   -128 * -128 = 16384
    //    127 *  127 = 16129
    //
    // Therefore 16 signed bits are sufficient.
    //-------------------------------------------------------------------------
    wire signed [15:0] mult_product = token_to_mult * weight_to_mult;

    //-------------------------------------------------------------------------
    // Output register / local result hold
    //
    // During step_delay_stall, accum_out holds its previous value.
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_out <= 16'sd0;
        end else if (compute_en) begin
            accum_out <= mult_product;
        end
        // If compute_en is low, accum_out implicitly holds.
    end

endmodule