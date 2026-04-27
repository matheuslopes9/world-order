# 🌍 WORLD ORDER

**Simulador geopolítico estratégico em tempo real (turnos trimestrais)** — comande qualquer das 195 nações do mundo na campanha **2000 → 2100** e tente levar seu país à hegemonia global.

Construído em **Godot 4.6** com renderização Vulkan, UI estilo *Age of Empires* e timeline de eventos históricos baseada em fatos reais.

🔗 **Repositório:** [github.com/matheuslopes9/world-order](https://github.com/matheuslopes9/world-order)

---

## 📋 Pré-requisitos

- **Godot 4.6+** ([download oficial](https://godotengine.org/download))
- Sistema com suporte a Vulkan (qualquer GPU dos últimos 5 anos)
- ~250 MB livre (projeto + cache de import)

---

## 🎮 Como jogar

1. Clone o repositório: `git clone https://github.com/matheuslopes9/world-order.git`
2. Abra o Godot 4.6 e importe `world-order/project.godot`
3. **F5** para rodar
3. Escolha modo de campanha:
   - **🕰 Inspirado** — eventos disparam em janelas históricas reais (11/9 em 2001, COVID em 2020, etc)
   - **🎲 Livre** — eventos com janelas alargadas, IA reage sem constraint histórico
4. **▶ INICIAR JOGO** → selecione nação no modal (lista à esquerda + dossiê à direita)
5. **⚡ ASSUMIR COMANDO**
6. Use a **action bar** inferior (9 painéis temáticos) ou clique em qualquer país no mapa para ações diplomáticas
7. **▶ PRÓXIMO TURNO** quando terminar (limite: **3 ações/turno**)

---

## ⚙️ Recursos implementados

### 🌍 Mundo vivo (195 nações + 238 países renderizados)
- Mapa-mundi em **Vulkan/Forward+** com 548k vértices, pan com inércia, zoom suave, 4 modos de visualização (Político/Economia/Militar/Estabilidade)
- Cada país com ISO-2, regime político, recursos naturais, militar, demografia, relações diplomáticas
- IA NPC ativa: 4-15 nações tomam ações por turno (configurável)

### 🕰 Campanha 2000-2100 (100 anos)
- **Reset histórico das nações em 2000** ([data/nations_2000.json](world-order/data/nations_2000.json)): 61 países com PIB/pop/regime/líder daquela época + 134 com escala global. Putin recém-eleito na Rússia, Saddam no Iraque, Mubarak no Egito, Argentina pré-default 2001, etc.
- **30 eventos âncora** ([events_timeline.json](world-order/data/events_timeline.json)): 11/9, Iraque, Tsunami, Lehman, Crimeia, COVID, Ucrânia, etc — disparam em year+quarter histórico
- **585 eventos secundários** gerados deterministicamente por país (3/nação × 195) com 6 categorias e ponderação por tier
- **28 megatrends 2025-2100** ([megatrends_2025_2100.json](world-order/data/megatrends_2025_2100.json)) com gatilho probabilístico crescente: AGI, refugiados climáticos, fusão nuclear, Marte, AI governance, contato extraterrestre

### 🎯 Modais de decisão histórica
- Quando evento âncora dispara e você é o `primary_country`, abre modal com **3 escolhas** que aplicam efeitos reais nos seus stats e nos de outros países
- Histórico das decisões persistente (`decision_log`)
- Tela de **estatísticas de divergência**: convergente vs divergente em relação à história real

### ⚡ Sistema de ações limitadas (3/turno)
- Equilibra nações pequenas vs grandes — jogador não pode mais clicar 50× compensando PIB inferior
- Contador na topbar com cor dinâmica (amarelo/laranja/vermelho)
- Ações passivas (aceitar tratado, cancelar pesquisa) NÃO consomem
- Reset automático a cada turno

### 🏛 9 painéis temáticos (modais centrais)
- **Governo** — 5 indicadores + 8 ações (propaganda, anti-corrupção, reforma política, saúde, educação, segurança, previdência, estímulo fiscal)
- **Militar** — capacidade militar + 6 operações (recrutar 4 unidades, base, orçamento)
- **Economia** — finanças trimestrais + recursos naturais + 4 ações econômicas
- **Diplomacia** — propostas pendentes, tratados ativos, alianças, top relações
- **Tech** — pesquisa ativa, filtros por categoria, lista de 100+ tecnologias
- **Intel** — 8 operações de espionagem + log de operações
- **Situação** — rankings globais (PIB, militar) com posição do jogador
- **Histórico** — legado nacional + sparklines de 7 indicadores
- **Notícias** — central de notícias com 5 filtros (Globais/Aliados/Inimigos/Regionais/Nacionais)

### 🤝 Diplomacia
- 6 tipos de tratado: Aliança Militar, Pacto de Não-Agressão, Livre Comércio, Parceria Tecnológica, Desarmamento, Acordo Climático
- IA decide aceitar/rejeitar baseado em personalidade + relação
- Detecção automática de violações (signatários em guerra)

### ⚔️ Sistema de guerra
- Declarar guerra: custo proporcional (max $20B ou 2% PIB)
- Defesa coletiva: aliados podem entrar em guerra junto
- Custos contínuos por turno (atrito militar, tesouro, apoio)
- Capitulação automática quando exausto

### 🕵 Espionagem (8 operações)
Infiltrar Governo, Infiltrar Militar, Roubo de Tecnologia, Desinformação, Fomentar Protestos, Sabotagem Industrial, Neutralização de Líder, Apoiar Golpe.
Taxa de sucesso por Intel Score vs Segurança do alvo.

### 🔬 Pesquisa tecnológica
100+ tecnologias em 5 categorias, 4 tiers (Básico → Elite), pré-requisitos, pesquisa ativa com barra de progresso.

### 📰 Sistema de notícias
- 130+ templates procedurais com tokens dinâmicos ({PAIS}, {N})
- 8 categorias temáticas (Tecnologia, Medicina, Militar, Social, Economia, Política, Clima, Descoberta)
- **Histórico persistente** de 500 últimas notícias com tags (involves, region, scope)
- Modal com **5 filtros** + janela temporal (Últimos 5/20 turnos / Tudo)
- Ticker INTEL clicável na bottom bar

### 💾 Save/Load
- `Ctrl+S` ou OPÇÕES → Salvar
- Save inclui: nações, tratados, propostas, settings, modo, news_history, fired_event_ids, decision_log
- Botão CONTINUAR no MainMenu auto-detecta save

### ⚙️ Configurações
- **Modo de campanha**: inspirado / livre
- **Dificuldade**: easy / normal / hard / brutal
- **Velocidade IA**: 4 / 8 / 15 ações/turno
- Persiste via `user://settings.cfg`

### 🎓 Tutorial
5 telas explicativas na primeira partida (skip/anterior/próximo)

### 🎯 Tier de dificuldade (calibrado via 4 rodadas de playtest)
- 🟢 FÁCIL — 78% win rate, ideal pra aprender
- 🔵 NORMAL — 42% win rate, equilibrado
- 🟡 DIFÍCIL — 60% win rate, exige estratégia
- 🟠 MUITO DIFÍCIL — 33% win rate
- 🔴 QUASE IMPOSSÍVEL — 30% win rate, pra veteranos
- Multiplicador de eficácia compensa: tier difícil ganha bônus de até 1.8×

### ⌨️ Atalhos
- **ESPAÇO** — Avançar Turno
- **ESC** — Abrir Opções
- **Ctrl+S** — Salvar
- **Roda do mouse** — Zoom
- **Arrastar com botão esquerdo** — Pan
- **Click no ticker INTEL** — Modal de notícias

---

## 🏆 Vitória / Derrota

**Vitória**: 20 turnos consecutivos com:
- Apoio Popular ≥ 65%
- Estabilidade ≥ 65%
- Inflação ≤ 15%
- Tesouro > 0

**Derrotas** (após 5 turnos de "lua de mel"):
- 💀 **Revolução**: Apoio Popular < 20% por 3 turnos
- 💀 **Falência Nacional**: Tesouro = 0 por 4 turnos
- 💀 **Golpe de Estado**: Estabilidade < 8%
- 💀 **Hiperinflação**: Inflação > 80%

---

## 🛠 Estrutura técnica

```
world-order/
├── project.godot                 # configuração Godot 4.6
├── icon.svg
├── PLAN_EVENTS_2000_2100.md      # roadmap dos eventos da campanha
├── README.md                     # versão técnica do README
├── theme/
│   └── game_theme.tres           # tema cyberpunk global
├── fonts/
│   ├── CascadiaMono.ttf          # mono pra valores numéricos
│   ├── SegoeUI.ttf               # UI principal
│   └── SegoeUIEmoji.ttf          # ícones
├── scenes/
│   ├── MainMenu.tscn             # tela inicial
│   ├── WorldMap.tscn             # cena principal (mapa + UI AoE-style)
│   ├── PlaytestSim.tscn          # simulação 195 nações
│   ├── MassivePlaytest.tscn      # simulação 3.900 partidas
│   ├── TimelineTest.tscn         # teste de eventos âncora
│   └── UIAutoTest.tscn           # autoplay UI (41 testes)
├── scripts/
│   ├── GameEngine.gd             # autoload, estado global, ações limitadas
│   ├── Nation.gd                 # classe Nação + soft cap PIB
│   ├── EventTimeline.gd          # timeline 2000-2100 + megatrends
│   ├── DiplomacyManager.gd       # 6 tipos tratado
│   ├── NewsManager.gd            # notícias procedurais
│   ├── TechManager.gd            # pesquisa tecnológica
│   ├── EspionageManager.gd       # 8 ops espionagem
│   ├── SaveSystem.gd             # save/load JSON
│   ├── WorldMap.gd               # UI principal + sistema modal
│   ├── GameOverlay.gd            # 9 painéis temáticos
│   ├── MainMenu.gd               # tela inicial + seletor de modo
│   ├── FlagData.gd               # 130+ países com cores oficiais
│   └── PlaytestSim.gd / MassivePlaytest.gd / TimelineTest.gd / UIAutoTest.gd
└── data/
    ├── world.json (9.8 MB)              # geometria 238 países
    ├── nations.json                     # 195 nações (cenário 2024)
    ├── nations_2000.json                # overrides do mundo em 2000
    ├── difficulty-tiers.json            # tier por nação
    ├── events.json                      # eventos com escolhas
    ├── events_timeline.json             # 30 âncora 2000-2024
    ├── event_templates.json             # 32 templates × 6 categorias
    ├── megatrends_2025_2100.json        # 28 megatrends
    ├── alliances.json                   # alianças reais
    ├── tech.json                        # 100+ tecnologias
    ├── personalities.json               # personalidades de IA
    ├── conflicts.json
    └── treaty-types.json
```

---

## 📊 Performance

- **Renderer**: Forward+ (Vulkan)
- **FPS**: 60+ (Intel Iris Xe Graphics integrado)
- **Carga inicial**: ~600ms
- **End_turn**: <100ms (195 nações + IA + eventos + tratados + tech + notícias)
- **Save/Load**: <50ms (JSON local)
- **Playtest validado**: 3.900 partidas × 50 turnos = ~3.9M operações de simulação rodam em ~65 minutos. **Zero bugs numéricos**.

---

## 🧪 Testes automatizados

```bash
# Autoplay UI (41 fluxos: cliques, modais, painéis, zoom)
godot --headless --path . res://scenes/UIAutoTest.tscn

# Teste de timeline (eventos âncora + megatrends)
godot --headless --path . res://scenes/TimelineTest.tscn

# Playtest massivo (3.900 partidas)
godot --headless --path . res://scenes/MassivePlaytest.tscn
```

---

## 🔄 Versão atual

**v0.5.0** (Abril 2026)

### Changelog
- **v0.5.0** — Campanha 2000-2100 completa: ano inicial 2000, modos livre/inspirado, 30 eventos âncora históricos, 585 secundários, 28 megatrends, modais de decisão, histórico persistente de notícias com 5 filtros, **limite de 3 ações/turno**, recalibração de tiers, soft cap de PIB.
- v0.4.0-godot — Tutorial, sparklines, save/load, opções, atalhos
- v0.3.0-godot — TechManager, EspionageManager, DiplomacyManager, NewsManager
- v0.2.0-godot — GameOverlay com 9 painéis (estilo AoE)
- v0.1.0-godot — WorldMap com 238 países em Vulkan, GameEngine, Nation
- *[anterior — projeto HTML/JS, descontinuado em favor do port Godot]*

---

## 🎯 Roadmap

- Recalibrar perfeitamente tiers (NORMAL vs DIFICIL ainda 17pp de diferença)
- Mais eventos secundários cobrindo os 195 países com perfis únicos por categoria
- Bandeiras com emblemas/símbolos (não só listras)
- Multiplayer assíncrono (fase exploratória)
