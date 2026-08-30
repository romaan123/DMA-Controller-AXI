
`timescale 1ns/1ps

module top_system (
    input wire ACLK,
    input wire ARESETN,
    input wire        PSEL,
    input wire        PENABLE,
    input wire        PWRITE,
    input wire [31:0] PADDR,
    input wire [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire        PREADY
);

    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [3:0]  awlen, wstrb, arlen;
    wire [2:0]  awsize, arsize;
    wire [1:0]  awburst, arburst, bresp, rresp;
    wire        awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rlast, rvalid, rready;

    dma_controller dma_master (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA), .PREADY(PREADY),
        .M_AXI_AWADDR(awaddr), .M_AXI_AWLEN(awlen), .M_AXI_AWSIZE(awsize),
        .M_AXI_AWBURST(awburst), .M_AXI_AWVALID(awvalid), .M_AXI_AWREADY(awready),
        .M_AXI_WDATA(wdata), .M_AXI_WSTRB(wstrb), .M_AXI_WLAST(wlast),
        .M_AXI_WVALID(wvalid), .M_AXI_WREADY(wready),
        .M_AXI_BRESP(bresp), .M_AXI_BVALID(bvalid), .M_AXI_BREADY(bready),
        .M_AXI_ARADDR(araddr), .M_AXI_ARLEN(arlen), .M_AXI_ARSIZE(arsize),
        .M_AXI_ARBURST(arburst), .M_AXI_ARVALID(arvalid), .M_AXI_ARREADY(arready),
        .M_AXI_RDATA(rdata), .M_AXI_RRESP(rresp), .M_AXI_RLAST(rlast),
        .M_AXI_RVALID(rvalid), .M_AXI_RREADY(rready)
    );

    axi_full_slave memory_slave (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWLEN(awlen), .S_AXI_AWSIZE(awsize),
        .S_AXI_AWBURST(awburst), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WLAST(wlast),
        .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARLEN(arlen), .S_AXI_ARSIZE(arsize),
        .S_AXI_ARBURST(arburst), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RLAST(rlast),
        .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready)
    );
endmodule
