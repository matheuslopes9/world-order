extends Node
## Singleton global do jogo (Autoload).
## Carrega dados, mantém estado, gerencia turnos.

const NationScript := preload("res://scripts/Nation.gd")
const DiplomacyScript := preload("res://scripts/DiplomacyManager.gd")
const NewsScript := preload("res://scripts/NewsManager.gd")
const TechScript := preload("res://scripts/TechManager.gd")
const EspionageScript := preload("res://scripts/EspionageManager.gd")
const TimelineScript := preload("res://scripts/EventTimeline.gd")

var diplomacy = null  # DiplomacyManager
var news = null       # NewsManager
var tech = null       # TechManager
var espionage = null  # EspionageManager
var timeline = null   # EventTimelineManager

# ── Estado do jogo ───────────────────────────────────────────────
var nations: Dictionary = {}             # code → Nation
var player_nation = null  # Nation
var current_turn: int = 0
var date_quarter: int = 1
var date_year: int = 2000  # Jogo começa no ano 2000 (campanha 100 anos até 2100)

# Limite de ações por turno (jogador) — equilibra jogo entre nações grandes e pequenas
const PLAYER_ACTIONS_PER_TURN: int = 3
var player_actions_remaining: int = PLAYER_ACTIONS_PER_TURN

signal player_actions_changed(remaining: int)

func _consume_action() -> bool:
	if player_actions_remaining <= 0:
		return false
	player_actions_remaining -= 1
	emit_signal("player_actions_changed", player_actions_remaining)
	return true

func can_player_act() -> bool:
	return player_actions_remaining > 0
var defcon: int = 5
var game_state: String = "MENU"           # MENU, SELECTING, PLAYING, ENDGAME
var recent_events: Array = []
# Histórico persistente de notícias com metadados pra filtros (até 500 entradas)
# Cada entry: { turn, type, headline, body, color, involves: [iso_codes], region, scope }
# scope: "national" | "regional" | "global"
var news_history: Array = []
const NEWS_HISTORY_MAX: int = 500

# Sanções ativas — lista de { from, to, turns_remaining, intensity }
# Aplicadas a cada turno em _process_active_sanctions()
var active_sanctions: Array = []
const SANCTION_DURATION: int = 5  # turnos de duração padrão
const SANCTION_PIB_PENALTY: float = 0.985  # -1.5% PIB/turno no alvo
const SANCTION_COST: int = 30  # $30B custo pro impositor (logística, perdas comerciais)

# Acordos comerciais ativos — lista de { exporter, importer, resource, value_per_turn, turns_remaining }
# Cada turno: importer paga $value/turn ao exporter, exporter ganha receita
var active_trades: Array = []
const TRADE_DURATION: int = 8  # turnos por contrato
const TRADE_BASE_VALUE: float = 8.0  # $8B/turno por nível 100 do recurso (escala linear)

# Helper: adiciona evento ao recent_events E ao news_history persistente com metadados
# involves: array de códigos ISO de nações envolvidas no evento (vazio = global)
# region: continente do evento (vazio = sem região específica)
func _log_news(entry: Dictionary, involves: Array = [], region: String = "") -> void:
	# Mantém o append em recent_events pra compatibilidade com ticker
	recent_events.append(entry)
	# Cria versão enriquecida pra histórico
	var rich := entry.duplicate()
	rich["turn"] = current_turn
	rich["involves"] = involves
	rich["region"] = region
	# scope é derivado: nacional > regional > global
	if player_nation != null and player_nation.codigo_iso in involves:
		rich["scope"] = "national"
	elif region != "" and player_nation != null and region == player_nation.continente:
		rich["scope"] = "regional"
	else:
		rich["scope"] = "global"
	news_history.append(rich)
	# Limita tamanho — descarta os mais antigos
	if news_history.size() > NEWS_HISTORY_MAX:
		news_history = news_history.slice(news_history.size() - NEWS_HISTORY_MAX, news_history.size())
var settings: Dictionary = {
	"difficulty": "normal",
	"ai_speed": 8,
	"notifications": "all",
	# Modo da campanha:
	#   "inspirado" — eventos históricos disparam em janelas reais (11/9 em 2001, etc)
	#   "livre"     — eventos disparam com janelas alargadas, IA reage sem constraint histórico
	"mode": "inspirado"
}

# ── Dados estáticos ──────────────────────────────────────────────
var difficulty_tiers: Dictionary = {}    # code → tier
var alliances_data: Array = []
var events_data: Array = []
var tech_data: Dictionary = {}
var personalities_data: Dictionary = {}

# ── Sinais ───────────────────────────────────────────────────────
signal data_loaded
signal nation_selected(code: String)
signal player_confirmed(code: String)
signal turn_advanced(turn: int)

func _ready() -> void:
	_load_all_data()
	diplomacy = DiplomacyScript.new(self)
	news = NewsScript.new(self)
	tech = TechScript.new(self)
	espionage = EspionageScript.new(self)
	timeline = TimelineScript.new(self)

func _load_all_data() -> void:
	var t0 := Time.get_ticks_msec()
	difficulty_tiers   = _load_json("res://data/difficulty-tiers.json")
	var alliances_raw  = _load_json("res://data/alliances.json")
	alliances_data     = alliances_raw.get("alliances", []) if alliances_raw else []
	var events_raw     = _load_json("res://data/events.json")
	events_data        = events_raw.get("eventos", []) if events_raw else []
	tech_data          = _load_json("res://data/tech.json")
	personalities_data = _load_json("res://data/personalities.json")
	var nations_raw    = _load_json("res://data/nations.json")
	if nations_raw:
		var ns_dict: Dictionary = nations_raw.get("nations", {})
		for code in ns_dict:
			var n = NationScript.new()
			var tier: String = difficulty_tiers.get(code, "")
			n.from_dict(ns_dict[code], code, tier)
			nations[code] = n
	# Se a campanha começa em 2000, aplica overrides daquele ano
	if date_year <= 2000:
		_apply_year_2000_overrides()
	var t1 := Time.get_ticks_msec()
	print("[ENGINE] %d nações + %d eventos + %d alianças carregados em %d ms" %
		[nations.size(), events_data.size(), alliances_data.size(), t1 - t0])
	emit_signal("data_loaded")

# Aplica overrides de nations_2000.json — re-escreve PIB/pop/estab/etc das nações
# pra refletir o mundo do ano 2000.
func _apply_year_2000_overrides() -> void:
	var raw = _load_json("res://data/nations_2000.json")
	if raw == null: return
	var overrides: Dictionary = raw.get("overrides", {})
	var globals: Dictionary = raw.get("global_overrides", {})
	var pib_scale: float = float(globals.get("pib_scale", 1.0))
	var tesouro_scale: float = float(globals.get("tesouro_scale", 1.0))
	var inf_baseline: float = float(globals.get("inflacao_baseline", 5.0))
	var tech_max: int = int(globals.get("tech_count_max", 3))
	var universal_tech: Array = raw.get("tech_universal_2000", [])
	var changed_explicit: int = 0
	var changed_global: int = 0
	for code in nations.keys():
		var n = nations[code]
		# Sempre limpa techs (depois reaplica universais)
		n.tecnologias_concluidas = universal_tech.duplicate()
		n.pesquisa_atual = null
		n.divida_publica = 0.0
		# Limpa estado de guerra/relações pra começar do zero (situação política reseta)
		n.em_guerra = []
		n.relacoes = {}
		# Override explícito
		if overrides.has(code):
			var ov: Dictionary = overrides[code]
			for key in ov.keys():
				if key in ["lider_atual", "contexto"]:
					continue  # campos descritivos, não aplicáveis ao Nation
				if key in n:
					n.set(key, ov[key])
			changed_explicit += 1
		else:
			# Aplica escala global pra países sem override (não temos dados precisos)
			n.pib_bilhoes_usd = n.pib_bilhoes_usd * pib_scale
			n.tesouro = n.tesouro * tesouro_scale
			n.inflacao = max(n.inflacao, inf_baseline)
			# Limita tech inicial a alguns universais
			while n.tecnologias_concluidas.size() > tech_max:
				n.tecnologias_concluidas.pop_back()
			changed_global += 1
		# Recalcula tier de dificuldade SEMPRE (mundo de 2000 é diferente de 2024)
		# Antes: usava difficulty_tiers.json (que reflete cenário 2024) — gerava inversão NORMAL>DIFICIL
		n.tier_dificuldade = n._compute_difficulty_tier()
	print("[2000] Overrides aplicados: %d explícitos + %d via escala global" % [changed_explicit, changed_global])

func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Arquivo não encontrado: %s" % path)
		return null
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		push_error("Erro ao parsear %s: %s" % [path, json.get_error_message()])
		return null
	return json.data

# ── Seleção de nação ─────────────────────────────────────────────

func select_nation(code: String) -> void:
	if nations.has(code):
		emit_signal("nation_selected", code)

func confirm_player_nation(code: String) -> void:
	if not nations.has(code):
		return
	player_nation = nations[code]
	game_state = "PLAYING"
	# Aplica multiplicador combinado: dificuldade global × bônus de tier nacional
	# Países difíceis recebem boost extra de tesouro inicial pra não ficarem sem opções
	var diff: String = settings.get("difficulty", "normal")
	var diff_mult: float = float({"easy": 1.5, "normal": 1.0, "hard": 0.7, "brutal": 0.4}.get(diff, 1.0))
	# Curva monotônica: tiers mais difíceis recebem MAIS boost
	var tier_mult: float = float({
		"FACIL": 1.3, "NORMAL": 1.6, "DIFICIL": 2.2,
		"MUITO_DIFICIL": 2.8, "QUASE_IMPOSSIVEL": 3.5
	}.get(player_nation.tier_dificuldade, 1.0))
	player_nation.tesouro = round(player_nation.tesouro * diff_mult * tier_mult)
	current_turn = 1
	emit_signal("player_confirmed", code)
	print("[ENGINE] Comando assumido: %s (Tier: %s, Tesouro: $%dB | mult=%.2f×%.2f)" %
		[player_nation.nome, player_nation.tier_dificuldade, int(player_nation.tesouro), diff_mult, tier_mult])

# ── Turno ────────────────────────────────────────────────────────

func end_turn() -> void:
	if game_state != "PLAYING":
		return
	current_turn += 1
	date_quarter += 1
	if date_quarter > 4:
		date_quarter = 1
		date_year += 1
	# Processa todas as nações
	for code in nations:
		var n = nations[code]
		n.update_pib(1.0)
		n.update_government(0.02)
		n.update_approval()
		n.process_turn_finances()
		n.update_elections()
		n.record_history()

	# IA: nações estrategicamente decidem (declarar guerra, propor paz, espionar)
	_run_ai_turn()
	# Custos contínuos de guerra
	_process_war_costs()
	# Sanções ativas: aplica penalidade nos alvos e decrementa duração
	_process_active_sanctions()
	# Comércio bilateral: transfere $ entre exportador/importador
	_process_active_trades()
	# Eventos aleatórios
	_roll_events()
	# Diplomacia: aplica tratados, processa propostas
	if diplomacy:
		diplomacy.process_turn()
	# Pesquisa: progride techs em andamento, aplica efeitos
	if tech:
		tech.process_turn()
	# Timeline histórica: dispara eventos âncora se chegou o momento
	if timeline:
		timeline.process_turn()
	# Notícias procedurais
	if news:
		var generated: Array = news.generate_turn_news()
		for n in generated:
			var inv: Array = n.get("involves", [])
			var reg: String = n.get("region", "")
			_log_news({
				"type": "news_" + n.get("category", ""),
				"headline": "%s %s" % [n.get("icon", ""), n.get("text", "")],
				"body": "",
				"involves_player": (player_nation != null and player_nation.codigo_iso in inv),
				"color": n.get("color", Color(0.7, 0.8, 1)),
			}, inv, reg)

	# Reset de ações do jogador para o novo turno
	player_actions_remaining = PLAYER_ACTIONS_PER_TURN
	emit_signal("player_actions_changed", player_actions_remaining)

	emit_signal("turn_advanced", current_turn)

# ─────────────────────────────────────────────────────────────────
# IA — nações NPCs decidem ações por turno
# ─────────────────────────────────────────────────────────────────

func _run_ai_turn() -> void:
	# Seleciona ~8 nações aleatoriamente (não todas, pra performance) — exclui jogador
	var codes: Array = nations.keys()
	codes.shuffle()
	var max_actors: int = settings.get("ai_speed", 8)
	var acted: int = 0
	for code in codes:
		if code == player_nation.codigo_iso:
			continue
		var n = nations[code]
		_ai_decide(n)
		acted += 1
		if acted >= max_actors:
			break

func _ai_decide(n) -> void:
	var aggro: float = _get_aggression(n)
	var treasury: float = n.tesouro
	var stab: float = n.estabilidade_politica

	# 1. PROPOR PAZ — exausto em guerra
	if n.em_guerra.size() > 0:
		var peace_urgency: float = (0.4 if treasury < 50.0 else 0.0) + (0.3 if stab < 40.0 else 0.0) + (1.0 - aggro) * 0.3
		if randf() < peace_urgency and treasury >= 20.0:
			var target: String = n.em_guerra[randi() % n.em_guerra.size()]
			_propose_peace(n.codigo_iso, target)
			return

	# 2. DECLARAR GUERRA — agressivo, com tesouro, sem guerra atual
	if n.em_guerra.size() == 0 and treasury >= 80.0 and stab >= 50.0:
		# Procura rival: pior relação CONHECIDA OU qualquer vizinho viável
		var worst_code: String = ""
		var worst_rel: float = 1000.0
		for c in n.relacoes:
			var r: float = n.relacoes[c]
			if r < worst_rel and c != n.codigo_iso:
				if nations.has(c) and not (n.codigo_iso in nations[c].em_guerra):
					worst_rel = r
					worst_code = c
		# Fallback: se não achou rival na lista, escolhe vizinho geográfico aleatório
		if worst_code == "" or worst_rel >= 0.0:
			var candidates: Array = []
			for c in nations:
				if c == n.codigo_iso: continue
				var other = nations[c]
				if other.continente == n.continente and not (n.codigo_iso in other.em_guerra):
					candidates.append(c)
			if candidates.size() > 0:
				worst_code = candidates[randi() % candidates.size()]
				worst_rel = -30.0  # tensão regional baseline
		if worst_code != "":
			# Chance baseada em agressividade: 0.5% (pacífico) até 5% (Putin/Kim) por turno
			var rel_factor: float = clamp((100.0 + worst_rel) / 100.0 + 0.5, 0.3, 1.5)
			var war_chance: float = aggro * 0.05 * rel_factor
			if randf() < war_chance:
				_declare_war(n.codigo_iso, worst_code)
				return

	# 3. AÇÃO TÁTICA simples (investe pequeno em saúde/propaganda)
	if treasury >= 20.0 and randf() < 0.4:
		treasury -= 20.0
		n.tesouro = treasury
		var mult: float = n.get_action_multiplier()
		if randf() < 0.5:
			n.felicidade = min(100.0, n.felicidade + 4.0 * mult)
			n.apoio_popular = min(100.0, n.apoio_popular + 2.0 * mult)
		else:
			n.apoio_popular = min(100.0, n.apoio_popular + 10.0 * mult)

func _get_aggression(n) -> float:
	var pers_id: String = n.personalidade
	var personalities: Dictionary = personalities_data.get("personalities", {})
	if personalities.has(pers_id):
		return float(personalities[pers_id].get("agressividade", 0.5))
	return 0.5

func _declare_war(from_code: String, to_code: String) -> void:
	if not nations.has(from_code) or not nations.has(to_code):
		return
	var attacker = nations[from_code]
	var defender = nations[to_code]
	if to_code in attacker.em_guerra:
		return
	var cost: float = max(20.0, attacker.pib_bilhoes_usd * 0.02)
	if attacker.tesouro < cost:
		return
	attacker.tesouro -= cost
	if not (to_code in attacker.em_guerra):
		attacker.em_guerra.append(to_code)
	if not (from_code in defender.em_guerra):
		defender.em_guerra.append(from_code)
	attacker.relacoes[to_code] = -100
	defender.relacoes[from_code] = -100
	defcon = max(1, defcon - 2)

	# Reação de alianças (defesa coletiva)
	var responders: Array = _trigger_collective_defense(from_code, to_code)
	var responder_names: String = ""
	if responders.size() > 0:
		var names := []
		for r in responders:
			names.append(nations[r].nome if nations.has(r) else r)
		responder_names = " — " + ", ".join(names) + " entram na guerra em defesa"

	# Notifica se envolve o jogador
	var involves_player: bool = (from_code == player_nation.codigo_iso) or (to_code == player_nation.codigo_iso) or _player_is_ally(to_code)
	_log_news({
		"type": "guerra",
		"headline": "⚔️ %s declarou guerra contra %s" % [attacker.nome, defender.nome],
		"body": "DEFCON %d%s." % [defcon, responder_names],
		"involves_player": involves_player,
	}, [from_code, to_code], attacker.continente)

func _propose_peace(from_code: String, to_code: String) -> void:
	if not nations.has(from_code) or not nations.has(to_code):
		return
	var a = nations[from_code]
	var b = nations[to_code]
	# Custo simbólico
	var cost: float = 20.0
	if a.tesouro < cost:
		return
	a.tesouro -= cost
	# Remove guerra
	a.em_guerra.erase(to_code)
	b.em_guerra.erase(from_code)
	# Relações neutralizam parcialmente
	a.relacoes[to_code] = -40
	b.relacoes[from_code] = -40
	var involves_player: bool = (from_code == player_nation.codigo_iso) or (to_code == player_nation.codigo_iso)
	_log_news({
		"type": "paz",
		"headline": "🕊️ %s e %s assinam armistício" % [a.nome, b.nome],
		"body": "Hostilidades cessam. Relações em -40.",
		"involves_player": involves_player,
	}, [from_code, to_code], a.continente)

func _trigger_collective_defense(attacker_code: String, defender_code: String) -> Array:
	var responders: Array = []
	for alliance in alliances_data:
		var members: Array = alliance.get("membros", [])
		if not (defender_code in members):
			continue
		if not alliance.get("artigo_defesa", false):
			continue
		var chance: float = float(alliance.get("reacao_agressao", {}).get("chance_intervencao", 0.5))
		for m in members:
			if m == defender_code or m == attacker_code:
				continue
			if not nations.has(m):
				continue
			if randf() < chance:
				var ally = nations[m]
				if not (attacker_code in ally.em_guerra):
					ally.em_guerra.append(attacker_code)
				var attacker = nations[attacker_code]
				if not (m in attacker.em_guerra):
					attacker.em_guerra.append(m)
				responders.append(m)
	return responders

func _player_is_ally(code: String) -> bool:
	if player_nation == null:
		return false
	for alliance in alliances_data:
		var members: Array = alliance.get("membros", [])
		if player_nation.codigo_iso in members and code in members:
			return true
	return false

# ─────────────────────────────────────────────────────────────────
# CUSTOS DE GUERRA (contínuos por turno)
# ─────────────────────────────────────────────────────────────────

func _process_war_costs() -> void:
	for code in nations:
		var n = nations[code]
		var wars: int = n.em_guerra.size()
		if wars == 0:
			continue
		# Custo proporcional ao PIB (com piso baixo pra países pequenos)
		var cost_per_war: float = max(3.0, n.pib_bilhoes_usd * 0.004)
		# Países pequenos (PIB < $200B) têm custo limitado a 1.5% do tesouro por guerra
		if n.pib_bilhoes_usd < 200.0:
			cost_per_war = min(cost_per_war, n.tesouro * 0.015)
		n.tesouro = max(0.0, n.tesouro - cost_per_war * wars)
		n.apoio_popular = max(0.0, n.apoio_popular - 1.5 * wars)
		n.felicidade = max(0.0, n.felicidade - 1.0 * wars)

# ─────────────────────────────────────────────────────────────────
# EVENTOS ALEATÓRIOS
# ─────────────────────────────────────────────────────────────────

signal player_event_triggered(event_data: Dictionary)

func _roll_events() -> void:
	if events_data.is_empty() or player_nation == null:
		return
	# 30% de chance de tentar evento por turno
	if randf() > 0.30:
		return
	var ev: Dictionary = events_data[randi() % events_data.size()]
	var year_min: int = int(ev.get("condicao", {}).get("ano_min", 0))
	if year_min > 0 and date_year < year_min:
		return
	# Eventos com escolhas e que afetam o jogador → emite sinal pra UI mostrar modal
	if ev.has("choices") and ev.get("afeta_jogador", false):
		emit_signal("player_event_triggered", ev)
	else:
		# Evento global ou local → aplica direto
		_apply_event_effects(ev.get("efeitos", {}), player_nation)
		var p_code: String = player_nation.codigo_iso if player_nation else ""
		_log_news({
			"type": "evento",
			"headline": "📰 %s" % ev.get("nome", "Evento"),
			"body": ev.get("descricao", ""),
			"involves_player": true,
		}, [p_code] if p_code != "" else [], "")

func apply_event_choice(event: Dictionary, choice_idx: int) -> void:
	var choices: Array = event.get("choices", [])
	if choice_idx < 0 or choice_idx >= choices.size():
		return
	var choice: Dictionary = choices[choice_idx]
	_apply_event_effects(choice.get("efeitos", {}), player_nation)
	var p_code2: String = player_nation.codigo_iso if player_nation else ""
	_log_news({
		"type": "evento_escolha",
		"headline": "🎯 %s" % event.get("nome", "Evento"),
		"body": "Escolha: %s" % choice.get("label", choice.get("texto", "Opção")),
		"involves_player": true,
	}, [p_code2] if p_code2 != "" else [], "")

func _apply_event_effects(efeitos: Dictionary, n) -> void:
	if n == null:
		return
	if efeitos.has("pib_fator"):
		n.apply_pib_multiplier(float(efeitos["pib_fator"]))
	if efeitos.has("tesouro"):
		n.tesouro = max(0.0, n.tesouro + float(efeitos["tesouro"]))
	if efeitos.has("estabilidade_fator"):
		n.estabilidade_politica = clamp(n.estabilidade_politica + float(efeitos["estabilidade_fator"]), 0.0, 100.0)
	if efeitos.has("apoio_popular"):
		n.apoio_popular = clamp(n.apoio_popular + float(efeitos["apoio_popular"]), 0.0, 100.0)
	if efeitos.has("felicidade"):
		n.felicidade = clamp(n.felicidade + float(efeitos["felicidade"]), 0.0, 100.0)
	if efeitos.has("inflacao"):
		n.inflacao = clamp(n.inflacao + float(efeitos["inflacao"]), 0.0, 100.0)
	if efeitos.has("corrupcao"):
		n.corrupcao = clamp(n.corrupcao + float(efeitos["corrupcao"]), 0.0, 100.0)

# Função pública para o jogador declarar guerra via UI
func player_declare_war(target_code: String) -> bool:
	if player_nation == null or not nations.has(target_code):
		return false
	if target_code in player_nation.em_guerra:
		return false
	var cost: float = max(20.0, player_nation.pib_bilhoes_usd * 0.02)
	if player_nation.tesouro < cost:
		return false
	if not _consume_action(): return false
	_declare_war(player_nation.codigo_iso, target_code)
	return true

func player_propose_peace(target_code: String) -> bool:
	if player_nation == null or not (target_code in player_nation.em_guerra):
		return false
	if player_nation.tesouro < 20.0:
		return false
	if not _consume_action(): return false
	_propose_peace(player_nation.codigo_iso, target_code)
	return true

# Diplomacia: player propõe tratado
func player_propose_treaty(target_code: String, treaty_type: String) -> Dictionary:
	if diplomacy == null or player_nation == null:
		return {"ok": false, "reason": "Sistema não inicializado"}
	# Valida ANTES de consumir (não desperdiça ação se não pode propor)
	if not nations.has(target_code):
		return {"ok": false, "reason": "Nação alvo inválida"}
	if target_code == player_nation.codigo_iso:
		return {"ok": false, "reason": "Não pode propor a si próprio"}
	if not _consume_action():
		return {"ok": false, "reason": "Sem ações restantes neste turno"}
	return diplomacy.propose(player_nation.codigo_iso, target_code, treaty_type)

# Diplomacia: player aceita/rejeita proposta dirigida a ele
# Aceitar/rejeitar NÃO consome ação (é resposta passiva, não iniciativa).
func player_accept_proposal(proposal_id: String) -> bool:
	if diplomacy == null: return false
	return diplomacy.player_accept(proposal_id)

func player_reject_proposal(proposal_id: String) -> bool:
	if diplomacy == null: return false
	return diplomacy.player_reject(proposal_id)

# Tech: player inicia pesquisa
func player_start_research(tech_id: String) -> Dictionary:
	if tech == null or player_nation == null:
		return {"ok": false, "reason": "Sistema não inicializado"}
	# Valida ANTES de consumir ação (evita perder ação por pré-req faltando)
	var check: Dictionary = tech.can_research(player_nation, tech_id)
	if not check.get("ok", false):
		return check  # devolve {"ok": false, "reason": "..."} sem consumir ação
	if not _consume_action():
		return {"ok": false, "reason": "Sem ações restantes neste turno"}
	tech.start_research(player_nation, tech_id)
	return {"ok": true}

# Cancelar pesquisa NÃO consome ação (correção/reversão)
func player_cancel_research() -> void:
	if tech and player_nation:
		tech.cancel_research(player_nation)

# Sanções: jogador impõe sanção a uma nação alvo
# Custa $30B + 1 ação. Aplica -1.5% PIB/turno no alvo por 5 turnos.
# Relação despenca -30 imediatamente. Se já houver sanção ativa, refresca duração.
func player_impose_sanctions(target_code: String) -> Dictionary:
	if player_nation == null:
		return {"ok": false, "reason": "Sem nação"}
	if not nations.has(target_code) or target_code == player_nation.codigo_iso:
		return {"ok": false, "reason": "Alvo inválido"}
	if player_nation.tesouro < SANCTION_COST:
		return {"ok": false, "reason": "Tesouro insuficiente: $%dB" % SANCTION_COST}
	if not _consume_action():
		return {"ok": false, "reason": "Sem ações restantes neste turno"}
	# Custo logístico
	player_nation.tesouro -= SANCTION_COST
	# Refresca ou cria sanção
	var existing: Dictionary = _find_sanction(player_nation.codigo_iso, target_code)
	if existing.size() > 0:
		existing["turns_remaining"] = SANCTION_DURATION
	else:
		active_sanctions.append({
			"from": player_nation.codigo_iso,
			"to": target_code,
			"turns_remaining": SANCTION_DURATION,
			"started_turn": current_turn,
		})
	# Penalidades imediatas de relação
	var t = nations[target_code]
	player_nation.relacoes[target_code] = clamp(float(player_nation.relacoes.get(target_code, 0)) - 30, -100, 100)
	t.relacoes[player_nation.codigo_iso] = clamp(float(t.relacoes.get(player_nation.codigo_iso, 0)) - 30, -100, 100)
	_log_news({
		"type": "sanctions",
		"headline": "🚫 %s impõe sanções contra %s" % [player_nation.nome, t.nome],
		"body": "Custo $%dB. -1.5%% PIB/turno por %d turnos. Relações em queda." % [SANCTION_COST, SANCTION_DURATION],
		"involves_player": true,
	}, [player_nation.codigo_iso, target_code], t.continente)
	return {"ok": true}

func _find_sanction(from: String, to: String) -> Dictionary:
	for s in active_sanctions:
		if s.get("from", "") == from and s.get("to", "") == to:
			return s
	return {}

# Comércio: jogador (exportador) propõe acordo de exportação a target (importador)
# Custa 1 ação. Validações: alvo válido, não-self, recurso disponível >= 30, sem
# sanção bilateral, sem guerra mútua. Cria acordo de 8 turnos.
# Receita por turno = (resource_value / 100) * TRADE_BASE_VALUE * (1 + relação_normalizada)
func player_export_resource(target_code: String, resource_id: String) -> Dictionary:
	if player_nation == null:
		return {"ok": false, "reason": "Sem nação"}
	if not nations.has(target_code) or target_code == player_nation.codigo_iso:
		return {"ok": false, "reason": "Alvo inválido"}
	# Recurso precisa existir e ter valor mínimo
	if not player_nation.recursos.has(resource_id):
		return {"ok": false, "reason": "Recurso não disponível"}
	var res_value: float = float(player_nation.recursos[resource_id])
	if res_value < 30:
		return {"ok": false, "reason": "Recurso muito escasso (<30/100) pra exportar"}
	# Conflitos bloqueiam
	if target_code in player_nation.em_guerra:
		return {"ok": false, "reason": "Não há comércio com inimigos em guerra"}
	if _find_sanction(player_nation.codigo_iso, target_code).size() > 0 or _find_sanction(target_code, player_nation.codigo_iso).size() > 0:
		return {"ok": false, "reason": "Sanções ativas bloqueiam comércio"}
	# Já existe acordo do mesmo recurso?
	for t in active_trades:
		if t.get("exporter", "") == player_nation.codigo_iso and t.get("importer", "") == target_code and t.get("resource", "") == resource_id:
			return {"ok": false, "reason": "Já existe acordo do mesmo recurso"}
	if not _consume_action():
		return {"ok": false, "reason": "Sem ações restantes neste turno"}
	# Calcula valor por turno
	var rel_norm: float = clamp(float(player_nation.relacoes.get(target_code, 0)) / 100.0, -0.3, 0.3)
	var value_per_turn: float = (res_value / 100.0) * TRADE_BASE_VALUE * (1.0 + rel_norm)
	active_trades.append({
		"exporter": player_nation.codigo_iso,
		"importer": target_code,
		"resource": resource_id,
		"value_per_turn": value_per_turn,
		"turns_remaining": TRADE_DURATION,
	})
	# Bônus de relação por cooperação econômica
	player_nation.relacoes[target_code] = clamp(float(player_nation.relacoes.get(target_code, 0)) + 8, -100, 100)
	var t_nat = nations[target_code]
	t_nat.relacoes[player_nation.codigo_iso] = clamp(float(t_nat.relacoes.get(player_nation.codigo_iso, 0)) + 8, -100, 100)
	_log_news({
		"type": "trade",
		"headline": "🤝 %s exporta %s para %s" % [player_nation.nome, resource_id.capitalize(), t_nat.nome],
		"body": "Receita: $%.1fB/turno por %d turnos" % [value_per_turn, TRADE_DURATION],
		"involves_player": true,
	}, [player_nation.codigo_iso, target_code], t_nat.continente)
	return {"ok": true, "value_per_turn": value_per_turn}

func _process_active_trades() -> void:
	var still_active: Array = []
	for t in active_trades:
		var entry: Dictionary = t
		var exporter: String = entry.get("exporter", "")
		var importer: String = entry.get("importer", "")
		var value: float = float(entry.get("value_per_turn", 0))
		# Importer só paga se tiver tesouro
		if nations.has(importer) and nations.has(exporter):
			var imp_nation = nations[importer]
			var exp_nation = nations[exporter]
			if imp_nation.tesouro >= value:
				imp_nation.tesouro -= value
				exp_nation.tesouro += value
			else:
				# Quebra contrato — sem dinheiro, sem comércio
				continue
		entry["turns_remaining"] = int(entry.get("turns_remaining", 0)) - 1
		if entry["turns_remaining"] > 0:
			still_active.append(entry)
	active_trades = still_active

# Processa sanções ativas todo turno: aplica penalidade no alvo, decrementa duração
func _process_active_sanctions() -> void:
	var still_active: Array = []
	for s in active_sanctions:
		var entry: Dictionary = s
		var to_code: String = entry.get("to", "")
		if nations.has(to_code):
			nations[to_code].apply_pib_multiplier(SANCTION_PIB_PENALTY)
		entry["turns_remaining"] = int(entry.get("turns_remaining", 0)) - 1
		if entry["turns_remaining"] > 0:
			still_active.append(entry)
	active_sanctions = still_active

# Espionagem: player executa op
func player_execute_spy(op_id: String, target_code: String) -> Dictionary:
	if espionage == null or player_nation == null:
		return {"ok": false, "msg": "Sistema não inicializado"}
	# Valida operação e alvo ANTES de consumir
	if not espionage.OPS.has(op_id):
		return {"ok": false, "msg": "Operação inválida"}
	if not nations.has(target_code) or target_code == player_nation.codigo_iso:
		return {"ok": false, "msg": "Alvo inválido"}
	var op: Dictionary = espionage.OPS[op_id]
	var cost: float = float(op.get("custo", 0))
	if player_nation.tesouro < cost:
		return {"ok": false, "msg": "Tesouro insuficiente: $%dB" % int(cost)}
	if not _consume_action():
		return {"ok": false, "msg": "Sem ações restantes neste turno"}
	return espionage.execute(player_nation.codigo_iso, op_id, target_code)

# ── Helpers ──────────────────────────────────────────────────────

func get_difficulty_meta(tier: String) -> Dictionary:
	match tier:
		"FACIL":            return {"label": "FÁCIL",            "color": Color(0, 1, 0.533),    "icon": "🟢", "desc": "Recursos abundantes, instituições sólidas. Ideal para aprender."}
		"NORMAL":           return {"label": "NORMAL",           "color": Color(0, 0.823, 1),    "icon": "🔵", "desc": "Equilibrado. Vitória requer atenção, mas é alcançável."}
		"DIFICIL":          return {"label": "DIFÍCIL",          "color": Color(1, 0.667, 0),    "icon": "🟡", "desc": "Recursos limitados. Vitória exige escolhas inteligentes."}
		"MUITO_DIFICIL":    return {"label": "MUITO DIFÍCIL",    "color": Color(1, 0.467, 0),    "icon": "🟠", "desc": "Crise estrutural. Cada decisão importa. Ações têm efeito ampliado."}
		"QUASE_IMPOSSIVEL": return {"label": "QUASE IMPOSSÍVEL", "color": Color(1, 0.2, 0.2),    "icon": "🔴", "desc": "Situação catastrófica. Apenas mestres conseguem reverter."}
	return {"label": "?", "color": Color.WHITE, "icon": "⚪", "desc": ""}
