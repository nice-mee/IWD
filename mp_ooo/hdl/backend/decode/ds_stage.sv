module ds_stage
import cpu_params::*;
import uop_types::*;
(
    // input   logic               clk,
    // input   logic               rst,

    // handshake with rename stage
    input   logic               prv_valid,
    output  logic               prv_ready,
    input   uop_t               uops[ID_WIDTH],

    // INT Reservation Stations
    ds_int_rs_itf.ds            to_int_rs,

    // INTM Reservation Stations
    ds_int_rs_itf.ds            to_intm_rs
);

    //////////////////////////
    //    Dispatch Stage    //
    //////////////////////////

    logic               dispatch_valid  [ID_WIDTH];
    logic               dispatch_ready  [ID_WIDTH];

    // Upstream signals to determine if we can dispatch
    generate for (genvar i = 0; i < ID_WIDTH; i++) begin : dispatch_valids
        assign dispatch_valid[i] = prv_valid && uops[i].valid;
    end endgenerate

    // Encoder to select the reservation station
    generate for (genvar i = 0; i < ID_WIDTH; i++) begin : valid_encoders
        always_comb begin
            to_int_rs.valid = '0;
            to_intm_rs.valid = '0;
            unique case (uops[i].rs_type)
                RS_INT: begin
                    to_int_rs.valid = dispatch_valid[i]; // Dispatch to INT Reservation Stations
                end
                RS_INTM: begin
                    to_intm_rs.valid = dispatch_valid[i]; // Dispatch to INTM Reservation Stations
                end
                default: begin
                end
            endcase
        end
    end endgenerate

    generate for (genvar i = 0; i < ID_WIDTH; i++) begin
        assign to_int_rs.uop = uops[i];
        assign to_intm_rs.uop = uops[i];
    end endgenerate

    // Mux for selecting the ready signal
    generate for (genvar i = 0; i < ID_WIDTH; i++) begin
        always_comb begin
            unique case (uops[i].rs_type)
                RS_INT: begin
                    dispatch_ready[i] = to_int_rs.ready; // Collect ready signal from INT Reservation Stations
                end
                RS_INTM: begin
                    dispatch_ready[i] = to_intm_rs.ready; // Collect ready signal from INTM Reservation Stations
                end
                default: begin
                    dispatch_ready[i] = '0;
                end
            endcase
        end
    end endgenerate

    always_comb begin
        prv_ready = 1'b1;
        for (int i = 0; i < ID_WIDTH; i++) begin
            prv_ready = prv_ready && dispatch_ready[i];
        end
    end

endmodule