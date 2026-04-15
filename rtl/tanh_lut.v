module tanh_lut #( // Parametros para leitura dos valores no formato Q4.12, 16 bits totais onde 12 representam valor fracionário
    parameter integer DATA_W = 16,
    parameter integer Q_FRAC = 12
)(
    input  wire signed [DATA_W-1:0] x_in,
    output reg  signed [DATA_W-1:0] y_out
);

    // Breakpoints em Q4.12
    localparam signed [15:0] X0 = 16'sd0;      // 0.0
    localparam signed [15:0] X1 = 16'sd2048;   // 0.5
    localparam signed [15:0] X2 = 16'sd4096;   // 1.0
    localparam signed [15:0] X3 = 16'sd6144;   // 1.5
    localparam signed [15:0] X4 = 16'sd8192;   // 2.0
    localparam signed [15:0] X5 = 16'sd12288;  // 3.0

    // Valores de referência em Q4.12
    localparam signed [15:0] Y0 = 16'sd0;      // tanh(0.0) = 0.000
    localparam signed [15:0] Y1 = 16'sd1893;   // tanh(0.5) ≈ 0.462
    localparam signed [15:0] Y2 = 16'sd3122;   // tanh(1.0) ≈ 0.762
    localparam signed [15:0] Y3 = 16'sd3708;   // tanh(1.5) ≈ 0.905
    localparam signed [15:0] Y4 = 16'sd3949;   // tanh(2.0) ≈ 0.964

    // Inclinações (Slopes) em Q4.12
    localparam signed [15:0] S01 = 16'sd3786;  // [0.0, 0.5]
    localparam signed [15:0] S12 = 16'sd2460;  // [0.5, 1.0]
    localparam signed [15:0] S23 = 16'sd1172;  // [1.0, 1.5]
    localparam signed [15:0] S34 = 16'sd483;   // [1.5, 2.0]
    localparam signed [15:0] S45 = 16'sd128;   // [2.0, 3.0]

    // Saturação
    localparam signed [15:0] SAT_POS = 16'sd4095;   // +0.9998
    localparam signed [15:0] SAT_NEG = -16'sd4095;  // -0.9998

    // Variáveis internas
    reg         sign_neg; 			// Sinal d número
    reg [16:0]  x_abs_u;       	// unsigned 17 bits para suportar abs(-32768)=32768
    reg [15:0]  x0_seg_u;        // Início do segmento
    reg signed [15:0] y0_seg;		// Valor base
    reg signed [15:0] slope_seg;	// Inclinação

    reg signed [31:0] delta_x32;
    reg signed [31:0] interp_full;
    reg signed [15:0] y_abs;

    always @(*) begin
        sign_neg = x_in[DATA_W-1];

        // Valor absoluto robusto
        if (sign_neg)
            x_abs_u = {1'b0, (~x_in + 16'd1)};
        else
            x_abs_u = {1'b0, x_in};

        // defaults
        x0_seg_u  = X0[15:0];
        y0_seg    = Y0;
        slope_seg = S01;
        delta_x32 = 32'sd0;
        interp_full = 32'sd0;
        y_abs     = 16'sd0;

        // Saturação por magnitude
        if (x_abs_u >= {1'b0, X5[15:0]}) begin
            y_abs = SAT_POS;
        end else begin
            if (x_abs_u < {1'b0, X1[15:0]}) begin
                x0_seg_u  = X0[15:0];
                y0_seg    = Y0;
                slope_seg = S01;
            end else if (x_abs_u < {1'b0, X2[15:0]}) begin
                x0_seg_u  = X1[15:0];
                y0_seg    = Y1;
                slope_seg = S12;
            end else if (x_abs_u < {1'b0, X3[15:0]}) begin
                x0_seg_u  = X2[15:0];
                y0_seg    = Y2;
                slope_seg = S23;
            end else if (x_abs_u < {1'b0, X4[15:0]}) begin
                x0_seg_u  = X3[15:0];
                y0_seg    = Y3;
                slope_seg = S34;
            end else begin
                x0_seg_u  = X4[15:0];
                y0_seg    = Y4;
                slope_seg = S45;
            end
				
				// Interpolação linear
            delta_x32   = $signed({15'd0, x_abs_u}) - $signed({16'd0, x0_seg_u});
            interp_full = (delta_x32 * $signed(slope_seg)) >>> Q_FRAC;
            y_abs       = y0_seg + interp_full[15:0];
				
				// Clamping extra
            if (y_abs > SAT_POS)
                y_abs = SAT_POS;
            else if (y_abs < 16'sd0)
                y_abs = 16'sd0;
        end
		  
		  // Restaura o sinal
        if (sign_neg)
            y_out = -y_abs;
        else
            y_out = y_abs;
			
		  // Saturação final
        if (y_out > SAT_POS)
            y_out = SAT_POS;
        else if (y_out < SAT_NEG)
            y_out = SAT_NEG;
    end

endmodule