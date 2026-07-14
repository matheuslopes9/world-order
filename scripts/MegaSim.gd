extends Node
## MEGA SIM — joga N campanhas completas (2000→2100) cobrindo TODAS as nações.
## Shardável para paralelismo: rode várias instâncias com args próprios:
##
##   Godot_console.exe --headless --path . res://scenes/MegaSim.tscn -- --shard=0 --shards=4 --games=250
##
## Cada shard cobre um subconjunto round-robin das 195 nações, ciclando as
## 4 personalidades do bot; a cada 10 jogos, 1 é PASSIVO (controle).
## Resultado: user://megasim_shard_N.json (parcial a cada 25 jogos).
##
## Métricas por jogo: desfecho + contexto de morte, economia (picos de
## inflação/dívida, mínimo de tesouro), guerras, mundo (DEFCON, guerras
## simultâneas), conquistas, backlog diplomático, anomalias e perf/turno.

var shard: int = 0
var shards: int = 1
var games: int = 250
var all_active: bool = false  # --active=1: desliga o controle passivo (teste de cobertura)

var ns_dict: Dictionary = {}
var results: Array = []
var _endgame_result: Dictionary = {}
var _decisions: int = 0

const PERSONAS := ["balanced", "economic", "military", "diplomat"]
const END_YEAR := 2100
const MAX_TURNS := 440

var _backups: Dictionary = {}
const PROTECTED := ["user://achievements.json", "user://world_order_save.json", "user://meta_progression.json"]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			match kv[0]:
				"--shard": shard = int(kv[1])
				"--shards": shards = int(kv[1])
				"--games": games = int(kv[1])
				"--active": all_active = int(kv[1]) == 1
	await get_tree().process_frame
	_backup_user_files()
	var raw = GameEngine._load_json("res://data/nations.json")
	ns_dict = raw.get("nations", {})
	GameEngine.player_event_triggered.connect(_on_player_event)
	GameEngine.endgame_reached.connect(_on_endgame)
	# Nações deste shard (round-robin sobre a lista ordenada)
	var codes: Array = ns_dict.keys()
	codes.sort()
	var my_codes: Array = []
	for i in codes.size():
		if i % shards == shard:
			my_codes.append(codes[i])
	print("[MEGA %d] %d jogos | %d nações neste shard" % [shard, games, my_codes.size()])
	var t0 := Time.get_ticks_msec()
	for g in games:
		var code: String = my_codes[g % my_codes.size()]
		var persona: String = PERSONAS[(g / my_codes.size()) % PERSONAS.size()]
		var passive: bool = false if all_active else (g % 10 == 9)
		_run_one(code, persona, passive)
		if (g + 1) % 20 == 0:
			_write_results()
			var dt: float = (Time.get_ticks_msec() - t0) / 1000.0
			print("[MEGA %d] %d/%d jogos (%.0fs, ~%.1fs/jogo)" % [shard, g + 1, games, dt, dt / (g + 1)])
	_write_results()
	_restore_user_files()
	print("[MEGA %d] CONCLUIDO em %.0fs" % [shard, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(0)

# ─────────────────────────────────────────────────────────────────

# Snapshot dos níveis de ministério ao fim do jogo (diagnóstico do gabinete).
func _snapshot_niveis(n) -> Dictionary:
	var out: Dictionary = {}
	if n.ministerios != null:
		for p in n.ministerios:
			out[p] = int(n.ministerios[p].get("nivel", 1))
	return out

func _reset_engine() -> void:
	var E = GameEngine
	E.player_nation = null
	E.current_turn = 0
	E.date_quarter = 1
	E.date_year = 2000
	E.defcon = 5
	E.game_state = "MENU"
	E.victory_achieved = false
	E._turns_since_war = 0
	E.player_nemesis = ""
	E.nemesis_declared = false
	E.recent_events.clear()
	E.news_history.clear()
	E.active_sanctions.clear()
	E.active_trades.clear()
	E.player_power_rank_history.clear()
	E.bailout_pending = {}
	E._last_bailout_turn = -999
	E.active_shock = {}
	E._last_shock_turn = 0
	E._last_corruption_event_turn = -99
	E._war_score.clear()
	E.settings["difficulty"] = "normal"
	E.settings["mode"] = "inspirado"
	E.settings["scenario"] = "campanha"
	E.nations.clear()
	var n_script = load("res://scripts/Nation.gd")
	for c in ns_dict:
		var n = n_script.new()
		var tier: String = E.difficulty_tiers.get(c, "")
		n.from_dict(ns_dict[c], c, tier)
		E.nations[c] = n
	E._apply_year_2000_overrides()
	E.diplomacy = load("res://scripts/DiplomacyManager.gd").new(E)
	E.tech = load("res://scripts/TechManager.gd").new(E)
	E.espionage = load("res://scripts/EspionageManager.gd").new(E)
	E.timeline = load("res://scripts/EventTimeline.gd").new(E)
	E.storylines = load("res://scripts/StorylineManager.gd").new(E)
	if E.achievements:
		E.achievements.unlocked = {}
	E.timeline.historic_event_decision.connect(_on_historic)
	E.storylines.storyline_triggered.connect(_on_storyline)
	_endgame_result = {}
	_decisions = 0

func _run_one(code: String, persona: String, passive: bool) -> void:
	_reset_engine()
	var E = GameEngine
	E.confirm_player_nation(code)
	var n = E.player_nation
	var pib0: float = n.pib_bilhoes_usd
	var rank0: int = _pib_rank(code)
	var bot = load("res://scripts/BotPlayer.gd").new(E, get_tree(), persona)
	bot.verbose = false

	var outcome := "SOBREVIVEU"
	var outcome_turn := 0
	var hegemonia_turn := 0
	var max_infl := 0.0
	var max_debt := 0.0
	var min_tes := 1e15
	var defcon_sum := 0.0
	var wars_player := 0
	var was_war := false
	var peak_world_wars := 0
	var anomaly := ""
	var death_ctx := {}
	var t_start := Time.get_ticks_msec()

	while E.date_year < END_YEAR and E.current_turn < MAX_TURNS:
		if not passive:
			# Gabinete: ajusta verba de P&D por persona (abre trilhas paralelas)
			bot._manage_ministry_budgets()
			var fails := 0
			while E.player_actions_remaining > 0:
				var best: Dictionary = bot._choose_best_action()
				if best.is_empty():
					break
				if bot._execute_action(best):
					fails = 0
				else:
					fails += 1
					if fails >= 2:
						break
			bot._handle_pending_proposals()
			# Resgate do FMI: jogador ativo aceita (sobrevivência)
			if not E.bailout_pending.is_empty():
				E.accept_bailout()
		E.end_turn()
		max_infl = max(max_infl, n.inflacao)
		max_debt = max(max_debt, n.divida_publica)
		min_tes = min(min_tes, n.tesouro)
		defcon_sum += E.defcon
		var at_war: bool = not n.em_guerra.is_empty()
		if at_war and not was_war:
			wars_player += 1
		was_war = at_war
		if E.current_turn % 10 == 0:
			var w := 0
			for c in E.nations:
				w += E.nations[c].em_guerra.size()
			@warning_ignore("integer_division")
			peak_world_wars = max(peak_world_wars, w / 2)
		# Anomalias numéricas
		if is_nan(n.pib_bilhoes_usd) or n.pib_bilhoes_usd <= 0.0 or is_nan(n.tesouro) or is_nan(n.inflacao):
			anomaly = "NaN/PIB<=0 no turno %d" % E.current_turn
			break
		if n.pib_bilhoes_usd > 1e8:
			anomaly = "PIB runaway no turno %d (%.2e)" % [E.current_turn, n.pib_bilhoes_usd]
			break
		if E.game_state == "ENDGAME":
			var ttl: String = String(_endgame_result.get("title", "?"))
			var vict: bool = bool(_endgame_result.get("victory", false))
			if vict and "HEGEMONIA" in ttl:
				if hegemonia_turn == 0:
					hegemonia_turn = E.current_turn
				E.resume_after_endgame()
			else:
				outcome = _clean_title(ttl)
				outcome_turn = E.current_turn
				if not vict and not ("LEGADO" in ttl):
					death_ctx = {
						"apoio": snappedf(n.apoio_popular, 0.1),
						"estab": snappedf(n.estabilidade_politica, 0.1),
						"tesouro": snappedf(n.tesouro, 0.1),
						"inflacao": snappedf(n.inflacao, 0.1),
						"divida": snappedf(n.divida_publica, 0.1),
						"guerras": n.em_guerra.size(),
					}
				break

	if outcome == "SOBREVIVEU" and hegemonia_turn > 0:
		outcome = "HEGEMONIA"
		outcome_turn = hegemonia_turn

	# Backlog diplomático (propostas paradas na fila do jogador — relevante p/ passivo)
	var backlog := 0
	if E.diplomacy:
		for p in E.diplomacy.proposals:
			if p.get("target", "") == code:
				backlog += 1

	results.append({
		"code": code, "tier": n.tier_dificuldade, "persona": persona, "passive": passive,
		"outcome": outcome, "turn": outcome_turn, "heg_turn": hegemonia_turn,
		"year": E.date_year, "turns": E.current_turn,
		"pib0": snappedf(pib0, 0.1), "pib_f": snappedf(n.pib_bilhoes_usd, 0.1),
		"growth_x": snappedf(n.pib_bilhoes_usd / max(1.0, pib0), 0.01),
		"rank0": rank0, "rank_f": _pib_rank(code),
		"power_rank_f": int(E.player_power_rank_history.back()) if E.player_power_rank_history.size() > 0 else 0,
		"techs": n.tecnologias_concluidas.size(),
		"min_niveis": _snapshot_niveis(n),
		"corrupcao_f": snappedf(n.corrupcao, 0.1),
		"confianca_f": snappedf(n.confianca_investidor, 0.1),
		"empresas_sairam": n.empresas_sairam,
		"desviado": snappedf(n.tesouro_desviado_total, 0.1),
		"treaties": _count_treaties(code),
		"wars": wars_player,
		"decisions": _decisions,
		"achv": GameEngine.achievements.unlocked.size() if GameEngine.achievements else 0,
		"max_infl": snappedf(max_infl, 0.1), "max_debt": snappedf(max_debt, 0.1),
		"min_tes": snappedf(min_tes, 0.1),
		"defcon_avg": snappedf(defcon_sum / max(1, E.current_turn), 0.01),
		"peak_world_wars": peak_world_wars,
		"backlog": backlog,
		"anomaly": anomaly,
		"death_ctx": death_ctx,
		"ms_turn": snappedf(float(Time.get_ticks_msec() - t_start) / max(1, E.current_turn), 0.1),
	})

func _clean_title(t: String) -> String:
	return t.replace("💀 ", "").replace("🏛 ", "").replace("📜 ", "").replace("🏆 ", "")

# ─────────────────────────────────────────────────────────────────

func _on_historic(ev: Dictionary) -> void:
	var choices: Array = ev.get("choices", [])
	if choices.is_empty(): return
	GameEngine.timeline.apply_choice_by_id(String(ev.get("id", "")), String(choices[0].get("id", "")))
	_decisions += 1

func _on_storyline(storyline_id: String, ev: Dictionary) -> void:
	var choices: Array = ev.get("choices", [])
	if choices.is_empty(): return
	GameEngine.storylines.apply_storyline_choice(storyline_id, String(choices[0].get("id", "")))
	_decisions += 1

func _on_player_event(ev: Dictionary) -> void:
	GameEngine.apply_event_choice(ev, 0)
	_decisions += 1

func _on_endgame(result: Dictionary) -> void:
	_endgame_result = result

func _pib_rank(code: String) -> int:
	var my: float = GameEngine.nations[code].pib_bilhoes_usd
	var rank := 1
	for c in GameEngine.nations:
		if c != code and GameEngine.nations[c].pib_bilhoes_usd > my:
			rank += 1
	return rank

func _count_treaties(code: String) -> int:
	var count := 0
	if GameEngine.diplomacy:
		for t in GameEngine.diplomacy.treaties:
			if code in t.get("signatories", []):
				count += 1
	return count

func _write_results() -> void:
	var f := FileAccess.open("user://megasim_shard_%d.json" % shard, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"shard": shard, "games": results.size(), "results": results}))
		f.close()

func _backup_user_files() -> void:
	for path in PROTECTED:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			_backups[path] = f.get_buffer(f.get_length())
			f.close()
		else:
			_backups[path] = null

func _restore_user_files() -> void:
	for path in PROTECTED:
		var data = _backups.get(path)
		if data == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(data)
				f.close()
