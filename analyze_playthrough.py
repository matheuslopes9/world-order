#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ANÁLISE DE PLAYTHROUGH COMPLETO — consolida os shards do MegaSim e avalia o
BALANCEAMENTO do jogo do início ao fim, com as mecânicas novas (grand strategy,
eventos, drama). Foca em: saúde, curva de dificuldade por tier, engajamento
(decisões/guerra/território), e nações-outlier.
Uso: python analyze_playthrough.py
"""
import json, os, glob, statistics as st
from collections import Counter, defaultdict

USERDATA = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Nations- New Dawn")

def load_all():
    games = []
    for p in glob.glob(os.path.join(USERDATA, "megasim_shard_*.json")):
        try:
            d = json.load(open(p, encoding="utf-8"))
            games.extend(d.get("results", []))
        except Exception as e:
            print(f"  (falha ao ler {os.path.basename(p)}: {e})")
    return games

def sec(t): print("\n" + "="*66 + f"\n{t}\n" + "="*66)

def main():
    g = load_all()
    if not g:
        print("Nenhum resultado de shard encontrado ainda. A sim está rodando?")
        return
    n = len(g)
    print(f"\n🎮 PLAYTHROUGH COMPLETO — {n} campanhas (2000→2100), nações cobertas: {len(set(x.get('code') for x in g))}")

    # ---- 1. SAÚDE / INTEGRIDADE ----
    sec("1. SAÚDE — o motor aguenta 100 anos?")
    anom = Counter(x.get("anomaly", "") for x in g)
    n_anom = sum(v for k, v in anom.items() if k)
    neg_pib = sum(1 for x in g if x.get("pib_f", 1) <= 0)
    nan_pib = sum(1 for x in g if x.get("pib_f", 1) != x.get("pib_f", 1))
    incompletos = sum(1 for x in g if x.get("turns", 0) < 1150 and "SÉCULO" in str(x.get("outcome", "")))
    print(f"  anomalias/crashes: {n_anom}/{n}  {'✅' if n_anom==0 else '⚠'}")
    print(f"  PIB negativo: {neg_pib} | NaN: {nan_pib}  {'✅' if neg_pib+nan_pib==0 else '⚠'}")
    infl = [x.get("max_infl", 0) for x in g]
    print(f"  inflação máx: média {st.mean(infl):.1f}%, pior {max(infl):.0f}%  {'✅' if max(infl)<80 else '⚠ hiperinflação?'}")
    gx = [x.get("growth_x", 0) for x in g]
    print(f"  crescimento PIB (x): média {st.mean(gx):.0f}x, máx {max(gx):.0f}x  {'✅ sem runaway' if max(gx)<20000 else '⚠ runaway'}")
    dc = [x.get("defcon_avg", 5) for x in g]
    print(f"  DEFCON médio: {st.mean(dc):.2f}  {'✅ saudável' if st.mean(dc)>3.5 else '⚠ mundo travado em alerta'}")

    # ---- 2. CURVA DE DIFICULDADE POR TIER ----
    sec("2. BALANCEAMENTO — a curva de dificuldade é justa?")
    tiers = ["FACIL","NORMAL","DIFICIL","MUITO_DIFICIL","QUASE_IMPOSSIVEL"]
    def win(o): return ("HEGEMON" in str(o)) or ("POTÊNCIA DO S" in str(o))
    def survive(o): return win(o) or ("LEGADO" in str(o))
    print(f"  {'TIER':<18}{'jogos':>6}{'vitória':>9}{'sobrevive':>11}{'derrota':>9}")
    for t in tiers:
        gg = [x for x in g if x.get("tier")==t]
        if not gg: continue
        w = sum(1 for x in gg if win(x.get("outcome")))
        s = sum(1 for x in gg if survive(x.get("outcome")))
        d = len(gg) - s
        print(f"  {t:<18}{len(gg):>6}{100*w/len(gg):>8.0f}%{100*s/len(gg):>10.0f}%{100*d/len(gg):>8.0f}%")
    # monotonicidade: vitória deve cair do fácil ao difícil
    wr = []
    for t in tiers:
        gg = [x for x in g if x.get("tier")==t]
        if gg: wr.append((t, 100*sum(1 for x in gg if win(x.get("outcome")))/len(gg)))
    mono = all(wr[i][1] >= wr[i+1][1]-8 for i in range(len(wr)-1))  # tolerância 8pp
    print(f"  → curva monotônica (fácil vence mais que difícil): {'✅ SIM' if mono else '⚠ NÃO — revisar tiers'}")

    # ---- 3. ENGAJAMENTO / MECÂNICAS NOVAS ----
    sec("3. DIVERSÃO — as mecânicas estão VIVAS?")
    dec = [x.get("decisions", 0) for x in g]
    print(f"  DECISÕES/jogo: média {st.mean(dec):.1f}, máx {max(dec)}  (eventos + storylines + ações)")
    wars = [x.get("wars", 0) for x in g]
    com_guerra = sum(1 for x in wars if x > 0)
    print(f"  GUERRA: média {st.mean(wars):.1f}/jogo, {100*com_guerra/n:.0f}% das campanhas têm guerra do jogador")
    trt = [x.get("treaties", 0) for x in g]
    print(f"  DIPLOMACIA: {st.mean(trt):.1f} tratados/jogo")
    # território (só se o campo existir — shards novos)
    with_terr = [x for x in g if "provinces_f" in x and "provinces_0" in x]
    if with_terr:
        expandiu = sum(1 for x in with_terr if x["provinces_f"] > x["provinces_0"])
        perdeu = sum(1 for x in with_terr if x["provinces_f"] < x["provinces_0"])
        deltas = [x["provinces_f"]-x["provinces_0"] for x in with_terr]
        print(f"  TERRITÓRIO ({len(with_terr)} jogos c/ dado): {expandiu} expandiram, {perdeu} encolheram, delta médio {st.mean(deltas):+.1f} províncias")
    else:
        print("  TERRITÓRIO: sem dado nesta rodada (shards antigos — rodar shard novo p/ medir)")
    hegs = sum(1 for x in g if "HEGEMON" in str(x.get("outcome")))
    print(f"  HEGEMONIA alcançada: {hegs}/{n} ({100*hegs/n:.1f}%)  {'✅' if hegs>0 else '⚠ ninguém vence a grande vitória'}")

    # ---- 4. OUTCOMES GERAIS ----
    sec("4. DESFECHOS — variedade de finais")
    for o, c in Counter(str(x.get("outcome","?")) for x in g).most_common():
        print(f"  {c:>4}  ({100*c/n:>4.0f}%)  {o}")

    # ---- 5. NAÇÕES OUTLIER ----
    sec("5. OUTLIERS — nações quebradas (sempre vencem ou sempre perdem)?")
    by_nation = defaultdict(list)
    for x in g: by_nation[x.get("code")].append(x)
    # nações que aparecem >=1x e sempre derrota (injogáveis) ou crescimento absurdo
    inj = [c for c,xs in by_nation.items() if xs and all(not survive(x.get("outcome")) for x in xs)]
    runaway = [x.get("code") for x in g if x.get("growth_x",0) > 10000]
    print(f"  nações que SEMPRE perdem (candidatas a injogáveis): {len(inj)}  {inj[:15] if inj else '✅ nenhuma'}")
    print(f"  nações com crescimento absurdo (>10000x): {len(set(runaway))}  {list(set(runaway))[:10] if runaway else '✅ nenhuma'}")

    print("\n" + "="*66)
    print("VEREDITO RÁPIDO:")
    ok_saude = n_anom==0 and neg_pib+nan_pib==0 and max(gx)<20000 and st.mean(dc)>3.5
    ok_curva = mono
    ok_diversao = st.mean(dec) > 40 and com_guerra/n > 0.3
    print(f"  Saúde do motor:     {'✅ OK' if ok_saude else '⚠ revisar'}")
    print(f"  Curva de tier:      {'✅ justa' if ok_curva else '⚠ revisar'}")
    print(f"  Diversão/engajamento: {'✅ vivo' if ok_diversao else '⚠ morno'}")
    print("="*66)

if __name__ == "__main__":
    main()
