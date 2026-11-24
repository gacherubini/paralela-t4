#!/usr/bin/env bash
# Bateria de medicoes do T4 (rodar dentro de um job com 4 nos exclusivos).
#
#   ./medir.sh          mede tudo -> resultados/tempos.csv
#   ./medir.sh mapa     so mostra onde cada processo/thread roda -> resultados/mapa.txt
#
# Cada no da atlantica: 2 sockets x 4 nucleos x 2 threads HT = 8 nucleos / 16 CPUs.
# Para comparar MPI puro e hibrido com o MESMO total de nucleos, os dois usam as
# mesmas CPUs em cada ponto (metade dos ranks/threads em cada socket):
#
#   total | MPI puro (ranks/no)     | hibrido 4x (1 rank/no)   | hibrido 8x (1 rank/socket)
#     4   | 1 por no                | 4 x 1 thread             |
#     8   | 2 por no, 1 por socket  | 4 x 2 threads            |
#    16   | 4 por no, 2 por socket  | 4 x 4 threads            |
#    32   | 8 por no, 4 por socket  | 4 x 8 threads            | 8 x 4 threads
#    64   | 16 por no (HT)          | 4 x 16 threads (HT)      | 8 x 8 threads (HT)
#
# Variaveis: N=8192 IT=500 TOL=1e-6 REPS=3 LIMITE_REPS=300 TEMPO_MAX=1800
#            NOS=4 LOCAL=0 (1 = teste fora do cluster, sem afinidade)
set -uo pipefail
cd "$(dirname "$0")"

N=${N:-8192}; IT=${IT:-500}; TOL=${TOL:-1e-6}
REPS=${REPS:-3}; LIMITE_REPS=${LIMITE_REPS:-300}; TEMPO_MAX=${TEMPO_MAX:-1800}
NOS=${NOS:-4}; LOCAL=${LOCAL:-0}
MODO=${1:-medir}
mkdir -p resultados
OUT=resultados/tempos.csv

# roda VERSAO TOTAL_PROCS THREADS args...  -> executa com o mapeamento certo
roda() {
    local v=$1 np=$2 t=$3; shift 3
    if [ "$v" = seq ]; then timeout "$TEMPO_MAX" ./jacobi_seq "$@"; return; fi
    local k=$(( np / NOS )) flags=(--oversubscribe) env=(env OMP_NUM_THREADS="$t")
    if [ "$LOCAL" = 1 ]; then
        flags+=(--bind-to none)
    elif [ "${SEM_AFINIDADE:-0}" = 1 ]; then   # plano B: so distribui por no
        flags+=(--map-by ppr:$k:node --bind-to none)
    elif [ "$v" = mpi ]; then
        if   [ "$k" -le 1 ];  then flags+=(--map-by ppr:1:node --bind-to core)
        elif [ "$k" -le 8 ];  then flags+=(--map-by ppr:$((k / 2)):socket --bind-to core)
        else                       flags+=(--map-by ppr:$((k / 2)):socket --use-hwthread-cpus --bind-to hwthread)
        fi
    elif [ "$k" -le 1 ]; then  # hibrido, 1 rank por no: o rank fica solto e o OpenMP fixa as threads
        flags+=(--map-by ppr:1:node --bind-to none)
        if [ "$t" -le 8 ]; then env+=(OMP_PLACES=cores); else env+=(OMP_PLACES=threads); fi
        env+=(OMP_PROC_BIND=close)
    else                       # hibrido, 1 rank por socket, preso aos 4 nucleos (8 HT) dele
        # (--bind-to socket deixava o rank SEM afinidade no Open MPI 4: as threads
        #  dos dois ranks do no caiam nos mesmos nucleos. pe=4 prende de fato.)
        flags+=(--map-by ppr:1:socket:pe=4 --bind-to core)
        if [ "$t" -le 4 ]; then env+=(OMP_PLACES=cores); else env+=(OMP_PLACES=threads); fi
        env+=(OMP_PROC_BIND=close)
    fi
    local x=(); for e in "${env[@]:1}"; do x+=(-x "${e%%=*}"); done
    timeout "$TEMPO_MAX" "${env[@]}" mpirun "${flags[@]}" "${x[@]}" -np "$np" "./jacobi_$v" "$@"
}

# mediana VERSAO NP T -> linha da mediana + ;reps;tmin;tmax (tempo = campo 6)
mediana() {
    local i linha tt saida=()
    for ((i = 0; i < REPS; i++)); do
        linha=$(roda "$@" -n "$N" -i "$IT" -t "$TOL" | tail -1) || return 1
        [ -n "$linha" ] || return 1
        saida+=("$linha")
        tt=$(echo "$linha" | cut -d';' -f6)
        awk -v t="$tt" -v l="$LIMITE_REPS" 'BEGIN{exit !(t > l)}' && break
    done
    printf '%s\n' "${saida[@]}" | sort -t';' -k6 -g |
        awk -F';' '{l[NR]=$0; t[NR]=$6} END {print l[int((NR+1)/2)] ";" NR ";" t[1] ";" t[NR]}'
}

# CONFIG VERSAO TOTAL THREADS_POR_RANK
CONFIGS=(
  "seq      seq 1  1"
  "mpi      mpi 4  1"  "mpi mpi 8 1"  "mpi mpi 16 1"  "mpi mpi 32 1"  "mpi mpi 64 1"
  "hib-no   hib 4  1"  "hib-no hib 4 2"  "hib-no hib 4 4"  "hib-no hib 4 8"  "hib-no hib 4 16"
  "hib-sock hib 8  4"  "hib-sock hib 8 8"
)

if [ "$MODO" = mapa ]; then
    : > resultados/mapa.txt
    for c in "${CONFIGS[@]:1}"; do
        set -- $c
        echo "== $1 np=$3 threads=$4" | tee -a resultados/mapa.txt
        err=$(roda "$2" "$3" "$4" -n 512 -i 2 -t 0 -m 2>&1 >/dev/null)
        echo "$err" | grep '^mapa' | sort -t= -k2,2n -k3,3n | awk '{print "   " $0}' >> resultados/mapa.txt
        echo "$err" | grep -v '^mapa' | head -8   # erros do mpirun, se houver
    done
    echo "mapeamento em resultados/mapa.txt"
    exit 0
fi

[ -s "$OUT" ] && mv "$OUT" "$OUT.$(date +%Y%m%d-%H%M%S)"   # rodada nova nao se mistura com a velha
echo 'config;versao;procs;threads;n;iter;tempo;calc;red;halo;calc_max;delta;soma;reps;tmin;tmax' > "$OUT"
echo "N=$N IT=$IT TOL=$TOL REPS=$REPS  ($(date))"
for c in "${CONFIGS[@]}"; do
    set -- $c
    printf '%-9s np=%-3s t=%-3s ' "$1" "$3" "$4"
    if linha=$(mediana "$2" "$3" "$4"); then
        echo "$1;$linha" >> "$OUT"
        echo "tempo=$(echo "$linha" | cut -d';' -f6)s  calc=$(echo "$linha" | cut -d';' -f7)  red=$(echo "$linha" | cut -d';' -f8)  halo=$(echo "$linha" | cut -d';' -f9)"
    elif [ "$2" != seq ] && linha=$(SEM_AFINIDADE=1 mediana "$2" "$3" "$4"); then
        echo "$1-semaf;$linha" >> "$OUT"
        echo "tempo=$(echo "$linha" | cut -d';' -f6)s  (SEM AFINIDADE: o mapeamento normal falhou)"
    else
        echo "FALHOU (erro ou mais de ${TEMPO_MAX}s)"
    fi
done
echo "fim $(date)"
