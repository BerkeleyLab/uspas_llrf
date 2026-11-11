// Test wrapper for cic_bpm integrated with DDS and DDC.
// Converts 4-channel raw ADC samples to baseband I/Q via DDC with a shared DDS LO,
// then processes magnitudes through 3-rate CIC filters and positionCalc.

module test_cic_bpm #(
    parameter integer DW         = 16,
    parameter integer DWBB       = 18,
    parameter integer DWLO       = 18,
    parameter integer DWH        = 20,
    parameter integer DWL        = 12,
    parameter integer DWO        = 32,
    parameter integer N_BTN      = 4,
    parameter integer EX0        = 3,
    parameter integer EX1        = 4,
    parameter integer EX2        = 4
) (
    input  logic                   clk,
    input  logic                   reset,

    // 4-channel button ADC raw inputs
    input  logic signed [DW-1:0]   adc_array_in [0:N_BTN-1],

    // DDS LO control
    input  logic [DWLO-1:0]        amplitude,
    input  logic signed [DWLO:0]   phase_shift,
    input  logic [DWH-1:0]         phase_step_h,
    input  logic [DWL-1:0]         phase_step_l,
    input  logic [DWL-1:0]         modulo,

    // DDC control
    input  logic                   i_sel,
    input  logic                   sig_valid,

    // Control and Calibration Interface for positionCalc
    input  logic [DWO-1:0]         gpioData,
    input  logic                   csrStrobe,
    input  logic                   xCalStrobe,
    input  logic                   yCalStrobe,
    input  logic                   qCalStrobe,

    // Status and Calibration Readback
    output logic [DWO-1:0]         csr,
    output logic [DWO-1:0]         xCalibration,
    output logic [DWO-1:0]         yCalibration,
    output logic [DWO-1:0]         qCalibration,

    // Turn-by-Turn (TbT, rate 0) Outputs
    output logic [DWO-1:0]         tbtX,
    output logic [DWO-1:0]         tbtY,
    output logic [DWO-1:0]         tbtQ,
    output logic [DWO-1:0]         tbtS,
    output logic                   tbtToggle,
    output logic                   tbtValid,

    // Fast Acquisition (FA, rate 1) Outputs
    output logic [DWO-1:0]         faX,
    output logic [DWO-1:0]         faY,
    output logic [DWO-1:0]         faQ,
    output logic [DWO-1:0]         faS,
    output logic                   faToggle,
    output logic                   faValid,

    // Slow Acquisition (SA, rate 2) Outputs
    output logic [DWO-1:0]         saX,
    output logic [DWO-1:0]         saY,
    output logic [DWO-1:0]         saQ,
    output logic [DWO-1:0]         saS,
    output logic                   saToggle,
    output logic                   saValid
);

    // ------------------------------------------------------------------------
    // Shared DDS LO Generator
    // ------------------------------------------------------------------------
    wire signed [DWLO-1:0] sin_lo;
    wire signed [DWLO-1:0] cos_lo;

    dds #(
        .DWLO (DWLO),
        .DWH  (DWH),
        .DWL  (DWL)
    ) dds_inst (
        .clk          (clk),
        .reset        (reset),
        .amplitude    (amplitude),
        .phase_shift  (phase_shift),
        .phase_step_h (phase_step_h),
        .phase_step_l (phase_step_l),
        .modulo       (modulo),
        .sin_out      (sin_lo),
        .cos_out      (cos_lo)
    );

    // ------------------------------------------------------------------------
    // DDC Down-Conversion for each of the 4 Button Channels
    // ------------------------------------------------------------------------
    wire signed [DWBB-1:0] ddc_i [0:N_BTN-1];
    wire signed [DWBB-1:0] ddc_q [0:N_BTN-1];

    genvar ch;
    generate
        for (ch = 0; ch < N_BTN; ch = ch + 1) begin: gen_ddc
            ddc #(
                .DWI  (DW),
                .DWO  (DWBB),
                .DWLO (DWLO)
            ) ddc_inst (
                .clk   (clk),
                .reset (reset),
                .adc   (adc_array_in[ch]),
                .cosa  (cos_lo),
                .sina  (sin_lo),
                .i_sel (i_sel),
                .i_out (ddc_i[ch]),
                .q_out (ddc_q[ch])
            );
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Pack baseband I/Q to feed cic_bpm
    // ------------------------------------------------------------------------
    logic signed [N_BTN*DW-1:0] sig_i_flat;
    logic signed [N_BTN*DW-1:0] sig_q_flat;

    generate
        for (ch = 0; ch < N_BTN; ch = ch + 1) begin: gen_sig_flat
            assign sig_i_flat[DW*ch +: DW] = ddc_i[ch][DWBB-1 -: DW];
            assign sig_q_flat[DW*ch +: DW] = ddc_q[ch][DWBB-1 -: DW];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // CIC BPM Processing Core
    // ------------------------------------------------------------------------
    cic_bpm #(
        .DW  (DW),
        .DWO (DWO),
        .EX0 (EX0),
        .EX1 (EX1),
        .EX2 (EX2)
    ) cic_bpm_inst (
        .clk          (clk),
        .sig_i        (sig_i_flat),
        .sig_q        (sig_q_flat),
        .sig_valid    (sig_valid),

        .gpioData     (gpioData),
        .csrStrobe    (csrStrobe),
        .xCalStrobe   (xCalStrobe),
        .yCalStrobe   (yCalStrobe),
        .qCalStrobe   (qCalStrobe),

        .csr          (csr),
        .xCalibration (xCalibration),
        .yCalibration (yCalibration),
        .qCalibration (qCalibration),

        .tbtX         (tbtX),
        .tbtY         (tbtY),
        .tbtQ         (tbtQ),
        .tbtS         (tbtS),
        .tbtToggle    (tbtToggle),
        .tbtValid     (tbtValid),

        .faX          (faX),
        .faY          (faY),
        .faQ          (faQ),
        .faS          (faS),
        .faToggle     (faToggle),
        .faValid      (faValid),

        .saX          (saX),
        .saY          (saY),
        .saQ          (saQ),
        .saS          (saS),
        .saToggle     (saToggle),
        .saValid      (saValid)
    );

endmodule
