# Um MPI_Allreduce em vez de np MPI_Bcast na verificação

O pseudocódigo faz a verificação com um `MPI_Bcast` por processo (np coletivas por iteração), cada um espalhando o estado de um processo. Usamos um único `MPI_Allreduce(MPI_MAX)` do delta: todos recebem o mesmo valor, decidem parar na mesma iteração, e a coletiva custa ~log₂ np etapas em vez de np. O resultado é o mesmo (o maior delta é o que decide), e a fase continua sendo uma comunicação coletiva, como pede o modelo.
