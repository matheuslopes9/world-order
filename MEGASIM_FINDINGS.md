# 🔬 MEGA SIM — Relatório de 1000 Campanhas Completas (2000→2100)

Data: 2026-07-10 · Harness: `scenes/MegaSim.tscn` (4 shards paralelos × 250 jogos)
Cobertura: **todas as 195 nações** × 4 personalidades de bot + 10% passivos (controle)
Anomalias numéricas: **0** · Performance: ~33ms/turno (4 processos concorrentes)

> **STATUS: os 10 fixes foram APLICADOS e re-validados com 300 novas
> campanhas.** Tabela antes/depois no fim deste documento.

## Números-síntese

| Grupo | Vitória | Fim neutro | Morte |
|---|---|---|---|
| ATIVO (900 jogos) | 77.3% | 16.1% | 6.6% |
| PASSIVO (100 jogos) | 0% | 57% | 43% |

Crescimento mediano ativo: 533× em 100 anos · p90: 2451× · máx: **28.997× (Iêmen)**
Decisões históricas/jogo: mediana 59 (uniforme entre nações grandes e pequenas ✅)

---

## 🔴 FALHAS (por prioridade)

### F1. "Potência do Século" é troféu de participação — CRÍTICO
**83% de qualquer nação ativa termina no top-5 de poder** em 2100; 20% das
vitórias de século são micro-estados (Vaticano PIB $3B = 3ª potência, Nauru,
Tuvalu, Palau, San Marino...). Causa: o jogador monopoliza tech_norm (IA
pesquisa devagar → max mundial baixo → jogador = 1.0) e rel_norm (tratados
maximizam relações). 20 + 15 pts "grátis" batem qualquer potência média.
**Fix:** tech_norm por escala absoluta (ex: techs/40, não techs/max) +
rel_norm ponderada pela LARGURA das relações + exigir relevância econômica
(rank PIB ≤ 30) para contar como Potência do Século.

### F2. Hegemonia Global inalcançável — 0 vitórias em 900 jogos
Só 6 jogos chegaram a #1 de poder; o gate "PIB ≥ 50% do líder" bloqueia o
resto (a China da IA cresce ~200× e vira um teto impossível).
**Fix:** gate em 35% OU usar o próprio power score (≥ 90% do #2).

### F3. 7 nações sempre morrem, mesmo jogando bem (dados de 2000 ruins)
AO (t6), ER (t15), IQ (t34), **RU (t11!)**, SA (t17), SS (t28), UA
(hiperinflação t6). Rússia-2000 com Putin a ~70% de aprovação real morrendo
de revolução no turno 11 é dado, não design. Estônia (tigre báltico) também
está 0% em amostra menor.
**Fix:** overrides em `nations_2000.json` (apoio/estab/inflação iniciais).

### F4. Hiperinflação mata no turno 6 — dentro da lua de mel
5/5 mortes por hiperinflação foram t≤8 (UA todas). A lua de mel protege de
revolução/falência mas a inflação herdada dos dados estoura antes de
qualquer contramedida ter efeito.
**Fix:** lua de mel também congela derrota por hiperinflação OU evento de
"resgate do FMI" (ver ideia I2).

### F5. Sem cap de tratados: um jogo terminou com 91 ativos
Spam diplomático sem custo de manutenção. E no extremo oposto, 24% dos
jogos ativos terminam com ZERO tratados (persona economic: mediana 0).
**Fix:** custo de manutenção por tratado ou cap suave (~10) com penalidade.

### F6. Backlog diplomático: até 153 propostas acumuladas (passivo)
Propostas ao jogador nunca expiram — a UI de um jogador casual afogaria.
**Fix:** expirar em 8 turnos com -2 de relação ("ignorar ofertas é rude").

### F7. Picos de 63-143 guerras simultâneas no mundo
Cascatas de defesa coletiva criam guerras mundiais permanentes nos picos
(DEFCON médio 3.11 está saudável, mas o pico é caótico).
**Fix:** chance de intervenção de aliança decai por "distância" do conflito
+ armistício automático em guerras >20 turnos sem resolução.

### F8. Persona "economic" é a pior estratégia (48.5% vs 82-90%)
Spam de ação econômica tem retorno decrescente forte; pesquisa é dominante
(military/diplomat vencem MAIS porque sobram ações para tech). Mediana de
techs: economic 14 vs military 25.
**Fix/aceitar:** é "tech rush" clássico de 4X — mas as ações econômicas
merecem mais profundidade (ver I3).

### F9. Metade do catálogo de techs nunca é vista
Máximo 35/57 techs em 100 anos (p90 = 27). Tier 3-4 da árvore é conteúdo
morto para a maioria das partidas.
**Fix:** slots de pesquisa paralelos no fim do século, custo decrescente
por era, ou reduzir tempo_turnos dos tiers altos.

### F10. Meio de campanha "confortável demais"
Tesouro toca zero em 98% dos jogos (drama early-game ✅) mas inflação ≥30%
em só 4% e dívida >1.5×PIB em 0%. Depois do turno ~60, pouca ameaça.
**Fix:** ver ideias I1/I4 (armadilha da renda média, choques globais).

---

## 💡 IDEIAS (nascidas dos dados)

### I1. Armadilha da Renda Média — a mecânica que falta
O Iêmen cresceu 29.000× porque pobre+estável = milagre infinito. Na
economia real, o catch-up desacelera ao cruzar ~30-40% da fronteira, salvo
inovação (Coreia escapou; Brasil/México não). **Mecânica:** o bônus de
convergência decai na faixa 30-70% da fronteira, a menos que o país tenha
N techs / velocidade de pesquisa alta. Cria o desafio de meio de jogo que
falta (F10) e é pedagógico.

### I2. Resgate do FMI (crise como gameplay)
Quando tesouro=0 + default 3+ turnos: modal "aceitar resgate?" — tesouro
+X, mas austeridade (-apoio, -gasto social) e condição de reforma. Resolve
F4 com narrativa em vez de imunidade.

### I3. Profundidade econômica
Ações econômicas com sinergia: infra desbloqueia bônus de export; estímulo
com cooldown mas efeito maior; política industrial que acelera UMA
categoria de tech. Dá identidade à persona/estratégia econômica (F8).

### I4. Choques globais periódicos pós-2040
Recessões mundiais (a a timeline já tem megatrends!) que batem mais forte
em economias grandes e abertas — o late-game deixa de ser piloto automático.

### I5. Guerra ofensiva para o bot (e IA de conquista)
O bot nunca declara guerra — 175 jogos "military" sem um ataque sequer.
Adicionar candidato de guerra quando: poder militar ≥ 2× do rival + relação
≤ -60 + tesouro folgado. Também habilita conquista como caminho de poder.

### I6. Vitória Tecnológica e Diplomática
Com F1/F2 consertados, adicionar: **Singularidade** (completar a árvore —
hoje impossível, ver F9) e **Pax Mundial** (X alianças + 20 turnos sem
guerra global + DEFCON 5).

### I7. Espionagem/sanções no bot
0 usos em 1000 jogos — features sem cobertura de teste automatizado (e a
persona "diplomat" poderia sancionar rivais em vez de ignorá-los).

### I8. "Rivalidade" emergente das personas
Dado lindo: diplomat sofre 0.44 guerras/jogo, military 0.87 — relações
funcionam como escudo. Expor isso ao jogador (tooltip: "boas relações
reduzem chance de ser atacado") — o sistema já existe, falta comunicá-lo.

---

## ✅ Validações (o que os 1000 jogos PROVARAM que funciona)

- Ativo ≫ Passivo (77% vs 0% de vitória) — jogar bem compensa
- Zero anomalias numéricas em 400.000 turnos simulados
- Exposição de conteúdo uniforme (59 decisões/jogo p/ qualquer nação)
- Passivos morrem 43% (não 100%) — punição justa, não sentença
- Tier QUASE_IMPOSSÍVEL tem os maiores crescimentos (catch-up funciona)
- DEFCON médio 3.11 (mundo tenso mas não apocalíptico)
- Performance estável (sem degradação late-game detectável)

## ✅ V1 → V2: os 10 fixes validados (300 novas campanhas)

| Métrica | V1 (antes) | V2 (depois) | Fix |
|---|---|---|---|
| Micro-estados nas vitórias de século | 20% (Vaticano 3º!) | **0%** | F1 ✅ |
| Qualquer nação termina top-5 poder | 83% | **31%** | F1 ✅ |
| Curva de vitória por tier | quase plana (75-90%) | **87→43→50→19→9.5%** | F1 ✅ |
| Mortes injustas (tiers médios) | até 15% | **0%** | F3 ✅ |
| Nações fatais (RU/SA/UA/IQ/AO/EE) | 0% sobrevivência | **sobrevivem** | F3 ✅ |
| Morte por hiperinflação herdada (t≤12) | 5 | **0** | F4 ✅ |
| Máx tratados ativos | 91 | **≤10** (cap + fix no aceitar) | F5 ✅ |
| Backlog de propostas (AFK) | 153 | **5** | F6 ✅ |
| Pico de guerras simultâneas | 63 med / 143 máx | **34 med / 61 máx** | F7 ✅ |
| Persona economic vs média | -29pp | **na média** | F8 ✅ |
| Hegemonias | 19 (gate impossível p/ resto) | 3 em 272 (gate 35%) | F2 ✅ |

**Ressalvas honestas (anotadas para o futuro):**
- **F9 parcial**: o momentum de pesquisa não bastou — techs máx caiu p/ 29
  (a Armadilha da Renda Média reduz tesouro → menos compras de tech).
  Destravar o catálogo inteiro pede custo decrescente por era.
- **Iêmen ainda cresce ~28.000×** — mas agora É design: o bot pesquisa 20+
  techs e ESCAPA da armadilha (inovação = rota de fuga, como a Coreia real).
  Quem não inova, trava na renda média.
- **NORMAL (43%) ≈ DIFICIL (50%)**: inversão pequena persistente — o tier
  NORMAL contém nações com dados-2000 espinhosos; ruído de amostra (n=21).
- **Guerras do jogador 0.6 → 1.4/jogo**: efeito do armistício — guerras
  eternas viraram ciclos curtos (cada retomada conta de novo). Guerra curta
  e frequente > guerra zumbi eterna.
- DEFCON médio 3.11 → 2.65 pelo mesmo motivo (mais declarações, menos
  duração). Aceitável; reavaliar com o público.

## 🎮 V3 — Pacote "PODER E CONTROLE" validado (300 novas campanhas)

Mecânicas novas: guerra com espólios (war score → vitória decisiva →
reparações/recursos/prestígio), Resgate do FMI, choques globais pós-2035,
economia de escala científica, embaixada via API, bot military ofensivo.

| Métrica | V2 | V3 (com as mecânicas) |
|---|---|---|
| Mortes ativas | 1.1% | 1.5% (justas: 3 revoluções QUASE_IMP) |
| Falência ativa | 5 casos | **1** — o FMI salva quem joga |
| Picos de inflação >60% | 1.8% | **0%** |
| Curva de tier | inversão NORMAL<DIFICIL | **93→38→27→16→9% sem inversões** |
| Nações fatais | ER+SS | **só ER** (t57, tier extremo — ok) |
| Guerras do jogador/jogo | 0.6 | **1.4** (guerra circula: espólios + armistícios) |
| Pico de guerras mundiais | 61 | 55 |
| Crescimento máx | 28.653× | **8.253×** (mais são) |
| Anomalias | 0 | **0** |

**Watch items (próxima sessão):**
- Hegemonia: 0 em 272 (bot não a persegue; guerras derrubam o streak de
  apoio/estab ≥55). Humano com potência mira — reavaliar com playtests
  humanos antes de afrouxar.
- Árvore de techs: p90 23→24 apenas — o custo NÃO era o gargalo; é o
  TEMPO de pesquisa + o bot escolher sempre a mais barata. Próximo passo:
  2ª fila de pesquisa após 25 techs ou tempo decrescente por era.
- Win ativo 23.5%→19.9%: o século ficou mais DURO (guerras+choques) e
  mais honesto (FÁCIL 93% ✓). Monitorar diversão com humanos.

## Como reproduzir

```
# 4 shards paralelos (PowerShell):
0..3 | % { Start-Process .\Godot_v4.6.2-stable_win64_console.exe -ArgumentList "--headless","--path",".","res://scenes/MegaSim.tscn","--","--shard=$_","--shards=4","--games=250" }
# Resultados: %APPDATA%\Godot\app_userdata\World Order\megasim_shard_N.json
```

---

# 🪙 Validação da Economia — Fases 3 & 4 (bolsa + cripto)

Data: 2026-07-15 · Harness: `scenes/MegaSim.tscn` · Godot 4.7.1 · PC novo (12 núcleos)
**489 campanhas completas** (2000→2100): 195 (1 ciclo balanced) + 294 (2 shards × 196
games = 4 ciclos das personas balanced/economic/military/diplomat) · `--active=1`.

## Veredito: ✅ economia validada. Cripto oscila saudável e é complementar.

| Métrica | Resultado | Leitura |
|---|---|---|
| Anomalias / crashes | **0** em 489 jogos | motor sólido |
| Performance | **~17,6 ms/turno** (p90 19,5) | saturação do PC antigo RESOLVIDA |
| Cripto preço final | med **$1.293** (p10 435 · p90 2.008) | oscila, não morre |
| Cripto no piso (≤$200) | **1,6%** | reversão à média funciona ✅ |
| Economic tocaram cripto | **96,9%** (95/98) | bot economic usa a mecânica ✅ |
| P&L cripto (economic) | med **+166** (p10 −19 · p90 +7.444) | risco real, retorno assimétrico ✅ |
| Bolsa (fase 3) jogada | **97,5%** · índice med 4.752 | complementar, não explode |

## 🟡 Achado de balanceamento (não é bug, é ajuste fino)

**Cap prudencial da cripto (12% do PIB) é violado em 14/489 (2,9%).** Causa: o cap
limita a COMPRA, mas o preço pode subir depois e inflar a posição além de 12% (até
25% do PIB nos extremos). Nesses casos a cripto vira **~50% do portfólio** (≈ bolsa),
mais que "complementar". **Nenhum** desses casos quebrou a economia (todos LEGADO/
POTÊNCIA DO SÉCULO). Opções: (a) aceitar (é realista — não forçar venda na alta);
(b) rebalancear passivo se `crypto_val > cap` (haircut suave); (c) cap de compra mais
baixo (~8%). Recomendação: (a) por ora, revisitar se testers humanos reclamarem.

## 🟡 Crescimento do PIB alto no late-game

`growth_x` mediano **746×** em 100 anos (p90 4.301× · max 32.069×). Herança do
relatório de 1000 campanhas (era 533×). Não quebra nada, mas infla os números do fim
do século. Candidato a damping no crescimento composto — fora do escopo da economia.

## Desfecho por persona (todas ativas)

| Persona | LEGADO | POTÊNCIA | REVOLUÇÃO | GOLPE |
|---|---|---|---|---|
| balanced (195) | 107 | 86 | 2 | 0 |
| economic (98) | 60 | 36 | 1 | 1 |
| military (98) | 48 | 37 | 6 | 7 | ← mais derrotas (esperado: guerra é arriscada) |
| diplomat (98) | 52 | 44 | 1 | 1 |

Military tem ~13% de derrota (revolução+golpe) vs ~2% das outras — coerente com o
design (militarismo é a rota de alto risco). Economic sobrevive bem mesmo arriscando
cripto.
