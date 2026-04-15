Projeto: Acelerador de Hardware para Rede Neural ELM (Extreme Learning Machine)
Disciplina: TEC 499 - MI Sistemas Digitais (UEFS)
Integrantes/Colaboradores: Cauê Nascimento, Gabriel Oliveira, Yago Mendes
Marco: 1 - Implementação de Hardware e Simulação RTL
Este repositório apresenta a solução de hardware em Verilog que desenvolvemos para acelerar a inferência de uma rede neural ELM, com foco na tarefa de classificar dígitos manuscritos (MNIST) utilizando uma FPGA Cyclone V (DE1-SoC).

1. Levantamento de Requisitos
Para cumprir as exigências do projeto e assegurar o funcionamento correto solicitado no Marco 1, implementamos os seguintes requisitos:
Processamento Matemático: Utilizamos aritmética de ponto fixo no formato Q4.12 (16 bits), garantindo o processamento preciso de números fracionários sem a complexidade de uma Unidade de Ponto Flutuante (FPU).
Capacidade da Rede: A rede suporta uma camada de entrada com 784 neurônios (imagens 28x28), uma camada oculta com 128 neurônios e uma camada de saída com 10 classes.
Função de Ativação em Hardware: Implementamos a função Tangente Hiperbólica (tanh) através de uma aproximação linear (PWL) para representar a não-linearidade dos neurônios.
Interface de Comunicação: O sistema é controlado por um protocolo de handshake (Start-Busy-Done) por meio de registradores mapeados em memória (MMIO).

2. Arquitetura do Datapath e Controle (Peso 20 no Barema)
A arquitetura foi organizada em dois blocos principais: o Fluxo de Dados (Datapath), responsável pelos cálculos, e a Unidade de Controle (FSM), que coordena todas as operações.
2.1 Máquina de Estados Finitos (FSM)
A lógica de controle foi implementada no módulo elm_accel.v, seguindo os estados definidos no barema:
ST_READY (IDLE): O acelerador permanece aguardando uma instrução de início. Os indicadores de status mostram que o sistema está pronto.
ST_BUSY (LOAD/COMPUTE): Ao receber o comando START, a FSM entra em uma sub-máquina de estados:
PH_H_ADDR / PH_H_WAIT / PH_H_ACC: Realiza o cálculo da Camada Oculta (Matriz de Pesos de Entrada $\times$ Pixels + Bias).
PH_ACTIVATE: Aplica a função de ativação Tanh no resultado acumulado.
PH_ACTIVATE: Aplica a função de ativação Tanh no resultado acumulado.
PH_ARGMAX (STORE/DONE): Identifica a saída com o maior valor (predição) entre as 10 possíveis e ativa o sinal de finalização.
2.2 Unidade MAC (Multiply-Accumulate)
Implementada no módulo mac_q412.v, esta unidade recebe dois números de 16 bits (Q4.12), multiplica-os, gerando um resultado intermediário de 32 bits, e efetua um deslocamento binário (>>> 12) para manter a escala correta antes de somar ao acumulador.
2.3 Função de Ativação (Tanh)
Ao contrário da ReLU simples, este projeto utiliza a Tangente Hiperbólica, implementada no módulo tanh_lut.v. A curva é aproximada por segmentos de reta (Piecewise Linear), permitindo que o hardware execute uma função complexa apenas com somas e deslocamentos, otimizando o uso de recursos da FPGA.

3. Interface MMIO e Ciclo de Instrução (Peso 30 no Barema)
A comunicação do sistema com o mundo externo é feita através de um banco de registradores detalhado abaixo. O controle segue o protocolo Start -> Execute -> Done.

Tabela de Registradores (Offsets)
Nome do Reg | Descrição
-------------------------------------------------------------------------------------------------------
INSTR       | Registrador de entrada. Bits definem o comando (0: Pesos, 1: Bias, 2: Imagem, 3: Start).
-------------------------------------------------------------------------------------------------------
STATUS      | [0] Busy, [1] Done, [2] Error, [3] Image Loaded, [4] Weights Loaded.
-------------------------------------------------------------------------------------------------------
PRED        | Resultado final da classificação (0 a 9).


Protocolo de Operação:
O usuário/software envia o comando 3 para o registrador de instrução.
O hardware detecta o instr_valid e ativa o sinal busy_flag no registrador de status.
A FSM executa todos os ciclos de clock necessários para a inferência (latência determinística baseada no número de neurônios).
Ao final, o hardware desativa o busy_flag, ativa o done_flag e disponibiliza o resultado no registrador PRED.

4. Detalhamento de Software e Hardware
Hardwares Usados
Placa: DE1-SoC da Terasic.
Chip: Cyclone V (5CSEMA5F31C6).
Periféricos: Displays de 7 segmentos (status), LEDs (resultado binário), e Memória Interna M10K (para armazenar 128 neurônios e 784 pixels).
Softwares Usados
Quartus Prime Lite Edition (v23.1/v25.1): Compilação e síntese.
ModelSim / Questa: Simulação RTL automatizada com Testbenches.
Python: Para gerar os arquivos .mif que inicializam a memória ROM com os pesos da rede neural treinada.

5. Processo de Instalação e Configuração
Preparação: Instale o Intel Quartus Prime e o simulador Questa/ModelSim.
Arquivos: Coloque todos os arquivos .v e .mif na mesma pasta.
Quartus: Crie um novo projeto, defina o top_de1soc.v como entidade principal e inclua os demais módulos.
Organização dos Pinos: Configure os pinos para CLOCK_50, KEYs, SWs, LEDs e displays HEX, seguindo as orientações do manual da placa DE1-SoC.
Processo de Compilação: Inicie a compilação. O arquivo .sof resultante será o que você usará para programar a sua FPGA.

6. Testes de Funcionamento e Simulação (Peso 25 no Barema)
Para confirmar se tudo funciona como esperado, criamos um Testbench para verificar tudo automaticamente:
Software de Automação: Usamos o simulador Questa.
Como Funciona: O Testbench pega uma imagem do MNIST, ativa o sinal de START e fica de olho nos sinais internos.
Golden Model: Pegamos os resultados da simulação e comparamos com um modelo feito em Python. O sistema acertou 100% na comparação funcional com o modelo de ponto fixo rodando no software.
Tempo de Resposta: Descobrimos que o sistema leva um número específico de ciclos de clock por inferência, então podemos prever com precisão o tempo de resposta do hardware.

7. Análise de Resultados e Recursos (Peso 15 no Barema)
Depois da síntese no Quartus, vimos que os recursos da FPGA foram usados assim:
Elementos Lógicos (LUTs/FFs): Usamos de forma equilibrada, principalmente na FSM e nos somadores de 32 bits.
Blocos de Memória (BRAM/M10K): Usamos bastante para guardar a matriz de pesos de entrada (784x128) e a matriz beta (128x10).
DSPs: Aproveitamos para acelerar as multiplicações do módulo MAC.
Resumo: A implementação em Q4.12 se mostrou o ponto certo entre o custo do hardware e a precisão. Usar uma FSM sequencial ajudou o projeto a caber sem problemas na Cyclone V, garantindo um ritmo de análise de dados mais ágil do que a execução exclusiva por programas em CPUs básicas.

Guia Rápido de Uso para Iniciantes
Ligue a placa DE1-SoC.
Carregue o código (arquivo .sof) via programador do Quartus.
Observe o display HEX: ele mostrará rEAdY.
Coloque a chave SW[0] para cima e aperte o botão KEY[1] para carregar a imagem de teste da memória.
Coloque as chaves em 0011 (instrução 3) e aperte KEY[1].
O display mostrará bUSY por um instante e depois dOnE.
O número que a rede "viu" na imagem aparecerá nos LEDs vermelhos e no display HEX0.
