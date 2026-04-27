class_name SaveSystem
extends RefCounted
## Sistema de save/load via JSON local.
## Salva nações + estado do jogo + tratados + log de espionagem.

const SAVE_PATH := "user://world_order_save.json"

static func save_game(engine) -> bool:
	var data := {
		"version": "0.3.0-godot",
		"timestamp": Time.get_datetime_string_from_system(),
		"current_turn": engine.current_turn,
		"date_quarter": engine.date_quarter,
		"date_year": engine.date_year,
		"defcon": engine.defcon,
		"settings": engine.settings,
		"player_code": engine.player_nation.codigo_iso if engine.player_nation else "",
		"nations": _serialize_nations(engine.nations),
		"treaties": engine.diplomacy.treaties if engine.diplomacy else [],
		"proposals": engine.diplomacy.proposals if engine.diplomacy else [],
		"news_history": _serialize_news(engine.news_history),
		"fired_event_ids": engine.timeline.fired_event_ids if engine.timeline else [],
		"decision_log": engine.timeline.decision_log if engine.timeline else [],
		"player_actions_remaining": engine.player_actions_remaining,
		"active_sanctions": engine.active_sanctions,
		"active_trades": engine.active_trades,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: não foi possível abrir " + SAVE_PATH + " para escrita")
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	print("[SAVE] Jogo salvo: turno %d, jogador %s" % [engine.current_turn, data["player_code"]])
	return true

static func load_game(engine) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return false
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		push_error("SaveSystem: erro ao parsear save: " + json.get_error_message())
		return false
	var data: Dictionary = json.data
	# Restaura estado básico
	engine.current_turn = int(data.get("current_turn", 0))
	engine.date_quarter = int(data.get("date_quarter", 1))
	engine.date_year = int(data.get("date_year", 2024))
	engine.defcon = int(data.get("defcon", 5))
	engine.settings = data.get("settings", engine.settings)
	# Restaura nações
	_deserialize_nations(engine.nations, data.get("nations", {}))
	# Restaura jogador
	var player_code: String = data.get("player_code", "")
	if player_code != "" and engine.nations.has(player_code):
		engine.player_nation = engine.nations[player_code]
	# Restaura tratados
	if engine.diplomacy:
		engine.diplomacy.treaties = data.get("treaties", [])
		engine.diplomacy.proposals = data.get("proposals", [])
	# Restaura histórico de notícias
	engine.news_history = _deserialize_news(data.get("news_history", []))
	# Restaura eventos históricos já disparados
	if engine.timeline:
		engine.timeline.fired_event_ids = data.get("fired_event_ids", [])
		engine.timeline.decision_log = data.get("decision_log", [])
	# Restaura ações restantes do turno (se save foi feito mid-turno)
	engine.player_actions_remaining = int(data.get("player_actions_remaining", engine.PLAYER_ACTIONS_PER_TURN))
	# Restaura sanções ativas
	engine.active_sanctions = data.get("active_sanctions", [])
	# Restaura acordos comerciais ativos
	engine.active_trades = data.get("active_trades", [])
	print("[LOAD] Jogo carregado: turno %d, jogador %s" % [engine.current_turn, player_code])
	return true

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func get_save_info() -> Dictionary:
	if not has_save(): return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return {}
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK: return {}
	var data: Dictionary = json.data
	return {
		"timestamp": data.get("timestamp", "?"),
		"current_turn": data.get("current_turn", 0),
		"player_code": data.get("player_code", "?"),
		"defcon": data.get("defcon", 5),
		"date_year": data.get("date_year", 2024),
		"date_quarter": data.get("date_quarter", 1),
	}

static func delete_save() -> bool:
	if not has_save(): return false
	var dir := DirAccess.open("user://")
	if dir == null: return false
	dir.remove("world_order_save.json")
	return true

# ─────────────────────────────────────────────────────────────────
# SERIALIZAÇÃO INTERNA
# ─────────────────────────────────────────────────────────────────

static func _serialize_nations(nations: Dictionary) -> Dictionary:
	var out := {}
	for code in nations:
		var n = nations[code]
		out[code] = {
			"codigo_iso": n.codigo_iso,
			"nome": n.nome,
			"continente": n.continente,
			"capital": n.capital,
			"regime_politico": n.regime_politico,
			"populacao": n.populacao,
			"pib_bilhoes_usd": n.pib_bilhoes_usd,
			"tesouro": n.tesouro,
			"divida_publica": n.divida_publica,
			"inflacao": n.inflacao,
			"estabilidade_politica": n.estabilidade_politica,
			"apoio_popular": n.apoio_popular,
			"corrupcao": n.corrupcao,
			"burocracia_eficiencia": n.burocracia_eficiencia,
			"felicidade": n.felicidade,
			"recursos": n.recursos,
			"militar": n.militar,
			"tecnologias_concluidas": n.tecnologias_concluidas,
			"pesquisa_atual": n.pesquisa_atual,
			"velocidade_pesquisa": n.velocidade_pesquisa,
			"relacoes": n.relacoes,
			"em_guerra": n.em_guerra,
			"intel_score": n.intel_score,
			"seguranca_intel": n.seguranca_intel,
			"spy_ops_log": n.spy_ops_log,
			"gasto_social": n.gasto_social,
			"revolucao_turnos": n.revolucao_turnos,
			"falencia_turnos": n.falencia_turnos,
			"default_turnos": n.default_turnos,
			"tier_dificuldade": n.tier_dificuldade,
		}
	return out

static func _deserialize_nations(target: Dictionary, src: Dictionary) -> void:
	for code in src:
		if not target.has(code): continue
		var n = target[code]
		var d: Dictionary = src[code]
		for key in d:
			if key in n:
				n.set(key, d[key])

# JSON não suporta Color — converte pra [r,g,b,a] na serialização e de volta no load
static func _serialize_news(history: Array) -> Array:
	var out: Array = []
	for entry in history:
		var copy: Dictionary = entry.duplicate()
		if copy.has("color") and copy["color"] is Color:
			var c: Color = copy["color"]
			copy["color"] = [c.r, c.g, c.b, c.a]
		out.append(copy)
	return out

static func _deserialize_news(raw: Array) -> Array:
	var out: Array = []
	for entry in raw:
		if not (entry is Dictionary): continue
		var copy: Dictionary = entry.duplicate()
		if copy.has("color") and copy["color"] is Array:
			var arr: Array = copy["color"]
			if arr.size() >= 3:
				copy["color"] = Color(arr[0], arr[1], arr[2], arr[3] if arr.size() > 3 else 1.0)
		out.append(copy)
	return out
