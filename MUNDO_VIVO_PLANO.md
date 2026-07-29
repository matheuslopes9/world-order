# 🌍 Plano: Mundo Vivo — Nations: New Dawn

Objetivo central: **REJOGABILIDADE** — cada partida conta uma história diferente,
com um antagonista orgânico diferente, para o jogo não enjoar. Construção FATIADA
e testável (cada bloco jogável + validado por MegaSim antes do próximo).

## Ordem dos blocos (a memória vem ANTES da IA — e por quê)

A IA "estratégica" sem memória esqueceria o motivo da estratégia em ~20 turnos
(o drift ideológico puxa relações de volta ao normal). Memória é pré-requisito
de oportunismo, vendeta e rival orgânico. Então:

| # | Bloco | Frente | Impacto sozinho | Risco |
|---|-------|--------|-----------------|-------|
| **A** | Memória & Reputação | rancor | Mundo guarda rancor; reputação modula nemesis/coalizão | Baixo |
| **B** | IA que Estrategiza + rival ascendente | IA | Antagonista orgânico diferente por partida (o CORAÇÃO) | Médio |
| **C** | Conquista com Consequência | conquista | Anexar dói; agressor vira pária | Médio |
| **D** | Política Interna Viva | política | Regime importa; jogador exposto a golpe | Alto |

Se o tempo acabar, parar depois de C já deixa o mundo transformado.

## Bloco A — Memória & Reputação (ligar o campo morto)
- `Nation.memoria` (Nation.gd:206) é código morto — greenfield, sem risco de save legado.
- Estrutura: lista cap-12 de `{tipo, culpado_iso, turno, peso}`. tipo ∈ {guerra_declarada, provincia_perdida, secessao_fomentada, sancao, traicao_alianca, coalizao}.
- Decaimento no cursor (~a cada 8 turnos): `peso *= 0.97` → meia-vida ~12 anos. provincia_perdida decai mais devagar.
- Helper `_remember(vitima, tipo, culpado, peso)` em ~6 call sites (_declare_war, transfer_province, incite_secession, sanção, quebra de aliança).
- Leitura: `_grudge_against(n, alvo)` entra no seletor de alvo de guerra (prioriza rancor sobre worst_rel) E em _drift_ideological_relations (rancor IMPEDE a relação voltar ao normal — fix do bug da mágoa que evapora).
- Índice global `player_reputation` (float no engine): acumula por agressão do jogador, decai devagar. É o HUB que conecta A→C (nemesis + coalizão passam a ler reputação, não só poder).
- Save: memoria em _serialize_nations, player_reputation em save_game, tudo .get(default) retrocompat.
- ESCOPO: cap 12 entradas, só agravos que já disparam eventos. Nada de insultos menores ou grafo de alianças.

## Bloco B — IA que Estrategiza (planejamento leve)
- NÃO reescrever _ai_decide (1849): PREFIXAR com camada de META que enviesa os gates existentes.
- `objetivo_atual` por nação, recalc só quando age no cursor (não todo turno): EXPANDIR / DEFENDER / DESENVOLVER / OPORTUNISMO (atacar vizinho enfraquecido). Cada meta só REMAPEIA thresholds/chances que já existem (war_chance, alvo, ação tática).
- RIVAL ORGÂNICO (núcleo da rejogabilidade): 1 nação/partida com flag `ascendente`, escolhida turno 60-120 entre top-10 (não jogador), viés por aggro. Ganha: crescimento leve (dentro dos caps), objetivo travado EXPANDIR, prioridade no cursor. Toda partida uma potência diferente sobe e vira antagonista — história diferente sem conteúdo novo.
- Determinístico + barato: seleção de meta + alvo mais fraco na fronteira (_pick_frontier_province já existe). SEM pathfinding, SEM simular turnos futuros, SEM avaliar 194 alvos.
- Reusa personas (pesos_acao/prioridades/gatilhos_agressao já ricos).
- ESCOPO: 4 objetivos, 1 rival. Nada de coalizões ofensivas de IA nem IA fomentando secessão.

## Bloco C — Conquista com Consequência (reusar unrest + core_iso)
- transfer_province: quando conquista e new_owner != core_iso, semear unrest inicial (30-50).
- Nova fase `_process_occupation()` no end_turn: itera SÓ províncias owner != core (dezenas, não milhares): unrest cresce, custo de guarnição (padrão _process_war_costs), ao cruzar 100 racha de volta ao core via caminho de secessão existente (respeita guards).
- Vizinhos coalizam por AGRESSÃO: estender _process_containment_coalition — 2º gatilho por reputação (Bloco A), não só hegemonia de poder. Infra de coalizão já pronta. Nações que perderam província entram com peso extra.
- Sem quebrar guards/economia: usa os mesmos guards de secessão, custo sai do tesouro (não toca update_pib).
- ESCOPO: só owner != core gera unrest. Nada de cultura/religião/gestão de ocupação além de "pacificar custa $".

## Bloco D — Política Interna Viva (escopo mínimo, por último)
- Regime gateia: _roll_events (2651) LER os campos regime/estabilidade_max já existentes (fix de 1 função). Gate opcional regime_requerido em PANEL_ACTIONS.
- Jogador exposto a golpe: remover `if n==player_nation: return` (1558) COM travas de justiça: só golpe (nunca morte aleatória), aviso claro por vários turnos (estabilidade < 12 sustentada — culpa dele), imune no fácil.
- ESCOPO CRÍTICO (vira poço): SEM facções, SEM parlamento, SEM ideologia que muda economia. Regime gateia + jogador cai por golpe evitável. Ponto final.

## Riscos
- Perf: menor risco (IA rotativa 24/turno, memória cap-12, ocupação só províncias conquistadas, reputação 1 float). NÃO pôr recálculo no loop de todas-as-nações.
- Balanceamento: o risco real. Rival ascendente cresce por PIB (dentro dos caps), não bônus militar bruto. Metas modulam thresholds calibrados, não substituem. Todo bloco valida no MegaSim: guerras/século, DEFCON, sobrevivência do controle passivo NÃO podem piorar.
- Save: 3 campos novos, todos .get(default) retrocompat.
- "Nunca terminar" (maior risco de PROJETO): cada bloco fecha quando o MegaSim valida impacto + não-regressão, NÃO quando "está completo". Enriquecer A/B/C/D é tudo v2.

**Regra de ouro:** entregar o mundo que LEMBRA agora (memória/reputação/ocupação — ROI alto e finito); IA que PLANEJA fica no mínimo viável (metas+rival), não no sonho EU4.
