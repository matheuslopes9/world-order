#!/usr/bin/env python3
"""Analisa os resultados do MegaSim: balanceamento geral + foco na economia/cripto."""
import json, glob, os, statistics as st
from collections import Counter, defaultdict

USERDIR = os.path.expanduser("~/AppData/Roaming/Godot/app_userdata/Nations- New Dawn")

def load():
    rows = []
    for path in sorted(glob.glob(os.path.join(USERDIR, "megasim_shard_*.json"))):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        rows.extend(data.get("results", []))
    return rows

def crypto_by_persona(rows):
    print("\n── CRIPTO POR PERSONA ──")
    by = defaultdict(list)
    for r in rows:
        by[r["persona"]].append(r)
    for p, rs in by.items():
        touched = [r for r in rs if r["crypto_inv"] > 1.0 or r["crypto_val"] > 1.0]
        pnl = [r["crypto_val"] - r["crypto_inv"] for r in touched]
        pnl_txt = summarize(pnl) if pnl else "—"
        print(f"  {p:<10} n={len(rs):<4} tocaram cripto={len(touched):>3} ({pct(len(touched),len(rs)):5.1f}%)  P&L: {pnl_txt}")

def pct(n, d): return 100.0 * n / d if d else 0.0

def summarize(vals):
    vals = [v for v in vals if v is not None]
    if not vals: return "—"
    vals_s = sorted(vals)
    med = st.median(vals_s)
    p10 = vals_s[int(0.10*(len(vals_s)-1))]
    p90 = vals_s[int(0.90*(len(vals_s)-1))]
    return f"med={med:,.1f}  p10={p10:,.1f}  p90={p90:,.1f}  min={vals_s[0]:,.1f}  max={vals_s[-1]:,.1f}"

def main():
    rows = load()
    n = len(rows)
    if not n:
        print("Nenhum resultado encontrado em", USERDIR); return
    print(f"===== MEGASIM: {n} partidas completas (2000→2100) =====\n")

    # --- Desfechos ---
    print("── DESFECHOS ──")
    oc = Counter(r["outcome"] for r in rows)
    for k, v in oc.most_common():
        print(f"  {k:<24} {v:>4}  ({pct(v,n):5.1f}%)")

    # --- Anomalias / mortes precoces ---
    anoms = [r for r in rows if r.get("anomaly")]
    print(f"\n── ANOMALIAS: {len(anoms)} ({pct(len(anoms),n):.1f}%) ──")
    for r in anoms[:15]:
        print(f"  {r['code']} {r.get('anomaly','')} — {r.get('death_ctx','')[:70]}")

    # --- Economia macro ---
    print("\n── ECONOMIA (crescimento do PIB, x sobre inicial) ──")
    print("  growth_x:", summarize([r["growth_x"] for r in rows]))
    print("  pib_f   :", summarize([r["pib_f"] for r in rows]))
    print("  divida_f:", summarize([r["divida_f"] for r in rows]))
    print("  rating  :", summarize([r["rating"] for r in rows]))
    print("  max_infl:", summarize([r["max_infl"] for r in rows]))
    print("  max_debt:", summarize([r["max_debt"] for r in rows]))
    print("  balanca :", summarize([r["balanca"] for r in rows]))

    # --- Mercado de ações (fase 3) ---
    print("\n── BOLSA (fase 3) ──")
    print("  market_f   :", summarize([r["market_f"] for r in rows]))
    print("  stocks_val :", summarize([r["stocks_val"] for r in rows]))
    with_stocks = [r for r in rows if r["stocks_val"] > 1.0]
    print(f"  jogaram na bolsa: {len(with_stocks)} ({pct(len(with_stocks),n):.1f}%)")

    # --- CRIPTO (fase 4) — o foco ---
    print("\n── CRIPTO / WorldCoin (fase 4) ──")
    print("  crypto_f (preço final):", summarize([r["crypto_f"] for r in rows]))
    print("  crypto_val (posição)  :", summarize([r["crypto_val"] for r in rows]))
    print("  crypto_inv (investido):", summarize([r["crypto_inv"] for r in rows]))
    with_crypto = [r for r in rows if r["crypto_val"] > 1.0 or r["crypto_inv"] > 1.0]
    print(f"  nações que tocaram cripto: {len(with_crypto)} ({pct(len(with_crypto),n):.1f}%)")

    # Preço final da cripto: saudável = não colapsou pro piso (150) nem explodiu
    prices = [r["crypto_f"] for r in rows]
    at_floor = sum(1 for p in prices if p <= 200.0)
    print(f"  preço no piso (≤200): {at_floor} ({pct(at_floor,n):.1f}%)  ← se alto, cripto está morrendo")

    # Cripto DOMINA a economia? Compara posição cripto vs PIB
    dom = [r for r in rows if r["pib_f"] > 0 and r["crypto_val"] / r["pib_f"] > 0.12]
    print(f"  posição cripto > 12% do PIB (violaria o cap): {len(dom)}  ← deveria ser ~0")

    # Cripto vs bolsa: complementar? Quem lucrou mais em cada?
    crypto_pnl = [r["crypto_val"] - r["crypto_inv"] for r in with_crypto]
    if crypto_pnl:
        print(f"  P&L cripto (val-inv) dos que jogaram:", summarize(crypto_pnl))

    # --- Guerra / diplomacia / ações ---
    print("\n── JOGABILIDADE ──")
    print("  techs concluídas:", summarize([r["techs"] for r in rows]))
    print("  decisões tomadas:", summarize([r["decisions"] for r in rows]))
    print("  guerras (jogador):", summarize([r["wars"] for r in rows]))
    print("  tratados:", summarize([r["treaties"] for r in rows]))
    print("  corrupção final:", summarize([r["corrupcao_f"] for r in rows]))
    print("  empresas que saíram:", summarize([r["empresas_sairam"] for r in rows]))
    print("  achievements:", summarize([r["achv"] for r in rows]))
    print("  ms/turno (perf):", summarize([r["ms_turn"] for r in rows]))

    crypto_by_persona(rows)

    # --- Por persona ---
    print("\n── DESFECHO POR PERSONA ──")
    by_persona = defaultdict(Counter)
    for r in rows: by_persona[r["persona"]][r["outcome"]] += 1
    for p, c in by_persona.items():
        tot = sum(c.values())
        win = c.get("hegemonia", 0) + c.get("vitoria", 0)
        print(f"  {p:<12} n={tot:<4} hegemonia/vitória={pct(win,tot):5.1f}%  {dict(c)}")

if __name__ == "__main__":
    main()
