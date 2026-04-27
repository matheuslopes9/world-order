# 🌍 WORLD ORDER (Godot 4.6)

Simulador geopolítico de estratégia em tempo real (turnos trimestrais). Comande qualquer uma das 195 nações do mundo e tente levar seu país à hegemonia global — ou pelo menos sobreviver.

Porte nativo do jogo HTML/JS para Godot 4.6 com renderização Vulkan e UI inspirada em Plague Inc.

---

## 🎮 Como Jogar

1. Abra o Godot, importe o projeto (`project.godot`)
2. Aperte **F5**
3. Clique **▶ INICIAR JOGO**
4. Selecione uma nação na lista esquerda (filtre por busca, ordene por dificuldade)
5. **⚡ ASSUMIR COMANDO**
6. Use o painel esquerdo (9 abas) e o dossiê do país (direita) para tomar decisões
7. Clique **▶ PRÓXIMO TURNO** (botão circular grande no canto inferior direito)

---

## ⚙️ Recursos Implementados

### 🏛 9 Painéis Temáticos (acessíveis via tabs)
- **Governo** — 5 indicadores + 8 ações de governo
- **Militar** — capacidade militar + 6 operações (recrutar 4 unidades, base, orçamento)
- **Economia** — finanças trimestrais + recursos naturais + 4 ações econômicas
- **Diplomacia** — propostas pendentes, tratados ativos, alianças, top relações
- **Tech** — pesquisa ativa, filtros por categoria, lista de 100+ techs
- **Intel** — 8 operações de espionagem + log de operações
- **Situação** — rankings globais (PIB, militar) com posição do jogador
- **Histórico** — legado nacional + sparklines de 7 indicadores
- **Notícias** — descrição (eventos no rodapé)

### 🤝 Diplomacia Completa
- 6 tipos de tratado: Aliança Militar, Pacto de Não-Agressão, Livre Comércio, Parceria Tecnológica, Desarmamento, Acordo Climático
- Propostas com decisão automática pela IA (baseado em personalidade + relação)
- Notificação ao jogador para propostas dirigidas
- Aceitar/Rejeitar com efeitos imediatos
- Detecção automática de violações (signatários em guerra)
- Penalidades de relação ao romper tratado

### ⚔️ Sistema de Guerra
- Declarar guerra: custo proporcional (max $20B ou 2% PIB)
- Defesa coletiva: aliados podem entrar em guerra junto
- Custos contínuos por turno (atrito militar, tesouro, apoio)
- Capitulação automática quando exausto
- Propor paz quando em guerra

### 🕵 Espionagem (8 operações)
1. Infiltrar Governo
2. Infiltrar Forças Armadas
3. Roubo de Tecnologia
4. Desinformação
5. Fomentar Protestos
6. Sabotagem Industrial
7. Neutralização de Líder
8. Apoiar Golpe de Estado

Taxa de sucesso ajustada por Intel Score vs Segurança do alvo. Falha causa crise diplomática.

### 🔬 Pesquisa Tecnológica
- 100+ tecnologias em 5 categorias (Militar, Digital, Energia, Social, Espacial)
- 4 tiers (Básico → Elite)
- Pré-requisitos, custo, tempo, requisitos de PIB/estabilidade
- Pesquisa ativa com barra de progresso
- Efeitos aplicados ao concluir (PIB, militar, intel, ciência, etc.)

### 📰 Notícias Procedurais
- 8 categorias temáticas (Tecnologia, Medicina, Militar, Social, Economia, Política, Clima, Descoberta)
- 130+ templates com tokens dinâmicos ({PAIS}, {N})
- 3-5 notícias por turno
- Peso militar aumenta em DEFCON baixo
- Aparecem no ticker do rodapé

### 💾 Save/Load
- Salvar a qualquer momento (Ctrl+S ou OPÇÕES)
- Carregar continua exatamente de onde parou
- Botão CONTINUAR no MainMenu detecta save automaticamente
- Save inclui nações, tratados, propostas, settings

### ⚙️ Configurações
- Dificuldade: easy / normal / hard / brutal (afeta multiplicador de tesouro inicial e IA)
- Velocidade IA: 4 / 8 / 15 ações por turno
- Configurações persistem via `user://settings.cfg`

### 🎓 Tutorial
- 5 telas explicativas na primeira partida
- Skip/Anterior/Próximo
- Reaparece se necessário (controle por settings)

### 🗺 Mapa Vivo
- 238 países com 548k vértices renderizados em Vulkan
- 4 modos de visualização: Político, Economia, Militar, Estabilidade
- Zoom (+/-/↺) com clamp aos bounds do mapa
- Pan com drag (arrastar)
- Click para selecionar país
- Hover destaca país
- Cores dinâmicas: Jogador (ciano), Aliados (verde), Em guerra (vermelho)

### 🎯 Sistema de Tier de Dificuldade
- 195 nações classificadas em 5 tiers (calibrado via playtest)
- 🟢 FÁCIL (68 nações) — superpotências
- 🔵 NORMAL (25) — emergentes médios
- 🟡 DIFÍCIL (59) — emergentes pequenos
- 🟠 MUITO DIFÍCIL (25) — em crise
- 🔴 QUASE IMPOSSÍVEL (18) — situações catastróficas
- Multiplicador de eficácia de ações compensa: tier difícil ganha bônus

### ⌨️ Atalhos de Teclado
- **ESPAÇO** — Avançar Turno
- **ESC** — Abrir Opções (save/load/settings)
- **Ctrl+S** — Salvar Progresso
- **Roda do mouse** — Zoom in/out
- **Arrastar com botão esquerdo** — Pan no mapa

---

## 🏆 Condições de Vitória/Derrota

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

## 🛠️ Estrutura Técnica

```
world-order/
├── project.godot           # configuração Godot
├── theme/
│   └── game_theme.tres     # tema cyberpunk global
├── scenes/
│   ├── MainMenu.tscn
│   ├── WorldMap.tscn        # cena principal (mapa + UI)
│   └── PlaytestSim.tscn     # simulação automatizada
├── scripts/
│   ├── GameEngine.gd        # autoload, estado global
│   ├── Nation.gd            # classe Nação
│   ├── DiplomacyManager.gd  # tratados
│   ├── NewsManager.gd       # notícias procedurais
│   ├── TechManager.gd       # pesquisa tecnológica
│   ├── EspionageManager.gd  # 8 ops espionagem
│   ├── SaveSystem.gd        # save/load JSON
│   ├── WorldMap.gd          # mapa + UI principal
│   ├── GameOverlay.gd       # HUD do jogador (9 painéis)
│   ├── MainMenu.gd          # tela inicial
│   └── PlaytestSim.gd       # simulação massiva (todas as nações)
├── data/
│   ├── world.json (9.8 MB)        # geometria 238 países
│   ├── nations.json (197 KB)      # 195 nações com dados de 2024
│   ├── difficulty-tiers.json      # tier por nação (calibrado)
│   ├── alliances.json             # alianças reais
│   ├── events.json                # eventos com escolhas
│   ├── tech.json                  # 100+ tecnologias
│   ├── personalities.json         # personalidades de IA
│   ├── conflicts.json
│   └── treaty-types.json
└── icon.svg
```

---

## 📊 Performance

- **Renderer**: Forward+ (Vulkan)
- **FPS**: 60+ (Intel Iris Xe Graphics integrado)
- **Carga inicial**: ~400-600ms
- **End_turn**: <100ms (processa 195 nações + IA + eventos + tratados + tech + notícias)
- **Save/Load**: <50ms (JSON local)

---

## 🔄 Versão Atual

**v0.4.0-godot** (Abril 2026)

### Changelog
- v0.4.0: Tutorial, sparklines, save/load, opções, atalhos de teclado
- v0.3.0: TechManager, EspionageManager (8 ops), DiplomacyManager (6 tipos tratado), NewsManager (notícias procedurais)
- v0.2.0: GameOverlay com 9 painéis funcionais, layout estilo Plague Inc
- v0.1.0: WorldMap com 238 países em Vulkan, GameEngine, Nation
