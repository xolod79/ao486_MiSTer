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
		gf1_clk <= gf1_clk + 14386;   // = (9878400 * 2 *65536) / 90000000
	end

	reg [8:0] DADDR_l1;
	reg [10:0] DADDR_l2;

	wire [8:0] DADDR;
	wire [7:0] DRAM_o;
	wire [7:0] DRAM_i;
	reg  dwe;
	reg  dram_access;
	wire dram_we;
	wire dram_refresh;

	wire ras;
	wire cas0;
	wire cas1;
	wire cas2;
	wire cas3;

	wire casa0 = cas0 & ras;
	wire casa1 = cas1 & ras;
	wire casa2 = cas2 & ras;
	wire casa3 = cas3 & ras;

sdram sdram (
	.init             (~pll_locked),
	.clk              (clk),
	.addr             ({DADDR_l2, DADDR_l1}),
	.dout             (DRAM_i),
	.din              (DRAM_o),
	.we               (dram_access &  dwe),
	.rd               (dram_access & ~dwe),
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

	reg o_ras;
	reg o_cas0;
	reg o_cas1;
	reg o_cas2;
	reg o_cas3;

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
		.CS2           (0),
		.DRQ1          (dreq),
		.DACK1         (dma_ack),
		.DACK2         (0),
		.IRQ1          (irq1),
		.IRQ2          (irq2),
		.RESET         (reset),
		.DMA_TC        (dma_tc),
		.DRAM_CAS0     (cas0),
		.DRAM_CAS1     (cas1),
		.DRAM_CAS2     (cas2),
		.DRAM_CAS3     (cas3),
		.dram_ras      (ras),
		.DRAM_ADDR     (DADDR),
		.DRAM_DATA_i   (DRAM_i),
		.DRAM_DATA_o   (DRAM_o),
		.DRAM_WE       (dram_we),
		.dram_refresh  (dram_refresh),
		.DAC_CLK       (dac_clk),
		.DAC_DATA      (dac_data),
		.DAC_LR        (dac_lr),
		.WAIT          (gf1_wait)
		);

	always @(posedge clk)
	begin
		// dram
		if (ras & ~o_ras)
		begin
			DADDR_l2[8:0] <= DADDR;
		end
		if ((casa0 & ~o_cas0) | (casa1 & ~o_cas1) | (casa2 & ~o_cas2) | (casa3 & ~o_cas3))
		begin
			if (o_ras)
			begin
				DADDR_l1 <= DADDR;
				DADDR_l2[10:9] <= { casa2 | casa3, casa1 | casa3 };
				dwe <= dram_we;
				dram_access <= 1;
			end
		end
		if ((~casa0 & o_cas0) | (~casa1 & o_cas1) | (~casa2 & o_cas2) | (~casa3 & o_cas3))
		begin
			dwe <= 0;
			dram_access <= 0;
		end

		o_cas0 <= casa0;
		o_cas1 <= casa1;
		o_cas2 <= casa2;
		o_cas3 <= casa3;
		o_ras <= ras;

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
