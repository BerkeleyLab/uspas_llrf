// LEMP llrf_shell ports (designs/lemp/llrf_shell.sv). Until the LEMP top level
// (plan step 9e) connects interlock_wrapper and the pins, the inputs are held
// inactive: no interlock latched, SSSB alarm and RF status low.
,
.intlk_latch_in     (8'b0),
.sssb_alarm         (1'b0),
.sssb_rf_status     (1'b0),
.dds_reset_out      (),
.dds_cos            (),
.dds_sin            (),
.pmod_trigs         (),
.sssb_rf_switch_out (),
.sssb_rst_out       (),
.evr_events         ()
