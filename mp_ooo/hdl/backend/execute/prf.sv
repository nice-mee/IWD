module prf
import cpu_params::*;
import int_rs_types::*;
(
    input   logic               clk,
    input   logic               rst,

    rs_prf_itf.prf              from_rs[CDB_WIDTH],
    cdb_itf.prf                 cdb[CDB_WIDTH]
);
    // physical register file
    logic [31:0]    prf_data [PRF_DEPTH];

    // local copy of cdb interface and rs_prf_interface
    cdb_prf_t       cdb_local       [CDB_WIDTH];
    rs_prf_itf_t    from_rs_local   [CDB_WIDTH];
    generate 
        for (genvar i = 0; i < CDB_WIDTH; i++) begin 
            assign cdb_local[i].valid       = cdb[i].valid;
            assign cdb_local[i].rd_phy      = cdb[i].rd_phy;
            assign cdb_local[i].rd_value    = cdb[i].rd_value;

            assign from_rs_local[i].rs1_phy = from_rs[i].rs1_phy;
            assign from_rs_local[i].rs2_phy = from_rs[i].rs2_phy;
            assign from_rs[i].rs1_value     = from_rs_local[i].rs1_value;
            assign from_rs[i].rs2_value     = from_rs_local[i].rs2_value;
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i++) begin
                prf_data[i] <= '0;
            end
        end else begin
            for (int i = 0; i < CDB_WIDTH; i++) begin
                if (cdb_local[i].valid && (cdb_local[i].rd_phy != '0)) begin 
                    prf_data[cdb_local[i].rd_phy] <= cdb_local[i].rd_value;
                end
            end
        end
    end

    always_comb begin
        for (int j = 0; j < CDB_WIDTH; j++) begin
            from_rs_local[j].rs1_value = prf_data[from_rs_local[j].rs1_phy];
            from_rs_local[j].rs2_value = prf_data[from_rs_local[j].rs2_phy];

            for (int i = 0; i < CDB_WIDTH; i++) begin
                if (cdb_local[i].valid && (cdb_local[i].rd_phy == from_rs_local[j].rs1_phy)) begin 
                    from_rs_local[j].rs1_value = cdb_local[i].rd_value;
                end

                if (cdb_local[i].valid && (cdb_local[i].rd_phy == from_rs_local[j].rs2_phy)) begin 
                    from_rs_local[j].rs2_value = cdb_local[i].rd_value;
                end
            end

            if (from_rs_local[j].rs1_phy == '0) begin 
                from_rs_local[j].rs1_value = '0;
            end

            if (from_rs_local[j].rs2_phy == '0) begin 
                from_rs_local[j].rs2_value = '0;
            end
        end
    end


endmodule