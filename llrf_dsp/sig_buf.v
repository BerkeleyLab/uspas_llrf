
module sig_buf #(
    parameter integer AW=12,
    parameter integer DW=16
) (
    // sig_clk domain
    input           sig_clk,
    input           sig_val,
    input [DW-1:0]  sig_dat,
    input           sig_last,
    output [31:0]   buf_count,
    // lb_clk domain
    input           lb_clk,
    input           lb_flip_buf,
    input [AW-1:0]  lb_addr,
    output [DW-1:0] lb_rdata,
    output          buf_ready
);

    // ------
    // Double-buffered circular buffer
    // ------
    wire buf_sync, buf_transferred;
    circle_buf #(
        .aw        (AW),
        .dw        (DW),
        .stat_w    (32),
        .auto_flip (0)
    ) i_circle_buf (
        .iclk            (sig_clk),
        .d_in            (sig_dat),
        .stb_in          (sig_val),
        .boundary        (sig_last),
        .stop            (1'b0),
        .buf_sync        (buf_sync),
        .buf_transferred (buf_transferred),
        .oclk            (lb_clk),
        .enable          (buf_ready),
        .read_addr       (lb_addr),
        .d_out           (lb_rdata),
        .stb_out         (lb_flip_buf),
        .buf_count       (buf_count),
        .buf_stat        (),
        .debug_stat      (),
        .buf_stat2       ()
    );

endmodule
