`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_SCHED
#(
    parameter   bk_cnt = 4
)
(
    // clock & reset
    input                       clk,
    input                       rst_n,

    TIMING_IF.MON               timing_if,

    // requests from bank controllers
    BK_CTRL_IF.SCHED            bk_if,
    
    SCHED_IF.SCHED              sched_if
);

    // -------------------------------------------------------------------------
    // Command selection helpers
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        CMD_NONE,
        CMD_PRE,
        CMD_RD,
        CMD_WR,
        CMD_ACT,
        CMD_REF
    } cmd_e;

    localparam int              RR_W = (bk_cnt>1) ? $clog2(bk_cnt) : 1;
    localparam int              CAS_PRIO_LIMIT = 4; 
    cmd_e                       sel_cmd;
    logic   [RR_W:0]            sel_bank;
    bk_req_t                    sel_req;
    logic   [RR_W-1:0]          rr_ptr, rr_ptr_n;

    logic   [3:0]               consec_cas_cnt, consec_cas_cnt_n;

    // -------------------------------------------------------------------------
    // Inter-bank / bus timing counters
    // -------------------------------------------------------------------------
    localparam int              CCD_W = ((`T_CCD_WIDTH>`BURST_CYCLE_WIDTH)?`T_CCD_WIDTH:`BURST_CYCLE_WIDTH) + 1;
    logic   [`T_RRD_WIDTH-1:0]  rrd_cnt,        rrd_cnt_n;
    logic   [CCD_W-1:0]         ccd_cnt,        ccd_cnt_n;
    logic   [`T_WTR_WIDTH-1:0]  wtr_cnt,        wtr_cnt_n;
    logic   [`T_RTW_WIDTH-1:0]  rtw_cnt,        rtw_cnt_n;

    logic                       grant_act, grant_rd, grant_wr;
    logic                       grant_pre, grant_ref;
    logic                       act_ok, rd_ok, wr_ok;
    logic                       ras_exist;

    // -------------------------------------------------------------------------
    // Timing counters
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rrd_cnt             <= 'd0;
            ccd_cnt             <= 'd0;
            wtr_cnt             <= 'd0;
            rtw_cnt             <= 'd0;
            rr_ptr              <= 'd0;

            consec_cas_cnt      <= 'd0;
        end
        else begin
            rrd_cnt             <= rrd_cnt_n;
            ccd_cnt             <= ccd_cnt_n;
            wtr_cnt             <= wtr_cnt_n;
            rtw_cnt             <= rtw_cnt_n;
            rr_ptr              <= rr_ptr_n;

            consec_cas_cnt      <= consec_cas_cnt_n;
        end
    end

    always_comb begin
        rrd_cnt_n               = (rrd_cnt!='d0) ? rrd_cnt - 1'b1 : 'd0;
        ccd_cnt_n               = (ccd_cnt!='d0) ? ccd_cnt - 1'b1 : 'd0;
        wtr_cnt_n               = (wtr_cnt!='d0) ? wtr_cnt - 1'b1 : 'd0;
        rtw_cnt_n               = (rtw_cnt!='d0) ? rtw_cnt - 1'b1 : 'd0;
        consec_cas_cnt_n        = consec_cas_cnt;

        if (grant_act)
            rrd_cnt_n           = timing_if.t_rrd_m1;
        if (grant_rd | grant_wr)
            ccd_cnt_n           = timing_if.t_ccd_m1;//  + timing_if.burst_cycle_m2;
        if (grant_wr)
            wtr_cnt_n           = timing_if.t_wtr_m1;
        if (grant_rd)
            rtw_cnt_n           = timing_if.t_rtw_m1;

        if ((grant_rd | grant_wr) & ras_exist) begin
            consec_cas_cnt_n = consec_cas_cnt != 'd0 ? consec_cas_cnt - 1'b1 : 'd0;
        end
        else if (grant_act | grant_pre | grant_ref) begin
            consec_cas_cnt_n        = CAS_PRIO_LIMIT;
        end
    end

    // RAS exist check
    always_comb begin
        ras_exist               = 1'b0;
        for (int i = 0; i < bk_cnt; i++) begin
            if (bk_if.reqs[i].act_req | bk_if.reqs[i].pre_req | bk_if.reqs[i].ref_req) begin
                ras_exist           = 1'b1;
            end
        end
    end

    assign act_ok                  = (rrd_cnt == 0);
    assign rd_ok                   = (ccd_cnt == 0) & (wtr_cnt == 0);
    assign wr_ok                   = (ccd_cnt == 0) & (rtw_cnt == 0);



    // -------------------------------------------------------------------------
    // Scheduler
    // -------------------------------------------------------------------------

    cmd_e                      sel_cmd_cas;
    logic   [RR_W:0]           sel_bank_cas;
    bk_req_t                   sel_req_cas;
    seq_num_t                  best_seq_cas;
    logic   [RR_W:0]           best_tb_cas;

    always_comb begin
        sel_cmd_cas             = CMD_NONE;
        sel_bank_cas            = '0;
        sel_req_cas             = '0;
        best_seq_cas            = {`MC_SEQ_NUM_WIDTH{1'b1}};
        best_tb_cas             = {RR_W+1{1'b1}};
    
        // 1) FR-FCFS 스타일: ready한 CAS(RD/WR) 우선, oldest(seq_num) 선택, 동률 시 rr_ptr 기준 근접 우선
        for (int i = 0; i < bk_cnt; i++) begin
            cmd_e cand_cmd;
            seq_num_t cand_seq;
            logic [RR_W:0] cand_tb;
            cand_cmd = CMD_NONE;
            cand_seq = bk_if.reqs[i].seq_num;
            cand_tb  = (i >= rr_ptr) ? (i - rr_ptr) : (bk_cnt - (rr_ptr - i));

            if (rd_ok && bk_if.reqs[i].rd_req) begin
                cand_cmd = CMD_RD;
            end else if (wr_ok && bk_if.reqs[i].wr_req) begin
                cand_cmd = CMD_WR;
            end

            if (cand_cmd != CMD_NONE) begin
                if ((cand_seq < best_seq_cas) | ((cand_seq == best_seq_cas) & (cand_tb < best_tb_cas))) begin
                    sel_cmd_cas   = cand_cmd;
                    sel_bank_cas  = i;
                    sel_req_cas   = bk_if.reqs[i];
                    best_seq_cas  = cand_seq;
                    best_tb_cas   = cand_tb;
                end
            end
        end
    end


    cmd_e                      sel_cmd_ras;
    logic   [RR_W:0]           sel_bank_ras;
    bk_req_t                   sel_req_ras;
    seq_num_t                  best_seq_ras;
    logic   [RR_W:0]           best_tb_ras;
    always_comb begin
        sel_cmd_ras             = CMD_NONE;
        sel_bank_ras            = '0;
        sel_req_ras             = '0;
        best_seq_ras            = {`MC_SEQ_NUM_WIDTH{1'b1}};
        best_tb_ras             = {RR_W+1{1'b1}};
        // 2) CAS 후보가 없으면 RAS 계열(ACT/PRE/REF) 중 oldest 선택
        for (int i = 0; i < bk_cnt; i++) begin
            cmd_e cand_cmd;
            seq_num_t cand_seq;
            logic [RR_W:0] cand_tb;
            cand_cmd = CMD_NONE;
            cand_seq = bk_if.reqs[i].seq_num;
            cand_tb  = (i >= rr_ptr) ? (i - rr_ptr) : (bk_cnt - (rr_ptr - i));

            if (bk_if.reqs[i].pre_req) begin
                cand_cmd = CMD_PRE;
            end else if (act_ok && bk_if.reqs[i].act_req) begin
                cand_cmd = CMD_ACT;
            end else if (bk_if.reqs[i].ref_req) begin
                cand_cmd = CMD_REF;
            end

            if (cand_cmd != CMD_NONE) begin
                if ((cand_seq < best_seq_ras) | ((cand_seq == best_seq_ras) & (cand_tb < best_tb_ras))) begin
                    sel_cmd_ras   = cand_cmd;
                    sel_bank_ras  = i;
                    sel_req_ras   = bk_if.reqs[i];
                    best_seq_ras  = cand_seq;
                    best_tb_ras   = cand_tb;
                end
            end
        end
    end

    // Final selection between CAS and RAS candidates
    always_comb begin
        sel_cmd                 = CMD_NONE;
        sel_bank                = 0;
        sel_req                 = '0;
        if ((sel_cmd_ras != CMD_NONE &
            (sel_cmd_cas == CMD_NONE | sel_cmd_cas != CMD_NONE & (consec_cas_cnt == 'd0)))) begin
            sel_cmd             = sel_cmd_ras;
            sel_bank            = sel_bank_ras;
            sel_req             = sel_req_ras;
        end else begin
            sel_cmd             = sel_cmd_cas;
            sel_bank            = sel_bank_cas;
            sel_req             = sel_req_cas;
        end
    end


    // output selection
    always_comb begin
        rr_ptr_n                = rr_ptr;
        bk_if.gnts              = '{default:'0};

        sched_if.act_gnt        = 1'b0;
        sched_if.rd_gnt         = 1'b0;
        sched_if.wr_gnt         = 1'b0;
        sched_if.pre_gnt        = 1'b0;
        sched_if.ref_gnt        = 1'b0;
        sched_if.ba             = '0;
        sched_if.ra             = '0;
        sched_if.ca             = '0;
        sched_if.id             = '0;
        sched_if.len            = '0;

        grant_act               = 1'b0;
        grant_rd                = 1'b0;
        grant_wr                = 1'b0;
        grant_pre               = 1'b0;
        grant_ref               = 1'b0;
        
        // Drive grants and output command when something is selected
        case (sel_cmd)
            CMD_PRE: begin
                bk_if.gnts[sel_bank].pre_gnt = 1'b1;
                sched_if.pre_gnt             = 1'b1;
                grant_pre                    = 1'b1;
            end
            CMD_RD: begin
                bk_if.gnts[sel_bank].rd_gnt  = 1'b1;
                sched_if.rd_gnt              = 1'b1;
                sched_if.id                  = sel_req.id;
                sched_if.len                 = sel_req.len;
                grant_rd                     = 1'b1;
            end
            CMD_WR: begin
                bk_if.gnts[sel_bank].wr_gnt  = 1'b1;
                sched_if.wr_gnt              = 1'b1;
                sched_if.id                  = sel_req.id;
                sched_if.len                 = sel_req.len;
                grant_wr                     = 1'b1;
            end
            CMD_ACT: begin
                bk_if.gnts[sel_bank].act_gnt = 1'b1;
                sched_if.act_gnt             = 1'b1;
                grant_act                    = 1'b1;
            end
            CMD_REF: begin
                bk_if.gnts[sel_bank].ref_gnt = 1'b1;
                sched_if.ref_gnt             = 1'b1;
                grant_ref                    = 1'b1;
            end
            default: ;
        endcase

        // common address fields for all command types
        if (sel_cmd != CMD_NONE) begin
            sched_if.ba         = sel_req.ba;
            sched_if.ra         = sel_req.ra;
            sched_if.ca         = sel_req.ca;
            rr_ptr_n            = (sel_bank + 1) % bk_cnt;
        end
    end




endmodule // SAL_SCHED
