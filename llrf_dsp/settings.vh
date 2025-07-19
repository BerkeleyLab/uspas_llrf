`include "settings.vams"

task init_dds_task (
    output [31:0] phase_step,
    output [11:0] modulo
);
    integer m, r;
    reg [19:0] phase_step_h;
    reg [11:0] phase_step_l;
    begin
        m = 4096 / `DEN_DDS;
        modulo = 4096 - m * `DEN_DDS;
        r = {1'b1,{20{1'b0}}} * `NUM_DDS;
        phase_step_h =  r / `DEN_DDS;
        phase_step_l = (r % `DEN_DDS) * m;
        phase_step = {phase_step_h, phase_step_l};
    end
endtask

task calc_cic_gain_task (
    input [6:0] wave_samp_per,
    input [4:0] shift_base,
    output [2:0] shift,
    output real mon_gain
);
    real cic_R;
    real cic_bit_growth;
    real cic_snr_bit_growth;
    real full_shift;
    begin
        cic_R = wave_samp_per * `CIC_BASE_PERIOD;
        cic_bit_growth = 2 * $ln(cic_R) / $ln(2);
        cic_snr_bit_growth = $ln(cic_R/2) / $ln(2) / 2;
        full_shift = $floor(cic_bit_growth - cic_snr_bit_growth);
        shift = $max((full_shift - shift_base)/2, 0);
        mon_gain = 2**(cic_bit_growth - shift_base + 2 - 2*shift);
    end
endtask

task calc_loop_gain_task (
    input signed [17:0] amp_setpoint_adc,
    input signed [17:0] phs_setpoint_deg,
    output real open_amp_gain,
    output real open_phs_gain,
    output signed [17:0] amp_setpoint_open,
    output signed [17:0] phs_setpoint_open,
    output signed [17:0] amp_setpoint_close,
    output signed [17:0] phs_setpoint_close
);
    begin
        // Gain = `LO_AMP * `CORDIC_GAIN / 2**18 / 2 = 0.235068
        open_amp_gain = 2**17 / (`CORDIC_GAIN * `LO_AMP * `CORDIC_GAIN); //Because of 2 cordics
        open_phs_gain = 0; // deg
        amp_setpoint_open = amp_setpoint_adc * open_amp_gain;
        phs_setpoint_open = (phs_setpoint_deg + open_phs_gain) / 360 * 2**18;
        amp_setpoint_close = amp_setpoint_adc * `AMP_RX_GAIN;
        phs_setpoint_close = (phs_setpoint_deg + open_phs_gain) / 360 * 2**18;
    end
endtask
