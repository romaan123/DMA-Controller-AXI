`timescale 1ns/1ps

module axi_full_slave #(
    parameter MEM_BYTES = 4096 
)(
    input wire ACLK,
    input wire ARESETN,

    // Write Channel
    input wire [31:0] S_AXI_AWADDR,
    input wire [3:0]  S_AXI_AWLEN,
    input wire [2:0]  S_AXI_AWSIZE,
    input wire [1:0]  S_AXI_AWBURST,
    input wire        S_AXI_AWVALID,
    output reg        S_AXI_AWREADY,

    input wire [31:0] S_AXI_WDATA,
    input wire [3:0]  S_AXI_WSTRB,
    input wire        S_AXI_WLAST,
    input wire        S_AXI_WVALID,
    output reg        S_AXI_WREADY,

    output reg [1:0]  S_AXI_BRESP,
    output reg        S_AXI_BVALID,
    input wire        S_AXI_BREADY,

    // Read Channel
    input wire [31:0] S_AXI_ARADDR,
    input wire [3:0]  S_AXI_ARLEN,
    input wire [2:0]  S_AXI_ARSIZE,
    input wire [1:0]  S_AXI_ARBURST,
    input wire        S_AXI_ARVALID,
    output reg        S_AXI_ARREADY,

    output reg [31:0] S_AXI_RDATA,
    output reg [1:0]  S_AXI_RRESP,
    output reg        S_AXI_RLAST,
    output reg        S_AXI_RVALID,
    input wire        S_AXI_RREADY
);

    reg [7:0] mem [0:MEM_BYTES-1];

    localparam IDLE = 2'b00, ACTIVE = 2'b01, RESP = 2'b10;
    reg [1:0] state_w, state_r;

    reg [31:0] awaddr, araddr;
    reg [3:0]  awlen, arlen;
    reg [2:0]  awsize, arsize;
    reg [4:0]  w_beat_cnt, r_beat_cnt;
    reg        w_err, r_err;

    wire [31:0] w_addr_al = {awaddr[31:2], 2'b00};
    wire [31:0] r_addr_al = {araddr[31:2], 2'b00};

    // ---------------- WRITE CHANNEL ----------------
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            state_w <= IDLE;
            S_AXI_AWREADY <= 0;
            S_AXI_WREADY <= 0;
            S_AXI_BVALID <= 0;
            S_AXI_BRESP <= 2'b00;
        end else begin
            case (state_w)
                IDLE: begin
                    S_AXI_AWREADY <= 1;
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        S_AXI_AWREADY <= 0;
                        awaddr <= S_AXI_AWADDR;
                        awlen  <= S_AXI_AWLEN;
                        awsize <= S_AXI_AWSIZE;
                        w_beat_cnt <= 0;
                        w_err  <= 0;
                        S_AXI_WREADY <= 1;
                        state_w <= ACTIVE;
                    end
                end

                ACTIVE: begin
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        if (awaddr + (1 << awsize) > MEM_BYTES) w_err <= 1;
                        else begin
                            if (S_AXI_WSTRB[0]) mem[w_addr_al]   <= S_AXI_WDATA[7:0];
                            if (S_AXI_WSTRB[1]) mem[w_addr_al+1] <= S_AXI_WDATA[15:8];
                            if (S_AXI_WSTRB[2]) mem[w_addr_al+2] <= S_AXI_WDATA[23:16];
                            if (S_AXI_WSTRB[3]) mem[w_addr_al+3] <= S_AXI_WDATA[31:24];
                        end

                        awaddr <= awaddr + (1 << awsize);
                        w_beat_cnt <= w_beat_cnt + 1;

                        if (S_AXI_WLAST) begin
                            S_AXI_WREADY <= 0;
                            S_AXI_BVALID <= 1;
                            if (w_err || awaddr >= MEM_BYTES || w_beat_cnt != awlen) 
                                S_AXI_BRESP <= 2'b10; // SLVERR
                            else 
                                S_AXI_BRESP <= 2'b00; // OKAY
                            state_w <= RESP;
                        end
                    end
                end

                RESP: begin
                    if (S_AXI_BREADY && S_AXI_BVALID) begin
                        S_AXI_BVALID <= 0;
                        state_w <= IDLE;
                    end
                end
            endcase
        end
    end

    // ---------------- READ CHANNEL ----------------
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            state_r <= IDLE;
            S_AXI_ARREADY <= 0;
            S_AXI_RVALID <= 0;
            S_AXI_RLAST <= 0;
        end else begin
            case (state_r)
                IDLE: begin
                    S_AXI_ARREADY <= 1;
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        S_AXI_ARREADY <= 0;
                        araddr <= S_AXI_ARADDR;
                        arlen  <= S_AXI_ARLEN;
                        arsize <= S_AXI_ARSIZE;
                        r_beat_cnt <= 0;
                        r_err  <= 0;
                        state_r <= ACTIVE;
                    end
                end

                ACTIVE: begin
                    if (!S_AXI_RVALID || S_AXI_RREADY) begin
                        S_AXI_RVALID <= 1;
                        S_AXI_RLAST <= (r_beat_cnt == arlen);
                        
                        if (araddr + (1 << arsize) > MEM_BYTES) begin
                            S_AXI_RRESP <= 2'b10; // SLVERR
                            S_AXI_RDATA <= 32'h0;
                        end else begin
                            S_AXI_RRESP <= 2'b00;
                            S_AXI_RDATA <= {mem[r_addr_al+3], mem[r_addr_al+2], mem[r_addr_al+1], mem[r_addr_al]};
                        end

                        if (S_AXI_RVALID && S_AXI_RREADY) begin
                            araddr <= araddr + (1 << arsize);
                            if (S_AXI_RLAST) begin
                                S_AXI_RVALID <= 0;
                                S_AXI_RLAST <= 0;
                                state_r <= IDLE;
                            end else begin
                                r_beat_cnt <= r_beat_cnt + 1;
                            end
                        end
                    end
                end
            endcase
        end
    end
endmodule
