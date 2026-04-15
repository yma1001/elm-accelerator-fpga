module top_de1soc (
    input  wire        CLOCK_50,
    input  wire [2:0]  KEY,
    input  wire [1:0]  SW,
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4
);

    localparam integer HOLD_500MS = 25_000_000;

    localparam [1:0] CMD_STORE_WEIGHTS = 2'd0;
    localparam [1:0] CMD_STORE_BIAS    = 2'd1;
    localparam [1:0] CMD_STORE_IMG     = 2'd2;
    localparam [1:0] CMD_START         = 2'd3;

    localparam [2:0] DISP_READY = 3'd0;
    localparam [2:0] DISP_STORE = 3'd1;
    localparam [2:0] DISP_BUSY  = 3'd2;
    localparam [2:0] DISP_DONE  = 3'd3;
    localparam [2:0] DISP_ERROR = 3'd4;

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

    wire rst_n;
    wire instr_valid_pulse;
    wire status_btn_pulse;

    reg  [31:0] instr;

    reg  [25:0] busy_hold_cnt;
    reg  [25:0] store_hold_cnt;

    wire busy_vis;
    wire store_vis;
    wire ready_done_vis;

    reg  [2:0] display_status_now;
    reg  [2:0] display_status_latched;

    reg  [5:0] hex4_char;
    reg  [5:0] hex3_char;
    reg  [5:0] hex2_char;
    reg  [5:0] hex1_char;
    reg  [5:0] hex0_char;

    assign rst_n = KEY[0];

    always @(*) begin
        instr = 32'b0;
        instr[31:30] = SW[1:0];
    end

    button_pulse u_button_cmd (
        .clk   (CLOCK_50),
        .rst_n (rst_n),
        .key_n (KEY[1]),
        .pulse (instr_valid_pulse)
    );

    button_pulse u_button_status (
        .clk   (CLOCK_50),
        .rst_n (rst_n),
        .key_n (KEY[2]),
        .pulse (status_btn_pulse)
    );

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

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            busy_hold_cnt <= 0;
        end else begin
            if (busy_flag)
                busy_hold_cnt <= HOLD_500MS;
            else if (busy_hold_cnt != 0)
                busy_hold_cnt <= busy_hold_cnt - 1'b1;
        end
    end

    assign busy_vis = busy_flag | (busy_hold_cnt != 0);

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            store_hold_cnt <= 0;
        end else begin
            if (instr_valid_pulse &&
               (SW[1:0] == CMD_STORE_WEIGHTS ||
                SW[1:0] == CMD_STORE_BIAS    ||
                SW[1:0] == CMD_STORE_IMG)) begin
                store_hold_cnt <= HOLD_500MS;
            end else if (store_hold_cnt != 0) begin
                store_hold_cnt <= store_hold_cnt - 1'b1;
            end
        end
    end

    assign store_vis = (store_hold_cnt != 0);
    assign ready_done_vis = done_flag && !busy_vis && !error_flag && !store_vis;

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

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n)
            display_status_latched <= DISP_READY;
        else if (status_btn_pulse)
            display_status_latched <= display_status_now;
    end

    always @(*) begin
        hex4_char = CH_BLANK;
        hex3_char = CH_BLANK;
        hex2_char = CH_BLANK;
        hex1_char = CH_BLANK;
        hex0_char = CH_BLANK;

        case (display_status_latched)
            DISP_READY: begin
                hex4_char = CH_r; hex3_char = CH_E; hex2_char = CH_A; hex1_char = CH_d; hex0_char = CH_Y;
            end
            DISP_STORE: begin
                hex4_char = CH_S; hex3_char = CH_t; hex2_char = CH_O; hex1_char = CH_r; hex0_char = CH_E;
            end
            DISP_BUSY: begin
                hex4_char = CH_BLANK; hex3_char = CH_b; hex2_char = CH_U; hex1_char = CH_S; hex0_char = CH_Y;
            end
            DISP_DONE: begin
                hex4_char = CH_BLANK; hex3_char = CH_d; hex2_char = CH_O; hex1_char = CH_n; hex0_char = CH_E;
            end
            DISP_ERROR: begin
                hex4_char = CH_E; hex3_char = CH_r; hex2_char = CH_r; hex1_char = CH_O; hex0_char = CH_r;
            end
            default: begin
                hex4_char = CH_BLANK; hex3_char = CH_BLANK; hex2_char = CH_BLANK; hex1_char = CH_BLANK; hex0_char = CH_BLANK;
            end
        endcase
    end

    hex7seg_char u_hex0 (.char_code(hex0_char), .hex(HEX0));
    hex7seg_char u_hex1 (.char_code(hex1_char), .hex(HEX1));
    hex7seg_char u_hex2 (.char_code(hex2_char), .hex(HEX2));
    hex7seg_char u_hex3 (.char_code(hex3_char), .hex(HEX3));
    hex7seg_char u_hex4 (.char_code(hex4_char), .hex(HEX4));

    assign LEDR[3:0] = pred[3:0];
    assign LEDR[4]   = busy_vis;
    assign LEDR[5]   = error_flag;
    assign LEDR[6]   = ready_done_vis;
    assign LEDR[7]   = img_loaded;
    assign LEDR[8]   = weights_loaded;
    assign LEDR[9]   = bias_loaded;

endmodule