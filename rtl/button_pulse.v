module button_pulse (
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,   // botão ativo em 0
    output reg  pulse
);
	 
	 // Guarda o estado anterior do botão.
    reg key_d;
	 
	 // Detecta a transição do nível lógico do botão, de solto (1) para apertado (0) e sobe o nível lógico do pulso
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // Botão reset pressionado. Valor do botão e do pulso voltam pro padrão
            key_d <= 1'b1;
            pulse <= 1'b0;
        end else begin
            pulse <= key_d & ~key_n; // 1 ciclo quando aperta
            key_d <= key_n; // Estado atual guardado
        end
    end

endmodule