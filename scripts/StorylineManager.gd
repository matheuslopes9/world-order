class_name StorylineManager
extends RefCounted
## Storyline System — arcs narrativos com follow-ups condicionais.
##
## Cada storyline tem:
##   - trigger_condition: quando pode disparar (turno mínimo, estado, prob)
##   - trigger_event: o evento inicial (com choices)
##   - nodes: sub-eventos que disparam após delay_turns baseado no choice tomado
##
## A cada turno:
##   1. Verifica storylines não-iniciadas → tenta disparar trigger
##   2. Verifica nodes pendentes → dispara quando chega o turno

signal storyline_triggered(storyline_id: String, event: Dictionary)

var engine = null
var storylines_data: Array = []

# Storylines ativas pra esse save: cada entry = { storyline_id, current_node, fire_turn, choice }
var active_arcs: Array = []
# IDs de storylines já iniciadas (não dispara duas vezes a mesma)
var started_arcs: Array = []

func _init(eng) -> void:
	engine = eng
	_load_data()

func _load_data() -> void:
	var f := FileAccess.open("res://data/storylines.json", FileAccess.READ)
	if f == null: return
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK: return
	var d: Dictionary = json.data
	storylines_data = d.get("storylines", [])
	print("[STORYLINES] %d arcs carregados" % storylines_data.size())

# Chamado todo turno por GameEngine.end_turn()
func process_turn() -> void:
	if engine == null or engine.player_nation == null: return
	# 1. Dispara nodes pendentes que chegaram a hora
	_process_pending_nodes()
	# 2. Tenta iniciar novas storylines
	_try_start_new_arcs()

func _try_start_new_arcs() -> void:
	for arc in storylines_data:
		var arc_dict: Dictionary = arc
		var arc_id: String = arc_dict.get("id", "")
		if arc_id == "" or arc_id in started_arcs: continue
		if not _check_trigger_condition(arc_dict.get("trigger_condition", {})):
			continue
		# Probabilidade
		var prob: float = float(arc_dict.get("trigger_condition", {}).get("probability", 0.0))
		if randf() > prob: continue
		# Dispara evento inicial
		_fire_trigger(arc_dict)
		started_arcs.append(arc_id)
		# Limita 1 por turno pra evitar overload
		break

func _check_trigger_condition(cond: Dictionary) -> bool:
	if engine == null or engine.player_nation == null: return false
	var n = engine.player_nation
	var turn: int = engine.current_turn
	if turn < int(cond.get("min_turn", 0)): return false
	if cond.has("max_turn") and turn > int(cond.get("max_turn", 99999)): return false
	if cond.has("min_apoio_popular") and n.apoio_popular < float(cond.get("min_apoio_popular", 0)): return false
	if cond.has("max_apoio_popular") and n.apoio_popular > float(cond.get("max_apoio_popular", 100)): return false
	if cond.has("min_pib") and n.pib_bilhoes_usd < float(cond.get("min_pib", 0)): return false
	if cond.has("max_pib") and n.pib_bilhoes_usd > float(cond.get("max_pib", 999999)): return false
	if cond.has("min_estabilidade") and n.estabilidade_politica < float(cond.get("min_estabilidade", 0)): return false
	if cond.has("max_estabilidade") and n.estabilidade_politica > float(cond.get("max_estabilidade", 100)): return false
	if cond.has("max_felicidade") and n.felicidade > float(cond.get("max_felicidade", 100)): return false
	# Regime obrigatório
	if cond.has("regime_in"):
		var allowed: Array = cond.get("regime_in", [])
		if allowed.size() > 0 and not (n.regime_politico in allowed):
			return false
	return true

func _fire_trigger(arc: Dictionary) -> void:
	var trigger: Dictionary = arc.get("trigger_event", {})
	if trigger.is_empty(): return
	# Cria evento no formato esperado pelo modal de decisão histórica
	var event: Dictionary = {
		"id": "storyline_%s_trigger" % arc.get("id", ""),
		"headline": trigger.get("headline", ""),
		"body": trigger.get("body", ""),
		"choices": trigger.get("choices", []),
		"categories": ["storyline"],
		"trigger": {"primary_country": engine.player_nation.codigo_iso, "involves": [engine.player_nation.codigo_iso], "region": engine.player_nation.continente},
		"modal_decision": true,
		"is_storyline": true,
		"storyline_id": arc.get("id", ""),
		"color": trigger.get("color", [0.7, 0.5, 1, 1]),
	}
	# Loga em news_history
	if engine.has_method("_log_news"):
		engine._log_news({
			"type": "storyline",
			"headline": "📖 " + String(trigger.get("headline", "")),
			"body": String(trigger.get("body", "")),
			"involves_player": true,
			"color": Color(0.85, 0.6, 1),
		}, [engine.player_nation.codigo_iso], engine.player_nation.continente)
	emit_signal("storyline_triggered", arc.get("id", ""), event)

# Chamado quando jogador escolhe uma opção do trigger ou node
func apply_storyline_choice(storyline_id: String, choice_id: String) -> void:
	var arc: Dictionary = _find_arc(storyline_id)
	if arc.is_empty(): return
	# Acha qual choice foi (do trigger ou de algum node ativo)
	var trigger: Dictionary = arc.get("trigger_event", {})
	var choices: Array = trigger.get("choices", [])
	for c in choices:
		if c.get("id", "") == choice_id:
			_apply_effects(c.get("effects", {}))
			var next_node_id: String = c.get("next_node", "")
			if next_node_id != "":
				_schedule_node(storyline_id, next_node_id)
			return
	# Se não achou no trigger, busca em nodes (caso de node intermediário com choices)
	var nodes: Dictionary = arc.get("nodes", {})
	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		for c in node.get("choices", []):
			if c.get("id", "") == choice_id:
				_apply_effects(c.get("effects", {}))
				var next_id: String = c.get("next_node", "")
				if next_id != "":
					_schedule_node(storyline_id, next_id)
				return

func _schedule_node(storyline_id: String, node_id: String) -> void:
	var arc: Dictionary = _find_arc(storyline_id)
	var nodes: Dictionary = arc.get("nodes", {})
	var node: Dictionary = nodes.get(node_id, {})
	if node.is_empty(): return
	var delay: int = int(node.get("delay_turns", 5))
	active_arcs.append({
		"storyline_id": storyline_id,
		"node_id": node_id,
		"fire_turn": engine.current_turn + delay,
	})

func _process_pending_nodes() -> void:
	var still_pending: Array = []
	for arc_state in active_arcs:
		var entry: Dictionary = arc_state
		if engine.current_turn < int(entry.get("fire_turn", 99999)):
			still_pending.append(entry)
			continue
		# Hora de disparar este node
		var arc: Dictionary = _find_arc(String(entry.get("storyline_id", "")))
		var nodes: Dictionary = arc.get("nodes", {})
		var node: Dictionary = nodes.get(String(entry.get("node_id", "")), {})
		if node.is_empty(): continue
		# Aplica efeitos automáticos (para nodes sem choices)
		if node.has("auto_apply_effects"):
			_apply_effects(node.get("auto_apply_effects", {}))
		# Loga em news_history
		if engine.has_method("_log_news"):
			engine._log_news({
				"type": "storyline_node",
				"headline": "📖 " + String(node.get("headline", "")),
				"body": String(node.get("body", "")),
				"involves_player": true,
				"color": Color(0.85, 0.6, 1),
			}, [engine.player_nation.codigo_iso], engine.player_nation.continente)
		# Se node tem choices, dispara modal
		if node.has("choices") and node.get("choices", []).size() > 0:
			var event: Dictionary = {
				"id": "storyline_%s_%s" % [entry.get("storyline_id"), entry.get("node_id")],
				"headline": node.get("headline", ""),
				"body": node.get("body", ""),
				"choices": node.get("choices", []),
				"categories": ["storyline"],
				"trigger": {"primary_country": engine.player_nation.codigo_iso, "involves": [engine.player_nation.codigo_iso], "region": engine.player_nation.continente},
				"modal_decision": true,
				"is_storyline": true,
				"storyline_id": entry.get("storyline_id"),
				"color": node.get("color", [0.85, 0.6, 1, 1]),
			}
			emit_signal("storyline_triggered", String(entry.get("storyline_id", "")), event)
	active_arcs = still_pending

func _find_arc(storyline_id: String) -> Dictionary:
	for arc in storylines_data:
		if arc.get("id", "") == storyline_id:
			return arc
	return {}

# Aplica effects (formato similar aos events da timeline) ao player
func _apply_effects(effects: Dictionary) -> void:
	if engine == null or engine.player_nation == null: return
	var n = engine.player_nation
	# Player effects
	var player_eff: Dictionary = effects.get("_player", {})
	if not player_eff.is_empty():
		if player_eff.has("pib_fator"):
			n.apply_pib_multiplier(float(player_eff["pib_fator"]))
		if player_eff.has("tesouro"):
			n.tesouro = max(0.0, n.tesouro + float(player_eff["tesouro"]))
		if player_eff.has("estabilidade_fator"):
			n.estabilidade_politica = clamp(n.estabilidade_politica + float(player_eff["estabilidade_fator"]), 0.0, 100.0)
		if player_eff.has("apoio_popular"):
			n.apoio_popular = clamp(n.apoio_popular + float(player_eff["apoio_popular"]), 0.0, 100.0)
		if player_eff.has("felicidade"):
			n.felicidade = clamp(n.felicidade + float(player_eff["felicidade"]), 0.0, 100.0)
		if player_eff.has("corrupcao"):
			n.corrupcao = clamp(n.corrupcao + float(player_eff["corrupcao"]), 0.0, 100.0)
		if player_eff.has("inflacao"):
			n.inflacao = clamp(n.inflacao + float(player_eff["inflacao"]), 0.0, 200.0)
	# Recursos especiais
	var rec_eff: Dictionary = effects.get("_player_recursos", {})
	for k in rec_eff.keys():
		if n.recursos.has(k):
			n.recursos[k] = min(100.0, float(n.recursos[k]) + float(rec_eff[k]))
	# Relações globais (se tiver)
	if effects.has("_global_relations"):
		var delta: float = float(effects["_global_relations"])
		for code in engine.nations.keys():
			if code == n.codigo_iso: continue
			var other = engine.nations[code]
			n.relacoes[code] = clamp(float(n.relacoes.get(code, 0)) + delta, -100.0, 100.0)
			other.relacoes[n.codigo_iso] = clamp(float(other.relacoes.get(n.codigo_iso, 0)) + delta, -100.0, 100.0)
