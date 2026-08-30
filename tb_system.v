
`timescale 1ns/1ps

module tb_system;
    reg ACLK, ARESETN;
    reg PSEL, PENABLE, PWRITE;
    reg [31:0] PADDR, PWDATA;
    wire [31:0] PRDATA;
    wire PREADY;

    top_system sys (.ACLK(ACLK), .ARESETN(ARESETN),
                    .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
                    .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA), .PREADY(PREADY));

    initial begin ACLK = 0; forever #5 ACLK = ~ACLK; end

    task apb_write(input [31:0] a, input [31:0] d);
    begin
        @(posedge ACLK); PSEL=1; PADDR=a; PWDATA=d; PWRITE=1; PENABLE=0;
        @(posedge ACLK); PENABLE=1;
        @(posedge ACLK); PSEL=0; PENABLE=0;
    end
    endtask

    task apb_read(input [31:0] a, output [31:0] d);
    begin
        @(posedge ACLK); PSEL=1; PADDR=a; PWRITE=0; PENABLE=0;
        @(posedge ACLK); PENABLE=1; #1; d=PRDATA;
        @(posedge ACLK); PSEL=0; PENABLE=0;
    end
    endtask

    integer i;
    reg [31:0] status;

    initial begin
        ARESETN = 0; PSEL = 0; PENABLE = 0;
        #20 ARESETN = 1;

        // Initialize source memory
        for(i = 0; i < 256; i = i + 1) sys.memory_slave.mem[i] = i;

        // ---------------------------------------------------------
        $display("--- Test 1: 32-bit Transfer, 18 beats ---");
        apb_write(32'h00, 32'h0);       // SRC = 0x00
        apb_write(32'h04, 32'h80);      // DST = 0x80 (128)
        apb_write(32'h08, 32'd18);      // LEN = 18 beats
        apb_write(32'h0C, 32'h09);      // Start=1, Size=10 (32-bit)

        status = 0;
        while (status[1] == 0) apb_read(32'h10, status);
        $display("Test 1 Complete. Errors: %b", status[2]);
        
        for(i = 0; i < 72; i = i + 1) begin
            if (sys.memory_slave.mem[128+i] !== i)
                $display("FAIL T1 @ %0d. Exp %0d, Got %0d", i, i, sys.memory_slave.mem[128+i]);
        end
        #50;

        // ---------------------------------------------------------
        $display("--- Test 2: 8-bit Transfer, 4 beats, unaligned DST ---");
        apb_write(32'h00, 32'h00);      // SRC = 0x00
        apb_write(32'h04, 32'h41);      // DST = 0x41 (65)
        apb_write(32'h08, 32'd4);       // LEN = 4 beats
        apb_write(32'h0C, 32'h01);      // Start=1, Size=00 (8-bit)

        status = 0;
        while (status[1] == 0) apb_read(32'h10, status);
        $display("Test 2 Complete. Errors: %b", status[2]);

        for(i = 0; i < 4; i = i + 1) begin
            if (sys.memory_slave.mem[65+i] !== i)
                $display("FAIL T2 @ %0d. Exp %0d, Got %0d", i, i, sys.memory_slave.mem[65+i]);
        end
        #50;
        
        // ---------------------------------------------------------
        $display("--- Test 3: SLVERR (Out of Bounds) ---");
        apb_write(32'h00, 32'd4090);    // SRC close to 4096 memory end
        apb_write(32'h04, 32'h00);      
        apb_write(32'h08, 32'd4);       // 4 beats (32-bit) -> 16 bytes. 4090 + 16 = 4106 > 4096!
        apb_write(32'h0C, 32'h09);      // Start=1, Size=10 (32-bit)

        status = 0;
        while (status[1] == 0) apb_read(32'h10, status);
        $display("Test 3 Complete. Errors: %b", status[2]);
        if (status[2] !== 1'b1) $display("FAIL T3: Expected SLVERR.");
        else $display("PASS T3: SLVERR correctly caught.");

        $display("Tests Finished.");
        $finish;
    end
endmodule
