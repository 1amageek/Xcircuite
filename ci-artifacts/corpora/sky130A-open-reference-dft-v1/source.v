module hosted_dft_probe(
  clock,
  data_in,
  set_b,
  test_mode,
  data_out
);
  input clock;
  input data_in;
  input set_b;
  input test_mode;
  output data_out;

  sky130_fd_sc_hd__dfstp_1 u_scan_0(
    .Q(data_out),
    .D(data_in),
    .CLK(clock),
    .SET_B(set_b)
  );
endmodule
