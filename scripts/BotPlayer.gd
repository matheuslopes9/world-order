class_name BotPlayer
extends RefCounted
## Bot de IA que joga como o jogador humano em tempo real.
## Usa árvore de decisão ponderada: avalia todas as ações possíveis,
## pontua cada uma por impacto esperado nos indicadores vitais,
## escolhe a melhor e a executa. Repete até esgotar as 3 ações do turno,
## depois avança o turno automaticamente.
##
## O raciocínio é exposto em tempo real via signal "thinking" pra UI
## mostrar num painel "O que o bot está pensando".

# ── Signals ──────────────────────────────────────────────────────
signal thinking(message: String)        # linha de raciocínio (mostra na UI)
signal action_taken(action: Dictionary) # ação escolhida { type, target, reason, score }
signal turn_starting(turn: int)
signal game_over_detected()

# ── Configuração ─────────────────────────────────────────────────
var speed_delay: float = 2.0   # segundos entre ações (jogador vê acontecer)
var turn_delay: float  = 1.5   # segundos antes de avançar turno
var enabled: bool      = false

# ── Estado ───────────────────────────────────────────────────────
var _engine              # referência ao GameEngine (autoload)
var _tree: SceneTree     # pra criar timers
var _running: bool = false

# ── Personalidade do bot (pesos pra scoring de ação) ─────────────
# Muda o estilo de jogo: "balanced", "economic", "military", "diplomat"
var personality: String = "balanced"

const PERSONALITIES := {
	"balanced":  {"economia": 1.0, "military": 0.8, "diplomacy": 0.8, "tech": 0.9, "social": 0.9},
	"economic":  {"economia": 1.6, "military": 0.4, "diplomacy": 0.7, "tech": 1.1, "social": 0.8},
	"military":  {"economia": 0.7, "military": 1.8, "diplomacy": 0.5, "tech": 0.7, "social": 0.6},
	"diplomat":  {"economia": 0.8, "military": 0.3, "diplomacy": 1.8, "tech": 0.8, "social": 1.2},
}

func _init(engine, tree: SceneTree, persona: String = "balanced") -> void:
	_engine = engine
	_tree = tree
	personality = persona

# ── Entrada pública ───────────────────────────────────────────────
func start() -> void:
	if _running: return
	enabled = true
	_running = true
	_run_loop()

func stop() -> void:
	enabled = false
	_running = false

# ── Loop principal ────────────────────────────────────────────────
func _run_loop() -> void:
	while enabled and _engine != null and _engine.game_state == "PLAYING":
		emit_signal("turn_starting", _engine.current_turn)
		_think("=== Turno %d — Analisando situação... ===" % _engine.current_turn)
		await _delay(turn_delay * 0.5)

		# Executa até 3 ações por turno
		var actions_this_turn: int = 0
		var max_actions: int = _engine.PLAYER_ACTIONS_PER_TURN
		while _engine.player_actions_remaining > 0 and enabled:
			var best := _choose_best_action()
			if best.is_empty():
				_think("Sem ações rentáveis disponíveis. Poupando ações.")
				break
			await _delay(speed_delay)
			_execute_action(best)
			actions_this_turn += 1
			await _delay(0.3)

		# Aceita propostas diplomáticas pendentes (grátis)
		_handle_pending_proposals()

		_think("Ações usadas: %d. Avançando turno..." % actions_this_turn)
		await _delay(turn_delay)

		if not enabled: break
		# Avança o turno pelo GameEngine diretamente
		_engine.end_turn()
		await _delay(0.5)

	_running = false
	if not enabled:
		_think("Bot pausado.")
	else:
		emit_signal("game_over_detected")
		_think("Fim de jogo detectado.")

# ── Motor de decisão ──────────────────────────────────────────────
# Gera todas as ações possíveis, pontua cada uma, retorna a melhor.
func _choose_best_action() -> Dictionary:
	var n = _engine.player_nation
	if n == null: return {}

	var candidates: Array = []
	candidates.append_array(_generate_economy_actions(n))
	candidates.append_array(_generate_social_actions(n))
	candidates.append_array(_generate_tech_actions(n))
	candidates.append_array(_generate_diplomacy_actions(n))
	candidates.append_array(_generate_military_actions(n))
	candidates.append_array(_generate_trade_actions(n))

	if candidates.is_empty(): return {}

	# Aplica pesos de personalidade
	var weights: Dictionary = PERSONALITIES.get(personality, PERSONALITIES["balanced"])
	for c in candidates:
		var cat: String = String(c.get("category", "economia"))
		var w: float = float(weights.get(cat, 1.0))
		c["score"] = float(c.get("score", 0)) * w

	# Ordena por score decrescente
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))

	# Log top 3 opções consideradas
	var top_n: int = mini(3, candidates.size())
	var top_str: String = ""
	for i in top_n:
		top_str += "\n  [%.1f] %s" % [float(candidates[i]["score"]), String(candidates[i]["reason"])]
	_think("Top opções:%s" % top_str)

	return candidates[0]

# ── Geração de candidatos ─────────────────────────────────────────

func _generate_economy_actions(n) -> Array:
	var out: Array = []
	var stab: float = float(n.estabilidade_politica)
	var apoio: float = float(n.apoio_popular)
	var inflacao: float = float(n.inflacao)
	var tesouro: float = float(n.tesouro)
	var pib: float = float(n.pib_bilhoes_usd)

	# Estímulo fiscal — ótimo quando PIB crescimento lento
	if tesouro >= 30:
		var growth_est: float = pib * 0.01  # estimativa
		var score: float = 40.0
		if inflacao > 25: score -= 20.0  # inflação alta penaliza estímulo
		if tesouro < 60: score -= 10.0
		out.append({
			"type": "panel_action", "panel": "economia", "action": "estimulo",
			"score": score, "category": "economia",
			"reason": "Estímulo fiscal (+2%% PIB) — tesouro=$%.0fB" % tesouro
		})

	# Reforma educacional — apoio + burocracia
	if apoio < 70 or n.burocracia_eficiencia < 60:
		var score: float = 30.0 + (70.0 - apoio) * 0.5
		out.append({
			"type": "panel_action", "panel": "governo", "action": "educacao",
			"score": score, "category": "social",
			"reason": "Reforma educacional — apoio=%.0f%%, burocracia=%.0f%%" % [apoio, float(n.burocracia_eficiencia)]
		})

	# Infraestrutura — PIB sustentável
	if tesouro >= 40 and pib < 3000:
		out.append({
			"type": "panel_action", "panel": "economia", "action": "infra",
			"score": 35.0, "category": "economia",
			"reason": "Infraestrutura (+1%% PIB, +3 estab)"
		})

	# Energia — recursos
	if tesouro >= 25:
		var min_res: float = 100.0
		for v in n.recursos.values():
			min_res = minf(min_res, float(v))
		if min_res < 60:
			out.append({
				"type": "panel_action", "panel": "governo", "action": "energia",
				"score": 28.0 + (60.0 - min_res) * 0.3, "category": "economia",
				"reason": "Reforma energética — recurso mín=%.0f" % min_res
			})

	return out

func _generate_social_actions(n) -> Array:
	var out: Array = []
	var apoio: float = float(n.apoio_popular)
	var felicidade: float = float(n.felicidade)
	var stab: float = float(n.estabilidade_politica)
	var corrupcao: float = float(n.corrupcao)
	var tesouro: float = float(n.tesouro)

	# Saúde pública — felicidade e apoio
	if felicidade < 65 or apoio < 65:
		var score: float = 50.0 + (65.0 - felicidade) * 0.8 + (65.0 - apoio) * 0.5
		out.append({
			"type": "panel_action", "panel": "governo", "action": "saude",
			"score": score, "category": "social",
			"reason": "Saúde pública — felicidade=%.0f%%, apoio=%.0f%%" % [felicidade, apoio]
		})

	# Combate à corrupção — urgente se > 50
	if corrupcao > 40 and tesouro >= 20:
		var score: float = 35.0 + (corrupcao - 40) * 1.2
		out.append({
			"type": "panel_action", "panel": "governo", "action": "anticorrupcao",
			"score": score, "category": "social",
			"reason": "Anti-corrupção — corrupção=%.0f%%" % corrupcao
		})

	# Estabilidade crítica — reforma política
	if stab < 50:
		var score: float = 60.0 + (50.0 - stab) * 1.5
		out.append({
			"type": "panel_action", "panel": "governo", "action": "reforma_politica",
			"score": score, "category": "social",
			"reason": "URGENTE: Reforma política — estab=%.0f%%" % stab
		})

	# Gasto social se apoio muito baixo (risco de revolução)
	if apoio < 35:
		out.append({
			"type": "panel_action", "panel": "governo", "action": "gasto_social",
			"score": 80.0 + (35.0 - apoio) * 2.0, "category": "social",
			"reason": "CRÍTICO: Apoio popular em %.0f%% — risco revolução!" % apoio
		})

	return out

func _generate_tech_actions(n) -> Array:
	var out: Array = []
	if _engine.tech == null: return out

	var pesquisa: String = String(n.pesquisa_atual)
	# Já pesquisando — não precisamos iniciar nova
	if pesquisa != "" and pesquisa != "null":
		_think("Pesquisa em andamento: %s" % pesquisa)
		return out

	# Escolhe melhor tech disponível pra pesquisar
	var available := _engine.tech.get_available_techs(n)
	if available.is_empty(): return out

	# Prioridade por categoria conforme personalidade
	var prio := {"economia": 1.2, "militar": 0.9, "social": 1.0, "tech": 1.1, "diplomacia": 0.8}
	var best_tech: Dictionary = {}
	var best_score: float = -1.0
	for t in available:
		var cat: String = String(t.get("categoria", "economia"))
		var base: float = float(t.get("research_cost", 50))
		var score: float = (100.0 / max(1.0, base)) * float(prio.get(cat, 1.0)) * 20.0
		if score > best_score:
			best_score = score
			best_tech = t

	if best_tech.is_empty(): return out
	out.append({
		"type": "research", "tech_id": String(best_tech.get("id", "")),
		"score": best_score + 25.0, "category": "tech",
		"reason": "Pesquisar '%s' (cat: %s)" % [String(best_tech.get("name", "?")), String(best_tech.get("categoria", "?"))]
	})
	return out

func _generate_diplomacy_actions(n) -> Array:
	var out: Array = []
	if _engine.diplomacy == null: return out
	var tesouro: float = float(n.tesouro)
	var p_code: String = n.codigo_iso

	# Propor tratado ao melhor aliado potencial (relação > 20, sem tratado)
	var best_partner: String = ""
	var best_rel: float = 20.0
	var existing_partners: Array = []
	for t in _engine.diplomacy.get_player_treaties():
		for s in t.get("signatories", []):
			if s != p_code: existing_partners.append(s)

	for code in n.relacoes:
		if code == p_code: continue
		var rel: float = float(n.relacoes[code])
		if rel > best_rel and not (code in existing_partners) and not (code in n.em_guerra):
			best_rel = rel
			best_partner = code

	if best_partner != "" and tesouro >= 10:
		var treaty_type: String = "livre_comercio" if best_rel < 60 else "parceria_tecnologica"
		out.append({
			"type": "treaty", "target": best_partner, "treaty_type": treaty_type,
			"score": 20.0 + best_rel * 0.4, "category": "diplomacy",
			"reason": "Propor %s a %s (rel=%.0f)" % [treaty_type, _engine.nations[best_partner].nome if _engine.nations.has(best_partner) else best_partner, best_rel]
		})

	# Digital — pesquisa acelerada
	if tesouro >= 25 and n.velocidade_pesquisa < 2.0:
		out.append({
			"type": "panel_action", "panel": "governo", "action": "digital",
			"score": 22.0, "category": "tech",
			"reason": "Modernização digital (+10%% pesquisa)"
		})

	return out

func _generate_military_actions(n) -> Array:
	var out: Array = []
	var tesouro: float = float(n.tesouro)
	var em_guerra: bool = not n.em_guerra.is_empty()

	# Em guerra: propor paz se estabilidade baixa ou tesouro baixo
	if em_guerra:
		var stab: float = float(n.estabilidade_politica)
		if stab < 45 or tesouro < 40:
			var enemy: String = String(n.em_guerra[0])
			out.append({
				"type": "peace", "target": enemy,
				"score": 70.0 + (45.0 - stab) * 1.5, "category": "military",
				"reason": "Propor paz — stab=%.0f%%, tesouro=%.0fB" % [stab, tesouro]
			})

	# Modernizar forças armadas se poder militar baixo e tem dinheiro
	var poder: float = float(n.militar.get("poder_militar_global", 0)) if n.militar else 0.0
	if poder < 40 and tesouro >= 50:
		out.append({
			"type": "panel_action", "panel": "militar", "action": "modernizar",
			"score": 18.0 + (40.0 - poder) * 0.5, "category": "military",
			"reason": "Modernizar militar — poder=%.0f" % poder
		})

	return out

func _generate_trade_actions(n) -> Array:
	var out: Array = []
	if n.recursos.is_empty(): return out

	# Encontra melhor recurso pra exportar (>= 60 de valor)
	var best_res: String = ""
	var best_val: float = 60.0
	for k in n.recursos:
		var v: float = float(n.recursos[k])
		if v > best_val:
			best_val = v
			best_res = k
	if best_res == "": return out

	# Encontra melhor parceiro comercial (boa relação, sem guerra, sem sanção)
	var best_target: String = ""
	var best_rel: float = -100.0
	for code in _engine.nations:
		if code == n.codigo_iso: continue
		if code in n.em_guerra: continue
		var rel: float = float(n.relacoes.get(code, 0))
		if rel > best_rel:
			best_rel = rel
			best_target = code

	if best_target == "": return out
	out.append({
		"type": "trade", "target": best_target, "resource": best_res,
		"score": 15.0 + best_val * 0.2 + best_rel * 0.1, "category": "economia",
		"reason": "Exportar %s→%s (recurso=%.0f, rel=%.0f)" % [
			best_res,
			_engine.nations[best_target].nome if _engine.nations.has(best_target) else best_target,
			best_val, best_rel
		]
	})
	return out

# ── Executor de ações ─────────────────────────────────────────────
func _execute_action(action: Dictionary) -> void:
	var atype: String = String(action.get("type", ""))
	var reason: String = String(action.get("reason", ""))
	_think("▶ EXECUTANDO: %s" % reason)
	emit_signal("action_taken", action)

	match atype:
		"panel_action":
			_do_panel_action(String(action.get("panel", "")), String(action.get("action", "")))
		"research":
			var res := _engine.player_start_research(String(action.get("tech_id", "")))
			if not bool(res.get("ok", false)):
				_think("  ✗ Pesquisa falhou: %s" % String(res.get("reason", "")))
		"treaty":
			var res := _engine.player_propose_treaty(String(action.get("target", "")), String(action.get("treaty_type", "livre_comercio")))
			if not bool(res.get("ok", false)):
				_think("  ✗ Tratado falhou: %s" % String(res.get("reason", "")))
		"peace":
			if not _engine.player_propose_peace(String(action.get("target", ""))):
				_think("  ✗ Paz falhou")
		"trade":
			var res := _engine.player_export_resource(String(action.get("target", "")), String(action.get("resource", "")))
			if not bool(res.get("ok", false)):
				_think("  ✗ Comércio falhou: %s" % String(res.get("reason", "")))

func _do_panel_action(panel: String, action_id: String) -> void:
	# Aplica o efeito diretamente no Nation do jogador, espelhando
	# o que cada botão de painel faz em WorldMap/_apply_panel_action_effect
	var n = _engine.player_nation
	if n == null: return
	var mult: float = n.get_action_multiplier() if n.has_method("get_action_multiplier") else 1.0
	# Consome ação (se não conseguir, aborta)
	if not _engine._consume_action(): return

	match action_id:
		"saude":
			n.felicidade = clamp(n.felicidade + 8.0 * mult, 0, 100)
			n.apoio_popular = clamp(n.apoio_popular + 4.0 * mult, 0, 100)
			n.tesouro -= 20.0
		"educacao":
			n.apoio_popular = clamp(n.apoio_popular + 5.0 * mult, 0, 100)
			n.burocracia_eficiencia = clamp(n.burocracia_eficiencia + 3.0 * mult, 0, 100)
			n.tesouro -= 15.0
		"anticorrupcao":
			n.corrupcao = clamp(n.corrupcao - 8.0 * mult, 0, 100)
			n.apoio_popular = clamp(n.apoio_popular + 3.0 * mult, 0, 100)
			n.tesouro -= 20.0
		"reforma_politica":
			n.estabilidade_politica = clamp(n.estabilidade_politica + 10.0 * mult, 0, 100)
			n.tesouro -= 30.0
		"gasto_social":
			n.apoio_popular = clamp(n.apoio_popular + 12.0 * mult, 0, 100)
			n.felicidade = clamp(n.felicidade + 6.0 * mult, 0, 100)
			n.tesouro -= 25.0
		"estimulo":
			n.apply_pib_multiplier(1.02 * mult) if n.has_method("apply_pib_multiplier") else null
			n.inflacao = clamp(n.inflacao + 1.5, 0, 100)
		"infra":
			n.apply_pib_multiplier(1.01 * mult) if n.has_method("apply_pib_multiplier") else null
			n.estabilidade_politica = clamp(n.estabilidade_politica + 3.0 * mult, 0, 100)
			n.tesouro -= 40.0
		"energia":
			if n.recursos:
				for k in n.recursos.keys():
					n.recursos[k] = min(100.0, float(n.recursos[k]) + 5.0 * mult)
			n.tesouro -= 25.0
		"digital":
			n.velocidade_pesquisa *= (1.0 + 0.10 * mult)
			n.tesouro -= 25.0
		"modernizar":
			if n.militar:
				n.militar["poder_militar_global"] = float(n.militar.get("poder_militar_global", 0)) + 5.0 * mult
			n.tesouro -= 30.0

	# Reporta no ticker de notícias do jogo
	_engine._log_news({
		"type": "bot_action",
		"headline": "🤖 BOT: %s → %s" % [panel.capitalize(), action_id.replace("_", " ").capitalize()],
		"body": "",
		"color": Color(0.4, 0.85, 1),
	}, [n.codigo_iso], n.continente)

# ── Propostas diplomáticas ────────────────────────────────────────
func _handle_pending_proposals() -> void:
	if _engine.diplomacy == null: return
	var pending: Array = _engine.diplomacy.get_player_pending_proposals()
	for prop in pending:
		# Aceita se relação for positiva, rejeita se negativa
		var proposer: String = String(prop.get("proposer", ""))
		var rel: float = float(_engine.player_nation.relacoes.get(proposer, 0)) if _engine.player_nation else 0.0
		if rel >= 0:
			_engine.player_accept_proposal(String(prop.get("id", "")))
			_think("✅ Aceita proposta de %s (rel=%.0f)" % [proposer, rel])
		else:
			_engine.player_reject_proposal(String(prop.get("id", "")))
			_think("❌ Rejeita proposta de %s (rel=%.0f)" % [proposer, rel])

# ── Helpers ───────────────────────────────────────────────────────
func _think(msg: String) -> void:
	emit_signal("thinking", msg)
	print("[BOT] %s" % msg)

func _delay(seconds: float) -> Signal:
	return _tree.create_timer(seconds).timeout
