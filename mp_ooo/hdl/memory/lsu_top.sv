module lsu_top
import cpu_params::*;
import uop_types::*;
import lsu_types::*;
(
    input   logic               clk,
    input   logic               rst,

    ds_rs_mono_itf.rs           from_ds,
    rs_prf_itf.rs               to_prf,
    cdb_itf.rs                  cdb[CDB_WIDTH],
    cdb_itf.fu                  fu_cdb_out,
    ldq_rob_itf.ldq             ld_to_rob,
    stq_rob_itf.stq             st_to_rob,
    cacheline_itf.master        dcache_itf,

    // Flush signals
    input   logic               backend_flush
);

    // Distribute signal from dispatch to RS and LSQ
    ds_rs_mono_itf              ds_mem_rs_i();
    ds_rs_mono_itf              ds_ldq_i();
    ds_rs_mono_itf              ds_stq_i();
    assign ds_mem_rs_i.valid = from_ds.valid && ds_ldq_i.ready && ds_stq_i.ready;
    assign ds_mem_rs_i.uop   = from_ds.uop;
    assign ds_stq_i.valid    = from_ds.valid && ds_mem_rs_i.ready && ds_ldq_i.ready;
    assign ds_stq_i.uop      = from_ds.uop;
    assign ds_ldq_i.valid    = from_ds.valid && ds_mem_rs_i.ready && ds_stq_i.ready;
    assign ds_ldq_i.uop      = from_ds.uop;
    assign from_ds.ready     = ds_mem_rs_i.ready && ds_ldq_i.ready && ds_stq_i.ready;

    agu_lsq_itf                 agu_lsq_i();

    mem_rs mem_rs_i(
        .clk                    (clk),
        .rst                    (rst || backend_flush),

        .from_ds                (ds_mem_rs_i),
        .to_prf                 (to_prf),
        .cdb                    (cdb),
        .to_lsq                 (agu_lsq_i)
    );

    dmem_itf                    dmem_itf_i();
    ldq_dmem_itf                ld_dmem_itf_i();
    stq_dmem_itf                st_dmem_itf_i();
    ldq_stq_itf                 ldq_stq_i();

    // lsq lsq_i(
    //     .clk                    (clk),
    //     .rst                    (rst),

    //     .from_ds                (ds_lsq_i),
    //     .from_agu               (agu_lsq_i),
    //     .cdb_out                (fu_cdb_out),
    //     .from_rob               (fu_cdb_out_dbg),
    //     .lsu_ready              (from_ds.ready),
    //     .backend_flush          (backend_flush),

    //     .dmem                   (dmem_itf_i)
    // );

    load_queue ldq_i(
        .clk                    (clk),
        .rst                    (rst),
        .backend_flush          (backend_flush),

        .from_ds                (ds_ldq_i),
        .from_agu               (agu_lsq_i),
        .cdb_out                (fu_cdb_out),
        .to_rob                 (ld_to_rob),
        .dmem                   (ld_dmem_itf_i),
        .from_stq               (ldq_stq_i)
    );

    store_queue stq_i(
        .clk                    (clk),
        .rst                    (rst),
        .backend_flush          (backend_flush),

        .from_ds                (ds_stq_i),
        .from_agu               (agu_lsq_i),
        .to_rob                 (st_to_rob),
        .dmem                   (st_dmem_itf_i),
        .from_ldq               (ldq_stq_i)
    );

    dmem_arbiter dmem_arb_i(
        .clk                    (clk),
        .rst                    (rst),
        .backend_flush          (backend_flush),

        .load                   (ld_dmem_itf_i),
        .store                  (st_dmem_itf_i),
        .cache                  (dmem_itf_i)
    );

    dcache dcache_i(
        .clk                    (clk),
        .rst                    (rst),

        .ufp                    (dmem_itf_i),

        .dfp                    (dcache_itf)
    );

endmodule
