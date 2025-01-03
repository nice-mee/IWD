// pipeline_reg
// A simple implementation of a pipeline register with valid/ready handshaking.

module pipeline_reg #(
            parameter   type        DATA_T = logic[1:0]
)
(
    input   logic                   clk,
    input   logic                   rst,

    input   logic                   flush,

    // Prev stage handshake
    input   logic                   prv_valid,
    output  logic                   prv_ready,

    // Next stage handshake
    output  logic                   nxt_valid,
    input   logic                   nxt_ready,

    // Datapath input
    input   DATA_T                  prv_data,

    // Datapath output
    output  DATA_T                  nxt_data
);

    logic                           reg_valid;
    DATA_T                          reg_data;

    assign nxt_valid = reg_valid;
    assign prv_ready = ~reg_valid || (nxt_valid && nxt_ready);

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            reg_valid <= '0;
        end else if (prv_ready) begin
            reg_valid <= prv_valid;
        end
    end

    always_ff @(posedge clk) begin
        if (prv_ready && prv_valid) begin
            reg_data <= prv_data;
        end
    end

    assign nxt_data = reg_data;

endmodule
