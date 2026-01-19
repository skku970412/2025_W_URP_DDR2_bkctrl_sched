`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_TB_SCN_ROW_HIT;
    /*
     * Scenario: Row-hit stream
     * Traffic: Read-only, fixed bank/row, sequential columns
     * Goal: Maximize row-hit rate and observe best-case latency
     */
    `include "SAL_TB_COMMON.svh"

    localparam int NUM_REQ = 256;
    localparam int RD_WINDOW = 16;

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
                ra = 'd0;
                ca = dram_ca_t'((issued + j) % (1 << `DRAM_CA_WIDTH));
                addr = pack_addr(ra, ba, ca);
                issue_read(axi_id_t'(j), addr);
            end
            issued += batch;
            throttle_reads(RD_WINDOW);
        end

        wait_for_reads(NUM_REQ);
        report_stats("ROW_HIT");
        $finish;
    end
endmodule
