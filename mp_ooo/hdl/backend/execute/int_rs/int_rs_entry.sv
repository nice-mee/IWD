module int_rs_entry
import cpu_params::*;
import uop_types::*;
import int_rs_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic               valid,
    // output  logic               will_be_valid,
    output  logic               request,
    input   logic               grant,

    input   logic               push_en,
    input   int_rs_entry_t      entry_in,
    output  int_rs_entry_t      entry_out,
    output  int_rs_entry_t      entry,
    input   logic               clear,

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

    int_rs_entry_t              entry_reg;
    int_rs_entry_t              next_entry;

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

    assign request = entry_valid && entry_reg.rs1_valid && entry_reg.rs2_valid;

    assign valid = entry_valid;
    assign entry = entry_reg;

endmodule
