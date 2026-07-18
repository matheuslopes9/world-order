# ⚖️ Relatório de Balanceamento — Pós-Geopolítica Viva

Data: 2026-07-17 · Após adicionar blocos, afinidade, contenção e guerra com objetivos.
Base: MegaSim de 240 campanhas completas (1200 turnos) + probes dirigidos.

## Resumo

Depois das mecânicas grandes da Fase 2, o balanceamento foi re-medido e corrigido em
4 frentes. O jogo agora tem **curva de dificuldade justa, hegemonia difícil, e tensão
real** — sem snowball garantido nem colapsos precoces.

## O que foi diagnosticado e corrigido

### 1. Performance (crítico) — 42ms → 26ms/turno
As features de geopolítica dobraram o custo/turno. Gargalo: `_process_bloc_benefits`
iterava por nação × todos os blocos. Reescrito para iterar por bloco × membros.
Um jogo isolado agora roda 1200 turnos em **~31s, constante em todas as fases** (sem
gargalo de late-game). *(commit a498cea)*

### 2. Nações pequenas não podiam virar potência (virada épica = 0%)
Causa: o PIB no score de poder era linear (`pib/max_mundial`). Com a China chegando a
$1,5 quadrilhão, o PIB de qualquer nação pequena virava ~0 — ela nunca contava, por
mais que crescesse. Fix: normalização comprimida `pow(pib/max, 0.65)` — nações
pequenas contam, mas o PIB absoluto ainda ordena o topo. *(commits 1a407df, d037a79)*

### 3. Curva de dificuldade por tier estava INVERTIDA
Tiers difíceis ganhavam MENOS que fáceis (DIFÍCIL 66% vs NORMAL 20% num lote). O fix
de poder (#2) corrigiu junto. Curva atual (240 sims), **monotônica e justa**:

| Tier | Vitória | Crescimento mediano |
|---|---|---|
| FÁCIL | **70%** | 139× |
| NORMAL | **29%** | 149× |
| DIFÍCIL | **13%** | 425× |
| MUITO_DIFÍCIL | **6%** | 643× |
| QUASE_IMPOSSÍVEL | **2%** | 822× |

### 4. Hegemonia cedo demais → agora bem calibrada
Chegou a sair no turno 180. Fix: só a partir do turno 300 + PIB ≥40% do líder. Agora
a hegemonia sai na **mediana do turno 471** (de 1200) — uma conquista de fim de jogo.

### 5. Jogo sem tensão (mortalidade ~0%) → espiral de crise
As EWMAs de estabilidade/apoio auto-corrigiam crises rápido demais. Adicionada
**espiral de crise**: com estabilidade <30 E apoio <35, o desgaste se realimenta.
Probe: uma nação deixada em crise agora **colapsa em ~14 turnos** (antes se
recuperava). Sobreviver a uma crise virou uma conquista. *(commit f56f18c)*

## Estado atual do balanceamento

| Métrica | Valor (240 sims) | Leitura |
|---|---|---|
| Anomalias/crashes | **0** | motor sólido |
| Vitória por tier | 70%→2% (FÁCIL→QUASE_IMPOSSÍVEL) | curva justa ✓ |
| Hegemonia (timing) | turno 471 mediano | difícil, fim de jogo ✓ |
| Virada épica (fraco→top-5) | ~1% | possível, raro ✓ |
| Snowball (top-10 mantém) | 64% | não é garantido ✓ |
| Guerras/jogador | med 0, max 17 | blocos não causam cascata ✓ |
| Tensão (crise → colapso) | ~14 turnos se ignorada | risco real ✓ |

## Notas

- A **taxa de vitória global** (~10%) é puxada para baixo porque o MegaSim cobre
  TODAS as 195 nações igualmente, e a maioria é MUITO_DIFÍCIL/QUASE_IMPOSSÍVEL. Para
  os tiers que um jogador normalmente escolhe (FÁCIL/NORMAL), a vitória é 70%/29% —
  saudável. O tier é a alavanca de dificuldade, como deve ser.
- **Reprodução:** `MegaSim.tscn -- --shard=I --shards=N --games=M --active=1
  [--scenario=X]`; analisar com `python analyze_balance.py`.
- **Limitação da medição:** os bots do MegaSim jogam defensivamente, então a
  mortalidade medida subestima a tensão para um jogador humano (que arrisca mais).
