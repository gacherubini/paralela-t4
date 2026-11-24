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

[ "$falhas" -eq 0 ] && echo "TODOS OS TESTES PASSARAM" || { echo "$falhas FALHA(S)"; exit 1; }
