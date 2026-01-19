`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_TB_SCN_BANK_INTERLEAVE;
    /*
     * Scenario: Bank-interleave stream
     * Traffic: Read-only, rotating banks with same row/col
     * Goal: Maximize bank-level parallelism
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
                ba = dram_ba_t'((issued + j) % (1 << `DRAM_BA_WIDTH));
                ra = 'd0;
                ca = dram_ca_t'((issued + j) % (1 << `DRAM_CA_WIDTH));
                addr = pack_addr(ra, ba, ca);
                issue_read(axi_id_t'(j), addr);
            end
            wait_for_reads(issued + batch);
            issued += batch;
        end

        report_stats("BANK_INTERLEAVE");
        $finish;
    end
endmodule
