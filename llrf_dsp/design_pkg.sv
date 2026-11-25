`default_nettype none

// Design I/O of the base shell (llrf_dsp/llrf_shell.sv): its design_in and
// design_out ports, typed per design (plan 14c). A design with its own shell
// and I/O has its own design_pkg (designs/lemp/design_pkg.sv); the top
// (top/common/marble_zest_mid.vh) connects them, and the design's
// design_mid.vh drives design_in and uses design_out. The base shell has no
// design I/O: one unused bit each (a packed struct cannot be empty).
package design_pkg;
    typedef struct packed {
        logic unused;
    } design_in_t;

    typedef struct packed {
        logic unused;
    } design_out_t;
endpackage

`default_nettype wire
