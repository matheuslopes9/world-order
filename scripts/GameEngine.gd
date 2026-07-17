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
var date_month: int = 1   # 1-12 (ritmo mensal: 1 turno = 1 mês)
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
const WAR_FATIGUE_TURNS: int = 60         # guerras > 5 anos (60 meses) entram em fadiga
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

# ── MERCADO DE AÇÕES (Fase 3 da economia) ──
# Índice global compartilhado por todas as nações. Flutua com o estado do
# mundo (choques derrubam, prosperidade + paz sobem) + ruído. O jogador
# investe tesouro OCIOSO; retorno é real mas COMPLEMENTAR (não domina —
# governar bem rende mais que especular). Base 1000.
var market_index: float = 1000.0
var market_history: Array = []       # últimos N valores (sparkline)
var player_stocks_invested: float = 0.0   # $B que o jogador aportou (custo)
var player_stocks_shares: float = 0.0      # "cotas" compradas (valor = shares × index/1000)
const MARKET_HISTORY_MAX: int = 40

# ── CRIPTOMOEDA — WorldCoin (Fase 4 da economia) ──
# Ativo de ALTÍSSIMA volatilidade: ciclos bull/bear pronunciados + risco de
# COLAPSO súbito. Alto risco/retorno, COMPLEMENTAR (não domina). Base 1000.
# Nações sob sanção podem usar cripto p/ driblar bloqueios (realista).
var crypto_price: float = 1000.0
var crypto_history: Array = []
var crypto_cycle: float = 0.0        # fase do ciclo bull/bear (-1 bear … +1 bull)
var player_crypto_invested: float = 0.0
var player_crypto_coins: float = 0.0
var crypto_legal_tender: bool = false  # adotou cripto como moeda legal?
const CRYPTO_HISTORY_MAX: int = 40
# Haircut prudencial: o cap de COMPRA é 12% do PIB, mas a valorização pode inflar
# a posição além disso. Se passar de HAIRCUT_TETO do PIB por alta de preço, o
# excedente é realizado aos poucos (HAIRCUT_FRAC/turno) — corta a super-exposição
# sem forçar venda total na alta (mantém o upside da aposta). Ver MEGASIM_FINDINGS.
const CRYPTO_HAIRCUT_TETO: float = 0.15   # 15% do PIB
const CRYPTO_HAIRCUT_FRAC: float = 0.10   # realiza 10% do excedente por turno
var _crypto_haircut_avisado: bool = false
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
const SANCTION_DURATION: int = 15  # ~15 meses de duração padrão (ritmo mensal)
const SANCTION_PIB_PENALTY: float = 0.995  # -0.5% PIB/mês no alvo (dura 3× mais turnos)
const SANCTION_COST: int = 30  # $30B custo pro impositor (logística, perdas comerciais)

# Acordos comerciais ativos — lista de { exporter, importer, resource, value_per_turn, turns_remaining }
# Cada turno: importer paga $value/turn ao exporter, exporter ganha receita
var active_trades: Array = []
const TRADE_DURATION: int = 24  # ~24 meses por contrato (ritmo mensal)
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
	"ai_speed": 24,   # nações que agem por turno (cursor rotativo — todas a cada ~8 turnos)
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
		n.pesquisa_por_ministerio = {}
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
		# Piso de PIB $2B: micro-economias devastadas (Eritreia $0.7B em 2000, pós-guerra
		# com a Etiópia) colapsavam deterministicamente ao piso e ficavam injogáveis
		# (PIB→0, inflação alta em 4/4 partidas). O piso mantém a nação viável sem
		# distorcer as demais (só afeta as pouquíssimas abaixo de $2B).
		n.pib_bilhoes_usd = maxf(n.pib_bilhoes_usd, 2.0)
		# Snapshot do PIB APÓS o override — pib_inicial deve refletir o ponto
		# de partida real da campanha (antes guardava o valor de 2024, gerando
		# caps e títulos de legado inconsistentes)
		n.pib_inicial = n.pib_bilhoes_usd
		# PERSONALIDADE: nations.json traz personalidade=null p/ TODAS as nações —
		# atribui aqui (líder real de leaders_2024, ou arquétipo por regime).
		_assign_personality(n)
	print("[2000] Overrides aplicados: %d explícitos + %d via escala global" % [changed_explicit, changed_global])
	# Semeia relações iniciais por afinidade ideológica (o mundo já começa com blocos).
	_seed_ideological_relations()
	# Membros do mesmo bloco (OTAN, BRICS…) começam como aliados próximos.
	_seed_bloc_relations()

# Dá a "cara" inicial ao mundo: nações de ideologia afim começam com relação positiva,
# opostas com relação fria. As relações partiam todas de 0 (neutras) — agora refletem
# o alinhamento geopolítico de 2000. Só semeia pares do MESMO continente + as grandes
# potências entre si (evita semear 195×195 e manter foco no que importa).
func _seed_ideological_relations() -> void:
	var codes: Array = nations.keys()
	# Ordena as maiores potências (relações globais só entre elas + vizinhos regionais)
	var grandes: Array = []
	for c in codes:
		if nations[c].pib_bilhoes_usd >= 800.0:
			grandes.append(c)
	for i in codes.size():
		var a = nations[codes[i]]
		for j in range(i + 1, codes.size()):
			var b = nations[codes[j]]
			var mesmo_cont: bool = a.continente == b.continente
			var ambas_grandes: bool = (codes[i] in grandes) and (codes[j] in grandes)
			if not mesmo_cont and not ambas_grandes:
				continue
			# afinidade [-1,+1] → relação inicial [-35,+35], atenuada p/ pares fracos
			var aff: float = _ideological_affinity(a, b)
			var peso: float = 1.0 if ambas_grandes else 0.7
			var rel: float = aff * 35.0 * peso
			a.relacoes[b.codigo_iso] = clampf(rel, -100.0, 100.0)
			b.relacoes[a.codigo_iso] = clampf(rel, -100.0, 100.0)

# Atribui uma personalidade válida à nação: usa o líder real (leaders_2024) quando
# existe; senão, um arquétipo genérico coerente com o regime político. Determinístico.
func _assign_personality(n) -> void:
	# Já tem personalidade válida? (ex.: save carregado) — respeita.
	var personalities: Dictionary = personalities_data.get("personalities", {})
	if n.personalidade != null and personalities.has(String(n.personalidade)):
		return
	# 1. Líder real de 2024 mapeado por código ISO
	var leaders: Dictionary = personalities_data.get("leaders_2024", {})
	if leaders.has(n.codigo_iso):
		var pid: String = String(leaders[n.codigo_iso].get("personalidade", ""))
		if personalities.has(pid):
			n.personalidade = pid
			return
	# 2. Fallback por regime político (arquétipo genérico coerente)
	var r: String = n.regime_politico
	if ("DITADURA" in r) or ("AUTORITAR" in r):
		n.personalidade = "agressivo"
	elif ("TEOCRACIA" in r) or ("COMUNIS" in r):
		n.personalidade = "isolacionista"
	elif ("MONARQUIA" in r):
		n.personalidade = "expansionista"
	elif n.pib_bilhoes_usd >= 500.0:
		n.personalidade = "tecnocrata"   # potências médias/grandes: orientadas a tech
	else:
		n.personalidade = "diplomatico"  # default pacífico p/ nações menores

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
	date_month = 1
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
		# Dá tech_bonus tecnologias aleatórias pra cada nação grande (PIB > 500B).
		# tech_data.tecnologias é uma LISTA de 57 techs (não um dict de categorias).
		var all_tech_ids: Array = []
		for t in tech_data.get("tecnologias", []):
			all_tech_ids.append(t.get("id", ""))
		for code in nations.keys():
			var n = nations[code]
			if n.pib_bilhoes_usd >= 500.0:
				for i in tech_bonus:
					var rand_id: String = String(all_tech_ids[randi() % all_tech_ids.size()])
					if rand_id != "" and not (rand_id in n.tecnologias_concluidas):
						n.tecnologias_concluidas.append(rand_id)
	# Modificadores TEMÁTICOS (#8): dão identidade própria a cada cenário além da janela.
	# Instabilidade inicial (Década Crítica: mundo mais frágil)
	var start_instab: float = float(found.get("start_instability", 0))
	if start_instab != 0.0:
		for code in nations.keys():
			nations[code].estabilidade_politica = clampf(nations[code].estabilidade_politica + start_instab, 0.0, 100.0)
	# DEFCON inicial (Guerra Fria 2.0: tensão elevada desde o começo)
	if found.has("start_defcon"):
		defcon = clampi(int(found.get("start_defcon", 5)), 1, 5)
	# Velocidade de pesquisa (Guerra Fria 2.0: corrida tecnológica)
	var research_mult: float = float(found.get("research_speed_mult", 1.0))
	if research_mult != 1.0:
		for code in nations.keys():
			nations[code].velocidade_pesquisa *= research_mult
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
	date_month += 1
	if date_month > 12:
		date_month = 1
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
		_process_leadership(n)
		n.record_history()
		# Gabinete: verba de P&D alocada rende XP contínuo ao ministério
		if n.ministerios != null:
			for pasta in n.ministerios:
				var vb: float = float(n.ministerios[pasta].get("verba", 0.0))
				if vb > 0.0:
					n.add_ministry_xp(pasta, vb * 0.05)   # XP/turno /3 (ritmo mensal)

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
	# Blocos geopolíticos: bônus de membro (segurança coletiva, comércio interno)
	_process_bloc_benefits()
	# Eventos aleatórios
	_roll_events()
	# Choques econômicos globais (recessões, crises energéticas...)
	_process_global_shocks()
	# Corrupção do jogador: escândalos, fuga de empresas, operações anticorrupção
	_process_corruption()
	# Mercado de ações: atualiza o índice global
	_process_market()
	# Criptomoeda: ciclos bull/bear e risco de colapso
	_process_crypto()
	# Doutrina econômica escolhida no wizard: aplica o efeito por turno prometido
	_process_economic_doctrine()
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

	# Coalizão de contenção: se o jogador vira hegemon, as grandes potências se unem
	# contra ele (balancing realista — o mundo reage à ascensão).
	_process_containment_coalition()

	# Recuperação de DEFCON: 4 turnos sem nova guerra → tensão mundial alivia
	# (antes o DEFCON só descia — o mundo travava em alerta nuclear permanente)
	_turns_since_war += 1
	if _turns_since_war >= 12 and defcon < 5:   # ~1 ano sem guerra (ritmo mensal)
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
	var pib_norm: float = _pib_power_norm(n.pib_bilhoes_usd)
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

# Normalização COMPRIMIDA do PIB para o score de poder. Linear (pib/max) fazia o PIB
# de nações pequenas virar ~0 (China a $1,5 quadrilhão) → virada épica = 0%. Log puro
# facilitava demais o topo (hegemonia no turno 180). Meio-termo: razão elevada a 0.5
# (raiz) — comprime a escala o bastante para nações pequenas contarem, mas o PIB
# absoluto ainda ordena claramente o topo (grandes potências continuam à frente).
func _pib_power_norm(pib: float) -> float:
	var mx: float = maxf(_world_max_pib, 200.0)
	var ratio: float = clampf(maxf(pib, 50.0) / mx, 0.0, 1.0)
	return pow(ratio, 0.5)

# Decomposição do score de poder — a UI usa pra mostrar ONDE investir.
# (mesma fórmula de compute_power_score; manter em sincronia)
func get_power_breakdown(n) -> Dictionary:
	var pib_norm: float = _pib_power_norm(n.pib_bilhoes_usd)
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
	# ── Derrotas ── (contadores/janelas ×3 — ritmo mensal: 1 turno = 1 mês)
	var honeymoon_turns: int = 15 + int(n.get_meta("perk_honeymoon_extra", 0))  # ~1,25 ano
	var honeymoon: bool = current_turn <= honeymoon_turns
	if n.apoio_popular < 20:
		n.revolucao_turnos += 1
	else:
		n.revolucao_turnos = 0
	if n.tesouro <= 0:
		n.falencia_turnos += 1
		# FMI oferece resgate ANTES do colapso (6 meses de falência de 12)
		if n.falencia_turnos == 6 and bailout_pending.is_empty() and current_turn - _last_bailout_turn > 120:
			_offer_bailout()
	else:
		n.falencia_turnos = 0
	if not honeymoon:
		if n.revolucao_turnos >= 9:
			_fire_endgame(false, "💀 REVOLUÇÃO", "Apoio popular abaixo de 20%% por 9 meses.")
			return
		if n.falencia_turnos >= 12:
			_fire_endgame(false, "💀 FALÊNCIA NACIONAL", "Tesouro zerado por 12 meses. Colapso fiscal.")
			return
		if n.estabilidade_politica < 8:
			_fire_endgame(false, "💀 GOLPE DE ESTADO", "Estabilidade colapsou abaixo de 8%%. Você foi deposto.")
			return
		# Graça estendida contra inflação HERDADA: ~3 anos (36 meses) pra domar antes
		# da derrota valer (alguns países começam 2000 já em crise inflacionária).
		if n.inflacao > 80 and current_turn > 36:
			_fire_endgame(false, "💀 HIPERINFLAÇÃO", "Inflação acima de 80%%. Economia em ruínas.")
			return
	# ── Marco "Nação Modelo": 20 turnos de indicadores excelentes ──
	# Celebra e CONTINUA (antes isto encerrava a campanha como "hegemonia"
	# no ano ~2008, trivializando os outros 92 anos de jogo)
	var win_cond: bool = n.apoio_popular >= 65 and n.estabilidade_politica >= 65 and n.inflacao <= 15 and n.tesouro > 0
	n.set_meta("victory_streak", (int(n.get_meta("victory_streak", 0)) + 1) if win_cond else 0)
	if int(n.get_meta("victory_streak", 0)) >= 60 and not bool(n.get_meta("model_nation_done", false)):
		n.set_meta("model_nation_done", true)
		_log_news({
			"type": "marco",
			"headline": "🌟 %s é reconhecida como NAÇÃO MODELO" % n.nome,
			"body": "5 anos de indicadores exemplares. O mundo observa seu governo como referência.",
			"involves_player": true,
			"color": Color(1, 0.9, 0.4),
		}, [n.codigo_iso], n.continente)
	# ── Vitória: HEGEMONIA GLOBAL — liderança real do ranking de poder ──
	# Exige: #1 no poder composto + economia ≥ 50% da maior + país estável,
	# sustentado por 48 meses (4 anos), a partir do turno 180 (ano ~2015).
	if victory_achieved:
		return
	var power_rank: int = get_power_rank(n.codigo_iso)
	# 35% do líder (era 50% — inalcançável: a China da IA cresce ~200× e
	# virava um teto impossível; 0 hegemonias em 900 jogos simulados)
	var econ_relevante: bool = n.pib_bilhoes_usd >= _world_max_pib * 0.45
	if power_rank == 1 and econ_relevante and n.apoio_popular >= 55.0 and n.estabilidade_politica >= 55.0:
		n.set_meta("hegemony_streak", int(n.get_meta("hegemony_streak", 0)) + 1)
	else:
		n.set_meta("hegemony_streak", 0)
	if int(n.get_meta("hegemony_streak", 0)) >= 48 and current_turn >= 180:
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
# EMPRÉSTIMO PROATIVO — alavancagem estratégica (Fase 2 da economia)
# O jogador ESCOLHE tomar dívida para investir cedo (não só o FMI em crise).
# Limite e juros vêm do RATING DE CRÉDITO da nação. Não consome ação — é
# decisão orçamentária, feita livremente no painel Fazenda.
# ─────────────────────────────────────────────────────────────────

func player_take_loan(valor: float) -> Dictionary:
	var n = player_nation
	if n == null:
		return {"ok": false, "reason": "Sem nação"}
	var limite: float = n.limite_emprestimo()
	if valor <= 0.0:
		return {"ok": false, "reason": "Valor inválido"}
	if valor > limite:
		return {"ok": false, "reason": "Acima do limite de crédito ($%dB). Melhore o rating." % int(limite)}
	# O empréstimo entra no tesouro; a dívida cresce pelo principal (juros
	# são cobrados por turno em calc_despesas, conforme o rating vigente).
	n.tesouro += valor
	n.divida_publica += valor
	var juros_pct: float = n.juros_emprestimo() * 100.0
	_log_news({
		"type": "emprestimo",
		"headline": "🏦 %s capta $%dB no mercado (rating %s)" % [n.nome, int(valor), n.rating_letra()],
		"body": "Juros de %.1f%%/ano. Alavancagem para investir — se bem usada, acelera; se não, afunda." % juros_pct,
		"involves_player": true,
		"color": Color(0.5, 0.8, 1),
	}, [n.codigo_iso], n.continente)
	return {"ok": true, "valor": valor, "juros": n.juros_emprestimo()}

# Amortização antecipada: paga parte da dívida com o tesouro (melhora rating,
# reduz juros futuros). Não consome ação.
func player_repay_debt(valor: float) -> Dictionary:
	var n = player_nation
	if n == null:
		return {"ok": false, "reason": "Sem nação"}
	valor = clampf(valor, 0.0, minf(n.tesouro, n.divida_publica))
	if valor <= 0.0:
		return {"ok": false, "reason": "Sem tesouro ou sem dívida para pagar"}
	n.tesouro -= valor
	n.divida_publica = maxf(0.0, n.divida_publica - valor)
	return {"ok": true, "valor": valor}

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
	# Rola novo choque: pós-2035, cooldown de 15 anos. Ritmo MENSAL: cooldown ×3
	# (180 meses) e probabilidade ÷3 (0.004/mês) — mesma frequência anual de choques.
	# Cenários com shock_frequency_mult (Década Crítica) ativam mais cedo e mais vezes.
	var shock_mult: float = float(active_scenario.get("shock_frequency_mult", 1.0)) if not active_scenario.is_empty() else 1.0
	var ano_min: int = 2035 if shock_mult <= 1.0 else 2008
	var cooldown: int = int(180.0 / shock_mult)
	if date_year < ano_min or current_turn - _last_shock_turn < cooldown:
		return
	if randf() > 0.004 * shock_mult:
		return
	var meta: Dictionary = SHOCK_TYPES[randi() % SHOCK_TYPES.size()]
	# Duração do choque ×3 (em meses) para durar o mesmo tempo real
	var dur: int = randi_range(int(meta["dur_min"]) * 3, int(meta["dur_max"]) * 3)
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
		# Efeitos por-turno enquanto o choque dura. Como o choque agora dura 3× mais
		# turnos (dur×3), cada multiplicador é aproximado de 1.0 (dano/turno /3) para
		# o mesmo impacto TOTAL ao longo do choque.
		match sid:
			"recessao_global":
				# Economias grandes e integradas sofrem mais
				var severity: float = 0.995 if n.pib_bilhoes_usd < _world_max_pib * 0.3 else 0.9927
				n.apply_pib_multiplier(severity)
			"crise_energetica":
				var oil: float = float(n.recursos.get("petroleo", 0))
				var gas: float = float(n.recursos.get("gas_natural", 0))
				if oil >= 70.0 or gas >= 70.0:
					n.apply_pib_multiplier(1.001)
				elif oil < 40.0 and gas < 40.0:
					n.apply_pib_multiplier(0.996)
			"colapso_financeiro":
				n.apply_pib_multiplier(0.9967)
				n.inflacao = clamp(n.inflacao + 0.27, 0.0, 100.0)

# ─────────────────────────────────────────────────────────────────
# CORRUPÇÃO — a espiral: escândalos, fuga de empresas, operações
# Foca no país do JOGADOR (a narrativa via WON é sobre ele). A mecânica
# numérica (roubo do tesouro, IED→PIB) já roda na Nation todo turno; aqui
# entram os ACONTECIMENTOS que dão rosto e drama ao sistema.
# ─────────────────────────────────────────────────────────────────
var _last_corruption_event_turn: int = -99

func _process_corruption() -> void:
	var n = player_nation
	if n == null or current_turn - _last_corruption_event_turn < 9:
		return
	var corr: float = n.corrupcao
	var conf: float = n.confianca_investidor

	# 1) ESCÂNDALO DE PROPINA — corrupção alta ocasionalmente estoura na mídia
	if corr >= 55.0 and randf() < (corr - 55.0) / 45.0 * 0.25:
		var desvio: float = max(1.0, n.pib_bilhoes_usd * 0.004 * (corr / 100.0))
		n.tesouro = max(0.0, n.tesouro - desvio)
		n.tesouro_desviado_total += desvio
		n.apoio_popular = max(0.0, n.apoio_popular - 5.0)
		n.confianca_investidor = max(0.0, n.confianca_investidor - 6.0)
		_last_corruption_event_turn = current_turn
		_log_news({
			"type": "corrupcao",
			"headline": "🔴 ESCÂNDALO: US$%.1fB desviados dos cofres públicos" % desvio,
			"body": "Investigação revela esquema de propina. Apoio popular e confiança do mercado despencam.",
			"involves_player": true,
			"color": Color(1, 0.3, 0.3),
		}, [n.codigo_iso], n.continente)
		return

	# 2) ÊXODO DE EMPRESA — confiança baixa faz multinacionais anunciarem saída
	if conf <= 35.0 and randf() < (35.0 - conf) / 35.0 * 0.22:
		var perda: float = n.pib_bilhoes_usd * 0.006
		n.apply_pib_multiplier(1.0 - 0.006)
		n.empresas_sairam += 1
		n.confianca_investidor = max(0.0, n.confianca_investidor - 3.0)
		_last_corruption_event_turn = current_turn
		var setores := ["montadora", "petroleira", "banco internacional", "gigante de tecnologia", "mineradora"]
		var setor: String = setores[randi() % setores.size()]
		_log_news({
			"type": "corrupcao",
			"headline": "🏭 %s anuncia saída do país" % setor.capitalize(),
			"body": "Insegurança jurídica e corrupção citadas. Perda de ~US$%.1fB em investimento e empregos." % perda,
			"involves_player": true,
			"color": Color(1, 0.5, 0.3),
		}, [n.codigo_iso], n.continente)
		return

	# 3) OPERAÇÃO ANTICORRUPÇÃO — recompensa narrativa quando corrupção está BAIXANDO
	#    e já foi alta: sinaliza que o esforço do jogador está dando certo.
	if corr <= 35.0 and conf >= 55.0 and n.tesouro_desviado_total > 5.0 and randf() < 0.12:
		n.confianca_investidor = min(100.0, n.confianca_investidor + 4.0)
		n.apoio_popular = min(100.0, n.apoio_popular + 3.0)
		_last_corruption_event_turn = current_turn
		_log_news({
			"type": "corrupcao",
			"headline": "⚖️ Operação anticorrupção desarticula esquema",
			"body": "Justiça recupera parte dos recursos desviados. Investidores voltam a confiar no país.",
			"involves_player": true,
			"color": Color(0.4, 0.9, 0.6),
		}, [n.codigo_iso], n.continente)

# ─────────────────────────────────────────────────────────────────
# MERCADO DE AÇÕES — índice global compartilhado (Fase 3 da economia)
# ─────────────────────────────────────────────────────────────────

func _process_market() -> void:
	# Deriva MENSAL do índice. Tendência de alta secular (bolsa real ~7%/ano nominal
	# = ~0,57%/mês), pontuada por CRASHES em crises/guerras. Taxas /3 vs. trimestral;
	# ruído /√3 p/ manter a volatilidade anualizada. O drift-base garante que o
	# buy-and-hold de longo prazo seja lucrativo, mas a volatilidade cria timing.
	var drift: float = 0.0060  # ~7,4%/ano bruto — absorve as penalidades frequentes
	# Penalidades por-turno enquanto a condição dura; os choques duram 3× mais turnos
	# (dur×3), então cada penalidade é modesta para não colapsar a bolsa no século.
	if not active_shock.is_empty():
		drift -= 0.012        # CRASH: crise global derruba a bolsa
	if defcon <= 2:
		drift -= 0.004        # tensão MILITAR aguda (DEFCON 1-2) assusta o mercado
	if player_nation != null and player_nation.inflacao > 25.0:
		drift -= 0.003        # inflação descontrolada
	var noise: float = (randf() - 0.5) * 0.0346   # ±1,73% de ruído/mês (vol anual mantida)
	market_index = maxf(100.0, market_index * (1.0 + drift + noise))
	market_history.append(snappedf(market_index, 0.1))
	if market_history.size() > MARKET_HISTORY_MAX:
		market_history.pop_front()

# Valor atual da posição do jogador (cotas × preço).
func player_stocks_value() -> float:
	return player_stocks_shares * (market_index / 1000.0)

# Investe $valor do tesouro no mercado (compra cotas ao preço atual).
func player_invest_stocks(valor: float) -> Dictionary:
	var n = player_nation
	if n == null:
		return {"ok": false, "reason": "Sem nação"}
	valor = clampf(valor, 0.0, n.tesouro)
	if valor < 1.0:
		return {"ok": false, "reason": "Tesouro insuficiente"}
	# Limite prudencial DUPLO (a bolsa é complementar, não pode dominar):
	#  - no máx 40% do caixa (tesouro + posição) — evita all-in
	#  - no máx 25% do PIB em novos aportes — evita a bolsa virar a economia
	var pos_atual: float = player_stocks_value()
	var teto_caixa: float = (n.tesouro + pos_atual) * 0.40
	var teto_pib: float = n.pib_bilhoes_usd * 0.25
	var teto: float = minf(teto_caixa, teto_pib)
	if pos_atual + valor > teto:
		valor = maxf(0.0, teto - pos_atual)
	if valor < 1.0:
		return {"ok": false, "reason": "Posição no limite prudencial (bolsa é complementar)"}
	n.tesouro -= valor
	player_stocks_invested += valor
	player_stocks_shares += valor / (market_index / 1000.0)
	return {"ok": true, "valor": valor}

# Resgata $valor da posição (vende cotas ao preço atual, credita o tesouro).
func player_sell_stocks(valor: float) -> Dictionary:
	var n = player_nation
	if n == null:
		return {"ok": false, "reason": "Sem nação"}
	var pos: float = player_stocks_value()
	valor = clampf(valor, 0.0, pos)
	if valor < 1.0:
		return {"ok": false, "reason": "Sem posição para resgatar"}
	var frac: float = valor / maxf(0.01, pos)
	player_stocks_shares *= (1.0 - frac)
	player_stocks_invested *= (1.0 - frac)
	n.tesouro += valor
	return {"ok": true, "valor": valor}

# ─────────────────────────────────────────────────────────────────
# CRIPTOMOEDA — WorldCoin: volátil, cíclica, com risco de colapso (Fase 4)
# ─────────────────────────────────────────────────────────────────

func _process_crypto() -> void:
	# Modelo: preço oscila em torno de uma ÂNCORA que sobe devagar (adoção
	# crescente ao longo do século), com REVERSÃO À MÉDIA forte (crashes se
	# recuperam, bolhas se desinflam) + ciclo bull/bear + volatilidade extrema
	# + risco de colapso. Sem a reversão, os crashes levavam a cripto ao piso
	# e ela morria; com ela, oscila de verdade (fundo → recuperação → topo).
	# Ritmo MENSAL: âncora cresce ~$16/ano (×1,333/mês em vez de ×4/tri); trend e
	# reversão /3; vol /√3 (volatilidade anual mantida); chance de colapso /3.
	var ancora: float = 800.0 + current_turn * 1.333   # cresce ~$16/ano
	crypto_cycle = clampf(crypto_cycle + (randf() - 0.5) * 0.104, -1.0, 1.0)
	var trend: float = crypto_cycle * 0.0167         # ±1,67%/mês conforme o ciclo
	var reversao: float = clampf((ancora - crypto_price) / ancora, -0.5, 0.5) * 0.04  # puxa p/ âncora
	var vol: float = (randf() - 0.5) * 0.1155         # ±5,8% de ruído/mês (vol anual mantida)
	# Colapso súbito: ~0,67%/mês de chance de crash de 35-55% (mais provável no topo)
	var body := ""
	if randf() < 0.0067 + maxf(0.0, crypto_cycle) * 0.01:
		var crash: float = randf_range(0.35, 0.55)
		crypto_price = maxf(150.0, crypto_price * (1.0 - crash))
		crypto_cycle = -0.7  # vira bear após o crash (mas a reversão recupera depois)
		body = "colapso"
		if player_crypto_coins > 0.0 or crypto_legal_tender:
			_log_news({
				"type": "cripto",
				"headline": "₿ COLAPSO da WorldCoin: -%d%% num único dia" % int(crash * 100),
				"body": "Pânico no mercado cripto. Quem estava exposto amargou perdas pesadas." + (" Nações que adotaram a moeda tremem." if crypto_legal_tender else ""),
				"involves_player": true,
				"color": Color(1, 0.3, 0.3),
			})
	else:
		crypto_price = maxf(150.0, crypto_price * (1.0 + trend + reversao + vol))
	crypto_history.append(snappedf(crypto_price, 0.1))
	if crypto_history.size() > CRYPTO_HISTORY_MAX:
		crypto_history.pop_front()
	# Adoção como moeda legal: expõe a nação à volatilidade (estabilidade oscila)
	if crypto_legal_tender and player_nation != null and body == "colapso":
		player_nation.estabilidade_politica = maxf(0.0, player_nation.estabilidade_politica - 4.0)
	# Haircut prudencial: se a valorização levou a posição acima do teto do PIB,
	# realiza o excedente aos poucos (evita super-exposição silenciosa da cripto).
	_apply_crypto_haircut()

# Se a posição em cripto excede CRYPTO_HAIRCUT_TETO do PIB (por alta de preço, não
# por compra), vende o excedente em fatias de CRYPTO_HAIRCUT_FRAC/turno. Avisa o
# jogador 1× ao cruzar o teto. Vale para humano e bot (via player_sell_crypto).
func _apply_crypto_haircut() -> void:
	var n = player_nation
	if n == null or player_crypto_coins <= 0.0:
		_crypto_haircut_avisado = false
		return
	var teto: float = n.pib_bilhoes_usd * CRYPTO_HAIRCUT_TETO
	var pos: float = player_crypto_value()
	if pos <= teto:
		_crypto_haircut_avisado = false
		return
	if not _crypto_haircut_avisado:
		_crypto_haircut_avisado = true
		_log_news({
			"type": "cripto",
			"headline": "₿ Exposição à WorldCoin acima do prudente (%.0f%% do PIB)" % (pos / maxf(1.0, n.pib_bilhoes_usd) * 100.0),
			"body": "Sua posição em cripto disparou com a alta. O tesouro nacional começa a realizar lucro aos poucos para reduzir o risco.",
			"involves_player": true,
			"color": Color(1, 0.75, 0.2),
		}, [n.codigo_iso], n.continente)
	player_sell_crypto((pos - teto) * CRYPTO_HAIRCUT_FRAC)

func player_crypto_value() -> float:
	return player_crypto_coins * (crypto_price / 1000.0)

func player_buy_crypto(valor: float) -> Dictionary:
	var n = player_nation
	if n == null:
		return {"ok": false, "reason": "Sem nação"}
	valor = clampf(valor, 0.0, n.tesouro)
	if valor < 1.0:
		return {"ok": false, "reason": "Tesouro insuficiente"}
	# Limite prudencial APERTADO (cripto é mais arriscada que a bolsa):
	# max 20% do caixa e max 12% do PIB
	var pos_atual: float = player_crypto_value()
	var teto: float = minf((n.tesouro + pos_atual) * 0.20, n.pib_bilhoes_usd * 0.12)
	if pos_atual + valor > teto:
		valor = maxf(0.0, teto - pos_atual)
	if valor < 1.0:
		return {"ok": false, "reason": "Posição no limite prudencial (cripto é alto risco)"}
	n.tesouro -= valor
	player_crypto_invested += valor
	player_crypto_coins += valor / (crypto_price / 1000.0)
	return {"ok": true, "valor": valor}

func player_sell_crypto(valor: float) -> Dictionary:
	var n = player_nation
	if n == null:
		return {"ok": false, "reason": "Sem nação"}
	var pos: float = player_crypto_value()
	valor = clampf(valor, 0.0, pos)
	if valor < 1.0:
		return {"ok": false, "reason": "Sem posição para vender"}
	var frac: float = valor / maxf(0.01, pos)
	player_crypto_coins *= (1.0 - frac)
	player_crypto_invested *= (1.0 - frac)
	n.tesouro += valor
	return {"ok": true, "valor": valor}

# Adota (ou revoga) a cripto como moeda legal. Bônus: +IED/inovação e permite
# driblar sanções; risco: exposição à volatilidade (estabilidade sofre em crash).
func player_toggle_legal_tender() -> Dictionary:
	var n = player_nation
	if n == null:
		return {"ok": false, "reason": "Sem nação"}
	crypto_legal_tender = not crypto_legal_tender
	if crypto_legal_tender:
		n.confianca_investidor = min(100.0, n.confianca_investidor + 5.0)  # sinal de inovação
		_log_news({
			"type": "cripto",
			"headline": "₿ %s adota a WorldCoin como moeda legal" % n.nome,
			"body": "Aposta ousada: atrai capital de inovação e driblará sanções — mas expõe o país à volatilidade cripto.",
			"involves_player": true,
			"color": Color(1, 0.75, 0.2),
		}, [n.codigo_iso], n.continente)
	else:
		_log_news({
			"type": "cripto",
			"headline": "₿ %s revoga o curso legal da WorldCoin" % n.nome,
			"body": "Recuo diante da volatilidade. Estabilidade em primeiro lugar.",
			"involves_player": true,
			"color": Color(0.7, 0.75, 0.85),
		}, [n.codigo_iso], n.continente)
	return {"ok": true, "legal": crypto_legal_tender}

# ─────────────────────────────────────────────────────────────────
# DOUTRINA ECONÔMICA — efeito por turno da escolha do wizard (etapa 3)
# ─────────────────────────────────────────────────────────────────

# Aplica, 1×/turno, o efeito da doutrina econômica escolhida em "Tomar Posse".
# Cumpre a promessa dos tooltips da etapa 3 (antes só armazenada como meta).
# "mista" é o baseline (sem efeito). Números pequenos e compostos: são um viés
# de longo prazo, não um atalho — coerente com "governar bem > especular".
# Roda a doutrina econômica de TODAS as nações 1×/turno. O jogador usa a doutrina
# escolhida no wizard (meta "economic_doctrine"); os bots usam a ideologia econômica
# da sua personalidade (personalities.json → ideologia_economica). Isso faz o rumo
# econômico de cada país refletir a ideologia do líder (comunista→planejada, etc.).
func _process_economic_doctrine() -> void:
	for code in nations.keys():
		_apply_doctrine_turn(nations[code], _doctrine_for(nations[code]))

# Resolve a doutrina econômica de uma nação: o jogador tem a meta explícita do wizard;
# os bots herdam da ideologia_economica da personalidade. Default "mista".
func _doctrine_for(n) -> String:
	if n == player_nation:
		return String(n.get_meta("economic_doctrine", "mista"))
	var personalities: Dictionary = personalities_data.get("personalities", {})
	var pers: Dictionary = personalities.get(n.personalidade, {})
	return String(pers.get("ideologia_economica", "mista"))

# Aplica o efeito POR TURNO da doutrina a uma nação.
# CALIBRAÇÃO: taxas pequenas — compostas por 1200 turnos (1 século no ritmo MENSAL)
# dão um VIÉS sensível mas não dominante (Livre ~1,5× PIB, Planej ~0,9×, Nórdico
# ~0,85×). Taxas ÷3 vs. o ritmo trimestral. O "+5 corrupção" do Livre Mercado é
# estrutural (1× no takeover, ver _apply_economic_doctrine_once).
func _apply_doctrine_turn(n, doctrine: String) -> void:
	match doctrine:
		"livre_mercado":
			n.pib_bilhoes_usd *= 1.00033       # PIB ~1,5× no século
		"planejada":
			n.tesouro *= 1.00167               # tesouro ~1,2× ao longo do século
			n.pib_bilhoes_usd *= 0.9999        # PIB ~0,89× (menos dinamismo)
		"nordica":
			n.felicidade = clampf(n.felicidade + 0.1, 0.0, 100.0)  # bem-estar sustentado
			n.pib_bilhoes_usd *= 0.99987       # PIB ~0,85× (carga tributária alta)
		_:
			pass  # "mista" e desconhecidas: baseline, sem efeito

# Efeito ESTRUTURAL (uma vez) da doutrina, aplicado no momento do takeover (jogador).
func _apply_economic_doctrine_once(n) -> void:
	if String(n.get_meta("economic_doctrine", "mista")) == "livre_mercado":
		n.corrupcao = clampf(n.corrupcao + 5.0, 0.0, 100.0)  # +5 corrupção (custo institucional)

# ─────────────────────────────────────────────────────────────────
# ROTATIVIDADE DE LIDERANÇA (Fase 2) — líder ruim cai, novo líder muda o rumo
# ─────────────────────────────────────────────────────────────────

# Turnos por ano de jogo — 1 turno = 1 MÊS (ritmo mensal), então 12 turnos/ano.
# Muitas janelas de liderança derivam desta constante.
const TURNS_PER_YEAR: int = 12
# Idade máxima antes de forçar sucessão (vida ~ até idade avançada).
const LEADER_MAX_AGE: int = 90
# Turnos de impopularidade extrema antes de uma democracia trocar de líder.
# ~4 anos de impopularidade sustentada — um mandato ruim inteiro, não uma má fase.
const LEADER_UNPOP_LIMIT: int = 48   # 4 anos × 12 meses
# Mandato mínimo: carência antes de o líder poder cair por impopularidade (~3 anos).
const LEADER_MIN_TENURE: int = 36    # 3 anos × 12 meses

func _is_autocracy(n) -> bool:
	var r: String = n.regime_politico
	return ("DITADURA" in r) or ("AUTORITARISMO" in r) or ("TEOCRACIA" in r) or ("COMUNISMO" in r) or ("MONARQUIA" in r)

# ─────────────────────────────────────────────────────────────────
# AFINIDADE IDEOLÓGICA (#7) — nações de ideologia afim se atraem, opostas repelem.
# Faz emergir blocos geopolíticos informais (democracias de mercado vs autocracias
# planejadas — o eixo Ocidente × Rússia/China). Combina 2 eixos estruturados:
#   1) ideologia ECONÔMICA (livre_mercado…planejada), posicionada numa reta 0..1
#   2) REGIME (democracia vs autocracia)
# Retorna afinidade em [-1, +1]: +1 = muito afim, -1 = polos opostos.
# ─────────────────────────────────────────────────────────────────

# Posição de cada doutrina no eixo mercado(0) ↔ planejamento(1).
const _ECON_AXIS := {
	"livre_mercado": 0.0,
	"mista": 0.4,
	"nordica": 0.6,
	"planejada": 1.0,
}

func _econ_axis_of(n) -> float:
	return float(_ECON_AXIS.get(_doctrine_for(n), 0.4))

func _ideological_affinity(a, b) -> float:
	# Eixo econômico: distância na reta (0 = idênticos → +1; 1 = polos → -1)
	var econ_dist: float = absf(_econ_axis_of(a) - _econ_axis_of(b))  # 0..1
	var econ_aff: float = 1.0 - 2.0 * econ_dist                       # +1..-1
	# Eixo de regime: mesmo tipo (ambos democracia ou ambos autocracia) atrai
	var regime_aff: float = 1.0 if (_is_autocracy(a) == _is_autocracy(b)) else -1.0
	# Combina (econômico pesa mais que o regime)
	return clampf(econ_aff * 0.6 + regime_aff * 0.4, -1.0, 1.0)

# Puxa devagar as relações de `n` na direção da afinidade ideológica. Roda quando a
# nação age no cursor da IA (~a cada 2 anos). Só mexe em pares JÁ conhecidos (com
# relação registrada — semeados no início ou por eventos/diplomacia) para custo baixo
# e foco. Cada passo é pequeno; o efeito emerge por composição ao longo do século.
func _drift_ideological_relations(n) -> void:
	if n.relacoes.is_empty():
		return
	for other_code in n.relacoes.keys():
		if not nations.has(other_code):
			continue
		var other = nations[other_code]
		# Não mexe em relações "travadas" por guerra (guerra domina o sinal)
		if other_code in n.em_guerra:
			continue
		var aff: float = _ideological_affinity(n, other)
		# Alvo de longo prazo: afinidade máxima → +50, mínima → -50 (blocos, não guerra)
		var alvo: float = aff * 50.0
		var atual: float = float(n.relacoes[other_code])
		# Passo rumo ao alvo (8% do gap por ativação ≈ a cada 2 anos). Forte o bastante
		# para consolidar blocos coerentes com a ideologia ATUAL apesar da rotatividade
		# de líderes, mas gradual (blocos levam décadas para se formar/desfazer).
		var novo: float = atual + (alvo - atual) * 0.08
		n.relacoes[other_code] = clampf(novo, -100.0, 100.0)

# Roda 1×/turno por nação (exceto o jogador — o líder do jogador é ele mesmo).
# Decide se o líder atual cai (por eleição perdida, impopularidade, morte ou golpe)
# e, se cair, empossa um sucessor de ideologia possivelmente diferente.
func _process_leadership(n) -> void:
	if n == player_nation:
		return
	# Inicializa o líder na primeira passagem
	if n.lider_nome == "":
		n.lider_nome = _leader_name_for(n)
		n.lider_desde_turno = current_turn
		# Sincroniza a ideologia econômica com a personalidade inicial (o campo do save
		# guardava o REGIME, não a doutrina — normaliza para exibir/dirigir a economia).
		var personalities0: Dictionary = personalities_data.get("personalities", {})
		var pers0: Dictionary = personalities0.get(n.personalidade, {})
		n.ideologia_dominante = String(pers0.get("ideologia_economica", "mista"))
	# Envelhece o líder (idade +1 por ano de jogo)
	if current_turn > 0 and current_turn % TURNS_PER_YEAR == 0:
		n.lider_idade += 1
	# Conta impopularidade prolongada
	if n.apoio_popular < 30.0:
		n.turnos_impopular += 1
	else:
		n.turnos_impopular = 0
	# ── Gatilhos de queda (raros e significativos — mandatos, não porta-giratória) ──
	var motivo: String = ""
	var tenure: int = current_turn - n.lider_desde_turno
	# 1. Morte natural (vale para TODOS, inclusive ditadores — Rússia-like).
	#    Probabilidades ÷3 vs. trimestral (rodam 3× mais por ano no ritmo mensal).
	if n.lider_idade >= LEADER_MAX_AGE and randf() < 0.02:
		motivo = "morte"
	elif n.lider_idade >= 78 and randf() < 0.0013:
		motivo = "morte"  # chance pequena de morte após 78
	# 2. Golpe/revolução: estabilidade MUITO baixa e sustentada (vale para todos, raro)
	elif n.estabilidade_politica < 12.0 and randf() < 0.01:
		motivo = "golpe"
	# 3. Democracia: perde por impopularidade prolongada após cumprir mandato mínimo
	#    (autocracia NÃO cai por impopularidade — só morte/golpe).
	elif not _is_autocracy(n) and tenure >= LEADER_MIN_TENURE and n.turnos_impopular >= LEADER_UNPOP_LIMIT:
		motivo = "eleicao"
	if motivo != "":
		_succeed_leader(n, motivo)

# Empossa um novo líder, possivelmente de ideologia diferente → o país muda de rumo.
func _succeed_leader(n, motivo: String) -> void:
	var ideo_antiga: String = n.ideologia_dominante
	# Golpe/revolução pode inverter o regime; eleição/morte mantém o regime.
	if motivo == "golpe" and randf() < 0.5:
		n.regime_politico = "DITADURA_MILITAR" if not _is_autocracy(n) else "DEMOCRACIA"
	# Sorteia um novo arquétipo de personalidade (com viés a MUDAR de ideologia)
	var novo_pers: String = _pick_successor_personality(n)
	n.personalidade = novo_pers
	var personalities: Dictionary = personalities_data.get("personalities", {})
	var pers: Dictionary = personalities.get(novo_pers, {})
	n.ideologia_dominante = String(pers.get("ideologia_economica", "mista"))
	# Reset do líder
	n.lider_nome = _leader_name_for(n)
	n.lider_idade = randi_range(45, 65)
	n.lider_desde_turno = current_turn
	n.turnos_impopular = 0
	n.lideres_passados += 1
	# Golpe abala; eleição/sucessão pacífica dá fôlego
	match motivo:
		"golpe":
			n.estabilidade_politica = clampf(n.estabilidade_politica - 8.0, 0.0, 100.0)
			n.apoio_popular = clampf(n.apoio_popular + 10.0, 0.0, 100.0)  # "lua de mel" do novo regime
		"eleicao":
			n.apoio_popular = clampf(n.apoio_popular + 15.0, 0.0, 100.0)
			n.estabilidade_politica = clampf(n.estabilidade_politica + 5.0, 0.0, 100.0)
		"morte":
			n.estabilidade_politica = clampf(n.estabilidade_politica - 3.0, 0.0, 100.0)
	# Notícia (escopo conforme relevância do país)
	var mudou_ideo: bool = n.ideologia_dominante != ideo_antiga
	# Só noticia trocas RELEVANTES (senão 194 nações poluem o feed): grandes potências,
	# nações do continente do jogador, ou qualquer golpe (sempre dramático).
	var relevante: bool = (motivo == "golpe") \
		or (n.pib_bilhoes_usd >= _world_max_pib * 0.15) \
		or (player_nation != null and n.continente == player_nation.continente)
	if relevante:
		var verbo: String = String({"golpe": "toma o poder em um golpe", "eleicao": "vence as eleições", "morte": "assume após a morte do antecessor"}.get(motivo, "assume"))
		var rumo: String = (" — o país vira para %s" % _ideo_label(n.ideologia_dominante)) if mudou_ideo else ""
		_log_news({
			"type": "lideranca",
			"headline": "🎙 %s: %s %s%s" % [n.nome, n.lider_nome, verbo, rumo],
			"body": "Nova liderança em %s. Ideologia econômica: %s." % [n.nome, _ideo_label(n.ideologia_dominante)],
			"involves_player": false,
			"color": Color(1, 0.8, 0.3) if motivo != "golpe" else Color(1, 0.4, 0.3),
		}, [n.codigo_iso], n.continente)

# Sorteia um arquétipo sucessor. Viés: 60% de chance de MUDAR a ideologia econômica
# (o país muda de rumo); 40% mantém continuidade ideológica.
func _pick_successor_personality(n) -> String:
	var personalities: Dictionary = personalities_data.get("personalities", {})
	if personalities.is_empty():
		return n.personalidade
	var ideo_atual: String = n.ideologia_dominante
	var candidatos: Array = personalities.keys()
	var quer_mudar: bool = randf() < 0.6
	var filtrados: Array = []
	for pid in candidatos:
		var pi: String = String(personalities[pid].get("ideologia_economica", "mista"))
		if quer_mudar and pi != ideo_atual:
			filtrados.append(pid)
		elif not quer_mudar and pi == ideo_atual:
			filtrados.append(pid)
	if filtrados.is_empty():
		filtrados = candidatos
	return String(filtrados[randi() % filtrados.size()])

func _ideo_label(ideo: String) -> String:
	return {"livre_mercado": "livre mercado", "planejada": "economia planejada",
		"nordica": "modelo nórdico", "mista": "economia mista"}.get(ideo, ideo)

# Gera um nome de líder procedural (sobrenome regional simples). Determinístico o
# suficiente para variar entre nações sem depender de tabelas gigantes.
func _leader_name_for(n) -> String:
	var titulos := ["Pres.", "Chanceler", "PM", "Líder"]
	var t: String = titulos[randi() % titulos.size()]
	return "%s %s" % [t, _random_surname(n)]

func _random_surname(n) -> String:
	var nomes := ["Silva", "Kane", "Moretti", "Adler", "Novak", "Reyes", "Haddad",
		"Okoro", "Tanaka", "Ilić", "Andersson", "Costa", "Volkov", "Mensah",
		"Larsen", "Farah", "Petrov", "Duarte", "Nasser", "Weber"]
	return nomes[randi() % nomes.size()]

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
	elif current_turn % 15 == 0:
		# Provocação periódica do rival declarado (a cada ~15 meses)
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

# COALIZÃO DE CONTENÇÃO (#9): quando o jogador domina o mundo, as outras grandes
# potências se unem para conter sua hegemonia (balancing realista — ninguém quer um
# hegemon absoluto). Ativa quando o jogador é #1 E muito mais forte que o #2. As
# rivais esfriam relações com o jogador e se aproximam entre si (bloco anti-hegemonia).
var _containment_active: bool = false

func _process_containment_coalition() -> void:
	if player_nation == null:
		return
	# Só reage a partir do meio do jogo (turno ~120 = ~2010) e a cada 6 meses
	if current_turn < 120 or current_turn % 6 != 0:
		return
	# O jogador é hegemon? #1 de poder E ≥1,6× o poder do #2 entre os grandes.
	var my_score: float = compute_power_score(player_nation)
	var maiores: Array = []
	for code in nations.keys():
		if code == player_nation.codigo_iso:
			continue
		if nations[code].pib_bilhoes_usd >= 500.0:
			maiores.append(code)
	if maiores.size() < 3:
		return
	maiores.sort_custom(func(a, b): return compute_power_score(nations[a]) > compute_power_score(nations[b]))
	var segundo_score: float = compute_power_score(nations[maiores[0]])
	var hegemon: bool = my_score > segundo_score * 1.6 and get_power_rank(player_nation.codigo_iso) == 1
	if not hegemon:
		if _containment_active:
			_containment_active = false  # perdeu o status; coalizão se dissolve
		return
	# Ativa/mantém a coalizão: as 5 maiores rivais formam o bloco de contenção
	var coalizao: Array = maiores.slice(0, mini(5, maiores.size()))
	if not _containment_active:
		_containment_active = true
		_log_news({
			"type": "coalizao",
			"headline": "🌐 Coalizão de contenção se forma contra %s" % player_nation.nome,
			"body": "As grandes potências, alarmadas com o poder de %s, cerram fileiras para conter sua hegemonia." % player_nation.nome,
			"involves_player": true,
			"color": Color(1, 0.5, 0.3),
		}, [player_nation.codigo_iso], "")
	# Efeito por ativação: rivais esfriam com o jogador e se aproximam entre si
	for i in coalizao.size():
		var ri = nations[coalizao[i]]
		ri.relacoes[player_nation.codigo_iso] = clampf(float(ri.relacoes.get(player_nation.codigo_iso, 0)) - 4.0, -100.0, 100.0)
		player_nation.relacoes[coalizao[i]] = clampf(float(player_nation.relacoes.get(coalizao[i], 0)) - 4.0, -100.0, 100.0)
		for j in range(i + 1, coalizao.size()):
			var rj = nations[coalizao[j]]
			ri.relacoes[coalizao[j]] = clampf(float(ri.relacoes.get(coalizao[j], 0)) + 3.0, -100.0, 100.0)
			rj.relacoes[coalizao[i]] = clampf(float(rj.relacoes.get(coalizao[i], 0)) + 3.0, -100.0, 100.0)

# ─────────────────────────────────────────────────────────────────
# IA — nações NPCs decidem ações por turno
# ─────────────────────────────────────────────────────────────────

var _ai_cursor: int = 0

func _run_ai_turn() -> void:
	# Fase 3: cursor ROTATIVO em vez de amostra aleatória — garante que TODAS as
	# nações ajam periodicamente (antes 8 aleatórias/turno = cada nação agia 1× a cada
	# ~24 turnos/6 anos; o mundo ficava passivo). Com ai_speed=24, todas agem a cada
	# ~8 turnos (2 anos). Determinístico e justo, sem custo de shuffle.
	var codes: Array = nations.keys()
	var total: int = codes.size()
	if total <= 1:
		return
	var max_actors: int = settings.get("ai_speed", 24)
	var acted: int = 0
	var checked: int = 0
	while acted < max_actors and checked < total:
		var code: String = String(codes[_ai_cursor % total])
		_ai_cursor = (_ai_cursor + 1) % total
		checked += 1
		if code == player_nation.codigo_iso:
			continue
		_ai_decide(nations[code])
		acted += 1

func _ai_decide(n) -> void:
	# Drift de relações por afinidade ideológica (#7): sempre que a nação age, suas
	# relações caminham devagar na direção da afinidade — afins se aproximam, opostos
	# se afastam. Compostas ao longo do século, fazem blocos geopolíticos EMERGIREM.
	_drift_ideological_relations(n)
	var aggro: float = _get_aggression(n)
	var treasury: float = n.tesouro
	var stab: float = n.estabilidade_politica

	# 0. GABINETE — nações com folga investem P&D (sobem níveis + abrem trilhas).
	# Verba modesta p/ não desbalancear as finanças da IA; foco em educação/casa civil.
	if n.ministerios != null and treasury >= 120.0 and stab >= 45.0:
		var rd_base: float = n.pib_bilhoes_usd * 0.006
		if float(n.ministerios["educacao"].get("verba", 0.0)) <= 0.0:
			n.ministerios["educacao"]["verba"] = rd_base
			n.ministerios["casa_civil"]["verba"] = rd_base * 0.7
			n.ministerios["fazenda"]["verba"] = rd_base * 0.6

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

	# 3. PESQUISA — nações com folga desenvolvem tecnologia em trilhas paralelas
	# (sem isto o jogador monopolizava o eixo tecnológico do ranking de poder).
	# Preenche uma trilha ociosa até o limite de slots do país.
	var slots_ia: int = n.research_slots() if n.has_method("research_slots") else 2
	if tech != null and n.pesquisa_por_ministerio.size() < slots_ia and n.tesouro >= 60.0 and randf() < 0.35:
		var avail: Array = tech.get_available_techs(n)
		if not avail.is_empty():
			# Escolhe a que mais DESTRAVA a árvore numa pasta livre (não a mais barata)
			var ocupadas: Dictionary = {}
			for p in n.pesquisa_por_ministerio:
				ocupadas[p] = true
			var best: Dictionary = {}
			var best_sc: float = -1.0
			for t in avail:
				if ocupadas.has(tech.ministry_of(t)):
					continue
				var sc: float = 1.0 + int(tech.unlock_count.get(String(t.get("id", "")), 0)) * 3.0 + int(t.get("tier", 1)) * 1.5
				sc += 30.0 / max(1.0, float(t.get("custo", 50)))
				if sc > best_sc:
					best_sc = sc
					best = t
			if not best.is_empty():
				tech.start_research(n, String(best.get("id", "")))
				return

	# 4. AÇÃO TÁTICA ponderada pela PERSONALIDADE (Fase 3): a escolha reflete o
	# arquétipo do líder — agressivo investe em militar, tecnocrata em educação,
	# diplomata em relações, etc. Usa pesos_acao do personalities.json (antes um
	# 50/50 fixo entre felicidade e apoio, ignorando a personalidade).
	if treasury >= 20.0 and randf() < 0.4:
		treasury -= 20.0
		n.tesouro = treasury
		var mult: float = n.get_action_multiplier()
		_apply_personality_action(n, _pick_personality_action(n), mult)

func _get_aggression(n) -> float:
	var pers_id: String = n.personalidade
	var personalities: Dictionary = personalities_data.get("personalities", {})
	if personalities.has(pers_id):
		return float(personalities[pers_id].get("agressividade", 0.5))
	return 0.5

# Escolhe uma ação tática ponderada pelos pesos_acao da personalidade do líder.
# Retorna uma categoria: "bem_estar" | "apoio" | "educacao" | "infra" | "militar" | "relacoes".
func _pick_personality_action(n) -> String:
	var personalities: Dictionary = personalities_data.get("personalities", {})
	var pesos: Dictionary = personalities.get(n.personalidade, {}).get("pesos_acao", {})
	# Mapeia categorias de ação tática para os pesos do JSON (soma de pesos relacionados).
	var opcoes := {
		"educacao": float(pesos.get("investir_educacao", 1.0)),
		"bem_estar": float(pesos.get("investir_saude", 1.0)),
		"infra": float(pesos.get("invest_infra", 1.0)),
		"militar": float(pesos.get("mobilizar", 0.0)) + float(pesos.get("recrutar_tanques", 0.0)) + float(pesos.get("recrutar_avioes", 0.0)),
		"relacoes": float(pesos.get("melhorar_relacoes", 1.0)),
		"apoio": float(pesos.get("reforma_politica", 1.0)),
	}
	# Soma total e sorteio ponderado
	var total: float = 0.0
	for k in opcoes:
		total += maxf(0.0, opcoes[k])
	if total <= 0.0:
		return "apoio"
	var r: float = randf() * total
	var acc: float = 0.0
	for k in opcoes:
		acc += maxf(0.0, opcoes[k])
		if r <= acc:
			return k
	return "apoio"

# Aplica o efeito da ação tática escolhida. Efeitos modestos (é 1 de várias ações/turno).
func _apply_personality_action(n, categoria: String, mult: float) -> void:
	match categoria:
		"educacao":
			n.velocidade_pesquisa = minf(3.0, n.velocidade_pesquisa + 0.02 * mult)
			n.felicidade = minf(100.0, n.felicidade + 2.0 * mult)
		"bem_estar":
			n.felicidade = minf(100.0, n.felicidade + 4.0 * mult)
			n.apoio_popular = minf(100.0, n.apoio_popular + 2.0 * mult)
		"infra":
			n.pib_bilhoes_usd *= (1.0 + 0.003 * mult)
			n.estabilidade_politica = minf(100.0, n.estabilidade_politica + 1.0 * mult)
		"militar":
			if n.militar != null:
				n.militar["poder_militar_global"] = float(n.militar.get("poder_militar_global", 0.0)) + 3.0 * mult
		"relacoes":
			# Melhora relação com o vizinho mais próximo (aliado potencial)
			for c in n.relacoes:
				if c != n.codigo_iso and nations.has(c) and nations[c].continente == n.continente:
					n.relacoes[c] = clampf(float(n.relacoes[c]) + 4.0 * mult, -100.0, 100.0)
					break
		_:  # "apoio"
			n.apoio_popular = minf(100.0, n.apoio_popular + 10.0 * mult)

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

# ─────────────────────────────────────────────────────────────────
# BLOCOS GEOPOLÍTICOS (#11) — OTAN, BRICS, ASEAN… (data/alliances.json)
# Os blocos já existiam como dados (defesa coletiva); agora ganham vida:
# relações intra-bloco altas, bônus de membro por turno, e o jogador entra/sai.
# ─────────────────────────────────────────────────────────────────

# Retorna a lista de dicts de aliança das quais `code` é membro.
func _alliances_of(code: String) -> Array:
	var out: Array = []
	for alliance in alliances_data:
		if code in alliance.get("membros", []):
			out.append(alliance)
	return out

# Membros do mesmo bloco começam como aliados (relação alta). Faz OTAN/BRICS/etc.
# serem blocos coesos desde 2000, sobre a base ideológica já semeada.
func _seed_bloc_relations() -> void:
	for alliance in alliances_data:
		var members: Array = alliance.get("membros", [])
		# Defesa coletiva = laço mais forte (+45); blocos econômicos/soft = +25
		var laco: float = 45.0 if alliance.get("artigo_defesa", false) else 25.0
		for i in members.size():
			var a_code: String = String(members[i])
			if not nations.has(a_code):
				continue
			for j in range(i + 1, members.size()):
				var b_code: String = String(members[j])
				if not nations.has(b_code):
					continue
				# Reforça (não sobrescreve) — soma ao valor ideológico já semeado, com cap
				var na = nations[a_code]
				var nb = nations[b_code]
				na.relacoes[b_code] = clampf(maxf(float(na.relacoes.get(b_code, 0)), laco), -100.0, 100.0)
				nb.relacoes[a_code] = clampf(maxf(float(nb.relacoes.get(a_code, 0)), laco), -100.0, 100.0)

# Aplica os bônus de ser membro de bloco(s), 1×/turno. Defesa coletiva reduz custo
# militar e dá poder de defesa; blocos econômicos dão um leve empurrão de PIB/comércio.
func _process_bloc_benefits() -> void:
	# Itera POR BLOCO (12) × membros — bem mais barato que por nação × todos os blocos.
	for alliance in alliances_data:
		var membros: Array = alliance.get("membros", [])
		var defesa: bool = alliance.get("artigo_defesa", false)
		var econ: bool = alliance.get("bonus_membro", {}).get("bonus_comercio", false) or String(alliance.get("tipo", "")) == "economico"
		if not defesa and not econ:
			continue
		for code in membros:
			if not nations.has(code):
				continue
			var n = nations[code]
			if defesa:
				n.estabilidade_politica = minf(100.0, n.estabilidade_politica + 0.05)  # segurança coletiva
			if econ:
				n.pib_bilhoes_usd *= 1.0002  # livre comércio interno

# Blocos abertos ao jogador entrar (por afinidade): precisa de relação média positiva
# com os membros. Retorna a lista de blocos elegíveis (para a UI).
func player_eligible_blocs() -> Array:
	if player_nation == null:
		return []
	var out: Array = []
	for alliance in alliances_data:
		var members: Array = alliance.get("membros", [])
		if player_nation.codigo_iso in members:
			continue
		# Média de relação com os membros presentes
		var soma: float = 0.0
		var cont: int = 0
		for m in members:
			if nations.has(m):
				soma += float(player_nation.relacoes.get(m, 0))
				cont += 1
		if cont > 0 and soma / cont >= 20.0:  # bem-quisto pelo bloco
			out.append(alliance)
	return out

# Jogador entra num bloco (consome 1 ação). Custa relações com blocos rivais.
func player_join_bloc(bloc_id: String) -> Dictionary:
	if player_nation == null:
		return {"ok": false, "reason": "Sem nação"}
	var alvo: Dictionary = {}
	for a in alliances_data:
		if String(a.get("id", "")) == bloc_id:
			alvo = a
			break
	if alvo.is_empty():
		return {"ok": false, "reason": "Bloco inexistente"}
	if player_nation.codigo_iso in alvo.get("membros", []):
		return {"ok": false, "reason": "Já é membro"}
	if not _consume_action():
		return {"ok": false, "reason": "Sem ações neste turno"}
	alvo["membros"].append(player_nation.codigo_iso)
	# Relação sobe com os novos aliados
	for m in alvo.get("membros", []):
		if m != player_nation.codigo_iso and nations.has(m):
			player_nation.relacoes[m] = clampf(float(player_nation.relacoes.get(m, 0)) + 20, -100, 100)
			nations[m].relacoes[player_nation.codigo_iso] = clampf(float(nations[m].relacoes.get(player_nation.codigo_iso, 0)) + 20, -100, 100)
	_log_news({
		"type": "diplomacia",
		"headline": "🤝 %s adere ao bloco %s" % [player_nation.nome, alvo.get("nome", bloc_id)],
		"body": "Um novo alinhamento geopolítico. Segurança coletiva e cooperação com os membros.",
		"involves_player": true,
		"color": Color(0.4, 0.85, 1),
	}, [player_nation.codigo_iso], player_nation.continente)
	return {"ok": true, "bloc": alvo.get("nome", bloc_id)}

# Jogador sai de um bloco (consome 1 ação). Penaliza relações com ex-aliados.
func player_leave_bloc(bloc_id: String) -> Dictionary:
	if player_nation == null:
		return {"ok": false, "reason": "Sem nação"}
	var alvo: Dictionary = {}
	for a in alliances_data:
		if String(a.get("id", "")) == bloc_id:
			alvo = a
			break
	if alvo.is_empty() or not (player_nation.codigo_iso in alvo.get("membros", [])):
		return {"ok": false, "reason": "Não é membro"}
	if not _consume_action():
		return {"ok": false, "reason": "Sem ações neste turno"}
	alvo["membros"].erase(player_nation.codigo_iso)
	var pen: float = float(alvo.get("penalidade_saida", {}).get("relacoes_membros", -30))
	for m in alvo.get("membros", []):
		if nations.has(m):
			player_nation.relacoes[m] = clampf(float(player_nation.relacoes.get(m, 0)) + pen, -100, 100)
			nations[m].relacoes[player_nation.codigo_iso] = clampf(float(nations[m].relacoes.get(player_nation.codigo_iso, 0)) + pen, -100, 100)
	_log_news({
		"type": "diplomacia",
		"headline": "🚪 %s deixa o bloco %s" % [player_nation.nome, alvo.get("nome", bloc_id)],
		"body": "Rompimento diplomático. Os ex-aliados veem a saída como traição.",
		"involves_player": true,
		"color": Color(1, 0.5, 0.3),
	}, [player_nation.codigo_iso], player_nation.continente)
	return {"ok": true, "bloc": alvo.get("nome", bloc_id)}

# Defesa coletiva (Artigo 5): quando `defender_code` é atacado, os membros dos seus
# blocos de defesa podem entrar na guerra contra o agressor.
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
			if current_turn - int(_war_started[key]) >= WAR_FATIGUE_TURNS and randf() < 0.10:
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
					"headline": "🕊️ Armistício: %s e %s encerram guerra de %d anos" % [n.nome, nations[other].nome if nations.has(other) else other, (current_turn - 0) / 12],
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
	# OBJETIVO DE GUERRA (se o vencedor é o jogador e declarou por um motivo): amplifica
	# o espólio correspondente. Guerra "por algo" — não só um war score abstrato.
	var objetivo: String = String(_war_objectives.get(key, "conter"))
	_war_objectives.erase(key)
	var foco_reparacao: bool = objetivo == "reparacoes" and w_code == (player_nation.codigo_iso if player_nation else "")
	var foco_recurso: bool = objetivo == "recurso" and w_code == (player_nation.codigo_iso if player_nation else "")
	var foco_regime: bool = objetivo == "regime" and w_code == (player_nation.codigo_iso if player_nation else "")
	# Reparações: até 50% do tesouro do perdedor (70% se o objetivo era reparações)
	var frac_rep: float = 0.7 if foco_reparacao else 0.5
	var reparacao: float = clamp(loser.tesouro * frac_rep, 0.0, loser.pib_bilhoes_usd * (0.15 if foco_reparacao else 0.10))
	loser.tesouro = max(0.0, loser.tesouro - reparacao)
	winner.tesouro += reparacao
	# Concessão de recursos: o melhor recurso do perdedor muda de mãos (mais se o
	# objetivo era o recurso)
	var best_res: String = ""
	var best_val: float = 0.0
	for k in loser.recursos:
		if float(loser.recursos[k]) > best_val:
			best_val = float(loser.recursos[k])
			best_res = k
	var take: float = 0.0
	if best_res != "":
		take = min(30.0 if foco_recurso else 15.0, best_val * (0.45 if foco_recurso else 0.25))
		loser.recursos[best_res] = max(0.0, best_val - take)
		winner.recursos[best_res] = min(100.0, float(winner.recursos.get(best_res, 0)) + take)
	# Mudança de regime imposta pelo vencedor (objetivo "regime"): o perdedor vira um
	# regime alinhado ao vencedor e sofre instabilidade extra da imposição.
	if foco_regime:
		loser.regime_politico = winner.regime_politico
		loser.estabilidade_politica = clamp(loser.estabilidade_politica - 15.0, 0.0, 100.0)
		loser.set_meta("regime_imposto_por", w_code)
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
		# Custo proporcional ao PIB (com piso baixo pra países pequenos). Taxas /3
		# (ritmo mensal — mesmo custo anual de guerra).
		var cost_per_war: float = max(1.0, n.pib_bilhoes_usd * 0.00133)
		# Países pequenos (PIB < $200B) têm custo limitado a 0.5% do tesouro por guerra
		if n.pib_bilhoes_usd < 200.0:
			cost_per_war = min(cost_per_war, n.tesouro * 0.005)
		n.tesouro = max(0.0, n.tesouro - cost_per_war * wars)
		n.apoio_popular = max(0.0, n.apoio_popular - 0.5 * wars)
		n.felicidade = max(0.0, n.felicidade - 0.33 * wars)
		# CRISE HUMANITÁRIA: guerra do JOGADOR que se arrasta (>3 anos) gera refugiados
		# e desgaste crescente — o custo de uma guerra longa é assimétrico (vencer no
		# war score não significa vencer no longo prazo).
		if player_nation != null and code == player_nation.codigo_iso and current_turn % 12 == 0:
			var guerra_longa: bool = false
			for inimigo in n.em_guerra:
				var wk: String = _war_key(code, inimigo)
				if _war_started.has(wk) and current_turn - int(_war_started[wk]) >= 36:
					guerra_longa = true
					break
			if guerra_longa:
				n.felicidade = clamp(n.felicidade - 3.0, 0.0, 100.0)
				n.corrupcao = clamp(n.corrupcao + 1.0, 0.0, 100.0)  # economia de guerra
				_log_news({
					"type": "guerra",
					"headline": "🏚 Crise humanitária: guerra prolongada de %s gera refugiados" % n.nome,
					"body": "Anos de conflito cobram seu preço: deslocamento, fadiga popular e economia de guerra. Uma vitória tardia pode ser pírrica.",
					"involves_player": true,
					"color": Color(0.9, 0.5, 0.4),
				}, [code], n.continente)
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
	if randf() > 0.10:   # 30%/tri → 10%/mês (mesma frequência anual de eventos)
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
# Objetivos de guerra do jogador por conflito (key = _war_key). Define o que a vitória
# extrai: "reparacoes" (mais $), "recurso" (mais recurso), "regime" (muda o regime do
# perdedor + humilha), "conter" (padrão — espólio equilibrado).
var _war_objectives: Dictionary = {}

func player_declare_war(target_code: String, objetivo: String = "conter") -> bool:
	if player_nation == null or not nations.has(target_code):
		return false
	if target_code in player_nation.em_guerra:
		return false
	var cost: float = max(20.0, player_nation.pib_bilhoes_usd * 0.02)
	if player_nation.tesouro < cost:
		return false
	if not _consume_action(): return false
	player_nation.tesouro -= cost
	_war_objectives[_war_key(player_nation.codigo_iso, target_code)] = objetivo
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
func player_cancel_research(pasta: String = "") -> void:
	if tech and player_nation:
		tech.cancel_research(player_nation, pasta)

# ─────────────────────────────────────────────────────────────────
# GABINETE DE MINISTROS
# ─────────────────────────────────────────────────────────────────

# Aloca verba permanente de P&D a um ministério (acelera sua trilha + dá XP).
# NÃO consome ação — é ajuste orçamentário, feito livremente.
func player_alloc_rd(pasta: String, verba: float) -> Dictionary:
	var n = player_nation
	if n == null or not n.ministerios.has(pasta):
		return {"ok": false, "reason": "Ministério inválido"}
	verba = clampf(verba, 0.0, max(20.0, n.pib_bilhoes_usd * 0.03))
	n.ministerios[pasta]["verba"] = verba
	# Verba investida rende XP proporcional (uma vez por ajuste pra cima)
	if verba > 0:
		n.add_ministry_xp(pasta, verba * 0.4)
	return {"ok": true, "verba": verba}

# Player define o foco de pesquisa de um ministério (inicia a trilha da pasta).
func player_set_research_focus(tech_id: String) -> Dictionary:
	return player_start_research(tech_id)

# Snapshot do gabinete p/ a UI: cada pasta com nível, xp%, verba, trilha ativa.
func get_cabinet_snapshot() -> Array:
	var out: Array = []
	var n = player_nation
	if n == null:
		return out
	var trilhas: Dictionary = tech.get_all_research_progress(n) if tech != null else {}
	for pasta in n.MINISTERIOS:
		var d: Dictionary = n.ministerios.get(pasta, {})
		var nv: int = int(d.get("nivel", 1))
		var xp: float = float(d.get("xp", 0.0))
		var xp_atual: float = n.MIN_XP_LIMIARES[nv - 1]
		var xp_prox: float = n.MIN_XP_LIMIARES[nv] if nv < n.MIN_NIVEL_MAX else xp_atual
		var xp_pct: float = 100.0
		if nv < n.MIN_NIVEL_MAX and xp_prox > xp_atual:
			xp_pct = clampf((xp - xp_atual) / (xp_prox - xp_atual) * 100.0, 0, 100)
		var meta: Dictionary = MINISTRY_META.get(pasta, {})
		out.append({
			"pasta": pasta,
			"nome": meta.get("nome", pasta),
			"icon": meta.get("icon", "•"),
			"role": meta.get("role", "presidente"),
			"nivel": nv,
			"xp": xp,
			"xp_pct": xp_pct,
			"verba": float(d.get("verba", 0.0)),
			"pesquisa": trilhas.get(pasta, {}),
		})
	return out

# Sanções: jogador impõe sanção a uma nação alvo
# Custa $30B + 1 ação. Aplica -0.5% PIB/turno no alvo por 15 turnos (~1,25 ano).
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
		"body": "Custo $%dB. -0.5%% PIB/mês por %d meses. Relações em queda." % [SANCTION_COST, SANCTION_DURATION],
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
			# Cripto como moeda legal DRIBLA parte da sanção (efeito real, não só texto):
			# o alvo usa a WorldCoin para contornar o bloqueio → penalidade cai 60%.
			var penalty: float = SANCTION_PIB_PENALTY
			var alvo_com_cripto: bool = (player_nation != null and to_code == player_nation.codigo_iso and crypto_legal_tender)
			if alvo_com_cripto:
				penalty = 1.0 - (1.0 - SANCTION_PIB_PENALTY) * 0.4  # -60% da penalidade
			nations[to_code].apply_pib_multiplier(penalty)
		entry["turns_remaining"] = int(entry.get("turns_remaining", 0)) - 1
		if entry["turns_remaining"] > 0:
			still_active.append(entry)
	active_sanctions = still_active

# ─────────────────────────────────────────────────────────────────
# AÇÕES DE PAINEL — catálogo ÚNICO (fonte de verdade)
# GameOverlay (botões) e BotPlayer (IA espectador) chamam a MESMA API.
# Antes: efeitos duplicados na UI e no bot, com custos/valores divergentes.
# ─────────────────────────────────────────────────────────────────

# Cada ação tem "min" = pasta do gabinete que a executa (crédito de XP + escala por nível).
# 6 pastas: casa_civil, fazenda, seguranca, saude, educacao, exterior.
const PANEL_ACTIONS := {
	# ── CASA CIVIL (coordenação política — escala com nível da pasta) ──
	"propaganda":           {"panel": "governo",  "min": "casa_civil", "cost": 10,  "label": "📢 PROPAGANDA",        "desc": "Apoio +10%"},
	"combater_corrupcao":   {"panel": "governo",  "min": "casa_civil", "cost": 20,  "label": "⚖ ANTI-CORRUPÇÃO",    "desc": "Corrupção -15%"},
	"reforma_politica":     {"panel": "governo",  "min": "casa_civil", "cost": 30,  "label": "🏛 REFORMA POLÍTICA",  "desc": "Estab +12, Felic +5"},
	"investir_previdencia": {"panel": "governo",  "min": "casa_civil", "cost": 20,  "label": "👵 PREVIDÊNCIA",       "desc": "Apoio +3"},
	# ── FAZENDA (economia) ──
	"estimulo_fiscal":      {"panel": "economia", "min": "fazenda",    "cost": 80,  "label": "💰 ESTÍMULO FISCAL",   "desc": "PIB +2%, Felic +5"},
	"aperto_monetario":     {"panel": "economia", "min": "fazenda",    "cost": 30,  "label": "🏦 APERTO MONETÁRIO",  "desc": "Inflação -12, PIB -0.5%"},
	"infra_basica":         {"panel": "economia", "min": "fazenda",    "cost": 50,  "label": "🏗 INFRAESTRUTURA",      "desc": "PIB +1%"},
	"infra_megaprojeto":    {"panel": "economia", "min": "fazenda",    "cost": 100, "label": "🌉 MEGAPROJETO",         "desc": "PIB +2.5%, Estab -2"},
	"subsidios":            {"panel": "economia", "min": "fazenda",    "cost": 40,  "label": "💵 SUBSÍDIOS SETORIAIS", "desc": "PIB +1.5%, Corrup +3"},
	"explorar_recurso":     {"panel": "economia", "min": "fazenda",    "cost": 20,  "label": "⛏ EXPLORAR RECURSOS",   "desc": "Recurso escasso +15%"},
	# ── SAÚDE ──
	"investir_saude":       {"panel": "saude",    "min": "saude",      "cost": 20,  "label": "🏥 INVESTIR NO SUS",     "desc": "Felic +4, Apoio +2"},
	"campanha_vacinacao":   {"panel": "saude",    "min": "saude",      "cost": 30,  "label": "💉 CAMPANHA DE VACINAÇÃO","desc": "Felic +6, População +0.4%"},
	"construir_hospitais":  {"panel": "saude",    "min": "saude",      "cost": 45,  "label": "🏥 REDE HOSPITALAR",     "desc": "Felic +5, Estab +3"},
	# ── EDUCAÇÃO ──
	"investir_educacao":    {"panel": "educacao", "min": "educacao",   "cost": 20,  "label": "📚 INVESTIR NO ENSINO",  "desc": "Pesquisa +5%"},
	"universidades":        {"panel": "educacao", "min": "educacao",   "cost": 45,  "label": "🎓 UNIVERSIDADES",       "desc": "Pesquisa +8%, PIB +0.5%"},
	"bolsas_pesquisa":      {"panel": "educacao", "min": "educacao",   "cost": 35,  "label": "🔬 BOLSAS DE PESQUISA",  "desc": "Pesquisa +10%"},
	# ── JUSTIÇA & SEGURANÇA (segurança interna + defesa + guerra) ──
	"investir_seguranca":   {"panel": "seguranca","min": "seguranca",  "cost": 20,  "label": "👮 SEGURANÇA PÚBLICA",   "desc": "Estab +3, Corrup -2"},
	"reforma_judicial":     {"panel": "seguranca","min": "seguranca",  "cost": 35,  "label": "⚖ REFORMA JUDICIAL",    "desc": "Corrup -10, Estab +4"},
	"recrutar_infantaria":  {"panel": "seguranca","min": "seguranca",  "cost": 5,   "label": "🪖 RECRUTAR INFANTARIA", "desc": "+10.000 soldados"},
	"recrutar_tanques":     {"panel": "seguranca","min": "seguranca",  "cost": 15,  "label": "🛡 RECRUTAR TANQUES",    "desc": "+200 tanques"},
	"recrutar_avioes":      {"panel": "seguranca","min": "seguranca",  "cost": 25,  "label": "✈ RECRUTAR AVIÕES",     "desc": "+50 aviões"},
	"recrutar_navios":      {"panel": "seguranca","min": "seguranca",  "cost": 30,  "label": "⚓ RECRUTAR NAVIOS",     "desc": "+5 navios"},
	"construir_base":       {"panel": "seguranca","min": "seguranca",  "cost": 40,  "label": "🏗 CONSTRUIR BASE",      "desc": "Poder +10"},
	"aumentar_orcamento":   {"panel": "seguranca","min": "seguranca",  "cost": 20,  "label": "💰 +20% ORÇAMENTO MIL.", "desc": "Orçamento permanente +20%"},
}

# Categoria de tech (tech.json) → ministério dono da trilha de pesquisa.
const MINISTRY_OF_CATEGORY := {
	"SOCIAL": "saude", "DIGITAL": "educacao", "ESPACIAL": "casa_civil",
	"ENERGIA": "fazenda", "MILITAR": "seguranca",
}
# Cada tech pertence a UMA pasta do gabinete — trilhas equilibradas (~9-10 techs/pasta)
# para que a árvore inteira seja alcançável em 100 turnos com pesquisa paralela.
const MINISTRY_OF_TECH := {
	# DIGITAL
	"ciberseguranca_nacional": "seguranca",
	"computacao_quantica": "educacao",
	"constelacao_satelites": "casa_civil",
	"criptografia_pos_quantica": "educacao",
	"guerra_cibernetica": "seguranca",
	"ia_aplicada": "educacao",
	"ia_geral": "educacao",
	"ia_militar": "casa_civil",
	"internet_quantica": "educacao",
	"rede_5g": "educacao",
	"vigilancia_em_massa": "seguranca",
	# ENERGIA
	"armazenamento_grid": "fazenda",
	"bateria_estado_solido": "fazenda",
	"biocombustivel_avancado": "saude",
	"energia_solar_espacial": "fazenda",
	"eolica_offshore": "fazenda",
	"fusao_nuclear": "saude",
	"grade_inteligente": "fazenda",
	"hidroeletrica": "fazenda",
	"hidrogenio_verde": "fazenda",
	"reatores_smr": "fazenda",
	"solar_larga_escala": "fazenda",
	# ESPACIAL
	"asat": "exterior",
	"base_lunar": "casa_civil",
	"defesa_espacial": "exterior",
	"estacao_espacial": "casa_civil",
	"foguetes_lancamento": "casa_civil",
	"foguetes_reutilizaveis": "casa_civil",
	"gnss_proprio": "casa_civil",
	"mineracao_asteroidal": "exterior",
	"satelites_comunicacao": "casa_civil",
	"satelites_imageamento": "casa_civil",
	# MILITAR
	"armas_hipersonicas": "exterior",
	"artilharia_guiada": "seguranca",
	"caca_5a_geracao": "exterior",
	"defesa_antimissil": "seguranca",
	"drones_letais_autonomos": "seguranca",
	"drones_tatticos": "seguranca",
	"fragatas_multiissao": "exterior",
	"laser_alta_energia": "exterior",
	"misseis_cruzeiro": "seguranca",
	"sistema_antiaereo": "seguranca",
	"submarinos_ataque": "exterior",
	"superporta_avioes": "exterior",
	"tanques_3g": "seguranca",
	# SOCIAL
	"cidades_inteligentes": "saude",
	"colonizacao_espacial": "exterior",
	"economia_circular": "saude",
	"educacao_universal": "educacao",
	"genomica_precisao": "saude",
	"identidade_digital_soberana": "educacao",
	"medicina_regenerativa": "saude",
	"programa_espacial": "casa_civil",
	"prolongamento_vida": "saude",
	"saude_universal": "saude",
	"universidades_elite": "educacao",
	"vacinacao_em_massa": "saude",
}
# Labels e ícones das pastas p/ a UI.
const MINISTRY_META := {
	"casa_civil": {"nome": "Casa Civil",           "icon": "🏛", "role": "casa_civil"},
	"fazenda":    {"nome": "Fazenda",              "icon": "💰", "role": "economia"},
	"seguranca":  {"nome": "Justiça & Segurança",  "icon": "⚖", "role": "seguranca"},
	"saude":      {"nome": "Saúde",                "icon": "🏥", "role": "saude"},
	"educacao":   {"nome": "Educação",             "icon": "📚", "role": "educacao"},
	"exterior":   {"nome": "Relações Exteriores",  "icon": "🌐", "role": "chanceler"},
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
	# Credita XP ao ministério dono da ação (progressão do gabinete)
	var pasta: String = String(meta.get("min", ""))
	if pasta != "" and n.has_method("add_ministry_xp"):
		if n.add_ministry_xp(pasta, 25.0 + cost * 0.5):
			_log_news({
				"type": "gabinete",
				"headline": "📈 %s sobe para nível %d" % [MINISTRY_META.get(pasta, {}).get("nome", pasta), n.ministry_level(pasta)],
				"body": "Ministério mais forte: ações mais eficazes e novas pesquisas liberadas.",
				"involves_player": true,
				"color": Color(0.5, 0.9, 1),
			})
	return {"ok": true, "msg": msg, "cost": cost}

# Aplica o efeito da ação na nação. Mantém os valores calibrados
# que antes viviam em GameOverlay (governo escala com mult; militar/economia não).
func _apply_panel_action(n, action_id: String) -> String:
	# Multiplicador base × força do ministério dono (nível 1→5)
	var pasta: String = String(PANEL_ACTIONS.get(action_id, {}).get("min", ""))
	var mult: float = n.get_action_multiplier()
	if pasta != "" and n.has_method("ministry_action_mult"):
		mult *= n.ministry_action_mult(pasta)
	match action_id:
		# ── GOVERNO ──
		"propaganda":
			var v: float = 10.0 * mult
			n.apoio_popular = min(100.0, n.apoio_popular + v)
			return "Apoio +%d%%" % int(v)
		"combater_corrupcao":
			var v: float = 15.0 * mult
			n.corrupcao = max(0.0, n.corrupcao - v)
			# Combater corrupção restaura a confiança do investidor (sinal ao mercado)
			n.confianca_investidor = min(100.0, n.confianca_investidor + 4.0 * mult)
			return "Corrupção -%d%%, Confiança +%d" % [int(v), int(4.0 * mult)]
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
			n.velocidade_pesquisa = min(3.0, n.velocidade_pesquisa + 0.05 * mult)
			return "Pesquisa +%d%%" % int(5.0 * mult)
		# ── SAÚDE ──
		"campanha_vacinacao":
			_add_social_spend(n, "saude")
			var vf: float = 6.0 * mult
			n.felicidade = min(100.0, n.felicidade + vf)
			n.populacao = int(n.populacao * (1.0 + 0.004 * mult))
			return "Felic +%d, População +%.1f%%" % [int(vf), 0.4 * mult]
		"construir_hospitais":
			_add_social_spend(n, "saude")
			var vf2: float = 5.0 * mult
			var ve2: float = 3.0 * mult
			n.felicidade = min(100.0, n.felicidade + vf2)
			n.estabilidade_politica = min(100.0, n.estabilidade_politica + ve2)
			return "Felic +%d, Estab +%d" % [int(vf2), int(ve2)]
		# ── EDUCAÇÃO ──
		"universidades":
			_add_social_spend(n, "educacao")
			n.velocidade_pesquisa = min(3.0, n.velocidade_pesquisa + 0.08 * mult)
			n.apply_pib_multiplier(1.0 + 0.005 * mult)
			return "Pesquisa +%d%%, PIB +%.1f%%" % [int(8.0 * mult), 0.5 * mult]
		"bolsas_pesquisa":
			_add_social_spend(n, "educacao")
			n.velocidade_pesquisa = min(3.0, n.velocidade_pesquisa + 0.10 * mult)
			return "Pesquisa +%d%%" % int(10.0 * mult)
		# ── JUSTIÇA & SEGURANÇA ──
		"investir_seguranca":
			_add_social_spend(n, "seguranca")
			var ve: float = 3.0 * mult
			var vc: float = 2.0 * mult
			n.estabilidade_politica = min(100.0, n.estabilidade_politica + ve)
			n.corrupcao = max(0.0, n.corrupcao - vc)
			return "Estab +%d, Corrup -%d" % [int(ve), int(vc)]
		"reforma_judicial":
			var vcj: float = 10.0 * mult
			var vej: float = 4.0 * mult
			n.corrupcao = max(0.0, n.corrupcao - vcj)
			n.estabilidade_politica = min(100.0, n.estabilidade_politica + vej)
			# Segurança jurídica atrai investidores de volta (forte sinal institucional)
			n.confianca_investidor = min(100.0, n.confianca_investidor + 6.0 * mult)
			return "Corrup -%d, Estab +%d, Confiança +%d" % [int(vcj), int(vej), int(6.0 * mult)]
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
