# Trabalho 4 - Computacao Paralela - Grupo 20
# Mesmo fonte e mesmas flags nas tres versoes: o MPI acrescenta -DPARALELO e o
# hibrido acrescenta -fopenmp. Sem -fopenmp os #pragma omp sao ignorados.

CC      = gcc
MPICC   = mpicc
CFLAGS  = -O2 -Wall -Wextra -std=gnu11 -Wno-unknown-pragmas
LDLIBS  = -lm

all: jacobi_seq jacobi_mpi jacobi_hib

jacobi_seq: jacobi.c
	$(CC) $(CFLAGS) -o $@ $< $(LDLIBS)

jacobi_mpi: jacobi.c
	$(MPICC) $(CFLAGS) -DPARALELO -o $@ $< $(LDLIBS)

jacobi_hib: jacobi.c
	$(MPICC) $(CFLAGS) -DPARALELO -fopenmp -o $@ $< $(LDLIBS)

# Corretude: MPI e hibrido tem de dar o mesmo numero de iteracoes, o mesmo
# delta (bit a bit) e a mesma soma (ate 1e-9 relativo) que o sequencial.
teste: all
	./teste.sh

clean:
	rm -f jacobi_seq jacobi_mpi jacobi_hib

.PHONY: all teste clean
