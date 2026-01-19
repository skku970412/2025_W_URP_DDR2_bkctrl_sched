`ifndef SAL_TB_COMMON_SVH
`define SAL_TB_COMMON_SVH

    // clock & reset
    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #(`CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    APB_IF                          apb_if      (.clk(clk), .rst_n(rst_n));
    AXI_A_IF                        axi_ar_if   (.clk(clk), .rst_n(rst_n));
    AXI_R_IF                        axi_r_if    (.clk(clk), .rst_n(rst_n));
    AXI_A_IF                        axi_aw_if   (.clk(clk), .rst_n(rst_n));
    AXI_W_IF                        axi_w_if    (.clk(clk), .rst_n(rst_n));
    AXI_B_IF                        axi_b_if    (.clk(clk), .rst_n(rst_n));

    DFI_CTRL_IF                     dfi_ctrl_if (.clk(clk), .rst_n(rst_n));
    DFI_WR_IF                       dfi_wr_if   (.clk(clk), .rst_n(rst_n));
    DFI_RD_IF                       dfi_rd_if   (.clk(clk), .rst_n(rst_n));

    DDR_IF                          ddr_if      ();

    SAL_DDR_CTRL                    u_dram_ctrl
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        // APB interface
        .apb_if                     (apb_if),

        // AXI interface
        .axi_ar_if                  (axi_ar_if),
        .axi_aw_if                  (axi_aw_if),
        .axi_w_if                   (axi_w_if),
        .axi_b_if                   (axi_b_if),
        .axi_r_if                   (axi_r_if),

        // DFI interface
        .dfi_ctrl_if                (dfi_ctrl_if),
        .dfi_wr_if                  (dfi_wr_if),
        .dfi_rd_if                  (dfi_rd_if)
    );

    DDRPHY                          u_ddrphy
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .dfi_ctrl_if                (dfi_ctrl_if),
        .dfi_wr_if                  (dfi_wr_if),
        .dfi_rd_if                  (dfi_rd_if),

        .ddr_if                     (ddr_if)
    );

    ddr2_dimm                       u_rank0
    (
        .ddr_if                     (ddr_if),
        .cs_n                       (ddr_if.cs_n[0])
    );

    ddr2_dimm                       u_rank1
    (
        .ddr_if                     (ddr_if),
        .cs_n                       (ddr_if.cs_n[1])
    );

    // cycle counter
    int unsigned                    cycle;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle                   <= 0;
        else
            cycle                   <= cycle + 1;
    end

    localparam int MAX_ID = (1 << `AXI_ID_WIDTH);

    int unsigned rd_issue_q [0:MAX_ID-1][$];
    int unsigned wr_issue_q [0:MAX_ID-1][$];

    int unsigned rd_completed;
    int unsigned wr_completed;
    int unsigned rd_issued_total;
    int unsigned wr_issued_total;
    int unsigned rd_lat_sum;
    int unsigned wr_lat_sum;
    int unsigned rd_lat_max;
    int unsigned wr_lat_max;
    int unsigned rd_lat_max_id [0:MAX_ID-1];
    int unsigned rd_issued_id  [0:MAX_ID-1];
    int unsigned rd_completed_id [0:MAX_ID-1];
    int unsigned wr_issued_id  [0:MAX_ID-1];
    int unsigned wr_completed_id [0:MAX_ID-1];

    int unsigned rd_lat_list[$];
    int unsigned wr_lat_list[$];

    task init_tb();
        int i;
        axi_aw_if.init();
        axi_w_if.init();
        axi_b_if.init();
        axi_ar_if.init();
        axi_r_if.init();

        // wait for reset and DRAM init
        @(posedge rst_n);
        repeat (250) @(posedge clk);
        axi_r_if.rready = 1'b1;
        axi_b_if.bready = 1'b1;

        rd_issued_total = 0;
        wr_issued_total = 0;
        rd_completed = 0;
        wr_completed = 0;
        rd_lat_sum = 0;
        wr_lat_sum = 0;
        rd_lat_max = 0;
        wr_lat_max = 0;
        rd_lat_list.delete();
        wr_lat_list.delete();
        for (i = 0; i < MAX_ID; i++) begin
            rd_issue_q[i].delete();
            wr_issue_q[i].delete();
            rd_lat_max_id[i] = 0;
            rd_issued_id[i] = 0;
            rd_completed_id[i] = 0;
            wr_issued_id[i] = 0;
            wr_completed_id[i] = 0;
        end
    endtask

    function axi_addr_t pack_addr(
        input dram_ra_t ra,
        input dram_ba_t ba,
        input dram_ca_t ca
    );
        axi_addr_t addr;
        addr = '0;
        addr[`DDR_CA_WIDTH+2:3] = ca;
        addr[(`DDR_CA_WIDTH+3)+:`DDR_BA_WIDTH] = ba;
        addr[(`DDR_BA_WIDTH+`DDR_CA_WIDTH+3)+:`DDR_RA_WIDTH] = ra;
        return addr;
    endfunction

    function dram_ba_t rand_ba();
        return dram_ba_t'($urandom_range((1<<`DRAM_BA_WIDTH)-1));
    endfunction
    function dram_ra_t rand_ra();
        return dram_ra_t'($urandom_range((1<<`DRAM_RA_WIDTH)-1));
    endfunction
    function dram_ca_t rand_ca();
        return dram_ca_t'($urandom_range((1<<`DRAM_CA_WIDTH)-1));
    endfunction

    function logic [255:0] rand_data();
        logic [255:0] data;
        data = { $urandom, $urandom, $urandom, $urandom,
                 $urandom, $urandom, $urandom, $urandom };
        return data;
    endfunction

    task issue_read(input axi_id_t id, input axi_addr_t addr);
        axi_ar_if.send(id, addr, 'd1, `AXI_SIZE_128, `AXI_BURST_INCR);
        rd_issue_q[id].push_back(cycle);
        rd_issued_id[id] = rd_issued_id[id] + 1;
        rd_issued_total = rd_issued_total + 1;
    endtask

    task issue_write(input axi_id_t id, input axi_addr_t addr, input logic [255:0] data);
        axi_aw_if.send(id, addr, 'd1, `AXI_SIZE_128, `AXI_BURST_INCR);
        wr_issue_q[id].push_back(cycle);
        axi_w_if.send(id, data[0:127], 16'hFFFF, 1'b0);
        axi_w_if.send(id, data[128:255], 16'hFFFF, 1'b1);
        wr_issued_id[id] = wr_issued_id[id] + 1;
        wr_issued_total = wr_issued_total + 1;
    endtask

    task wait_for_reads(input int target);
        while (rd_completed < target) begin
            @(posedge clk);
        end
    endtask

    task wait_for_writes(input int target);
        while (wr_completed < target) begin
            @(posedge clk);
        end
    endtask

    task throttle_reads(input int max_outstanding);
        while ((int'(rd_issued_total) - int'(rd_completed)) >= max_outstanding) begin
            @(posedge clk);
        end
    endtask

    task throttle_writes(input int max_outstanding);
        while ((int'(wr_issued_total) - int'(wr_completed)) >= max_outstanding) begin
            @(posedge clk);
        end
    endtask

    task report_stats(input string name);
        int count;
        int idx;
        int unsigned p99;
        count = rd_lat_list.size();
        p99 = 0;
        if (count > 0) begin
            rd_lat_list.sort();
            idx = (count * 99) / 100;
            if (idx >= count) idx = count - 1;
            p99 = rd_lat_list[idx];
        end
        $display("SCN=%s rd_count=%0d rd_avg=%0d rd_p99=%0d rd_max=%0d", name, count,
                 (count>0) ? (rd_lat_sum / count) : 0, p99, rd_lat_max);
        report_fairness();
    endtask

    task report_write_stats(input string name);
        int count;
        int idx;
        int unsigned p99;
        count = wr_lat_list.size();
        p99 = 0;
        if (count > 0) begin
            wr_lat_list.sort();
            idx = (count * 99) / 100;
            if (idx >= count) idx = count - 1;
            p99 = wr_lat_list[idx];
        end
        $display("SCN=%s wr_count=%0d wr_avg=%0d wr_p99=%0d wr_max=%0d", name, count,
                 (count>0) ? (wr_lat_sum / count) : 0, p99, wr_lat_max);
    endtask

    task report_fairness();
        real sum;
        real sumsq;
        int active;
        sum = 0.0;
        sumsq = 0.0;
        active = 0;
        for (int i=0; i<MAX_ID; i++) begin
            if (rd_issued_id[i] > 0) begin
                sum += real'(rd_completed_id[i]);
                sumsq += real'(rd_completed_id[i]) * real'(rd_completed_id[i]);
                active++;
            end
        end
        if (active > 0 && sum > 0.0) begin
            real jain;
            jain = (sum * sum) / (active * sumsq);
            $display("fairness_jain=%0.3f active_ids=%0d", jain, active);
        end
    endtask

    task report_id_stats();
        for (int i=0; i<MAX_ID; i++) begin
            if (rd_issued_id[i] > 0) begin
                $display("id=%0d rd_issued=%0d rd_done=%0d rd_max=%0d", i,
                         rd_issued_id[i], rd_completed_id[i], rd_lat_max_id[i]);
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_completed = 0;
            wr_completed = 0;
            rd_lat_sum = 0;
            wr_lat_sum = 0;
            rd_lat_max = 0;
            wr_lat_max = 0;
        end else begin
            if (axi_r_if.rvalid && axi_r_if.rready) begin
                if (axi_r_if.rlast) begin
                    int unsigned lat;
                    int unsigned issue_cycle;
                    if (rd_issue_q[axi_r_if.rid].size() > 0) begin
                        issue_cycle = rd_issue_q[axi_r_if.rid].pop_front();
                    end else begin
                        issue_cycle = cycle;
                    end
                    lat = cycle - issue_cycle;
                    rd_lat_sum = rd_lat_sum + lat;
                    if (lat > rd_lat_max) rd_lat_max = lat;
                    if (lat > rd_lat_max_id[axi_r_if.rid]) rd_lat_max_id[axi_r_if.rid] = lat;
                    rd_lat_list.push_back(lat);
                    rd_completed_id[axi_r_if.rid] = rd_completed_id[axi_r_if.rid] + 1;
                    rd_completed = rd_completed + 1;
                end
            end
            if (axi_b_if.bvalid && axi_b_if.bready) begin
                int unsigned lat;
                int unsigned issue_cycle;
                if (wr_issue_q[axi_b_if.bid].size() > 0) begin
                    issue_cycle = wr_issue_q[axi_b_if.bid].pop_front();
                end else begin
                    issue_cycle = cycle;
                end
                lat = cycle - issue_cycle;
                wr_lat_sum = wr_lat_sum + lat;
                if (lat > wr_lat_max) wr_lat_max = lat;
                wr_lat_list.push_back(lat);
                wr_completed_id[axi_b_if.bid] = wr_completed_id[axi_b_if.bid] + 1;
                wr_completed = wr_completed + 1;
            end
        end
    end

`endif
