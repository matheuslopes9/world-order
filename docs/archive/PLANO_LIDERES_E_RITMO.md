# 🎭 Plano — Líderes com Ideologia, Rotatividade de Poder e Ritmo Mensal

Documento de planejamento. Decisões travadas com o usuário (2026-07-15):
- **Ritmo mensal**: 1 turno = 1 mês (1.200 turnos, 2000→2100, ~10h de campanha).
- **Líderes-bot com ideologia** que dirige a economia e as decisões.
- **Rotatividade de poder**: líder ruim cai → novo líder de outra ideologia muda o rumo.
- **Autocracias (Rússia-like) só trocam por morte/golpe**; democracias por eleição.
- **Vida do líder** limita o mandato (expectativa ~ até idade avançada).

---

## Estado atual (auditado)

- IA dos bots é **rasa**: processa só ~8 nações/turno (`_run_ai_turn`), usa **só
  `agressividade`**. Os `pesos_acao`/`pesos_tratado` do `personalities.json` e o
  campo `ideologia_dominante` são **dados mortos** (nunca lidos).
- **35 arquétipos** de personalidade + mapa `leaders_2024` já existem no JSON.
- **Doutrina econômica** funcional (`_process_economic_doctrine`) mas **só p/ o jogador**.
- **Rotatividade de líder NÃO existe**: golpe/revolução só derrubam o jogador; o
  `regime_politico` dos bots é fixo. `update_elections()` só mexe em números.
- Tempo em **trimestres** (`date_quarter` 1-4); MUITAS constantes assumem isso.

---

## FASE 0 — Ritmo mensal (fundação; alto risco de balanceamento)

Muda `date_quarter` (1-4) → `date_month` (1-12). **Toca constantes de balanceamento**
espalhadas que assumem "turno = trimestre" (cooldowns, taxas/turno, janelas de choque).

Passos:
1. Substituir `date_quarter` por `date_month`; virar ano a cada 12 (não 4).
2. UI de data: "Jan 2000" em vez de "Q1 2000".
3. **Recalibrar taxas por-turno** (÷3 aprox.): doutrina econômica, juros, inflação,
   crescimento de PIB, cooldowns de choque (`_last_shock < 60` → ~180), fadiga de
   guerra, contadores de revolução/falência, TTL de propostas, etc.
4. Eventos-âncora: hoje têm `quarter`; migrar para `month` (ou manter trimestre
   lógico do evento e mapear). A timeline dispara por ano+janela, então o grosso
   sobrevive; ajustar os que checam quarter específico.
5. **Re-validar com MegaSim** — o balanceamento inteiro precisa passar de novo em
   1.200 turnos. Este é o maior risco: growth_x, dívida, inflação, cripto/haircut.

> ⚠️ Fase 0 é pré-requisito das demais, mas é a mais delicada. Alternativa: fazê-la
> por último, mantendo trimestral durante o desenvolvimento dos líderes e migrando
> o ritmo só no fim (menos re-testes intermediários).

---

## FASE 1 — Ideologia econômica dirige os bots

1. Adicionar **ideologia econômica** a cada arquétipo do `personalities.json`
   (mapear: `putin_russo`→estatista, `milei_libertario`→livre_mercado,
   `lula_multipolar`→mista/social, `xi_hegemonico`→planejada, etc.).
2. Generalizar `_process_economic_doctrine(n)` para **qualquer nação** (hoje só
   `player_nation`), lendo a doutrina da ideologia do líder-bot.
3. Rodar no loop de turno para todas as nações (com o damping/cache de sempre —
   195 nações × 1.200 turnos exige cuidado de performance).

**Teste:** nação comunista acumula tesouro/PIB mais lento; libertária cresce PIB
mais rápido com mais corrupção. SystemsCheck + MegaSim (0 anomalias).

---

## FASE 2 — Rotatividade de liderança (o coração)

Novo sistema `_process_leadership(n)` no loop de turno, após eleições:

- **Estado novo em Nation**: `lider_nome`, `lider_ideologia`, `lider_idade`,
  `lider_desde_turno`, `turnos_impopular`.
- **Gatilhos de queda**:
  - Democracia: derrota eleitoral (apoio baixo na eleição) OU impopularidade
    prolongada → novo líder, possível nova ideologia.
  - Autocracia (ditadura/teocracia/comunista autoritário): **NÃO cai por eleição**.
    Só por **morte** (idade/vida) ou **golpe/revolução** (estabilidade muito baixa
    por N turnos). Rússia-like: mesmo líder por décadas.
  - **Morte natural**: todo líder tem idade; ao passar da expectativa (~sortear em
    torno de idade avançada), sucessão. Vida máx ~100 anos.
- **Ao trocar**: sorteia novo líder (nome + ideologia, possivelmente divergente do
  anterior), aplica nova `economic_doctrine`/`ideologia_dominante`, opcionalmente
  muda `regime_politico` (revolução pode virar o regime). Notícia via `_log_news`
  no escopo certo (nacional/regional/global conforme o país).
- **Efeito visível**: o país muda de rumo econômico/diplomático após a troca.

**Teste:** simular nação com apoio baixo → cai e troca ideologia; autocracia com
apoio baixo NÃO cai por eleição, só por golpe; líder velho morre e sucede.

---

## FASE 3 — Bots mais ricos (ligar os dados mortos)

- `_ai_decide` passa a usar `pesos_acao` da personalidade (escolha ponderada, como
  o BotPlayer já faz) em vez da cascata hardcoded.
- `DiplomacyManager` usa `pesos_tratado`/`prioridades`/`gatilhos_agressao`.
- Processar **mais nações/turno** (hoje só 8) para o mundo reagir de verdade — com
  orçamento de performance medido (talvez todas, com trabalho amortizado).

**Teste:** personalidades produzem comportamentos distintos mensuráveis no MegaSim
(agressivo declara mais guerra; diplomata assina mais tratados; tecnocrata pesquisa
mais). 0 anomalias, performance aceitável.

---

## Ordem recomendada

**1 → 2 → 3 → 0.** Construir os líderes/ideologia/IA em trimestral (estável, testes
rápidos), e migrar o ritmo mensal por ÚLTIMO (Fase 0), recalibrando tudo de uma vez
com o sistema já completo. Reduz re-testes intermediários e isola o risco do ritmo.

Cada fase: SystemsCheck + MegaSim + commit + push antes da próxima.
