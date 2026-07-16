#!/usr/bin/env python3
"""Analisa o MegaSim caçando FALHAS por nação: anomalias, colapsos precoces,
outliers de balanceamento (PIB runaway/morto, dívida explosiva, inflação, etc.)."""
import json, glob, os, statistics as st
from collections import defaultdict, Counter

USERDIR = os.path.expanduser("~/AppData/Roaming/Godot/app_userdata/Nations- New Dawn")

def load():
    rows = []
    for path in sorted(glob.glob(os.path.join(USERDIR, "megasim_shard_*.json"))):
        with open(path, encoding="utf-8") as f:
            rows.extend(json.load(f).get("results", []))
    return rows

def main():
    rows = load()
    n = len(rows)
    if not n:
        print("Sem resultados."); return
    print(f"===== CAÇA A FALHAS — {n} partidas, {len(set(r['code'] for r in rows))} nações distintas =====\n")

    # 1. ANOMALIAS (crash/NaN/PIB runaway) — falha grave
    anoms = [r for r in rows if r.get("anomaly")]
    print(f"── 1. ANOMALIAS: {len(anoms)} ({100*len(anoms)/n:.1f}%) ──")
    by_code_anom = Counter(r["code"] for r in anoms)
    for code, c in by_code_anom.most_common(20):
        ex = next(r for r in anoms if r["code"] == code)
        print(f"  {code} ×{c}: {ex.get('anomaly','')}")
    if not anoms: print("  (nenhuma — ótimo)")

    # 2. MORTES / desfechos não-neutros por nação
    print("\n── 2. DESFECHOS ──")
    oc = Counter(r["outcome"] for r in rows)
    for k, v in oc.most_common():
        print(f"  {k:<22} {v:>4} ({100*v/n:4.1f}%)")
    deaths = [r for r in rows if r["outcome"] not in ("LEGADO DO SÉCULO","POTÊNCIA DO SÉCULO","HEGEMONIA")]
    death_by_code = Counter(r["code"] for r in deaths)
    if death_by_code:
        print("  nações que mais MORREM:")
        for code, c in death_by_code.most_common(15):
            print(f"    {code}: {c} mortes")

    # 3. PIB MORTO (nação encolheu ou mal cresceu) — growth_x < 1 é encolhimento real
    print("\n── 3. PIB MORTO (growth_x < 1.0 = encolheu no século) ──")
    dead = [r for r in rows if r["growth_x"] < 1.0]
    dbc = Counter(r["code"] for r in dead)
    print(f"  {len(dead)} partidas encolheram ({100*len(dead)/n:.1f}%)")
    for code, c in dbc.most_common(15):
        ex = [r for r in dead if r["code"]==code]
        print(f"    {code}: {c}× (growth med {st.median([r['growth_x'] for r in ex]):.2f})")

    # 4. PIB RUNAWAY (cauda extrema, > 20000×)
    print("\n── 4. PIB RUNAWAY (growth_x > 20000×) ──")
    runaway = sorted([r for r in rows if r["growth_x"] > 20000], key=lambda r:-r["growth_x"])
    print(f"  {len(runaway)} partidas")
    for r in runaway[:15]:
        print(f"    {r['code']} {r['persona']}: {r['growth_x']:.0f}× (PIB final ${r['pib_f']:,.0f}B)")

    # 5. DÍVIDA EXPLOSIVA (pico > 5000)
    print("\n── 5. DÍVIDA EXPLOSIVA (max_debt > 5000) ──")
    debt = sorted([r for r in rows if r["max_debt"] > 5000], key=lambda r:-r["max_debt"])
    dbc2 = Counter(r["code"] for r in debt)
    print(f"  {len(debt)} partidas; nações recorrentes: {dict(dbc2.most_common(8))}")

    # 6. INFLAÇÃO DESCONTROLADA (pico > 40)
    print("\n── 6. INFLAÇÃO ALTA (max_infl > 40) ──")
    infl = [r for r in rows if r["max_infl"] > 40]
    ibc = Counter(r["code"] for r in infl)
    print(f"  {len(infl)} partidas; nações: {dict(ibc.most_common(10))}")

    # 7. NAÇÕES SEM NENHUM SUCESSO (todas as partidas terminam mal/mortas)
    print("\n── 7. NAÇÕES FRÁGEIS (nunca chegam a Potência/Hegemonia) ──")
    by_code = defaultdict(list)
    for r in rows: by_code[r["code"]].append(r)
    frageis = []
    for code, rs in by_code.items():
        wins = sum(1 for r in rs if r["outcome"] in ("POTÊNCIA DO SÉCULO","HEGEMONIA"))
        deaths_c = sum(1 for r in rs if r["outcome"] not in ("LEGADO DO SÉCULO","POTÊNCIA DO SÉCULO","HEGEMONIA"))
        if wins == 0 and deaths_c > 0:
            frageis.append((code, len(rs), deaths_c, st.median([r["growth_x"] for r in rs])))
    frageis.sort(key=lambda x:-x[2])
    for code, tot, d, g in frageis[:20]:
        print(f"    {code}: {d}/{tot} mortes, growth med {g:.0f}")

    # 8. PERFORMANCE outliers
    print("\n── 8. PERFORMANCE (ms/turno) ──")
    ms = [r["ms_turn"] for r in rows]
    print(f"  med={st.median(ms):.1f}  p90={sorted(ms)[int(0.9*(len(ms)-1))]:.1f}  max={max(ms):.1f}")

    # Resumo de saúde
    print("\n── VEREDITO ──")
    print(f"  anomalias: {len(anoms)} | encolhimentos: {len(dead)} | runaway: {len(runaway)}")
    print(f"  dívida explosiva: {len(debt)} | inflação alta: {len(infl)} | nações frágeis: {len(frageis)}")

if __name__ == "__main__":
    main()
