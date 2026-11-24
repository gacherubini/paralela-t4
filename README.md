# T4 Paralela — Difusão de calor (Jacobi) em Fases Paralelas, MPI puro × híbrido MPI/OpenMP (Grupo 20, cp32020)

Enunciado e rubrica em [`docs/enunciado.md`](docs/enunciado.md).

Uma placa de N×N pontos com a borda de cima a 100 °C e as outras a 0 °C. A cada
iteração, cada ponto vira a média dos 4 vizinhos (método de Jacobi), até a maior
variação ficar abaixo da tolerância ou atingir o limite de iterações.

| Fase (cada iteração) | O que faz | Chamada |
|---|---|---|
| 1. processamento local | atualiza a própria faixa de linhas | laço com `#pragma omp parallel for` no híbrido |
| 2. verificação global | todos ficam sabendo a maior variação | `MPI_Allreduce(MPI_MAX)` |
| 3. troca com vizinhos | linhas de borda (halo) com o processo de cima e o de baixo | `MPI_Sendrecv` ×2 |

| Binário | Compilação | Uso |
|---|---|---|
| `jacobi_seq` | `gcc` | base do speed-up |
| `jacobi_mpi` | `mpicc -DPARALELO` | MPI puro, 1 processo por núcleo |
| `jacobi_hib` | `mpicc -DPARALELO -fopenmp` | 1 processo por nó (ou socket) + threads OpenMP |

Saída: `versao;procs;threads;n;iter;tempo;calc;red;halo;calc_max;delta;soma`.
`make teste` confere que MPI e híbrido dão o mesmo `iter`, o mesmo `delta` (bit a
bit) e a mesma `soma` que o sequencial.

## Arquivos

| Arquivo | O que é |
|---|---|
| `jacobi.c` | fonte único das três versões |
| `Makefile` | `make` compila; `make teste` roda `teste.sh` |
| `teste.sh` | corretude: vários np/threads, N que não divide, parada por convergência |
| `medir.sh` | bateria: seq, MPI 4–64, híbrido 4×{1,2,4,8,16} e 8×{4,8}; `./medir.sh mapa` mostra onde cada thread rodou |
| `job.sh` | Slurm, 4 nós exclusivos: make + teste + mapa + medir + analisar |
| `analisar.py` | tabelas (`tabelas.txt`, `tab_escala.tex`) e gráficos (`grafico_escala`, `grafico_fases`) |

## Rodar no cluster

```bash
ssh cp32020@atlantica.lad.pucrs.br       # via sparta se estiver fora da PUCRS
git clone https://github.com/gacherubini/paralela-t4 && cd paralela-t4
make                                     # só compila na hospedeira (NÃO executar lá)
sbatch job.sh                            # 4 nós exclusivos: teste + mapa + medição, ~30-45 min
squeue -u $USER                          # acompanhar a fila
tail -f slurm-*.out                      # ver saindo
```

Ao terminar: `resultados/` tem `tempos.csv`, `mapa.txt`, `maquina.txt`, `tabelas.txt`.
Para trazer de volta: `git add resultados && git commit -m "Add cluster results" && git push`
(ou copiar o conteúdo de `resultados/tempos.csv` e `resultados/mapa.txt`).
