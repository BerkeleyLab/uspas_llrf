`default_nettype none

// LEMP design I/O of designs/lemp/llrf_shell.sv (plan 14c), connected in
// top/lemp/design_mid.vh: interlock_wrapper, the PMOD triggers, the SSSB and
// the EVR events.
package design_pkg;
    import llrf_shell_pkg::DWLO;

    localparam int NI = 8;  // interlocks latched by interlock_wrapper

    typedef struct packed {
        logic [NI-1:0] intlk_latch;     // interlock_wrapper latched faults
        logic          sssb_alarm;      // SSSB status (ZEST_PMOD1)
        logic          sssb_rf_status;
    } design_in_t;

    typedef struct packed {
        logic            dds_reset;     // RX LO, to interlock_wrapper's DDC
        logic [DWLO-1:0] dds_cos;
        logic [DWLO-1:0] dds_sin;
        logic [3:0]      pmod_trigs;    // PMOD triggers
        logic            sssb_rf_switch;  // SSSB controls (ZEST_PMOD1)
        logic            sssb_rst;
        logic [3:0]      evr_events;    // EVR event strobes, for diagnostics
    } design_out_t;
endpackage

`default_nettype wire
