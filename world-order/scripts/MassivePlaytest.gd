extends Node
## PLAYTEST MASSIVO — 20 partidas por nação × 195 nações = 3.900 partidas.
## Cada partida: 50 turnos, com limite de 3 ações/turno (FASE 7).
## Roda: godot --headless res://scenes/MassivePlaytest.tscn

const TURNS_PER_RUN: int = 50
const RUNS_PER_NATION: int = 5  # reduzido pra rebalanceamento rápido (era 20)
const EXPORT_JSON_PATH: String = "user://playtest_results.json"

# resultados[code] = { runs: [...], aggregates: {...} }
var stats_per_nation: Dictionary = {}
var bugs_detected: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run()
	get_tree().quit()

func _run() -> void:
	if GameEngine.nations.is_empty():
		await GameEngine.data_loaded

	var t_start := Time.get_ticks_msec()
	var codes: Array = GameEngine.nations.keys()
	codes.sort()
	var total_nations: int = codes.size()
	var total_runs: int = total_nations * RUNS_PER_NATION

	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  PLAYTEST MASSIVO — %d nações × %d partidas = %d partidas" % [total_nations, RUNS_PER_NATION, total_runs])
	print("║  Limite de ações: %d/turno (FASE 7)" % GameEngine.PLAYER_ACTIONS_PER_TURN)
	print("╚═══════════════════════════════════════════════════════════════════════\n")

	# Cache de dados originais
	var nations_raw = GameEngine._load_json("res://data/nations.json")
	var ns_dict: Dictionary = nations_raw.get("nations", {})
	var n_script = preload("res://scripts/Nation.gd")
	var ov_raw = GameEngine._load_json("res://data/nations_2000.json")
	var ov_dict: Dictionary = ov_raw.get("overrides", {})
	var ov_global: Dictionary = ov_raw.get("global_overrides", {})
	var ov_techs: Array = ov_raw.get("tech_universal_2000", [])

	var i: int = 0
	for code in codes:
		i += 1
		var runs: Array = []
		for r in RUNS_PER_NATION:
			runs.append(_simulate_one(code, ns_dict, n_script, ov_dict, ov_global, ov_techs, r))
		# Agrega
		stats_per_nation[code] = {
			"nome": GameEngine.nations[code].nome if GameEngine.nations.has(code) else code,
			"runs": runs,
			"aggregates": _aggregate(runs)
		}
		if i % 10 == 0:
			var pct: float = 100.0 * i / total_nations
			var elapsed_s: float = (Time.get_ticks_msec() - t_start) / 1000.0
			var eta_s: float = elapsed_s * (total_nations - i) / i if i > 0 else 0
			print("[Progresso] %d/%d nações | %.1f%% | %.0fs decorridos | ~%.0fs restantes" % [i, total_nations, pct, elapsed_s, eta_s])

	var t_total := Time.get_ticks_msec() - t_start
	print("\n=== TEMPO TOTAL: %.1fs ===" % (t_total / 1000.0))
	_print_report()

func _simulate_one(code: String, ns_dict: Dictionary, n_script, ov_dict: Dictionary, ov_global: Dictionary, ov_techs: Array, run_seed: int) -> Dictionary:
	# Reset GameEngine
	GameEngine.player_nation = null
	GameEngine.current_turn = 0
	GameEngine.date_quarter = 1
	GameEngine.date_year = 2000
	GameEngine.defcon = 5
	GameEngine.recent_events.clear()
	GameEngine.news_history.clear()
	if GameEngine.timeline:
		GameEngine.timeline.fired_event_ids.clear()
		GameEngine.timeline.decision_log.clear()
	GameEngine.player_actions_remaining = GameEngine.PLAYER_ACTIONS_PER_TURN

	# Recria nações com overrides 2000
	GameEngine.nations.clear()
	for c in ns_dict:
		var n = n_script.new()
		var tier: String = GameEngine.difficulty_tiers.get(c, "")
		n.from_dict(ns_dict[c], c, tier)
		GameEngine.nations[c] = n
	# Aplica overrides 2000
	var pib_scale: float = float(ov_global.get("pib_scale", 1.0))
	var tesouro_scale: float = float(ov_global.get("tesouro_scale", 1.0))
	for c in GameEngine.nations.keys():
		var n = GameEngine.nations[c]
		n.tecnologias_concluidas = ov_techs.duplicate()
		n.pesquisa_atual = null
		n.divida_publica = 0.0
		n.em_guerra = []
		n.relacoes = {}
		if ov_dict.has(c):
			var ov: Dictionary = ov_dict[c]
			for key in ov.keys():
				if key in ["lider_atual", "contexto"]: continue
				if key in n: n.set(key, ov[key])
		else:
			n.pib_bilhoes_usd *= pib_scale
			n.tesouro *= tesouro_scale

	if not GameEngine.nations.has(code):
		return {"status": "MISSING", "t_died": 0}

	GameEngine.confirm_player_nation(code)
	var nat = GameEngine.player_nation
	var initial_pib: float = float(nat.pib_bilhoes_usd)

	var status: String = "?"
	var t_died: int = 0
	var actions_used: int = 0
	var max_war_count: int = 0
	var min_treasury: float = nat.tesouro
	var max_inflation: float = nat.inflacao

	# Auto-resposta para decisões históricas (escolha 1 = caminho convergente)
	var conn := func(ev: Dictionary):
		var choices: Array = ev.get("choices", [])
		if choices.size() > 0:
			GameEngine.timeline.apply_choice_by_id(ev.get("id", ""), choices[0].get("id", ""))
	if GameEngine.timeline and GameEngine.timeline.has_signal("historic_event_decision"):
		# Limpa conexões anteriores e religa
		var sigs: Array = GameEngine.timeline.historic_event_decision.get_connections()
		for s in sigs:
			GameEngine.timeline.historic_event_decision.disconnect(s["callable"])
		GameEngine.timeline.historic_event_decision.connect(conn)

	for t in TURNS_PER_RUN:
		# Bot toma 0-3 ações por turno (respeita limite FASE 7)
		var actions_this_turn: int = randi_range(1, GameEngine.PLAYER_ACTIONS_PER_TURN)
		for _a in actions_this_turn:
			if not GameEngine.can_player_act(): break
			if _take_strategic_action(nat):
				actions_used += 1
		GameEngine.end_turn()
		# Métricas
		max_war_count = max(max_war_count, nat.em_guerra.size())
		min_treasury = min(min_treasury, nat.tesouro)
		max_inflation = max(max_inflation, nat.inflacao)
		# Vitória/Derrota
		var honeymoon: bool = (t + 1) <= 5
		if status == "?":
			if nat.apoio_popular < 20:
				nat.revolucao_turnos += 1
				if not honeymoon and nat.revolucao_turnos >= 3:
					status = "REVOLUCAO"; t_died = t + 1
			else: nat.revolucao_turnos = 0
			if nat.tesouro <= 0:
				nat.falencia_turnos += 1
				if not honeymoon and nat.falencia_turnos >= 4:
					if status == "?": status = "FALENCIA"; t_died = t + 1
			else: nat.falencia_turnos = 0
			if not honeymoon and nat.estabilidade_politica < 8 and status == "?":
				status = "GOLPE"; t_died = t + 1
			if not honeymoon and nat.inflacao > 80 and status == "?":
				status = "HIPERINFLACAO"; t_died = t + 1
		# Bugs numéricos
		if is_nan(nat.pib_bilhoes_usd) or nat.pib_bilhoes_usd < 0:
			bugs_detected.append("[%s/run%d] PIB inválido turno %d: %f" % [code, run_seed, t+1, nat.pib_bilhoes_usd])
			break

	if status == "?":
		var win: bool = nat.apoio_popular >= 65 and nat.estabilidade_politica >= 65 and nat.inflacao <= 15 and nat.tesouro > 0
		status = "VITORIA" if win else "SOBREVIVEU"

	return {
		"status": status,
		"t_died": t_died,
		"pib_growth_pct": (nat.pib_bilhoes_usd / initial_pib - 1.0) * 100.0 if initial_pib > 0 else 0.0,
		"actions_used": actions_used,
		"max_wars": max_war_count,
		"max_inflation": max_inflation,
		"final_estab": nat.estabilidade_politica,
		"final_apoio": nat.apoio_popular,
		"final_tesouro": nat.tesouro,
	}

func _aggregate(runs: Array) -> Dictionary:
	if runs.is_empty(): return {}
	var counts := {"VITORIA": 0, "SOBREVIVEU": 0, "REVOLUCAO": 0, "FALENCIA": 0, "GOLPE": 0, "HIPERINFLACAO": 0, "MISSING": 0}
	var pib_growths: Array = []
	var actions_used: Array = []
	for r in runs:
		var s: String = r.get("status", "?")
		counts[s] = counts.get(s, 0) + 1
		pib_growths.append(float(r.get("pib_growth_pct", 0.0)))
		actions_used.append(int(r.get("actions_used", 0)))
	var avg_pib: float = 0.0
	for v in pib_growths: avg_pib += v
	avg_pib /= max(1, pib_growths.size())
	var avg_acts: float = 0.0
	for v in actions_used: avg_acts += v
	avg_acts /= max(1, actions_used.size())
	var win_rate: float = 100.0 * counts.get("VITORIA", 0) / runs.size()
	var death_rate: float = 100.0 * (counts.get("REVOLUCAO", 0) + counts.get("FALENCIA", 0) + counts.get("GOLPE", 0) + counts.get("HIPERINFLACAO", 0)) / runs.size()
	return {
		"runs": runs.size(),
		"win_rate": win_rate,
		"death_rate": death_rate,
		"avg_pib_growth": avg_pib,
		"avg_actions": avg_acts,
		"counts": counts,
	}

# Mesma estratégia do PlaytestSim original (resumida)
func _take_strategic_action(n) -> bool:
	var ap: float = n.apoio_popular
	var st: float = n.estabilidade_politica
	var tes: float = n.tesouro
	var mult: float = n.get_action_multiplier()
	if ap < 30 and tes >= 10:
		tes -= 10; n.tesouro = tes
		n.apoio_popular = min(100.0, ap + 10.0 * mult)
		return true
	if st < 35 and tes >= 30:
		tes -= 30; n.tesouro = tes
		n.estabilidade_politica = min(100.0, st + 12.0 * mult)
		n.felicidade = min(100.0, n.felicidade + 5.0 * mult)
		return true
	if n.corrupcao > 50 and tes >= 20:
		tes -= 20; n.tesouro = tes
		n.corrupcao = max(0.0, n.corrupcao - 15.0 * mult)
		return true
	if n.inflacao > 12 and tes >= 30:
		tes -= 30; n.tesouro = tes
		n.inflacao = max(0.0, n.inflacao - 8.0 * mult)
		return true
	if tes >= 50:
		tes -= 50; n.tesouro = tes
		n.pib_bilhoes_usd *= 1.01
		return true
	return false

# ─────────────────────────────────────────────────────────────────
# RELATÓRIO CONSOLIDADO
# ─────────────────────────────────────────────────────────────────

func _print_report() -> void:
	# Agrupa por tier
	var by_tier := {"FACIL": [], "NORMAL": [], "DIFICIL": [], "MUITO_DIFICIL": [], "QUASE_IMPOSSIVEL": []}
	for code in stats_per_nation.keys():
		var nation_data: Dictionary = stats_per_nation[code]
		var tier: String = GameEngine.nations[code].tier_dificuldade if GameEngine.nations.has(code) else "NORMAL"
		if not by_tier.has(tier): by_tier[tier] = []
		by_tier[tier].append({"code": code, "data": nation_data})

	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  RESUMO POR TIER (%d partidas/nação)" % RUNS_PER_NATION)
	print("╚═══════════════════════════════════════════════════════════════════════")
	for tier in ["FACIL", "NORMAL", "DIFICIL", "MUITO_DIFICIL", "QUASE_IMPOSSIVEL"]:
		var nations: Array = by_tier.get(tier, [])
		if nations.is_empty(): continue
		var sum_win: float = 0.0
		var sum_death: float = 0.0
		var sum_pib: float = 0.0
		for entry in nations:
			var ag: Dictionary = entry["data"]["aggregates"]
			sum_win += float(ag.get("win_rate", 0.0))
			sum_death += float(ag.get("death_rate", 0.0))
			sum_pib += float(ag.get("avg_pib_growth", 0.0))
		var n: int = nations.size()
		print("%-18s [%3d nações]  Win: %5.1f%%  Death: %5.1f%%  PIB+%6.1f%%" % [tier, n, sum_win/n, sum_death/n, sum_pib/n])

	# Top 10 melhores e piores
	var ranked: Array = []
	for code in stats_per_nation.keys():
		var ag: Dictionary = stats_per_nation[code]["aggregates"]
		ranked.append({"code": code, "nome": stats_per_nation[code]["nome"], "win": float(ag.get("win_rate", 0.0)), "death": float(ag.get("death_rate", 0.0)), "pib": float(ag.get("avg_pib_growth", 0.0))})
	ranked.sort_custom(func(a, b): return a["win"] > b["win"])
	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  TOP 10 MAIS FÁCEIS")
	print("╚═══════════════════════════════════════════════════════════════════════")
	for i in min(10, ranked.size()):
		var e: Dictionary = ranked[i]
		print("  %s [%s]  Win %5.1f%%  Death %5.1f%%  PIB %+5.1f%%" % [e["nome"], e["code"], e["win"], e["death"], e["pib"]])
	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  TOP 10 MAIS DIFÍCEIS (menor win rate)")
	print("╚═══════════════════════════════════════════════════════════════════════")
	for i in range(min(10, ranked.size())):
		var idx: int = ranked.size() - 1 - i
		var e: Dictionary = ranked[idx]
		print("  %s [%s]  Win %5.1f%%  Death %5.1f%%  PIB %+5.1f%%" % [e["nome"], e["code"], e["win"], e["death"], e["pib"]])

	if bugs_detected.size() > 0:
		print("\n╔═══════════════════════════════════════════════════════════════════════")
		print("║  BUGS DETECTADOS: %d" % bugs_detected.size())
		print("╚═══════════════════════════════════════════════════════════════════════")
		for b in bugs_detected.slice(0, min(20, bugs_detected.size())):
			print("  - %s" % b)
	else:
		print("\n✅ Nenhum bug numérico detectado.")

	# Export JSON pra análise/recalibração
	_export_json()

func _export_json() -> void:
	var out: Dictionary = {}
	for code in stats_per_nation.keys():
		var nation_data: Dictionary = stats_per_nation[code]
		var ag: Dictionary = nation_data.get("aggregates", {})
		var tier: String = GameEngine.nations[code].tier_dificuldade if GameEngine.nations.has(code) else "NORMAL"
		out[code] = {
			"nome": nation_data.get("nome", code),
			"current_tier": tier,
			"win_rate": ag.get("win_rate", 0.0),
			"death_rate": ag.get("death_rate", 0.0),
			"avg_pib_growth": ag.get("avg_pib_growth", 0.0),
			"avg_actions": ag.get("avg_actions", 0.0),
		}
	var f := FileAccess.open(EXPORT_JSON_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("\n[EXPORT] Resultados salvos em: %s" % ProjectSettings.globalize_path(EXPORT_JSON_PATH))
