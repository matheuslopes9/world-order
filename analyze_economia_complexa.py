#!/usr/bin/env python3
"""Análise da COMPLEXIDADE ECONÔMICA (raw vs processed) no MegaSim.
Responde: o ECS está distribuído de forma saudável? É complementar (não domina)?
A volatilidade de commodity correlaciona com economias pobres/dependentes?
Comparado ao balanceamento anterior, a economia continua sã (0 anomalias, curva de tier)."""
import json, glob, os, statistics as st
from collections import Counter, defaultdict

USERDIR = os.path.expanduser("~/AppData/Roaming/Godot/app_userdata/Nations- New Dawn")
WINS = {"POTÊNCIA DO SÉCULO", "HEGEMONIA"}
DEATHS = {"REVOLUÇÃO", "GOLPE DE ESTADO", "FALÊNCIA NACIONAL", "HIPERINFLAÇÃO"}

def load():
    rows = []
    for path in sorted(glob.glob(os.path.join(USERDIR, "megasim_shard_*.json"))):
        with open(path, encoding="utf-8") as f:
            rows.extend(json.load(f).get("results", []))
    return rows

def pct(a, b): return 100.0*a/b if b else 0.0

def main():
    rows = load()
    n = len(rows)
    if not n:
        print("Sem resultados."); return
    print(f"===== COMPLEXIDADE ECONÔMICA — {n} campanhas =====\n")

    ecs = [r.get("ecs_f", 0.0) for r in rows if "ecs_f" in r]
    vol = [r.get("commodity_vol_f", 0.0) for r in rows if "commodity_vol_f" in r]
    if not ecs:
        print("⚠ Campos ecs_f ausentes — rode o MegaSim novo."); return

    # 1. DISTRIBUIÇÃO DO ECS (deve variar; não todos iguais)
    print("── 1. DISTRIBUIÇÃO DO ECS (0-100) ──")
    ecs_s = sorted(ecs)
    print(f"  min={min(ecs):.0f}  p10={ecs_s[int(.1*(len(ecs)-1))]:.0f}  med={st.median(ecs):.0f}  "
          f"p90={ecs_s[int(.9*(len(ecs)-1))]:.0f}  max={max(ecs):.0f}  desvio={st.pstdev(ecs):.1f}")
    faixas = Counter()
    for e in ecs:
        if e >= 80: faixas["Muito Alta (80+)"] += 1
        elif e >= 62: faixas["Alta (62-79)"] += 1
        elif e >= 45: faixas["Média (45-61)"] += 1
        elif e >= 28: faixas["Baixa (28-44)"] += 1
        else: faixas["Muito Baixa (<28)"] += 1
    for k in ["Muito Alta (80+)","Alta (62-79)","Média (45-61)","Baixa (28-44)","Muito Baixa (<28)"]:
        print(f"    {k:<20} {faixas.get(k,0):>4} ({pct(faixas.get(k,0),len(ecs)):4.1f}%)")

    # 2. ECS × VITÓRIA (complexidade ajuda, mas não é determinística — complementar)
    print("\n── 2. ECS vs DESFECHO (complexidade é vantagem, não garantia) ──")
    win_ecs = [r.get("ecs_f",0) for r in rows if r["outcome"] in WINS]
    loss_ecs = [r.get("ecs_f",0) for r in rows if r["outcome"] in DEATHS]
    all_ecs_med = st.median(ecs)
    if win_ecs:
        print(f"  ECS mediano de quem VENCEU:  {st.median(win_ecs):.0f}  (vs geral {all_ecs_med:.0f})")
    if loss_ecs:
        print(f"  ECS mediano de quem MORREU:  {st.median(loss_ecs):.0f}")
    # correlação grosseira growth_x vs ECS
    pares = [(r.get("ecs_f",0), r.get("growth_x",1)) for r in rows]
    hi = [g for e,g in pares if e >= 60]
    lo = [g for e,g in pares if e < 40]
    if hi and lo:
        print(f"  crescimento mediano — ECS alto (≥60): {st.median(hi):.0f}×  |  ECS baixo (<40): {st.median(lo):.0f}×")

    # 3. VOLATILIDADE DE COMMODITY (deve ser MAIOR em economias pobres/dependentes)
    print("\n── 3. VOLATILIDADE DE COMMODITY (0-1) ──")
    if vol:
        vol_s = sorted(vol)
        print(f"  min={min(vol):.2f}  med={st.median(vol):.2f}  p90={vol_s[int(.9*(len(vol)-1))]:.2f}  max={max(vol):.2f}")
        # infl máxima em alta vs baixa volatilidade
        hi_v = [r.get("max_infl",0) for r in rows if r.get("commodity_vol_f",0) >= 0.5]
        lo_v = [r.get("max_infl",0) for r in rows if r.get("commodity_vol_f",0) < 0.2]
        if hi_v and lo_v:
            print(f"  inflação máx mediana — vol alta (≥0.5): {st.median(hi_v):.0f}%  |  vol baixa (<0.2): {st.median(lo_v):.0f}%")

    # 4. SANIDADE GERAL (a economia nova não quebrou o balanceamento?)
    print("\n── 4. SANIDADE (economia continua sã?) ──")
    oc = Counter(r["outcome"] for r in rows)
    wins = sum(v for k,v in oc.items() if k in WINS)
    deaths = sum(v for k,v in oc.items() if k in DEATHS)
    print(f"  vitórias: {pct(wins,n):.1f}%  |  mortes: {pct(deaths,n):.1f}%")
    growth = [r.get("growth_x",1) for r in rows]
    runaway = sum(1 for g in growth if g > 50000)
    print(f"  crescimento mediano: {st.median(growth):.0f}×  |  runaway (>50000×): {runaway}")
    infl_hyper = sum(1 for r in rows if r.get("max_infl",0) > 90)
    print(f"  inflação >90% (risco hiper): {infl_hyper} ({pct(infl_hyper,n):.1f}%)")
    # curva de tier
    by_tier = defaultdict(list)
    for r in rows: by_tier[r.get("tier","?")].append(r)
    print("  curva de tier (vitória%):", end=" ")
    for tier in ["FACIL","NORMAL","DIFICIL","MUITO_DIFICIL","QUASE_IMPOSSIVEL"]:
        rs = by_tier.get(tier, [])
        if rs:
            w = pct(sum(1 for r in rs if r["outcome"] in WINS), len(rs))
            print(f"{tier[:4]}={w:.0f}%", end="  ")
    print()

    # VEREDITO
    print("\n── VEREDITO ──")
    v = []
    if st.pstdev(ecs) >= 8:
        v.append(f"✓ ECS bem distribuído (desvio {st.pstdev(ecs):.0f}) — nações diferem em complexidade")
    else:
        v.append(f"⚠ ECS pouco variável (desvio {st.pstdev(ecs):.0f}) — todos parecidos?")
    if win_ecs and loss_ecs and st.median(win_ecs) > st.median(loss_ecs):
        v.append(f"✓ complexidade é vantagem (vencedor ECS {st.median(win_ecs):.0f} > morto {st.median(loss_ecs):.0f})")
    if vol and hi_v and lo_v and st.median(hi_v) > st.median(lo_v):
        v.append("✓ volatilidade de commodity gera mais inflação (mecânica ativa)")
    if runaway == 0:
        v.append("✓ sem runaway de PIB — economia nova não desestabilizou o crescimento")
    for x in v: print(f"  {x}")

if __name__ == "__main__":
    main()
