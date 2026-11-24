# Enunciado TP4: Fases Paralelas (FP)

Disciplina 4645J-04 — Computação Paralela — Turma 320 — 2026/2 — Prof. Cesar Augusto F. De Rose
Fonte: Moodle PUCRS (mod/page id=3803764, atualizado em 12/nov/2026). Entrega: tarefa "Submissão do trabalho TPP4 MPI/OpenMP".

O objetivo do trabalho é implementar, usando a biblioteca MPI, uma versão paralela seguindo o modelo fases paralelas, de um programa escolhido pelo grupo que seja adequado a este modelo (uma versão MPI puro e uma versão híbrida MPI com OpenMP). Após implementado, o programa deve ser executado no cluster atlantica com 4 nós (32/64 processos, no segundo caso com HT) para realização das medições de desempenho. Cada grupo deve entregar um relatório em .pdf de uma página com a análise dos resultados e o código em anexo (seguir modelo proposto).

Cada um dos processos é responsável por 1/np do trabalho, que já pode ser gerado internamente em cada processo, ou gerado em um único processo e depois distribuído em partes iguais entre os restantes. Depois, o processamento segue as seguintes fases, que são executadas em paralelo por todos os processos até a conclusão da ordenação (por isso o nome do modelo):

1. Processamento local: cada processo realiza a sua parte do trabalho global;
2. É feita uma verificação distribuída para identificar se o trabalho está pronto (comunicação coletiva);
3. Se não, cada processo troca valores com seus vizinhos em busca de convergência (padrão depende da lógica do problema).

O foco deste trabalho é a comparação da versão em MPI puro (np 32/64) com a versão híbrida MPI/OpenMP (np 4, 8 e 16 threads dentro do nó).

Verificar os itens de avaliação na rubrica para este trabalho.

## Rubrica (10 pontos cada item)

1. O relatório está bem escrito e no formato solicitado.
2. O problema escolhido é interessante e adequado para a aplicação de paralelismo no modelo de fases paralelas híbrido que combina MPI com OpenMP.
3. O problema foi ajustado para ter carga suficiente para sua avaliação em 4 máquinas e a carga das mensagens foi suficiente para ser subdividida entre as threads no processo trabalhador.
4. O grupo adaptou o problema utilizando corretamente as diretivas do MPI e OpenMP e explicou no relatório como as diretivas foram usadas e como o modelo original foi adaptado para sua versão híbrida.
5. Enviou o código em anexo, de forma que foi possível reproduzir os resultados apresentados no relatório.
6. Plotou a escalabilidade forte da versão MPI puro e da híbrida, observando também a eficiência.
7. Deixou claro no relatório se foi usada alguma ferramenta de IA, o nome da ferramenta e como foi usada (na instrumentação do código e na confecção do relatório).
8. Dedicou boa parte do relatório a uma análise aprofundada dos resultados (foco do relatório).
9. Apresentação dos resultados (escalabilidade forte) em aula, com participação ativa de todos os integrantes.

## Pseudocódigo FP do professor (exemplo: ordenação de um grande vetor)

```c
MPI_Init();
my_rank = MPI_Comm_rank();  // número do processo atual
proc_n  = MPI_Comm_size();  // número total de processos

// gero parte local do vetor (1/np avos do vetor global)
Inicializa(vetor);          // ordem reversa
pronto = FALSE;

while (!pronto) {
    BubbleSort(vetor);      // ordeno vetor local

    // verifico condição de parada
    // se não for np-1, mando o meu maior elemento para a direita
    // se não for 0, recebo o maior elemento da esquerda
    // comparo se o meu menor elemento é maior do que o maior recebido
    //   (se sim, estou ordenado em relação ao meu vizinho)
    // compartilho o meu estado com todos: BCAST com cada processo como origem (NP vezes)
    for (0 até NP-1)
        MPI_Bcast(estado);
    // se todos estiverem ordenados com seus vizinhos, pronto = TRUE, break
    // senão continuo

    // troco valores para convergir
    // se não for o 0, mando os menores valores do meu vetor para a esquerda
    // se não for np-1, recebo os menores valores da direita
    // ordeno estes valores com a parte mais alta do meu vetor local
    // devolvo os valores que recebi para a direita
    // se não for o 0, recebo de volta os maiores valores da esquerda
}
MPI_Finalize();
```
