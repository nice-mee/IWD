module arbiter 
import arbiter_types::*;
(
    input   logic                   clk,
    input   logic                   rst,

    cacheline_itf.slave             icache,
    cacheline_itf.slave             dcache,
    cacheline_itf.master            adapter
);


    //---------------------------------------------------------------------------------
    // Record Write Info
    //---------------------------------------------------------------------------------
    
    logic   [31:0]                  addr_buf;
    logic   [255:0]                 data_buf;

    always_ff @( posedge clk ) begin
        if( rst ) begin
            addr_buf <= '0;
            data_buf <= '0;
        end else begin
            if( dcache.write ) begin
                addr_buf <= dcache.addr;
                data_buf <= dcache.wdata;
            end
        end
    end

    //---------------------------------------------------------------------------------
    // FSM
    //---------------------------------------------------------------------------------

    logic curr_state, next_state;

    always_ff @( posedge clk ) begin
        if( rst ) begin
            curr_state <= PASS_THRU;
        end else begin
            curr_state <= next_state;
        end
    end

    always_comb begin
        icache.ready    =   '0;
        dcache.ready    =   '0;
        adapter.read    =   '0;
        adapter.write   =   '0;
        adapter.addr    =   'x;
        adapter.wdata   =   'x;  
        unique case (curr_state)
            PASS_THRU: begin
                if( adapter.ready ) begin
                    if( dcache.read || dcache.write ) begin // prioritize dcache, since icache is always reading
                        dcache.ready    =   '1;
                        adapter.read    =   dcache.read;
                        adapter.write   =   dcache.write;
                        adapter.addr    =   dcache.addr;
                        adapter.wdata   =   dcache.wdata;
                    end else if ( icache.read ) begin
                        icache.ready    =   '1;
                        adapter.read    =   '1;
                        adapter.addr    =   icache.addr;
                        adapter.wdata   =   icache.wdata;
                    end
                end
            end
            WAIT_WRITE: begin
                    adapter.write   =   '1;
                    adapter.addr    =   addr_buf;
                    adapter.wdata   =   data_buf;
            end
            default: ;
        endcase
    end

    always_comb begin
        unique case (curr_state)
            PASS_THRU: begin
                if( dcache.write )          next_state = WAIT_WRITE;
                else                        next_state = PASS_THRU;
            end
            WAIT_WRITE: begin
                if( adapter.ready )         next_state = PASS_THRU;   
                else                        next_state = WAIT_WRITE;
            end 
            default: next_state = curr_state;
        endcase
    end

    //---------------------------------------------------------------------------------
    // Direct Connect, Leave for Master
    //---------------------------------------------------------------------------------

    always_comb begin
        icache.rdata    =   adapter.rdata;
        dcache.rdata    =   adapter.rdata;
        icache.rvalid   =   adapter.rvalid;
        dcache.rvalid   =   adapter.rvalid;
        icache.raddr    =   adapter.raddr;
        dcache.raddr    =   adapter.raddr;
    end

endmodule
