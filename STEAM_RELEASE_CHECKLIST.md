# 🎮 WORLD ORDER — Checklist Steam Release

Documento de auditoria pra preparar lançamento na Steam. Atualizado em 2026-04.

## Status atual: ~60% pronto pra Steam Direct

---

## 1. Requisitos burocráticos Steam (não-código)

| Item | Status | Notas |
|------|--------|-------|
| Steam Direct fee ($100) | ❌ | Pago uma vez por jogo |
| 30-day cooldown após pagamento | ❌ | Valve revisa antes |
| Steamworks SDK integrado | ❌ | Achievements/cloud save dependem disso |
| Build review (1-5 dias) | ❌ | Depois que upload de build |
| Store page review (3-5 dias) | ❌ | Antes do "coming soon" |
| AI Disclosure (regra 2026) | ⚠ | Precisa declarar uso de Claude/AI no dev |
| Classificação etária regional | ❌ | IARC ratings (Brasil ESRB/Classind) |

## 2. Assets gráficos obrigatórios

Resoluções **estritas** segundo docs Steam (atualização 2024):

| Asset | Dimensões | Formato | Status |
|-------|-----------|---------|--------|
| Header Capsule | 920×430 | PNG/JPG | ❌ |
| Small Capsule | 462×174 | PNG/JPG | ❌ |
| Main Capsule | 1232×706 | PNG/JPG | ❌ |
| Vertical Capsule | 748×896 | PNG/JPG | ❌ |
| Library Capsule | 600×900 | PNG | ❌ |
| Library Hero | 3840×1240 | PNG | ❌ |
| Library Logo | 1280 ou 720 wide | PNG transparente | ❌ |
| Page Background | 1438×810 | PNG/JPG | ⚠ opcional |
| Shortcut Icon | 256×256 | ICO/PNG | ❌ |
| App Icon | 184×184 | JPG | ❌ |
| Screenshots (mín 5) | 1920×1080 mín | PNG/JPG | ❌ |
| Trailer | MP4 1080p | até 60s loop | ❌ |

**Total:** 12 assets gráficos novos a produzir + screenshots in-game.

## 3. Requisitos técnicos do build

### Sistema operacional
- [ ] Windows 10/11 64-bit (build atual ✓)
- [ ] Linux (opcional mas recomendado — Godot exporta nativo)
- [ ] macOS (opcional — Godot exporta nativo)

### Performance
- [x] FPS estável 60+ em hardware modesto (Intel Iris Xe testado)
- [x] Tempo de boot <5s
- [x] Sem memory leaks (alguns warnings ao quit, normais)

### Resolução
- [x] Suporta 1920×1080 (default)
- [ ] Suporta 1366×768 (laptop comum) — não testado
- [ ] Suporta 4K (escala UI?) — não implementado
- [ ] Modo janela / fullscreen toggle — não testado

### Input
- [x] Mouse + teclado (atalhos ESC/SPACE/Ctrl+S)
- [ ] Suporte a controle (Steam Controller / Xbox / DualShock) — **NÃO IMPLEMENTADO**
- [x] Tooltips em botões

### Save
- [x] Save/Load funcional (JSON em `user://`)
- [ ] Steam Cloud Save (precisa Steamworks SDK)
- [ ] Auto-save — **NÃO IMPLEMENTADO**

## 4. Conteúdo & UX

### Telas obrigatórias
- [x] Main Menu
- [x] In-game (HUD)
- [x] Save/Load
- [x] Settings (dificuldade, AI speed, modo)
- [x] Pause (via Opções modal)
- [x] Game Over
- [ ] **Tela de Vitória dedicada** — atualmente reusa Game Over
- [ ] **Créditos** — falta
- [ ] **Tela de seleção de idioma** — falta
- [ ] **Tutorial / Como Jogar** — falta dedicado (existe modal de tutorial)
- [ ] **Estatísticas/Leaderboard** — falta

### Idiomas (Steam recomenda mínimo 5 pra alcance global)
- [x] Português Brasileiro (default)
- [ ] Inglês — **CRÍTICO pra alcance global**
- [ ] Espanhol — recomendado
- [ ] Francês, Alemão, Russo — opcional
- [ ] Chinês simplificado, Japonês — opcional mas alcance enorme

### Confirmações em ações destrutivas
- [ ] Declarar guerra (sem confirmação atualmente)
- [ ] Impor sanções (sem confirmação)
- [ ] Reset save (sem confirmação)
- [ ] Sair sem salvar (sem aviso)

### Acessibilidade
- [ ] Daltonismo: cores vermelho/verde sem ícones de redundância
- [ ] Texto pequeno em painéis (10-14px) — sem opção de aumentar
- [ ] Atalhos de teclado documentados (página de ajuda)
- [ ] Navegação só com teclado (Tab/Enter)

## 5. Steam Features integráveis

| Feature | Implementado? | Esforço |
|---------|--------------|---------|
| Steam Cloud Save | ❌ | Médio (configurar via SDK) |
| Steam Achievements | ❌ | Alto (precisa decidir 15-30 conquistas + integrar) |
| Steam Workshop | ❌ | Não relevante (sem mods) |
| Steam Trading Cards | ❌ | Médio (assets gráficos pra cards) |
| Steam Leaderboards | ❌ | Médio (score de partida) |
| Steam Stats | ❌ | Baixo (track de eventos pessoais) |
| Steam Rich Presence | ❌ | Baixo ("Jogando como Brasil — 2024") |

## 6. Documentação obrigatória

- [ ] **EULA/Termos de Uso** — pode ser template
- [ ] **Política de Privacidade** — obrigatória se coleta dados
- [ ] **README de support** — email de contato funcional
- [ ] **Changelog público** — README atual tem, precisa formatar Steam

## 7. Conteúdo do jogo (maturidade)

- [x] 195 nações modeladas
- [x] Campanha 100 anos com 30+585+28 = ~643 eventos
- [x] 9 painéis temáticos funcionais
- [x] Sanções + Comércio + Diplomacia + Espionagem + Tech + News
- [ ] **Achievements integrados** — 0 implementados
- [ ] **Replayability** — sem ranking, sem perks carry-over
- [ ] **Endless mode após vitória** — atualmente continua mas sem feedback

---

## 🎯 PRIORIZAÇÃO REAL PARA STEAM

### Tier 1 — BLOQUEADOR (sem isso não publica)
1. **Inglês traduzido** — Steam exige pra alcance internacional
2. **Build review-ready**: testar em Windows limpo (sem Godot instalado)
3. **Assets de loja**: capsules + library + screenshots
4. **EULA/Política**

### Tier 2 — IMPORTANTE (qualidade percebida)
5. **Confirmações em ações destrutivas**
6. **Tela de Vitória dedicada**
7. **Créditos**
8. **Auto-save**
9. **Steam Cloud Save** (SDK)
10. **Steam Achievements** (15-30 conquistas)

### Tier 3 — NICE-TO-HAVE
11. Suporte a controle
12. Daltonismo (ícones redundantes)
13. Multi-idioma além de pt-BR/en
14. Leaderboards/Stats

---

## Estimativa de tempo

- **Tier 1 (bloqueadores):** ~40-60h
- **Tier 2 (qualidade):** ~30-40h
- **Tier 3 (polish):** ~50-100h

**Total mínimo viável Steam:** ~70-100h de trabalho focado, fora do gameplay core.

---

## Decisão: o que fazer AGORA na sessão atual

Não dá pra produzir assets gráficos via código nem integrar Steamworks SDK em GDScript puro sem extension. Mas posso implementar **as partes que dependem só de código GDScript**:

1. ✅ Confirmação em ações destrutivas (modal "tem certeza?")
2. ✅ Auto-save (a cada N turnos)
3. ✅ Tela de vitória dedicada
4. ✅ Tela de créditos
5. ✅ Sistema de achievements local (sem Steam, mas estrutura pronta)
6. ✅ Save corrupto: fallback graceful
7. ✅ Recuperação de modal-leak em scene change
8. ✅ Debounce de botões pra evitar duplo clique
9. ✅ Testes pra sanções + comércio (lacunas do autoplay atual)
10. ⚠ Tradução EN — pode usar dicionário i18n + Claude pra traduzir strings

**Steam SDK + assets gráficos = trabalho separado** pra outra sessão.
