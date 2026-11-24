#!/usr/bin/env bash
#SBATCH --job-name=jacobi-g20
#SBATCH --nodes=4
#SBATCH --exclusive
#SBATCH --time=01:30:00
#SBATCH --output=slurm-%j.out
#
# 4 nos exclusivos da atlantica: compila, testa a corretude, registra o
# mapeamento de processos/threads e roda a bateria completa.
#   sbatch job.sh                       (N=8192, 500 iteracoes)
#   N=4096 IT=500 sbatch job.sh         (outro tamanho)
# acompanhar:  squeue -u $USER ; tail -f slurm-*.out
set -uo pipefail
cd "$SLURM_SUBMIT_DIR"
mkdir -p resultados
{ echo "nos: $SLURM_JOB_NODELIST"; LC_ALL=C lscpu; free -g; gcc --version | head -1;
  mpirun --version 2>&1 | head -1; } > resultados/maquina.txt 2>&1

make || exit 1
make teste || { echo "TESTE DE CORRETUDE FALHOU: abortando"; exit 1; }
./medir.sh mapa
./medir.sh
python3 analisar.py || true
