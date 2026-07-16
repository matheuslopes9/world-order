# 🌍 Nations: New Dawn — Estado do Jogo

> **Documento vivo** — retrato completo do que existe no jogo hoje + lacunas e
> oportunidades de melhoria. Gerado por auditoria de código em 2026-07-16.
> Godot 4.7.1 · GDScript · PT-BR (+EN parcial) · versão interna `v0.5.0`.

**O que é:** simulador geopolítico de **195 nações**, campanha **2000→2100**,
**1 turno = 1 mês** (~1.200 turnos, ~10h de campanha). Você governa uma nação rumo
à hegemonia — ou à sobrevivência.

---

## 📊 Conteúdo em números

| Conteúdo | Quantidade |
|---|---|
| Nações jogáveis | **195** |
| Tecnologias | **57** (5 categorias → 6 trilhas de ministério) |
| Eventos-âncora históricos | **30** (2000-2022) + ~585 secundários procedurais |
| Megatrends (2025-2100) | **28** |
| Storyline arcs encadeados | **5** (15 nodes) |
| Personalidades de nação | **29** arquétipos (24 líderes reais 2024 + 5 genéricos) |
| Líderes históricos jogáveis | **8** (wizard) |
| Cenários | **5** |
| Tipos de tratado | **6** |
| Operações de espionagem | **8** |
| Ações de ministério | **25** (em `PANEL_ACTIONS`) |
| Perks de meta-progressão | **8** |
| Conquistas | **18** |
| Regiões de retrato / papéis | 15 regiões × 10 papéis (procedurais) |

---

## 🎮 1. Loop de jogo e experiência

- **Menu principal** (`MainMenu.gd`) — ✅ completo: nova campanha / continuar, seletor
  de **modo** (inspirado/livre) e **cenário**, modal de **progresso+perks**, idioma
  (PT/EN), créditos, apagar save, e a **lore de abertura da IA OLIMPIA** (intro
  cinematográfica de 4 fragmentos, só na 1ª vez).
- **Wizard "Tomar Posse"** (`WorldMap.gd`) — ✅ completo, 4 etapas: (1) identidade do
  líder (nome/background/lema), (2) sistema de governo, (3) doutrina econômica, (4)
  escolher 3 de 8 "primeiros 100 dias" grátis. Suporta **líderes históricos
  pré-fabricados** com traits (Lula 2003, Putin 2000, Bush 2001…) no modo inspirado.
- **Tela principal** (`WorldMap.gd`, 4.560 linhas) — ✅ mapa mundial vetorial, barra
  superior (data mensal, tesouro, DEFCON, score, **rank de poder mundial** com seta,
  ações N/3), barra de recursos, action bar (11 botões), zoom/pan, 5 filtros de mapa,
  ticker de notícias, marcadores de evento, autosave.
- **Dossiê de nação** — ✅ stats completos (inclui líder, idade, ideologia), retrato
  procedural reativo, tier de dificuldade, análise estratégica (prós/contras), e as
  ações contra a nação (embaixada, tratado, comércio, espionagem, sanção, guerra/paz).
- **Painéis de ministério** (`GameOverlay.gd`) — ✅ 9 abas; feed de notícias com **3
  emissoras** (NN/RN/GN) e âncora com rosto.
- **3 ações por turno** (+1 com perk). Ações de painel, diplomacia, espionagem, guerra
  consomem ação; decisões financeiras (empréstimo, bolsa, cripto, verba P&D) **não**.
- **Save/load** — ✅ save único + autosave por turno; persiste tudo (economia, líderes,
  tratados, mercados, storylines).
- **Áudio** (`AudioManager.gd`) — ✅ música + SFX, com síntese procedural de fallback.
- **Retratos** (`PortraitGen.gd`) — ✅ 15 regiões etno-culturais × 10 papéis,
  determinísticos, com 5 expressões reativas ao estado da nação.

---

## 💰 2. Economia (roadmap de 4 fases — CONCLUÍDO)

Filosofia: **governar bem rende mais que especular**. Bolsa e cripto são temperos de
risco para tesouro ocioso.

- **PIB / crescimento** (`Nation.update_pib`) — modelo de convergência (catch-up):
  nações pobres com boas instituições crescem mais; economias maduras desaceleram.
  Com **armadilha do desenvolvimento** (pobreza extrema freia), soft-cap e **teto
  absoluto de 15.000× o PIB inicial** (anti-runaway, validado 2026-07-16).
- **Receita/despesas** — imposto fixado pelo regime (comunista 35%…autoritário 18%),
  gastos de governo/social/militar + juros da dívida.
- **Fase 1 — Balança comercial**: 4 setores (energia/alimentos/industriais/matérias),
  exporta o que abunda, importa o que falta; saldo afeta receita, inflação, IED.
- **Fase 2 — Dívida + crédito**: rating 0-100 (letras AAA-D), juros por rating
  (3-18%), empréstimo proativo, **FMI/bailout** automático, default.
- **Fase 3 — Bolsa (índice WON)**: investir/resgatar tesouro ocioso, limite prudencial
  (40% do caixa / 25% do PIB), drift ~7%/ano, crashes em crises.
- **Fase 4 — Cripto WorldCoin**: volátil, ciclos bull/bear, risco de colapso, adotar
  como **moeda legal**, limite mais apertado (20% caixa/12% PIB) + **haircut
  prudencial** (realiza excedente acima de 15% do PIB).
- **Doutrina econômica** — livre_mercado/planejada/nórdica/mista; dirige a economia do
  jogador (escolha do wizard) **e dos 195 bots** (via ideologia do líder).
- **Corrupção** — espiral: roubo do tesouro, IED/confiança do investidor, fuga de
  empresas; eventos narrativos (escândalo, êxodo, operação anticorrupção).
- **Inflação** — modelo EWMA com pressões (déficit/militar/guerra/social); **>80% = derrota**.

---

## 🏛 3. Política interna e liderança

- **Estabilidade / apoio / felicidade** — derivam uns dos outros (EWMA) e afetam
  crescimento, receita, rating, vitória/derrota.
- **Regime político** — imposto, corrupção-base e tier de dificuldade derivam dele.
- **Rotatividade de liderança** (`_process_leadership`) — ✅ líder ruim cai → sucessor
  de ideologia possivelmente diferente muda o rumo do país. **Democracias** trocam por
  eleição/impopularidade; **autocracias (Rússia) só por morte/golpe**; vida ~90 anos.
  ~3 trocas/nação por século.
- **Gabinete de 6 ministros** — pastas com níveis 1-5, XP, verba de P&D; **Casa Civil
  desbloqueia trilhas de pesquisa paralelas** (2-6 slots).
- **Vitória**: 🏆 Hegemonia Global (48 meses no topo), 🏛 Potência do Século (top-5 em
  2100), 🌟 Nação Modelo (marco). **Derrota**: Revolução, Falência, Golpe, Hiperinflação.

---

## 🌐 4. Relações internacionais

- **Guerra** — declarar (custo + DEFCON −2), custo/turno, **war score** até vitória
  decisiva (100 pts), **espólios** (reparações + recurso), fadiga/armistício (60
  turnos), capitulação automática. DEFCON 1-5 global.
- **Diplomacia** (`DiplomacyManager`) — 6 tipos de tratado com efeitos/turno, propor/
  aceitar/rejeitar, IA avalia por relação + personalidade (`pesos_tratado`), TTL 24
  turnos, máx 10 tratados/nação.
- **Espionagem** (`EspionageManager`) — 8 operações (infiltrar, roubar tech,
  desinformação, protestos, sabotagem, assassinato, golpe) com % de êxito por intel.
- **Sanções** — penaliza PIB do alvo por turno (dura 15 meses).
- **Comércio bilateral** — exportar recurso por receita/turno (contrato de 24 meses).
- **Nemesis** — rastreia a pior relação; rival declarado gera provocações periódicas.

---

## 🔬 5. Tecnologia e IA

- **Árvore de 57 techs** em 6 trilhas paralelas (uma por ministério), com momentum
  (cada tech barateia/acelera as próximas), gates por PIB/estabilidade/nível.
- **IA das 195 nações** (`_run_ai_turn`/`_ai_decide`) — cursor rotativo processa 24
  nações/turno (todas a cada ~2 anos); decide P&D → paz → guerra → pesquisa → ação
  tática **ponderada pela personalidade** do líder (agressivo→militar, etc.).
- **Personalidades** (`personalities.json`) — 29 arquétipos com líderes reais 2024
  (Putin, Xi, Biden, Milei…), ideologia econômica, pesos de ação e de tratado.
  *(Bug corrigido em 2026-07-16: as personalidades não eram atribuídas — a IA rodava
  "genérica". Agora RU→Putin, AR→Milei, etc.)*

---

## 📰 6. Narrativa e conteúdo

- **Eventos-âncora históricos** (30) — 11/9, invasão do Iraque, tsunami, Crimeia,
  Brexit, Trump, COVID, Ucrânia… com decisões modais. **Crises globais (2008/COVID/
  Ucrânia)** agora abrem a decisão para QUALQUER jogador e têm impacto econômico real.
- **Megatrends** (28) — tendências 2025-2100 (clima, IA, economia, espaço) com gatilho
  probabilístico por década.
- **Storylines** (5 arcs, 15 nodes) — arcos encadeados (filha ativista, general
  ambicioso, descoberta de petróleo, epidemia, imigração em massa) com follow-ups.
- **Conselheiros** (4) — chanceler/general/economista/imprensa recomendam nos modais.
- **Sistema de notícias** (`NewsManager`) — 3-5 notícias procedurais/turno em 8
  categorias, roteadas para as 3 emissoras por escopo.
- **Cenários** (5) — Campanha 100 Anos, Década Crítica (2010-24), Guerra Fria 2.0
  (2025-50), Apocalipse Climático (2030-80), Sandbox.
- **Meta-progressão** — XP entre partidas, 8 perks (máx 2 ativos), desbloqueio de cenários.

---

## ✅ 7. Qualidade / validação

- **SystemsCheck: 132/132** · **GameplayTest: 84/84** (clica cada botão via UI real).
- **MegaSim**: cobertura de todas as 195 nações × 4 personas (780 campanhas de 1.200
  turnos) — **0 anomalias, 0 runaway, 0 encolhimentos** (validado 2026-07-16).
- Performance ~20-27ms/turno.
- Harnesses: SystemsCheck, GameplayTest, MegaSim, ScreenTour, PlaytestSim,
  MassivePlaytest, BalanceSim, UIAutoTest, TimelineTest, PortraitTour.

---

# 🔧 Lacunas e oportunidades de melhoria

Ordenadas por **valor/esforço**. Divididas entre *bugs/dívidas* (corrigir), *jogatina*
(profundidade) e *release* (polimento para Steam).

## 🐞 Bugs e dívidas técnicas (corrigir — baixo esforço)

1. **Idade do líder ausente na UI do wizard.** O campo existe mas fica fixo em 50 —
   não há widget. Impacto no endgame ("líder morreu aos X") e imersão. *(pequeno)*
2. **`data/treaty-types.json` é dado morto.** Os 6 tipos de tratado estão hardcoded no
   `DiplomacyManager`; o JSON não é lido. Unificar (ler do JSON) ou remover o arquivo. *(pequeno)*
3. **Discrepâncias texto × código:**
   - Sanção diz "−1,5% PIB/turno por 5 turnos" na UI, mas aplica −0,5%/15 turnos.
   - "Driblar sanções com cripto" é só narrativo — não há mitigação mecânica real.
   - Tooltips do wizard (governo) prometem efeitos que o código não aplica diretamente.
   Alinhar texto e código (ou implementar o efeito prometido). *(pequeno–médio)*
4. **Nome antigo "World Order"** ainda em README, GAME_DESIGN_ROADMAP, STEAM_CHECKLIST
   e no path do save (`world_order_save.json`). Padronizar para "Nations: New Dawn". *(pequeno)*
5. **Diagnóstico técnico legado** ("hello world": GPU/FPS/renderer) ainda visível no
   menu principal. Remover para o build de release. *(trivial)*
6. **Comentário desatualizado** em AchievementManager ("15" mas são 18). *(trivial)*

## 🎯 Profundidade de jogatina (alto valor)

7. **✅ FEITO (commit 62e87c2) — Afinidade ideológica na diplomacia.** Nações de
   ideologia afim se atraem, opostas repelem (eixo democracia-mercado × autocracia-
   planejada). Afeta relação-base inicial, aceitação de tratados e drift por turno →
   **blocos geopolíticos emergem** ao longo do século. Validado: 95% de coerência
   relação×ideologia, sem aumentar guerras. *Próximo passo natural: blocos FORMAIS (#11)
   sobre esta base.*
8. **⭐ Diferenciar os cenários intermediários.** Década Crítica e Guerra Fria 2.0 hoje
   só mudam janela de anos + bônus inicial. Dar a cada um **objetivos-âncora próprios**
   e 1-2 eventos exclusivos os transformaria em experiências distintas de verdade. *(médio)*
9. **Reação do mundo à ascensão do jogador.** Quando o jogador vira potência, as outras
   nações poderiam formar coalizões de contenção (balancing realista). Hoje o mundo não
   "reage" ao jogador além do nemesis. *(médio)*
10. **Guerra mais tática.** Hoje a guerra é um "war score" abstrato acumulado. Frentes,
    ocupação de território, ou objetivos de guerra dariam mais agência. *(grande — pós-v1)*
11. **Tratados multilaterais / blocos.** Só há tratados bilaterais. Blocos econômicos
    e alianças multi-nação (UE, OTAN, BRICS) seriam um salto de profundidade
    geopolítica — e casam com a afinidade ideológica (#7). *(grande)*
12. **Consequências de longo prazo das storylines.** 5 arcs é pouco para 1.200 turnos;
    e só afetam o jogador. Mais arcs + arcs que envolvam outras nações. *(médio, conteúdo)*

## 🎨 Experiência e clareza

13. **Visibilidade da rotatividade de líderes.** O sistema funciona mas é discreto. Um
    "quadro de líderes mundiais" ou destaque maior das trocas (com retrato do novo
    líder) mostraria melhor essa mecânica rica ao jogador. *(pequeno–médio)*
14. **Onboarding do late-game.** 1.200 turnos é longo; falta orientação de "o que fazer"
    na fase madura (metas de médio prazo, sugestões de conselheiros fora de eventos). *(médio)*
15. **Tutorial ativo.** Há 5 telas passivas; um tutorial guiado (primeira campanha)
    reduziria o abandono nos primeiros 10 minutos (crítico para Steam). *(médio)*

## 🚀 Release (Steam)

16. **Tradução EN incompleta.** Só ~57 strings via `tr()`; a maior parte da UI dinâmica
    (wizard, dossiê, painéis) é PT-BR hardcoded. Externalizar strings para vender em EN. *(grande)*
17. **Assets de áudio.** Só 2 de 8 SFX têm arquivo (resto é sintetizado); 2 faixas de
    música. Mais áudio dá polimento. *(médio)*
18. **Desafios diários** (do roadmap) — inexistentes. Gancho de retenção/leaderboard
    para Steam, mas escopo novo. Decisão de produto: cortar do v1.0 ou pós-lançamento. *(grande)*
19. **Excluir cenas de dev/QA do export** (SystemsCheck, MegaSim, ScreenTour…) do build
    Steam. *(trivial)*
20. **Steam SDK / conquistas / EULA / capsule art** — ver `STEAM_RELEASE_CHECKLIST.md`
    (auditado ~60% pronto). *(grande)*

---

## 🎯 Minha recomendação de próximos passos

Se o objetivo é **mais profundidade de jogatina** (o coração do jogo):
- **#7 Afinidade ideológica na diplomacia** — melhor relação valor/esforço. Aproveita
  os líderes com ideologia (que acabamos de ativar) para gerar blocos geopolíticos
  emergentes. Transforma a sensação do mundo.
- Depois **#8 diferenciar cenários** e **#9 reação à ascensão do jogador**.

Se o objetivo é **caminhar para o lançamento**:
- Limpar os bugs rápidos (#1-6), depois #16 (tradução) e #15 (tutorial).

Os **bugs #1-6 são todos rápidos** e valem ser feitos em qualquer caminho — são
inconsistências visíveis que um tester/reviewer notaria.
