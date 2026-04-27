class_name EventTimelineManager
extends RefCounted
## Gerencia a timeline histórica de eventos (2000-2024) e megatrends (2025-2100).
##
## Modos:
##   "inspirado" — eventos disparam em year_window estrito (1-2 anos de tolerância) + quarter
##   "livre"     — janela alargada ±2 anos; ignora quarter; permite divergências
##
## Eventos são carregados de res://data/events_timeline.json e disparados em order
## de year+quarter. Cada disparo:
##   1) Aplica effects_immediate (efeitos sem decisão)
##   2) Se modal_decision=true e jogador é primary_country → emite sinal pra UI mostrar modal
##   3) Senão aplica primeira choice como default
##   4) Loga em news_history via _log_news

signal historic_event_decision(event: Dictionary)  # UI escuta pra abrir modal

var engine = null  # GameEngine — referência fraca pra estado global

# Eventos âncora/secundários (gatilho temporal estrito por ano+quarter)
var pending_events: Array = []

# Megatrends 2025-2100 (gatilho probabilístico por turno dentro de janela de décadas)
var megatrends: Array = []

# IDs já disparados (pra evitar repetir + permitir histórico).
# Persistido no save.
var fired_event_ids: Array = []

# Histórico de decisões do jogador em eventos com modal.
# Cada entry: { event_id, choice_id, choice_label, turn, year }
# Persistido no save — usado em estatísticas de divergência.
var decision_log: Array = []

func _init(eng) -> void:
	engine = eng
	_load_timeline()
	_generate_secondary_events()
	_load_megatrends()

func _load_megatrends() -> void:
	var f := FileAccess.open("res://data/megatrends_2025_2100.json", FileAccess.READ)
	if f == null: return
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK: return
	var d: Dictionary = json.data
	megatrends = d.get("events", [])
	print("[TIMELINE] %d megatrends 2025-2100 carregados" % megatrends.size())

# Carrega events_timeline.json + megatrends_2025_2100.json (FASE 6 cria o segundo)
func _load_timeline() -> void:
	var f := FileAccess.open("res://data/events_timeline.json", FileAccess.READ)
	if f != null:
		var raw := f.get_as_text()
		f.close()
		var json := JSON.new()
		if json.parse(raw) == OK:
			var d: Dictionary = json.data
			pending_events = d.get("events", [])
			print("[TIMELINE] %d eventos âncora carregados" % pending_events.size())

# ─────────────────────────────────────────────────────────────────
# FASE 5: GERA EVENTOS SECUNDÁRIOS POR PAÍS
# 3 eventos por país, distribuídos pelos 25 anos (2000-2024).
# Determinístico: mesmo país sempre tem mesmos eventos (seed = hash do ISO).
# ─────────────────────────────────────────────────────────────────

func _generate_secondary_events() -> void:
	if engine == null or engine.nations.is_empty(): return
	var f := FileAccess.open("res://data/event_templates.json", FileAccess.READ)
	if f == null: return
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK: return
	var d: Dictionary = json.data
	var templates: Dictionary = d.get("templates", {})
	var weights_by_tier: Dictionary = d.get("weights_by_tier", {})
	var generated: int = 0
	for code in engine.nations.keys():
		var n = engine.nations[code]
		var tier: String = n.tier_dificuldade
		var weights: Dictionary = weights_by_tier.get(tier, weights_by_tier.get("NORMAL", {}))
		# Seed determinístico: mesmo país sempre gera os mesmos 3 eventos
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(code)
		# Escolhe 3 anos diferentes entre 2000-2024
		var years_used: Array = []
		for i in 3:
			var year: int = 2000 + rng.randi_range(0, 24)
			# Tenta não repetir o mesmo ano
			var attempts: int = 0
			while year in years_used and attempts < 5:
				year = 2000 + rng.randi_range(0, 24)
				attempts += 1
			years_used.append(year)
			# Escolhe categoria pesada por tier
			var cat: String = _weighted_pick(weights, rng)
			var pool: Array = templates.get(cat, [])
			if pool.is_empty(): continue
			var tpl: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			# Monta o evento
			var ev: Dictionary = {
				"id": "%s_%s_%d" % [code.to_lower(), tpl.get("id_suffix", "evt"), year],
				"year": year,
				"quarter": rng.randi_range(1, 4),
				"year_window": [year, year],
				"scope": "national",
				"categories": [cat],
				"trigger": {"primary_country": code, "involves": [code], "region": n.continente},
				"headline": String(tpl.get("headline", "")).replace("{PAIS}", n.nome).replace("{PARTIDO}", _random_partido(rng)),
				"body": String(tpl.get("body", "")).replace("{PAIS}", n.nome).replace("{PARTIDO}", _random_partido(rng)),
				"effects": {code: tpl.get("effects", {}).duplicate()},
				"modal_decision": false,
			}
			pending_events.append(ev)
			generated += 1
	print("[TIMELINE] %d eventos secundários gerados (3/país × 195 países)" % generated)

func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	# Escolha ponderada: soma os weights e roleta
	var total: float = 0.0
	for v in weights.values():
		total += float(v)
	var r: float = rng.randf() * total
	var acc: float = 0.0
	for k in weights.keys():
		acc += float(weights[k])
		if r <= acc:
			return String(k)
	return String(weights.keys()[0]) if weights.size() > 0 else "social"

func _random_partido(rng: RandomNumberGenerator) -> String:
	var nomes: Array = [
		"Aliança Nacional", "União Democrática", "Partido Progressista",
		"Frente Conservadora", "Movimento Reformista", "Coligação Centrista",
		"Bloco Trabalhista", "Coalizão Liberal", "Partido Verde",
		"Renovação Popular"
	]
	return nomes[rng.randi_range(0, nomes.size() - 1)]

# Chamado a cada turno por GameEngine.end_turn() pra checar gatilhos
func process_turn() -> void:
	if engine == null: return
	if engine.player_nation == null: return
	# 1. Eventos com gatilho temporal estrito (âncora + secundários)
	var to_fire: Array = []
	for ev in pending_events:
		var ev_dict: Dictionary = ev
		var eid: String = ev_dict.get("id", "")
		if eid == "" or eid in fired_event_ids:
			continue
		if _should_fire(ev_dict):
			to_fire.append(ev_dict)
	for ev in to_fire:
		_fire_event(ev)
	# 2. Megatrends (gatilho probabilístico)
	_process_megatrends()

func _process_megatrends() -> void:
	if engine == null or megatrends.is_empty(): return
	var year: int = engine.date_year
	var mode: String = engine.settings.get("mode", "inspirado")
	# RNG fresco a cada turno — não determinístico (megatrends são naturalmente caóticas)
	for ev in megatrends:
		var ev_dict: Dictionary = ev
		var eid: String = ev_dict.get("id", "")
		if eid == "" or eid in fired_event_ids:
			continue
		var lo: int = int(ev_dict.get("decade_start", 9999))
		var hi: int = int(ev_dict.get("decade_end", 0))
		if mode == "livre":
			# Mais permissivo: alarga em ±3 anos
			lo -= 3
			hi += 3
		if year < lo or year > hi:
			continue
		# Pré-condição (alguns megatrends precisam de outro evento ter ocorrido antes)
		var requires: String = ev_dict.get("requires_fired", "")
		if requires != "" and not (requires in fired_event_ids):
			continue
		# Probabilidade crescente: linearmente por quanto avançamos na janela
		var base_prob: float = float(ev_dict.get("base_prob", 0.02))
		var window_size: int = max(1, hi - lo + 1)
		var progress: float = float(year - lo) / float(window_size)  # 0.0 → 1.0 conforme avança
		# Probabilidade efetiva: base * (1 + progress) — dobra no fim da janela
		var effective_prob: float = base_prob * (1.0 + progress)
		if randf() < effective_prob:
			_fire_event(ev_dict)

# Helper: testa se evento deve disparar agora dado modo + ano + quarter
func _should_fire(ev: Dictionary) -> bool:
	if engine == null: return false
	var year: int = engine.date_year
	var quarter: int = engine.date_quarter
	var mode: String = engine.settings.get("mode", "inspirado")
	# Janela de tempo
	var window: Array = ev.get("year_window", [])
	var lo: int = 0
	var hi: int = 0
	if window.size() == 2:
		lo = int(window[0])
		hi = int(window[1])
	else:
		lo = int(ev.get("year", 0))
		hi = lo
	if mode == "livre":
		# Alarga janela em ±2 anos no modo livre
		lo -= 2
		hi += 2
	if year < lo or year > hi:
		return false
	# Quarter (só importa no modo inspirado)
	if mode == "inspirado":
		var ev_q: int = int(ev.get("quarter", 0))
		if ev_q > 0 and quarter != ev_q:
			# Ainda permite no último ano da janela se ainda não disparou (catch-up)
			if year >= hi and quarter > ev_q:
				pass  # permite (já passou do quarter, mas ainda no ano final)
			else:
				return false
	# else "livre": qualquer quarter dentro da janela vale
	return true

# Aplica efeitos + modal/choice + log
func _fire_event(ev: Dictionary) -> void:
	var eid: String = ev.get("id", "")
	fired_event_ids.append(eid)

	# 1) Aplica effects (efeitos por país sem decisão)
	var effects_per_country: Dictionary = ev.get("effects", {})
	for code in effects_per_country.keys():
		if code == "_player":
			# placeholder pra "jogador" — só vale em choices. Aqui ignora.
			continue
		_apply_effects_to_nation(code, effects_per_country[code])
	# Efeitos globais
	var global_eff: Dictionary = ev.get("effects_global", {})
	if global_eff.size() > 0:
		_apply_global_effects(global_eff)

	# 2) Decisão? Se sim e jogador é primary, abre modal
	var primary: String = ev.get("trigger", {}).get("primary_country", "")
	var is_player: bool = (engine.player_nation != null and engine.player_nation.codigo_iso == primary)
	var has_choice: bool = bool(ev.get("modal_decision", false)) and ev.get("choices", []).size() > 0
	if has_choice and is_player:
		# Emite signal pra UI (FASE 4 conecta o modal)
		emit_signal("historic_event_decision", ev)
	elif has_choice:
		# Não é o jogador — aplica default = primeira choice (IA neutra)
		var first_choice: Dictionary = ev.get("choices", [])[0]
		_apply_choice_effects(ev, first_choice)

	# 3) Loga em news_history
	var involves: Array = ev.get("trigger", {}).get("involves", [])
	if involves.is_empty() and primary != "":
		involves = [primary]
	var region: String = ev.get("trigger", {}).get("region", "")
	var color: Color = _color_for_event(ev)
	if engine.has_method("_log_news"):
		engine._log_news({
			"type": "historic_" + String(ev.get("categories", ["geral"])[0]),
			"headline": ev.get("headline", ""),
			"body": ev.get("body", ""),
			"involves_player": is_player,
			"color": color,
			"historic_id": eid,
		}, involves, region)

# Aplica os effects do choice escolhido (público pra modal chamar depois)
func apply_choice_by_id(event_id: String, choice_id: String) -> void:
	var ev := _find_event(event_id)
	if ev.is_empty(): return
	for c in ev.get("choices", []):
		if String(c.get("id", "")) == choice_id:
			_apply_choice_effects(ev, c)
			# Registra a decisão pra estatísticas
			decision_log.append({
				"event_id": event_id,
				"event_headline": ev.get("headline", ""),
				"choice_id": choice_id,
				"choice_label": c.get("label", ""),
				"turn": engine.current_turn if engine else 0,
				"year": engine.date_year if engine else 0,
			})
			return

func _find_event(eid: String) -> Dictionary:
	for ev in pending_events:
		if String(ev.get("id", "")) == eid:
			return ev
	for ev in megatrends:
		if String(ev.get("id", "")) == eid:
			return ev
	return {}

func _apply_choice_effects(_ev: Dictionary, choice: Dictionary) -> void:
	var eff: Dictionary = choice.get("effects", {})
	for code in eff.keys():
		if code == "_player":
			if engine.player_nation != null:
				_apply_effects_to_nation(engine.player_nation.codigo_iso, eff[code])
		else:
			_apply_effects_to_nation(code, eff[code])

# ─────────────────────────────────────────────────────────────────
# APLICAÇÃO DE EFEITOS
# ─────────────────────────────────────────────────────────────────

func _apply_effects_to_nation(code: String, eff: Dictionary) -> void:
	if engine == null or not engine.nations.has(code): return
	var n = engine.nations[code]
	if eff.has("pib_fator"):
		n.apply_pib_multiplier(float(eff["pib_fator"]))
	if eff.has("tesouro"):
		n.tesouro = max(0.0, n.tesouro + float(eff["tesouro"]))
	if eff.has("estabilidade_fator"):
		n.estabilidade_politica = clamp(n.estabilidade_politica + float(eff["estabilidade_fator"]), 0.0, 100.0)
	if eff.has("apoio_popular"):
		n.apoio_popular = clamp(n.apoio_popular + float(eff["apoio_popular"]), 0.0, 100.0)
	if eff.has("felicidade"):
		n.felicidade = clamp(n.felicidade + float(eff["felicidade"]), 0.0, 100.0)
	if eff.has("corrupcao"):
		n.corrupcao = clamp(n.corrupcao + float(eff["corrupcao"]), 0.0, 100.0)
	if eff.has("inflacao"):
		n.inflacao = clamp(n.inflacao + float(eff["inflacao"]), 0.0, 200.0)

func _apply_global_effects(eff: Dictionary) -> void:
	if engine == null: return
	if eff.has("pib_fator"):
		var f: float = float(eff["pib_fator"])
		for code in engine.nations.keys():
			engine.nations[code].apply_pib_multiplier(f)
	if eff.has("defcon_delta"):
		engine.defcon = clamp(engine.defcon + int(eff["defcon_delta"]), 1, 5)

# Retorna eventos âncora (modal_decision=true) que devem disparar nos próximos N turnos.
# Usado pra avisar o jogador "evento histórico próximo" antes da hora.
func get_upcoming_decisions(turns_ahead: int = 2) -> Array:
	if engine == null or engine.player_nation == null: return []
	var current_year: int = engine.date_year
	var current_quarter: int = engine.date_quarter
	var p_code: String = engine.player_nation.codigo_iso
	var out: Array = []
	for ev in pending_events:
		var ev_dict: Dictionary = ev
		if ev_dict.get("id", "") in fired_event_ids:
			continue
		if not ev_dict.get("modal_decision", false):
			continue
		# Só interessa se jogador for o country primary
		if ev_dict.get("trigger", {}).get("primary_country", "") != p_code:
			continue
		var ev_year: int = int(ev_dict.get("year", 0))
		var ev_q: int = int(ev_dict.get("quarter", 1))
		# Calcula distância em turnos
		var diff: int = (ev_year - current_year) * 4 + (ev_q - current_quarter)
		if diff > 0 and diff <= turns_ahead:
			out.append({"event": ev_dict, "turns_until": diff})
	return out

func _color_for_event(ev: Dictionary) -> Color:
	var cats: Array = ev.get("categories", [])
	if cats.has("guerra") or cats.has("terrorismo"):
		return Color(1, 0.35, 0.35)
	if cats.has("crise") or cats.has("economia"):
		return Color(1, 0.78, 0.30)
	if cats.has("pandemia") or cats.has("desastre_natural"):
		return Color(0.85, 0.45, 1)
	if cats.has("politica") or cats.has("revolucao"):
		return Color(0.4, 0.85, 1)
	if cats.has("clima"):
		return Color(0.4, 1, 0.6)
	return Color(0.7, 0.85, 1)
