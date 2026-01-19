`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_TB_SCN_ROW_CONFLICT;
    /*
     * Scenario: Row-conflict stream
     * Traffic: Read-only, same bank, alternating rows
     * Goal: Stress PRE/ACT and observe worst-case row misses
     */
    `include "SAL_TB_COMMON.svh"

    localparam int NUM_REQ = 64;
    localparam int RD_WINDOW = 4;

    initial begin
        init_tb();

        for (int issued = 0; issued < NUM_REQ; ) begin
            int batch;
            batch = (NUM_REQ - issued > RD_WINDOW) ? RD_WINDOW : (NUM_REQ - issued);
            for (int j = 0; j < batch; j++) begin
                dram_ba_t ba;
                dram_ra_t ra;
                dram_ca_t ca;
                axi_addr_t addr;
                ba = 'd0;
                ra = dram_ra_t'((issued + j) & 1);
                ca = 'd0;
                addr = pack_addr(ra, ba, ca);
                issue_read(axi_id_t'(j), addr);
            end
            wait_for_reads(issued + batch);
            issued += batch;
        end

        report_stats("ROW_CONFLICT");
        $finish;
    end
endmodule
