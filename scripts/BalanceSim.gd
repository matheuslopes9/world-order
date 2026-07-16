extends Node
## BALANCE SIM — "joga o jogo" de ponta a ponta, headless.
##
## Roda campanhas COMPLETAS (2000 → 2100, ~400 turnos) para um cohort de
## nações representativas de todos os tiers, em dois modos:
##   ATIVO   — BotPlayer joga como um jogador humano engajado (mesma API/custos)
##   PASSIVO — governo inerte (nenhuma ação) — grupo de controle
##
## Mede: vitórias (e quando), derrotas (e causa), crescimento de PIB,
## RANKING GLOBAL (o país subiu? virou potência?), techs, tratados, guerras,
## conquistas desbloqueadas, comportamento do mundo (DEFCON, guerras da IA,
## potências emergentes) e anomalias numéricas.
##
## Rodar: Godot_v4.6.2-stable_win64_console.exe --headless --path . res://scenes/BalanceSim.tscn

# Cohort: cobre todos os tiers (tier real é lido em runtime)
const COHORT := ["US", "CN", "DE", "JP", "BR", "IN", "KR", "MX", "VN", "NG", "ET", "BO", "AF", "KP", "HT"]
const END_YEAR := 2100
const MAX_TURNS := 1320  # trava de segurança (ritmo mensal)

var ns_dict: Dictionary = {}
var results: Array = []
var anomalies: Array = []
var _backups: Dictionary = {}
const PROTECTED := ["user://achievements.json", "user://world_order_save.json", "user://meta_progression.json"]

# Estado da run corrente (preenchido por signals)
var _endgame_result: Dictionary = {}
var _modal_decisions: int = 0

func _ready() -> void:
	await get_tree().process_frame
	_backup_user_files()
	var raw = GameEngine._load_json("res://data/nations.json")
	ns_dict = raw.get("nations", {})
	# Conecta signals de nível-engine uma única vez
	GameEngine.player_event_triggered.connect(_on_player_event)
	GameEngine.endgame_reached.connect(_on_endgame)
	var t0 := Time.get_ticks_msec()
	print("\n╔════════════════════════════════════════════════════════════════════╗")
	print("║  BALANCE SIM — campanha completa 2000→2100 · %d nações × 2 modos   ║" % COHORT.size())
	print("╚════════════════════════════════════════════════════════════════════╝")
	for code in COHORT:
		if not ns_dict.has(code):
			print("⚠ %s não existe em nations.json — pulando" % code)
			continue
		for active in [true, false]:
			_run_campaign(code, active)
	print("\n[SIM] Tempo total: %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_print_report()
	_restore_user_files()
	get_tree().quit(0)

# ─────────────────────────────────────────────────────────────────
# RESET COMPLETO DO ENGINE (estado de "novo jogo" fiel)
# ─────────────────────────────────────────────────────────────────

func _reset_engine() -> void:
	var E = GameEngine
	E.player_nation = null
	E.current_turn = 0
	E.date_month = 1
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
	E.settings["difficulty"] = "normal"
	E.settings["mode"] = "inspirado"
	E.settings["scenario"] = "campanha"
	# Recria as 195 nações do zero
	E.nations.clear()
	var n_script = load("res://scripts/Nation.gd")
	for c in ns_dict:
		var n = n_script.new()
		var tier: String = E.difficulty_tiers.get(c, "")
		n.from_dict(ns_dict[c], c, tier)
		E.nations[c] = n
	E._apply_year_2000_overrides()
	# Recria managers com estado limpo (tratados, eventos disparados, arcs)
	E.diplomacy = load("res://scripts/DiplomacyManager.gd").new(E)
	E.tech = load("res://scripts/TechManager.gd").new(E)
	E.espionage = load("res://scripts/EspionageManager.gd").new(E)
	E.timeline = load("res://scripts/EventTimeline.gd").new(E)
	E.storylines = load("res://scripts/StorylineManager.gd").new(E)
	if E.achievements:
		E.achievements.unlocked = {}  # mede unlocks por run
	# Decisões de modal auto-resolvidas (primeira escolha — "neutra")
	E.timeline.historic_event_decision.connect(_on_historic_decision)
	E.storylines.storyline_triggered.connect(_on_storyline_event)
	_endgame_result = {}
	_modal_decisions = 0

# ─────────────────────────────────────────────────────────────────
# UMA CAMPANHA COMPLETA
# ─────────────────────────────────────────────────────────────────

func _run_campaign(code: String, active: bool) -> void:
	_reset_engine()
	var E = GameEngine
	E.confirm_player_nation(code)
	var n = E.player_nation
	var pib0: float = n.pib_bilhoes_usd
	var rank0: int = _pib_rank(code)
	var top10_start: Array = _top10_codes()

	var bot = load("res://scripts/BotPlayer.gd").new(E, get_tree(), "balanced")
	bot.verbose = false

	# Métricas acumuladas
	var outcome := "SOBREVIVEU"
	var outcome_turn := 0
	var victory_turn := 0
	var defcon_sum := 0.0
	var wars_player := 0
	var was_at_war_last := false
	var peak_pib_rank: int = rank0
	var actions_total := 0

	while E.date_year < END_YEAR and E.current_turn < MAX_TURNS:
		# ── Turno do "jogador" ──
		if active:
			var failed := 0
			while E.player_actions_remaining > 0:
				var best: Dictionary = bot._choose_best_action()
				if best.is_empty():
					break
				if bot._execute_action(best):
					actions_total += 1
					failed = 0
				else:
					failed += 1
					if failed >= 2:
						break
			bot._handle_pending_proposals()
		E.end_turn()
		# ── Métricas por turno ──
		defcon_sum += E.defcon
		var at_war: bool = not n.em_guerra.is_empty()
		if at_war and not was_at_war_last:
			wars_player += 1
		was_at_war_last = at_war
		if E.current_turn % 20 == 0:
			peak_pib_rank = min(peak_pib_rank, _pib_rank(code))
		# ── Anomalias ──
		if is_nan(n.pib_bilhoes_usd) or n.pib_bilhoes_usd <= 0:
			anomalies.append("[%s/%s] PIB inválido no turno %d: %f" % [code, "A" if active else "P", E.current_turn, n.pib_bilhoes_usd])
			break
		if is_nan(n.tesouro) or is_nan(n.inflacao):
			anomalies.append("[%s/%s] NaN no turno %d" % [code, "A" if active else "P", E.current_turn])
			break
		# ── Endgame ──
		if E.game_state == "ENDGAME":
			var vict: bool = bool(_endgame_result.get("victory", false))
			var ttl: String = String(_endgame_result.get("title", "DERROTA"))
			if vict and "HEGEMONIA" in ttl:
				# Hegemonia no meio da campanha → registra e continua até 2100
				if victory_turn == 0:
					victory_turn = E.current_turn
					outcome = "HEGEMONIA"
					outcome_turn = victory_turn
				E.resume_after_endgame()
			else:
				# Fim de campanha (POTÊNCIA/LEGADO) ou derrota
				if outcome != "HEGEMONIA":  # hegemonia anterior tem precedência no registro
					outcome = ttl.replace("💀 ", "").replace("🏛 ", "").replace("📜 ", "").replace("🏆 ", "")
					outcome_turn = E.current_turn
				break

	if outcome == "SOBREVIVEU" and victory_turn > 0:
		outcome = "HEGEMONIA"
		outcome_turn = victory_turn

	var turns_played: int = E.current_turn
	var rank_f: int = _pib_rank(code)
	var top10_end: Array = _top10_codes()
	var new_powers: Array = []
	for c in top10_end:
		if not (c in top10_start):
			new_powers.append(c)

	results.append({
		"code": code, "nome": n.nome, "tier": n.tier_dificuldade, "active": active,
		"outcome": outcome, "outcome_turn": outcome_turn, "turns": turns_played,
		"year_end": E.date_year,
		"pib0": pib0, "pib_f": n.pib_bilhoes_usd, "growth_x": n.pib_bilhoes_usd / max(1.0, pib0),
		"rank0": rank0, "rank_f": rank_f, "peak_rank": peak_pib_rank,
		"apoio_f": n.apoio_popular, "estab_f": n.estabilidade_politica,
		"inflacao_f": n.inflacao, "tesouro_f": n.tesouro, "divida_f": n.divida_publica,
		"techs": n.tecnologias_concluidas.size(),
		"treaties": _count_player_treaties(code),
		"wars": wars_player,
		"actions": actions_total,
		"decisions": _modal_decisions,
		"achievements": GameEngine.achievements.unlocked.keys() if GameEngine.achievements else [],
		"defcon_avg": defcon_sum / max(1, turns_played),
		"new_powers": new_powers,
	})
	var mode_str: String = "ATIVO  " if active else "PASSIVO"
	print("  %s %s [%s] %s%s → %s | PIB $%dB→$%dB (%.1fx) | rank %d→%d | techs %d | %s" % [
		code.rpad(3), mode_str, n.tier_dificuldade.substr(0, 6),
		outcome, (" t%d" % outcome_turn) if outcome_turn > 0 else "",
		"ano %d" % E.date_year,
		int(pib0), int(n.pib_bilhoes_usd), n.pib_bilhoes_usd / max(1.0, pib0),
		rank0, rank_f, n.tecnologias_concluidas.size(),
		"+".join(PackedStringArray(results[-1]["achievements"])) if results[-1]["achievements"].size() <= 4 else "%d achv" % results[-1]["achievements"].size()
	])

# ─────────────────────────────────────────────────────────────────
# AUTO-DECISÕES (modais que na UI esperariam o jogador)
# ─────────────────────────────────────────────────────────────────

func _on_historic_decision(ev: Dictionary) -> void:
	var choices: Array = ev.get("choices", [])
	if choices.is_empty(): return
	GameEngine.timeline.apply_choice_by_id(String(ev.get("id", "")), String(choices[0].get("id", "")))
	_modal_decisions += 1

func _on_storyline_event(storyline_id: String, ev: Dictionary) -> void:
	var choices: Array = ev.get("choices", [])
	if choices.is_empty(): return
	GameEngine.storylines.apply_storyline_choice(storyline_id, String(choices[0].get("id", "")))
	_modal_decisions += 1

func _on_player_event(ev: Dictionary) -> void:
	GameEngine.apply_event_choice(ev, 0)
	_modal_decisions += 1

func _on_endgame(result: Dictionary) -> void:
	_endgame_result = result

# ─────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────

func _pib_rank(code: String) -> int:
	var my_pib: float = GameEngine.nations[code].pib_bilhoes_usd
	var rank := 1
	for c in GameEngine.nations:
		if c != code and GameEngine.nations[c].pib_bilhoes_usd > my_pib:
			rank += 1
	return rank

func _top10_codes() -> Array:
	var arr: Array = []
	for c in GameEngine.nations:
		arr.append({"c": c, "p": GameEngine.nations[c].pib_bilhoes_usd})
	arr.sort_custom(func(a, b): return a["p"] > b["p"])
	var out: Array = []
	for i in mini(10, arr.size()):
		out.append(arr[i]["c"])
	return out

func _count_player_treaties(code: String) -> int:
	var count := 0
	if GameEngine.diplomacy:
		for t in GameEngine.diplomacy.treaties:
			if code in t.get("signatories", []):
				count += 1
	return count

# ─────────────────────────────────────────────────────────────────
# RELATÓRIO
# ─────────────────────────────────────────────────────────────────

func _print_report() -> void:
	print("\n╔════════════════════════════════════════════════════════════════════╗")
	print("║  RELATÓRIO CONSOLIDADO                                             ║")
	print("╚════════════════════════════════════════════════════════════════════╝")
	for active in [true, false]:
		var subset: Array = results.filter(func(r): return r["active"] == active)
		if subset.is_empty(): continue
		var win_types := ["HEGEMONIA", "POTÊNCIA DO SÉCULO", "VITORIA"]
		var neutral_types := ["SOBREVIVEU", "LEGADO DO SÉCULO"]
		var wins: int = subset.filter(func(r): return r["outcome"] in win_types).size()
		var survived: int = subset.filter(func(r): return r["outcome"] in neutral_types).size()
		var deaths: int = subset.size() - wins - survived
		var avg_growth := 0.0
		var avg_rank_delta := 0.0
		var avg_win_turn := 0.0
		var avg_techs := 0.0
		for r in subset:
			avg_growth += r["growth_x"]
			avg_rank_delta += r["rank0"] - r["rank_f"]
			avg_techs += r["techs"]
			if r["outcome"] in win_types: avg_win_turn += r["outcome_turn"]
		avg_growth /= subset.size()
		avg_rank_delta /= subset.size()
		avg_techs /= subset.size()
		if wins > 0: avg_win_turn /= wins
		print("\n── MODO %s (%d runs) ──" % ["ATIVO" if active else "PASSIVO", subset.size()])
		print("  Vitórias: %d | Fim neutro (legado/sobreviveu): %d | Derrotas: %d" % [wins, survived, deaths])
		if wins > 0: print("  Turno médio da vitória: %.0f (ano ~%d)" % [avg_win_turn, 2000 + int(avg_win_turn / 4)])
		print("  Crescimento médio de PIB: %.2fx em 100 anos" % avg_growth)
		print("  Subida média de ranking: %+.1f posições" % avg_rank_delta)
		print("  Techs médias pesquisadas: %.1f" % avg_techs)
		# Desfechos detalhados
		var causes: Dictionary = {}
		for r in subset:
			causes[r["outcome"]] = causes.get(r["outcome"], 0) + 1
		print("  Desfechos: %s" % str(causes))

	# Comparação ATIVO vs PASSIVO por nação (a pergunta central!)
	print("\n── ATIVO vs PASSIVO (efeito de jogar bem) ──")
	print("  %-4s %-7s | %-22s | %-22s | ΔPIB   Δrank" % ["", "tier", "ATIVO", "PASSIVO"])
	for code in COHORT:
		var a: Dictionary = {}
		var p: Dictionary = {}
		for r in results:
			if r["code"] == code and r["active"]: a = r
			elif r["code"] == code and not r["active"]: p = r
		if a.is_empty() or p.is_empty(): continue
		print("  %-4s %-7s | %-22s | %-22s | %.1fx→%.1fx  %d→%d" % [
			code, String(a["tier"]).substr(0, 7),
			"%s%s" % [a["outcome"].substr(0, 14), (" t%d" % a["outcome_turn"]) if a["outcome_turn"] > 0 else ""],
			"%s%s" % [p["outcome"].substr(0, 14), (" t%d" % p["outcome_turn"]) if p["outcome_turn"] > 0 else ""],
			p["growth_x"], a["growth_x"], a["rank0"], a["rank_f"]
		])

	# Potências emergentes (mundo IA)
	print("\n── MUNDO (IA) ──")
	var all_new_powers: Dictionary = {}
	var defcon_avg := 0.0
	for r in results:
		defcon_avg += r["defcon_avg"]
		for c in r["new_powers"]:
			all_new_powers[c] = all_new_powers.get(c, 0) + 1
	defcon_avg /= max(1, results.size())
	print("  DEFCON médio nas runs: %.2f" % defcon_avg)
	print("  Novos membros do top-10 PIB (frequência): %s" % (str(all_new_powers) if all_new_powers.size() > 0 else "NENHUM — ranking mundial congelado!"))

	# Conquistas
	print("\n── CONQUISTAS (frequência de unlock nas %d runs) ──" % results.size())
	var achv_freq: Dictionary = {}
	for r in results:
		for a_id in r["achievements"]:
			achv_freq[a_id] = achv_freq.get(a_id, 0) + 1
	var achv_keys: Array = achv_freq.keys()
	achv_keys.sort_custom(func(x, y): return achv_freq[x] > achv_freq[y])
	for k in achv_keys:
		print("  %-20s %d/%d runs" % [k, achv_freq[k], results.size()])
	# Conquistas NUNCA desbloqueadas
	if GameEngine.achievements:
		var never: Array = []
		for a in GameEngine.achievements.ACHIEVEMENTS:
			if not achv_freq.has(a["id"]): never.append(a["id"])
		print("  Nunca desbloqueadas: %s" % str(never))

	print("\n── ANOMALIAS ──")
	if anomalies.is_empty():
		print("  Nenhuma anomalia numérica ✅")
	else:
		for a in anomalies.slice(0, 20):
			print("  ⚠ %s" % a)

# ─────────────────────────────────────────────────────────────────

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
	print("[SIM] Arquivos user:// restaurados")
