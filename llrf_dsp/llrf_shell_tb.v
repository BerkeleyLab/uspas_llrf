`timescale 1ns / 1ps
`include "constants.vams"
`include "settings.vams"
module llrf_shell_tb;

parameter  LB_VERBOSE       = 0;        // show LB transactions
parameter  N_ADC            = 8;
localparam MAX_SIM          = 8000000;    // ns
localparam DW               = 16;
localparam BUF_DWI          = 16;
localparam LB_ADW           = 18;
localparam CLK_CYCLE        = 8;        // ns
localparam LB_READ_DELAY    = 3;
parameter CBUF_AW           = 8;
parameter CBUF_DW           = 24;
parameter [17:0] DSP_CBUF_ADDR = 18'h20000;
parameter [17:0] DSP_SLOW_ADDR = 18'h12011;
localparam P_T                 = 2/8.7206e-9;
`define NULL 0

integer cc=0;
initial begin
    $display("##################################################");
    $display("    ---- Checking llrf_shell.v ----");
    if ($test$plusargs("vcd")) begin
        $dumpfile("llrf_shell.vcd");
        $dumpvars(5,llrf_shell_tb);
    end
    for (cc=0; cc<=MAX_SIM/`DSP_CLK_CYCLE; cc=cc+1) begin
        dsp_clk=0; #(`DSP_CLK_CYCLE/2);
        dsp_clk=1; #(`DSP_CLK_CYCLE/2);
    end
    $display("Simulation timed-out");
    $display("FAIL");
    $stop();
end

    `include "settings.vh"
    `include "regmap_llrf_shell.vh"

    // --------------------------------------------------------------
    //  Generate Clocks
    // --------------------------------------------------------------
    reg lb_clk=0, dsp_clk=0;
    always #(CLK_CYCLE/2) lb_clk = ~lb_clk;
    // --------------------------------------------------------------
    //  LocalBus functions
    // --------------------------------------------------------------

    reg lb_write=0, lb_read=0;
    reg [LB_ADW-1:0] lb_addr=0;
    reg [31:0] lb_wdata=0;
    wire [31:0] lb_rdata;
    reg [31:0] rdata=0;
    reg lb_rvalid=0;

    task lb_write_task(
        input [LB_ADW-1:0] addr,
        input [31:0] data
    );
        begin
            @ (posedge lb_clk);
            lb_addr  = addr;
            lb_wdata = data;
            lb_write = 1'b1;
            @ (posedge lb_clk);
            lb_write = 1'b0;
        end
    endtask

    task lb_read_task(
        input [LB_ADW-1:0] addr,
        output [31:0] data
    );
        begin
            @ (posedge lb_clk);
            lb_addr = addr;
            lb_read = 1'b1;
            // repeat (4 + LB_READ_DELAY) @ (posedge lb_clk);    // badger timing
            repeat (0 + LB_READ_DELAY) @ (posedge lb_clk);
            lb_rvalid = 1'b1;
            data = lb_rdata;
            // $display("time: %g Read ack: ADDR 0x%x DATA 0x%x", $time, addr, lb_rdata);
            @ (posedge lb_clk);
            lb_read = 1'b0;
            lb_rvalid = 1'b0;
        end
    endtask

    task read_inlk_task(
        input [7:0] chan,
        output real amp_out,
        output real phs_out
    );
        begin
            lb_read_task(MON_AMP_0 + chan, rdata);
            amp_out = $signed(rdata[15:0]);
            lb_read_task(MON_PHS_0 + chan, rdata);
            phs_out = $signed(rdata[16:0]) * 360.0 / 2**17;
            if (phs_out < -180) phs_out += 360;
            else if (phs_out > 180) phs_out -= 360;
        end
    endtask

    task read_waveform_task(
        input [7:0] chan,
        output real amp_out,
        output real phs_out
    );
        reg [LB_ADW-1:0] addr;
        reg signed [CBUF_DW-1:0] dout_i;
        reg signed [CBUF_DW-1:0] dout_q;
        begin
            lb_read_task(LLRF_CIRCLE_READY, rdata);
            while (!lb_rdata[0]) begin
                lb_read_task(LLRF_CIRCLE_READY, rdata);
            end
            // $display("Time: %g ns ns: Got cbuf_ready.", $time);
            for (addr=chan*2; addr < chan*2+2; addr++) begin
                lb_read_task(DSP_CBUF_ADDR + addr, rdata);    // read cbuf
                if (addr % 2 == 0) dout_i = $signed(rdata[CBUF_DW-1:0]);
                else dout_q = $signed(rdata[CBUF_DW-1:0]);
                amp_out = $hypot(dout_i, dout_q);
                phs_out = $atan2(dout_q, dout_i) * 180 / `M_PI;
                if (phs_out < -180) phs_out += 360;
                else if (phs_out > 180) phs_out -= 360;
            end
        end
    endtask

    task close_loops_task;
        begin
            lb_write_task(AMP_LOOP_RESET, 1);
            lb_write_task(PHS_LOOP_RESET, 1);
            lb_write_task(AMP_LOOP_ENABLE, 1);
            lb_write_task(PHS_LOOP_ENABLE, 1);
            lb_write_task(AMP_LOOP_RESET, 0);
            lb_write_task(PHS_LOOP_RESET, 0);
        end
    endtask

    reg pass =1;
    reg signed [17:0] setpoint_done = 0;

    // no actual check here
    task generate_ntw(
        input real freq
    );
    begin
        // excite with 100 MHz input
        @(posedge lb_clk);
        lb_write_task(NTW_PHASE_STEP_H, 29260777);
        lb_write_task(NTW_PHASE_STEP_L, 1);
        lb_write_task(NTW_MODULO, 4095);
        @(posedge lb_clk);
        lb_write_task(AMP_SETPOINT, 10000);
        lb_write_task(PHS_SETPOINT, 100);
        lb_write_task(NTW_LO_AMP, 20000);
        lb_write_task(KP_AMP, 1000);
        lb_write_task(KP_PHS, 1000);
        lb_write_task(KI_AMP, 100);
        lb_write_task(KI_PHS, 100);
        lb_write_task(AMP_LOOP_ENABLE, 1);
        lb_write_task(PHS_LOOP_ENABLE, 1);
        lb_write_task(NTW_AMP_ENABLE, 1);
        lb_write_task(NTW_PHS_ENABLE, 0);
        lb_write_task(AMP_LOOP_RESET, 0);
        lb_write_task(PHS_LOOP_RESET, 0);
        @(posedge lb_clk);
    end
endtask

    integer time0=0;
    always @(negedge lb_clk) begin
        time0 = $time-(CLK_CYCLE)/2;
        if (lb_write && LB_VERBOSE)
            $display("Time: %8g ns, LB  Write   : ADDR 0x%08x DATA 0x%08x",
                time0, lb_addr, lb_wdata);
        if (lb_rvalid && LB_VERBOSE)
            $display("Time: %8g ns, LB  Readback: ADDR 0x%08x DATA 0x%08x",
                time0, lb_addr, lb_rdata);
    end

    // ---------------------
    // Generate stimulus
    // ---------------------
    parameter real AMPI = 32767;     // full scale: 2^15
    parameter real PHSI = 50;        // deg
    parameter AMP_SETP_ADC = 10000;  // full scale: 2^15
    parameter PHS_SETP_DEG = PHSI;   // deg

    real theta;
    integer adc_cc=0;
    reg signed [15:0] adc=16'hxxxx;
    always @(posedge dsp_clk) begin
        adc_cc <= dut.dds_reset ? 0 : adc_cc + 1'b1; // synchronize with dds LO phase
        theta <= adc_cc * `M_TWO_PI * `NUM_DDS / `DEN_DDS - PHSI * `M_PI / 180;
        adc <= $floor(AMPI * $cos(theta));
    end

    // ---------------------
    // DUT
    // ---------------------
    wire [N_ADC*DW-1:0] adc_in_flat;
    wire [15:0] dac_a_out;
    wire [15:0] dac_b_out;
    llrf_shell #(
        .CIC_BASE_PERIOD(`CIC_BASE_PERIOD),
        .SHIFT_BASE     (`SHIFT_BASE),
        .CBUF_AW        (CBUF_AW),
        .CBUF_DW        (CBUF_DW),
        .N_ADC          (N_ADC)
    ) dut(
        .lb_clk         (lb_clk),
        .lb_write       (lb_write),
        .lb_addr        (lb_addr),
        .lb_wdata       (lb_wdata),
        .lb_rdata       (lb_rdata),
        .lb_read        (lb_read),
        .lb_rvalid      (lb_rvalid),

        .dsp_clk        (dsp_clk),
        .adc_data_in    (adc_in_flat),
        .dac_data_a_out (dac_a_out),
        .dac_data_b_out (dac_b_out),

        .drive_permit_in (1'b1),
        .slow_permit_in (1'b1),

        .arc_permit_in  (3'b111)
    );

    assign adc_in_flat = {{((N_ADC-3)*DW){1'b0}}, dac_a_out, {DW{1'b0}}, dac_a_out, adc};

    // ---------------------
    // Main sequence
    // ---------------------
    reg [19:0] phase_step_h;
    reg [11:0] phase_step_l;
    wire [31:0] phase_step = {phase_step_h, phase_step_l};
    reg [11:0] modulo;
    reg [18:0] phase_shift=0;
    reg pulse_mode=1'b0;
    reg [11:0] pulse_high_len=10;
    reg dac_permit=1'b1;

    integer wave_samp_per;
    reg [9:0] chan_keep = 10'b11;  // 2 dac + 8 adc
    reg [2:0] shift;
    reg [2:0] inlk_shift;
    reg signed [17:0] amp_setpoint;
    reg signed [17:0] phs_setpoint;
    reg signed [17:0] amp_setpoint_close;
    reg signed [17:0] phs_setpoint_close;
    reg amp_loop_enable = 0;
    reg phs_loop_enable = 0;
    reg amp_loop_reset = 0;
    reg phs_loop_reset = 0;
    reg dsp_reset = 0;

    reg signed [17:0] Kp_amp = 8000;
    reg signed [17:0] Kp_phs = 8000;
    reg signed [17:0] Ki_amp = 400;
    reg signed [17:0] Ki_phs = 400;

    real mon_gain;
    real inlk_gain;
    real open_amp_gain;
    real open_phs_gain;

    real amp_expect;
    real phs_expect;
    reg init_done=0;

    initial begin
        $display("---- Init settings ----");
        wave_samp_per = 1;

        init_dds_task(phase_step_h, phase_step_l, modulo);
        calc_cic_gain_task(wave_samp_per, `SHIFT_BASE, shift, mon_gain);
        calc_cic_gain_task(1, `SHIFT_INLK, inlk_shift, inlk_gain);
        calc_loop_gain_task(
            AMP_SETP_ADC, PHS_SETP_DEG,
            open_amp_gain, open_phs_gain,
            amp_setpoint, phs_setpoint,
            amp_setpoint_close, phs_setpoint_close);
        inlk_gain = inlk_gain * `CORDIC_GAIN;

        amp_expect = AMPI;
        phs_expect = PHSI;

        $display("----DSP Calibration----");
        $display("%20s = %12.5f", "mon_gain", mon_gain);
        $display("%20s = %12d", "inlk_shift", inlk_shift);
        $display("%20s = %12.5f", "inlk_gain", inlk_gain);
        $display("%20s = %12.5f", "open_amp_gain", open_amp_gain);

        $display("%20s = %12.1f", "amp_expect", amp_expect);
        $display("%20s = %12.1f", "phs_expect", phs_expect);
        init_done = 1'b1;
    end

    integer fd;
    reg [255:0] fname;
    reg fail=0;
    real amp_err, phs_err;
    real wfm_amp, wfm_phs;
    integer jx;
    reg inlk_check=0;
    initial begin
        while (!init_done);
        $display("---- Frequency settings ----");
        $display("%20s = %12d", "NUM_DDS", `NUM_DDS);
        $display("%20s = %12d", "DEN_DDS", `DEN_DDS);
        $display("---- Set Registers ----");
        lb_write_task(DDS_PHASE_STEP, phase_step);
        lb_write_task(DDS_PHASE_SHIFT, phase_shift);
        lb_write_task(DDS_MODULO, modulo);
        lb_write_task(DDS_RESET, 1);
        lb_write_task(WAVE_SAMP_PER, wave_samp_per);
        lb_write_task(CHAN_KEEP, chan_keep);
        lb_write_task(WAVE_SHIFT, shift);
        lb_write_task(AMP_SETPOINT, amp_setpoint);
        lb_write_task(PHS_SETPOINT, phs_setpoint);
        lb_write_task(AMP_LOOP_ENABLE, amp_loop_enable);
        lb_write_task(PHS_LOOP_ENABLE, phs_loop_enable);
        lb_write_task(AMP_LOOP_RESET, amp_loop_reset);
        lb_write_task(PHS_LOOP_RESET, phs_loop_reset);
        lb_write_task(DSP_RESET, dsp_reset);
        lb_write_task(KP_AMP, Kp_amp);
        lb_write_task(KP_PHS, Kp_phs);
        lb_write_task(KI_AMP, Ki_amp);
        lb_write_task(KI_PHS, Ki_phs);
        lb_write_task(PULSE_MODE, pulse_mode);
        lb_write_task(PULSE_HIGH_LEN, pulse_high_len);
        lb_write_task(DAC_PERMIT, dac_permit);
        $display("%20s = %12d", "dds_phase_step", phase_step);
        $display("%20s = %12d", "dds_phase_shift", phase_shift);
        $display("%20s = %12d", "dds_modulo", modulo);
        $display("%20s = %12d", "wave_shift", shift);
        $display("%20s = %12d", "wave_samp_per", wave_samp_per);
        $display("%20s = %12d", "chan_keep", chan_keep);
        $display("%20s = %12d", "amp_setpoint", amp_setpoint);
        $display("%20s = %12d", "phs_setpoint", phs_setpoint);
        $display("%20s = %12d", "amp_loop_enable", amp_loop_enable);
        $display("%20s = %12d", "phs_loop_enable", phs_loop_enable);
        $display("%20s = %12d", "amp_loop_reset", amp_loop_reset);
        $display("%20s = %12d", "phs_loop_reset", phs_loop_reset);
        $display("%20s = %12d", "dsp_reset", dsp_reset);
        $display("%20s = %12d", "Kp_amp", Kp_amp);
        $display("%20s = %12d", "Kp_phs", Kp_phs);
        $display("%20s = %12d", "Ki_amp", Ki_amp);
        $display("%20s = %12d", "Ki_phs", Ki_phs);
        $display("%20s = %12d", "pulse_mode", pulse_mode);
        $display("%20s = %12d", "pulse_high_len", pulse_high_len);
        $display("%20s = %12d", "dac_permit", dac_permit);

        if ($value$plusargs("gen_init=%s", fname)) begin
            fd = $fopen(fname, "w");
            $display("gen_init: fname is %0s", fname);
            $fwrite(fd, "{\n");
            $fwrite(fd, "\"%s\": %d,\n", "dds_phase_step", phase_step);
            $fwrite(fd, "\"%s\": %d,\n", "dds_phase_shift", phase_shift);
            $fwrite(fd, "\"%s\": %d,\n", "dds_modulo", modulo);
            $fwrite(fd, "\"%s\": %d,\n", "wave_shift", shift);
            $fwrite(fd, "\"%s\": %d,\n", "wave_samp_per", wave_samp_per);
            $fwrite(fd, "\"%s\": %d,\n", "chan_keep", chan_keep);
            $fwrite(fd, "\"%s\": %d,\n", "amp_setpoint", amp_setpoint);
            $fwrite(fd, "\"%s\": %d,\n", "phs_setpoint", phs_setpoint);
            $fwrite(fd, "\"%s\": %d,\n", "amp_loop_enable", amp_loop_enable);
            $fwrite(fd, "\"%s\": %d,\n", "phs_loop_enable", phs_loop_enable);
            $fwrite(fd, "\"%s\": %d,\n", "amp_loop_reset", amp_loop_reset);
            $fwrite(fd, "\"%s\": %d,\n", "phs_loop_reset", phs_loop_reset);
            $fwrite(fd, "\"%s\": %d,\n", "dsp_reset", dsp_reset);
            $fwrite(fd, "\"%s\": %d,\n", "Kp_amp", Kp_amp);
            $fwrite(fd, "\"%s\": %d,\n", "Kp_phs", Kp_phs);
            $fwrite(fd, "\"%s\": %d,\n", "Ki_amp", Ki_amp);
            $fwrite(fd, "\"%s\": %d,\n", "Ki_phs", Ki_phs);
            $fwrite(fd, "\"%s\": %d,\n", "pulse_mode", pulse_mode);
            $fwrite(fd, "\"%s\": %d,\n", "pulse_high_len", pulse_high_len);
            $fwrite(fd, "\"%s\": %d\n", "dac_permit", dac_permit);
            $fwrite(fd, "}");
            $fclose(fd);
            $finish();
        end

        lb_write_task(DSP_RESET, 1);
        lb_write_task(DSP_RESET, 0);

        lb_write_task(CIRCLE_BUF_FLIP, 1); // discard 1st waveform
        // wait for cbuf_ready
        while (!rdata[0]) lb_read_task(LLRF_CIRCLE_READY, rdata);

        // readout waveform
        lb_write_task(CIRCLE_BUF_FLIP, 1);

        $display("---- Check waveforms ----");
        read_waveform_task(0, wfm_amp, wfm_phs);
        amp_err = wfm_amp / mon_gain - amp_expect;
        fail |= $abs(amp_err / amp_expect) > 0.001;
        $display("Time: %g ns, Cbuf Readout: adc0: amp = %8.1f cnt, expect = %8.1f, %s",
            $time, wfm_amp / mon_gain, amp_expect, fail ? "FAIL":"OK");
        fail |= $abs(wfm_phs - phs_expect) > 0.1;
        $display("Time: %g ns, Cbuf Readout: adc0: phs = %8.2f deg, expect = %8.1f, %s",
            $time, wfm_phs, phs_expect, fail ? "FAIL":"OK");

        // loopback gain check
        read_waveform_task(1, wfm_amp, wfm_phs);
        amp_err = wfm_amp / mon_gain - AMP_SETP_ADC;
        fail |= $abs(amp_err / amp_expect) > 0.001;
        $display("Time: %g ns, Cbuf Readout: adc1: amp = %8.1f cnt, expect = %8.1f, %s",
            $time, wfm_amp / mon_gain, AMP_SETP_ADC, fail ? "FAIL":"OK");
        fail |= $abs(wfm_phs - phs_expect) > 0.1;
        $display("Time: %g ns, Cbuf Readout: adc1: phs = %8.2f deg, expect = %8.1f, %s",
            $time, wfm_phs, phs_expect, fail ? "FAIL":"OK");

        $display("---- Check Min/Max ----");
        // wait for slow_ready
        while (!rdata[1]) lb_read_task(LLRF_CIRCLE_READY, rdata);
        lb_read_task(DSP_SLOW_ADC_MIN_0, rdata);
        amp_err = amp_expect + $signed(rdata[15:0]);
        fail |= amp_err < 0 || (amp_err / amp_expect) > 0.05;
        $display("Time: %g ns, Slow Readout: adc_min_0 = %8d cnt, expect = %8.1f, %s",
            $time, $signed(rdata[15:0]), -amp_expect, fail ? "FAIL":"OK");

        lb_read_task(DSP_SLOW_ADC_MAX_0, rdata);
        amp_err = amp_expect - $signed(rdata[15:0]);
        fail |= amp_err < 0 || (amp_err / amp_expect) > 0.05;
        $display("Time: %g ns, Slow Readout: adc_max_0 = %8d cnt, expect = %8.1f, %s",
            $time, $signed(rdata[15:0]), amp_expect, fail ? "FAIL":"OK");
        lb_read_task(DSP_SLOW_ADC_MIN_1, rdata);
        $display("Time: %g ns, Slow Readout: adc_min_1 = %8d cnt, expect = %8.1f",
            $time, $signed(rdata[15:0]), -AMP_SETP_ADC);
        lb_read_task(DSP_SLOW_ADC_MAX_1, rdata);
        $display("Time: %g ns, Slow Readout: adc_max_1 = %8d cnt, expect = %8.1f",
            $time, $signed(rdata[15:0]), AMP_SETP_ADC);

        $display("---- Check Inlk ----");
        read_inlk_task(0, wfm_amp, wfm_phs);
        amp_err = wfm_amp / inlk_gain - amp_expect;
        fail |= $abs(amp_err / amp_expect) > 0.001;
        $display("Time: %g ns, Inlk Readout: adc_amp_0 = %8.1f cnt, expect = %8.1f, %s",
            $time, wfm_amp / inlk_gain, amp_expect, fail ? "FAIL":"OK");
        fail |= $abs(wfm_phs - phs_expect) > 0.1;
        $display("Time: %g ns, Inlk Readout: adc_phs_0 = %8.2f deg, expect = %8.1f, %s",
            $time, wfm_phs, phs_expect, fail ? "FAIL":"OK");

        read_inlk_task(1, wfm_amp, wfm_phs);
        amp_err = wfm_amp / inlk_gain - AMP_SETP_ADC;
        fail |= $abs(amp_err / amp_setpoint) > 0.001;
        $display("Time: %g ns, Inlk Readout: adc_amp_1 = %8.1f cnt, expect = %8.1f, %s",
            $time, wfm_amp / inlk_gain, AMP_SETP_ADC, fail ? "FAIL":"OK");
        fail |= $abs(wfm_phs - phs_expect) > 0.1;
        $display("Time: %g ns, Inlk Readout: adc_phs_1 = %8.2f deg, expect = %8.1f, %s",
            $time, wfm_phs, phs_expect, fail ? "FAIL":"OK");

        $display("---- Check Close Loop Amp Response ----");
        // may override init register values here
        lb_write_task(AMP_SETPOINT, amp_setpoint_close);
        lb_write_task(PHS_SETPOINT, phs_setpoint_close);
        close_loops_task();
        #20000;  //wait for loop actions
        read_inlk_task(1, wfm_amp, wfm_phs);
        amp_err = wfm_amp / inlk_gain - AMP_SETP_ADC;
        fail |= $abs(amp_err / amp_setpoint) > 0.001;
        $display("Time: %g ns, Loop Readout: adc_amp_1 = %8.1f cnt, expect = %8d, %s",
            $time, wfm_amp / inlk_gain, AMP_SETP_ADC, fail ? "FAIL":"OK");
        fail |= $abs(wfm_phs - phs_expect) > 0.15;
        $display("Time: %g ns, Loop Readout: adc_phs_1 = %8.2f deg, expect = %8.1f, %s",
            $time, wfm_phs, phs_expect, fail ? "FAIL":"OK");

        $display("---- Check Fast Interlock ----");
        lb_write_task(INLK_INLK_MODE_0, 2'b10);
        lb_write_task(INLK_INLK_MODE_3, 2'b10);
        lb_write_task(INLK_AMP_LO_0, 0.99 * amp_expect * inlk_gain);
        lb_write_task(INLK_AMP_HI_0, 1.01 * amp_expect * inlk_gain);
        lb_write_task(INLK_AMP_LO_3, 0.99 * AMP_SETP_ADC * inlk_gain);
        lb_write_task(INLK_AMP_HI_3, 1.01 * AMP_SETP_ADC * inlk_gain);
        # (`DSP_CLK_CYCLE * 20); // wait for settings pass clock domains using cycling wave_cnt
        lb_write_task(INLK_PERMIT_MASK, 10'b00_0000_1001); // look at stimulus and loopback channels
        lb_write_task(INLK_RESET_INLK, 1'b1);
        $display("Inlk: %8s %8s %8s %8s %8s %8s %8s %8s %8s %8s %8s",
            "chan", "mon_amp", "amp_lo", "amp_hi", ">=lo", ">=hi", "mode", "OK", "Permit", "amp", "phs");
        while (dut.inlk.wave_cnt != 0) @ (posedge dsp_clk);
        inlk_check = 1'b1;
        #200;
        inlk_check = 1'b0;

        $display("Time: %g ns, Validation: %s.", $time, !fail ? "PASS":"FAIL");
        $display("##################################################");
        if (!fail) $finish();
        else $stop();
    end

    always @(posedge dsp_clk) begin
        if (fail) $stop();
    end

    // fast interlock checking
    always @(posedge dsp_clk) begin
        #1;
        if (inlk_check && dut.inlk.wave_valid && dut.inlk.wave_cnt[0]) begin
            $display("inlk: %8d %8d %8d %8d %8d %8d %8b %8d %8d %8.1f %8.3f",
                dut.mon_addr_out,
                $signed(dut.mon_amp_out),
                dut.inlk.amp_lo, dut.inlk.amp_hi, dut.inlk.cmpg_lo, dut.inlk.cmpg_hi,
                dut.inlk.inlk_mode,
                dut.inlk.inlk_ok[dut.mon_addr_out],
                dut.inlk_permit_out,
                $signed(dut.mon_amp_out) / inlk_gain,
                $signed(dut.mon_phs_out) * 360.0 / 2**17
            );
            fail |= ~dut.inlk_permit_out;
        end
    end

    // ADC0/1 signal level in gtkwave
    reg signed [15:0] mon_amp_out_0;
    reg signed [16:0] mon_phs_out_0;
    reg signed [15:0] mon_amp_out_1;
    reg signed [16:0] mon_phs_out_1;
    real mon_amp_0;
    real mon_amp_1;
    real mon_phs_0;
    real mon_phs_1;
    real measured_cav_amp;
    real measured_cav_phs;
    always @(posedge dsp_clk) begin
        if (dut.mon_valid_out) begin
            if (dut.mon_addr_out == 3'd0) begin
                mon_amp_out_0 <= dut.mon_amp_out;
                mon_phs_out_0 <= dut.mon_phs_out;
            end
            if (dut.mon_addr_out == 3'd1) begin
                mon_amp_out_1 <= dut.mon_amp_out;
                mon_phs_out_1 <= dut.mon_phs_out;
            end
        end
        mon_amp_0 = mon_amp_out_0 / inlk_gain;
        mon_amp_1 = mon_amp_out_1 / inlk_gain;
        mon_phs_0 = mon_phs_out_0 * 360.0 / 2**17;
        mon_phs_1 = mon_phs_out_1 * 360.0 / 2**17;
        measured_cav_amp = dut.dsp.amp_measured / (2.9337 * `CORDIC_GAIN);
        measured_cav_phs = dut.dsp.phs_measured * 360.0 / 2**18; // deg
        if (measured_cav_phs < -180) measured_cav_phs += 360;
        else if (measured_cav_phs > 180) measured_cav_phs -= 360;
    end

endmodule
