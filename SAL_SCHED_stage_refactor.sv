`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

// -----------------------------------------------------------------------------
// SAL_SCHED (Stage1~4 refactor)
//   - Base: SAL_SCHED_CAS_CNT_0120.sv 구조(CAS 후보 + RAS 후보 분리)
//   - 추가 정책(옵션, localparam로 on/off):
//       * AGING (bank starvation-free)
//       * BLISS-style Blacklisting (ID fairness)
//       * Write draining mode (RD/WR 방향전환 감소)
// -----------------------------------------------------------------------------
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
    // knobs (간단한 ablation을 위해 on/off 가능)
    // -------------------------------------------------------------------------
    localparam bit EN_AGING      = 1'b1;   // starvation-free (bank age 기반)
    localparam bit EN_BLISS      = 1'b1;   // ID blacklisting
    localparam bit EN_WDRAIN     = 1'b1;   // write draining + hysteresis

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

    // CAS priority limiter (기존 CAS_CNT 파일의 의미 유지)
    localparam int              CAS_PRIO_LIMIT = 4;

    // AGING
    localparam int              AGE_W = 8;

    // BLISS blacklisting
    localparam int              ID_CNT = (1<<`AXI_ID_WIDTH); // AXI_ID_WIDTH=4 in this project -> 16
    localparam int              BL_TMR_W = 6;                // up to 63 cycles
    localparam int              BL_CONSEC_W = 4;             // up to 15

    // scoring weights (조절 포인트)
    localparam int              CAS_BONUS   = 8;   // CAS 선호(행히트 성능 유지)
    localparam int              BL_PENALTY  = 16;  // blacklisted ID 페널티

    // blacklisting rule
    localparam logic [BL_CONSEC_W-1:0] BL_THRESH = 4'd8;     // 연속 8번 CAS grant 시 blacklisting
    localparam logic [BL_TMR_W-1:0]    BL_TIME   = 6'd32;    // 32 cycles 동안 blacklisted

    // write draining (hysteresis)
    localparam int              HI_WM = 2; // write pending >= HI_WM -> write_mode enter
    localparam int              LO_WM = 1; // write pending <= LO_WM -> write_mode exit

    // -------------------------------------------------------------------------
    // Scheduler-selected output (Stage3 결과)
    // -------------------------------------------------------------------------
    cmd_e                       sel_cmd;
    logic   [RR_W:0]            sel_bank;
    bk_req_t                    sel_req;

    // round-robin pointer (tie-break)
    logic   [RR_W-1:0]          rr_ptr, rr_ptr_n;

    // CAS limit counter (기존 변수명 유지)
    logic   [3:0]               consec_cas_cnt, consec_cas_cnt_n;

    // -------------------------------------------------------------------------
    // Inter-bank / bus timing counters
    // -------------------------------------------------------------------------
    localparam int              CCD_W = ((`T_CCD_WIDTH>`BURST_CYCLE_WIDTH)?`T_CCD_WIDTH:`BURST_CYCLE_WIDTH) + 1;
    logic   [`T_RRD_WIDTH-1:0]  rrd_cnt,        rrd_cnt_n;
    logic   [CCD_W-1:0]         ccd_cnt,        ccd_cnt_n;
    logic   [`T_WTR_WIDTH-1:0]  wtr_cnt,        wtr_cnt_n;
    logic   [`T_RTW_WIDTH-1:0]  rtw_cnt,        rtw_cnt_n;
    logic   [CCD_W-1:0]         ccd_load;

    logic                       grant_act, grant_rd, grant_wr;
    logic                       grant_pre, grant_ref;

    // global allow flags (Stage1)
    logic                       act_ok, rd_ok, wr_ok;

    // -------------------------------------------------------------------------
    // Policy state registers
    // -------------------------------------------------------------------------
    // (1) Aging
    logic   [AGE_W-1:0]         age       [bk_cnt];
    logic   [AGE_W-1:0]         age_n     [bk_cnt];

    // (2) BLISS blacklisting
    logic   [ID_CNT-1:0]        blacklist, blacklist_n;
    logic   [BL_TMR_W-1:0]      bl_timer   [ID_CNT];
    logic   [BL_TMR_W-1:0]      bl_timer_n [ID_CNT];
    axi_id_t                    last_grant_id, last_grant_id_n;
    logic   [BL_CONSEC_W-1:0]   consec_id_cnt, consec_id_cnt_n;

    // (3) Write draining
    logic                       write_mode, write_mode_n;

    // derived for updates
    logic                       grant_any;
    logic                       grant_is_cas;

    // -------------------------------------------------------------------------
    // helpers
    // -------------------------------------------------------------------------
    function automatic logic [AGE_W-1:0] sat_inc_age(input logic [AGE_W-1:0] v);
        if (&v) sat_inc_age = v;
        else    sat_inc_age = v + 1'b1;
    endfunction

    // -------------------------------------------------------------------------
    // Stage1) Timing filter + pending summary
    //   - act_ok/rd_ok/wr_ok
    //   - wr_pending_cnt for write_mode hysteresis
    //   - ras_exist for CAS budget decrement
    // -------------------------------------------------------------------------
    int unsigned wr_pending_cnt;
    logic        ras_exist;

    always_comb begin
        // global timing eligibility
        act_ok = (rrd_cnt == 0);
        rd_ok  = (ccd_cnt == 0) & (wtr_cnt == 0);
        wr_ok  = (ccd_cnt == 0) & (rtw_cnt == 0);

        // quick summary counts
        wr_pending_cnt = 0;
        ras_exist      = 1'b0;
        for (int i=0; i<bk_cnt; i++) begin
            if (bk_if.reqs[i].wr_req)
                wr_pending_cnt++;
            if (bk_if.reqs[i].act_req | bk_if.reqs[i].pre_req | bk_if.reqs[i].ref_req)
                ras_exist = 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Stage0) registers for inter-bank timing + rr_ptr + CAS budget
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rrd_cnt         <= 'd0;
            ccd_cnt         <= 'd0;
            wtr_cnt         <= 'd0;
            rtw_cnt         <= 'd0;
            rr_ptr          <= 'd0;
            consec_cas_cnt  <= 'd0;
        end
        else begin
            rrd_cnt         <= rrd_cnt_n;
            ccd_cnt         <= ccd_cnt_n;
            wtr_cnt         <= wtr_cnt_n;
            rtw_cnt         <= rtw_cnt_n;
            rr_ptr          <= rr_ptr_n;
            consec_cas_cnt  <= consec_cas_cnt_n;
        end
    end

    assign ccd_load = timing_if.t_ccd_m1 + timing_if.burst_cycle_m2;

    // timing counters next-state
    always_comb begin
        rrd_cnt_n          = (rrd_cnt!='d0) ? rrd_cnt - 1'b1 : 'd0;
        ccd_cnt_n          = (ccd_cnt!='d0) ? ccd_cnt - 1'b1 : 'd0;
        wtr_cnt_n          = (wtr_cnt!='d0) ? wtr_cnt - 1'b1 : 'd0;
        rtw_cnt_n          = (rtw_cnt!='d0) ? rtw_cnt - 1'b1 : 'd0;
        consec_cas_cnt_n   = consec_cas_cnt;

        if (grant_act)
            rrd_cnt_n      = timing_if.t_rrd_m1;
        if (grant_rd | grant_wr)
            ccd_cnt_n      = ccd_load;
        if (grant_wr)
            wtr_cnt_n      = timing_if.t_wtr_m1;
        if (grant_rd)
            rtw_cnt_n      = timing_if.t_rtw_m1;

        // CAS budget update (기존 CAS_CNT 의미: RAS가 있으면 CAS 연속 횟수 제한)
        if ((grant_rd | grant_wr) & ras_exist) begin
            consec_cas_cnt_n = (consec_cas_cnt!='d0) ? (consec_cas_cnt - 1'b1) : 'd0;
        end
        else if (grant_act | grant_pre | grant_ref) begin
            consec_cas_cnt_n = CAS_PRIO_LIMIT;
        end
    end

    // -------------------------------------------------------------------------
    // Stage4 update signals (from final selection)
    // -------------------------------------------------------------------------
    assign grant_any    = (sel_cmd != CMD_NONE);
    assign grant_is_cas = (grant_rd | grant_wr);

    // -------------------------------------------------------------------------
    // Policy FF: Write draining mode
    // -------------------------------------------------------------------------
    always_comb begin
        write_mode_n = write_mode;
        if (!EN_WDRAIN) begin
            write_mode_n = 1'b0;
        end
        else begin
            if (!write_mode && (wr_pending_cnt >= HI_WM))
                write_mode_n = 1'b1;
            else if (write_mode && (wr_pending_cnt <= LO_WM))
                write_mode_n = 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_mode <= 1'b0;
        end
        else begin
            write_mode <= write_mode_n;
        end
    end

    // -------------------------------------------------------------------------
    // Policy FF: Aging (bank-level)
    // -------------------------------------------------------------------------
    always_comb begin
        for (int i=0; i<bk_cnt; i++) begin
            age_n[i] = age[i];
            if (!EN_AGING) begin
                age_n[i] = 'd0;
            end
            else begin
                logic pend;
                pend = bk_if.reqs[i].act_req | bk_if.reqs[i].pre_req | bk_if.reqs[i].ref_req |
                       bk_if.reqs[i].rd_req  | bk_if.reqs[i].wr_req;

                if (grant_any && (sel_bank == i[RR_W:0]))
                    age_n[i] = 'd0;
                else if (pend)
                    age_n[i] = sat_inc_age(age[i]);
                else
                    age_n[i] = 'd0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i=0; i<bk_cnt; i++) begin
                age[i] <= 'd0;
            end
        end
        else begin
            for (int i=0; i<bk_cnt; i++) begin
                age[i] <= age_n[i];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Policy FF: BLISS blacklisting (ID-level)
    // -------------------------------------------------------------------------
    always_comb begin
        // default keep
        blacklist_n      = blacklist;
        last_grant_id_n  = last_grant_id;
        consec_id_cnt_n  = consec_id_cnt;
        for (int id=0; id<ID_CNT; id++) begin
            bl_timer_n[id] = bl_timer[id];
        end

        // timer decay
        for (int id=0; id<ID_CNT; id++) begin
            if (bl_timer_n[id] != 'd0) begin
                bl_timer_n[id] = bl_timer_n[id] - 1'b1;
                if (bl_timer_n[id] == 'd0)
                    blacklist_n[id] = 1'b0;
            end
        end

        // update on CAS grant only
        if (EN_BLISS && grant_is_cas) begin
            axi_id_t gid;
            logic [BL_CONSEC_W-1:0] new_consec;
            gid = sel_req.id;

            if (gid == last_grant_id)
                new_consec = consec_id_cnt + 1'b1;
            else
                new_consec = 'd1;

            last_grant_id_n = gid;

            if (new_consec >= BL_THRESH) begin
                blacklist_n[gid] = 1'b1;
                bl_timer_n[gid]  = BL_TIME;
                consec_id_cnt_n  = 'd0;
            end
            else begin
                consec_id_cnt_n  = new_consec;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blacklist       <= 'd0;
            last_grant_id   <= 'd0;
            consec_id_cnt   <= 'd0;
            for (int id=0; id<ID_CNT; id++) begin
                bl_timer[id] <= 'd0;
            end
        end
        else begin
            blacklist       <= blacklist_n;
            last_grant_id   <= last_grant_id_n;
            consec_id_cnt   <= consec_id_cnt_n;
            for (int id=0; id<ID_CNT; id++) begin
                bl_timer[id] <= bl_timer_n[id];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage2) 후보 추출: best CAS / best RAS
    //   - 변수명은 기존 파일(SAL_SCHED_CAS_CNT_0120.sv) 그대로 유지
    // -------------------------------------------------------------------------
    cmd_e                      sel_cmd_cas;
    logic   [RR_W:0]           sel_bank_cas;
    bk_req_t                   sel_req_cas;
    seq_num_t                  best_seq_cas;
    logic   [RR_W:0]           best_tb_cas;
    int signed                 best_score_cas;

    cmd_e                      sel_cmd_ras;
    logic   [RR_W:0]           sel_bank_ras;
    bk_req_t                   sel_req_ras;
    seq_num_t                  best_seq_ras;
    logic   [RR_W:0]           best_tb_ras;
    int signed                 best_score_ras;

    // ------------------
    // Stage2-A) CAS 후보
    // ------------------
    always_comb begin
        sel_cmd_cas   = CMD_NONE;
        sel_bank_cas  = '0;
        sel_req_cas   = '0;
        best_seq_cas  = {`MC_SEQ_NUM_WIDTH{1'b1}};
        best_tb_cas   = {RR_W+1{1'b1}};
        best_score_cas= -32'sd1;

        for (int i = 0; i < bk_cnt; i++) begin
            cmd_e       cand_cmd;
            seq_num_t   cand_seq;
            logic [RR_W:0] cand_tb;
            int signed  cand_score;
            axi_id_t    cand_id;
            logic       cand_bl;

            cand_cmd  = CMD_NONE;
            cand_seq  = bk_if.reqs[i].seq_num;
            cand_tb   = (i >= rr_ptr) ? (i - rr_ptr) : (bk_cnt - (rr_ptr - i));
            cand_id   = bk_if.reqs[i].id;
            cand_bl   = (EN_BLISS) ? blacklist[cand_id] : 1'b0;

            // write_mode에 따라 RD/WR 우선순위를 바꿈
            if (!write_mode) begin
                if (rd_ok && bk_if.reqs[i].rd_req) begin
                    cand_cmd = CMD_RD;
                end else if (wr_ok && bk_if.reqs[i].wr_req) begin
                    cand_cmd = CMD_WR;
                end
            end
            else begin
                if (wr_ok && bk_if.reqs[i].wr_req) begin
                    cand_cmd = CMD_WR;
                end else if (rd_ok && bk_if.reqs[i].rd_req) begin
                    cand_cmd = CMD_RD;
                end
            end

            // score: age + CAS_BONUS - blacklist penalty
            cand_score = 0;
            if (EN_AGING) cand_score += int'(age[i]);

            if (cand_cmd == CMD_RD || cand_cmd == CMD_WR) begin
                cand_score += CAS_BONUS;
                if (cand_bl)
                    cand_score -= BL_PENALTY;
            end

            if (cand_cmd != CMD_NONE) begin
                if ((cand_score > best_score_cas) ||
                    ((cand_score == best_score_cas) && ((cand_seq < best_seq_cas) ||
                                                       ((cand_seq == best_seq_cas) && (cand_tb < best_tb_cas))))) begin
                    sel_cmd_cas    = cand_cmd;
                    sel_bank_cas   = i[RR_W:0];
                    sel_req_cas    = bk_if.reqs[i];
                    best_seq_cas   = cand_seq;
                    best_tb_cas    = cand_tb;
                    best_score_cas = cand_score;
                end
            end
        end
    end

    // ------------------
    // Stage2-B) RAS 후보
    // ------------------
    always_comb begin
        sel_cmd_ras    = CMD_NONE;
        sel_bank_ras   = '0;
        sel_req_ras    = '0;
        best_seq_ras   = {`MC_SEQ_NUM_WIDTH{1'b1}};
        best_tb_ras    = {RR_W+1{1'b1}};
        best_score_ras = -32'sd1;

        for (int i = 0; i < bk_cnt; i++) begin
            cmd_e       cand_cmd;
            seq_num_t   cand_seq;
            logic [RR_W:0] cand_tb;
            int signed  cand_score;

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

            cand_score = 0;
            if (EN_AGING) cand_score += int'(age[i]);

            if (cand_cmd != CMD_NONE) begin
                if ((cand_score > best_score_ras) ||
                    ((cand_score == best_score_ras) && ((cand_seq < best_seq_ras) ||
                                                       ((cand_seq == best_seq_ras) && (cand_tb < best_tb_ras))))) begin
                    sel_cmd_ras    = cand_cmd;
                    sel_bank_ras   = i[RR_W:0];
                    sel_req_ras    = bk_if.reqs[i];
                    best_seq_ras   = cand_seq;
                    best_tb_ras    = cand_tb;
                    best_score_ras = cand_score;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage3) CAS vs RAS 최종 선택
    //   - 기본은 CAS 우선(FR-FCFS)
    //   - 단, RAS가 있으면 consec_cas_cnt==0일 때 강제로 RAS
    //   - 추가로, best_score_ras > best_score_cas면 RAS를 먼저 뽑도록 허용(aging이 쌓이면 자연히 RAS가 선택)
    // -------------------------------------------------------------------------
    always_comb begin
        sel_cmd   = CMD_NONE;
        sel_bank  = '0;
        sel_req   = '0;

        if ((sel_cmd_cas != CMD_NONE) || (sel_cmd_ras != CMD_NONE)) begin
            if (sel_cmd_ras != CMD_NONE && sel_cmd_cas == CMD_NONE) begin
                // only RAS
                sel_cmd  = sel_cmd_ras;
                sel_bank = sel_bank_ras;
                sel_req  = sel_req_ras;
            end
            else if (sel_cmd_cas != CMD_NONE && sel_cmd_ras == CMD_NONE) begin
                // only CAS
                sel_cmd  = sel_cmd_cas;
                sel_bank = sel_bank_cas;
                sel_req  = sel_req_cas;
            end
            else begin
                // both exist
                if (consec_cas_cnt == 'd0) begin
                    sel_cmd  = sel_cmd_ras;
                    sel_bank = sel_bank_ras;
                    sel_req  = sel_req_ras;
                end
                else if (best_score_ras > best_score_cas) begin
                    sel_cmd  = sel_cmd_ras;
                    sel_bank = sel_bank_ras;
                    sel_req  = sel_req_ras;
                end
                else begin
                    sel_cmd  = sel_cmd_cas;
                    sel_bank = sel_bank_cas;
                    sel_req  = sel_req_cas;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage4) output (grants + sched_if) + rr_ptr update + grant flags
    // -------------------------------------------------------------------------
    always_comb begin
        rr_ptr_n           = rr_ptr;
        bk_if.gnts         = '{default:'0};

        sched_if.act_gnt   = 1'b0;
        sched_if.rd_gnt    = 1'b0;
        sched_if.wr_gnt    = 1'b0;
        sched_if.pre_gnt   = 1'b0;
        sched_if.ref_gnt   = 1'b0;
        sched_if.ba        = '0;
        sched_if.ra        = '0;
        sched_if.ca        = '0;
        sched_if.id        = '0;
        sched_if.len       = '0;

        grant_act          = 1'b0;
        grant_rd           = 1'b0;
        grant_wr           = 1'b0;
        grant_pre          = 1'b0;
        grant_ref          = 1'b0;

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

        if (sel_cmd != CMD_NONE) begin
            sched_if.ba  = sel_req.ba;
            sched_if.ra  = sel_req.ra;
            sched_if.ca  = sel_req.ca;
            rr_ptr_n     = (sel_bank + 1) % bk_cnt;
        end
    end

endmodule // SAL_SCHED
