#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ANÁLISE DE SAÚDE do MegaSim — caça FALHAS, ERROS e MELHORIAS numa
campanha massiva (1000 jogos, 195 nações, 2000→2100). Consolida:
  1. Anomalias/crashes (NaN, PIB≤0, jogos incompletos)
  2. Desfechos (vitórias/mortes/timeout) e se fazem sentido
  3. Outliers extremos (PIB runaway, inflação travada, dívida infinita)
  4. Cobertura de eventos/decisões/storylines/conquistas
  5. Balanceamento por tier + por nação (quem nunca vence? quem sempre morre?)
  6. Performance (ms/turno)
Rodar: python analyze_health.py
"""
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

def pct(a, b): return 100.0 * a / b if b else 0.0
def p(rows, k, d=0.0): return [r.get(k, d) for r in rows]

def main():
    rows = load()
    n = len(rows)
    if not n:
        print("Sem resultados — o MegaSim ainda não terminou ou não escreveu."); return
    print(f"\n{'='*66}\n  ANÁLISE DE SAÚDE — {n} campanhas completas (2000→2100)\n{'='*66}")

    # ── 1. INTEGRIDADE (o mais importante — bugs de verdade) ──
    print("\n── 1. INTEGRIDADE (crashes / anomalias) ──")
    anom = [r for r in rows if r.get("anomaly", "")]
    incompletos = [r for r in rows if r.get("turns", 0) < 1100]  # deveria rodar ~1200
    print(f"  anomalias reportadas: {len(anom)} ({pct(len(anom),n):.2f}%)")
    if anom:
        by_type = Counter(r["anomaly"] for r in anom)
        for k, v in by_type.most_common(10):
            print(f"     ⚠ {k}: {v}x")
        for r in anom[:5]:
            print(f"        ex: {r['code']} tier={r.get('tier','?')} turno={r.get('turns','?')} outcome={r.get('outcome','?')}")
    print(f"  jogos incompletos (<1100 turnos): {len(incompletos)} ({pct(len(incompletos),n):.2f}%)")
    # NaN/valores impossíveis remanescentes
    bad = [r for r in rows if any(
        isinstance(r.get(k), float) and (r[k] != r[k] or abs(r[k]) == float('inf'))
        for k in ("pib_f", "growth_x", "max_infl", "divida_f", "min_tes"))]
    print(f"  valores NaN/inf nos campos-chave: {len(bad)}")

    # ── 2. DESFECHOS ──
    print("\n── 2. DESFECHOS ──")
    oc = Counter(r["outcome"] for r in rows)
    for k, v in oc.most_common():
        print(f"  {k:<24} {v:>5} ({pct(v,n):5.1f}%)")
    wins = sum(v for k, v in oc.items() if k in WINS)
    deaths = sum(v for k, v in oc.items() if k in DEATHS)
    print(f"  → vitórias {pct(wins,n):.1f}% · mortes {pct(deaths,n):.1f}% · resto (sobrevive) {pct(n-wins-deaths,n):.1f}%")

    # ── 3. OUTLIERS EXTREMOS (sinais de balanceamento quebrado) ──
    print("\n── 3. OUTLIERS EXTREMOS ──")
    growth = p(rows, "growth_x", 1.0)
    gs = sorted(growth)
    print(f"  crescimento (growth_x): med={st.median(growth):.0f}× p99={gs[int(.99*(n-1))]:.0f}× max={max(growth):.0f}×")
    runaway = [r for r in rows if r.get("growth_x", 1) > 20000]
    print(f"     runaway (>20000×): {len(runaway)} ({pct(len(runaway),n):.2f}%)" + (" ⚠" if len(runaway) > n*0.01 else ""))
    shrink = [r for r in rows if r.get("growth_x", 1) < 0.2]
    print(f"     colapso econômico (<0.2×): {len(shrink)} ({pct(len(shrink),n):.2f}%)")
    infl = p(rows, "max_infl", 0.0)
    print(f"  inflação máxima: med={st.median(infl):.0f}% p99={sorted(infl)[int(.99*(n-1))]:.0f}% max={max(infl):.0f}%")
    hyper = [r for r in rows if r.get("max_infl", 0) >= 100.0]
    print(f"     inflação cravada em 100% (teto): {len(hyper)} ({pct(len(hyper),n):.2f}%)")
    debt = p(rows, "divida_f", 0.0)
    print(f"  dívida final: med={st.median(debt):.0f} p99={sorted(debt)[int(.99*(n-1))]:.0f} max={max(debt):.0f}")

    # ── 4. COBERTURA DE CONTEÚDO (eventos/decisões/storylines/conquistas) ──
    print("\n── 4. COBERTURA DE CONTEÚDO ──")
    dec = p(rows, "decisions", 0)
    print(f"  decisões/storylines por jogo: med={st.median(dec):.0f} max={max(dec)} · jogos com 0 decisões: {sum(1 for d in dec if d==0)} ({pct(sum(1 for d in dec if d==0),n):.0f}%)")
    achv = p(rows, "achv", 0)
    print(f"  conquistas/jogo: med={st.median(achv):.0f} max={max(achv)} · jogos com 0: {sum(1 for a in achv if a==0)} ({pct(sum(1 for a in achv if a==0),n):.0f}%)")
    wars = p(rows, "wars", 0)
    print(f"  guerras/jogo: med={st.median(wars):.0f} p90={sorted(wars)[int(.9*(n-1))]} max={max(wars)}")
    treaties = p(rows, "treaties", 0)
    print(f"  tratados/jogo: med={st.median(treaties):.0f} max={max(treaties)}")
    techs = p(rows, "techs", 0)
    print(f"  techs concluídas: med={st.median(techs):.0f} max={max(techs)} · jogos com 0 tech: {sum(1 for t in techs if t==0)} ({pct(sum(1 for t in techs if t==0),n):.0f}%)")

    # ── 5. BALANCEAMENTO POR TIER ──
    print("\n── 5. BALANCEAMENTO POR TIER ──")
    by_tier = defaultdict(list)
    for r in rows: by_tier[r.get("tier", "?")].append(r)
    for tier in ["FACIL", "NORMAL", "DIFICIL", "MUITO_DIFICIL", "QUASE_IMPOSSIVEL"]:
        rs = by_tier.get(tier, [])
        if not rs: continue
        w = pct(sum(1 for r in rs if r["outcome"] in WINS), len(rs))
        d = pct(sum(1 for r in rs if r["outcome"] in DEATHS), len(rs))
        g = st.median([r.get("growth_x", 1) for r in rs])
        print(f"  {tier:<16} n={len(rs):<4} vitória={w:5.1f}% morte={d:4.1f}% growth_med={g:.0f}×")

    # ── 6. NAÇÕES PROBLEMÁTICAS (nunca vencem / sempre morrem) ──
    print("\n── 6. NAÇÕES OUTLIER (por código) ──")
    by_code = defaultdict(list)
    for r in rows: by_code[r["code"]].append(r)
    never_win, always_die, runaway_nat = [], [], []
    for code, rs in by_code.items():
        if len(rs) < 3: continue
        w = sum(1 for r in rs if r["outcome"] in WINS)
        d = sum(1 for r in rs if r["outcome"] in DEATHS)
        rw = sum(1 for r in rs if r.get("growth_x", 1) > 20000)
        if d == len(rs): always_die.append((code, len(rs)))
        if rw > len(rs) * 0.5: runaway_nat.append((code, rw, len(rs)))
    print(f"  nações que SEMPRE morrem (todas as partidas): {len(always_die)}")
    for code, cnt in always_die[:12]:
        print(f"     ✗ {code} ({cnt} jogos, 100% morte)")
    print(f"  nações com PIB runaway em >50% dos jogos: {len(runaway_nat)}")
    for code, rw, tot in runaway_nat[:12]:
        print(f"     ⚠ {code} ({rw}/{tot} jogos com runaway)")

    # ── 7. PERFORMANCE ──
    print("\n── 7. PERFORMANCE ──")
    mst = [r.get("ms_turn", 0) for r in rows if r.get("ms_turn", 0) > 0]
    if mst:
        print(f"  ms/turno: med={st.median(mst):.1f}ms p99={sorted(mst)[int(.99*(len(mst)-1))]:.1f}ms max={max(mst):.1f}ms")

    # ── VEREDITO ──
    print(f"\n{'='*66}\n  VEREDITO\n{'='*66}")
    v = []
    if len(anom) == 0: v.append("✓ ZERO anomalias/crashes em %d jogos — motor sólido" % n)
    else: v.append("⚠ %d anomalias (%.2f%%) — INVESTIGAR" % (len(anom), pct(len(anom),n)))
    if len(incompletos) == 0: v.append("✓ todos os jogos completaram os ~1200 turnos")
    else: v.append("⚠ %d jogos incompletos — possível travamento" % len(incompletos))
    if len(runaway) <= n*0.01: v.append("✓ PIB runaway sob controle (%.2f%%)" % pct(len(runaway),n))
    else: v.append("⚠ PIB runaway em %.1f%% — cap pode estar furado" % pct(len(runaway),n))
    if 8 <= pct(wins,n) <= 40: v.append("✓ taxa de vitória global saudável (%.0f%%)" % pct(wins,n))
    else: v.append("⚠ taxa de vitória %.0f%% (esperado 8-40%% em cobertura total)" % pct(wins,n))
    if len(always_die) == 0: v.append("✓ nenhuma nação é injogável (sempre morre)")
    else: v.append("⚠ %d nações sempre morrem — injogáveis" % len(always_die))
    for x in v: print(f"  {x}")

if __name__ == "__main__":
    main()
