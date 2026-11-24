# Difusão de calor por Jacobi em fases paralelas (T4)

Placa N×N resolvida pelo método de Jacobi no modelo de fases paralelas, em MPI puro e em MPI com OpenMP.

## Problema

**Placa**:
Malha de N×N pontos internos cercada por uma borda fixa: 100 °C em cima, 0 °C nos outros três lados.
_Avoid_: matriz (quando o que importa é o problema físico), grade

**Iteração**:
Uma passada de Jacobi: cada ponto interno vira a média dos 4 vizinhos, lidos da matriz da iteração anterior.
_Avoid_: passo de tempo, geração

**Delta**:
Maior variação |novo − atual| entre todos os pontos numa iteração; é o que a verificação compara com a tolerância.
_Avoid_: erro, resíduo

**Tolerância**:
Valor abaixo do qual o delta indica convergência e o laço para (`-t`).

## Decomposição

**Faixa**:
Bloco de linhas contíguas da placa que pertence a um processo MPI (⌊N/np⌋ ou ⌈N/np⌉ linhas).
_Avoid_: pedaço, bloco, partição

**Linha fantasma**:
Cópia local da linha de borda do vizinho, guardada acima e abaixo da faixa (halo).
_Avoid_: linha extra, ghost (no texto em português)

**Fronteira entre nós**:
Par de faixas vizinhas cujos processos estão em nós diferentes; a troca entre elas passa pela rede.

## Fases

**Processamento local**:
Fase 1: a iteração de Jacobi sobre a própria faixa (`passo()`); no híbrido, dividida entre as threads.
_Avoid_: cálculo (no texto do relatório, "cálculo" é o tempo medido dessa fase)

**Verificação**:
Fase 2: `MPI_Allreduce(MPI_MAX)` do delta, para todos decidirem juntos se param.
_Avoid_: reduce, checagem

**Troca de bordas**:
Fase 3: dois `MPI_Sendrecv` que atualizam as linhas fantasma com os vizinhos de cima e de baixo.
_Avoid_: comunicação (genérico demais), halo exchange

## Versões e configurações

**MPI puro**:
`jacobi_mpi`: um processo por núcleo (ou hardware thread, com 64), sem threads.

**Híbrido 1 proc/nó**:
`jacobi_hib` com 4 processos, um por nó, e 1 a 16 threads OpenMP cada.
_Avoid_: híbrido (sozinho, quando a configuração importa)

**Híbrido 1 proc/socket**:
`jacobi_hib` com 8 processos, um por socket, presos aos 4 núcleos dele, com 4 ou 8 threads.

**Núcleos**:
Total de processos × threads de uma execução; o eixo x da escalabilidade forte. Com 64, são hardware threads (HT).
_Avoid_: processadores, cores

**Mapa**:
Onde cada processo e thread rodou (nó e CPU), registrado com `-m` em `resultados/mapa.txt`.
