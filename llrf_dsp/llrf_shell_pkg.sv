// Types and constants shared by the llrf_shell blocks and design shells
// (plan §2.3). The register map types are generated separately
// (designs/<d>/_gen/llrf_shell_regmap_pkg.sv).
package llrf_shell_pkg;
    localparam int N_ADC = 8;
    localparam int N_DRIVE = 2;
    localparam int N_CH = N_ADC + N_DRIVE;
    localparam int DW = 16;      // ADC/DAC width
    localparam int DWLO = 18;    // LO width
    localparam int DWBB = 18;    // baseband width
    localparam int LB_ADW = 18;
    localparam int LB_DW = 32;

    typedef logic signed [DW-1:0] adc_t;
    typedef logic signed [DWBB-1:0] bb_t;

    // wave_trig_sel encoding (uspas_llrf.regmap.WaveTrigSel)
    localparam logic [2:0] WAVE_TRIG_INT    = 3'd0,  // internal trigger
                           WAVE_TRIG_EXT    = 3'd1,  // external trigger
                           WAVE_TRIG_SOFT   = 3'd2,  // software trigger
                           WAVE_TRIG_EVR    = 3'd3,  // EVR trigger
                           WAVE_TRIG_ALWAYS = 3'd4,  // internal trigger, cbuf continuous
                           WAVE_TRIG_MIXED  = 3'd5;  // external or software trigger
endpackage
