
`timescale 1ns/1ps

module dma_controller (
    input wire ACLK,
    input wire ARESETN,

    // APB Slave
    input wire        PSEL,
    input wire        PENABLE,
    input wire        PWRITE,
    input wire [31:0] PADDR,
    input wire [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire        PREADY,

    // AXI Master
    output reg [31:0] M_AXI_AWADDR,
    output reg [3:0]  M_AXI_AWLEN,
    output reg [2:0]  M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    output reg        M_AXI_AWVALID,
    input wire        M_AXI_AWREADY,

    output reg [31:0] M_AXI_WDATA,
    output reg [3:0]  M_AXI_WSTRB,
    output reg        M_AXI_WLAST,
    output reg        M_AXI_WVALID,
    input wire        M_AXI_WREADY,

    input wire [1:0]  M_AXI_BRESP,
    input wire        M_AXI_BVALID,
    output reg        M_AXI_BREADY,

    output reg [31:0] M_AXI_ARADDR,
    output reg [3:0]  M_AXI_ARLEN,
    output reg [2:0]  M_AXI_ARSIZE,
    output wire [1:0] M_AXI_ARBURST,
    output reg        M_AXI_ARVALID,
    input wire        M_AXI_ARREADY,

    input wire [31:0] M_AXI_RDATA,
    input wire [1:0]  M_AXI_RRESP,
    input wire        M_AXI_RLAST,
    input wire        M_AXI_RVALID,
    output reg        M_AXI_RREADY
);

    assign M_AXI_AWBURST = 2'b01; 
    assign M_AXI_ARBURST = 2'b01; 
    assign PREADY = 1'b1;         

    // APB Registers
    reg [31:0] r_src, r_dst, r_len;
    reg [1:0]  r_size; 
    reg        r_start, r_stop_req, r_busy, r_done, r_err;

    // Combinational APB Read
    assign PRDATA = (PADDR[7:0] == 8'h00) ? r_src :
                    (PADDR[7:0] == 8'h04) ? r_dst :
                    (PADDR[7:0] == 8'h08) ? r_len :
                    (PADDR[7:0] == 8'h0C) ? {28'd0, r_size, 1'b0, 1'b0} :
                    (PADDR[7:0] == 8'h10) ? {29'd0, r_err, r_done, r_busy} : 32'd0;

    reg [31:0] buffer [0:15];
    reg [3:0]  buf_ptr_in, buf_ptr_out;

    localparam IDLE = 3'd0, READ_ADDR = 3'd1, READ_DATA = 3'd2,
               WRITE_ADDR = 3'd3, WRITE_DATA = 3'd4, WRITE_RESP = 3'd5, UPDATE = 3'd6;
    reg [2:0] state;
    
    reg [31:0] beats_left;
    reg [3:0]  curr_burst_len;
    reg [31:0] curr_src, curr_dst;
    reg [3:0]  byte_inc;
    reg [3:0]  curr_wstrb_base;
    
    // Lane steering shifts
    wire [1:0] shift_in  = (curr_src[1:0] + (buf_ptr_in * byte_inc)) % 4;
    wire [1:0] shift_out = (curr_dst[1:0] + (buf_ptr_out * byte_inc)) % 4;

    // APB Write Process
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            r_src <= 0; r_dst <= 0; r_len <= 0;
            r_size <= 2'b10; r_start <= 0; r_stop_req <= 0;
        end else begin
            r_start <= 0; // autoclear
            
            // Clear latched STOP if the dma fsm handles it and returns to idle
            if (state == IDLE && !r_busy) r_stop_req <= 0;

            if (PSEL && PENABLE && PWRITE) begin
                case (PADDR[7:0])
                    8'h00: r_src <= PWDATA;
                    8'h04: r_dst <= PWDATA;
                    8'h08: r_len <= PWDATA;
                    8'h0C: begin
                        r_start <= PWDATA[0];
                        if (PWDATA[1]) r_stop_req <= 1; // Latch stop
                        r_size  <= PWDATA[3:2];
                    end
                endcase
            end
        end
    end

    // DMA FSM Process
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            state <= IDLE;
            r_busy <= 0; r_done <= 0; r_err <= 0;
            M_AXI_ARVALID <= 0; M_AXI_AWVALID <= 0; M_AXI_WVALID <= 0;
            M_AXI_RREADY <= 0; M_AXI_BREADY <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (r_start && r_len > 0) begin
                        curr_src <= r_src;
                        curr_dst <= r_dst;
                        beats_left <= r_len;
                        r_busy <= 1;
                        r_done <= 0;
                        r_err <= 0;
                        
                        byte_inc <= (r_size == 2'b00) ? 1 : (r_size == 2'b01) ? 2 : 4;
                        M_AXI_ARSIZE <= {1'b0, r_size}; 
                        M_AXI_AWSIZE <= {1'b0, r_size};
                        
                        curr_wstrb_base <= (r_size == 2'b00) ? 4'b0001 : (r_size == 2'b01) ? 4'b0011 : 4'b1111;
                        state <= READ_ADDR;
                    end
                end
                
                READ_ADDR: begin
                    curr_burst_len <= (beats_left > 16) ? 15 : (beats_left - 1);
                    buf_ptr_in <= 0;
                    buf_ptr_out <= 0;
                    
                    if (!M_AXI_ARVALID) begin
                        M_AXI_ARADDR <= curr_src;
                        M_AXI_ARLEN <= (beats_left > 16) ? 15 : (beats_left - 1);
                        M_AXI_ARVALID <= 1;
                    end else if (M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 0;
                        M_AXI_RREADY <= 1;
                        state <= READ_DATA;
                    end
                end
                
                READ_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        // Align incoming data to lowest byte of buffer based on source address lane
                        buffer[buf_ptr_in] <= M_AXI_RDATA >> (shift_in * 8);
                        buf_ptr_in <= buf_ptr_in + 1;
                        if (M_AXI_RRESP != 2'b00) r_err <= 1;
                        
                        if (M_AXI_RLAST) begin
                            M_AXI_RREADY <= 0;
                            state <= WRITE_ADDR;
                        end
                    end
                end
                
                WRITE_ADDR: begin
                    if (!M_AXI_AWVALID) begin
                        M_AXI_AWADDR <= curr_dst;
                        M_AXI_AWLEN <= curr_burst_len;
                        M_AXI_AWVALID <= 1;
                    end else if (M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 0;
                        state <= WRITE_DATA;
                    end
                end
                
                WRITE_DATA: begin
                    if (!M_AXI_WVALID) begin
                        M_AXI_WVALID <= 1;
                        // Shift data and strobe to the correct byte lane based on dest address
                        M_AXI_WDATA <= buffer[buf_ptr_out] << (shift_out * 8);
                        M_AXI_WSTRB <= curr_wstrb_base << shift_out;
                        M_AXI_WLAST <= (buf_ptr_out == curr_burst_len);
                    end else if (M_AXI_WREADY) begin
                        if (M_AXI_WLAST) begin
                            M_AXI_WVALID <= 0;
                            M_AXI_WLAST <= 0;
                            M_AXI_BREADY <= 1;
                            state <= WRITE_RESP;
                        end else begin
                            buf_ptr_out <= buf_ptr_out + 1;
                            M_AXI_WVALID <= 0; // Force combinational update of WDATA/WSTRB next cycle
                        end
                    end
                end
                
                WRITE_RESP: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        M_AXI_BREADY <= 0;
                        if (M_AXI_BRESP != 2'b00) r_err <= 1;
                        state <= UPDATE;
                    end
                end
                
                UPDATE: begin
                    if (r_stop_req) begin
                        r_done <= 1;
                        r_busy <= 0;
                        state <= IDLE;
                    end else begin
                        beats_left <= beats_left - (curr_burst_len + 1);
                        curr_src <= curr_src + ((curr_burst_len + 1) * byte_inc);
                        curr_dst <= curr_dst + ((curr_burst_len + 1) * byte_inc);
                        
                        if (beats_left - (curr_burst_len + 1) == 0) begin
                            r_done <= 1;
                            r_busy <= 0;
                            state <= IDLE;
                        end else begin
                            state <= READ_ADDR;
                        end
                    end
                end
            endcase
        end
    end
endmodule
