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
    cmd_e                       sel_cmd;
    logic   [RR_W:0]            sel_bank;
    bk_req_t                    sel_req;
    logic   [RR_W-1:0]          rr_ptr, rr_ptr_n;


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

        end
        else begin
            rrd_cnt             <= rrd_cnt_n;
            ccd_cnt             <= ccd_cnt_n;
            wtr_cnt             <= wtr_cnt_n;
            rtw_cnt             <= rtw_cnt_n;
            rr_ptr              <= rr_ptr_n;

        end
    end

    always_comb begin
        rrd_cnt_n               = (rrd_cnt!='d0) ? rrd_cnt - 1'b1 : 'd0;
        ccd_cnt_n               = (ccd_cnt!='d0) ? ccd_cnt - 1'b1 : 'd0;
        wtr_cnt_n               = (wtr_cnt!='d0) ? wtr_cnt - 1'b1 : 'd0;
        rtw_cnt_n               = (rtw_cnt!='d0) ? rtw_cnt - 1'b1 : 'd0;

        if (grant_act)
            rrd_cnt_n           = timing_if.t_rrd_m1;
        if (grant_rd | grant_wr)
            ccd_cnt_n           = timing_if.t_ccd_m1;//  + timing_if.burst_cycle_m2;
        if (grant_wr)
            wtr_cnt_n           = timing_if.t_wtr_m1;
        if (grant_rd)
            rtw_cnt_n           = timing_if.t_rtw_m1;

    end

    assign act_ok                  = (rrd_cnt == 0);
    assign rd_ok                   = (ccd_cnt == 0) & (wtr_cnt == 0);
    assign wr_ok                   = (ccd_cnt == 0) & (rtw_cnt == 0);
    // -------------------------------------------------------------------------
    // Scheduler (round-robin across banks)
    // -------------------------------------------------------------------------
    always_comb begin
        sel_cmd                 = CMD_NONE;
        sel_bank                = '0;
        sel_req                 = '0;

        for (int offset = 0; offset < bk_cnt; offset++) begin
            int idx;
            idx = rr_ptr + offset;
            if (idx >= bk_cnt) begin
                idx = idx - bk_cnt;
            end

            if (sel_cmd == CMD_NONE) begin
                if (rd_ok && bk_if.reqs[idx].rd_req) begin
                    sel_cmd     = CMD_RD;
                    sel_bank    = idx[RR_W:0];
                    sel_req     = bk_if.reqs[idx];
                end
                else if (wr_ok && bk_if.reqs[idx].wr_req) begin
                    sel_cmd     = CMD_WR;
                    sel_bank    = idx[RR_W:0];
                    sel_req     = bk_if.reqs[idx];
                end
                else if (bk_if.reqs[idx].pre_req) begin
                    sel_cmd     = CMD_PRE;
                    sel_bank    = idx[RR_W:0];
                    sel_req     = bk_if.reqs[idx];
                end
                else if (act_ok && bk_if.reqs[idx].act_req) begin
                    sel_cmd     = CMD_ACT;
                    sel_bank    = idx[RR_W:0];
                    sel_req     = bk_if.reqs[idx];
                end
                else if (bk_if.reqs[idx].ref_req) begin
                    sel_cmd     = CMD_REF;
                    sel_bank    = idx[RR_W:0];
                    sel_req     = bk_if.reqs[idx];
                end
            end
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
