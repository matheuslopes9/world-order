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
		"date_month": engine.date_month,
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
		"alliances_data": engine.alliances_data,  # membership de blocos muda no jogo (#11)
		"war_objectives": engine._war_objectives,  # objetivo de cada guerra em andamento
		"war_score": engine._war_score,             # placar de cada frente em andamento
		"war_started": engine._war_started,         # turno de início (fadiga de guerra)
		"provinces_owned": _serialize_provinces(engine),  # só as províncias que MUDARAM de dono
		"active_sanctions": engine.active_sanctions,
		"active_trades": engine.active_trades,
		"storyline_active_arcs": engine.storylines.active_arcs if engine.storylines else [],
		"storyline_started_arcs": engine.storylines.started_arcs if engine.storylines else [],
		"player_nemesis": engine.player_nemesis,
		"nemesis_declared": engine.nemesis_declared,
		"victory_achieved": engine.victory_achieved,
		"power_rank_history": engine.player_power_rank_history,
		"market_index": engine.market_index,
		"player_stocks_invested": engine.player_stocks_invested,
		"player_stocks_shares": engine.player_stocks_shares,
		"crypto_price": engine.crypto_price,
		"crypto_cycle": engine.crypto_cycle,
		"player_crypto_invested": engine.player_crypto_invested,
		"player_crypto_coins": engine.player_crypto_coins,
		"crypto_legal_tender": engine.crypto_legal_tender,
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
	if file == null:
		push_error("SaveSystem: não foi possível abrir o save (acesso negado)")
		return false
	var raw := file.get_as_text()
	file.close()
	# Validações de save corrupto (com backup pra debug)
	if raw.length() < 50:
		push_error("SaveSystem: save vazio ou truncado")
		_backup_corrupt_save(raw, "vazio")
		return false
	var json := JSON.new()
	if json.parse(raw) != OK:
		push_error("SaveSystem: JSON inválido — " + json.get_error_message())
		_backup_corrupt_save(raw, "json_invalido")
		return false
	if not (json.data is Dictionary):
		push_error("SaveSystem: estrutura de save inválida")
		_backup_corrupt_save(raw, "estrutura_invalida")
		return false
	var data: Dictionary = json.data
	# Sanity checks: campos obrigatórios
	if not data.has("current_turn") or not data.has("nations"):
		push_error("SaveSystem: save sem campos obrigatórios")
		_backup_corrupt_save(raw, "campos_faltando")
		return false
	# Restaura estado básico
	engine.current_turn = int(data.get("current_turn", 0))
	engine.date_month = int(data.get("date_month", 1))
	engine.date_year = int(data.get("date_year", 2024))
	engine.market_index = float(data.get("market_index", 1000.0))
	engine.player_stocks_invested = float(data.get("player_stocks_invested", 0.0))
	engine.player_stocks_shares = float(data.get("player_stocks_shares", 0.0))
	engine.crypto_price = float(data.get("crypto_price", 1000.0))
	engine.crypto_cycle = float(data.get("crypto_cycle", 0.0))
	engine.player_crypto_invested = float(data.get("player_crypto_invested", 0.0))
	engine.player_crypto_coins = float(data.get("player_crypto_coins", 0.0))
	engine.crypto_legal_tender = bool(data.get("crypto_legal_tender", false))
	engine.defcon = int(data.get("defcon", 5))
	engine.settings = data.get("settings", engine.settings)
	# Restaura membership de blocos (#11) se o save a tiver
	if data.has("alliances_data"):
		engine.alliances_data = data.get("alliances_data", engine.alliances_data)
	engine._war_objectives = data.get("war_objectives", {})
	# Restaura o placar/início das guerras em andamento (evita perder progresso)
	engine._war_score = data.get("war_score", {})
	engine._war_started = data.get("war_started", {})
	# Restaura nações
	_deserialize_nations(engine.nations, data.get("nations", {}))
	# Restaura território conquistado (migração: save antigo sem províncias → mantém
	# o dono original do provinces.json, já carregado no _load_all_data)
	_deserialize_provinces(engine, data.get("provinces_owned", {}))
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
	# Restaura storylines (arcs ativos + iniciados)
	if engine.storylines:
		engine.storylines.active_arcs = data.get("storyline_active_arcs", [])
		engine.storylines.started_arcs = data.get("storyline_started_arcs", [])
	# Restaura antagonista
	engine.player_nemesis = String(data.get("player_nemesis", ""))
	engine.nemesis_declared = bool(data.get("nemesis_declared", false))
	# Restaura estado de vitória (evita re-disparo do modal em modo livre)
	engine.victory_achieved = bool(data.get("victory_achieved", false))
	# Restaura trajetória do ranking de poder
	engine.player_power_rank_history = data.get("power_rank_history", [])
	print("[LOAD] Jogo carregado: turno %d, jogador %s" % [engine.current_turn, player_code])
	return true

# Salva backup do save corrupto pra debug (não sobrescreve o save vivo)
static func _backup_corrupt_save(raw_content: String, reason: String) -> void:
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var backup_path: String = "user://corrupt_save_%s_%s.txt" % [reason, ts]
	var f := FileAccess.open(backup_path, FileAccess.WRITE)
	if f != null:
		f.store_string(raw_content)
		f.close()
		print("[SAVE] Backup do save corrupto: %s" % backup_path)

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
		"date_month": data.get("date_month", 1),
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

# PROVÍNCIAS: só salva as que MUDARAM de dono (owner_iso != core_iso, o dono
# histórico). A geometria/adjacência vem sempre do provinces.json (imutável),
# então o save fica pequeno mesmo com centenas de províncias.
static func _serialize_provinces(engine) -> Dictionary:
	var out := {}
	if not engine.has_method("province_owner"):
		return out
	for pid in engine.provinces:
		var p: Dictionary = engine.provinces[pid]
		var owner: String = String(p.get("owner_iso", ""))
		var core: String = String(p.get("core_iso", owner))
		if owner != core:  # só o que foi conquistado
			out[pid] = owner
	return out

# Restaura o dono das províncias conquistadas. Migração: save antigo sem esse
# campo → dicionário vazio → províncias ficam no dono original (já carregado).
static func _deserialize_provinces(engine, src: Dictionary) -> void:
	if src == null or src.is_empty() or engine.provinces.is_empty():
		return
	for pid in src:
		if not engine.provinces.has(pid):
			continue
		var new_owner: String = String(src[pid])
		if not engine.nations.has(new_owner):
			continue
		# usa a porta oficial pra manter provinces_of consistente (sem mover
		# pop/PIB de novo — isso já está refletido no save das nações)
		var p: Dictionary = engine.provinces[pid]
		var old_owner: String = String(p.get("owner_iso", ""))
		if old_owner == new_owner:
			continue
		p["owner_iso"] = new_owner
		if engine.provinces_of.has(old_owner):
			engine.provinces_of[old_owner].erase(pid)
		if not engine.provinces_of.has(new_owner):
			engine.provinces_of[new_owner] = []
		engine.provinces_of[new_owner].append(pid)

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
			"confianca_investidor": n.confianca_investidor,
			"complexidade_economica": n.complexidade_economica,
			"grau_processamento": n.grau_processamento,
			"empresas_sairam": n.empresas_sairam,
			"tesouro_desviado_total": n.tesouro_desviado_total,
			"defaults_no_historico": n.defaults_no_historico,
			"recursos": n.recursos,
			"militar": n.militar,
			"tecnologias_concluidas": n.tecnologias_concluidas,
			"pesquisa_atual": n.pesquisa_atual,
			"pesquisa_por_ministerio": n.pesquisa_por_ministerio,
			"ministerios": n.ministerios,
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
			# Liderança (Fase 2): muda durante o jogo, precisa persistir
			"personalidade": n.personalidade,
			"ideologia_dominante": n.ideologia_dominante,
			"lider_nome": n.lider_nome,
			"lider_idade": n.lider_idade,
			"lider_desde_turno": n.lider_desde_turno,
			"turnos_impopular": n.turnos_impopular,
			"lideres_passados": n.lideres_passados,
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
		# Migração retrocompatível: saves antigos não têm gabinete
		if n.ministerios == null or n.ministerios.is_empty():
			n._init_ministerios()
		else:
			# Save com gabinete antigo (só nivel/xp/verba): dá nome/idade/etc
			# aos ministros sem esses campos, preservando nível e verba.
			for pasta in n.ministerios:
				var md = n.ministerios[pasta]
				if md is Dictionary and not md.has("nome"):
					var novo = n._new_minister()
					novo["nivel"] = md.get("nivel", 1)
					novo["xp"] = md.get("xp", 0.0)
					novo["verba"] = md.get("verba", 0.0)
					n.ministerios[pasta] = novo
		# Save antigo com fila única de pesquisa → migra p/ trilha da Educação
		if (n.pesquisa_por_ministerio == null or n.pesquisa_por_ministerio.is_empty()) \
				and n.pesquisa_atual != null and typeof(n.pesquisa_atual) == TYPE_DICTIONARY:
			n.pesquisa_por_ministerio = {"educacao": n.pesquisa_atual}

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
