// Extra IP for a design. Copy to top/<design>/design_mid.vh to use.
// Included at the end of marble_zest_mid.vh, so every board, system and
// llrf_shell signal is in scope. Localbus segments 2 and up (lb_write_2,
// lb_read_2, lb_rdata_2, ...) belong to the design; define DESIGN_LB_SEG2 (SYNTH_OPT in
// top/<design>/Makefile) so the lb_rdata mux reads segment 2.
