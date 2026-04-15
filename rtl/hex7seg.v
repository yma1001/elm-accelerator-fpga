module hex7seg_char (
	input wire [5:0] char_code,
	output reg [6:0] hex
);

	// Os mesmos códigos de caractere usados no top_level, usados para comparação
   localparam [3:0] CH_BLANK = 4'd0; // Display apagado
   localparam [3:0] CH_A     = 4'd1;
   localparam [3:0] CH_b     = 4'd2;
   localparam [3:0] CH_d     = 4'd3;
	localparam [3:0] CH_E     = 4'd4;
   localparam [3:0] CH_n     = 4'd5;
   localparam [3:0] CH_O     = 4'd6;
   localparam [3:0] CH_r     = 4'd7;
   localparam [3:0] CH_S     = 4'd8;
   localparam [3:0] CH_t     = 4'd9;
   localparam [3:0] CH_U     = 4'd10;
   localparam [3:0] CH_Y     = 4'd11;
	
	// Compara o código recebido com os parametros definidos acima para exibir o caractere desejado no display
	always @(*) begin
		case (char_code)
			CH_BLANK: hex = 7'b1111111;
			CH_A : hex = 7'b0001000;
			CH_b : hex = 7'b0000011;
			CH_d : hex = 7'b0100001;
			CH_E : hex = 7'b0000110;
			CH_n : hex = 7'b0101011;
			CH_O : hex = 7'b1000000;
			CH_r : hex = 7'b0101111;
			CH_S : hex = 7'b0010010; 
			CH_t : hex = 7'b0000111;
			CH_U : hex = 7'b1000001;
			CH_Y : hex = 7'b0010001;
			default : hex = 7'b1111111;
		endcase
	end
endmodule