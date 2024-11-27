module br_rs
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
    br_cdb_itf.fu               br_cdb_out,
    input   logic               branch_ready
);
    ///////////////////////////
    // Reservation Stations  //
    ///////////////////////////

    // local copy of cdb
    cdb_rs_t cdb_rs[CDB_WIDTH];
    generate 
        for (genvar i = 0; i < CDB_WIDTH; i++) begin 
            assign cdb_rs[i].valid  = cdb[i].valid;
            assign cdb_rs[i].rd_phy = cdb[i].rd_phy;
        end
    endgenerate

    typedef struct packed {
        logic   [ROB_IDX-1:0]   rob_id;
        logic   [PRF_IDX-1:0]   rs1_phy;
        logic                   rs1_valid;
        logic   [PRF_IDX-1:0]   rs2_phy;
        logic                   rs2_valid;
        logic   [PRF_IDX-1:0]   rd_phy;
        logic   [ARF_IDX-1:0]   rd_arch;
        logic   [31:0]          imm;
        logic   [31:0]          pc;
        logic   [3:0]           fu_opcode;
        logic                   predict_taken;
        logic   [31:0]          predict_target;
    } br_rs_entry_t;

    // rs array, store uop+available
    br_rs_entry_t   br_rs_arr      [BRRS_DEPTH];
    logic           br_rs_available  [BRRS_DEPTH];

    // push logic
    logic                   int_rs_push_en;
    logic [BRRS_IDX-1:0]    int_rs_push_idx;

    // issue logic
    logic                   int_rs_issue_en;
    logic [BRRS_IDX-1:0]    int_rs_issue_idx;
    logic                   src1_valid;
    logic                   src2_valid;

    // rs array update
    always_ff @(posedge clk) begin 
        // rs array reset to all available, and top point to 0
        if (rst || backend_flush) begin 
            for (int i = 0; i < BRRS_DEPTH; i++) begin 
                br_rs_available[i] <= 1'b1;
            end
        end else begin 
            // issue > snoop cdb > push
            // push renamed instruction
            if (int_rs_push_en) begin 
                // set rs to unavailable
                br_rs_available[int_rs_push_idx]           <= 1'b0;
                br_rs_arr[int_rs_push_idx].rob_id        <= from_ds.uop.rob_id;
                br_rs_arr[int_rs_push_idx].rs1_phy       <= from_ds.uop.rs1_phy;
                br_rs_arr[int_rs_push_idx].rs1_valid     <= from_ds.uop.rs1_valid;
                br_rs_arr[int_rs_push_idx].rs2_phy       <= from_ds.uop.rs2_phy;
                br_rs_arr[int_rs_push_idx].rs2_valid     <= from_ds.uop.rs2_valid;
                br_rs_arr[int_rs_push_idx].rd_phy        <= from_ds.uop.rd_phy;
                br_rs_arr[int_rs_push_idx].rd_arch       <= from_ds.uop.rd_arch;
                br_rs_arr[int_rs_push_idx].imm           <= from_ds.uop.imm;
                br_rs_arr[int_rs_push_idx].pc            <= from_ds.uop.pc;
                br_rs_arr[int_rs_push_idx].fu_opcode     <= from_ds.uop.fu_opcode;
                br_rs_arr[int_rs_push_idx].predict_taken <= from_ds.uop.predict_taken;
                br_rs_arr[int_rs_push_idx].predict_target <= from_ds.uop.predict_target;
            end

            // snoop CDB to update rs1/rs2 valid
            for (int i = 0; i < BRRS_DEPTH; i++) begin
                for (int k = 0; k < CDB_WIDTH; k++) begin 
                    // if the rs is unavailable (not empty), and rs1/rs2==cdb.rd,
                    // set rs1/rs2 to valid
                    if (cdb_rs[k].valid && !br_rs_available[i]) begin 
                        if (br_rs_arr[i].rs1_phy == cdb_rs[k].rd_phy) begin 
                            br_rs_arr[i].rs1_valid <= 1'b1;
                        end
                        if (br_rs_arr[i].rs2_phy == cdb_rs[k].rd_phy) begin 
                            br_rs_arr[i].rs2_valid <= 1'b1;
                        end
                    end
                end 
            end

            // pop issued instruction
            if (int_rs_issue_en) begin 
                // set rs to available
                br_rs_available[int_rs_issue_idx] <= 1'b1;
            end
        end
    end

    // push logic, push instruction to rs if id is valid and rs is ready
    // loop from top until the first available station
    always_comb begin
        int_rs_push_en  = '0;
        int_rs_push_idx = '0;
        if (from_ds.valid && branch_ready) begin 
            for (int i = 0; i < BRRS_DEPTH; i++) begin 
                if (br_rs_available[(BRRS_IDX)'(unsigned'(i))]) begin 
                    int_rs_push_idx = (BRRS_IDX)'(unsigned'(i));
                    int_rs_push_en = 1'b1;
                    break;
                end
            end
        end
    end

    // issue enable logic
    // loop from top until src all valid
    always_comb begin
        int_rs_issue_en  = '0;
        int_rs_issue_idx = '0; 
        src1_valid       = '0;
        src2_valid       = '0;
        for (int i = 0; i < BRRS_DEPTH; i++) begin 
            if (!br_rs_available[(BRRS_IDX)'(unsigned'(i))]) begin 
                
                src1_valid = br_rs_arr[(BRRS_IDX)'(unsigned'(i))].rs1_valid;
                for (int k = 0; k < CDB_WIDTH; k++) begin 
                    if (cdb_rs[k].valid && (cdb_rs[k].rd_phy == br_rs_arr[(BRRS_IDX)'(unsigned'(i))].rs1_phy)) begin 
                        src1_valid = 1'b1;
                    end
                end
                    
                src2_valid = br_rs_arr[(BRRS_IDX)'(unsigned'(i))].rs2_valid;
                for (int k = 0; k < CDB_WIDTH; k++) begin 
                    if (cdb_rs[k].valid && (cdb_rs[k].rd_phy == br_rs_arr[(BRRS_IDX)'(unsigned'(i))].rs2_phy)) begin 
                        src2_valid = 1'b1;
                    end
                end
                    
                if (src1_valid && src2_valid) begin 
                    int_rs_issue_en = '1;
                    int_rs_issue_idx = (BRRS_IDX)'(unsigned'(i));
                    break;
                end
            end
        end
    end

    // full logic, set rs.ready to 0 if rs is full
    always_comb begin 
    	from_ds.ready = '0;
        for (int i = 0; i < BRRS_DEPTH; i++) begin 
            if (br_rs_available[i]) begin 
                from_ds.ready = '1;
            end
        end
    end
    // assign from_ds.ready = |br_rs_available;

    // communicate with prf
    assign to_prf.rs1_phy = br_rs_arr[int_rs_issue_idx].rs1_phy;
    assign to_prf.rs2_phy = br_rs_arr[int_rs_issue_idx].rs2_phy;

    //////////////////////
    // BR_RS to FU_ALU //
    //////////////////////
    logic           br_rs_valid;
    logic           fu_br_ready;
    fu_br_reg_t     fu_br_reg_in;

    // handshake with fu_alu_reg:
    assign br_rs_valid = int_rs_issue_en;

    // send data to fu_alu_reg
    always_comb begin 
        fu_br_reg_in.rob_id         = br_rs_arr[int_rs_issue_idx].rob_id;
        fu_br_reg_in.rd_phy         = br_rs_arr[int_rs_issue_idx].rd_phy;
        fu_br_reg_in.rd_arch        = br_rs_arr[int_rs_issue_idx].rd_arch;
        fu_br_reg_in.fu_opcode      = br_rs_arr[int_rs_issue_idx].fu_opcode;
        fu_br_reg_in.imm            = br_rs_arr[int_rs_issue_idx].imm;
        fu_br_reg_in.pc             = br_rs_arr[int_rs_issue_idx].pc;
        fu_br_reg_in.predict_taken  = br_rs_arr[int_rs_issue_idx].predict_taken;
        fu_br_reg_in.predict_target = br_rs_arr[int_rs_issue_idx].predict_target;

        fu_br_reg_in.rs1_value      = to_prf.rs1_value;
        fu_br_reg_in.rs2_value      = to_prf.rs2_value;
    end


    // Functional Units
    fu_br fu_br_i(
        .clk                    (clk),
        .rst                    (rst),
        .backend_flush          (backend_flush),

        .br_rs_valid            (br_rs_valid),
        .fu_br_ready            (fu_br_ready),
        .fu_br_reg_in           (fu_br_reg_in),
        .cdb                    (fu_cdb_out),
        .br_cdb                 (br_cdb_out)
    );

    // pipeline_reg 

endmodule
