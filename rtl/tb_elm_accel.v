`timescale 1ns/1ps

module tb_elm_accel;

    reg clk;
    reg rst_n;
    reg [31:0] instr;
    reg instr_valid;

    wire [3:0] pred;
    wire busy_flag, done_flag, error_flag;

    // DUT
    elm_accel uut (
        .clk(clk),
        .rst_n(rst_n),
        .instr(instr),
        .instr_valid(instr_valid),
        .pred(pred),
        .busy_flag(busy_flag),
        .done_flag(done_flag),
        .error_flag(error_flag)
    );

    // Clock: 20ns período
    always #10 clk = ~clk;

    // RESULTADOS
    reg test_result [0:4];

    // TASK: RESET SINCRONIZADO
    task reset;
    begin
        rst_n = 0;
        instr_valid = 0;
        instr = 0;

        repeat (3) @(posedge clk);

        rst_n = 1;

        repeat (3) @(posedge clk);
    end
    endtask

    // TASK: ENVIO DE COMANDO
    task send_cmd(input [1:0] cmd);
    begin
        @(posedge clk);
		  instr = 32'b0;
        instr[31:30] = cmd;
        instr_valid = 1;

        @(posedge clk);
        instr_valid = 0;

        @(posedge clk); // garante processamento
    end
    endtask

    // TESTE 1: START sem dados → erro
    task test1;
    begin
        $display("\n[TESTE 1] START sem STORE");
        reset();

        send_cmd(2'd3); // START

        wait(busy_flag == 1);
        @(posedge clk);

        test_result[0] = error_flag;

        $display(test_result[0] ? "PASS" : "FAIL");
    end
    endtask

    // TESTE 2: Apenas IMG → erro
    task test2;
    begin
        $display("\n[TESTE 2] Apenas imagem");
        reset();

        send_cmd(2'd2); // IMG
        send_cmd(2'd3); // START

        wait(busy_flag == 1);
        @(posedge clk);

        test_result[1] = error_flag;

        $display(test_result[1] ? "PASS" : "FAIL");
    end
    endtask


    // TESTE 3: Fluxo completo → sucesso
    task test3;
    begin
        $display("\n[TESTE 3] Fluxo completo");
        reset();

        send_cmd(2'd2); // IMG
        send_cmd(2'd0); // W
        send_cmd(2'd1); // B

        send_cmd(2'd3); // START

        wait(done_flag == 1);

        test_result[2] = (!error_flag && done_flag);

        $display(test_result[2] ? "PASS" : "FAIL");
    end
    endtask

    // TESTE 4: Busy ativa
    task test4;
    begin
        $display("\n[TESTE 4] Busy ativa");
        reset();

        send_cmd(2'd2);
        send_cmd(2'd0);
        send_cmd(2'd1);

        send_cmd(2'd3);

        wait(busy_flag == 1);

        test_result[3] = busy_flag;

        $display(test_result[3] ? "PASS" : "FAIL");
    end
    endtask

    // TESTE 5: START duplo

    task test5;
    begin
        $display("\n[TESTE 5] START duplo");
        reset();

        send_cmd(2'd2);
        send_cmd(2'd0);
        send_cmd(2'd1);

        send_cmd(2'd3);
        @(posedge clk);
        send_cmd(2'd3); // segundo START

        wait(done_flag == 1);

        test_result[4] = done_flag;

        $display(test_result[4] ? "PASS" : "FAIL");
    end
    endtask

    // CHECKLIST FINAL
    task checklist;
    begin
        $display("\n=======================================");
        $display("CHECKLIST FINAL DOS TESTES");
        $display("=======================================");

        $display("1. START sem dados        : %s", test_result[0] ? "PASS" : "FAIL");
        $display("2. Apenas imagem          : %s", test_result[1] ? "PASS" : "FAIL");
        $display("3. Fluxo completo         : %s", test_result[2] ? "PASS" : "FAIL");
        $display("4. Busy durante execucao  : %s", test_result[3] ? "PASS" : "FAIL");
        $display("5. START duplo            : %s", test_result[4] ? "PASS" : "FAIL");

        $display("=======================================\n");
    end
    endtask

    // DEBUG AUTOMÁTICO
    initial begin
        $monitor("t=%0t | busy=%d done=%d error=%d",
                 $time, busy_flag, done_flag, error_flag);
    end

    // EXECUÇÃO
    initial begin
        clk = 0;

        test1();
        test2();
        test3();
        test4();
        test5();

        checklist();

        #100;
        $stop;
    end

endmodule