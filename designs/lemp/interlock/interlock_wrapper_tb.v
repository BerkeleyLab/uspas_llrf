`timescale 1ns / 1ps
`include "constants.vams"
`include "settings.vams"

module interlock_wrapper_tb;

parameter  LB_VERBOSE       = 1;        // show LB transactions
localparam LB_ADW           = 18;
localparam LB_READ_DELAY    = 3;
parameter  NI               = 8;
localparam MAX_SIM          = 8000000;  // ns
localparam PULSE_IN         = 2000;  // ns
localparam DW               = 16;
localparam DWLO             = 18;
localparam BUF_DWI          = 16;
localparam CLK_CYCLE        = 8;        // ns
parameter  ADC_BUF_AW       = 3;
`define NULL 0

integer cc=0;
reg lb_clk=0, dsp_clk=0;
reg fiducial=0;
reg pulse_in=0;

initial begin
    $display("##################################################");
    $display("    ---- Checking interlock_wrapper.v ----");
    if ($test$plusargs("vcd")) begin
        $dumpfile("interlock_wrapper.vcd");
        $dumpvars(5,interlock_wrapper_tb);
    end
    for (cc=0; cc<=MAX_SIM/`DSP_CLK_CYCLE; cc=cc+1) begin
        dsp_clk=0; #(`DSP_CLK_CYCLE/2);
        dsp_clk=1; #(`DSP_CLK_CYCLE/2);
    end
    $display("Simulation timed-out");
    $display("FAIL");
    $stop();
end

initial begin
    for (cc=0; cc<=MAX_SIM/`FIDUCIAL_P; cc=cc+1) begin
        fiducial=0; #(`FIDUCIAL_P/2);
        fiducial=1; #(`FIDUCIAL_P/2);
    end
end

initial begin
    # 3500
    for (cc=0; cc<=MAX_SIM/PULSE_IN; cc=cc+1) begin
        pulse_in=1; #(PULSE_IN/4);
        pulse_in=0; #(3*PULSE_IN/4);
    end
end

    `include "settings.vh"
    `include "localbus.vh"
    `include "regmap_interlock_wrapper.vh"

    // --------------------------------------------------------------
    //  Generate Clocks
    // --------------------------------------------------------------
    always #(`DSP_CLK_CYCLE/2) dsp_clk = ~dsp_clk;
    always #(CLK_CYCLE/2)     lb_clk  = ~lb_clk;

    // --------------------------------------------------------------
    //  LocalBus functions
    // --------------------------------------------------------------

    reg [31:0] rdata=0;

    reg pass =1;
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
    real AMPI = 10000;
    parameter real PHSI = 0;
    parameter AMP_SETP_ADC = 10000;
    parameter PHS_SETP_DEG = PHSI;

    real theta;
    integer adc_cc=0;
    reg signed [15:0] adc=16'hxxxx;
    reg signed [15:0] adc_dc=16'hxxxx;
    integer adc_cc_start = `CIC_BASE_PERIOD % 20;    // truly important but empirical
    always @(posedge dsp_clk) begin
        adc_cc <= dut.dds_reset ? adc_cc_start : adc_cc + 1'b1; // synchronize with dds LO phase
        theta <= adc_cc * `M_TWO_PI * `NUM_DDS / `DEN_DDS - PHSI * `M_PI / 180;
        adc <= $floor(AMPI * $cos(theta)); // this is a full scale input to the ADC
        adc_dc <= $floor(AMPI); // this is a full scale input to the ADC
    end

    always @(posedge dut.lb_clk) begin
        if (dut.epics_wdog_mon.time_cnt == 1) lb_write_task(EPICS_WDOG_MON_TIMEOUT, 2);
        if (dut.admin_wdog_mon.time_cnt == 1) lb_write_task(ADMIN_WDOG_MON_TIMEOUT, 3);
    end

    reg dds_reset = 1;
    //captured from chassis
    reg [31:0] dds_phase_step = 32'h36DB6BD0;
    reg [18:0] dds_phase_shift = 0;
    reg [11:0] dds_modulo = 8;

    wire [18:0] dds_phase_acc;
    ph_acc dds_lo (
        .clk            (dsp_clk),
        .reset          (dds_reset),
        .en             (1'b1),
        .phase_acc      (dds_phase_acc),
        .phase_step_h   (dds_phase_step[31:12]),
        .phase_step_l   (dds_phase_step[11: 0]),
        .modulo         (dds_modulo)
    );

    // LO for RX (feedback)
    wire signed [DWLO-1:0] cosd, sind;
    cordicg_b22 #(.nstg(20), .width(18)) dds_cordicg_i(
        .clk            (dsp_clk),
        .opin           (2'b00),
        .xin            (18'd`LO_AMP),
        .yin            (18'd0),
        .phasein        (dds_phase_acc + dds_phase_shift),
        .xout           (cosd),
        .yout           (sind)
    );

    wire signed [DWLO-1:0] dds_cos = cosd;
    wire signed [DWLO-1:0] dds_sin = sind;
    wire signed [DW-1:0] kly_rev_in = adc;
    wire signed [DW-1:0] beam_vol_in = adc_dc;
    wire signed [DW-1:0] beam_cur_in = adc_dc;
    wire [NI-1:0] intlk_fault;
    wire [NI-1:0] intlk_latch;
    wire [NI-1:0] intlk_firstf;
    wire          intlk_trig;
    wire          mod_permit_out;
    wire          status_modulator;

    // ---------------------
    // DUT
    // ---------------------
    interlock_wrapper #(.NI(`NI)) dut(
        .clk                (dsp_clk),

        .lb_clk             (lb_clk),
        .lb_addr            (lb_addr),
        .lb_write           (lb_write),
        .lb_read            (lb_read),
        .lb_rvalid          (lb_rvalid),
        .lb_wdata           (lb_wdata),
        .lb_rdata           (lb_rdata),
        .lb_prefill         (lb_prefill),

        .mod_permit_out     (mod_permit_out),
        .status_modulator   (status_modulator),

        .dds_reset          (dds_reset),
		.dds_cos            (dds_cos),
        .dds_sin            (dds_sin),

        .dsp_dac_pll_locked (1'b1),
        .kly_rev_in         (kly_rev_in),
        .beam_vol_in        (beam_vol_in),
        .beam_cur_in        (beam_cur_in),

        .intlk_fault        (intlk_fault),
        .intlk_latch        (intlk_latch),
        .intlk_firstf       (intlk_firstf),
        .intlk_trig         (intlk_trig)
    );

    // ----------------------------------
    // Trigger generation
    // ---------------------------------
    wire dac_permit=1'b1;
    reg dac_permit_int;
    reg fiducial_dly;
    wire drive_on1 = dac_permit_int ? 1'b1 : 1'b0;  // with interlock

    reg [17:0] set_kr_amp_thr=18'h1ffff;
    reg [15:0] set_beam_vol_thr=16'h7fff;
    reg [15:0] set_beam_cur_thr=16'h7fff;

    always @(posedge dut.clk) begin
        fiducial_dly <= fiducial;
        // whenever an interlock occour both DAC are  disabled
        if (|intlk_latch) dac_permit_int <= 0;
        // when no more interocks are latched and a new fiducial arrives the dac permit is as the SW reg
        else if (~(|intlk_latch) & (fiducial & ~fiducial_dly)) dac_permit_int <= dac_permit;
    end

    // the PMOD triggers are the LEMP shell's (designs/lemp/triggers.sv),
    // tested in designs/lemp/tb; this TB checks only the interlocks
    wire [3:0] pmod_trigs = 4'b0;

    // ----------------------------------
    // PMOD1/2 assignments
    // ---------------------------------
    wire [7:0] PMOD1;
    assign PMOD1[0] = 1'b0;

    // FIDUCIAL (TIMING EVR INPUT) no sim
    // reg fiducial_in=0;
    // always @(posedge dsp_clk) begin
    //     fiducial_in <= PMOD1[0];
    // end

    // LLRF INTERLOCKS RELAY OUT control by interlock latched register
    assign PMOD1[1] = ~(|intlk_latch[6:0]) ? 1'b1 : 1'b0;

    //MODULATOR PERMIT OUT control by a reg in interlock_wrapper
    assign PMOD1[2] = 1'b1;

    real status_modulator_r = 1'b0;
    assign PMOD1[3] = status_modulator_r;
    // STATUS FROM MODULATOR IN
    reg status_modulator_in=0;
    always @(posedge dsp_clk) begin
        status_modulator_in <= PMOD1[3];
    end
    assign status_modulator=status_modulator_in;

    // PULSE GEN 0 (MOD TRIGGER)
    assign PMOD1[4] = pmod_trigs[0] & mod_permit_out;
    // PULSE GEN 1 (SSSB GATE)
    // PULSE GEN 2 (SCOP TTL)
    // PULSE GEN 0 (EXTRA)
    assign PMOD1[7:5] = pmod_trigs[3:1];

    // ---------------------
    // Main sequence
    // ---------------------
    reg [31:0] phase_step;
    reg [11:0] modulo;
    reg [18:0] phase_shift=0;
    reg pulse_mode=1'b0;
    reg [11:0] pulse_high_len=10;

    reg [17:0] kly_amp_thr=17'h1ffff;
    reg [0:0]  kly_amp_max_rst=1;

    reg [15:0] beam_vol_thr=17'h7fff;
    reg [0:0]  beam_vol_max_rst=1;

    reg [15:0] beam_cur_thr=17'h7fff;
    reg [0:0]  beam_cur_max_rst=1;

    integer wave_samp_per;
    reg [9:0] chan_keep = 10'b11;  // 2 dac + 8 adc
    reg [2:0] shift;
    reg [2:0] inlk_shift;
    reg amp_loop_enable = 0;
    reg phs_loop_enable = 0;
    reg amp_loop_reset = 0;


    real amp_calc_gain=6.23;
    real mon_gain;
    real inlk_gain;
    real open_amp_gain;
    real open_phs_gain;

    real amp_expect;
    real phs_expect;
    reg init_done=0;

    reg [31:0] phs_shift = 10;
    reg [31:0] phs_shift_delay = 2;

    // interlocks
    reg [31:0] kr_amp_thr = 32'h0001ffff;
    reg [31:0] reset_alarms = 32'h00000001;

    task init_task;
        begin
        $display("---- Init settings ----");
        wave_samp_per = 1;
        dds_reset = 1;

        init_dds_task(phase_step, modulo);
        calc_cic_gain_task(wave_samp_per, `SHIFT_BASE, shift, mon_gain);
        calc_cic_gain_task(1, `SHIFT_INLK, inlk_shift, inlk_gain);
        inlk_gain = inlk_gain * `CORDIC_GAIN;
        amp_expect = AMPI;

        $display("----DSP Calibration----");
        $display("%20s = %12.5f", "mon_gain", mon_gain);
        $display("%20s = %12d", "inlk_shift", inlk_shift);
        $display("%20s = %12.5f", "inlk_gain", inlk_gain);
        $display("%20s = %12.5f", "open_amp_gain", open_amp_gain);

        $display("%20s = %12.1f", "amp_expect", amp_expect);

        init_done = 1'b1;
        end
    endtask

    integer fd;
    reg [255:0] fname;
    reg fail=0;
    real amp_err, phs_err;
    real wfm_amp, wfm_phs;
    integer jx;
    reg inlk_check=0;
    reg signed [DW-1:0] rxbuf [0:2**ADC_BUF_AW];

    initial begin
        init_task();
        while (!init_done);
        $display("---- Frequency settings ----");
        $display("%20s = %12d", "NUM_DDS", `NUM_DDS);
        $display("%20s = %12d", "DEN_DDS", `DEN_DDS);
        $display("---- Set Registers ----");
        lb_write_task(TEST_CLOCK_OK, 1);
        lb_write_task(TEST_LO_FAULT_R, 1);
        lb_write_task(TEST_EPICS_WDOG_OK, 1);
        lb_write_task(EPICS_WDOG_MON_TIMEOUT, 2);
        lb_write_task(TEST_ADMIN_WDOG_OK, 1);
        lb_write_task(ADMIN_WDOG_MON_TIMEOUT, 3);
        //
        lb_write_task(KR_AMP_THR, set_kr_amp_thr);
        lb_write_task(KR_AMP_MAX_RST, 1);
        @(posedge dut.clk);
        lb_write_task(BEAM_VOL_THR, 16'h7fff);
        lb_write_task(BEAM_VOL_MAX_RST, 1);
        @(posedge dut.clk);
        lb_write_task(BEAM_CUR_THR, 16'h7fff);
        lb_write_task(BEAM_CUR_MAX_RST, 1);
        @(posedge dut.clk);
        //

        lb_write_task(INTLK_INTLK_BYP, 8'hff);
        lb_write_task(INTLK_INTLK_RESET, 8'hff);

        $display("%20s = %12d", "dds_phase_step", phase_step);
        $display("%20s = %12d", "dds_phase_shift", phase_shift);
        $display("%20s = %12d", "dds_modulo", modulo);
        $display("%20s = %12d", "INTLK_EN_BYP_MASK", `INTLK_EN_BYP_MASK);
        $display("%20s = %12d", "intlk_en_byp_int", dut.intlk_en_byp_int);
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);


        if ($value$plusargs("gen_init=%s", fname)) begin
            fd = $fopen(fname, "w");
            $display("gen_init: fname is %0s", fname);
            $fwrite(fd, "{\n");
            $fwrite(fd, "\"%s\": %d,\n", "dds_phase_step", phase_step);
            $fwrite(fd, "\"%s\": %d,\n", "dds_phase_shift", phase_shift);
            $fwrite(fd, "\"%s\": %d,\n", "dds_modulo", modulo);
            $fwrite(fd, "\"%s\": %d,\n", "wave_shift", shift);
            $fwrite(fd, "}");
            $fclose(fd);
            $finish();
        end
        #200
        @(posedge dut.clk);
        dds_reset = 0;

        #20
        @(posedge dut.clk);
        $fwrite(fd, "{reset all interlocks\n");
        lb_write_task(INTLK_INTLK_RESET, 8'hff);
        #200

        // ----------------------------
        // bit 0: Internal PLL lock fault TEST
        // ----------------------------
        $display("TEST PLL OK");
        @(posedge dut.clk);
        lb_write_task(TEST_CLOCK_OK , 1);
        #(5*`DSP_CLK_CYCLE)
        $display("Enable BYPASS");
        lb_write_task(INTLK_INTLK_BYP, 8'hFF);
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        #(5*`DSP_CLK_CYCLE)
        $display("reset Latched PLL Interlock");
        lb_write_task(INTLK_INTLK_RESET, 1);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h00);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h00);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h00);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");

        #(20*`DSP_CLK_CYCLE)
        $display("TEST PLL BAD");
        @(posedge dut.clk);
        lb_write_task(TEST_CLOCK_OK , 0);
        #(5*`DSP_CLK_CYCLE)
        $display("reset Latched PLL Interlock");
        lb_write_task(INTLK_INTLK_RESET, 1);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h01);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h00);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h00);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");

        $display("TEST PLL OK");
        @(posedge dut.clk);
        lb_write_task(TEST_CLOCK_OK , 1);
        #(5*`DSP_CLK_CYCLE)
        $display("reset Latched PLL Interlock");
        lb_write_task(INTLK_INTLK_RESET, 1);

        #(20*`DSP_CLK_CYCLE)
        $display("Disable BYPASS");
        lb_write_task(INTLK_INTLK_BYP, 8'hFE);
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h00);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h00);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h00);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");

        #(20*`DSP_CLK_CYCLE)
        $display("TEST PLL BAD");
        @(posedge dut.clk);
        lb_write_task(TEST_CLOCK_OK , 0);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h01);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h01);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h01);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");

        $display("reset Latched PLL Interlock");
        lb_write_task(INTLK_INTLK_RESET, 1);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h01);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h01);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h00);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");

        #(20*`DSP_CLK_CYCLE)
        $display("TEST CLOCK OK");
        @(posedge dut.clk);
        lb_write_task(TEST_CLOCK_OK , 1);
        #(5*`DSP_CLK_CYCLE)
        $display("reset Latched PLL Interlock");
        lb_write_task(INTLK_INTLK_RESET, 1);

        AMPI = 10000;
        // ----------------------------
        // bit 2: Local oscillator out-of-range fault TEST
        // ----------------------------
        $display("TEST Local oscillator OK");
        @(posedge dut.clk);
        lb_write_task(TEST_LO_FAULT_R , 1);
        #(5*`DSP_CLK_CYCLE)
        $display("Enable BYPASS");
        lb_write_task(INTLK_INTLK_BYP, 8'hFF);
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        #(5*`DSP_CLK_CYCLE)
        $display("reset Latched Local oscillator Interlock");
        lb_write_task(INTLK_INTLK_RESET, 4);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h00);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h00);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h00);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");


        #(20*`DSP_CLK_CYCLE)
        $display("TEST Local oscillator BAD");
        @(posedge dut.clk);
        lb_write_task(TEST_LO_FAULT_R , 0);
        #(5*`DSP_CLK_CYCLE)
        $display("reset Latched Local oscillator Interlock");
        lb_write_task(INTLK_INTLK_RESET, 4);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h04);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h00);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h00);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");


        $display("TEST Local oscillator OK");
        @(posedge dut.clk);
        lb_write_task(TEST_LO_FAULT_R , 1);
        #(5*`DSP_CLK_CYCLE)
        $display("reset Latched Local oscillator Interlock");
        lb_write_task(INTLK_INTLK_RESET, 4);

        #(20*`DSP_CLK_CYCLE)
        $display("Disable BYPASS");
        lb_write_task(INTLK_INTLK_BYP, 8'hFB);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h00);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h00);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h00);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");

        #(20*`DSP_CLK_CYCLE)
        $display("TEST Local oscillator BAD");
        @(posedge dut.clk);
        lb_write_task(TEST_LO_FAULT_R , 0);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h04);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h04);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h04);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");

        $display("reset Latched PLL Interlock");
        lb_write_task(INTLK_INTLK_RESET, 4);
        #(20*`DSP_CLK_CYCLE)
        fail |= (dut.intlk_fault != 8'h04);
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_latch != 8'h04);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch, "%s", fail ? "FAIL":"OK");
        fail |= (dut.intlk_firstf != 8'h00);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf, "%s", fail ? "FAIL":"OK");

        #(20*`DSP_CLK_CYCLE)
        $display("TEST Local oscillator OK");
        @(posedge dut.clk);
        lb_write_task(TEST_LO_FAULT_R , 1);
        #(5*`DSP_CLK_CYCLE)
        $display("reset Latched Local oscillator Interlock");
        lb_write_task(INTLK_INTLK_RESET, 4);

        // ----------------------------
        // bit 3: Klystron reverse amplitude TEST
        // ----------------------------
        AMPI = 15000;
        #(50*`DSP_CLK_CYCLE)
        $display("TEST Klystron reverse amplitude OK");
        $display("Enable BYPASS and set thr to max");
        lb_write_task(INTLK_INTLK_BYP, 8'hFF);
        lb_write_task(KR_AMP_THR, set_kr_amp_thr);
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        $display("TEST Klystron reverse amplitude below thr");
        lb_write_task(KR_AMP_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron reverse amplitude MAX", dut.kr_amp_max);
        set_kr_amp_thr=(dut.kr_amp_max+30);
        $display("%20s = %12d", "set Klystron reverse amplitude threashold :", set_kr_amp_thr);
        @(posedge dut.clk);
        lb_write_task(KR_AMP_THR , set_kr_amp_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        @(posedge dut.clk);
        $display("TEST Klystron reverse amplitude above thr");
        lb_write_task(KR_AMP_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron reverse amplitude MAX", dut.kr_amp_max);
        set_kr_amp_thr=(dut.kr_amp_max-30);
        $display("%20s = %12d", "set Klystron reverse amplitude threashold :", set_kr_amp_thr);
        @(posedge dut.clk);
        lb_write_task(KR_AMP_THR , set_kr_amp_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        $display("Disable BYPASS and set thr higher than max");
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron reverse amplitude MAX", dut.kr_amp_max);
        set_kr_amp_thr=(dut.kr_amp_max+30);
        $display("%20s = %12d", "set Klystron reverse amplitude threashold :", set_kr_amp_thr);
        @(posedge dut.clk);
        lb_write_task(KR_AMP_THR , set_kr_amp_thr);
        #(20*`DSP_CLK_CYCLE)
        $display("Disable BYPASS and set thr to max");
        lb_write_task(INTLK_INTLK_BYP, 8'hF7);
        lb_write_task(KR_AMP_THR, 18'h1ffff);
        #(5*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        $display("TEST Klystron reverse amplitude below thr");
        lb_write_task(KR_AMP_MAX_RST, 1);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        @(posedge dut.clk);
        $display("TEST Klystron reverse amplitude above thr");
        lb_write_task(KR_AMP_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron reverse amplitude MAX", dut.kr_amp_max);
        set_kr_amp_thr=(dut.kr_amp_max-30);
        $display("%20s = %12d", "set Klystron reverse amplitude threashold :", set_kr_amp_thr);
        @(posedge dut.clk);
        lb_write_task(KR_AMP_THR , set_kr_amp_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        $display("Set Klystron reverse amplitude thrashold to max");
        #(10*`DSP_CLK_CYCLE)
        set_kr_amp_thr=18'h1FFFF;
        $display("%20s = %12d", "set Klystron reverse amplitude threashold :", set_kr_amp_thr);
        @(posedge dut.clk);
        lb_write_task(KR_AMP_THR , set_kr_amp_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        // ----------------------------
        // bit 4: Klystron Beam Voltage TEST
        // ----------------------------
        AMPI = -15000;
        #(50*`DSP_CLK_CYCLE)
        $display("TEST Klystron Beam Voltage OK");
        $display("Enable BYPASS and set thr to max");
        lb_write_task(INTLK_INTLK_BYP, 8'hFF);
        lb_write_task(BEAM_VOL_THR, set_beam_vol_thr);
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        $display("TEST Klystron reverse amplitude below thr");
        lb_write_task(BEAM_VOL_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron Beam Voltage amplitude MAX", dut.beam_vol_max);
        $display("%20s = %12d", "Klystron Beam Voltage amplitude mIn", dut.beam_vol_min);
        set_beam_vol_thr=(dut.beam_vol_max+30);
        $display("%20s = %12d", "set Klystron Beam Voltage amplitude threashold :", set_beam_vol_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_VOL_THR , set_beam_vol_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h10);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        @(posedge dut.clk);
        $display("TEST Klystron Beam Voltage amplitude above thr");
        lb_write_task(BEAM_VOL_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron Beam Voltage amplitude MAX", dut.beam_vol_max);
        set_beam_vol_thr=(dut.beam_vol_max-30);
        $display("%20s = %12d", "set Klystron Beam Voltage amplitude threashold :", set_beam_vol_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_VOL_THR , set_beam_vol_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h10);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        $display("Disable BYPASS and set thr higher than max");
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron Beam Voltage amplitude MAX", dut.beam_vol_max);
        set_beam_vol_thr=(dut.beam_vol_max+30);
        $display("%20s = %12d", "set Klystron Beam Voltage amplitude threashold :", set_beam_vol_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_VOL_THR , set_beam_vol_thr);
        #(20*`DSP_CLK_CYCLE)
        $display("Disable BYPASS and set thr to max");
        lb_write_task(INTLK_INTLK_BYP, 8'hEF);
        lb_write_task(BEAM_VOL_THR, 16'h7fff);
        #(5*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        $display("TEST Klystron Beam Voltage amplitude below thr");
        lb_write_task(BEAM_VOL_MAX_RST, 1);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h10);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        @(posedge dut.clk);
        $display("TEST Klystron Beam Voltage amplitude above thr");
        lb_write_task(BEAM_VOL_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron Beam Voltage amplitude MAX", dut.beam_vol_max);
        set_beam_vol_thr=(dut.beam_vol_max-30);
        $display("%20s = %12d", "set Klystron Beam Voltage amplitude threashold :", set_beam_vol_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_VOL_THR , set_beam_vol_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h10);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        $display("Set Klystron Beam Voltage amplitude thrashold to max");
        #(10*`DSP_CLK_CYCLE)
        set_beam_vol_thr=16'h7FFF;
        $display("%20s = %12d", "set Klystron Beam Voltage amplitude threashold :", set_beam_vol_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_VOL_THR , set_beam_vol_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h10);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        // ----------------------------
        // bit 5: Klystron Beam Current TEST
        // ----------------------------
        AMPI = 15000;
        #(50*`DSP_CLK_CYCLE)
        $display("TEST Klystron Beam Current OK");
        $display("Enable BYPASS and set thr to max");
        lb_write_task(INTLK_INTLK_BYP, 8'hFF);
        lb_write_task(BEAM_CUR_THR, set_beam_cur_thr);
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        $display("TEST Klystron reverse amplitude below thr");
        lb_write_task(BEAM_CUR_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron Beam Current amplitude MAX", dut.beam_cur_max);
        $display("%20s = %12d", "Klystron Beam Current amplitude mIn", dut.beam_cur_min);
        set_beam_cur_thr=(dut.beam_cur_max+30);
        $display("%20s = %12d", "set Klystron Beam Current amplitude threashold :", set_beam_cur_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_CUR_THR , set_beam_cur_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h20);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        @(posedge dut.clk);
        $display("TEST Klystron Beam Current amplitude above thr");
        lb_write_task(BEAM_CUR_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron Beam Current amplitude MAX", dut.beam_cur_max);
        set_beam_cur_thr=(dut.beam_cur_max-30);
        $display("%20s = %12d", "set Klystron Beam Current amplitude threashold :", set_beam_cur_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_CUR_THR , set_beam_cur_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h20);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        $display("Disable BYPASS and set thr higher than max");
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron Beam Current amplitude MAX", dut.beam_cur_max);
        set_beam_cur_thr=(dut.beam_cur_max+30);
        $display("%20s = %12d", "set Klystron Beam Current amplitude threashold :", set_beam_cur_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_CUR_THR , set_beam_cur_thr);
        #(20*`DSP_CLK_CYCLE)
        $display("Disable BYPASS and set thr to max");
        lb_write_task(INTLK_INTLK_BYP, 8'hDF);
        lb_write_task(BEAM_CUR_THR, 16'h7fff);
        #(5*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_intlk_byp", dut.intlk_intlk_byp);
        $display("TEST Klystron Beam Current amplitude below thr");
        lb_write_task(BEAM_CUR_MAX_RST, 1);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h20);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        @(posedge dut.clk);
        $display("TEST Klystron Beam Current amplitude above thr");
        lb_write_task(BEAM_CUR_MAX_RST, 1);
        #(10*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "Klystron Beam Current amplitude MAX", dut.beam_cur_max);
        set_beam_cur_thr=(dut.beam_cur_max-30);
        $display("%20s = %12d", "set Klystron Beam Current amplitude threashold :", set_beam_cur_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_CUR_THR , set_beam_cur_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h20);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        $display("Set Klystron Beam Current amplitude thrashold to max");
        #(10*`DSP_CLK_CYCLE)
        set_beam_cur_thr=16'h7FFF;
        $display("%20s = %12d", "set Klystron Beam Current amplitude threashold :", set_beam_cur_thr);
        @(posedge dut.clk);
        lb_write_task(BEAM_CUR_THR , set_beam_cur_thr);
        #(25*`DSP_CLK_CYCLE)
        lb_write_task(INTLK_INTLK_RESET, 8'h20);
        #(20*`DSP_CLK_CYCLE)
        $display("%20s = %12d", "intlk_fault", dut.intlk_fault);
        $display("%20s = %12d", "intlk_latch", dut.intlk_latch);
        $display("%20s = %12d", "intlk_firstf", dut.intlk_firstf);

        // ----------------------------
        // bit 7: Modulator status TEST
        // ----------------------------
        #(50*`DSP_CLK_CYCLE)
        $display("TEST Modulator Status");
        status_modulator_r = 1;
        #(300*`DSP_CLK_CYCLE)
        status_modulator_r = 0;
        #(300*`DSP_CLK_CYCLE)

        // ----------------------------
        // TEST DONE
        // ----------------------------

        #500
        $display("\n##################################################");
        $display("Time: %g ns, Validation: %s.", $time, !fail ? "PASS":"FAIL");
        $display("##################################################");
        if (!fail) $finish();
        else $stop();
    end

    always @(posedge dsp_clk) begin
        if (fail) $stop();
    end

endmodule
