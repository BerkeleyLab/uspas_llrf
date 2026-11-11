// Calculate BPM button signal magnitudes via 3-rate CIC filtering
// and calculate beam position (X, Y, Q, Sum) for TbT, FA, and SA rates.

module cic_bpm #(
    parameter integer DW   = 16,
    parameter integer DWO  = 32,
    parameter integer EX0  = 5,
    parameter integer EX1  = 8,
    parameter integer EX2  = 10
) (
    input  wire                   clk,

    // 4-channel button baseband I/Q inputs
    input  wire signed [4*DW-1:0] sig_i,
    input  wire signed [4*DW-1:0] sig_q,
    input  wire                   sig_valid,

    // Control and Calibration Interface
    input  wire [DWO-1:0]         gpioData,
    input  wire                   csrStrobe,
    input  wire                   xCalStrobe,
    input  wire                   yCalStrobe,
    input  wire                   qCalStrobe,

    // Status and Calibration Readback
    output wire [DWO-1:0]         csr,
    output wire [DWO-1:0]         xCalibration,
    output wire [DWO-1:0]         yCalibration,
    output wire [DWO-1:0]         qCalibration,

    // Turn-by-Turn (TbT, rate 0) Outputs
    output wire [DWO-1:0]         tbtX,
    output wire [DWO-1:0]         tbtY,
    output wire [DWO-1:0]         tbtQ,
    output wire [DWO-1:0]         tbtS,
    output wire                   tbtToggle,
    output wire                   tbtValid,

    // Fast Acquisition (FA, rate 1) Outputs
    output wire [DWO-1:0]         faX,
    output wire [DWO-1:0]         faY,
    output wire [DWO-1:0]         faQ,
    output wire [DWO-1:0]         faS,
    output wire                   faToggle,
    output wire                   faValid,

    // Slow Acquisition (SA, rate 2) Outputs
    output wire [DWO-1:0]         saX,
    output wire [DWO-1:0]         saY,
    output wire [DWO-1:0]         saQ,
    output wire [DWO-1:0]         saS,
    output wire                   saToggle,
    output wire                   saValid
);

    // ------------------------------------------------------------------------
    // 4-Channel Magnitude Calculation and 3-rate CIC Decimation
    // ------------------------------------------------------------------------
    wire [DW-1:0] tbt_mag [0:3];
    wire [DW-1:0] fa_mag  [0:3];
    wire [DW-1:0] sa_mag  [0:3];

    wire [2:0] mag_valid [0:3];

    genvar btn;
    generate
        for (btn = 0; btn < 4; btn = btn + 1) begin: gen_btn_mag
            wire [3*DW-1:0] cic_mag;
            wire [2:0] cic_mag_valid;

            cic_mag3 #(
                .DW     (DW),
                .EX0    (EX0),
                .EX1    (EX1),
                .EX2    (EX2)
            ) cic_mag3_inst (
                .clk                (clk),
                .sig_i              (sig_i[btn*DW +: DW]),
                .sig_q              (sig_q[btn*DW +: DW]),
                .sig_valid          (sig_valid),
                .sig_cic_mag        (cic_mag),
                .sig_cic_mag_valid  (cic_mag_valid)
            );

            assign tbt_mag[btn]   = cic_mag[0*DW +: DW];
            assign fa_mag[btn]    = cic_mag[1*DW +: DW];
            assign sa_mag[btn]    = cic_mag[2*DW +: DW];
            assign mag_valid[btn] = cic_mag_valid;
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Rate Input Toggles for positionCalc
    // ------------------------------------------------------------------------
    reg tbtInToggle = 0;
    reg faInToggle  = 0;
    reg saInToggle  = 0;

    always @(posedge clk) begin
        if (mag_valid[0][0]) tbtInToggle <= ~tbtInToggle;
        if (mag_valid[0][1]) faInToggle  <= ~faInToggle;
        if (mag_valid[0][2]) saInToggle  <= ~saInToggle;
    end

    // ------------------------------------------------------------------------
    // Position, Quadrupole, and Sum Calculation Engine
    // ------------------------------------------------------------------------
    positionCalc #(
        .MAG_WIDTH      (DW),
        .DATA_WIDTH     (DWO)
    ) position_calc_inst (
        .clk            (clk),
        .gpioData       (gpioData),
        .csrStrobe      (csrStrobe),
        .xCalStrobe     (xCalStrobe),
        .yCalStrobe     (yCalStrobe),
        .qCalStrobe     (qCalStrobe),

        .tbt0           (tbt_mag[0]),
        .tbt1           (tbt_mag[1]),
        .tbt2           (tbt_mag[2]),
        .tbt3           (tbt_mag[3]),

        .fa0            (fa_mag[0]),
        .fa1            (fa_mag[1]),
        .fa2            (fa_mag[2]),
        .fa3            (fa_mag[3]),

        .sa0            (sa_mag[0]),
        .sa1            (sa_mag[1]),
        .sa2            (sa_mag[2]),
        .sa3            (sa_mag[3]),

        .tbtInToggle    (tbtInToggle),
        .faInToggle     (faInToggle),
        .saInToggle     (saInToggle),

        .csr            (csr),
        .xCalibration   (xCalibration),
        .yCalibration   (yCalibration),
        .qCalibration   (qCalibration),

        .tbtX           (tbtX),
        .tbtY           (tbtY),
        .tbtQ           (tbtQ),
        .tbtS           (tbtS),

        .faX            (faX),
        .faY            (faY),
        .faQ            (faQ),
        .faS            (faS),

        .saX            (saX),
        .saY            (saY),
        .saQ            (saQ),
        .saS            (saS),

        .tbtToggle      (tbtToggle),
        .faToggle       (faToggle),
        .saToggle       (saToggle),

        .tbtValid       (tbtValid),
        .faValid        (faValid),
        .saValid        (saValid)
    );

endmodule
