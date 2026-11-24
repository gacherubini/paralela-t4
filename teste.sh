#!/usr/bin/env bash
# Confere que jacobi_mpi e jacobi_hib reproduzem o jacobi_seq.
# Dois casos: (a) para pelo limite de iteracoes, com N que nao divide por np
# (faixas desiguais); (b) converge antes (para pela tolerancia), para conferir
# que todos os processos decidem parar na mesma iteracao.
set -uo pipefail
MPIRUN=${MPIRUN:-mpirun --oversubscribe}
falhas=0

confere() {   # rotulo referencia obtido
    local rot=$1 ref=$2 got=$3
    if awk -F';' -v r="$ref" -v g="$got" 'BEGIN{
            split(r, a, ";"); split(g, b, ";");
            rel = (a[12] == 0) ? 0 : (a[12] - b[12]) / a[12]; if (rel < 0) rel = -rel;
            exit !(a[5] == b[5] && a[11] == b[11] && rel < 1e-9) }'; then
        echo "OK     $rot  ($(echo "$got" | cut -d';' -f5,11 --output-delimiter=' iter, delta='))"
    else
        echo "FALHOU $rot"; echo "  esperado: $ref"; echo "  obtido:   $got"; falhas=$((falhas + 1))
    fi
}

for caso in "203 300 0" "40 100000 1e-3"; do
    set -- $caso; n=$1; it=$2; tol=$3
    ref=$(./jacobi_seq -n "$n" -i "$it" -t "$tol" | tail -1)
    echo "seq n=$n: $(echo "$ref" | cut -d';' -f5,11 --output-delimiter=' iter, delta=')"
    for np in 1 2 3 4 7; do
        confere "mpi np=$np n=$n" "$ref" "$($MPIRUN -np $np ./jacobi_mpi -n $n -i $it -t $tol | tail -1)"
    done
    for cfg in "1 1" "2 3" "4 4" "3 2"; do
        set -- $cfg
        confere "hib np=$1 t=$2 n=$n" "$ref" \
            "$(OMP_NUM_THREADS=$2 $MPIRUN -x OMP_NUM_THREADS -np $1 ./jacobi_hib -n $n -i $it -t $tol | tail -1)"
    done
done

# Casos de borda: faixas de 1 linha (N = np) e mais threads do que linhas.
ref=$(./jacobi_seq -n 7 -i 50 -t 0 | tail -1)
confere "mpi np=7 n=7 (1 linha por faixa)" "$ref" "$($MPIRUN -np 7 ./jacobi_mpi -n 7 -i 50 -t 0 | tail -1)"
confere "hib np=7 t=4 n=7 (threads > linhas)" "$ref" \
    "$(OMP_NUM_THREADS=4 $MPIRUN -x OMP_NUM_THREADS -np 7 ./jacobi_hib -n 7 -i 50 -t 0 | tail -1)"
ref=$(./jacobi_seq -n 1000 -i 20 -t 0 | tail -1)
confere "hib np=4 t=3 n=1000" "$ref" \
    "$(OMP_NUM_THREADS=3 $MPIRUN -x OMP_NUM_THREADS -np 4 ./jacobi_hib -n 1000 -i 20 -t 0 | tail -1)"

# Erros esperados: N < np aborta; argumento invalido sai com erro. Criterio: o
# programa NAO pode imprimir linha de resultado. (O codigo de saida e o texto
# do MPI_Abort variam com a versao do Open MPI e com o Slurm: nao servem.)
deve_falhar() {   # rotulo comando...
    local rot=$1 out; shift
    out=$(timeout 60 "$@" 2>&1)
    if echo "$out" | grep -qE '^(seq|mpi|hib);'; then
        echo "FALHOU $rot (deveria dar erro, mas imprimiu resultado)"
        echo "$out" | head -5 | sed 's/^/    /'; falhas=$((falhas + 1))
    else echo "OK     $rot (erro, como esperado)"; fi
}
deve_falhar "mpi np=4 n=3 (N < np)" $MPIRUN -np 4 ./jacobi_mpi -n 3 -i 10 -t 0
deve_falhar "seq sem -i" ./jacobi_seq -n 10 -t 0
deve_falhar "seq tol negativa" ./jacobi_seq -n 10 -i 5 -t -1

[ "$falhas" -eq 0 ] && echo "TODOS OS TESTES PASSARAM" || { echo "$falhas FALHA(S)"; exit 1; }
