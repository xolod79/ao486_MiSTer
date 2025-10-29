module gus    // ULTRASND IO = 240, IRQ = 7, DMA = 7
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

	input  [27:0] clock_rate,

	output        dma_req,
	input         dma_ack,
	input         dma_tc,
	input  [15:0] dma_readdata,
	output [15:0] dma_writedata,

	output        irq,

	output [15:0] audio_l,
	output [15:0] audio_r,

	input         pll_locked,
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE

);

	reg [16:0] gf1_clk;

	wire gf1_clk2 = gf1_clk[16];

	always @(posedge clk)
	begin
		if (clock_rate == 100_000_000)
					gf1_clk <= gf1_clk + 12948;   // = (9_878_400 * 2 *65536) / 100_000_000
		else if (clock_rate == 56_250_000)
					gf1_clk <= gf1_clk + 23018;   // = (9_878_400 * 2 *65536) / 56_250_000
		else if (clock_rate == 30_000_000)
					gf1_clk <= gf1_clk + 43159;   // = (9_878_400 * 2 *65536) / 30_000_000
		else if (clock_rate == 15_000_000)
					gf1_clk <= gf1_clk + 86319;   // = (9_878_400 * 2 *65536) / 15_000_000  !!! Not correct !!
		else
					gf1_clk <= gf1_clk + 14386;   // = (9_878_400 * 2 *65536) / 90_000_000
	end

	wire [19:0] dram_addr;
	wire [15:0] DRAM_o;
	wire [15:0] DRAM_i;
	wire word;
	wire dram_access;
	wire dram_we;
	wire dram_refresh;

sdram sdram (
	.init             (~pll_locked),
	.clk              (clk),
	.addr             (dram_addr),
	.dout             (DRAM_i),
	.din              (DRAM_o),
	.we               (dram_access &  dram_we),
	.rd               (dram_access & ~dram_we),
	.word             (word),
//	.ready            (),

	.SDRAM_DQ         (SDRAM_DQ),
	.SDRAM_A          (SDRAM_A),
	.SDRAM_DQML       (SDRAM_DQML),
	.SDRAM_DQMH       (SDRAM_DQMH),
	.SDRAM_BA         (SDRAM_BA),
	.SDRAM_nCS        (SDRAM_nCS),
	.SDRAM_nWE        (SDRAM_nWE),
	.SDRAM_nRAS       (SDRAM_nRAS),
	.SDRAM_nCAS       (SDRAM_nCAS),
	.SDRAM_CLK        (SDRAM_CLK),
	.SDRAM_CKE        (SDRAM_CKE)
);

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

	wire dreq;

	wire irq1;
	wire irq2;

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

/*	wire [15:0] gusbase = 16'h240;
	wire isgf1addr = (io_address[15:4] == gusbase[15:4]
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
		| io_address[3:0] == 4'h5 | io_address[3:0] == 4'h7)); */
	wire ismixeraddr = gus_cs & ~io_address8 & (io_address[3:0] == 4'h0);
//	wire isdmairqaddr = gus_cs & ~io_address8 & (io_address[3:0] == 4'hb);

	reg dmairq_regsel;
	reg dmairq_enable;
	assign dma_req = dmairq_enable & dreq;
	assign irq = dmairq_enable & (irq1 | irq2);

//	reg [3:0] irqsel;
//	reg [3:0] dmasel;

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
		.DRQ1          (dreq),
		.DACK1         (dma_ack),
		.IRQ1          (irq1),
		.IRQ2          (irq2),
		.RESET         (reset),
		.DMA_TC        (dma_tc),
		.dram_access   (dram_access),
		.dram_word     (word),
		.dram_addr     (dram_addr),
		.DRAM_DATA_i   (DRAM_i),
		.DRAM_DATA_o   (DRAM_o),
		.dram_we       (dram_we),
		.dram_refresh  (dram_refresh),
		.DAC_CLK       (dac_clk),
		.DAC_DATA      (dac_data),
		.DAC_LR        (dac_lr),
		.WAIT          (gf1_wait)
		);

	always @(posedge clk)
	begin
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

		if (ismixeraddr & write) begin
			dmairq_regsel <= writedata[6];
			dmairq_enable <= writedata[3];
		end

	end

endmodule
