# T4 Paralela — Difusão de calor (Jacobi) em Fases Paralelas, MPI puro × híbrido MPI/OpenMP (Grupo 20, cp32020)

Enunciado e rubrica em [`docs/enunciado.md`](docs/enunciado.md), vocabulário em
[`GLOSSARY.md`](GLOSSARY.md), decisões não óbvias em [`docs/adr/`](docs/adr/).
Relatório entregue: [`relatorio/relatorio.pdf`](relatorio/relatorio.pdf).

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
| `jacobi.c` | fonte único das três versões; `-n N -i ITER -t TOL [-m]` |
| `Makefile` | `make` compila; `make teste` roda `teste.sh` |
| `teste.sh` | corretude: vários np/threads, N que não divide, faixas de 1 linha, parada por convergência, erros esperados |
| `medir.sh` | bateria: seq, MPI 4–64, híbrido 4×{1,2,4,8,16} e 8×{4,8}; `./medir.sh mapa` mostra onde cada thread rodou |
| `job.sh` | Slurm, 4 nós exclusivos: make + teste + mapa + medir + analisar |
| `analisar.py` | tabelas (`tabelas.txt`, `tab_escala.tex`) e gráficos (`grafico_escala`, `grafico_fases`; precisa de matplotlib) |
| `relatorio/relatorio.tex` | relatório no formato da disciplina (pág. 1 texto, pág. 2 anexo, pág. 3+ código) |
| `apresentacao_grupo20.pdf` | slides da apresentação em aula (escalabilidade forte, 13 slides) |

## Rodar no cluster

```bash
# de fora da PUCRS, pela sparta (usuário = início do e-mail PUCRS):
ssh -J <usuario>@sparta.pucrs.br cp32020@atlantica.lad.pucrs.br
git clone https://github.com/gacherubini/paralela-t4 && cd paralela-t4
make                                     # só compila na hospedeira (NÃO executar lá)
sbatch job.sh                            # 4 nós exclusivos: teste + mapa + medição (~20 min)
squeue -u $USER                          # acompanhar a fila
tail -f $(ls -t slurm-*.out | head -1)   # ver saindo; termina com "fim <data>"
```

O job aborta antes de medir se o `make teste` falhar. O cluster não tem
matplotlib: os gráficos e o PDF saem na máquina local.

```powershell
# trazer os resultados (PowerShell, máquina local)
scp -J <usuario>@sparta.pucrs.br -r cp32020@atlantica.lad.pucrs.br:~/paralela-t4/resultados .
python analisar.py                       # tabelas + gráficos
cd relatorio; tectonic relatorio.tex     # relatorio.pdf
```

## Experimentos e o que cada um responde

| Experimento | Configuração | Pergunta |
|---|---|---|
| Escala forte, MPI puro | seq + np = 4, 8, 16, 32, 64 (64 com HT) | speed-up e eficiência com 1 processo por núcleo |
| Escala forte, híbrido 1 proc/nó | 4 processos × 1, 2, 4, 8, 16 threads | o mesmo total de núcleos, com OpenMP dentro do nó |
| Híbrido 1 proc/socket | 8 processos × 4, 8 threads | separar o efeito NUMA (2 sockets por nó) do efeito do OpenMP |
| Tempo por fase | `calc`, `red`, `halo` em toda execução | onde o tempo vai: cálculo, verificação (inclui espera) ou troca de bordas |
| Mapa | `./medir.sh mapa` (`-m`) | MPI e híbrido usam as mesmas CPUs em cada ponto? |

Em cada total de núcleos, MPI puro e híbrido ocupam exatamente as mesmas CPUs
(metade em cada socket; ver [ADR 0004](docs/adr/0004-mesmas-cpus-nas-duas-versoes.md)).
`E = S / (processos × threads)`; com 64, conta as hardware threads.

## Resultados (job 47086, atlantica[03-06], 24/nov/2026)

N = 8192, 500 iterações, sequencial = 138,9 s. Todas as execuções deram o mesmo
resultado que o sequencial (`ok = sim` em [`resultados/tabelas.txt`](resultados/tabelas.txt)).

| núcleos | MPI puro S | E | híbrido 1/nó S | E |
|---:|---:|---:|---:|---:|
| 4 | 3,83 | 0,96 | 3,82 | 0,96 |
| 8 | 7,16 | 0,89 | 7,02 | 0,88 |
| 16 | 8,00 | 0,50 | 7,70 | 0,48 |
| 32 | 8,67 | 0,27 | 7,51 | 0,23 |
| 64 (HT) | 8,51 | 0,13 | 7,47 | 0,12 |

- **Limite de banda de memória**: um núcleo já satura o barramento do seu socket;
  o speed-up acompanha o número de sockets em uso (4 → 3,8; 8 → 7,2), não o de núcleos.
  HT não ajuda.
- **MPI puro um pouco melhor**: no híbrido os processos do meio têm vizinhos em
  outros nós dos dois lados e fazem duas trocas pela rede em série (~4 ms/iteração);
  no MPI cada processo de fronteira faz uma. Menos mensagens (6 × 126) não compensam.
