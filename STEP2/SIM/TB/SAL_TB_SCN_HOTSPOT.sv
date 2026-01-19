`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_TB_SCN_HOTSPOT;
    /*
     * Scenario: Hotspot skew
     * Traffic: Read-only, 80% to a single bank/row, 20% random
     * Goal: Stress fairness and observe tail latency
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
                axi_addr_t addr;
                if ($urandom_range(99) < 80) begin
                    addr = pack_addr('d0, 'd0, dram_ca_t'((issued + j) % (1 << `DRAM_CA_WIDTH)));
                end else begin
                    addr = pack_addr(rand_ra(), rand_ba(), rand_ca());
                end
                issue_read(axi_id_t'(j), addr);
            end
            issued += batch;
            throttle_reads(RD_WINDOW);
        end

        wait_for_reads(NUM_REQ);
        report_stats("HOTSPOT");
        $finish;
    end
endmodule
