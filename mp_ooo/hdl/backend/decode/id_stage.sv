module id_stage
import cpu_params::*;
import uop_types::*;
(
    // input   logic               clk,
    // input   logic               rst,

    // Instruction queue
    fifo_backend_itf.backend    from_fifo,

    // RAT
    id_rat_itf.id               to_rat,

    // Free List
    id_fl_itf.id                to_fl,

    // ROB
    id_rob_itf.id               to_rob,

    // INT Reservation Stations
    id_int_rs_itf.id            to_int_rs,

    // INTM Reservation Stations
    id_int_rs_itf.id            to_intm_rs

);
    uop_t                       uop;
    rs_type_t                   rs_type;
    // fu_type_t                   fu_type;
    logic   [3:0]               fu_opcode;
    op1_sel_t                   op1_sel;
    op2_sel_t                   op2_sel;
    logic   [31:0]              imm;
    logic   [ARF_IDX-1:0]       rd_arch;
    logic   [ARF_IDX-1:0]       rs1_arch;
    logic   [ARF_IDX-1:0]       rs2_arch;
    logic                       inst_invalid;

    //////////////////////////
    //     Decode Stage     //
    //////////////////////////

    decoder decoder_i(
        .inst                   (from_fifo.data.inst[0]),
        .*
    );

    assign uop.pc = from_fifo.data.pc[0];
    assign uop.inst = from_fifo.data.inst[0];
    assign uop.rs_type = rs_type;
    // assign uop.fu_type = fu_type;
    assign uop.fu_opcode = fu_opcode;
    assign uop.op1_sel = op1_sel;
    assign uop.op2_sel = op2_sel;
    assign uop.imm = imm;
    assign uop.rd_arch = rd_arch;
    assign uop.rs1_arch = rs1_arch;
    assign uop.rs2_arch = rs2_arch;


    //////////////////////////
    //     Rename Stage     //
    //////////////////////////

    // Pop from free list if we do need destination register
    logic rs_ready;
    assign rs_ready = (to_int_rs.ready && (rs_type == RS_INT)) || (to_intm_rs.ready && (rs_type == RS_INTM));
    assign to_fl.valid = from_fifo.valid && to_rob.ready && rs_ready && (rd_arch != '0)  && ~inst_invalid;

    // Read from RAT
    assign to_rat.read_arch[0] = rs1_arch;
    assign to_rat.read_arch[1] = rs2_arch;
    assign uop.rs1_phy = to_rat.read_phy[0];
    assign uop.rs1_valid = to_rat.read_valid[0];
    assign uop.rs2_phy = to_rat.read_phy[1];
    assign uop.rs2_valid = to_rat.read_valid[1];

    // Write to RAT if we do need destination register
    assign to_rat.write_en = from_fifo.valid && to_fl.ready && to_rob.ready && rs_ready && (rd_arch != '0) && ~inst_invalid;
    assign to_rat.write_arch = uop.rd_arch;
    assign to_rat.write_phy = to_fl.free_idx;
    assign uop.rd_phy = (rd_arch != '0) ? to_fl.free_idx : '0;

    // Notify ROB
    assign to_rob.valid = from_fifo.valid && to_fl.ready && rs_ready && ~inst_invalid;
    assign to_rob.rd_phy = uop.rd_phy;
    assign to_rob.rd_arch = uop.rd_arch;
    assign uop.rob_id = to_rob.rob_id;


    //////////////////////////
    //    Dispatch Stage    //
    //////////////////////////

    // Dispatch to INT Reservation Stations
    assign to_int_rs.valid = from_fifo.valid && to_fl.ready && to_rob.ready && (rs_type == RS_INT) && ~inst_invalid;
    assign to_int_rs.uop = uop;

    // Dispatch to INTM Reservation Stations
    assign to_intm_rs.valid = from_fifo.valid && to_fl.ready && to_rob.ready && (rs_type == RS_INTM) && ~inst_invalid;
    assign to_intm_rs.uop = uop;

    // Backpressure Ready signal
    assign from_fifo.ready = to_fl.ready && to_rob.ready && rs_ready && ~inst_invalid;

    //////////////////////////
    //          RVFI        //
    //////////////////////////

    assign to_rob.rvfi_dbg.order = 'x;
    assign to_rob.rvfi_dbg.inst = uop.inst;
    assign to_rob.rvfi_dbg.rs1_addr = uop.rs1_arch;
    assign to_rob.rvfi_dbg.rs2_addr = uop.rs2_arch;
    assign to_rob.rvfi_dbg.rs1_rdata = 'x;
    assign to_rob.rvfi_dbg.rs2_rdata = 'x;
    assign to_rob.rvfi_dbg.rd_addr = uop.rd_arch;
    assign to_rob.rvfi_dbg.rd_wdata = 'x;
    assign to_rob.rvfi_dbg.frd_addr = 'x;
    assign to_rob.rvfi_dbg.frd_wdata = 'x;
    assign to_rob.rvfi_dbg.pc_rdata = uop.pc;
    assign to_rob.rvfi_dbg.pc_wdata = 'x;
    assign to_rob.rvfi_dbg.mem_addr = 'x;
    assign to_rob.rvfi_dbg.mem_rmask = 'x;
    assign to_rob.rvfi_dbg.mem_wmask = 'x;
    assign to_rob.rvfi_dbg.mem_rdata = 'x;
    assign to_rob.rvfi_dbg.mem_wdata = 'x;

endmodule
