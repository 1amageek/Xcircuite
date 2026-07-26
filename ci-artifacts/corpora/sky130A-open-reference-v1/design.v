module hosted_probe(input a, output y);
  sky130_fd_sc_hd__buf_1 buffer_instance(.A(a), .X(y));
endmodule
