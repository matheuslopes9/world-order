extends Node
## Singleton global do jogo (Autoload).
## Carrega dados, mantém estado, gerencia turnos.

const NationScript := preload("res://scripts/Nation.gd")
const DiplomacyScript := preload("res://scripts/DiplomacyManager.gd")
const NewsScript := preload("res://scripts/NewsManager.gd")
const TechScript := preload("res://scripts/TechManager.gd")
const EspionageScript := preload("res://scripts/EspionageManager.gd")
const TimelineScript := preload("res://scripts/EventTimeline.gd")
const AchievementScript := preload("res://scripts/AchievementManager.gd")
const StorylineScript := preload("res://scripts/StorylineManager.gd")
const MetaProgressionScript := preload("res://scripts/MetaProgression.gd")

var diplomacy = null  # DiplomacyManager
var news = null       # NewsManager
var tech = null       # TechManager
var espionage = null  # EspionageManager
var timeline = null   # EventTimelineManager
var achievements = null  # AchievementManager
var storylines = null    # StorylineManager
var meta_progression = null  # MetaProgression (singleton entre saves)

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
var victory_achieved: bool = false        # vitória já celebrada (evita re-disparo em modo livre)
var _turns_since_war: int = 0             # p/ recuperação gradual de DEFCON
# Registro de início de guerras (par "A|B" → turno) — alimenta o armistício
# automático por fadiga. Auto-regenera após load (pares órfãos re-registram).
var _war_started: Dictionary = {}
const WAR_FATIGUE_TURNS: int = 20         # guerras > 5 anos entram em fadiga
# War score por par ("A|B" ordenado -> float; >0 favorece o 1o em ordem
# alfabetica). Acumula com vantagem militar/economica - vitoria decisiva
# gera ESPOLIOS (guerra deixa de ser dreno sem proposito).
var _war_score: Dictionary = {}
const WAR_DECISIVE_SCORE: float = 100.0

# ── Resgate do FMI (jogador em crise fiscal) ──
signal bailout_offered(terms: Dictionary)
var bailout_pending: Dictionary = {}
var _last_bailout_turn: int = -999

# ── Choques econômicos globais (pós-2035) ──
var active_shock: Dictionary = {}   # {id, nome, turns_remaining, ...}
var _last_shock_turn: int = 0
# Posição do jogador no ranking de poder, registrada por turno (sparkline da UI)
var player_power_rank_history: Array = []
const POWER_RANK_HISTORY_MAX: int = 60
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
	"mode": "inspirado",
	# Cenário ativo (id em data/scenarios.json). Default = campanha 2000-2100
	"scenario": "campanha"
}

# Definição do cenário ativo carregada de data/scenarios.json (preenchida em apply_scenario)
var active_scenario: Dictionary = {}
var scenarios_data: Array = []

# Antagonista declarado: nação com pior relação ao jogador, atualizado a cada turno.
# Quando relação ≤ -50 vira "rival declarado" e ganha bônus de hostilidade.
var player_nemesis: String = ""
var nemesis_declared: bool = false  # vira true ao cruzar limiar

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
	achievements = AchievementScript.new(self)
	storylines = StorylineScript.new(self)
	meta_progression = MetaProgressionScript.new()

func _load_all_data() -> void:
	var t0 := Time.get_ticks_msec()
	difficulty_tiers   = _load_json("res://data/difficulty-tiers.json")
	var alliances_raw  = _load_json("res://data/alliances.json")
	alliances_data     = alliances_raw.get("alliances", []) if alliances_raw else []
	var events_raw     = _load_json("res://data/events.json")
	events_data        = events_raw.get("eventos", []) if events_raw else []
	tech_data          = _load_json("res://data/tech.json")
	personalities_data = _load_json("res://data/personalities.json")
	var scenarios_raw  = _load_json("res://data/scenarios.json")
	scenarios_data     = scenarios_raw.get("scenarios", []) if scenarios_raw else []
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
	# Aplica cenário ativo (default = campanha 2000-2100, se outro for escolhido
	# no MainMenu, será reaplicado no início do WorldMap)
	apply_scenario(String(settings.get("scenario", "campanha")))
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
		# Orçamento militar sanizado pro ano 2000: os dados-base são de 2024
		# (Ucrânia em guerra tinha orçamento maior que o PIB-2000 inteiro →
		# pressão inflacionária de +200 e morte no turno 6). Clamp a 5% do PIB
		# (mundo-2000 real: 2-4%), com piso simbólico.
		var orc: float = float(n.militar.get("orcamento_militar_bilhoes", 0))
		n.militar["orcamento_militar_bilhoes"] = min(orc, max(0.3, n.pib_bilhoes_usd * 0.05))
		# Recalcula tier de dificuldade SEMPRE (mundo de 2000 é diferente de 2024)
		# Antes: usava difficulty_tiers.json (que reflete cenário 2024) — gerava inversão NORMAL>DIFICIL
		n.tier_dificuldade = n._compute_difficulty_tier()
		# Snapshot do PIB APÓS o override — pib_inicial deve refletir o ponto
		# de partida real da campanha (antes guardava o valor de 2024, gerando
		# caps e títulos de legado inconsistentes)
		n.pib_inicial = n.pib_bilhoes_usd
	print("[2000] Overrides aplicados: %d explícitos + %d via escala global" % [changed_explicit, changed_global])

# Aplica um cenário (carregado de scenarios.json). Deve ser chamado ANTES
# do jogo iniciar — define start_year, end_year, bônus, regras.
func apply_scenario(scenario_id: String) -> void:
	var found: Dictionary = {}
	for s in scenarios_data:
		if s.get("id", "") == scenario_id:
			found = s
			break
	if found.is_empty():
		print("[SCENARIO] %s não encontrado, mantendo campanha padrão" % scenario_id)
		return
	active_scenario = found
	settings["scenario"] = scenario_id
	# Define ano de início conforme cenário
	date_year = int(found.get("start_year", 2000))
	date_quarter = 1
	# Modo padrão sugerido pelo cenário (jogador pode trocar via mode toggle)
	if found.has("default_mode"):
		settings["mode"] = String(found.get("default_mode"))
	# Aplica bônus iniciais ao mundo se houver
	var pib_bonus: float = float(found.get("starting_pib_bonus", 1.0))
	var tech_bonus: int = int(found.get("starting_tech_bonus", 0))
	if pib_bonus != 1.0:
		for code in nations.keys():
			nations[code].pib_bilhoes_usd *= pib_bonus
			nations[code].pib_inicial = nations[code].pib_bilhoes_usd
	if tech_bonus > 0 and tech and tech_data.has("tecnologias"):
		# Dá tech_bonus tecnologias aleatórias pra cada nação grande (PIB > 500B)
		var all_tech_ids: Array = []
		for cat in tech_data.get("tecnologias", {}).values():
			for t in cat:
				all_tech_ids.append(t.get("id", ""))
		for code in nations.keys():
			var n = nations[code]
			if n.pib_bilhoes_usd >= 500.0:
				for i in tech_bonus:
					var rand_id: String = String(all_tech_ids[randi() % all_tech_ids.size()])
					if rand_id != "" and not (rand_id in n.tecnologias_concluidas):
						n.tecnologias_concluidas.append(rand_id)
	print("[SCENARIO] %s aplicado: %d → %d (modo: %s)" % [scenario_id, int(found.get("start_year", 2000)), int(found.get("end_year", 2100)), settings.get("mode", "?")])

# Verifica se cenário atual desabilita game over (sandbox)
func is_no_game_over() -> bool:
	return bool(active_scenario.get("no_game_over", false))

func is_no_endgame() -> bool:
	return bool(active_scenario.get("no_endgame", false))

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
	# Aplica perks ativos do meta_progression (XP unlocks)
	if meta_progression:
		meta_progression.apply_perks_to_player(player_nation)
	# Perk "actions_per_turn": +1 ação por turno se ativo
	var extra_actions: int = int(player_nation.get_meta("perk_extra_actions", 0))
	if extra_actions > 0:
		player_actions_remaining = PLAYER_ACTIONS_PER_TURN + extra_actions
	# Perk "Carisma Natural": +relação inicial com TODOS os países (nos 2 sentidos)
	# (antes: o meta era gravado mas nunca lido — perk de 200 XP não fazia nada)
	var rel_boost: float = float(player_nation.get_meta("perk_global_relations", 0))
	if rel_boost > 0.0:
		for other_code in nations:
			if other_code == code: continue
			var other = nations[other_code]
			player_nation.relacoes[other_code] = clamp(float(player_nation.relacoes.get(other_code, 0)) + rel_boost, -100.0, 100.0)
			other.relacoes[code] = clamp(float(other.relacoes.get(code, 0)) + rel_boost, -100.0, 100.0)
	current_turn = 1
	player_power_rank_history.clear()
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
	# Fronteira tecnológica mundial (maior PIB per capita entre economias
	# relevantes) — alimenta o modelo de crescimento por convergência.
	# Filtros evitam micro-estados/paraísos fiscais como referência.
	var frontier_pc: float = 0.0
	for code in nations:
		var nf = nations[code]
		if nf.pib_bilhoes_usd >= 100.0 and nf.populacao >= 5_000_000:
			frontier_pc = max(frontier_pc, nf.pib_per_capita())
	# Processa todas as nações
	for code in nations:
		var n = nations[code]
		n.frontier_pib_pc = frontier_pc
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
	# Progresso das guerras: vantagem acumula, vitória decisiva gera espólios
	_process_war_resolution()
	# Fadiga: guerras longas demais terminam em armistício
	_process_war_fatigue()
	# Sanções ativas: aplica penalidade nos alvos e decrementa duração
	_process_active_sanctions()
	# Comércio bilateral: transfere $ entre exportador/importador
	_process_active_trades()
	# Eventos aleatórios
	_roll_events()
	# Choques econômicos globais (recessões, crises energéticas...)
	_process_global_shocks()
	# Diplomacia: aplica tratados, processa propostas
	if diplomacy:
		diplomacy.process_turn()
	# Pesquisa: progride techs em andamento, aplica efeitos
	if tech:
		tech.process_turn()
	# Timeline histórica: dispara eventos âncora se chegou o momento
	if timeline:
		timeline.process_turn()
	# Atualiza conquistas (verifica condições de progressão automática)
	if achievements:
		achievements.update()
	# Storylines: dispara nodes pendentes + tenta iniciar novas
	if storylines:
		storylines.process_turn()
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

	# Atualiza tracking de antagonista (nação rival recorrente)
	_update_player_nemesis()

	# Recuperação de DEFCON: 4 turnos sem nova guerra → tensão mundial alivia
	# (antes o DEFCON só descia — o mundo travava em alerta nuclear permanente)
	_turns_since_war += 1
	if _turns_since_war >= 4 and defcon < 5:
		defcon += 1
		_turns_since_war = 0
		_log_news({
			"type": "defcon",
			"headline": "🕊️ Tensão mundial alivia — DEFCON sobe para %d" % defcon,
			"body": "Período prolongado sem novos conflitos.",
			"involves_player": false,
			"color": Color(0.5, 1, 0.7),
		})

	# Reset de ações do jogador para o novo turno
	# (inclui perk "Equipe Eficiente" — antes o bônus era perdido após o turno 1)
	var extra_actions: int = int(player_nation.get_meta("perk_extra_actions", 0)) if player_nation else 0
	player_actions_remaining = PLAYER_ACTIONS_PER_TURN + extra_actions
	emit_signal("player_actions_changed", player_actions_remaining)

	# Avalia vitória/derrota (lógica vive no motor; a UI só apresenta o modal)
	evaluate_endgame()

	# Registra a posição no ranking de poder (trajetória no painel Situação)
	if player_nation != null:
		player_power_rank_history.append(get_power_rank(player_nation.codigo_iso))
		if player_power_rank_history.size() > POWER_RANK_HISTORY_MAX:
			player_power_rank_history.pop_front()

	emit_signal("turn_advanced", current_turn)

# ─────────────────────────────────────────────────────────────────
# PODER GLOBAL — score composto usado por ranking e vitórias
# economia 40% · militar 25% · tecnologia 20% · diplomacia 15%
# ─────────────────────────────────────────────────────────────────

var _world_max_pib: float = 1.0
var _world_max_mil: float = 1.0
var _world_max_tech: float = 1.0

func _refresh_world_maxima() -> void:
	_world_max_pib = 1.0
	_world_max_mil = 1.0
	_world_max_tech = 6.0  # piso: evita "winner-take-all" no início (1 tech = 100%)
	for code in nations:
		var n = nations[code]
		_world_max_pib = max(_world_max_pib, n.pib_bilhoes_usd)
		_world_max_mil = max(_world_max_mil, n.get_military_power())
		_world_max_tech = max(_world_max_tech, float(n.tecnologias_concluidas.size()))

# Tecnologia numa escala ABSOLUTA (40 techs = potência científica plena).
# Antes era relativa ao máximo mundial — o jogador virava 1.0 cedo e o
# monopólio de 20 pts levava micro-estados ao top-5 (Vaticano 3ª potência
# em 1000 jogos simulados).
const TECH_POWER_SCALE := 40.0
# Diplomacia: qualidade × LARGURA da rede (25 relações = rede global).
# Antes 3 tratados com +100 davam os 15 pts inteiros.
const REL_BREADTH_SCALE := 25.0

func compute_power_score(n) -> float:
	var pib_norm: float = n.pib_bilhoes_usd / _world_max_pib
	var mil_norm: float = n.get_military_power() / _world_max_mil
	var tech_norm: float = clamp(float(n.tecnologias_concluidas.size()) / TECH_POWER_SCALE, 0.0, 1.0)
	var rel_sum: float = 0.0
	var rel_n: int = 0
	for c in n.relacoes:
		rel_sum += float(n.relacoes[c])
		rel_n += 1
	var rel_quality: float = ((rel_sum / rel_n) + 100.0) / 200.0 if rel_n > 0 else 0.5
	var rel_breadth: float = clamp(float(rel_n) / REL_BREADTH_SCALE, 0.0, 1.0)
	var rel_norm: float = rel_quality * (0.3 + 0.7 * rel_breadth)
	return 40.0 * pib_norm + 25.0 * mil_norm + 20.0 * tech_norm + 15.0 * rel_norm

# Decomposição do score de poder — a UI usa pra mostrar ONDE investir.
# (mesma fórmula de compute_power_score; manter em sincronia)
func get_power_breakdown(n) -> Dictionary:
	var pib_norm: float = n.pib_bilhoes_usd / _world_max_pib
	var mil_norm: float = n.get_military_power() / _world_max_mil
	var tech_norm: float = clamp(float(n.tecnologias_concluidas.size()) / TECH_POWER_SCALE, 0.0, 1.0)
	var rel_sum: float = 0.0
	var rel_n: int = 0
	for c in n.relacoes:
		rel_sum += float(n.relacoes[c])
		rel_n += 1
	var rel_quality: float = ((rel_sum / rel_n) + 100.0) / 200.0 if rel_n > 0 else 0.5
	var rel_breadth: float = clamp(float(rel_n) / REL_BREADTH_SCALE, 0.0, 1.0)
	var rel_norm: float = rel_quality * (0.3 + 0.7 * rel_breadth)
	var econ: float = 40.0 * pib_norm
	var mil: float = 25.0 * mil_norm
	var tech_pts: float = 20.0 * tech_norm
	var dipl: float = 15.0 * rel_norm
	return {
		"economia": econ, "militar": mil, "tecnologia": tech_pts, "diplomacia": dipl,
		"total": econ + mil + tech_pts + dipl,
	}

# Posição da nação no ranking mundial de poder (1 = líder mundial)
func get_power_rank(code: String) -> int:
	if not nations.has(code):
		return 999
	var my_score: float = compute_power_score(nations[code])
	var rank: int = 1
	for c in nations:
		if c != code and compute_power_score(nations[c]) > my_score:
			rank += 1
	return rank

# ─────────────────────────────────────────────────────────────────
# ENDGAME — vitória/derrota avaliadas no motor
# (a UI escuta endgame_reached e apenas apresenta o modal)
#
# Design:
#  🏛 POTÊNCIA DO SÉCULO — chegar a 2100 no top-5 do ranking de poder
#  🏆 HEGEMONIA GLOBAL   — ser o #1 do ranking por 12 turnos (3 anos)
#  🌟 NAÇÃO MODELO       — 20 turnos de indicadores excelentes (marco,
#                          celebra e CONTINUA — não encerra a campanha)
#  💀 derrotas            — revolução, falência, golpe, hiperinflação
# ─────────────────────────────────────────────────────────────────

signal endgame_reached(result: Dictionary)

func evaluate_endgame() -> void:
	if player_nation == null or game_state != "PLAYING":
		return
	var n = player_nation
	_refresh_world_maxima()
	# ── Fim da campanha (end_year do cenário, ex: 2100) — avaliação de legado ──
	# (dispara UMA vez; quem "continuar livre" após 2100 não revê o modal)
	if not is_no_endgame() and not bool(n.get_meta("century_end_fired", false)):
		var end_year: int = int(active_scenario.get("end_year", 2100)) if not active_scenario.is_empty() else 2100
		if date_year >= end_year:
			n.set_meta("century_end_fired", true)
			var final_rank: int = get_power_rank(n.codigo_iso)
			# Relevância econômica obrigatória: sem ela, micro-estados com
			# monopólio de tech/diplomacia viravam "potência" (Vaticano 3º
			# em 1000 jogos simulados). Potência de verdade tem economia.
			var pib_rank: int = 1
			for c in nations:
				if c != n.codigo_iso and nations[c].pib_bilhoes_usd > n.pib_bilhoes_usd:
					pib_rank += 1
			if (final_rank <= 5 and pib_rank <= 30) or victory_achieved:
				victory_achieved = true
				if achievements:
					achievements.on_victory(n.tier_dificuldade)
				_fire_endgame(true, "🏛 POTÊNCIA DO SÉCULO",
					"Você atravessou 100 anos de história e terminou como %dª potência mundial (%dª economia). Seu nome está gravado no século." % [final_rank, pib_rank])
			else:
				var extra: String = ""
				if final_rank <= 5 and pib_rank > 30:
					extra = " Influência e tecnologia impressionam (%dº em poder), mas sem peso econômico (%dª economia) o mundo não o reconhece como potência." % [final_rank, pib_rank]
				_fire_endgame(false, "📜 LEGADO DO SÉCULO",
					("Seu governo atravessou o século inteiro e terminou como %dª potência. Sobreviver a 100 anos já é história — mas o mundo seguiu liderado por outros." % final_rank) + extra)
			return
	if is_no_game_over():
		return
	# ── Derrotas ──
	var honeymoon_turns: int = 5 + int(n.get_meta("perk_honeymoon_extra", 0))
	var honeymoon: bool = current_turn <= honeymoon_turns
	if n.apoio_popular < 20:
		n.revolucao_turnos += 1
	else:
		n.revolucao_turnos = 0
	if n.tesouro <= 0:
		n.falencia_turnos += 1
		# FMI oferece resgate ANTES do colapso (2 turnos de falência de 4)
		if n.falencia_turnos == 2 and bailout_pending.is_empty() and current_turn - _last_bailout_turn > 40:
			_offer_bailout()
	else:
		n.falencia_turnos = 0
	if not honeymoon:
		if n.revolucao_turnos >= 3:
			_fire_endgame(false, "💀 REVOLUÇÃO", "Apoio popular abaixo de 20%% por 3 turnos.")
			return
		if n.falencia_turnos >= 4:
			_fire_endgame(false, "💀 FALÊNCIA NACIONAL", "Tesouro zerado por 4 turnos. Colapso fiscal.")
			return
		if n.estabilidade_politica < 8:
			_fire_endgame(false, "💀 GOLPE DE ESTADO", "Estabilidade colapsou abaixo de 8%%. Você foi deposto.")
			return
		# Graça estendida contra inflação HERDADA: alguns países começam o ano
		# 2000 já em crise inflacionária (Angola 65%+) — 3 anos pra domar antes
		# da derrota valer (a lua de mel padrão de 5 turnos não bastava).
		if n.inflacao > 80 and current_turn > 12:
			_fire_endgame(false, "💀 HIPERINFLAÇÃO", "Inflação acima de 80%%. Economia em ruínas.")
			return
	# ── Marco "Nação Modelo": 20 turnos de indicadores excelentes ──
	# Celebra e CONTINUA (antes isto encerrava a campanha como "hegemonia"
	# no ano ~2008, trivializando os outros 92 anos de jogo)
	var win_cond: bool = n.apoio_popular >= 65 and n.estabilidade_politica >= 65 and n.inflacao <= 15 and n.tesouro > 0
	n.set_meta("victory_streak", (int(n.get_meta("victory_streak", 0)) + 1) if win_cond else 0)
	if int(n.get_meta("victory_streak", 0)) >= 20 and not bool(n.get_meta("model_nation_done", false)):
		n.set_meta("model_nation_done", true)
		_log_news({
			"type": "marco",
			"headline": "🌟 %s é reconhecida como NAÇÃO MODELO" % n.nome,
			"body": "20 turnos de indicadores exemplares. O mundo observa seu governo como referência.",
			"involves_player": true,
			"color": Color(1, 0.9, 0.4),
		}, [n.codigo_iso], n.continente)
	# ── Vitória: HEGEMONIA GLOBAL — liderança real do ranking de poder ──
	# Exige: #1 no poder composto + economia ≥ 50% da maior + país estável,
	# sustentado por 16 turnos (4 anos), a partir do turno 60 (ano ~2015).
	if victory_achieved:
		return
	var power_rank: int = get_power_rank(n.codigo_iso)
	# 35% do líder (era 50% — inalcançável: a China da IA cresce ~200× e
	# virava um teto impossível; 0 hegemonias em 900 jogos simulados)
	var econ_relevante: bool = n.pib_bilhoes_usd >= _world_max_pib * 0.35
	if power_rank == 1 and econ_relevante and n.apoio_popular >= 55.0 and n.estabilidade_politica >= 55.0:
		n.set_meta("hegemony_streak", int(n.get_meta("hegemony_streak", 0)) + 1)
	else:
		n.set_meta("hegemony_streak", 0)
	if int(n.get_meta("hegemony_streak", 0)) >= 16 and current_turn >= 60:
		victory_achieved = true
		if achievements:
			achievements.on_victory(n.tier_dificuldade)
		_fire_endgame(true, "🏆 HEGEMONIA GLOBAL",
			"Sua nação lidera o ranking mundial de poder há 4 anos consecutivos. Economia, tecnologia, forças armadas e diplomacia — o século é seu.")

func _fire_endgame(victory: bool, title: String, msg: String) -> void:
	game_state = "ENDGAME"
	emit_signal("endgame_reached", {"victory": victory, "title": title, "msg": msg})

# "Continuar Livre" pós-vitória: retoma o jogo (vitória não re-dispara)
func resume_after_endgame() -> void:
	if game_state == "ENDGAME":
		game_state = "PLAYING"

# ─────────────────────────────────────────────────────────────────
# RESGATE DO FMI — crise fiscal vira ESCOLHA dramática, não morte lenta
# ─────────────────────────────────────────────────────────────────

func _offer_bailout() -> void:
	if player_nation == null:
		return
	var valor: float = max(60.0, player_nation.pib_bilhoes_usd * 0.08)
	bailout_pending = {"valor": valor, "turn": current_turn}
	emit_signal("bailout_offered", bailout_pending)
	_log_news({
		"type": "fmi",
		"headline": "🏦 FMI oferece resgate de $%dB a %s" % [int(valor), player_nation.nome],
		"body": "Condições: austeridade (gasto social -50%, apoio -8) e dívida com juros. Recuse por sua conta e risco.",
		"involves_player": true,
		"color": Color(1, 0.85, 0.3),
	}, [player_nation.codigo_iso], player_nation.continente)

func accept_bailout() -> bool:
	if bailout_pending.is_empty() or player_nation == null:
		return false
	var n = player_nation
	var valor: float = float(bailout_pending.get("valor", 0))
	n.tesouro += valor
	n.divida_publica += valor * 1.2  # empréstimo com juros embutidos
	# Austeridade: as condições do Fundo
	n.apoio_popular = clamp(n.apoio_popular - 8.0, 0.0, 100.0)
	n.felicidade = clamp(n.felicidade - 5.0, 0.0, 100.0)
	for k in n.gasto_social:
		n.gasto_social[k] = float(n.gasto_social[k]) * 0.5
	n.falencia_turnos = 0
	_last_bailout_turn = current_turn
	bailout_pending = {}
	_log_news({
		"type": "fmi",
		"headline": "🏦 %s aceita o resgate do FMI" % n.nome,
		"body": "Tesouro reforçado em $%dB. O povo sente a austeridade." % int(valor),
		"involves_player": true,
		"color": Color(0.4, 0.85, 1),
	}, [n.codigo_iso], n.continente)
	return true

func decline_bailout() -> void:
	if bailout_pending.is_empty():
		return
	bailout_pending = {}
	_last_bailout_turn = current_turn
	_log_news({
		"type": "fmi",
		"headline": "🏦 %s RECUSA o resgate do FMI" % player_nation.nome,
		"body": "Soberania acima de tudo — mas o tesouro segue vazio.",
		"involves_player": true,
		"color": Color(1, 0.55, 0.3),
	}, [player_nation.codigo_iso], player_nation.continente)

# ─────────────────────────────────────────────────────────────────
# CHOQUES ECONÔMICOS GLOBAIS — o mundo pós-2035 não é piloto automático
# ─────────────────────────────────────────────────────────────────

const SHOCK_TYPES := [
	{
		"id": "recessao_global", "nome": "Recessão Global", "icon": "📉",
		"dur_min": 6, "dur_max": 8,
		"desc": "Demanda mundial em colapso. Economias grandes sofrem mais.",
	},
	{
		"id": "crise_energetica", "nome": "Crise Energética Global", "icon": "🛢",
		"dur_min": 5, "dur_max": 7,
		"desc": "Petróleo e gás disparam: exportadores lucram, importadores sangram.",
	},
	{
		"id": "colapso_financeiro", "nome": "Colapso Financeiro", "icon": "💥",
		"dur_min": 4, "dur_max": 5,
		"desc": "Pânico bancário mundial. Tesouros encolhem, inflação sobe.",
	},
]

func _process_global_shocks() -> void:
	# Aplica choque ativo
	if not active_shock.is_empty():
		_apply_shock_turn()
		active_shock["turns_remaining"] = int(active_shock["turns_remaining"]) - 1
		if int(active_shock["turns_remaining"]) <= 0:
			for c in nations:
				nations[c].commodity_multiplier = 1.0
			_log_news({
				"type": "choque_fim",
				"headline": "✅ Fim da %s — economia mundial normaliza" % active_shock.get("nome", "crise"),
				"body": "Mercados respiram após %d turnos de turbulência." % active_shock.get("dur_total", 0),
				"involves_player": true,
				"color": Color(0.4, 1, 0.6),
			})
			active_shock = {}
		return
	# Rola novo choque: pós-2035, ~1.2%/turno, cooldown de 15 anos
	if date_year < 2035 or current_turn - _last_shock_turn < 60:
		return
	if randf() > 0.012:
		return
	var meta: Dictionary = SHOCK_TYPES[randi() % SHOCK_TYPES.size()]
	var dur: int = randi_range(int(meta["dur_min"]), int(meta["dur_max"]))
	active_shock = {
		"id": meta["id"], "nome": meta["nome"], "icon": meta["icon"],
		"turns_remaining": dur, "dur_total": dur,
	}
	_last_shock_turn = current_turn
	# Efeito imediato do colapso financeiro: tesouros derretem
	if meta["id"] == "colapso_financeiro":
		for c in nations:
			nations[c].tesouro *= 0.88
	# Crise energética: reprecifica commodities
	if meta["id"] == "crise_energetica":
		for c in nations:
			var nn = nations[c]
			var oil: float = float(nn.recursos.get("petroleo", 0))
			var gas: float = float(nn.recursos.get("gas_natural", 0))
			nn.commodity_multiplier = 2.0 if (oil >= 70.0 or gas >= 70.0) else 1.0
	_log_news({
		"type": "choque",
		"headline": "%s %s ATINGE O MUNDO (%d turnos)" % [meta["icon"], meta["nome"].to_upper(), dur],
		"body": String(meta["desc"]) + " Use Aperto Monetário e Estímulo com sabedoria.",
		"involves_player": true,
		"color": Color(1, 0.4, 0.3),
	})

func _apply_shock_turn() -> void:
	var sid: String = String(active_shock.get("id", ""))
	for c in nations:
		var n = nations[c]
		match sid:
			"recessao_global":
				# Economias grandes e integradas sofrem mais
				var severity: float = 0.985 if n.pib_bilhoes_usd < _world_max_pib * 0.3 else 0.978
				n.apply_pib_multiplier(severity)
			"crise_energetica":
				var oil: float = float(n.recursos.get("petroleo", 0))
				var gas: float = float(n.recursos.get("gas_natural", 0))
				if oil >= 70.0 or gas >= 70.0:
					n.apply_pib_multiplier(1.003)
				elif oil < 40.0 and gas < 40.0:
					n.apply_pib_multiplier(0.988)
			"colapso_financeiro":
				n.apply_pib_multiplier(0.99)
				n.inflacao = clamp(n.inflacao + 0.8, 0.0, 100.0)

# ─────────────────────────────────────────────────────────────────
# EMBAIXADA — via API central (consome ação como toda iniciativa)
# ─────────────────────────────────────────────────────────────────

const EMBASSY_COST: float = 15.0

func player_open_embassy(target_code: String) -> Dictionary:
	if player_nation == null:
		return {"ok": false, "reason": "Sem nação"}
	if not nations.has(target_code) or target_code == player_nation.codigo_iso:
		return {"ok": false, "reason": "Alvo inválido"}
	if player_nation.tesouro < EMBASSY_COST:
		return {"ok": false, "reason": "Custo: $%dB" % int(EMBASSY_COST)}
	if not _consume_action():
		return {"ok": false, "reason": "Sem ações restantes neste turno"}
	player_nation.tesouro -= EMBASSY_COST
	var t = nations[target_code]
	player_nation.relacoes[target_code] = clamp(float(player_nation.relacoes.get(target_code, 0)) + 15, -100, 100)
	t.relacoes[player_nation.codigo_iso] = clamp(float(t.relacoes.get(player_nation.codigo_iso, 0)) + 15, -100, 100)
	return {"ok": true, "msg": "Embaixada em %s • relações +15" % t.nome}

# Identifica e mantém o "nêmesis" do jogador — nação com pior relação que cruzou ≤ -50.
# Nemesis declarada gera notícias de provocação periódicas e tem maior chance de hostilidade.
func _update_player_nemesis() -> void:
	if player_nation == null: return
	var worst_code: String = ""
	var worst_rel: float = 1.0
	for code in player_nation.relacoes:
		if code == player_nation.codigo_iso: continue
		var r: float = float(player_nation.relacoes[code])
		if r < worst_rel:
			worst_rel = r
			worst_code = code
	if worst_code == "" or worst_rel > -50.0:
		# Sem rival qualificado — limpa estado se havia
		if nemesis_declared:
			nemesis_declared = false
			player_nemesis = ""
		return
	# Tem rival qualificado
	if worst_code != player_nemesis:
		# Mudou o rival principal — declara
		player_nemesis = worst_code
		nemesis_declared = true
		var rival_name: String = nations[worst_code].nome if nations.has(worst_code) else worst_code
		_log_news({
			"type": "rival_declared",
			"headline": "🔥 %s emerge como rival declarado de %s" % [rival_name, player_nation.nome],
			"body": "Relação caiu para %d — esperar provocações nos próximos turnos." % int(worst_rel),
			"color": Color(1, 0.4, 0.3),
		}, [worst_code, player_nation.codigo_iso], nations[worst_code].continente if nations.has(worst_code) else "")
	elif current_turn % 5 == 0:
		# Provocação periódica do rival declarado (a cada 5 turnos)
		var rival = nations.get(player_nemesis)
		if rival != null:
			var provocations: Array = [
				"%s denuncia %s em fórum internacional" % [rival.nome, player_nation.nome],
				"%s acusa %s de interferência regional" % [rival.nome, player_nation.nome],
				"%s ameaça revisar tratados com %s" % [rival.nome, player_nation.nome],
				"Manifestações anti-%s em %s ganham força" % [player_nation.nome, rival.nome],
			]
			var msg: String = provocations[randi() % provocations.size()]
			_log_news({
				"type": "rival_provocation",
				"headline": "⚠ " + msg,
				"body": "",
				"color": Color(1, 0.55, 0.3),
			}, [player_nemesis, player_nation.codigo_iso], rival.continente)
			# Aplica pequena penalidade contínua de relação (rival ataca)
			player_nation.relacoes[player_nemesis] = clamp(float(player_nation.relacoes.get(player_nemesis, 0)) - 3, -100, 100)
			rival.relacoes[player_nation.codigo_iso] = clamp(float(rival.relacoes.get(player_nation.codigo_iso, 0)) - 3, -100, 100)

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
			# Chance baseada em agressividade: ~0.3% (pacífico) até 3.5% (Putin/Kim) por turno
			# (calibrado: 0.05 gerava guerra nova a cada ~2.5 turnos — 160 guerras/século
			# e DEFCON travado em 2)
			var rel_factor: float = clamp((100.0 + worst_rel) / 100.0 + 0.5, 0.3, 1.5)
			var war_chance: float = aggro * 0.035 * rel_factor
			if randf() < war_chance:
				_declare_war(n.codigo_iso, worst_code)
				return

	# 3. PESQUISA — nações com folga desenvolvem tecnologia
	# (sem isto o jogador monopolizava o eixo tecnológico do ranking de poder)
	if tech != null and n.pesquisa_atual == null and n.tesouro >= 60.0 and randf() < 0.25:
		var avail: Array = tech.get_available_techs(n)
		if not avail.is_empty():
			var cheapest: Dictionary = avail[0]
			for t in avail:
				if float(t.get("custo", 999)) < float(cheapest.get("custo", 999)):
					cheapest = t
			tech.start_research(n, String(cheapest.get("id", "")))
			return

	# 4. AÇÃO TÁTICA simples (investe pequeno em saúde/propaganda)
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
	_turns_since_war = 0
	_war_started[_war_key(from_code, to_code)] = current_turn

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
	_war_started.erase(_war_key(from_code, to_code))
	_war_score.erase(_war_key(from_code, to_code))
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
		var base_chance: float = float(alliance.get("reacao_agressao", {}).get("chance_intervencao", 0.5))
		var defender_cont: String = nations[defender_code].continente if nations.has(defender_code) else ""
		for m in members:
			if m == defender_code or m == attacker_code:
				continue
			if not nations.has(m):
				continue
			var ally = nations[m]
			# Amortece cascatas (picos de 143 guerras simultâneas nos playtests):
			# aliados distantes e já ocupados intervêm menos
			var chance: float = base_chance
			if ally.continente != defender_cont:
				chance *= 0.6
			if ally.em_guerra.size() > 0:
				chance *= 0.5
			if randf() < chance:
				if not (attacker_code in ally.em_guerra):
					ally.em_guerra.append(attacker_code)
				var attacker = nations[attacker_code]
				if not (m in attacker.em_guerra):
					attacker.em_guerra.append(m)
				_war_started[_war_key(attacker_code, m)] = current_turn
				responders.append(m)
	return responders

func _war_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

# Fadiga de guerra: conflitos com mais de WAR_FATIGUE_TURNS entram em
# armistício com 30% de chance por turno — guerras não duram para sempre
# (nos playtests, guerras IA↔IA órfãs se acumulavam até 143 simultâneas)
func _process_war_fatigue() -> void:
	var seen: Dictionary = {}
	for code in nations:
		var n = nations[code]
		for enemy in n.em_guerra:
			var key: String = _war_key(code, enemy)
			if seen.has(key):
				continue
			seen[key] = true
			if not _war_started.has(key):
				_war_started[key] = current_turn  # auto-registro (pós-load/eventos)
				continue
			if current_turn - int(_war_started[key]) >= WAR_FATIGUE_TURNS and randf() < 0.30:
				# Armistício por exaustão
				var other: String = enemy
				n.em_guerra.erase(other)
				if nations.has(other):
					nations[other].em_guerra.erase(code)
					nations[other].relacoes[code] = -40
				n.relacoes[other] = -40
				_war_started.erase(key)
				_war_score.erase(key)
				_log_news({
					"type": "armisticio",
					"headline": "🕊️ Armistício: %s e %s encerram guerra de %d anos" % [n.nome, nations[other].nome if nations.has(other) else other, (current_turn - 0) / 4],
					"body": "Exaustão mútua força o fim das hostilidades.",
					"involves_player": player_nation != null and (code == player_nation.codigo_iso or other == player_nation.codigo_iso),
					"color": Color(0.7, 0.9, 0.7),
				}, [code, other], n.continente)
	# Limpa registros órfãos (pares que já não estão em guerra)
	for key in _war_started.keys():
		var parts: PackedStringArray = key.split("|")
		if parts.size() == 2 and nations.has(parts[0]):
			if not (parts[1] in nations[parts[0]].em_guerra):
				_war_started.erase(key)
				_war_score.erase(key)

# ─────────────────────────────────────────────────────────────────
# RESOLUÇÃO DE GUERRA — vantagem acumula; vitória decisiva = espólios
# ─────────────────────────────────────────────────────────────────

func _process_war_resolution() -> void:
	var seen: Dictionary = {}
	for code in nations.keys():
		var n = nations[code]
		for enemy in n.em_guerra.duplicate():
			var key: String = _war_key(code, enemy)
			if seen.has(key) or not nations.has(enemy):
				continue
			seen[key] = true
			var a_code: String = code if code < enemy else enemy
			var b_code: String = enemy if code < enemy else code
			var a = nations[a_code]
			var b = nations[b_code]
			# Vantagem por turno: poder militar pesa mais, economia sustenta
			var mil_diff: float = a.get_military_power() - b.get_military_power()
			var econ_diff: float = (a.pib_bilhoes_usd - b.pib_bilhoes_usd) * 0.001
			var delta: float = clamp(mil_diff * 0.02 + econ_diff * 0.01, -8.0, 8.0)
			delta += randf_range(-2.0, 2.0)  # fricção/fortuna da guerra
			_war_score[key] = float(_war_score.get(key, 0.0)) + delta
			if abs(float(_war_score[key])) >= WAR_DECISIVE_SCORE:
				var winner = a if float(_war_score[key]) > 0.0 else b
				var loser = b if float(_war_score[key]) > 0.0 else a
				_end_war_with_spoils(winner, loser, "vitória decisiva")

# Score da guerra do PONTO DE VISTA de uma nação (pra UI: quem está vencendo)
func get_war_score_for(code: String, enemy: String) -> float:
	var key: String = _war_key(code, enemy)
	var raw: float = float(_war_score.get(key, 0.0))
	return raw if code < enemy else -raw

# Encerra a guerra com ESPÓLIOS para o vencedor: reparações, transferência
# do melhor recurso do perdedor, prestígio militar e efeitos políticos.
func _end_war_with_spoils(winner, loser, motivo: String) -> void:
	var w_code: String = winner.codigo_iso
	var l_code: String = loser.codigo_iso
	winner.em_guerra.erase(l_code)
	loser.em_guerra.erase(w_code)
	var key: String = _war_key(w_code, l_code)
	_war_started.erase(key)
	_war_score.erase(key)
	# Reparações de guerra: até 50% do tesouro do perdedor (cap 10% do PIB dele)
	var reparacao: float = clamp(loser.tesouro * 0.5, 0.0, loser.pib_bilhoes_usd * 0.10)
	loser.tesouro = max(0.0, loser.tesouro - reparacao)
	winner.tesouro += reparacao
	# Concessão de recursos: o melhor recurso do perdedor muda de mãos (parcial)
	var best_res: String = ""
	var best_val: float = 0.0
	for k in loser.recursos:
		if float(loser.recursos[k]) > best_val:
			best_val = float(loser.recursos[k])
			best_res = k
	var take: float = 0.0
	if best_res != "":
		take = min(15.0, best_val * 0.25)
		loser.recursos[best_res] = max(0.0, best_val - take)
		winner.recursos[best_res] = min(100.0, float(winner.recursos.get(best_res, 0)) + take)
	# Política: vencedor celebra, perdedor amarga
	winner.apoio_popular = clamp(winner.apoio_popular + 10.0, 0.0, 100.0)
	winner.felicidade = clamp(winner.felicidade + 5.0, 0.0, 100.0)
	loser.apoio_popular = clamp(loser.apoio_popular - 10.0, 0.0, 100.0)
	loser.estabilidade_politica = clamp(loser.estabilidade_politica - 8.0, 0.0, 100.0)
	# Prestígio militar do vencedor
	winner.militar["poder_militar_global"] = float(winner.militar.get("poder_militar_global", 0)) + 3.0
	# Rancor duradouro
	winner.relacoes[l_code] = -60
	loser.relacoes[w_code] = -80
	var spoils_txt: String = "Reparações: $%dB" % int(reparacao)
	if best_res != "":
		spoils_txt += " • %s +%d" % [best_res.capitalize(), int(take)]
	var involves_p: bool = player_nation != null and (w_code == player_nation.codigo_iso or l_code == player_nation.codigo_iso)
	_log_news({
		"type": "guerra_vencida",
		"headline": "🏆 %s VENCE a guerra contra %s (%s)" % [winner.nome, loser.nome, motivo],
		"body": spoils_txt + ". O mundo toma nota.",
		"involves_player": involves_p,
		"color": Color(1, 0.85, 0.3),
	}, [w_code, l_code], winner.continente)
	if achievements and player_nation and w_code == player_nation.codigo_iso:
		achievements.on_war_won()

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
		# CAPITULAÇÃO AUTOMÁTICA: nação exausta (tesouro zerado + apoio em
		# colapso) rende-se — guerras não se arrastam para sempre
		if n.tesouro <= 0.0 and n.apoio_popular < 25.0 and randf() < 0.5:
			var enemies: Array = n.em_guerra.duplicate()
			for e_code in enemies:
				if nations.has(e_code):
					# Quem recebe a rendição VENCE — extrai espólios
					_end_war_with_spoils(nations[e_code], n, "capitulação")
				else:
					_war_started.erase(_war_key(code, e_code))
					_war_score.erase(_war_key(code, e_code))
			n.em_guerra.clear()
			n.estabilidade_politica = max(0.0, n.estabilidade_politica - 5.0)
			_log_news({
				"type": "capitulacao",
				"headline": "🏳️ %s capitula — exaustão de guerra" % n.nome,
				"body": "Sem recursos e sem apoio interno, o governo aceita os termos de rendição.",
				"involves_player": (player_nation != null and (code == player_nation.codigo_iso or player_nation.codigo_iso in enemies)),
				"color": Color(0.9, 0.8, 0.5),
			}, [code], n.continente)

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
	# Registra no log de decisões (conta pra conquista "Forjador da História")
	if timeline:
		timeline.decision_log.append({
			"event_id": event.get("id", event.get("nome", "evento")),
			"event_headline": event.get("nome", ""),
			"choice_id": str(choice_idx),
			"choice_label": choice.get("label", choice.get("texto", "")),
			"turn": current_turn,
			"year": date_year,
		})
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
	if achievements: achievements.on_war_declared(true)
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
	if diplomacy.count_treaties_of(player_nation.codigo_iso) >= diplomacy.MAX_TREATIES_PER_NATION:
		return {"ok": false, "reason": "Limite de %d tratados ativos atingido" % diplomacy.MAX_TREATIES_PER_NATION}
	if diplomacy.count_treaties_of(target_code) >= diplomacy.MAX_TREATIES_PER_NATION:
		return {"ok": false, "reason": "O alvo já está no limite de tratados"}
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

# ─────────────────────────────────────────────────────────────────
# AÇÕES DE PAINEL — catálogo ÚNICO (fonte de verdade)
# GameOverlay (botões) e BotPlayer (IA espectador) chamam a MESMA API.
# Antes: efeitos duplicados na UI e no bot, com custos/valores divergentes.
# ─────────────────────────────────────────────────────────────────

const PANEL_ACTIONS := {
	# ── GOVERNO (efeitos escalam com get_action_multiplier) ──
	"propaganda":           {"panel": "governo",  "cost": 10,  "label": "📢 PROPAGANDA",        "desc": "Apoio +10%"},
	"combater_corrupcao":   {"panel": "governo",  "cost": 20,  "label": "⚖ ANTI-CORRUPÇÃO",    "desc": "Corrupção -15%"},
	"reforma_politica":     {"panel": "governo",  "cost": 30,  "label": "🏛 REFORMA POLÍTICA",  "desc": "Estab +12, Felic +5"},
	"investir_saude":       {"panel": "governo",  "cost": 20,  "label": "🏥 SAÚDE",             "desc": "Felic +4, Apoio +2"},
	"investir_educacao":    {"panel": "governo",  "cost": 20,  "label": "📚 EDUCAÇÃO",          "desc": "Pesquisa +5%"},
	"investir_seguranca":   {"panel": "governo",  "cost": 20,  "label": "👮 SEGURANÇA",         "desc": "Estab +3, Corrup -2"},
	"investir_previdencia": {"panel": "governo",  "cost": 20,  "label": "👵 PREVIDÊNCIA",       "desc": "Apoio +3"},
	"estimulo_fiscal":      {"panel": "governo",  "cost": 80,  "label": "💰 ESTÍMULO FISCAL",   "desc": "PIB +2%, Felic +5"},
	"aperto_monetario":     {"panel": "governo",  "cost": 30,  "label": "🏦 APERTO MONETÁRIO",  "desc": "Inflação -12, PIB -0.5%"},
	# ── MILITAR ──
	"recrutar_infantaria":  {"panel": "militar",  "cost": 5,   "label": "🪖 RECRUTAR INFANTARIA", "desc": "+10.000 soldados"},
	"recrutar_tanques":     {"panel": "militar",  "cost": 15,  "label": "🛡 RECRUTAR TANQUES",    "desc": "+200 tanques"},
	"recrutar_avioes":      {"panel": "militar",  "cost": 25,  "label": "✈ RECRUTAR AVIÕES",     "desc": "+50 aviões"},
	"recrutar_navios":      {"panel": "militar",  "cost": 30,  "label": "⚓ RECRUTAR NAVIOS",     "desc": "+5 navios"},
	"construir_base":       {"panel": "militar",  "cost": 40,  "label": "🏗 CONSTRUIR BASE",      "desc": "Poder +10"},
	"aumentar_orcamento":   {"panel": "militar",  "cost": 20,  "label": "💰 +20% ORÇAMENTO MIL.", "desc": "Orçamento permanente +20%"},
	# ── ECONOMIA ──
	"infra_basica":         {"panel": "economia", "cost": 50,  "label": "🏗 INFRAESTRUTURA",      "desc": "PIB +1%"},
	"infra_megaprojeto":    {"panel": "economia", "cost": 100, "label": "🌉 MEGAPROJETO",         "desc": "PIB +2.5%, Estab -2"},
	"subsidios":            {"panel": "economia", "cost": 40,  "label": "💵 SUBSÍDIOS SETORIAIS", "desc": "PIB +1.5%, Corrup +3"},
	"explorar_recurso":     {"panel": "economia", "cost": 20,  "label": "⛏ EXPLORAR RECURSOS",   "desc": "Recurso escasso +15%"},
}

# Lista ordenada das ações de um painel (pra UI montar os botões)
func get_panel_actions(panel_id: String) -> Array:
	var out: Array = []
	for id in PANEL_ACTIONS:
		var meta: Dictionary = PANEL_ACTIONS[id]
		if meta.get("panel", "") == panel_id:
			var entry: Dictionary = meta.duplicate()
			entry["id"] = id
			out.append(entry)
	return out

# Executa uma ação de painel para o JOGADOR.
# Valida custo/ações ANTES de consumir. Retorna {ok, msg|reason, cost}.
# Presentação (ticker, som, re-render) fica a cargo de quem chama.
func player_panel_action(action_id: String) -> Dictionary:
	var n = player_nation
	if n == null:
		return {"ok": false, "reason": "Sem nação"}
	if not PANEL_ACTIONS.has(action_id):
		return {"ok": false, "reason": "Ação desconhecida: %s" % action_id}
	var meta: Dictionary = PANEL_ACTIONS[action_id]
	var cost: int = int(meta.get("cost", 0))
	if n.tesouro < cost:
		return {"ok": false, "reason": "Fundos insuficientes: $%dB necessários, $%dB disponíveis" % [cost, int(n.tesouro)]}
	if not _consume_action():
		return {"ok": false, "reason": "Sem ações restantes neste turno (limite: %d)" % PLAYER_ACTIONS_PER_TURN}
	n.tesouro -= cost
	var msg: String = _apply_panel_action(n, action_id)
	return {"ok": true, "msg": msg, "cost": cost}

# Aplica o efeito da ação na nação. Mantém os valores calibrados
# que antes viviam em GameOverlay (governo escala com mult; militar/economia não).
func _apply_panel_action(n, action_id: String) -> String:
	var mult: float = n.get_action_multiplier()
	match action_id:
		# ── GOVERNO ──
		"propaganda":
			var v: float = 10.0 * mult
			n.apoio_popular = min(100.0, n.apoio_popular + v)
			return "Apoio +%d%%" % int(v)
		"combater_corrupcao":
			var v: float = 15.0 * mult
			n.corrupcao = max(0.0, n.corrupcao - v)
			return "Corrupção -%d%%" % int(v)
		"reforma_politica":
			var ve: float = 12.0 * mult
			var vf: float = 5.0 * mult
			n.estabilidade_politica = min(100.0, n.estabilidade_politica + ve)
			n.felicidade = min(100.0, n.felicidade + vf)
			return "Estab +%d, Felic +%d" % [int(ve), int(vf)]
		"investir_saude":
			_add_social_spend(n, "saude")
			var vf: float = 4.0 * mult
			var va: float = 2.0 * mult
			n.felicidade = min(100.0, n.felicidade + vf)
			n.apoio_popular = min(100.0, n.apoio_popular + va)
			return "Felic +%d, Apoio +%d" % [int(vf), int(va)]
		"investir_educacao":
			_add_social_spend(n, "educacao")
			n.velocidade_pesquisa = min(3.0, n.velocidade_pesquisa + 0.05)
			return "Pesquisa +5%"
		"investir_seguranca":
			_add_social_spend(n, "seguranca")
			var ve: float = 3.0 * mult
			var vc: float = 2.0 * mult
			n.estabilidade_politica = min(100.0, n.estabilidade_politica + ve)
			n.corrupcao = max(0.0, n.corrupcao - vc)
			return "Estab +%d, Corrup -%d" % [int(ve), int(vc)]
		"investir_previdencia":
			_add_social_spend(n, "previdencia")
			var va: float = 3.0 * mult
			n.apoio_popular = min(100.0, n.apoio_popular + va)
			return "Apoio +%d" % int(va)
		"estimulo_fiscal":
			n.apply_pib_multiplier(1.02)
			n.felicidade = min(100.0, n.felicidade + 5.0)
			n.corrupcao = min(100.0, n.corrupcao + 2.0)
			return "PIB +2%, Felic +5"
		"aperto_monetario":
			var vi: float = 12.0 * mult
			n.inflacao = max(0.0, n.inflacao - vi)
			n.apply_pib_multiplier(0.995)
			n.felicidade = max(0.0, n.felicidade - 2.0)
			return "Inflação -%d, PIB -0.5%%" % int(vi)
		# ── MILITAR ──
		"recrutar_infantaria", "recrutar_tanques", "recrutar_avioes", "recrutar_navios":
			var u: Dictionary = n.militar.get("unidades", {})
			if u.is_empty():
				u = {"infantaria": 0, "tanques": 0, "avioes": 0, "navios": 0}
				n.militar["unidades"] = u
			match action_id:
				"recrutar_infantaria":
					u["infantaria"] = u.get("infantaria", 0) + 10000
					return "+10.000 soldados"
				"recrutar_tanques":
					u["tanques"] = u.get("tanques", 0) + 200
					return "+200 tanques"
				"recrutar_avioes":
					u["avioes"] = u.get("avioes", 0) + 50
					return "+50 aviões"
				_:
					u["navios"] = u.get("navios", 0) + 5
					return "+5 navios"
		"construir_base":
			n.militar["poder_militar_global"] = float(n.militar.get("poder_militar_global", 0)) + 10
			n.estabilidade_politica = max(0.0, n.estabilidade_politica - 2.0)
			return "Poder Militar +10 • Estab -2"
		"aumentar_orcamento":
			n.militar["orcamento_militar_bilhoes"] = float(n.militar.get("orcamento_militar_bilhoes", 0)) * 1.2
			return "Orçamento militar +20%"
		# ── ECONOMIA ──
		"infra_basica":
			n.apply_pib_multiplier(1.01)
			return "PIB +1%"
		"infra_megaprojeto":
			n.apply_pib_multiplier(1.025)
			n.estabilidade_politica = max(0.0, n.estabilidade_politica - 2.0)
			return "PIB +2.5%, Estab -2"
		"subsidios":
			n.apply_pib_multiplier(1.015)
			n.corrupcao = min(100.0, n.corrupcao + 3.0)
			return "PIB +1.5%, Corrup +3"
		"explorar_recurso":
			var rec: Dictionary = n.recursos
			var min_k := ""
			var min_v: float = 999.0
			for k in rec:
				if float(rec[k]) < min_v:
					min_v = float(rec[k])
					min_k = k
			if min_k != "":
				rec[min_k] = min(100.0, float(rec[min_k]) + 15.0)
				return "%s +15%%" % min_k.capitalize()
			return "Sem recursos mapeados"
	return "OK"

# Gasto social permanente ESCALADO AO PIB (0.4% por investimento, teto 2%
# do PIB por categoria). Antes: +$20B fixos — em um país de PIB $9B isso
# era 60% do PIB em 3 cliques → hiperinflação em 6 turnos (morte garantida
# de nações pequenas, detectada no BalanceSim).
func _add_social_spend(n, key: String) -> void:
	var inc: float = max(1.0, n.pib_bilhoes_usd * 0.004)
	var cap: float = max(2.0, n.pib_bilhoes_usd * 0.02)
	n.gasto_social[key] = min(cap, float(n.gasto_social.get(key, 0)) + inc)

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
