`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"

module SAL_BK_CTRL
#(
    parameter                   BK_ID   = 0
)
(
    // clock & reset
    input                       clk,
    input                       rst_n,

    // timing parameters
    TIMING_IF.MON               timing_if,

    // request from the address decoder
    REQ_IF.DST                  req_if,

    // request to the scheduler
    output  bk_req_t            bk_reqs,
    input   bk_gnt_t            bk_gnts,
    
    // per-bank auto-refresh requests
    input   wire                ref_req_i,
    output  logic               ref_gnt_o
);



    // -------------------------------------------------------------------------
    // 1. State definition
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_ACTIVATING,
        S_BANK_ACTIVE,
        S_READING,
        S_WRITING,
        S_PRECHARGING,
        S_REFRESHING
    } state_e;

    state_e                     state,          state_n;

    // -------------------------------------------------------------------------
    // 2. Request buffer (one outstanding request per bank)
    // -------------------------------------------------------------------------
    logic                       req_buf_valid,  req_buf_valid_n;
    logic                       req_buf_wr;
    axi_id_t                    req_buf_id;
    axi_len_t                   req_buf_len;
    seq_num_t                   req_buf_seq;
    dram_ra_t                   req_buf_ra;
    dram_ca_t                   req_buf_ca;
    logic                       ref_pending,    ref_pending_n;

    wire                        req_accept;
    assign  req_accept          = req_if.valid & req_if.ready;

    dram_ra_t                   cur_ra,         cur_ra_n;
    logic [`ROW_OPEN_WIDTH-1:0] row_open_cnt,   row_open_cnt_n;

    // constant BA for this instance
    wire    dram_ba_t           bk_ba;
    assign  bk_ba               = BK_ID[`DRAM_BA_WIDTH-1:0];

    // -------------------------------------------------------------------------
    // 3. Timing counters (per-bank constraints)
    // -------------------------------------------------------------------------
    logic       load_main,      load_tras,      load_trtp, load_twr, load_trc;
    logic [`T_RFC_WIDTH-1:0]   val_main; // reused for generic delays
    logic [`T_RAS_WIDTH-1:0]    val_tras;
    logic [`T_RTP_WIDTH-1:0]    val_trtp;
    logic [`T_WTP_WIDTH-1:0]    val_twr;
    logic [`T_RC_WIDTH-1:0]     val_trc;

    logic                       main_is_zero, tras_is_zero, trtp_is_zero, twr_is_zero, trc_is_zero;

    SAL_TIMING_CNTR #(.CNTR_WIDTH(`T_RFC_WIDTH)) u_cnt_main (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .reset_cmd_i            (load_main),
        .reset_value_i          (val_main),
        .is_zero_o              (main_is_zero)
    );

    SAL_TIMING_CNTR #(.CNTR_WIDTH(`T_RAS_WIDTH)) u_cnt_tras (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .reset_cmd_i            (load_tras),
        .reset_value_i          (val_tras),
        .is_zero_o              (tras_is_zero)
    );

    SAL_TIMING_CNTR #(.CNTR_WIDTH(`T_RTP_WIDTH)) u_cnt_trtp (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .reset_cmd_i            (load_trtp),
        .reset_value_i          (val_trtp),
        .is_zero_o              (trtp_is_zero)
    );

    SAL_TIMING_CNTR #(.CNTR_WIDTH(`T_WTP_WIDTH)) u_cnt_twr (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .reset_cmd_i            (load_twr),
        .reset_value_i          (val_twr),
        .is_zero_o              (twr_is_zero)
    );

    SAL_TIMING_CNTR #(.CNTR_WIDTH(`T_RC_WIDTH)) u_cnt_trc (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .reset_cmd_i            (load_trc),
        .reset_value_i          (val_trc),
        .is_zero_o              (trc_is_zero)
    );

    // -------------------------------------------------------------------------
    // 4. Sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= S_IDLE;
            cur_ra              <= '0;
            row_open_cnt        <= '0;
            ref_pending         <= 1'b0;

            req_buf_valid       <= 1'b0;
            req_buf_wr          <= 1'b0;
            req_buf_id          <= '0;
            req_buf_len         <= '0;
            req_buf_seq         <= '0;
            req_buf_ra          <= '0;
            req_buf_ca          <= '0;
        end
        else begin
            state               <= state_n;
            cur_ra              <= cur_ra_n;
            row_open_cnt        <= row_open_cnt_n;
            ref_pending         <= ref_pending_n;

            req_buf_valid       <= req_buf_valid_n;
            if (req_accept) begin
                req_buf_wr          <= req_if.wr;
                req_buf_id          <= req_if.id;
                req_buf_len         <= req_if.len;
                req_buf_seq         <= req_if.seq_num;
                req_buf_ra          <= req_if.ra;
                req_buf_ca          <= req_if.ca;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 5. Combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        // default assignments
        state_n             = state;
        cur_ra_n            = cur_ra;
        row_open_cnt_n      = (row_open_cnt > 0) ? row_open_cnt - 1'b1 : 'd0;
        req_buf_valid_n     = req_buf_valid;

        ref_gnt_o           = 1'b0;

        // latch refresh request until served
        ref_pending_n       = ref_pending;
        if (ref_req_i) begin
            ref_pending_n   = 1'b1;
        end
        if (bk_gnts.ref_gnt) begin
            ref_pending_n   = 1'b0;
        end

        // ready when buffer is empty and refresh is not pending
        req_if.ready        = ~req_buf_valid & ~ref_pending_n;

        bk_reqs             = '0;
        // keep address/meta information stable while requesting
        bk_reqs.ba          = bk_ba;
        bk_reqs.ra          = req_buf_valid ? req_buf_ra : cur_ra;
        bk_reqs.ca          = req_buf_ca;
        bk_reqs.seq_num     = req_buf_seq;
        bk_reqs.id          = req_buf_id;
        bk_reqs.len         = req_buf_len;

        load_main           = 1'b0;    val_main  = '0;
        load_tras           = 1'b0;    val_tras  = '0;
        load_trtp           = 1'b0;    val_trtp  = '0;
        load_twr            = 1'b0;    val_twr   = '0;
        load_trc            = 1'b0;    val_trc   = '0;

        case (state)
            S_IDLE: begin
                if (ref_pending) begin
                    bk_reqs.ref_req = 1'b1;
                    bk_reqs.ra      = '0;
                    bk_reqs.ca      = '0;
                    if (bk_gnts.ref_gnt) begin
                        ref_gnt_o       = 1'b1;
                load_main       = 1'b1;
                val_main        = timing_if.t_rfc_m1;
                state_n         = S_REFRESHING;
            end
        end
        else if (req_buf_valid && trc_is_zero) begin
            bk_reqs.act_req   = 1'b1;
            bk_reqs.ra        = req_buf_ra;
            if (bk_gnts.act_gnt) begin
                load_main       = 1'b1;
                val_main        = timing_if.t_rcd_m1;
                        load_tras       = 1'b1;
                        val_tras        = timing_if.t_ras_m1;
                        load_trc        = 1'b1;
                        val_trc         = timing_if.t_rc_m1;
                        cur_ra_n        = req_buf_ra;
                        state_n         = S_ACTIVATING;
                    end
                end
            end

            S_ACTIVATING: begin
                if (main_is_zero) begin
                    state_n         = S_BANK_ACTIVE;
                    row_open_cnt_n  = timing_if.row_open_cnt;
                end
            end

            S_BANK_ACTIVE: begin
                logic row_hit;
                row_hit = req_buf_valid && (req_buf_ra == cur_ra);

                if (row_hit) begin
                    if (req_buf_wr) begin
                        bk_reqs.wr_req = 1'b1;
                        bk_reqs.ca     = req_buf_ca;
                        if (bk_gnts.wr_gnt) begin
                            load_main       = 1'b1;
                            val_main        = timing_if.t_ccd_m1;
                            load_twr        = 1'b1;
                            val_twr         = timing_if.t_wtp_m1;
                            state_n         = S_WRITING;
                            req_buf_valid_n = 1'b0;
                        end
                    end
                    else begin
                        bk_reqs.rd_req = 1'b1;
                        bk_reqs.ca     = req_buf_ca;
                        if (bk_gnts.rd_gnt) begin
                            load_main       = 1'b1;
                            val_main        = timing_if.t_ccd_m1;
                            load_trtp       = 1'b1;
                            val_trtp        = timing_if.t_rtp_m1;
                            state_n         = S_READING;
                            req_buf_valid_n = 1'b0;
                        end
                    end
                end
                else begin
                    logic should_close;
                    should_close = (req_buf_valid && !row_hit) || (row_open_cnt == 0) || ref_pending_n;

                    if (should_close && tras_is_zero && trtp_is_zero && twr_is_zero) begin
                        bk_reqs.pre_req = 1'b1;
                        bk_reqs.ra      = '0;
                        bk_reqs.ca      = '0;
                        if (bk_gnts.pre_gnt) begin
                            load_main       = 1'b1;
                            val_main        = timing_if.t_rp_m1;
                            state_n         = S_PRECHARGING;
                        end
                    end
                end
            end

            S_READING: begin
                if (main_is_zero) begin
                    state_n         = S_BANK_ACTIVE;
                    row_open_cnt_n  = timing_if.row_open_cnt;
                end
            end

            S_WRITING: begin
                if (main_is_zero) begin
                    state_n         = S_BANK_ACTIVE;
                    row_open_cnt_n  = timing_if.row_open_cnt;
                end
            end

            S_PRECHARGING: begin
                if (main_is_zero) begin
                    state_n         = S_IDLE;
                    row_open_cnt_n  = 'd0;
                end
            end

            S_REFRESHING: begin
                if (main_is_zero) begin
                    state_n         = S_IDLE;
                    row_open_cnt_n  = 'd0;
                end
            end

            default: state_n = S_IDLE;
        endcase

        // accept a new request into the buffer
        if (req_accept) begin
            req_buf_valid_n = 1'b1;
        end

        // refresh pending latch update
        // ref_pending_n updated above, committed in sequential block
    end




endmodule // SAL_BK_CTRL
