module gen_chan_keep_iq #(
    parameter N_CH=8
) (
    input [N_CH-1:0] chan_keep,
    output [2*N_CH-1:0] chan_keep_iq
);

genvar ix;
generate for (ix=0; ix<N_CH; ix=ix+1)
    begin: gen_chan_keep
        assign chan_keep_iq[2*ix] = chan_keep[ix];
        assign chan_keep_iq[2*ix+1] = chan_keep[ix];
    end
endgenerate

endmodule
