module gus    // ULTRASND IO = 240, IRQ = 11, DMA = 7
(
	input         clk, // LPC Clock
	input         reset,
	input         io_address8,
	input   [3:0] io_address,
	input   [7:0] writedata,
	output  [7:0] readdata,
	input         gus_cs,
	input         write,
	input         read,
	output        io_wait,

	output        dma_req,
	input         dma_ack,
	input         dma_tc,
	input  [15:0] dma_readdata,
	output [15:0] dma_writedata,

	output        irq_11,

	output [15:0] audio_l,
	output [15:0] audio_r
);

	reg [16:0] gf1_clk;

	wire gf1_clk2 = gf1_clk[16];

	always @(posedge clk)
	begin
		gf1_clk <= gf1_clk + 14386;   // = (9878400 * 2 *65536) / 90000000
	end

	reg [8:0] DADDR_l1;
	reg [10:0] DADDR_l2;

	wire [8:0] DADDR;
	wire [7:0] DRAM_o;
	wire [63:0] DRAM_o2 = { DRAM_o, DRAM_o, DRAM_o, DRAM_o, DRAM_o, DRAM_o, DRAM_o, DRAM_o };
	wire [63:0] DRAM_i2;
	reg [7:0] DRAM_i;
	reg [7:0] DRAM_i_l;
	reg [7:0] byteena;
	reg DWE;
	wire DRAM_WE;

	reg IOW;
	reg IOR;
	reg IO16;
	reg DACK1;

	wire RAS;
	wire CAS0;
	wire CAS1;
	wire CAS2;
	wire CAS3;

	always @(*)
	begin
		case(DADDR_l1[2:0])
			3'h0: DRAM_i <= DRAM_i2[7:0];
			3'h1: DRAM_i <= DRAM_i2[15:8];
			3'h2: DRAM_i <= DRAM_i2[23:16];
			3'h3: DRAM_i <= DRAM_i2[31:24];
			3'h4: DRAM_i <= DRAM_i2[39:32];
			3'h5: DRAM_i <= DRAM_i2[47:40];
			3'h6: DRAM_i <= DRAM_i2[55:48];
			3'h7: DRAM_i <= DRAM_i2[63:56];
		endcase
		case(DADDR_l1[2:0])
			3'h0: byteena <= 8'b00000001;
			3'h1: byteena <= 8'b00000010;
			3'h2: byteena <= 8'b00000100;
			3'h3: byteena <= 8'b00001000;
			3'h4: byteena <= 8'b00010000;
			3'h5: byteena <= 8'b00100000;
			3'h6: byteena <= 8'b01000000;
			3'h7: byteena <= 8'b10000000;
		endcase
	end

	wire CASA0 = CAS0 & RAS;
	wire CASA1 = CAS1 & RAS;
	wire CASA2 = CAS2 & RAS;
	wire CASA3 = CAS3 & RAS;

	bram ram
		(
		.address({DADDR_l2, DADDR_l1[8:3]}),
		.clock(clk),
		.data(DRAM_o2),
		.wren(DWE),
		.byteena(byteena),
		.q(DRAM_i2)
		);

	reg o_RAS;
	reg o_CAS0;
	reg o_CAS1;
	reg o_CAS2;
	reg o_CAS3;

	reg [15:0] dac_shifter;
	reg [15:0] dac_left;
	reg [15:0] dac_right;
	reg o_dac_clk;
	wire dac_clk;
	wire dac_data;
	wire dac_lr;
	reg o_dac_lr;

	assign audio_l = dac_left;
	assign audio_r = dac_right;

	reg [7:0] lpc_cnt;
	reg lpc_state;
	reg [3:0] lpc_out;
	reg io_write;
	reg io_read;
	reg io_dmawrite;
	reg io_dmaread;
//	reg [7:0] dma_req;
	wire DREQ;
	reg o_DREQ;

	reg irq_sleep;
	reg [7:0] irq_state;
	wire IRQ1;
	wire IRQ2;
	assign irq_11 = IRQ1 | IRQ2;
	reg o_IRQ;

//	wire [15:0] gusbase = 16'h240;

//	reg [15:0] io_address;

	wire gf1_wait;
	reg [1:0] read_wait;
	reg [1:0] write_wait;
	reg       read_d;
	reg       write_d;
	wire      gf1_read  = read  & gus_cs;
	wire      gf1_write = write & gus_cs;
	wire      read_cont =  (~read_d  & gf1_read)  | (|read_wait);
	wire      write_cont = (~write_d & gf1_write) | (|write_wait);
	assign    io_wait = gf1_wait | read_cont | write_cont;

/*	wire isgf1addr = (io_address[15:4] == gusbase[15:4]
		& (io_address[3:0] == 4'h6 | io_address[3:0] == 4'h8 | io_address[3:0] == 4'h9
		| io_address[3:0] == 4'ha | io_address[3:0] == 4'hc | io_address[3:0] == 4'he)) |
		(io_address[15:4] == (gusbase[15:4] | 16'h10)
		& (io_address[3:0] == 4'h2 | io_address[3:0] == 4'h3 | io_address[3:0] == 4'h4
		| io_address[3:0] == 4'h5 | io_address[3:0] == 4'h7));
	wire ismixeraddr = io_address == gusbase;
	wire isdmairqaddr = io_address == (gusbase | 16'hb); */

/*	wire isgf1addr = gus_cs & (~io_address8    // 240
		& (io_address[3:0] == 4'h6 | io_address[3:0] == 4'h8 | io_address[3:0] == 4'h9
		| io_address[3:0] == 4'ha | io_address[3:0] == 4'hc | io_address[3:0] == 4'he)) |
		(io_address8                  // 340
		& (io_address[3:0] == 4'h2 | io_address[3:0] == 4'h3 | io_address[3:0] == 4'h4
		| io_address[3:0] == 4'h5 | io_address[3:0] == 4'h7));
	wire ismixeraddr = gus_cs & ~io_address8 & (io_address[3:0] == 4'h0);
	wire isdmairqaddr = gus_cs & ~io_address8 & (io_address[3:0] == 4'hb); */

//	reg dmairq_enable;
//	wire DREQ2 = dmairq_enable & DREQ;
//	wire IRQE = dmairq_enable & IRQ;

//	reg [3:0] irqsel;
//	reg [3:0] dmasel;

//	wire goodaddr = isgf1addr | ismixeraddr | isdmairqaddr;
	
	gf1 gf1(
		.MCLK          (clk),
		.CLK           (gf1_clk2),
		.IOW           (write_cont),
		.IOR           (read_cont),
		.ADDRESS       (io_address[3:0]),
		.DATA_i        ({8'd0, writedata}),
		.DATA_o        (readdata),
		.dma_writedata (dma_writedata),
		.dma_readdata  (dma_readdata),
		.IO16          (0),
		.CS1           (gus_cs),
		.CS2           (0),
		.DRQ1          (dma_req),
		.DACK1         (dma_ack),
		.DACK2         (0),
		.IRQ1          (IRQ1),
		.IRQ2          (IRQ2),
		.RESET         (reset),
		.DMA_TC        (dma_tc),
		.DRAM_CAS0     (CAS0),
		.DRAM_CAS1     (CAS1),
		.DRAM_CAS2     (CAS2),
		.DRAM_CAS3     (CAS3),
		.DRAM_RAS      (RAS),
		.DRAM_ADDR     (DADDR),
		.DRAM_DATA_i   (DRAM_i),
		.DRAM_DATA_o   (DRAM_o),
		.DRAM_WE       (DRAM_WE),
		.DAC_CLK       (dac_clk),
		.DAC_DATA      (dac_data),
		.DAC_LR        (dac_lr),
		.WAIT          (gf1_wait)
		);

	always @(posedge clk)
	begin
		// dram
		if (RAS & ~o_RAS)
		begin
			DADDR_l2[8:0] <= DADDR;
		end
		if ((CASA0 & ~o_CAS0) | (CASA1 & ~o_CAS1)/* | (CASA2 & ~o_CAS2) | (CASA3 & ~o_CAS3)*/)
		begin
			if (o_RAS)
			begin
				DADDR_l1 <= DADDR;
				DADDR_l2[10:9] <= { CASA2 | CASA3, CASA1 | CASA3 };
				DWE <= DRAM_WE;
			end
		end
		if ((~CASA0 & o_CAS0) | (~CASA1 & o_CAS1))
		begin
			DWE <= 0;
		end

		o_CAS0 <= CASA0;
		o_CAS1 <= CASA1;
		o_CAS2 <= CASA2;
		o_CAS3 <= CASA3;
		o_RAS <= RAS;

		// dac

		if (dac_clk & ~o_dac_clk)
		begin
			dac_shifter <= { dac_shifter[14:0], dac_data };
			if (o_dac_lr & ~dac_lr)
				dac_left <= dac_shifter;
			else if (~o_dac_lr & dac_lr)
				dac_right <= dac_shifter;
			
			o_dac_lr <= dac_lr;
		end

		o_dac_clk <= dac_clk;

		read_d <= gf1_read;
		write_d <= gf1_write;
		read_wait  <= { read_wait[0],  (~read_d & gf1_read)   ? 1'b1 : 1'b0 };
		write_wait <= { write_wait[0], (~write_d & gf1_write) ? 1'b1 : 1'b0 };

	end

endmodule
