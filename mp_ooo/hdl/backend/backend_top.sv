module backend_top
import cpu_params::*;
import uop_types::*;
(
    input   logic               clk,
    input   logic               rst,

    // Instruction Queue
    fifo_backend_itf.backend    from_fifo,

    // Flush signals
    output  logic               backend_flush,
    output  logic   [31:0]      backend_redirect_pc
);

    assign backend_flush = 1'b0;
    assign backend_redirect_pc = 'x;

    id_rat_itf                  id_rat_itf_i();
    id_fl_itf                   id_fl_itf_i();
    id_rob_itf                  id_rob_itf_i();
    ds_int_rs_itf               ds_int_rs_itf_i();
    ds_int_rs_itf               ds_intm_rs_itf_i();
    ds_int_rs_itf               ds_mem_rs_itf_i();
    rob_rrf_itf                 rob_rrf_itf_i();
    rrf_fl_itf                  rrf_fl_itf_i();
    cdb_itf                     cdb_itfs[CDB_WIDTH]();
    rs_prf_itf                  rs_prf_itfs[CDB_WIDTH]();

    logic                       dispatch_valid;
    logic                       dispatch_ready;
    uop_t                       uops[ID_WIDTH];

    id_stage id_stage_i(
        // .clk                    (clk),
        // .rst                    (rst),

        .nxt_valid              (dispatch_valid),
        .nxt_ready              (dispatch_ready),

        .uops                   (uops),

        .from_fifo              (from_fifo),
        .to_rat                 (id_rat_itf_i),
        .to_fl                  (id_fl_itf_i),
        .to_rob                 (id_rob_itf_i)
    );

    rat rat_i(
        .clk                    (clk),
        .rst                    (rst),

        .from_id                (id_rat_itf_i),
        .cdb                    (cdb_itfs)
    );

    free_list free_list_i(
        .clk                    (clk),
        .rst                    (rst),

        .from_id                (id_fl_itf_i),
        .from_rrf               (rrf_fl_itf_i)
    );

    rob rob_i(
        .clk                    (clk),
        .rst                    (rst),

        .from_id                (id_rob_itf_i),
        .to_rrf                 (rob_rrf_itf_i),
        .cdb                    (cdb_itfs)
    );

    rrf rrf_i(
        .clk                    (clk),
        .rst                    (rst),

        .from_rob               (rob_rrf_itf_i),
        .to_fl                  (rrf_fl_itf_i)
    );

    ds_stage ds_stage_i(
        // .clk                    (clk),
        // .rst                    (rst),

        .prv_valid              (dispatch_valid),
        .prv_ready              (dispatch_ready),

        .uops                   (uops),

        .to_int_rs              (ds_int_rs_itf_i),
        .to_intm_rs             (ds_intm_rs_itf_i)
    );

    int_rs int_rs_i(
        .clk                    (clk),
        .rst                    (rst),

        .from_ds                (ds_int_rs_itf_i),
        .to_prf                 (rs_prf_itfs[0]),
        .cdb                    (cdb_itfs),
        .fu_cdb_out             (cdb_itfs[0])
    );

    intm_rs intm_rs_i(
        .clk                    (clk),
        .rst                    (rst),

        .from_ds                (ds_intm_rs_itf_i),
        .to_prf                 (rs_prf_itfs[1]),
        .cdb                    (cdb_itfs),
        .fu_cdb_out             (cdb_itfs[1])
    );

    prf prf_i(
        .clk                    (clk),
        .rst                    (rst),
        .from_rs                (rs_prf_itfs),
        .cdb                    (cdb_itfs)
    );

endmodule
