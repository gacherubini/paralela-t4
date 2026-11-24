/*
 * Trabalho 4 - Computacao Paralela - Grupo 20
 * Difusao de calor 2D pelo metodo de Jacobi no modelo de Fases Paralelas (FP).
 *
 * Um fonte, tres binarios:
 *   gcc                          -> jacobi_seq  (sequencial, base do speed-up)
 *   mpicc -DPARALELO             -> jacobi_mpi  (MPI puro: 1 processo por nucleo)
 *   mpicc -DPARALELO -fopenmp    -> jacobi_hib  (hibrido: poucos processos MPI,
 *                                                 threads OpenMP dentro de cada um)
 *
 * Problema: placa quadrada com N x N pontos internos. A borda de cima fica a
 * 100 graus e as outras tres a 0. A cada iteracao cada ponto interno vira a
 * media dos 4 vizinhos; repete-se ate a maior variacao ficar abaixo de TOL ou
 * ate ITER_MAX iteracoes.
 *
 * Decomposicao: a placa e cortada em faixas horizontais de linhas contiguas,
 * uma por processo (1/np do trabalho, gerado localmente). Cada faixa guarda
 * uma linha extra em cima e outra embaixo (linhas fantasma, "halo") com a
 * copia da borda do vizinho.
 *
 * Fases de cada iteracao (iguais em todos os processos):
 *   1. processamento local : atualiza a propria faixa       (OpenMP no hibrido)
 *   2. verificacao global  : MPI_Allreduce(MAX) da variacao (comunicacao coletiva)
 *   3. troca com vizinhos  : MPI_Sendrecv das linhas de borda com cima e baixo
 *
 * Saida (stdout, uma linha, so o rank 0):
 *   versao;procs;threads;n;iter;tempo;calc;red;halo;calc_max;delta;soma
 * tempo    = laco principal (sem alocacao/inicializacao), em segundos
 * calc/red/halo = media entre os processos do tempo em cada fase
 * calc_max = maior tempo de calculo entre os processos (desbalanceamento)
 * delta    = maior variacao na ultima iteracao (identica em todas as versoes)
 * soma     = soma das temperaturas finais (confere o resultado entre versoes)
 *
 * Uso: jacobi_xxx -n N -i ITER_MAX -t TOL [-m]
 *   -m  mostra em stderr onde cada processo/thread rodou (no e CPU)
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <unistd.h>
#include <sched.h>

#ifdef PARALELO
#include <mpi.h>
#endif
#ifdef _OPENMP
#include <omp.h>
#endif

#define QUENTE 100.0   /* temperatura da borda de cima */

#if defined(PARALELO) && defined(_OPENMP)
static const char *VERSAO = "hib";
#elif defined(PARALELO)
static const char *VERSAO = "mpi";
#else
static const char *VERSAO = "seq";
#endif

static double agora(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static void uso(const char *prog)
{
    fprintf(stderr, "uso: %s -n N -i ITER_MAX -t TOL [-m]\n", prog);
    exit(1);
}

/* Inicializa a faixa local (linhas 0..L+1, colunas 0..N+1).
 * 'ini' e o indice global da primeira linha interna da faixa (1..N).
 * A linha global 0 e a borda quente; a linha global N+1 e as colunas 0 e N+1
 * ficam a 0. Feita com o mesmo escalonamento estatico do calculo para que, no
 * hibrido, cada pagina de memoria seja tocada primeiro pela thread que vai
 * usa-la (first touch: a pagina fica no banco de memoria do socket dela). */
static void inicializa_linha(double *a, int i, int N, int ini)
{
    const int W = N + 2;
    double v = (ini - 1 + i == 0) ? QUENTE : 0.0;
    for (int j = 0; j < W; j++)
        a[(size_t)i * W + j] = (j == 0 || j == W - 1) ? 0.0 : v;
}

static void inicializa(double *a, int L, int N, int ini)
{
    /* linhas 1..L: mesmo laco (mesmos limites) do passo(), logo mesma divisao */
    #pragma omp parallel for schedule(static)
    for (int i = 1; i <= L; i++)
        inicializa_linha(a, i, N, ini);
    inicializa_linha(a, 0, N, ini);       /* linhas fantasma */
    inicializa_linha(a, L + 1, N, ini);
}

/* Fase 1: processamento local. Uma iteracao de Jacobi sobre as linhas 1..L.
 * Le 'atual', escreve 'novo' e devolve a maior variacao |novo - atual|.
 * No hibrido as linhas sao divididas entre as threads (schedule static: todas
 * as linhas custam o mesmo) e o maximo e combinado pela reducao do OpenMP. */
static double passo(const double *restrict atual, double *restrict novo, int L, int N)
{
    const int W = N + 2;
    double dmax = 0.0;
    #pragma omp parallel for schedule(static) reduction(max:dmax)
    for (int i = 1; i <= L; i++) {
        const double *cima = atual + (size_t)(i - 1) * W;
        const double *meio = atual + (size_t)i * W;
        const double *baixo = atual + (size_t)(i + 1) * W;
        double *saida = novo + (size_t)i * W;
        for (int j = 1; j <= N; j++) {
            double v = 0.25 * (cima[j] + baixo[j] + meio[j - 1] + meio[j + 1]);
            double d = fabs(v - meio[j]);
            if (d > dmax) dmax = d;
            saida[j] = v;
        }
    }
    return dmax;
}

#ifdef PARALELO
/* Fase 3: troca das linhas de borda com os vizinhos de cima e de baixo.
 * Na primeira/ultima faixa o vizinho e MPI_PROC_NULL: o Sendrecv nao faz nada
 * e a linha fantasma continua sendo a borda fixa da placa.
 * Sendrecv evita o impasse de todos mandarem antes de receber. So a thread
 * principal chama MPI (MPI_THREAD_FUNNELED). */
static void troca_bordas(double *a, int L, int N, int cima, int baixo)
{
    const int W = N + 2;
    /* minha primeira linha sobe; recebo a primeira linha de quem esta embaixo */
    MPI_Sendrecv(a + (size_t)1 * W, W, MPI_DOUBLE, cima, 0,
                 a + (size_t)(L + 1) * W, W, MPI_DOUBLE, baixo, 0,
                 MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    /* minha ultima linha desce; recebo a ultima linha de quem esta em cima */
    MPI_Sendrecv(a + (size_t)L * W, W, MPI_DOUBLE, baixo, 1,
                 a, W, MPI_DOUBLE, cima, 1,
                 MPI_COMM_WORLD, MPI_STATUS_IGNORE);
}
#endif

/* -m: mostra no e CPU de cada thread de cada processo (confere o mapeamento) */
static void mostra_mapa(int rank, int ini, int L)
{
    char host[256];
    gethostname(host, sizeof host);
    #pragma omp parallel
    {
        int t = 0;
#ifdef _OPENMP
        t = omp_get_thread_num();
#endif
        #pragma omp critical
        fprintf(stderr, "mapa rank=%d thread=%d host=%s cpu=%d linhas=%d..%d\n",
                rank, t, host, sched_getcpu(), ini, ini + L - 1);
    }
}

int main(int argc, char **argv)
{
    int N = 0, iter_max = 0, mapa = 0;
    double tol = -1.0;
    int rank = 0, np = 1, threads = 1;

#ifdef PARALELO
    int nivel;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &nivel);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &np);
#endif
#ifdef _OPENMP
    threads = omp_get_max_threads();
#endif

    int op;
    while ((op = getopt(argc, argv, "n:i:t:m")) != -1) {
        switch (op) {
        case 'n': N = atoi(optarg); break;
        case 'i': iter_max = atoi(optarg); break;
        case 't': tol = atof(optarg); break;
        case 'm': mapa = 1; break;
        default: uso(argv[0]);
        }
    }
    if (N <= 0 || iter_max <= 0 || tol < 0) uso(argv[0]);
    if (N < np) {
        if (rank == 0) fprintf(stderr, "N=%d menor que o numero de processos (%d)\n", N, np);
#ifdef PARALELO
        MPI_Abort(MPI_COMM_WORLD, 1);
#endif
        return 1;
    }
#if defined(PARALELO) && defined(_OPENMP)
    if (nivel < MPI_THREAD_FUNNELED && rank == 0)
        fprintf(stderr, "aviso: MPI sem suporte a MPI_THREAD_FUNNELED\n");
#endif

    /* Divisao das N linhas internas: as 'resto' primeiras faixas tem uma a mais */
    const int base = N / np, resto = N % np;
    const int L = base + (rank < resto);
    const int ini = 1 + rank * base + (rank < resto ? rank : resto);
    const size_t W = (size_t)N + 2;

    double *atual = malloc((L + 2) * W * sizeof(double));
    double *novo  = malloc((L + 2) * W * sizeof(double));
    if (!atual || !novo) {
        fprintf(stderr, "rank %d: sem memoria para %d linhas\n", rank, L);
#ifdef PARALELO
        MPI_Abort(MPI_COMM_WORLD, 1);
#endif
        return 1;
    }
    inicializa(atual, L, N, ini);
    inicializa(novo, L, N, ini);   /* bordas fixas existem nas duas matrizes */
    if (mapa) mostra_mapa(rank, ini, L);

#ifdef PARALELO
    const int cima  = (rank > 0)      ? rank - 1 : MPI_PROC_NULL;
    const int baixo = (rank < np - 1) ? rank + 1 : MPI_PROC_NULL;
    MPI_Barrier(MPI_COMM_WORLD);       /* todos largam juntos */
#endif

    double t_calc = 0, t_red = 0, t_halo = 0;
    double t_inicio = agora();
#ifdef PARALELO
    troca_bordas(atual, L, N, cima, baixo);   /* halos iniciais */
    t_halo += agora() - t_inicio;
#endif

    int it = 0;
    double delta = 0;
    while (1) {
        /* Fase 1: processamento local */
        double t0 = agora();
        double dlocal = passo(atual, novo, L, N);
        double *tmp = atual; atual = novo; novo = tmp;
        it++;
        double t1 = agora();
        t_calc += t1 - t0;

        /* Fase 2: verificacao distribuida (todos ficam sabendo a maior variacao) */
#ifdef PARALELO
        MPI_Allreduce(&dlocal, &delta, 1, MPI_DOUBLE, MPI_MAX, MPI_COMM_WORLD);
#else
        delta = dlocal;
#endif
        double t2 = agora();
        t_red += t2 - t1;
        if (delta < tol || it == iter_max) break;   /* decisao igual em todos */

        /* Fase 3: troca com os vizinhos para a proxima iteracao */
#ifdef PARALELO
        troca_bordas(atual, L, N, cima, baixo);
        t_halo += agora() - t2;
#endif
    }
    double tempo = agora() - t_inicio;

    /* Conferencia: soma das temperaturas internas finais */
    double soma = 0;
    #pragma omp parallel for schedule(static) reduction(+:soma)
    for (int i = 1; i <= L; i++)
        for (size_t j = 1; j <= (size_t)N; j++)
            soma += atual[i * W + j];

    double calc_max = t_calc;
#ifdef PARALELO
    double locais[3] = {t_calc, t_red, t_halo}, somas[3], soma_tot, tmax;
    MPI_Reduce(locais, somas, 3, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
    MPI_Reduce(&t_calc, &calc_max, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&soma, &soma_tot, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
    MPI_Reduce(&tempo, &tmax, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    t_calc = somas[0] / np; t_red = somas[1] / np; t_halo = somas[2] / np;
    soma = soma_tot; tempo = tmax;
#endif

    if (rank == 0)
        printf("%s;%d;%d;%d;%d;%.4f;%.4f;%.4f;%.4f;%.4f;%.17g;%.12e\n",
               VERSAO, np, threads, N, it, tempo, t_calc, t_red, t_halo,
               calc_max, delta, soma);

    free(atual);
    free(novo);
#ifdef PARALELO
    MPI_Finalize();
#endif
    return 0;
}
