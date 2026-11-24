#!/usr/bin/env python3
"""Tabelas e graficos do T4 a partir de resultados/tempos.csv.

  python3 analisar.py [pasta]      (padrao: resultados)

Gera na pasta:
  tabelas.txt        speed-up, eficiencia e divisao do tempo por fase
  tab_escala.tex     tabela para o relatorio
  grafico_escala.*   escalabilidade forte: speed-up e eficiencia (MPI x hibrido)
  grafico_fases.*    tempo medio por fase (calculo, verificacao, troca de bordas)
Os graficos so saem se o matplotlib estiver instalado.
"""
import csv
import os
import sys

PASTA = sys.argv[1] if len(sys.argv) > 1 else "resultados"
ROTULO = {"mpi": "MPI puro", "hib-no": "Híbrido (1 proc/nó)", "hib-sock": "Híbrido (1 proc/socket)"}
COR = {"mpi": "#1f6feb", "hib-no": "#d1495b", "hib-sock": "#2a9d4b"}
MARCA = {"mpi": "o", "hib-no": "s", "hib-sock": "^"}


def ler():
    linhas = []
    with open(os.path.join(PASTA, "tempos.csv")) as f:
        for r in csv.DictReader(f, delimiter=";"):
            for k in ("procs", "threads", "n", "iter", "reps"):
                r[k] = int(r[k])
            for k in ("tempo", "calc", "red", "halo", "calc_max", "delta", "soma", "tmin", "tmax"):
                r[k] = float(r[k])
            r["base"] = r["config"].replace("-semaf", "")
            linhas.append(r)
    return linhas


def main():
    dados = ler()
    seq = next(r for r in dados if r["versao"] == "seq")
    t1 = seq["tempo"]
    n = seq["n"]
    linha_bytes = (n + 2) * 8

    saida = []
    p = saida.append
    p(f"N={n} ({n}x{n} pontos), {seq['iter']} iteracoes, sequencial = {t1:.2f} s")
    p(f"cada linha de borda trocada = {linha_bytes / 1024:.1f} KiB\n")
    p(f"{'config':<14}{'procs':>6}{'thr':>5}{'nucleos':>8}{'tempo(s)':>10}{'S':>7}{'E':>7}"
      f"{'calc%':>7}{'verif%':>7}{'bordas%':>8}{'desbal%':>8}{'msg/it':>7}{'MiB/it':>7}  ok")
    tex = []
    for r in dados:
        nuc = r["procs"] * r["threads"]
        s = t1 / r["tempo"]
        e = s / nuc
        tot = r["calc"] + r["red"] + r["halo"] or 1
        desbal = (r["calc_max"] / r["calc"] - 1) * 100 if r["calc"] else 0
        msgs = 2 * (r["procs"] - 1)
        mib = msgs * linha_bytes / 2**20
        ok = (r["iter"] == seq["iter"] and r["delta"] == seq["delta"]
              and abs(r["soma"] - seq["soma"]) <= 1e-9 * abs(seq["soma"]))
        r.update(nuc=nuc, s=s, e=e)
        p(f"{r['config']:<14}{r['procs']:>6}{r['threads']:>5}{nuc:>8}{r['tempo']:>10.2f}{s:>7.2f}{e:>7.2f}"
          f"{100 * r['calc'] / tot:>7.1f}{100 * r['red'] / tot:>7.1f}{100 * r['halo'] / tot:>8.1f}"
          f"{desbal:>8.1f}{msgs:>7}{mib:>7.2f}  {'sim' if ok else 'NAO'}")
        if r["versao"] != "seq":
            tex.append(f"{ROTULO[r['base']]} & {r['procs']} & {r['threads']} & {nuc} & {r['tempo']:.2f} & "
                       f"{s:.2f} & {100 * e:.0f}\\% & {100 * r['calc'] / tot:.0f} / {100 * r['red'] / tot:.0f} / "
                       f"{100 * r['halo'] / tot:.0f} \\\\")
    texto = "\n".join(saida)
    print(texto)
    with open(os.path.join(PASTA, "tabelas.txt"), "w") as f:
        f.write(texto + "\n")
    with open(os.path.join(PASTA, "tab_escala.tex"), "w") as f:
        f.write("\\begin{tabular}{lrrrrrrc}\n\\toprule\n"
                "Versão & proc. & thr. & núcleos & tempo (s) & S & E & calc / verif / bordas (\\%) \\\\\n\\midrule\n"
                f"Sequencial & 1 & 1 & 1 & {t1:.2f} & 1,00 & 100\\% & 100 / 0 / 0 \\\\\n"
                + "\n".join(tex).replace(".", ",") + "\n\\bottomrule\n\\end{tabular}\n")

    try:
        import matplotlib
        import matplotlib.ticker
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("\nmatplotlib ausente: graficos nao gerados (rode na maquina local)")
        return

    plt.rcParams.update({"font.size": 9})
    # --- escalabilidade forte -------------------------------------------------
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(7.2, 2.9))
    xs_ideal = [1, 4, 8, 16, 32, 64]
    ax1.plot(xs_ideal, xs_ideal, "--", color="gray", lw=1, label="Ideal")
    ax2.axhline(1.0, ls="--", color="gray", lw=1)
    for cfg in ("mpi", "hib-no", "hib-sock"):
        pts = sorted((r for r in dados if r["base"] == cfg), key=lambda r: r["nuc"])
        if not pts:
            continue
        x = [r["nuc"] for r in pts]
        kw = dict(color=COR[cfg], marker=MARCA[cfg], ms=4, lw=1.5, label=ROTULO[cfg])
        ax1.plot(x, [r["s"] for r in pts], **kw)
        ax2.plot(x, [r["e"] for r in pts], **kw)
    for ax in (ax1, ax2):
        ax.axvspan(32, 64, color="#f2e8cf", alpha=0.6, lw=0)
        ax.set_xscale("log")   # sem base=2: o matplotlib 3.1 do cluster nao aceita
        ax.xaxis.set_minor_locator(matplotlib.ticker.NullLocator())
        ax.set_xticks([4, 8, 16, 32, 64])
        ax.set_xticklabels(["4", "8", "16", "32", "64\n(HT)"])
        ax.set_xlabel("núcleos (processos × threads)")
        ax.grid(alpha=0.3)
    ax1.set_ylabel("Speed-up")
    ax1.set_title("Speed-up (escalabilidade forte)")
    ax2.set_ylabel("Eficiência")
    ax2.set_title("Eficiência")
    ax2.set_ylim(0, 1.15)
    ax1.legend(fontsize=7, loc="upper left")
    fig.tight_layout()
    for ext in ("pdf", "png"):
        fig.savefig(os.path.join(PASTA, f"grafico_escala.{ext}"), dpi=200)
    plt.close(fig)

    # --- tempo por fase -------------------------------------------------------
    par = [r for r in dados if r["versao"] != "seq"]
    par.sort(key=lambda r: (r["nuc"], ["mpi", "hib-no", "hib-sock"].index(r["base"])))
    rot = [f"{'MPI' if r['base'] == 'mpi' else ('H-nó' if r['base'] == 'hib-no' else 'H-sk')}\n"
           f"{r['procs']}×{r['threads']}" for r in par]
    fig, ax = plt.subplots(figsize=(7.2, 2.6))
    x = range(len(par))
    tot = [(r["calc"] + r["red"] + r["halo"]) or 1 for r in par]
    c = [100 * r["calc"] / t for r, t in zip(par, tot)]
    v = [100 * r["red"] / t for r, t in zip(par, tot)]
    h = [100 * r["halo"] / t for r, t in zip(par, tot)]
    ax.bar(x, c, color="#8ecae6", label="cálculo local")
    ax.bar(x, v, bottom=c, color="#fb8500", label="verificação (Allreduce)")
    ax.bar(x, h, bottom=[a + b for a, b in zip(c, v)], color="#6a4c93", label="troca de bordas")
    ax.set_xticks(list(x))
    ax.set_xticklabels(rot, fontsize=7)
    ax.set_ylabel("% do tempo (média dos processos)")
    ax.set_ylim(0, 100)
    ax.set_title("Divisão do tempo por fase")
    ax.legend(fontsize=7, loc="lower left", framealpha=0.9)
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    for ext in ("pdf", "png"):
        fig.savefig(os.path.join(PASTA, f"grafico_fases.{ext}"), dpi=200)
    plt.close(fig)
    print(f"\ngraficos em {PASTA}/grafico_escala.* e {PASTA}/grafico_fases.*")


if __name__ == "__main__":
    main()
