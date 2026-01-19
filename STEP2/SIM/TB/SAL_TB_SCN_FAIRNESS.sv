`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_TB_SCN_FAIRNESS;
    /*
     * Scenario: Fairness stress
     * Traffic: Heavy stream (ID 0) + light stream (IDs 1..4)
     * Goal: Observe tail latency for light requests under pressure
     */
    `include "SAL_TB_COMMON.svh"

    localparam int NUM_HEAVY = 512;
    localparam int NUM_LIGHT = 128;
    localparam int RD_WINDOW = 32;
    localparam int HEAVY_BURST = 32;
    localparam int LIGHT_ID_BASE = 1;
    localparam int LIGHT_ID_COUNT = 4;
    localparam axi_id_t HEAVY_ID = axi_id_t'(0);

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
                batch = (NUM_HEAVY - heavy_issued > HEAVY_BURST) ? HEAVY_BURST : (NUM_HEAVY - heavy_issued);
                for (int j = 0; j < batch; j++) begin
                    axi_addr_t addr;
                    addr = pack_addr('d0, 'd0, dram_ca_t'((heavy_issued + j) % (1 << `DRAM_CA_WIDTH)));
                    issue_read(HEAVY_ID, addr);
                end
                heavy_issued += batch;
                total_issued += batch;
            end

            if (light_issued < NUM_LIGHT) begin
                axi_addr_t addr;
                axi_id_t lid;
                lid = axi_id_t'(LIGHT_ID_BASE + (light_issued % LIGHT_ID_COUNT));
                addr = pack_addr(
                    dram_ra_t'((light_issued % 4) + 1),
                    dram_ba_t'((light_issued % ((1 << `DRAM_BA_WIDTH) - 1)) + 1),
                    dram_ca_t'((light_issued * 3) % (1 << `DRAM_CA_WIDTH))
                );
                issue_read(lid, addr);
                light_issued += 1;
                total_issued += 1;
            end

            throttle_reads(RD_WINDOW);
        end

        wait_for_reads(total_issued);
        report_stats("FAIRNESS");
        report_id_stats();
        $finish;
    end
endmodule
