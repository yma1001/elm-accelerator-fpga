module elm_accel #( // Parametros definindo o tamanho da rede e o frmato numérico
    parameter integer D       = 784,
    parameter integer H       = 128,
    parameter integer C       = 10,
    parameter integer DATA_W  = 16,
    parameter integer ACC_W   = 32,
    parameter integer Q_FRAC  = 12
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [31:0]           instr,
    input  wire                  instr_valid,

    output wire [31:0]           status,
    output reg  [3:0]            pred,

    output reg                   busy_flag,
    output reg                   done_flag,
    output reg                   error_flag,
    output reg                   img_loaded,
    output reg                   weights_loaded,
    output reg                   bias_loaded,
    output reg                   beta_loaded,
    output reg                   started_once,
    output reg  [1:0]            state_dbg
);

    wire [1:0] cmd;
    assign cmd = instr[31:30]; // Extrai o comando dos switchs para uma instrução de 32 bits
	 
	 // Define as instruções
    localparam [1:0] CMD_STORE_WEIGHTS = 2'd0;
    localparam [1:0] CMD_STORE_BIAS    = 2'd1;
    localparam [1:0] CMD_STORE_IMG     = 2'd2;
    localparam [1:0] CMD_START         = 2'd3;
	 
	 // Campos demo de STORE
    // [6:4] = endereço demo
    // [3:0] = dado demo
    wire [2:0] store_addr_demo = instr[6:4];
    wire [3:0] store_data_demo = instr[3:0];
	 
	 // Converte o pixel da imagem para Q4.12
	 wire [15:0] img_store_data = {4'b0000, store_data_demo, 8'b00000000};
	 
	 // Faz a extensão de sinal para os pesos e bias e converte para Q4.12
	 wire signed [15:0] signed_demo_ext = {{12{store_data_demo[3]}}, store_data_demo};
    wire signed [15:0] wb_store_data   = signed_demo_ext <<< 8;

	 // Formatação dos endereços, endereços pequenos → expandidos para o tamanho da RAM
    wire [9:0]  img_store_addr = {7'b0,  store_addr_demo};
    wire [6:0]  b_store_addr   = {4'b0,  store_addr_demo};
    wire [16:0] w_store_addr   = {14'b0, store_addr_demo};
	 
	 // estados da máquina
    localparam [1:0] ST_READY = 2'd0;
    localparam [1:0] ST_STORE = 2'd1;
    localparam [1:0] ST_BUSY  = 2'd2;
	 
    reg [1:0] state, next_state;
	 
	 // Pipeline interno do cálculo da ELM
    localparam [4:0] PH_H_ADDR        = 5'd0;
    localparam [4:0] PH_H_WAIT0       = 5'd1;
    localparam [4:0] PH_H_WAIT1       = 5'd2;
    localparam [4:0] PH_H_MAC         = 5'd3;
    localparam [4:0] PH_H_BIAS        = 5'd4;
    localparam [4:0] PH_H_BIAS_WAIT0  = 5'd5;
    localparam [4:0] PH_H_BIAS_WAIT1  = 5'd6;
    localparam [4:0] PH_H_TANH        = 5'd7;
    localparam [4:0] PH_H_TANH_LATCH  = 5'd8;
    localparam [4:0] PH_O_ADDR        = 5'd9;
    localparam [4:0] PH_O_WAIT0       = 5'd10;
    localparam [4:0] PH_O_WAIT1       = 5'd11;
    localparam [4:0] PH_O_MAC         = 5'd12;
    localparam [4:0] PH_ARGMAX        = 5'd13;
	 
	 // Fase atual do cálculo da ELM
    reg [4:0] phase;
	 
	 // Índeces usados para percorrer pixels, neurônios ocultos e as classes
    reg [$clog2(D)-1:0] in_idx;
    reg [$clog2(H)-1:0] hid_idx;
    reg [$clog2(C)-1:0] cls_idx;
	 
	 // Armazenam a saída da camada oculta e scores das classes
    reg signed [DATA_W-1:0] h_mem [0:H-1];
    reg signed [ACC_W-1:0]  y_mem [0:C-1];
	 
	 // Interface com memórias
    reg  [16:0] w_addr;
    wire [15:0] w_q;

    reg  [10:0] beta_addr;
    wire [15:0] beta_q;

    reg  [6:0]  b_addr;
    wire [15:0] b_q;

    reg  [9:0]  img_addr;
    wire [15:0] img_q;

    // STORE real só pode ocorrer em READY
    wire do_store_weights = (state == ST_READY) && instr_valid && (cmd == CMD_STORE_WEIGHTS);
    wire do_store_bias    = (state == ST_READY) && instr_valid && (cmd == CMD_STORE_BIAS);
    wire do_store_img     = (state == ST_READY) && instr_valid && (cmd == CMD_STORE_IMG);
	 
	 // MUX da memória, se está em store, usa endereço/dado do switch. Senão, usa datapath normal
    wire [16:0] w_addr_mux = do_store_weights ? w_store_addr   : w_addr;
    wire [15:0] w_data_mux = do_store_weights ? wb_store_data  : 16'd0;
    wire        w_wren_mux = do_store_weights;

    wire [6:0]  b_addr_mux = do_store_bias    ? b_store_addr   : b_addr;
    wire [15:0] b_data_mux = do_store_bias    ? wb_store_data  : 16'd0;
    wire        b_wren_mux = do_store_bias;

    wire [9:0]  img_addr_mux = do_store_img   ? img_store_addr : img_addr;
    wire [15:0] img_data_mux = do_store_img   ? img_store_data : 16'd0;
    wire        img_wren_mux = do_store_img;
	 
	 // Acumuladores
    reg signed [ACC_W-1:0] acc;
    reg signed [ACC_W-1:0] z_hidden;

    wire signed [ACC_W-1:0] mult_hidden_full;
    wire signed [ACC_W-1:0] mult_hidden_scaled;
    wire signed [ACC_W-1:0] mult_output_full;
    wire signed [ACC_W-1:0] mult_output_scaled;

    wire signed [DATA_W-1:0] z_sat;
    wire signed [DATA_W-1:0] tanh_out;

    wire [3:0]              pred_argmax;
    wire signed [ACC_W-1:0] max_val_unused;

	 
    wire [16:0] hid_x784;
    wire [10:0] hid_x10;

    wire missing_any_store;
	 
	 // Calcula os endereços usando shift
    assign hid_x784 = ({10'b0, hid_idx} << 9)
                    + ({10'b0, hid_idx} << 8)
                    + ({10'b0, hid_idx} << 4);

    assign hid_x10  = ({4'b0, hid_idx} << 3)
                    + ({4'b0, hid_idx} << 1);
	 
	 // Dado faltando = Erro
    assign missing_any_store = !(img_loaded && weights_loaded && bias_loaded && beta_loaded);

	 // Limita o valores para evitar Overflow
    function signed [DATA_W-1:0] sat32_to_q16;
        input signed [ACC_W-1:0] x;
        begin
            if      (x > 32'sd32767)  sat32_to_q16 =  16'sd32767;
            else if (x < -32'sd32768) sat32_to_q16 = -16'sd32768;
            else                      sat32_to_q16 = x[DATA_W-1:0];
        end
    endfunction

    assign z_sat = sat32_to_q16(z_hidden);
	 
	 // Calcula a camada oculta (imagem * peso)
    mac_q412 #(
        .DATA_W(DATA_W), .ACC_W(ACC_W), .Q_FRAC(Q_FRAC)
    ) u_mac_hidden (
        .a(img_q),
        .b(w_q),
        .product_full(mult_hidden_full),
        .product_scaled(mult_hidden_scaled)
    );
	 
	 // Calcula a camada de saída (h * beta)
    mac_q412 #(
        .DATA_W(DATA_W), .ACC_W(ACC_W), .Q_FRAC(Q_FRAC)
    ) u_mac_output (
        .a(h_mem[hid_idx]),
        .b(beta_q),
        .product_full(mult_output_full),
        .product_scaled(mult_output_scaled)
    );
	
	 // Ativação
    tanh_lut #(
        .DATA_W(DATA_W), .Q_FRAC(Q_FRAC)
    ) u_tanh_lut (
        .x_in(z_sat),
        .y_out(tanh_out)
    );
	 
	 // Argmax
    argmax10 #(.ACC_W(ACC_W)) u_argmax10 (
        .y0(y_mem[0]), .y1(y_mem[1]), .y2(y_mem[2]), .y3(y_mem[3]), .y4(y_mem[4]),
        .y5(y_mem[5]), .y6(y_mem[6]), .y7(y_mem[7]), .y8(y_mem[8]), .y9(y_mem[9]),
        .pred(pred_argmax),
        .max_val(max_val_unused)
    );
	 
	 // Memórias (Peso, beta, bias e imagem)
    ram_w_in  u_ram_w    (.address(w_addr_mux),   .clock(clk), .data(w_data_mux),   .wren(w_wren_mux),   .q(w_q));
    rom_beta  u_rom_beta (.address(beta_addr),    .clock(clk),                                .q(beta_q));
    ram_b     u_ram_b    (.address(b_addr_mux),   .clock(clk), .data(b_data_mux),   .wren(b_wren_mux),   .q(b_q));
    ram_img   u_ram_img  (.address(img_addr_mux), .clock(clk), .data(img_data_mux), .wren(img_wren_mux), .q(img_q));
	 
	 // Faz um empacotamento de operandos para o Status
    assign status = {
        20'b0,
        started_once,
        beta_loaded,
        bias_loaded,
        weights_loaded,
        img_loaded,
        pred[3:0],
        error_flag,
        done_flag,
        busy_flag
    };
	 
	 // Máquina de estados principal do circuito
    always @(*) begin
        next_state = state;

        case (state)
            ST_READY: begin
                if (instr_valid && (cmd == CMD_STORE_WEIGHTS ||
                                    cmd == CMD_STORE_BIAS    ||
                                    cmd == CMD_STORE_IMG)) begin
                    next_state = ST_STORE;
                end else if (instr_valid && cmd == CMD_START) begin
                    next_state = ST_BUSY;
                end
            end

            ST_STORE: begin
                next_state = ST_READY;
            end

            ST_BUSY: begin
                next_state = (phase == PH_ARGMAX) ? ST_READY : ST_BUSY;
            end

            default: begin
                next_state = ST_READY;
            end
        endcase
    end

	 // Faz o reset geral do sistema, manipula as transições de estado e monitora a fase do cálculo
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
				// Reinicializa o estádo
            state          <= ST_READY;
            state_dbg      <= ST_READY;
            phase          <= PH_H_ADDR;
				
				// Zera os acumuladores
            in_idx         <= 0;
            hid_idx        <= 0;
            cls_idx        <= 0;

            w_addr         <= 0;
            beta_addr      <= 0;
            b_addr         <= 0;
            img_addr       <= 0;

            acc            <= 0;
            z_hidden       <= 0;
            pred           <= 0;
				
				// Reinicializa as flags
            busy_flag      <= 1'b0;
            done_flag      <= 1'b1;
            error_flag     <= 1'b0;

            img_loaded     <= 1'b0;
            weights_loaded <= 1'b0;
            bias_loaded    <= 1'b0;
            beta_loaded    <= 1'b1;
            started_once   <= 1'b0;
	
            // Limpa a memória
				for (i = 0; i < H; i = i + 1)
                h_mem[i] <= 0;

            for (i = 0; i < C; i = i + 1)
                y_mem[i] <= 0;
        end else begin
            state     <= next_state;
            state_dbg <= next_state;

            case (state)
					 
					 // Estado pronto, esperando comando
                ST_READY: begin
                    busy_flag <= 1'b0;

                    if (!instr_valid)
                        done_flag <= 1'b1;
								
						  // Comando válido
                    if (instr_valid) begin
                        case (cmd) 
									 // "Ativa" a flag de armazenamento
                            CMD_STORE_WEIGHTS: weights_loaded <= 1'b1;
                            CMD_STORE_BIAS:    bias_loaded    <= 1'b1;
                            CMD_STORE_IMG:     img_loaded     <= 1'b1;
		
                            // Inicializa o processo de cálculo
									 CMD_START: begin
                                started_once <= 1'b1;
                                done_flag    <= 1'b0;
                                busy_flag    <= 1'b1;
                                error_flag   <= missing_any_store;
											
										  // Define a fase inicial do cálculo e zera os contadores
                                phase    <= PH_H_ADDR; 
                                in_idx   <= 0;
                                hid_idx  <= 0;
                                cls_idx  <= 0;
                                acc      <= 0;
                                z_hidden <= 0;
                                pred     <= 0;
			
                                // Limpa a memória
										  for (i = 0; i < H; i = i + 1)
                                    h_mem[i] <= 0;

                                for (i = 0; i < C; i = i + 1)
                                    y_mem[i] <= 0;
                            end

                            default: begin
                                error_flag <= 1'b1;
                            end
                        endcase
                    end
                end
					 
                ST_STORE: begin
                    busy_flag <= 1'b1;
                    done_flag <= 1'b0;
                end

                ST_BUSY: begin
                    busy_flag <= 1'b1;
                    done_flag <= 1'b0;
						  
						  // Checa a fase atual do cálculo
                    case (phase)
								// Multiplicação do pixel da imagem com o peso
                        PH_H_ADDR: begin
                            img_addr <= in_idx[9:0];
                            w_addr   <= hid_x784 + {7'b0, in_idx};
                            phase    <= PH_H_WAIT0;
                        end
								
								// Espera memória
                        PH_H_WAIT0: phase <= PH_H_WAIT1;
                        PH_H_WAIT1: phase <= PH_H_MAC;

                        // repete o processo da camada oculta até o último pixel/peso, passa pra soma do bias
								PH_H_MAC: begin
                            acc <= acc + mult_hidden_scaled;
                            if (in_idx == D-1) begin
                                in_idx <= 0;
                                phase  <= PH_H_BIAS;
                            end else begin
                                in_idx <= in_idx + 1'b1;
                                phase  <= PH_H_ADDR;
                            end
                        end

                        // Soma do bias
								PH_H_BIAS: begin
                            b_addr <= hid_idx[6:0];
                            phase  <= PH_H_BIAS_WAIT0;
                        end

                        PH_H_BIAS_WAIT0: phase <= PH_H_BIAS_WAIT1;
                        PH_H_BIAS_WAIT1: phase <= PH_H_TANH;

                        // Ativação
								PH_H_TANH: begin
                            z_hidden <= acc + {{(ACC_W-DATA_W){b_q[DATA_W-1]}}, b_q};
                            phase    <= PH_H_TANH_LATCH;
                        end

                        // Guarda o resultado na memória e passa para o próximo neurónio até ativar todos, depois vai para o cálculo da camada de saída
								PH_H_TANH_LATCH: begin
                            h_mem[hid_idx] <= tanh_out;
                            acc            <= 0;
                            z_hidden       <= 0;

                            if (hid_idx == H-1) begin
                                hid_idx <= 0;
                                cls_idx <= 0;
                                acc     <= 0;
                                phase   <= PH_O_ADDR;
                            end else begin
                                hid_idx <= hid_idx + 1'b1;
                                phase   <= PH_H_ADDR;
                            end
                        end
								
								// Ler Beta
                        PH_O_ADDR: begin
                            beta_addr <= hid_x10 + {7'b0, cls_idx};
                            phase     <= PH_O_WAIT0;
                        end
								
								// Esperar memória
                        PH_O_WAIT0: phase <= PH_O_WAIT1;
                        PH_O_WAIT1: phase <= PH_O_MAC;
								
								// Salva na memória e passa para a próxima classe até ler tudo, depois passa para o Argmax
                        PH_O_MAC: begin
                            if (hid_idx == H-1) begin
                                y_mem[cls_idx] <= acc + mult_output_scaled;
                                acc            <= 0;
                                hid_idx        <= 0;

                                if (cls_idx == C-1) begin
                                    cls_idx <= 0;
                                    phase   <= PH_ARGMAX;
                                end else begin
                                    cls_idx <= cls_idx + 1'b1;
                                    phase   <= PH_O_ADDR;
                                end
                            end else begin
                                acc     <= acc + mult_output_scaled;
                                hid_idx <= hid_idx + 1'b1;
                                phase   <= PH_O_ADDR;
                            end
                        end
								
								// Faz o Argmax
                        PH_ARGMAX: begin
                            pred      <= pred_argmax;
                            busy_flag <= 1'b0;
                            done_flag <= 1'b1;
                        end

                        default: begin
                            error_flag <= 1'b1;
                            busy_flag  <= 1'b0;
                            done_flag  <= 1'b0;
                            phase      <= PH_H_ADDR;
                        end
                    endcase
                end

                // Comando inválido = Erro
					 default: begin
                    state        <= ST_READY;
                    state_dbg    <= ST_READY;
                    error_flag   <= 1'b1;
                    busy_flag    <= 1'b0;
                    done_flag    <= 1'b1;
                end
            endcase
        end
    end

endmodule