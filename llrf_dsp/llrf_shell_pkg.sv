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
                           WAVE_TRIG_MIXED  = 3'd5,  // external or software trigger
                           WAVE_TRIG_FIDUCIAL = 3'd6;  // fiducial trigger (LEMP); base shell: default case

    // Register configs of the blocks (plan §2.2): uspas_llrf/regmap.py puts
    // the registers of instance <inst> (Reg(inst=<inst>)) into the field
    // cfg_<domain>.<inst> of type <inst>_cfg_t, one member per register,
    // named without the '<inst>_' prefix (indexed: '<inst><n>_'). `// strobe`
    // members are high for one cycle after the write; signed registers are
    // signed members.
    localparam int INLK_AW = 4;  // monitor_inlk tables: amp_lo, amp_hi, inlk_mode
    localparam int PULSE_AW = 32;  // loop_ctrl pulse counter
    localparam int PULSE_RW = 4;   // loop_ctrl pulse resolution shift
    localparam int MOD_AW = 14;    // loop_ctrl modulation table depth 2^MOD_AW

    typedef struct packed {
        logic       reset_inlk;    // strobe
        logic [9:0] permit_mask;
    } inlk_cfg_t;                  // monitor_inlk

    typedef struct packed {
        logic       reset_latch;   // strobe
        logic       reset_arc_dev; // strobe
        logic [7:0] permit_mask;
        logic [7:0] test_mask;
        logic       test_stb;      // strobe
    } arc_cfg_t;                   // arc_inlk

    typedef struct packed {
        logic [17:0] lo_amp;
        logic [11:0] modulo;
        logic [31:0] phase_step_h;
        logic [11:0] phase_step_l;
    } ntw_cfg_t;                   // ntw_analyzer

    typedef struct packed {
        logic        [2:0]  adc_chan;          // field: ADC channel
        logic signed [17:0] amp_setpoint;
        logic signed [17:0] max_amp_setpoint;
        logic signed [17:0] phs_setpoint;
        logic signed [17:0] Kp_amp;
        logic signed [17:0] Kp_phs;
        logic signed [17:0] Ki_amp;
        logic signed [17:0] Ki_phs;
        logic               amp_enable;
        logic               phs_enable;
        logic               amp_reset;
        logic               phs_reset;
        logic        [PULSE_AW-1:0] pulse_start;
        logic        [PULSE_AW-1:0] pulse_high_len;
        logic        [PULSE_RW-1:0] pulse_res_shift;  // 2^pulse_res_shift clocks per table entry
        logic        [MOD_AW:0]     mod_len;          // table entries used, saturated to 2^MOD_AW
        logic               amp_mod_enable;
        logic               phs_mod_enable;
    } loop_cfg_t;                  // loop_ctrl (loops): cfg_dsp.loop[n], registers loopN_*

    typedef struct packed {
        logic [31:0] width;        // dsp clocks high
        logic [31:0] delay;        // dsp clocks after global_delay
    } trig_cfg_t;                  // triggers (LEMP): cfg_dsp.trig[n], registers trig_N_*
endpackage
