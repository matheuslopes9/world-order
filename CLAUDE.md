# Nations: New Dawn — Guia para o Claude Code

Jogo de estratégia geopolítica em **Godot 4.6 (GDScript)**, PT-BR, alvo Steam.
Simulador realista: **195 nações**, campanha **2000→2100** (1 turno = 1 mês →
12 turnos/ano; a campanha completa são ~1200 turnos).
O jogador governa uma nação e tenta levá-la à hegemonia — ou ao menos sobreviver.

> Repositório GitHub: `https://github.com/matheuslopes9/world-order` (nome antigo
> do projeto; o jogo se chama **Nations: New Dawn** desde o commit `f7c7219`).

---

## Como rodar (comandos essenciais)

O executável do Godot **não está no git** (`.gitignore` ignora `Godot_*.exe`).
Baixe o **Godot 4.6.2 stable (console)** e ponha na raiz do projeto (junto do
`project.godot`). No Windows, os comandos usam `.\` no PowerShell.

```
# 1) Gerar o cache de import (1ª vez / após clonar)
.\Godot_v4.6.2-stable_win64_console.exe --headless --path . --import

# 2) Teste de amarração dos sistemas (deve dar "PASS — 110 checks OK")
.\Godot_v4.6.2-stable_win64_console.exe --headless --path . res://scenes/SystemsCheck.tscn

# 3) Teste de UI por clique real (77/77)
.\Godot_v4.6.2-stable_win64_console.exe --headless --path . res://scenes/GameplayTest.tscn

# 4) Screenshots dos painéis (renderiza; salva em user://tour/)
.\Godot_v4.6.2-stable_win64_console.exe --path . res://scenes/ScreenTour.tscn

# 5) Jogar com janela
.\Godot_v4.6.2-stable_win64_console.exe --path .
```

**Simulação de massa (MegaSim)** — joga campanhas completas p/ validar balanceamento:
```
.\Godot_..._console.exe --headless --path . res://scenes/MegaSim.tscn -- --shard=0 --shards=N --games=M --active=1
```
- `--shards=N --shard=I`: divide as 195 nações em N grupos round-robin, roda o grupo I
- `--games=M`: nº de partidas neste shard
- `--active=1`: todas as nações jogam ativamente (cobertura). Sem isso, 10% são passivas (controle)
- Escreve `user://megasim_shard_I.json` (parcial a cada 20 jogos)
- Para cobrir as 195 uma vez: `--shards=1 --games=195` OU 4 shards de ~49

**Pasta `user://`** (saves, resultados de sim, screenshots) no Windows:
`C:\Users\<user>\AppData\Roaming\Godot\app_userdata\Nations- New Dawn\`
(o Godot troca `:` por `-` no nome). Analiso os `.json` com Python.

---

## Arquitetura (scripts principais em `scripts/`)

- **GameEngine.gd** (autoload) — o coração. Estado do mundo, `end_turn()`,
  catálogo central `PANEL_ACTIONS`, API `player_panel_action()`, vitórias/derrotas,
  guerra, FMI, choques globais, corrupção, e a **economia** (mercados, cripto).
- **Nation.gd** — uma nação: economia (`update_pib`, `calc_receita/despesas`,
  balança comercial, rating de crédito), política, gabinete de ministros, tech.
- **BotPlayer.gd** — IA que joga como o jogador (usa a MESMA API). Personas:
  balanced, economic, military, diplomat. `_manage_ministry_budgets` + `_manage_debt`.
- **TechManager.gd** — árvore de 57 techs em 6 trilhas paralelas (uma por ministério).
- **DiplomacyManager / EspionageManager / EventTimeline / StorylineManager** — subsistemas.
- **WorldMap.gd** — a tela principal do jogo (mapa, barra superior, modais, ticker).
- **GameOverlay.gd** — os painéis (Gabinete, Fazenda, Saúde, etc.) e o feed de notícias.
- **PortraitGen.gd** — retratos flat procedurais e determinísticos (o "elenco"): 15
  regiões etno-culturais, 10 papéis (presidente, 6 ministros, âncora...).
- **SaveSystem.gd** — serialização do save (`user://world_order_save.json`).
- **MegaSim / SystemsCheck / GameplayTest / ScreenTour** — harnesses de teste headless.

### Sistemas já implementados (o jogo é grande)
Poder e Controle (guerra c/ espólios, FMI, choques), **elenco de personagens**,
**gabinete de 6 ministérios** (Casa Civil, Fazenda, Justiça&Segurança, Saúde,
Educação, Rel. Exteriores) com **pesquisa científica paralela** e níveis 1-5,
**espiral da corrupção** (roubo do tesouro, fuga de empresas, IED/confiança do
investidor), e a **economia em 4 fases**: (1) balança comercial import/export,
(2) empréstimos proativos + rating de crédito, (3) mercado de ações, (4) cripto.

### 3 emissoras de notícias (por escopo)
- 🏛 **NN — National News** (notícias do próprio país)
- 📡 **RN — Regional News** (do continente)
- 🌍 **GN — Global News** (mundiais)
A âncora do telejornal anuncia a emissora conforme o escopo da manchete.

---

## Padrões e armadilhas (IMPORTANTE — aprendidos na marra)

- **Backup/restore de user://**: TODO harness de teste faz backup e restore dos
  arquivos reais (`world_order_save.json`, `achievements.json`, `settings.cfg`)
  para não apagar dados do jogador. Manter isso ao criar novos harnesses.
- **API central de ações**: UI e BotPlayer usam a MESMA `player_panel_action`.
  Nunca duplicar a lógica de efeito de uma ação — só declarar em `PANEL_ACTIONS`
  e implementar em `_apply_panel_action`.
- **Números que crescem com o PIB precisam de DAMPING + CAP.** Aconteceu com a
  balança comercial e a bolsa: sem `pow(pib, ~0.85)` + cap proporcional, viravam
  trilhões no fim do século e dominavam a economia.
- **Valores derivados chamados muitas vezes/turno → CACHEAR 1×/turno.** São 195
  nações × várias chamadas. Ex.: saldo comercial (`_saldo_comercial_cache`).
- **Cuidado com recursão em funções financeiras.** `rating_credito` NÃO pode
  chamar `calc_saldo` (→ `calc_despesas` → juros → rating → loop infinito). Usa
  inflação como proxy fiscal.
- **Testes com `randf()` são frágeis.** Comparar médias longas (30 turnos) com
  margem, nunca o valor cru pós-ruído.
- **Godot: `queue_free()` não remove o filho no mesmo frame** — em loops `while
  count > N`, usar `remove_child` imediato + `queue_free` depois (senão congela).
- **Renomear `config/name` muda a pasta `user://`.** Saves antigos ficam na pasta
  velha. Esperado.
- **Windows/Git Bash**: às vezes o drive `D:` some do path do bash. PowerShell é
  mais confiável para operações de disco. Caminhos com espaço ("Nations- New Dawn")
  precisam de aspas.

---

## Estado atual / próximos passos

- **Economia 100% implementada e commitada** (fases 1-4). A Fase 4 (cripto) passa
  nos 110 testes; falta rodar a **validação de massa (MegaSim)** que travava no PC
  antigo por saturação de CPU — rodar aqui e conferir que a cripto oscila saudável
  e é complementar (não domina). Depois: relatório final do roadmap econômico.
- Docs de plano no repo: `ECONOMIA_PLANO.md`, `GABINETE_PLANO.md`, `MEGASIM_FINDINGS.md`.
- Fluxo de trabalho: ao terminar um bloco, **commitar + `git push`**. No outro PC,
  `git pull` para sincronizar. Nunca editar nos dois ao mesmo tempo sem pull/push.

## Convenções de commit
Mensagens em PT-BR, no estilo `feat:/fix:/test:/chore:`, terminando com:
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```
