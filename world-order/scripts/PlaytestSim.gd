extends Node
## Simulação massiva: 195 nações × 50 turnos cada.
## Gera relatório consolidado de bugs, anomalias e padrões de gameplay.
## Roda: godot --headless res://scenes/PlaytestSim.tscn

const TURNS_PER_RUN: int = 50

# Estatísticas globais
var results: Array = []  # Dict por nação: code, nome, tier, outcome, métricas
var bugs_detected: Array = []  # Lista de strings descrevendo bugs

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run_massive_playtest()
	get_tree().quit()

func _run_massive_playtest() -> void:
	if GameEngine.nations.is_empty():
		await GameEngine.data_loaded

	var t_start := Time.get_ticks_msec()
	var codes: Array = GameEngine.nations.keys()
	var total: int = codes.size()
	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  PLAYTEST MASSIVO — %d nações × %d turnos = %d turnos simulados" % [total, TURNS_PER_RUN, total * TURNS_PER_RUN])
	print("╚═══════════════════════════════════════════════════════════════════════\n")

	# Cache de dados originais (pra reset entre runs)
	var nations_raw = GameEngine._load_json("res://data/nations.json")
	var ns_dict: Dictionary = nations_raw.get("nations", {})
	var n_script = preload("res://scripts/Nation.gd")

	var i: int = 0
	for code in codes:
		i += 1
		_simulate_one(code, ns_dict, n_script)
		if i % 25 == 0:
			print("[Progresso] %d/%d nações simuladas (%.1f%%)" % [i, total, 100.0 * i / total])

	var t_total := Time.get_ticks_msec() - t_start
	print("\n=== TEMPO TOTAL: %.1fs ===\n" % (t_total / 1000.0))

	_print_consolidated_report()

func _simulate_one(code: String, ns_dict: Dictionary, n_script) -> void:
	# Reset completo do GameEngine pra essa nação
	GameEngine.player_nation = null
	GameEngine.current_turn = 0
	GameEngine.date_quarter = 1
	GameEngine.date_year = 2024
	GameEngine.defcon = 5
	GameEngine.recent_events.clear()

	# Recria todas as nações do zero (importante: outras nações afetam pelo IA)
	GameEngine.nations.clear()
	for c in ns_dict:
		var n = n_script.new()
		var tier: String = GameEngine.difficulty_tiers.get(c, "")
		n.from_dict(ns_dict[c], c, tier)
		GameEngine.nations[c] = n

	if not GameEngine.nations.has(code):
		bugs_detected.append("Código %s não existe em nations.json" % code)
		return

	GameEngine.confirm_player_nation(code)
	var n = GameEngine.player_nation
	var initial_pib: float = float(n.pib_bilhoes_usd)
	var initial_tesouro: float = float(n.tesouro)
	var initial_estab: float = float(n.estabilidade_politica)

	var status: String = "?"
	var t_died: int = 0
	var actions_taken: int = 0
	var max_war_count: int = 0
	var min_treasury: float = n.tesouro
	var max_inflation: float = n.inflacao
	var max_debt: float = 0.0
	var ai_wars_observed: int = 0  # guerras IA contra outras nações

	for t in TURNS_PER_RUN:
		# Estratégia adaptativa: mais agressiva pra países instáveis
		var did_action: bool = _take_strategic_action(n)
		if did_action:
			actions_taken += 1

		# Detecta exceções dentro do end_turn
		var ok: bool = true
		# Não tem try/except em GDScript, mas vamos usar print pra debug
		GameEngine.end_turn()

		# Métricas
		max_war_count = max(max_war_count, n.em_guerra.size())
		min_treasury = min(min_treasury, n.tesouro)
		max_inflation = max(max_inflation, n.inflacao)
		max_debt = max(max_debt, n.divida_publica)
		ai_wars_observed += GameEngine.recent_events.size()

		# Verifica condições de derrota/vitória (lua de mel: 5 turnos)
		var honeymoon: bool = (t + 1) <= 5
		if status == "?":
			if n.apoio_popular < 20:
				n.revolucao_turnos += 1
				if not honeymoon and n.revolucao_turnos >= 3:
					status = "REVOLUCAO"
					t_died = t + 1
			else:
				n.revolucao_turnos = 0
			if n.tesouro <= 0:
				n.falencia_turnos += 1
				if not honeymoon and n.falencia_turnos >= 4:
					if status == "?":
						status = "FALENCIA"
						t_died = t + 1
			else:
				n.falencia_turnos = 0
			if not honeymoon and n.estabilidade_politica < 8 and status == "?":
				status = "GOLPE"
				t_died = t + 1
			if not honeymoon and n.inflacao > 80 and status == "?":
				status = "HIPERINFLACAO"
				t_died = t + 1

		# Detecta bugs numéricos
		if is_nan(n.pib_bilhoes_usd) or n.pib_bilhoes_usd < 0:
			bugs_detected.append("[%s] PIB inválido turno %d: %f" % [code, t+1, n.pib_bilhoes_usd])
			break
		if is_nan(n.tesouro) or is_nan(n.inflacao):
			bugs_detected.append("[%s] NaN detectado turno %d" % [code, t+1])
			break

	# Verifica vitória (só se sobreviveu)
	if status == "?":
		var win: bool = n.apoio_popular >= 65 and n.estabilidade_politica >= 65 and n.inflacao <= 15 and n.tesouro > 0
		if win:
			status = "VITORIA"
		else:
			status = "SOBREVIVEU"

	results.append({
		"code": code,
		"nome": n.nome,
		"tier": n.tier_dificuldade,
		"status": status,
		"t_died": t_died,
		"pib_inicial": initial_pib,
		"pib_final": n.pib_bilhoes_usd,
		"pib_growth": (n.pib_bilhoes_usd / initial_pib - 1.0) * 100.0,
		"tesouro_inicial": initial_tesouro,
		"tesouro_final": n.tesouro,
		"min_tesouro": min_treasury,
		"divida_max": max_debt,
		"max_inflacao": max_inflation,
		"max_guerras": max_war_count,
		"apoio_final": n.apoio_popular,
		"estab_final": n.estabilidade_politica,
		"acoes": actions_taken,
		"eventos_mundo": ai_wars_observed,
	})

# Estratégia adaptativa baseada em tier
func _take_strategic_action(n) -> bool:
	var ap: float = n.apoio_popular
	var st: float = n.estabilidade_politica
	var corr: float = n.corrupcao
	var fel: float = n.felicidade
	var tes: float = n.tesouro
	var infl: float = n.inflacao
	var mult: float = n.get_action_multiplier()
	var tier: String = n.tier_dificuldade

	# CRISE crítica (qualquer tier): apoio < 30, age agressivo
	if ap < 30 and tes >= 5:
		var cost: float = 5.0 if tes < 20 else 10.0
		var ganho: float = (5.0 if cost == 5.0 else 10.0) * mult
		tes -= cost; n.tesouro = tes
		n.apoio_popular = min(100.0, ap + ganho)
		return true
	if st < 25 and tes >= 20:
		tes -= 20; n.tesouro = tes
		n.estabilidade_politica = min(100.0, st + 3.0 * mult)
		n.corrupcao = max(0.0, corr - 2.0 * mult)
		return true
	if st < 35 and tes >= 30:
		tes -= 30; n.tesouro = tes
		n.estabilidade_politica = min(100.0, st + 12.0 * mult)
		n.felicidade = min(100.0, fel + 5.0 * mult)
		return true
	if corr > 50 and tes >= 20:
		tes -= 20; n.tesouro = tes
		n.corrupcao = max(0.0, corr - 15.0 * mult)
		return true
	if fel < 40 and tes >= 20:
		tes -= 20; n.tesouro = tes
		n.felicidade = min(100.0, fel + 4.0 * mult)
		n.apoio_popular = min(100.0, ap + 2.0 * mult)
		return true

	# OTIMIZAÇÃO (sobra dinheiro): ataca o pior indicador
	if tes >= 30:
		# Para países difíceis, prefere estabilidade/apoio
		if (tier == "QUASE_IMPOSSIVEL" or tier == "MUITO_DIFICIL") and st < 70 and tes >= 30:
			tes -= 30; n.tesouro = tes
			n.estabilidade_politica = min(100.0, st + 12.0 * mult)
			n.felicidade = min(100.0, fel + 5.0 * mult)
			return true
		if ap < 70:
			tes -= 10; n.tesouro = tes
			n.apoio_popular = min(100.0, ap + 10.0 * mult)
			return true
		if corr > 25:
			tes -= 20; n.tesouro = tes
			n.corrupcao = max(0.0, corr - 15.0 * mult)
			return true
		if fel < 90:
			tes -= 20; n.tesouro = tes
			n.felicidade = min(100.0, fel + 4.0 * mult)
			n.apoio_popular = min(100.0, ap + 2.0 * mult)
			return true
		# Investe em educação como tail
		tes -= 20; n.tesouro = tes
		n.felicidade = min(100.0, fel + 2.0 * mult)
		return true

	return false

# ─────────────────────────────────────────────────────────────────
# RELATÓRIO CONSOLIDADO
# ─────────────────────────────────────────────────────────────────

func _print_consolidated_report() -> void:
	var by_status: Dictionary = {}
	var by_tier: Dictionary = {}
	for r in results:
		var s: String = r["status"]
		var t: String = r["tier"]
		by_status[s] = by_status.get(s, 0) + 1
		if not by_tier.has(t):
			by_tier[t] = {"total": 0, "VITORIA": 0, "SOBREVIVEU": 0, "REVOLUCAO": 0, "FALENCIA": 0, "GOLPE": 0, "HIPERINFLACAO": 0}
		by_tier[t]["total"] += 1
		by_tier[t][s] = by_tier[t].get(s, 0) + 1

	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  RESULTADO GLOBAL — %d nações simuladas" % results.size())
	print("╚═══════════════════════════════════════════════════════════════════════")
	print("STATUS:")
	for s in ["VITORIA", "SOBREVIVEU", "REVOLUCAO", "FALENCIA", "GOLPE", "HIPERINFLACAO"]:
		var n: int = by_status.get(s, 0)
		var pct: float = 100.0 * n / results.size()
		print("  %s : %d (%.1f%%)" % [s.rpad(15), n, pct])

	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  POR TIER DE DIFICULDADE")
	print("╚═══════════════════════════════════════════════════════════════════════")
	for tier in ["FACIL", "NORMAL", "DIFICIL", "MUITO_DIFICIL", "QUASE_IMPOSSIVEL"]:
		if not by_tier.has(tier): continue
		var d: Dictionary = by_tier[tier]
		var total: int = d["total"]
		var vit: int = d.get("VITORIA", 0)
		var sob: int = d.get("SOBREVIVEU", 0)
		var rev: int = d.get("REVOLUCAO", 0)
		var fal: int = d.get("FALENCIA", 0)
		var gol: int = d.get("GOLPE", 0)
		var hip: int = d.get("HIPERINFLACAO", 0)
		print("%s [%d nações]" % [tier.rpad(20), total])
		print("  ✅ Vitória:        %3d (%5.1f%%)" % [vit, 100.0 * vit / total])
		print("  ⚖️ Sobreviveu:    %3d (%5.1f%%)" % [sob, 100.0 * sob / total])
		print("  💀 Revolução:     %3d (%5.1f%%)" % [rev, 100.0 * rev / total])
		print("  💀 Golpe:         %3d (%5.1f%%)" % [gol, 100.0 * gol / total])
		print("  💀 Falência:      %3d (%5.1f%%)" % [fal, 100.0 * fal / total])
		print("  💀 Hiperinflação: %3d (%5.1f%%)" % [hip, 100.0 * hip / total])

	# Anomalias econômicas
	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  ANOMALIAS ECONÔMICAS")
	print("╚═══════════════════════════════════════════════════════════════════════")
	var pib_runaway: Array = []   # PIB cresce > 200% em 50 turnos
	var pib_collapsed: Array = [] # PIB cai
	var debt_crisis: Array = []   # Dívida > 2× PIB
	var hyperinfl: Array = []     # Inflação > 50% pico
	var no_action: Array = []     # Quase nenhuma ação tomada
	for r in results:
		if r["pib_growth"] > 200: pib_runaway.append(r)
		if r["pib_growth"] < -10: pib_collapsed.append(r)
		if r["divida_max"] > r["pib_inicial"] * 2.0: debt_crisis.append(r)
		if r["max_inflacao"] > 50: hyperinfl.append(r)
		if r["acoes"] < 5: no_action.append(r)
	print("PIB cresceu mais que 200%% (%d nações):" % pib_runaway.size())
	for r in pib_runaway.slice(0, 5):
		print("  - %s [%s]: %.0f%% (PIB $%.0fB → $%.0fB)" % [r["nome"], r["tier"], r["pib_growth"], r["pib_inicial"], r["pib_final"]])
	print("PIB encolheu (%d nações):" % pib_collapsed.size())
	for r in pib_collapsed.slice(0, 5):
		print("  - %s [%s]: %.1f%%" % [r["nome"], r["tier"], r["pib_growth"]])
	print("Dívida > 2× PIB (%d nações):" % debt_crisis.size())
	for r in debt_crisis.slice(0, 5):
		print("  - %s: dívida $%.0fB | PIB $%.0fB | tesouro min $%.0fB" % [r["nome"], r["divida_max"], r["pib_inicial"], r["min_tesouro"]])
	print("Inflação > 50%% pico (%d nações):" % hyperinfl.size())
	for r in hyperinfl.slice(0, 5):
		print("  - %s [%s]: pico %.1f%%" % [r["nome"], r["tier"], r["max_inflacao"]])
	print("Quase sem ação (<5 ações em 50 turnos): %d nações" % no_action.size())
	for r in no_action.slice(0, 5):
		print("  - %s [%s]: %d ações | tesouro inicial $%.0fB" % [r["nome"], r["tier"], r["acoes"], r["tesouro_inicial"]])

	# Engagement de IA
	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  ATIVIDADE DA IA NO MUNDO")
	print("╚═══════════════════════════════════════════════════════════════════════")
	var avg_events: float = 0.0
	var total_events: int = 0
	var games_with_war: int = 0
	for r in results:
		total_events += r["eventos_mundo"]
		if r["max_guerras"] > 0:
			games_with_war += 1
	avg_events = float(total_events) / max(1, results.size())
	print("Eventos do mundo (média): %.1f por jogo de 50 turnos" % avg_events)
	print("Nações que entraram em guerra: %d (%.1f%%)" % [games_with_war, 100.0 * games_with_war / results.size()])

	# BUGS detectados
	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  BUGS DETECTADOS")
	print("╚═══════════════════════════════════════════════════════════════════════")
	if bugs_detected.is_empty():
		print("  Nenhum bug numérico (NaN, PIB negativo) detectado ✅")
	else:
		for b in bugs_detected.slice(0, 30):
			print("  ⚠ " + b)

	# Top 10 melhores e piores
	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  TOP 10 MELHORES (PIB final)")
	print("╚═══════════════════════════════════════════════════════════════════════")
	var sorted_pib := results.duplicate()
	sorted_pib.sort_custom(func(a, b): return a["pib_final"] > b["pib_final"])
	for r in sorted_pib.slice(0, 10):
		print("  %s [%s] $%.0fB → $%.0fB (%+.1f%%) | %s" %
			[r["nome"].rpad(25).substr(0,25), r["tier"].rpad(20).substr(0,20),
			 r["pib_inicial"], r["pib_final"], r["pib_growth"], r["status"]])

	print("\n╔═══════════════════════════════════════════════════════════════════════")
	print("║  TOP 10 PIORES (mortos cedo)")
	print("╚═══════════════════════════════════════════════════════════════════════")
	var died_early := results.filter(func(r): return r["t_died"] > 0).duplicate()
	died_early.sort_custom(func(a, b): return a["t_died"] < b["t_died"])
	for r in died_early.slice(0, 10):
		print("  %s [%s] turno %d | %s" %
			[r["nome"].rpad(25).substr(0,25), r["tier"].rpad(20).substr(0,20), r["t_died"], r["status"]])

	print("\n=== PLAYTEST CONCLUÍDO ===")
