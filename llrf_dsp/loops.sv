// Feedback loops (plan §2.2): one loop_ctrl per drive, with pulse
// modulation, its registers (cfg_dsp.loop[n], loop_cfg_t), the error words
// to lb_clk and the modulation table readback. The design shell supplies
// each loop's drive permit, pulse mode and phase offset.
module loops
    import llrf_shell_pkg::*;
(
    input                 dsp_clk,
    input                 dsp_reset,
    input                 dsp_tick,              // error words to lb_clk
    input  loop_cfg_t [N_DRIVE-1:0] cfg,
    input  [DWBB:0]       rx_phase_offset,
    input  [DWBB:0]       tx_phase_offset,
    input                 trig,                  // pulse start
    input  [N_DRIVE-1:0]  pulse_mode,            // 1: drive only while the pulse is on
    input  [N_DRIVE-1:0]  drive_permit,          // drive enable and permits
    input  bb_t           phs_offset [N_DRIVE],  // added to the phase setpoint
    input  bb_t           sig_i [N_ADC],         // field: channel cfg[n].adc_chan
    input  bb_t           sig_q [N_ADC],

    output bb_t           drive_i [N_DRIVE],
    output bb_t           drive_q [N_DRIVE],
    output [N_DRIVE-1:0]  pulse_dval,
    output [PULSE_AW-1:0] pulse_idx [N_DRIVE],
    output signed [14:0]  err_amp_lb [N_DRIVE],  // lb_clk
    output signed [14:0]  err_phs_lb [N_DRIVE],

    // localbus: modulation tables
    input                 lb_clk,
    input  [MOD_AW-1:0]   lb_addr,
    input  [DWBB-1:0]     lb_wdata,
    input  [N_DRIVE-1:0]  wr_amp_mod,
    input  [N_DRIVE-1:0]  wr_phs_mod,
    output [31:0]         rd_amp_mod [N_DRIVE],
    output [31:0]         rd_phs_mod [N_DRIVE]
);

genvar n;
generate for (n = 0; n < N_DRIVE; n = n + 1) begin: gen_loops
    wire signed [14:0] err_amp, err_phs;
    wire [DWBB-1:0] lb_rdata_amp_mod, lb_rdata_phs_mod;
    loop_ctrl #(.EW(15)) loop_ctrl (
        .dsp_clk          (dsp_clk),
        .dsp_reset        (dsp_reset),
        .cfg              (cfg[n]),
        .trig             (trig),
        .pulse_mode       (pulse_mode[n]),
        .drive_permit     (drive_permit[n]),
        .phs_offset       (phs_offset[n]),
        .rx_phase_offset  (rx_phase_offset),
        .tx_phase_offset  (tx_phase_offset),
        .field_i          (sig_i[cfg[n].adc_chan]),
        .field_q          (sig_q[cfg[n].adc_chan]),
        .drive_i          (drive_i[n]),
        .drive_q          (drive_q[n]),
        .drive_on         (),
        .amp_measured     (),
        .phs_measured     (),
        .err_amp          (err_amp),
        .err_phs          (err_phs),
        .pulse_dval       (pulse_dval[n]),
        .pulse_last       (),
        .pulse_idx        (pulse_idx[n]),
        .amp_setpoint_mod (),
        .phs_setpoint_mod (),
        .lb_clk           (lb_clk),
        .lb_addr          (lb_addr),
        .lb_wdata         (lb_wdata),
        .lb_write_amp_mod (wr_amp_mod[n]),
        .lb_write_phs_mod (wr_phs_mod[n]),
        .lb_rdata_amp_mod (lb_rdata_amp_mod),
        .lb_rdata_phs_mod (lb_rdata_phs_mod)
    );
    assign rd_amp_mod[n] = {{(32-DWBB){lb_rdata_amp_mod[DWBB-1]}}, lb_rdata_amp_mod};
    assign rd_phs_mod[n] = {{(32-DWBB){lb_rdata_phs_mod[DWBB-1]}}, lb_rdata_phs_mod};

    data_xdomain #(.size(30)) loop_err_xdomain (
        .clk_in   (dsp_clk),
        .gate_in  (dsp_tick),
        .data_in  ({err_amp, err_phs}),
        .clk_out  (lb_clk),
        .data_out ({err_amp_lb[n], err_phs_lb[n]})
    );
end endgenerate

endmodule
