// Extra IP for a design. Copy to top/<design>/design_mid.vh to use.
// It drives the shell's design_in (design_pkg; none here) and may use its
// design_out.
// Included at the end of marble_zest_mid.vh, so every board, system and
// llrf_shell signal is in scope. Localbus segments 2 and up (lb_write_2,
// lb_read_2, lb_rdata_2, ...) belong to the design; define DESIGN_LB_SEG2 (SYNTH_OPT in
// top/<design>/Makefile) so the lb_rdata mux reads segment 2.
assign design_in = '0;  // the base shell has no design I/O
