# 🌍 Nations: New Dawn

Simulador geopolítico de estratégia em **Godot 4 (GDScript)**, PT-BR, alvo Steam.
Comande uma das **195 nações reais** do mundo e leve-a à hegemonia global — ou
apenas sobreviva. Campanha **2000 → 2100** com **1 turno = 1 mês** (~1200 turnos,
8-12h de jogo). Mapa de **satélite real da Terra** (NASA Blue Marble) renderizado
em Vulkan.

> Repositório: `https://github.com/matheuslopes9/world-order` (nome antigo do
> projeto; o jogo se chama **Nations: New Dawn** desde o commit `f7c7219`).

---

## 🎮 Como jogar

1. Baixe o **Godot 4.7.x (console)** e coloque o executável na raiz do projeto.
2. `Godot_*_console.exe --headless --path . --import` (1ª vez, gera o cache).
3. Rode: `Godot_*.exe --path .` (janela) ou `--fullscreen`.
4. **▶ INICIAR JOGO** → **tela de início**: escolha a nação, monte seu líder
   (nome, idade, background, lema — tudo obrigatório), o regime, a doutrina
   econômica e os primeiros 100 dias. → **⚡ INICIAR GOVERNO**.
5. Use a **barra inferior** (ministérios) e o **mapa** para governar; clique em
   **▶ PRÓXIMO TURNO** para avançar um mês.

---

## ⚙️ Sistemas implementados

### 🏛 Gabinete de 6 ministérios
Casa Civil, Fazenda, Justiça & Segurança, Saúde, Educação, Exterior — cada um com
**ministro nomeado** (nome, idade, **competência** que afeta a força das ações),
nível 1-5, XP, **feitos bons/ruins** acumulados, e opção de **demitir e nomear
substituto**. Retratos procedurais determinísticos (o "elenco") por nação e cargo.

### 💰 Economia em 4 fases + complexidade
1. **Balança comercial** (import/export por setor, com damping e cap)
2. **Dívida e crédito** (rating AAA→D, juros dinâmicos, empréstimos, calote)
3. **Bolsa de valores** (índice que reage a paz/crise)
4. **Cripto WorldCoin** (ciclos de alta/colapso, moeda legal reduz sanções)

Mais **complexidade econômica**: cada nação tem um **Economic Complexity Score**
(0-100). Exportar commodity **bruta** rende menos que **manufatura**; a ação
**🏭 Upgrade Industrial** agrega valor; exportadores de bruto sofrem inflação mais
volátil. Crescimento por **modelo de convergência** (catch-up): país pobre bem
administrado pode virar potência em 100 anos.

### 🎭 Líderes, ideologia e rotatividade de poder
Cada nação tem um líder com **ideologia** (que dirige as decisões dos 194 bots),
idade e ~100 anos de vida. Líder impopular/velho **cai e é substituído** — o país
muda de rumo. Democracias trocam por eleição/impopularidade; **autocracias só por
morte ou golpe** (ex: Rússia).

### 🌐 Geopolítica viva
**Afinidade ideológica** (nações parecidas se aproximam), **12 blocos
geopolíticos** com defesa coletiva e bônus de comércio, **coalizão de contenção**
(o mundo se une contra um hegemon), e **guerra com objetivos** (reparações,
recurso, mudança de regime — a vitória impõe o regime do vencedor).

### 🕵 Espionagem, tech e diplomacia
8 operações de espionagem, **57 techs em 6 trilhas paralelas** (uma por
ministério), tratados multilaterais, embaixadas, sanções.

### 🗺 Mapa realista
- **Satélite real da NASA (Blue Marble)** — Amazônia, Saara, Himalaia, gelo polar
- **Oceano com batimetria real** + correntes animadas
- **Filtros de dados** (Satélite / Político por regime / Economia / Militar /
  Estabilidade / Recursos) — coropléticos limpos com cor consistente
- Mundo fechado por moldura, sem "mundo infinito"; efeito de guerra pulsante

### 🎨 Interface premium
- **Menu inicial + loading** com o logo do brasão e fundo texturizado (100 dicas
  rotativas no loading, spinner fluido a 60 FPS via carregamento em Thread)
- **Painéis temáticos** por ministério (cor + ícone únicos): Economia como
  dashboard de KPIs, Situação com medalhão de ranking, Militar como war room
- **Opções em 4 abas**: Jogo · Vídeo (janela/resolução/VSync/FPS/brilho) ·
  Áudio (música/SFX/mudo) · Sistema (salvar/carregar/sair)
- Modo de dificuldade (Fácil/Normal/Difícil/Brutal), acessibilidade (daltonismo,
  tamanho de fonte)

### 📰 3 emissoras de notícias
🏛 National (país) · 📡 Regional (continente) · 🌍 Global (mundo) — a âncora do
telejornal anuncia a emissora conforme o escopo.

---

## 🏆 Vitória e derrota

Poder = **economia 40% · militar 25% · tecnologia 20% · diplomacia 15%**.

- **🏆 HEGEMONIA** — #1 do ranking mundial por 4 anos, país estável, economia ≥40%
  da maior (a partir de 2025).
- **🏛 POTÊNCIA DO SÉCULO** — chegar a 2100 entre as 5 maiores.
- **📜 LEGADO DO SÉCULO** — sobreviver aos 100 anos.
- **Derrotas**: Revolução (apoio baixo prolongado), Falência (tesouro zerado),
  Golpe (estabilidade baixa), Hiperinflação. A **espiral de crise** faz uma crise
  ignorada colapsar o governo em ~14 meses.

---

## 🧪 Testes e simulação

```
# Amarração dos sistemas (152 checks)
Godot_*_console.exe --headless --path . res://scenes/SystemsCheck.tscn

# UI por clique real (82 checks — pressiona cada botão)
Godot_*_console.exe --headless --path . res://scenes/GameplayTest.tscn

# Simulação de massa (valida balanceamento)
Godot_*_console.exe --headless --path . res://scenes/MegaSim.tscn -- --shard=0 --shards=4 --games=250 --active=1
```

**Validação massiva** (1000 jogos completos): 0 crashes, 0 anomalias, curva de
tier justa (27% de vitória nos tiers jogáveis), nenhuma nação injogável, PIB sem
runaway. Análise: `analyze_health.py` (roda sobre os resultados do MegaSim).

---

## 🛠 Arquitetura

```
scripts/
├── GameEngine.gd        # autoload — o coração (estado, end_turn, PANEL_ACTIONS,
│                        #   economia, guerra, FMI, choques, vitória/derrota)
├── Nation.gd            # uma nação (economia, política, gabinete, tech, líder)
├── BotPlayer.gd         # IA que joga com a MESMA API do jogador (4 personas)
├── TechManager.gd       # 57 techs em 6 trilhas
├── DiplomacyManager / EspionageManager / EventTimeline / StorylineManager
├── WorldMap.gd          # tela principal (mapa, HUD, modais, setup)
├── GameOverlay.gd       # painéis dos ministérios + feed
├── PortraitGen.gd       # retratos procedurais (o "elenco")
├── SaveSystem.gd        # serialização
├── AudioManager / Accessibility / MetaProgression / AchievementManager
└── MegaSim / SystemsCheck / GameplayTest / ScreenTour   # harnesses
shaders/  ocean · country_fill (satélite) · menu_bg
assets/   logo.png · loading_bg.png (fundo) · earth_blue_marble.jpg (NASA)
icons/    resources/ (18 SVG) · ministries/ (14 SVG)
data/     world.json · nations.json · tech · alliances · scenarios · …
docs/archive/   planos já concluídos (histórico)
```

---

## 📊 Performance
- Vulkan (Forward+), 60 FPS
- ~36 ms/turno constante (195 nações + IA + eventos + economia), sem gargalo tardio
- Carregamento do mundo em Thread (spinner fluido)

---

## 🔄 Versão

**v0.5.0** — Doutrina Geopolítica em Tempo Real.

Convenção de commits: PT-BR, `feat:/fix:/test:/chore:`.
