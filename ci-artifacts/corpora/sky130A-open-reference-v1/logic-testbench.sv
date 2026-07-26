module hosted_probe_tb;
    reg a;
    wire y;

    hosted_probe dut (
        .a(a),
        .y(y)
    );

    initial begin
        a = 1'b0;
        #1;
        if (y !== 1'b0) begin
            $fatal(1, "Expected y=0 for a=0");
        end

        a = 1'b1;
        #1;
        if (y !== 1'b1) begin
            $fatal(1, "Expected y=1 for a=1");
        end

        $display("HOSTED_IVERILOG_SIMULATION_COMPLETE");
        $finish;
    end
endmodule
