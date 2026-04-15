module top_de1soc_semdelay (
    input  wire        CLOCK_50,
    input  wire [2:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4
);
	 
	 // Definição das operações Store/Start
    localparam [1:0] CMD_STORE_WEIGHTS = 2'd0;
    localparam [1:0] CMD_STORE_BIAS    = 2'd1;
    localparam [1:0] CMD_STORE_IMG     = 2'd2;
    localparam [1:0] CMD_START         = 2'd3;
	 
	 // Definição do status a ser exibido no display
    localparam [2:0] DISP_READY = 3'd0;
    localparam [2:0] DISP_STORE = 3'd1;
    localparam [2:0] DISP_BUSY  = 3'd2;
    localparam [2:0] DISP_DONE  = 3'd3;
    localparam [2:0] DISP_ERROR = 3'd4;
	 
	 // Definição dos caracteres usados nos displays
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
	 
	 // Sinais internos de status, resultado e flags
    wire [31:0] status;
    wire [3:0]  pred;
    wire        busy_flag;
    wire        done_flag;
    wire        error_flag;
    wire        img_loaded;
    wire        weights_loaded;
    wire        bias_loaded;
    wire        beta_loaded;
    wire        started_once;
    wire [1:0]  state_dbg;
	 
	 // Sinais visuais simplificados, usados para o status do sistema
    wire busy_vis;
    wire store_vis;
    wire ready_done_vis;
	 
    reg  [2:0] display_status_now;
    reg  [2:0] display_status_latched;
	 
	 // Displays de 7 segmentos usados para exibir o status atual para o usuário
    reg  [5:0] hex4_char;
    reg  [5:0] hex3_char;
    reg  [5:0] hex2_char;
    reg  [5:0] hex1_char;
    reg  [5:0] hex0_char;
	  
	 // registrador de instruções de 32 bits
    reg  [31:0] instr;
	 
    // Montagem da instrução
    always @(*) begin
        instr = 32'b0;
        instr[31:30] = SW[1:0];
		  instr[6:4]   = SW[5:3];
        instr[3:0]   = SW[9:6];
    end
	 
	 // Define o botão do reset
	 wire rst_n;
    assign rst_n = KEY[0];
	 
	 // Pulsos de instrução e status. Os botões passam por uma conversão para pulso, evitando multiplos triggers do bounce
    wire instr_valid_pulse;
    wire status_btn_pulse;

    // Botão de confirmação da instrução
    button_pulse u_button_cmd (
        .clk   (CLOCK_50),
        .rst_n (rst_n),
        .key_n (KEY[1]), // Botão start
        .pulse (instr_valid_pulse) // pulso de instrução
    );

    // Botão de snapshot do status
    button_pulse u_button_status (
        .clk   (CLOCK_50),
        .rst_n (rst_n),
        .key_n (KEY[2]), // Botão status
        .pulse (status_btn_pulse) // Pulso de status
    );

    // Coprocessador
    elm_accel u_elm_accel (
        .clk            (CLOCK_50),
        .rst_n          (rst_n),
        .instr          (instr),
        .instr_valid    (instr_valid_pulse),
        .status         (status),
        .pred           (pred),
        .busy_flag      (busy_flag),
        .done_flag      (done_flag),
        .error_flag     (error_flag),
        .img_loaded     (img_loaded),
        .weights_loaded (weights_loaded),
        .bias_loaded    (bias_loaded),
        .beta_loaded    (beta_loaded),
        .started_once   (started_once),
        .state_dbg      (state_dbg)
    );

    // Os sinais ajudam a simplificar a alternação do status do sistema e melhorar a legibilidade
    assign busy_vis  = busy_flag;

    assign store_vis = instr_valid_pulse &&
                      (SW[1:0] == CMD_STORE_WEIGHTS ||
                       SW[1:0] == CMD_STORE_BIAS    ||
                       SW[1:0] == CMD_STORE_IMG);

    assign ready_done_vis = done_flag && !busy_vis && !error_flag && !store_vis;

    // Status atual do sistema (tempo real)
    // prioridade: ERROR > BUSY > STORE > READY/DONE
    always @(*) begin
        if (error_flag)
            display_status_now = DISP_ERROR;
        else if (busy_vis)
            display_status_now = DISP_BUSY;
        else if (store_vis)
            display_status_now = DISP_STORE;
        else if (!started_once)
            display_status_now = DISP_READY;
        else
            display_status_now = DISP_DONE;
    end

    // Snapshot do status: ao apertar KEY[2], captura o status daquele instante e mantém fixo até apertar novamente
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n)
            display_status_latched <= DISP_READY;
        else if (status_btn_pulse)
            display_status_latched <= display_status_now;
    end

    // Texto nos HEX usando o status capturado
    always @(*) begin
        hex4_char = CH_BLANK;
        hex3_char = CH_BLANK;
        hex2_char = CH_BLANK;
        hex1_char = CH_BLANK;
        hex0_char = CH_BLANK;

        case (display_status_latched)
            DISP_READY: begin
                // READY
                hex4_char = CH_r;
                hex3_char = CH_E;
                hex2_char = CH_A;
                hex1_char = CH_d;
                hex0_char = CH_Y;
            end

            DISP_STORE: begin
                // STORE
                hex4_char = CH_S;
                hex3_char = CH_t;
                hex2_char = CH_O;
                hex1_char = CH_r;
                hex0_char = CH_E;
            end

            DISP_BUSY: begin
                // BUSY
                hex4_char = CH_BLANK;
                hex3_char = CH_b;
                hex2_char = CH_U;
                hex1_char = CH_S;
                hex0_char = CH_Y;
            end

            DISP_DONE: begin
                // DONE
                hex4_char = CH_BLANK;
                hex3_char = CH_d;
                hex2_char = CH_O;
                hex1_char = CH_n;
                hex0_char = CH_E;
            end

            DISP_ERROR: begin
                // ERROR
                hex4_char = CH_E;
                hex3_char = CH_r;
                hex2_char = CH_r;
                hex1_char = CH_O;
                hex0_char = CH_r;
            end

            default: begin
					 // Desligado
                hex4_char = CH_BLANK;
                hex3_char = CH_BLANK;
                hex2_char = CH_BLANK;
                hex1_char = CH_BLANK;
                hex0_char = CH_BLANK;
            end
        endcase
    end
	 
	 // Recebe o código do caractere e altera a saída do display para o caractere desejado
    hex7seg_char u_hex0 (.char_code(hex0_char), .hex(HEX0));
    hex7seg_char u_hex1 (.char_code(hex1_char), .hex(HEX1));
    hex7seg_char u_hex2 (.char_code(hex2_char), .hex(HEX2));
    hex7seg_char u_hex3 (.char_code(hex3_char), .hex(HEX3));
    hex7seg_char u_hex4 (.char_code(hex4_char), .hex(HEX4));

    // LEDs apresentando o resultados e as flags levantadas.
    assign LEDR[3:0] = pred[3:0];
    assign LEDR[4]   = busy_vis;
    assign LEDR[5]   = error_flag;
    assign LEDR[6]   = ready_done_vis;
    assign LEDR[7]   = img_loaded;
    assign LEDR[8]   = weights_loaded;
    assign LEDR[9]   = bias_loaded;

endmodule