`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_TB_SCN_RANDOM;
    /*
     * Scenario: Random uniform stream
     * Traffic: Read-only, uniform random bank/row/col
     * Goal: Approximate worst-case locality
     */
    `include "SAL_TB_COMMON.svh"

    localparam int NUM_REQ = 128;
    localparam int RD_WINDOW = 4;

    initial begin
        init_tb();

        for (int issued = 0; issued < NUM_REQ; ) begin
            int batch;
            batch = (NUM_REQ - issued > RD_WINDOW) ? RD_WINDOW : (NUM_REQ - issued);
            for (int j = 0; j < batch; j++) begin
                axi_addr_t addr;
                addr = pack_addr(rand_ra(), rand_ba(), rand_ca());
                issue_read(axi_id_t'(j), addr);
            end
            wait_for_reads(issued + batch);
            issued += batch;
        end

        report_stats("RANDOM");
        $finish;
    end
endmodule
