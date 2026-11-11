// LEMP llrf_shell ports (designs/lemp/llrf_shell.sv), connected in
// design_mid.vh: interlock_wrapper, PMOD triggers, SSSB and EVR events
,
.intlk_latch_in     (intlk_latch),
.sssb_alarm         (sssb_alarm),
.sssb_rf_status     (sssb_rf_status),
.dds_reset_out      (dds_reset),
.dds_cos            (dds_cos),
.dds_sin            (dds_sin),
.pmod_trigs         (pmod_trigs),
.sssb_rf_switch_out (sssb_rf_switch),
.sssb_rst_out       (sssb_rst),
.evr_events         (evr_events)
