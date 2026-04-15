# Aceleração por Hardware de uma Rede Neural ELM em FPGA DE1-SoC

Matéria: TEC 499 - MI Sistemas Digitais (UEFS)
Desenvolvedores: Cauê Nascimento, Gabriel Oliveira, Yago Mendes
Etapa: 1 - Implementação de Hardware e Simulação RTL

Este repositório demonstra a criação, usando Verilog, de um acelerador de hardware. Ele foi projetado para realizar a inferência de uma rede neural ELM (Extreme Learning Machine), com o objetivo de classificar números manuscritos em uma FPGA Cyclone V (DE1-SoC).

---

1. Descrição do Desafio

O desafio central é construir, usando hardware digital, um sistema que consiga processar a inferência de uma rede neural. Essa rede deve ser capaz de classificar imagens de 28x28 pixels, respeitando as limitações da FPGA e cumprindo os requisitos de funcionalidade, interface, ciclo de instrução e documentação definidos na Etapa 1. O critério de avaliação inclui correção funcional, um datapath e FSM bem estruturados, interface claramente documentada, um protocolo do tipo Start → Execute → Done e uma análise detalhada dos recursos utilizados.:contentReference[oaicite:2]{index=2}

A rede implementada segue a seguinte ordem:

- Entrada: vetor `x` com 784 posições (imagem 28x28 "achatada")
- Camada intermediária: 128 neurônios
- Saída: 10 categorias (dígitos de 0 a 9)

As equações da inferência são:

- `z = W_in · x + b`
- `h = tanh(z)`
- `y = h · beta`
- `pred = argmax(y)`

---

2. Requisitos Cumpridos

A solução foi criada para atender aos seguintes requisitos técnicos:

- Utilização de aritmética de ponto fixo no formato Q4.12
- Camada de entrada com 784 elementos
- Camada intermediária com 128 neurônios
- Camada de saída com 10 classes
- Uso de MAC em hardware para multiplicação e acumulação
- Implementação de função de ativação em hardware
- Emprego de FSM de controle para organizar leitura, processamento e finalização
- Implementação de protocolo operacional do tipo Start → Busy → Done
- Interface com documentação clara das instruções e status
- Demonstração da operação na placa DE1-SoC através de switches, botões, LEDs e displays

---

3. Organização da Solução

A arquitetura é organizada em dois blocos principais:

# 3.1 Datapath
Responsável pelos cálculos necessários para a inferência.

Módulos principais:
- `mac_q412`: realiza a multiplicação e reescala em Q4.12
- `tanh_lut`: implementa a ativação tangente hiperbólica por aproximação PWL
- `argmax10`: seleciona a classe com maior pontuação
- buffers internos `h_mem` e `y_mem`

# 3.2 Controle
Responsável pela organização do fluxo de execução.

Elementos principais:
- FSM principal em `elm_accel`
- subfases internas da inferência
- controle da leitura das memórias
- controle das instruções de armazenamento e início

---

4. Máquina de Estados e Pipeline

A FSM principal tem três estados:

- `ST_READY`: sistema inativo, esperando por instrução
- `ST_STORE`: confirmação de operação de escrita
- `ST_BUSY`: execução da inferência

Dentro de `ST_BUSY`, a inferência é dividida em fases internas, formando um pipeline sequencial para lidar com a latência das memórias síncronas:

# Camada Intermediária
- `PH_H_ADDR`
- `PH_H_WAIT0`
- `PH_H_WAIT1`
- `PH_H_MAC`
- `PH_H_BIAS`
- `PH_H_BIAS_WAIT0`
- `PH_H_BIAS_WAIT1`
- `PH_H_TANH`
- `PH_H_TANH_LATCH`

# Camada de Saída
- `PH_O_ADDR`
- `PH_O_WAIT0`
- `PH_O_WAIT1`
- `PH_O_MAC`

# Finalização
- `PH_ARGMAX`

Este pipeline permite separar:
1. o endereçamento das memórias,
2. a espera pela latência de leitura,
3. a multiplicação e acumulação (MAC),
4. a ativação,
5. a decisão final.

5. Representação numérica

O projeto adota o formato de ponto fixo Q4.12:

- `DATA_W = 16`
- `Q_FRAC = 12`
- `ACC_W = 32`

Em outras palavras:
- Dados primários representados em 16 bits
- Precisão fracionária definida por 12 bits
- Acumuladores de 32 bits para prevenir estouro nas somas

Quando multiplicamos dois números em Q4.12, obtemos um valor maior, que é ajustado com um deslocamento à direita (`>>> 12`) para manter a escala inicial.

---

6. Organização da memória e matrizes do modelo

O modelo se baseia nestas estruturas:

- `x`: vetor de entrada contendo 784 elementos
- `W_in`: matriz 128 x 784
- `b`: vetor de bias com 128 elementos
- `h`: vetor da camada escondida com 128 elementos
- `beta`: matriz 128 x 10
- `y`: vetor de saída com 10 elementos

Implementação no hardware:
- `ram_img`: armazena a imagem de entrada
- `ram_w_in`: armazena os pesos da camada escondida
- `ram_b`: armazena o bias da camada escondida
- `rom_beta`: armazena os pesos da camada de saída
- `h_mem`: memória temporária da camada escondida
- `y_mem`: memória temporária dos resultados finais
O display mostrará bUSY por um instante e depois dOnE.
O número que a rede "viu" na imagem aparecerá nos LEDs vermelhos e no display HEX0.

---

7. Operando diretamente na placa

Na demonstração prática, a instrução de 32 bits é construída com os interruptores:

- `instr[31:30]` = código de operação
- `instr[6:4]` = endereço de demonstração
- `instr[3:0]` = dado de demonstração

Botões disponíveis:
- `KEY[0]`: reinicialização
- `KEY[1]`: validação da instrução
- `KEY[2]`: captura do estado para mostrar

Funções implementadas:
- `00` = `ARMAZENA_PESOS`
- `01` = `ARMAZENA_BIAS`
- `10` = `ARMAZENA_IMG`
- `11` = `INICIA`

O estado é mostrado nos displays de 7 segmentos, enquanto os LEDs exibem a previsão e os indicadores de carga.

---

8. Principal novidade: escrita real na memória

Nesta versão, as instruções de escrita não são apenas indicações lógicas, mas escrevem dados reais na memória.

A lógica adicionada inclui:
- extração do endereço e dado demo da instrução
- ampliação da largura para os barramentos de memória
- alternância entre inferência e escrita
- ativação de `wren` real para:
- `ram_img`
- `ram_b`
- `ram_w_in`

Isso possibilita mostrar, via hardware, a escrita real em RAM por instrução, mesmo que de modo simples e para demonstração.

---

9. Processo de testes de operação

Os testes foram divididos em duas etapas:

# 9.1 Teste funcional da inferência
Comparar a saída do hardware com um modelo de referência em software para validar a precisão da classificação.

# 9.2 Teste estrutural da arquitetura
Verificar:
- reinicialização
- máquina de estados finitos (FSM)
- transição Início → Ocupado → Concluído
- armazenamentos em memória
- atualização dos indicadores
- exibição correta dos estados no visor

As diretrizes do relatório especificam que os testes planejados, sua execução e a análise dos resultados devem ser bem documentados.

---

10. Guia rápido de uso da placa

1. Ligue a DE1-SoC.
2. Programe a FPGA com o arquivo `.sof`.
3. Ajuste os interruptores para montar a instrução.
4. Aperte `KEY[1]` para enviar a instrução.
5. Observe:
- displays de 7 segmentos: estado do sistema
- LEDs: previsão e indicadores de carregamento
6. Para salvar o estado atual no display, aperte `KEY[2]`.

---

11. Lista de ferramentas utilizadas

- Intel Quartus Prime
- ModelSim / Questa
- Python, para gerar e tratar os dados
- In-System Memory Content Editor (ISMCE) para ver/depurar as memórias na FPGA

---

12. Considerações finais do projeto

A arquitetura atual foca em um fluxo sequencial controlado por FSM, diminuindo a quantidade de hardware duplicado e mantendo o projeto dentro dos limites da FPGA. Isso cumpre o objetivo do Marco 1 de demonstrar uma solução que funciona, bem documentada e validada em hardware, conforme as orientações.
