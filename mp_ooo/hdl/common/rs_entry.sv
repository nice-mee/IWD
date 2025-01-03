module rs_entry 
import cpu_params::*;
import uop_types::*;
import int_rs_types::*; #(
    parameter type RS_ENTRY_T = int_rs_entry_t
)
(
    input   logic               clk,
    input   logic               rst,

    output  logic               valid, // if the entry is valid
    output  logic               request, // if the entry is ready to be issued
    input   logic               grant, // permission to issue the entry

    input   logic               push_en, // push a new entry
    input   RS_ENTRY_T          entry_in, // new entry
    output  RS_ENTRY_T          entry_out, // current entry but with CDB forwarding (useful in shifting queues)
    output  RS_ENTRY_T          entry, // current entry
    input   logic               clear, // clear this entry (useful in shifting queues)

    input bypass_network_t      fast_bypass[NUM_FAST_BYPASS],
    output bypass_t             rs_bypass,
    cdb_itf.rs                  wakeup_cdb[CDB_WIDTH]
);

    cdb_rs_t cdb_rs[CDB_WIDTH];
    generate 
        for (genvar i = 0; i < CDB_WIDTH; i++) begin 
            assign cdb_rs[i].valid  = wakeup_cdb[i].valid;
            assign cdb_rs[i].rd_phy = wakeup_cdb[i].rd_phy;
        end
    endgenerate

    logic                       entry_valid;
    logic                       next_valid;

    RS_ENTRY_T                  entry_reg;
    RS_ENTRY_T                  next_entry;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            entry_valid <= 1'b0;
        end else begin
            entry_valid <= next_valid;
        end
    end

    always_comb begin
        next_valid = entry_valid;
        if (push_en) begin
            next_valid = 1'b1;
        end else if (grant) begin
            next_valid = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        entry_reg <= next_entry;
    end

    always_comb begin
        next_entry = entry_reg;
        if (push_en) begin
            next_entry = entry_in;
        end else begin
            for (int k = 0; k < CDB_WIDTH; k++) begin
                if (cdb_rs[k].valid) begin
                    if (entry_reg.rs1_phy == cdb_rs[k].rd_phy) begin
                        next_entry.rs1_valid = 1'b1;
                    end
                    if (entry_reg.rs2_phy == cdb_rs[k].rd_phy) begin
                        next_entry.rs2_valid = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin
        entry_out = entry_reg;
        for (int k = 0; k < CDB_WIDTH; k++) begin
            if (cdb_rs[k].valid) begin
                if (entry_reg.rs1_phy == cdb_rs[k].rd_phy) begin
                    entry_out.rs1_valid = 1'b1;
                end
                if (entry_reg.rs2_phy == cdb_rs[k].rd_phy) begin
                    entry_out.rs2_valid = 1'b1;
                end
            end
        end
    end

    logic                       src1_ready;
    logic                       src2_ready;

    generate for (genvar i = 0; i < CDB_WIDTH; i++) begin
        assign rs_bypass.rs1_bypass_en[i] = cdb_rs[i].valid && (cdb_rs[i].rd_phy != '0) && (entry_reg.rs1_phy == cdb_rs[i].rd_phy);
        assign rs_bypass.rs2_bypass_en[i] = cdb_rs[i].valid && (cdb_rs[i].rd_phy != '0) && (entry_reg.rs2_phy == cdb_rs[i].rd_phy);
    end endgenerate

    // add dual issue support
    always_comb begin
        rs_bypass.rs1_bypass_en[CDB_WIDTH] = '0;
        rs_bypass.rs2_bypass_en[CDB_WIDTH] = '0;
        rs_bypass.rs1_bypass_sel = 'x;
        rs_bypass.rs2_bypass_sel = 'x;
        // alu1 has higher priority, since oldest inst would be issued to alu1
        for ( int i = 0; i < NUM_FAST_BYPASS; i++ ) begin
            if( fast_bypass[i].valid && (fast_bypass[i].rd_phy != '0) && (entry_reg.rs1_phy == fast_bypass[i].rd_phy) ) begin
                rs_bypass.rs1_bypass_en[CDB_WIDTH] = '1;
                rs_bypass.rs1_bypass_sel = INT_ISSUE_IDX'(unsigned'(i));
                break;
            end
        end
        for ( int i = 0; i < NUM_FAST_BYPASS; i++ ) begin
            if( fast_bypass[i].valid && (fast_bypass[i].rd_phy != '0) && (entry_reg.rs2_phy == fast_bypass[i].rd_phy) ) begin
                rs_bypass.rs2_bypass_en[CDB_WIDTH] = '1;
                rs_bypass.rs2_bypass_sel = INT_ISSUE_IDX'(unsigned'(i));
                break;
            end
        end
    end
    // assign rs_bypass.rs1_bypass_en[CDB_WIDTH] = fast_bypass.valid && (fast_bypass.rd_phy != '0) && (entry_reg.rs1_phy == fast_bypass.rd_phy);
    // assign rs_bypass.rs2_bypass_en[CDB_WIDTH] = fast_bypass.valid && (fast_bypass.rd_phy != '0) && (entry_reg.rs2_phy == fast_bypass.rd_phy);


    assign src1_ready = entry_reg.rs1_valid || |(rs_bypass.rs1_bypass_en);
    assign src2_ready = entry_reg.rs2_valid || |(rs_bypass.rs2_bypass_en);
    assign request = entry_valid && src1_ready && src2_ready;

    assign valid = entry_valid;
    assign entry = entry_reg;

endmodule
