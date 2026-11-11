// LEMP signals between llrf_shell (design_shell_ports.vh) and the interlock
// and pins in design_mid.vh
wire [7:0]  intlk_latch;     // interlock_wrapper latched faults
wire [3:0]  pmod_trigs;      // PMOD triggers
wire [3:0]  evr_events;      // EVR event strobes, for diagnostics
wire        dds_reset;       // RX LO, to interlock_wrapper's DDC
wire [17:0] dds_cos;
wire [17:0] dds_sin;
reg         sssb_alarm = 0;  // SSSB status in (ZEST_PMOD1)
reg         sssb_rf_status = 0;
wire        sssb_rf_switch;  // SSSB controls out (ZEST_PMOD1)
wire        sssb_rst;
