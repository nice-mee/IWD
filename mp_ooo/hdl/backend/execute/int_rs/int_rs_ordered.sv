module int_rs_ordered
import cpu_params::*;
import uop_types::*;
import int_rs_types::*;
(
    input   logic               clk,
    input   logic               rst,

    ds_rs_itf.rs                from_ds,
    rs_prf_itf.rs               to_prf[INT_ISSUE_WIDTH],
    cdb_itf.rs                  cdb[CDB_WIDTH],
    cdb_itf.fu                  fu_cdb_out[INT_ISSUE_WIDTH],
    output bypass_network_t     alu_bypass
);

    //---------------------------------------------------------------------------------
    // Issue Queue:
    //---------------------------------------------------------------------------------

    logic   [INTRS_DEPTH-1:0]           rs_valid;
    logic   [INTRS_DEPTH-1:0]           rs_request;
    logic   [INTRS_DEPTH-1:0]           rs_grant;
    logic   [INTRS_DEPTH-1:0]           rs_push_en;
    logic   [INTRS_DEPTH-1:0]           rs_clear;
    int_rs_entry_t                      rs_entry[INTRS_DEPTH];
    int_rs_entry_t                      rs_entry_in[INTRS_DEPTH];
    int_rs_entry_t                      rs_entry_out[INTRS_DEPTH];
    int_rs_entry_t                      from_ds_entry[ID_WIDTH];
    logic   [INTRS_DEPTH-1:0] [CDB_WIDTH:0] rs1_bypass_en;
    logic   [INTRS_DEPTH-1:0] [CDB_WIDTH:0] rs2_bypass_en;

    always_comb begin
        for (int w = 0; w < ID_WIDTH; w++) begin
            from_ds_entry[w].rob_id     = from_ds.uop[w].rob_id;
            from_ds_entry[w].rs1_phy    = from_ds.uop[w].rs1_phy;
            from_ds_entry[w].rs1_valid  = from_ds.uop[w].rs1_valid;
            from_ds_entry[w].rs2_phy    = from_ds.uop[w].rs2_phy;
            from_ds_entry[w].rs2_valid  = from_ds.uop[w].rs2_valid;
            from_ds_entry[w].rd_phy     = from_ds.uop[w].rd_phy;
            from_ds_entry[w].rd_arch    = from_ds.uop[w].rd_arch;
            from_ds_entry[w].op1_sel    = from_ds.uop[w].op1_sel;
            from_ds_entry[w].op2_sel    = from_ds.uop[w].op2_sel;
            from_ds_entry[w].imm        = from_ds.uop[w].imm;
            from_ds_entry[w].fu_opcode  = from_ds.uop[w].fu_opcode;
        end
    end

    generate for (genvar i = 0; i < INTRS_DEPTH; i++) begin : rs_array
        rs_entry #(
            .RS_ENTRY_T (int_rs_entry_t)
        ) int_rs_entry_i (
            .clk            (clk),
            .rst            (rst),

            .valid          (rs_valid[i]),
            .request        (rs_request[i]),
            .grant          (rs_grant[i]),

            .push_en        (rs_push_en[i]),
            .entry_in       (rs_entry_in[i]),
            .entry_out      (rs_entry_out[i]),
            .entry          (rs_entry[i]),
            .clear          (rs_clear[i]),
            .wakeup_cdb     (cdb),
            .fast_bypass    (alu_bypass),
            .rs1_bypass_en  (rs1_bypass_en[i]),
            .rs2_bypass_en  (rs2_bypass_en[i])
        );
    end endgenerate

    //---------------------------------------------------------------------------------
    // RS Control:
    //---------------------------------------------------------------------------------

    // pointer to top of the array (like a fifo queue)
    logic [INTRS_IDX-1:0]   int_rs_top, rs_top_next;

    // pop logic
    logic                   int_rs_pop_en   [INT_ISSUE_WIDTH];
    logic                   alu_ready       [INT_ISSUE_WIDTH];

    // allocate logic
    logic                   int_rs_push_en  [ID_WIDTH];
    logic [INTRS_IDX-1:0]   int_rs_push_idx [ID_WIDTH];

    // issue logic
    int_rs_entry_t          issued_entry    [INT_ISSUE_WIDTH];
    logic                   fu_issue_en     [INT_ISSUE_WIDTH];
    logic   [INTRS_IDX-1:0] fu_issue_idx    [INT_ISSUE_WIDTH];

    // update mux logic
    rs_update_sel_t             rs_update_sel   [INTRS_DEPTH];
    logic [ID_WIDTH_IDX-1:0]    rs_push_sel     [INTRS_DEPTH];
    logic [INT_ISSUE_IDX-1:0]   rs_compress_sel [INTRS_DEPTH];

    ///////////////////////
    // Mux Select Logic  //
    ///////////////////////
    always_comb begin : compress_control
        for (int i = 0; i < INTRS_DEPTH; i++) begin
            // init
            rs_push_sel[i] = 'x;
            rs_update_sel[i] = SELF;
            rs_compress_sel[i] = '0;
            // compress
            for( int j = 0; j < INT_ISSUE_WIDTH; j++ ) begin
                if( rs_valid[i] & int_rs_pop_en[j] & (INTRS_IDX)'(unsigned'(i))>=fu_issue_idx[j] ) begin
                    rs_update_sel[i] = NEXT;
                    rs_compress_sel[i] = INT_ISSUE_IDX'(unsigned'(j));
                    if(  unsigned'(j) < INT_ISSUE_WIDTH-unsigned'(1)  ) begin // handle corner case
                        if( int_rs_pop_en[j+1] && INTRS_IDX'(unsigned'(i+j)+1)==fu_issue_idx[j+1] ) begin
                            rs_compress_sel[i] = rs_compress_sel[i] + INT_ISSUE_IDX'(unsigned'(1));
                        end
                    end
                end
            end
            // push
            for( int j = 0; j < ID_WIDTH; j++ ) begin 
                if ( int_rs_push_en[j] && ((INTRS_IDX)'(unsigned'(i)) == int_rs_push_idx[j]) ) begin
                    rs_update_sel[i] = PUSH_IN;
                    rs_push_sel[i] = ID_WIDTH_IDX'(unsigned'(j));
                end
            end
        end
    end

    always_comb begin
        for (int i = 0; i < INTRS_DEPTH; i++) begin
            unique case (rs_update_sel[i])
                NEXT: begin
                    if( unsigned'(i)+{31'b0, rs_compress_sel[i]} < INTRS_DEPTH-unsigned'(1) ) begin
                        rs_push_en[i] = rs_valid[unsigned'(i)+{31'b0, rs_compress_sel[i]}+1];
                        rs_clear[i] = ~rs_valid[unsigned'(i)+{31'b0, rs_compress_sel[i]}+1];
                    end else begin
                        rs_push_en[i] = 1'b0;
                        rs_clear[i] = 1'b1;
                    end
                end
                SELF: begin
                    rs_push_en[i] = 1'b0;
                    rs_clear[i] = 1'b0;
                end
                PUSH_IN: begin
                    rs_push_en[i] = 1'b1;
                    rs_clear[i] = 1'b0;
                end
                default: begin
                    rs_push_en[i] = 1'bx;
                    rs_clear[i] = 1'bx;
                end
            endcase
        end
    end

    always_comb begin : compress_mux 
        for (int i = 0; i < INTRS_DEPTH; i++) begin
            unique case (rs_update_sel[i])
                NEXT: begin
                    if (unsigned'(i)+{31'b0, rs_compress_sel[i]} < INTRS_DEPTH-unsigned'(1)) begin
                        rs_entry_in[i] = rs_entry_out[unsigned'(i)+{31'b0, rs_compress_sel[i]}+unsigned'(1)];
                    end else begin
                        rs_entry_in[i] = 'x;
                    end
                end
                SELF: begin
                    rs_entry_in[i] = 'x;
                end
                PUSH_IN: begin
                    rs_entry_in[i] = from_ds_entry[rs_push_sel[i]];
                end
                default: begin
                    rs_entry_in[i] = 'x;
                end
            endcase
        end
    end

    ///////////////////////
    // Push & Pop Logic  //
    ///////////////////////
    always_ff @(posedge clk) begin
        // rs array reset to all available, and top point to 0
        if (rst) begin
            int_rs_top <= '0;
        end else begin
            int_rs_top <= rs_top_next;
        end
    end

    always_comb begin
        // init
        rs_top_next = int_rs_top;
        // pop
        for( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            int_rs_pop_en[i] = '0;
            if( fu_issue_en[i] & alu_ready[i] ) begin
                int_rs_pop_en[i] = '1;
                rs_top_next = INTRS_IDX'(rs_top_next - 1); 
            end
        end
        // push: Allocate logic
        for( int i = 0; i < ID_WIDTH; i++ ) begin
            int_rs_push_en[i] = '0;
            int_rs_push_idx[i] = 'x;
            if( from_ds.valid[i] && from_ds.ready ) begin 
                int_rs_push_en[i] = '1;
                int_rs_push_idx[i] = rs_top_next;
                rs_top_next = INTRS_IDX'(rs_top_next + 1);
            end
        end
    end

    //////////////////
    // Issue Logic  //
    //////////////////
    issue_arbiter issue_arbiter_i( 
        .rs_request(rs_request),
        .rs_grant(rs_grant),
        .fu_issue_en(fu_issue_en),
        .fu_issue_idx(fu_issue_idx)
    );
    generate for (genvar i = 0; i < INT_ISSUE_WIDTH; i++) begin
        assign issued_entry[i] = rs_entry[fu_issue_idx[i]];
    end endgenerate
    
    ////////////
    // Ready  //
    one_hot_mux #(
        .T          (logic [CDB_WIDTH:0]),
        .NUM_INPUTS (INTRS_DEPTH)
    ) ohm_rs1 (
        .data_in    (rs1_bypass_en),
        .select     (rs_grant),
        .data_out   (to_prf.rs1_bypass_en)
    );

    one_hot_mux #(
        .T          (logic [CDB_WIDTH:0]),
        .NUM_INPUTS (INTRS_DEPTH)
    ) ohm_rs2 (
        .data_in    (rs2_bypass_en),
        .select     (rs_grant),
        .data_out   (to_prf.rs2_bypass_en)
    );

    ////////////
    logic   [INTRS_IDX:0]    n_available_slots;
    always_comb begin
        n_available_slots = '0;
        for (int i = 0; i < INTRS_DEPTH; i++) begin 
            if (~rs_valid[i]) begin 
                n_available_slots = (INTRS_IDX+1)'(n_available_slots + 1);
            end
        end
    end
    assign from_ds.ready = (n_available_slots >= (INTRS_IDX+1)'(ID_WIDTH));

    ///////////////////////////
    // communicate with prf  //
    ///////////////////////////
    generate for (genvar i = 0; i < INT_ISSUE_WIDTH; i++) begin
        assign to_prf[i].rs1_phy = issued_entry[i].rs1_phy;
        assign to_prf[i].rs2_phy = issued_entry[i].rs2_phy;
    end endgenerate

    //---------------------------------------------------------------------------------
    // INT_RS Reg to FU_ALU:
    //---------------------------------------------------------------------------------

    fu_alu_reg_t    fu_alu_reg_in   [INT_ISSUE_WIDTH];

    // handshake with fu_alu_reg:
    // assign int_rs_valid = |rs_grant;

    // send data to fu_alu_reg
    generate for (genvar i = 0; i < INT_ISSUE_WIDTH; i++) begin
        always_comb begin
            fu_alu_reg_in[i].rob_id       = issued_entry[i].rob_id;
            fu_alu_reg_in[i].rd_phy       = issued_entry[i].rd_phy;
            fu_alu_reg_in[i].rd_arch      = issued_entry[i].rd_arch;
            fu_alu_reg_in[i].op1_sel      = issued_entry[i].op1_sel;
            fu_alu_reg_in[i].op2_sel      = issued_entry[i].op2_sel;
            fu_alu_reg_in[i].fu_opcode    = issued_entry[i].fu_opcode;
            fu_alu_reg_in[i].imm          = issued_entry[i].imm;

            fu_alu_reg_in[i].rs1_value    = to_prf[i].rs1_value;
            fu_alu_reg_in[i].rs2_value    = to_prf[i].rs2_value;
        end
    end endgenerate


    // Functional Units
    generate for (genvar i = 0; i < INT_ISSUE_WIDTH; i++) begin : alu
        fu_alu fu_alu_i(
            .clk                    (clk),
            .rst                    (rst),
            .int_rs_valid           (fu_issue_en[i]),
            .fu_alu_ready           (alu_ready[i]),
            .fu_alu_reg_in          (fu_alu_reg_in[i]),
            .cdb                    (fu_cdb_out[i])
        );
    end endgenerate

endmodule
