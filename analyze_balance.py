#!/usr/bin/env python3
"""Análise de BALANCEAMENTO do MegaSim: snowball, dificuldade por tier,
taxa/timing de vitória e derrota, thresholds. Responde às perguntas de tuning."""
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
    print(f"===== BALANCEAMENTO — {n} campanhas =====\n")

    # 1. DESFECHOS globais
    oc = Counter(r["outcome"] for r in rows)
    wins = sum(v for k,v in oc.items() if k in WINS) + oc.get("HEGEMONIA",0)
    heg = sum(1 for r in rows if r.get("heg_turn",0) > 0)
    deaths = sum(v for k,v in oc.items() if k in DEATHS)
    print("── 1. DESFECHOS ──")
    for k,v in oc.most_common():
        print(f"  {k:<22} {v:>4} ({pct(v,n):5.1f}%)")
    print(f"  → vitórias (Potência+): {pct(wins,n):.1f}% | hegemonias reais: {pct(heg,n):.1f}% | mortes: {pct(deaths,n):.1f}%")

    # 2. SNOWBALL — rank inicial vs final (jogador dispara e ninguém alcança?)
    print("\n── 2. SNOWBALL (rank de PIB: início → fim) ──")
    subiu = [r for r in rows if r.get("rank_f",999) < r.get("rank0",999)]
    desceu = [r for r in rows if r.get("rank_f",999) > r.get("rank0",999)]
    print(f"  subiram no ranking: {pct(len(subiu),n):.0f}% | desceram: {pct(len(desceu),n):.0f}%")
    # Quem começa no top-10 termina no top-10? (persistência = snowball)
    top10_ini = [r for r in rows if r.get("rank0",999) <= 10]
    if top10_ini:
        mantem = sum(1 for r in top10_ini if r.get("rank_f",999) <= 10)
        print(f"  começou top-10 → terminou top-10: {pct(mantem,len(top10_ini)):.0f}% ({len(top10_ini)} casos)")
    # Nações fora do top-30 conseguem chegar ao top-5? (viradas = anti-snowball saudável)
    fracos = [r for r in rows if r.get("rank0",999) > 30]
    if fracos:
        viraram = sum(1 for r in fracos if r.get("rank_f",999) <= 5)
        print(f"  começou fora do top-30 → terminou top-5 (virada épica): {pct(viraram,len(fracos)):.1f}% ({len(fracos)} casos)")
    # power_rank final distribuição
    prf = [r.get("power_rank_f",0) for r in rows if r.get("power_rank_f",0) > 0]
    if prf:
        print(f"  power_rank final: med={st.median(prf):.0f} p10={sorted(prf)[int(.1*(len(prf)-1))]} p90={sorted(prf)[int(.9*(len(prf)-1))]}")

    # 3. DIFICULDADE POR TIER (o tier importa? fácil ganha mais, difícil morre mais?)
    print("\n── 3. DIFICULDADE POR TIER ──")
    by_tier = defaultdict(list)
    for r in rows: by_tier[r.get("tier","?")].append(r)
    ordem = ["FACIL","NORMAL","DIFICIL","MUITO_DIFICIL","QUASE_IMPOSSIVEL"]
    for tier in ordem:
        rs = by_tier.get(tier, [])
        if not rs: continue
        w = pct(sum(1 for r in rs if r["outcome"] in WINS), len(rs))
        d = pct(sum(1 for r in rs if r["outcome"] in DEATHS), len(rs))
        g = st.median([r["growth_x"] for r in rs])
        print(f"  {tier:<16} n={len(rs):<4} vitória={w:5.1f}%  morte={d:4.1f}%  growth_med={g:.0f}")

    # 4. TIMING DE VITÓRIA (hegemonia cedo demais = trivial)
    print("\n── 4. TIMING DE VITÓRIA/DERROTA (em turnos) ──")
    heg_turns = [r["heg_turn"] for r in rows if r.get("heg_turn",0) > 0]
    if heg_turns:
        print(f"  hegemonia alcançada no turno: med={st.median(heg_turns):.0f} min={min(heg_turns)} (de 1200) — cedo demais se <300")
    death_turns = [r["turn"] for r in rows if r["outcome"] in DEATHS and r.get("turn",0)>0]
    if death_turns:
        early = sum(1 for t in death_turns if t < 120)
        print(f"  mortes: med turno={st.median(death_turns):.0f} | mortes precoces (<10 anos): {early} ({pct(early,len(death_turns)):.0f}% das mortes)")

    # 5. THRESHOLDS (inflação/dívida no limiar de derrota)
    print("\n── 5. THRESHOLDS DE DERROTA ──")
    infl_alta = sum(1 for r in rows if r["max_infl"] > 80)  # gatilho hiperinflação
    print(f"  campanhas que passaram de 80%% inflação (risco hiperinflação): {infl_alta} ({pct(infl_alta,n):.1f}%)")
    quase_falencia = sum(1 for r in rows if r["min_tes"] <= 0)
    print(f"  campanhas com tesouro zerado em algum momento: {quase_falencia} ({pct(quase_falencia,n):.0f}%)")

    # 6. GUERRA / DIPLOMACIA (blocos causaram guerra demais?)
    print("\n── 6. GUERRA / DIPLOMACIA ──")
    print(f"  guerras/jogador: med={st.median([r['wars'] for r in rows]):.0f} p90={sorted([r['wars'] for r in rows])[int(.9*(n-1))]} max={max(r['wars'] for r in rows)}")
    print(f"  tratados/jogador: med={st.median([r['treaties'] for r in rows]):.0f} p90={sorted([r['treaties'] for r in rows])[int(.9*(n-1))]}")

    # VEREDITO de tuning
    print("\n── VEREDITO DE TUNING ──")
    win_pct = pct(wins,n)
    death_pct = pct(deaths,n)
    verdicts = []
    if win_pct > 60: verdicts.append(f"⚠ vitória fácil demais ({win_pct:.0f}%) — considere apertar")
    elif win_pct < 15: verdicts.append(f"⚠ vitória rara demais ({win_pct:.0f}%) — considere afrouxar")
    else: verdicts.append(f"✓ taxa de vitória saudável ({win_pct:.0f}%)")
    if death_pct > 25: verdicts.append(f"⚠ mortalidade alta ({death_pct:.0f}%)")
    elif death_pct < 2: verdicts.append(f"⚠ quase ninguém morre ({death_pct:.0f}%) — jogo sem tensão?")
    else: verdicts.append(f"✓ mortalidade saudável ({death_pct:.0f}%)")
    if heg_turns and st.median(heg_turns) < 300: verdicts.append(f"⚠ hegemonia cedo demais (med turno {st.median(heg_turns):.0f})")
    for v in verdicts: print(f"  {v}")

if __name__ == "__main__":
    main()
