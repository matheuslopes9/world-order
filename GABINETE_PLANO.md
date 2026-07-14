# 🏛 PLANO DE AÇÃO — Gabinete de Ministros

Transforma o "elenco visual" em um **gabinete funcional**: 6 ministérios, cada
um com rosto (PortraitGen), nível 1-5 por investimento, ações próprias e uma
**trilha de pesquisa científica paralela**. Decisões do usuário travadas:

- **6 pastas** — Defesa fundida na Segurança (Justiça & Segurança comanda a guerra)
- **Pesquisa paralela** por ministério (resolve o gargalo real: techs travam em ~24/57 por TEMPO)
- **Níveis 1-5** por investimento (progressão de longo prazo, recompensa foco)
- **Entrega única** — pacote completo + MegaSim de validação + relatório

---

## 🎭 O GABINETE (6 pastas universais — funciona p/ as 195 nações)

| Pasta | Papel PortraitGen | Governa (indicadores) | Absorve |
|---|---|---|---|
| 🏛 **Casa Civil** | `casa_civil` (novo) | coordenação, +ações/turno, apoio | painel Governo |
| 💰 **Fazenda** | `economia` (existe) | PIB, tesouro, inflação, dívida | painel Economia |
| ⚖️ **Justiça & Segurança** | `seguranca` (novo) | estabilidade, corrupção, **intel**, **militar**, **guerra** | painéis Militar + Intel |
| 🏥 **Saúde** | `saude` (novo) | felicidade, população, mortalidade | ações de saúde |
| 📚 **Educação** | `educacao` (novo) | velocidade de pesquisa, tech | painel Tech |
| 🌐 **Relações Exteriores** | `chanceler` (existe) | diplomacia, tratados, embaixadas | painel Diplomacia |

**Removidos como rostos separados:** General e Chefe de Inteligência — ambos
absorvidos pelo Min. da Justiça & Segurança (mantemos os *dados* militares/intel,
só some o rosto duplicado). Âncora do WON permanece (não é ministro).

Novos papéis em `PortraitGen.ROLES`: `casa_civil` (terno cinza + pin),
`seguranca` (terno escuro + distintivo/estrela), `saude` (jaleco branco + gravata),
`educacao` (terno + óculos, ar acadêmico). Cada um determinístico por nação.

---

## 🔬 PESQUISA CIENTÍFICA PARALELA POR MINISTÉRIO

**Problema que resolve** (documentado no MEGASIM_FINDINGS V3): a árvore trava em
p90=24 de 57 techs porque há **uma fila só** e o tempo domina. Filas paralelas =
mais cobertura da árvore + escolha estratégica de foco.

### Mapa techs → ministério (reusa as 5 categorias de tech.json)

| Categoria tech.json | Ministério dono | Nº techs |
|---|---|---|
| `SOCIAL` | Saúde + Educação (dividem) | 12 |
| `DIGITAL` | Educação | 11 |
| `ENERGIA` | Fazenda | 11 |
| `MILITAR` | Justiça & Segurança | 13 |
| `ESPACIAL` | Educação (ciência de ponta) | 10 |

> Ajuste fino no código: `MINISTRY_OF_CATEGORY` mapeia categoria→pasta. SOCIAL
> reparte por subtag (techs de saúde vs ensino) — ou, mais simples, Saúde pega
> SOCIAL e Educação pega DIGITAL+ESPACIAL. Decido na implementação pelo que
> equilibra melhor no MegaSim.

### Como funciona
- Cada ministério com **verba de P&D alocada** avança **sua própria trilha** a cada turno.
- `Nation.pesquisa_atual` (1 slot) → vira `Nation.pesquisa_por_ministerio: Dictionary`
  (até 6 slots, um por pasta). Retrocompatível: quem não aloca verba não pesquisa.
- **Velocidade da trilha** = base × (nível do ministério ÷ 3) × velocidade_pesquisa global × economia-de-escala (o decaimento de custo por tech que já existe).
- Nº de trilhas simultâneas **desbloqueia com o nível da Casa Civil** (nível 1→2 trilhas … nível 5→6 trilhas). Sem Casa Civil forte, você escolhe onde focar — decisão real.

---

## 📈 NÍVEIS DE MINISTÉRIO (1-5 por investimento)

Novo em `Nation`: `ministerios: Dictionary` — por pasta guarda `{nivel, xp, verba}`.

- **XP** sobe quando você usa uma ação daquela pasta OU aloca verba de P&D.
- **Nível** (1-5) sobe ao cruzar limiares de XP crescentes (ex: 100/300/700/1500).
- **Efeito do nível:**
  - Multiplica a força das ações da pasta (nível 5 ≈ 1.6× do nível 1) — reusa o `get_action_multiplier` que já existe, agora **por pasta**.
  - Acelera a trilha de pesquisa da pasta.
  - **Desbloqueia techs de tier alto**: uma tech tier 3-4 exige nível ≥3 do seu ministério (novo gate, além dos gates de PIB/estabilidade que já existem).
- **Bots** também sobem níveis (BotPlayer aloca verba conforme persona: military→Segurança, economic→Fazenda, etc.) — mantém o mundo coerente e a IA competitiva.

---

## 🗺 MUDANÇAS POR ARQUIVO

### `scripts/PortraitGen.gd`
- +4 papéis em `ROLES`: `casa_civil`, `seguranca`, `saude`, `educacao` (vestimenta/cor próprias).
- Nada muda no pipeline determinístico — só novas entradas.

### `scripts/Nation.gd`
- `var ministerios := {}` inicializado no load (6 pastas, nível 1, xp 0, verba 0).
- `pesquisa_atual` → `pesquisa_por_ministerio: Dictionary` (migração retrocompatível: um helper lê ambos).
- `get_action_multiplier(pasta)` passa a considerar o nível da pasta.
- `add_ministry_xp(pasta, x)`, `ministry_level(pasta)`, `set_ministry_budget(pasta, v)`.
- `calc_despesas()`: soma a verba de P&D alocada aos ministérios.

### `scripts/GameEngine.gd`
- `PANEL_ACTIONS`: adiciona campo `"ministerio"` a cada ação (a que pasta pertence) + novas ações por pasta (ex: Saúde → `campanha_vacinacao`, `construir_hospitais`; Educação → `universidades`, `bolsas_pesquisa`; Segurança → herda militares + `operacao_policial`, `reforma_judicial`).
- `player_panel_action`: ao executar, credita XP no ministério da ação.
- `MINISTRY_OF_CATEGORY` + `player_set_research_focus(pasta, tech_id)` + `player_alloc_rd(pasta, verba)`.
- `end_turn`: processa **cada trilha ministerial** (não só uma), aplica efeitos de tech ao concluir.
- `get_cabinet_snapshot()` → dados p/ a UI (nível, xp%, trilha, verba de cada pasta).

### `scripts/TechManager.gd`
- `get_available_techs(nation, pasta)` filtra por ministério + checa gate de nível.
- `_process_research` roda por-pasta; `get_effective_cost` já dá a economia de escala.

### `scripts/GameOverlay.gd` + `scripts/WorldMap.gd`
- Novo painel-mãe **GABINETE** na barra inferior (substitui/reagrupa Governo): grade dos 6 ministros com retrato + nível + trilha de pesquisa ativa. Clicar num ministro abre a pasta (ações + foco de pesquisa + alocar verba).
- Painéis Militar/Intel/Tech continuam acessíveis, mas agora "pertencem" a uma pasta e mostram o rosto do ministro dono.
- Cada ação mostra o efeito escalado pelo nível atual.

### `scripts/BotPlayer.gd`
- Aloca verba de P&D e sobe níveis conforme persona.
- Escolhe foco de pesquisa por pasta (não mais 1 fila global).

---

## ✅ TESTES E VALIDAÇÃO (parte do pacote)

1. **SystemsCheck** (+ checks): 6 ministérios inicializam; XP→nível cruza limiares; nível escala ação; trilhas paralelas concluem techs; gate de nível bloqueia tier alto; determinismo dos 4 novos retratos; cobertura 195 nações.
2. **GameplayTest**: clicar cada ministro, alocar verba, trocar foco, subir nível — botões respondem.
3. **ScreenTour**: novas paradas (painel Gabinete, uma pasta aberta, 4 retratos novos).
4. **MegaSim (300 campanhas)**: valida que a pesquisa paralela **sobe a cobertura de techs** (meta: p90 de 24→35+) sem quebrar a curva de dificuldade nem a performance; que os níveis criam progressão sem inflar vitórias; que os bots usam o sistema. Relatório V4 no MEGASIM_FINDINGS.

---

## 🎯 ORDEM DE IMPLEMENTAÇÃO (entrega única, mas incremental por dentro)

1. PortraitGen: +4 papéis, valida no PortraitTour.
2. Nation: estrutura `ministerios` + helpers + migração da pesquisa.
3. GameEngine: campo `ministerio` nas ações + novas ações + XP + trilhas paralelas + snapshot.
4. TechManager: filtro por pasta + gate de nível + processamento paralelo.
5. UI: painel Gabinete + pasta aberta + rostos nos painéis herdados.
6. BotPlayer: verba/nível/foco por persona.
7. Testes: SystemsCheck + GameplayTest + ScreenTour.
8. MegaSim V4 + relatório + commit.

**Riscos & mitigação:**
- *Balanceamento da pesquisa paralela* → o MegaSim mede cobertura e vitórias; ajusto velocidade/gates até a curva ficar sã (mesmo processo do V1→V3).
- *Retrocompat de saves* → helper lê `pesquisa_atual` antigo e migra p/ `pesquisa_por_ministerio`.
- *Performance* (+trilhas/turno) → processamento é O(6), desprezível; MegaSim confirma ms/turno.
