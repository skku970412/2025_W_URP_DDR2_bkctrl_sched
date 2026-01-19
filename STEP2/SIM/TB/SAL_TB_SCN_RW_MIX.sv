`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_TB_SCN_RW_MIX;
    /*
     * Scenario: Read/Write mix
     * Traffic: Independent read and write streams (50/50)
     * Goal: Observe contention between RD/WR and latency impact
     */
    `include "SAL_TB_COMMON.svh"

    localparam int NUM_READS = 64;
    localparam int NUM_WRITES = 64;
    localparam int RD_WINDOW = 4;
    localparam int WR_WINDOW = 2;

    task run_read_stream();
        int issued;
        issued = 0;
        while (issued < NUM_READS) begin
            int batch;
            batch = (NUM_READS - issued > RD_WINDOW) ? RD_WINDOW : (NUM_READS - issued);
            for (int j = 0; j < batch; j++) begin
                axi_addr_t addr;
                addr = pack_addr(rand_ra(), rand_ba(), rand_ca());
                issue_read(axi_id_t'(j), addr);
            end
            wait_for_reads(issued + batch);
            issued += batch;
        end
    endtask

    task run_write_stream();
        int issued;
        issued = 0;
        while (issued < NUM_WRITES) begin
            int batch;
            batch = (NUM_WRITES - issued > WR_WINDOW) ? WR_WINDOW : (NUM_WRITES - issued);
            for (int j = 0; j < batch; j++) begin
                axi_addr_t addr;
                addr = pack_addr(rand_ra(), rand_ba(), rand_ca());
                issue_write(axi_id_t'(j), addr, rand_data());
            end
            wait_for_writes(issued + batch);
            issued += batch;
        end
    endtask

    initial begin
        init_tb();

        fork
            run_read_stream();
            run_write_stream();
        join

        report_stats("RW_MIX");
        report_write_stats("RW_MIX");
        $finish;
    end
endmodule
