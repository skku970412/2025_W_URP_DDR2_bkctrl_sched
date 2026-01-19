`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_TB_SCN_FAIRNESS;
    /*
     * Scenario: Fairness stress
     * Traffic: Heavy stream (IDs 0..3) + light stream (IDs 4..7)
     * Goal: Observe tail latency for light requests under pressure
     */
    `include "SAL_TB_COMMON.svh"

    localparam int NUM_HEAVY = 64;
    localparam int NUM_LIGHT = 16;
    localparam int RD_WINDOW = 4;

    initial begin
        int heavy_issued;
        int light_issued;
        int total_issued;

        init_tb();

        heavy_issued = 0;
        light_issued = 0;
        total_issued = 0;

        while (heavy_issued < NUM_HEAVY || light_issued < NUM_LIGHT) begin
            int batch;

            if (heavy_issued < NUM_HEAVY) begin
                batch = (NUM_HEAVY - heavy_issued > RD_WINDOW) ? RD_WINDOW : (NUM_HEAVY - heavy_issued);
                for (int j = 0; j < batch; j++) begin
                    axi_addr_t addr;
                    addr = pack_addr('d0, 'd0, dram_ca_t'((heavy_issued + j) % (1 << `DRAM_CA_WIDTH)));
                    issue_read(axi_id_t'(j), addr);
                end
                heavy_issued += batch;
                total_issued += batch;
            end

            if (light_issued < NUM_LIGHT) begin
                axi_addr_t addr;
                axi_id_t lid;
                lid = axi_id_t'(RD_WINDOW + (light_issued % RD_WINDOW));
                addr = pack_addr(
                    dram_ra_t'((light_issued % 4) + 1),
                    dram_ba_t'((light_issued % ((1 << `DRAM_BA_WIDTH) - 1)) + 1),
                    dram_ca_t'((light_issued * 3) % (1 << `DRAM_CA_WIDTH))
                );
                issue_read(lid, addr);
                light_issued += 1;
                total_issued += 1;
            end

            wait_for_reads(total_issued);
        end

        report_stats("FAIRNESS");
        report_id_stats();
        $finish;
    end
endmodule
