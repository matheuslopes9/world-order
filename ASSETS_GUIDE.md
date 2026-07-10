# 🎨 GUIA DE ASSETS — World Order

Guia de assets gratuitos (CC0/OFL/domínio público) pesquisados e verificados para deixar o jogo mais bonito, sonoro e interativo. Atualizado em 2026-07.

---

## 🔊 1. SISTEMA DE ÁUDIO (JÁ INSTALADO)

O jogo agora tem um `AudioManager` (autoload) com filosofia **"nunca mudo"**:

- **Sem arquivos** → todos os 8 SFX são sintetizados proceduralmente na inicialização (~30ms)
- **Com arquivos** → basta soltar um arquivo com o nome certo em `audio/sfx/` e ele é usado automaticamente. Zero configuração.

### Convenção de nomes (drop-in)

| Arquivo | Quando toca | Status |
|---------|-------------|--------|
| `audio/sfx/click.wav` | clique em QUALQUER botão | ✅ instalado (Kenney, CC0) |
| `audio/sfx/hover.wav` | mouse sobre botão | ✅ instalado (Kenney, CC0) |
| `audio/sfx/confirm.ogg` | ação executada com sucesso | 🔧 sintetizado |
| `audio/sfx/error.ogg` | ação negada | 🔧 sintetizado |
| `audio/sfx/turn.ogg` | avanço de turno | 🔧 sintetizado |
| `audio/sfx/alert.ogg` | evento histórico / decisão | 🔧 sintetizado |
| `audio/sfx/achievement.ogg` | conquista desbloqueada | 🔧 sintetizado |
| `audio/sfx/war.ogg` | DEFCON caiu / guerra | 🔧 sintetizado |
| `audio/music/*.ogg` | playlist ambiente embaralhada | ✅ 2 faixas CC0 instaladas |

Integração automática: todo `BaseButton` que entra na árvore ganha SFX (a UI é 100% criada por código, então o hook é via `node_added`). Sinais do GameEngine (turno, eventos, conquistas, DEFCON) já conectados.

### Onde buscar mais SFX (CC0, uso comercial livre)

- **[Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)** — 100 sons de UI, CC0. *O melhor pack para este jogo.*
- **[Kenney UI Audio](https://kenney.nl/assets/ui-audio)** — 50 sons (já usamos click/hover deste, via [mirror Godot](https://github.com/Calinou/kenney-ui-audio))
- **[Kenney — todos os packs de áudio](https://kenney.nl/assets/category:Audio)** — impacts, digital audio, sci-fi
- **[OpenGameArt — Interface Sounds](https://opengameart.org/content/interface-sounds)** e [coleção CC0 do Kenney](https://opengameart.org/content/all-cc0-uploader-kenney)
- **freesound.org** — filtrar por licença CC0 (busque "geiger", "alarm", "sonar ping", "teletype" para clima de guerra fria)

Sugestões temáticas para substituir os sintetizados:
- `war.ogg` → tambor grave / air-raid siren curta (freesound, CC0)
- `alert.ogg` → "breaking news sting" / beep de teletipo
- `turn.ogg` → page flip + relógio tick, ou "sonar ping" suave
- `achievement.ogg` → fanfarra curta de metais

### Onde buscar música (tensão geopolítica / dark ambient)

Já instaladas (tocam automaticamente):
1. **Mysterious Ambience** — cynicmusic, CC0 ([OpenGameArt](https://opengameart.org/content/mysterious-ambience-song21))
2. **Dark Place (loop)** — SkyleTheFrench, CC0 ([OpenGameArt](https://opengameart.org/content/dark-place-loop))

Para expandir a playlist (basta soltar na pasta `audio/music/`):
- **[OpenGameArt — música CC0](https://opengameart.org/content/cc0-music-0)** — índice curado
- **[Free Music Archive — Ambient](https://freemusicarchive.org/genre/Ambient/)** — filtrar por CC0/CC-BY
- **[free-stock-music.com (CC0)](https://www.free-stock-music.com/search.php?license=99)** — filtro por licença CC0
- **[Dark Ambient Modular Game Loops (Chris Ball)](https://balldric.itch.io/dark-ambient-modular-game-loops-vol-1)** — loops modulares para camadas de tensão
- **Kevin MacLeod (incompetech.com)** — CC-BY 4.0 (exige crédito): "Darkest Child", "Static Motion", "Impact Prelude" são perfeitas pro clima do jogo

Ideia de design: 2 playlists — `paz` (ambient calmo) e `crise` (percussão tensa), trocando quando DEFCON ≤ 3. O AudioManager já rastreia DEFCON; é só separar as faixas em subpastas.

---

## ⚠️ 2. FONTES — RISCO LEGAL PARA STEAM (IMPORTANTE)

O projeto embarca **Segoe UI / Segoe UI Bold / Segoe UI Emoji** (`fonts/`). Essas fontes são **proprietárias da Microsoft e NÃO podem ser redistribuídas** com um jogo comercial. Isso é um bloqueador real para o release na Steam.

**Substitutas OFL (Open Font License — redistribuição comercial livre):**

| Fonte atual | Substituta | Status |
|-------------|-----------|--------|
| SegoeUI.ttf / SegoeUI-Bold.ttf | **Inter** (variável, ~860KB) | ✅ baixada em `fonts/Inter-Variable.ttf` |
| SegoeUIEmoji.ttf (12MB!) | **Noto Emoji** ([github](https://github.com/googlefonts/noto-emoji)) | 📋 recomendada |
| CascadiaMono.ttf | já é OFL ✅ | ok manter |

Como trocar (quando decidir): no `theme/game_theme.tres`, apontar a font family default para `Inter-Variable.ttf` (a Inter cobre pesos 100-900 num arquivo só). Depois remover os Segoe*.ttf do repositório.

---

## 🚩 3. BANDEIRAS REAIS (grande upgrade visual barato)

Hoje as bandeiras são desenhadas como faixas de `ColorRect` (aproximações). Existem packs de **bandeiras oficiais em domínio público**, nomeadas por código ISO-2 — exatamente o identificador que o jogo já usa (`codigo_iso`):

- **[hampusborgos/country-flags](https://github.com/hampusborgos/country-flags)** — SVG + PNG de todos os países, domínio público, nomeados `br.png`, `us.png`… ([demo](https://hampusborgos.github.io/country-flags/))
- **[lipis/flag-icons](https://github.com/lipis/flag-icons)** — SVGs curados (MIT)

Integração sugerida: baixar os PNGs 64px para `res://flags/`, e em `WorldMap._paint_flag()` usar `TextureRect` com `res://flags/%s.png % codigo_iso.to_lower()` com fallback para o desenho atual. ~2MB para 250 bandeiras.

---

## 🎨 4. ÍCONES E UI

- **[game-icons.net](https://game-icons.net)** — ~4000 ícones vetoriais temáticos (tanque, míssil, aperto de mão, urna, vírus, satélite…), CC-BY 3.0 (crédito nos créditos do jogo). Resolveria a dependência de emoji (que varia por plataforma).
- **[Kenney UI Pack](https://kenney-assets.itch.io/ui-pack)** — painéis, botões, sliders 9-patch, CC0.
- **[Kenney Game Icons](https://kenney.nl/assets/game-icons)** — ícones simples CC0.

## ✨ 5. SHADERS (mapa mais vivo)

- **[godotshaders.com](https://godotshaders.com)** — filtrar licença CC0/MIT:
  - *Animated water* — oceano com ondulação sutil no `Ocean` ColorRect
  - *Scanline/CRT* — reforça a identidade "sala de comando cyberpunk"
  - *Glow/outline pulsante* — países em guerra pulsando em vermelho
  - *Hologram* — para o modal de decisão histórica

---

## 📋 6. CHECKLIST DE PRÓXIMOS PASSOS

1. ~~SFX de clique/hover~~ ✅ feito
2. ~~Música ambiente~~ ✅ feito (2 faixas; adicionar mais é drag-and-drop)
3. Substituir SFX sintetizados por CC0 escolhidos a dedo (30 min)
4. Trocar Segoe UI → Inter no theme (**antes da Steam**, obrigatório)
5. Bandeiras reais PNG (1-2h, alto impacto visual)
6. Ícones game-icons.net nos painéis (substituir emojis, 2-3h)
7. Shader de água no oceano + pulso vermelho em países em guerra (2h)
8. Playlist dupla paz/crise via DEFCON (30 min)
