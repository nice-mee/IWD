module branch_top
import cpu_params::*;
import uop_types::*;
import int_rs_types::*;
(
    input   logic               clk,
    input   logic               rst,
    input   logic               backend_flush,

    ds_rs_mono_itf.rs        	from_ds,
    rs_prf_itf.rs               to_prf,
    cdb_itf.rs                  cdb[CDB_WIDTH],
    cdb_itf.fu                  fu_cdb_out,
    cb_bp_itf.cb                to_bp,
    cb_rob_itf.cb               to_rob,
    input bypass_network_t      alu_bypass[NUM_FAST_BYPASS]
);
    br_cdb_itf                  br_cdb_itf_i();

    ds_rs_mono_itf              ds_br_rs_itf_i();
    ds_rs_mono_itf              ds_cb_itf_i();

    assign ds_br_rs_itf_i.valid = from_ds.valid;
    assign ds_br_rs_itf_i.uop   = from_ds.uop;
    assign ds_cb_itf_i.valid    = from_ds.valid;
    assign ds_cb_itf_i.uop      = from_ds.uop;

    assign from_ds.ready        = ds_br_rs_itf_i.ready && ds_cb_itf_i.ready;

    control_buffer control_buffer_i(
        .clk                    (clk),
        .rst                    (rst || backend_flush),

        .from_ds                (ds_cb_itf_i),
        .br_cdb_in              (br_cdb_itf_i),
        .to_rob                 (to_rob),
        .branch_ready           (from_ds.ready),
        .to_bp                  (to_bp)
    );

    br_rs br_rs_i(
        .clk                    (clk),
        .rst                    (rst || backend_flush),

        .from_ds                (ds_br_rs_itf_i),
        .to_prf                 (to_prf),
        .cdb                    (cdb),
        .fu_cdb_out             (fu_cdb_out),
        .br_cdb_out             (br_cdb_itf_i),
        .branch_ready           (from_ds.ready),
        .alu_bypass             (alu_bypass)
    );
endmodule
