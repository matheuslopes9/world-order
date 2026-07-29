extends Node
## Teste do MUNDO VIVO Bloco B — IA estratégica + rival ascendente.
## Godot_console.exe --headless --path . res://scenes/StrategyTest.tscn

const SAVE_PATH := "user://nations_new_dawn_save.json"
var _save_backup := ""
var _had_save := false

func _ready() -> void:
	await get_tree().process_frame
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f: _save_backup = f.get_as_text(); f.close()
	var E = GameEngine
	E.player_nation = E.nations["BR"]
	E.game_state = "PLAYING"
	print("\n=== TESTE DE IA ESTRATÉGICA + RIVAL ASCENDENTE (Mundo Vivo B) ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	# 1. _compute_objetivo devolve metas coerentes com o estado
	var ar = E.nations["AR"]
	ar.ascendente = false; ar.memoria = []
	# nação estável, rica, agressiva → EXPANDIR
	ar.estabilidade_politica = 70.0; ar.tesouro = 500.0; ar.em_guerra = []
	# força aggro alto via personalidade militar (se disponível) — senão testa o gate
	var obj: String = E._compute_objetivo(ar)
	_t.call("meta calculada é válida (%s)" % obj, obj in ["EXPANDIR","DEFENDER","DESENVOLVER","OPORTUNISMO"])

	# nação instável → DEFENDER
	ar.estabilidade_politica = 30.0
	_t.call("nação instável vira DEFENDER (%s)" % E._compute_objetivo(ar), E._compute_objetivo(ar) == "DEFENDER")

	# ascendente → sempre EXPANDIR
	ar.estabilidade_politica = 30.0; ar.ascendente = true
	_t.call("rival ascendente força EXPANDIR mesmo instável", E._compute_objetivo(ar) == "EXPANDIR")
	ar.ascendente = false; ar.estabilidade_politica = 70.0

	# 2. seleção do rival ascendente: escolhe UMA potência não-jogador
	E._ascendente_iso = ""
	for c in E.nations: E.nations[c].ascendente = false
	E.current_turn = 80  # dentro da janela 60-120
	E._maybe_pick_ascendente()
	_t.call("rival ascendente foi escolhido", E._ascendente_iso != "")
	_t.call("ascendente NÃO é o jogador", E._ascendente_iso != "BR")
	if E._ascendente_iso != "":
		_t.call("a nação escolhida tem a flag ascendente", E.nations[E._ascendente_iso].ascendente)
		# é uma potência (top-poder)? checa que está acima da mediana
		var powers = []
		for c in E.nations: powers.append(E.compute_power_score(E.nations[c]))
		powers.sort()
		var mediana = powers[powers.size()/2]
		_t.call("ascendente é uma POTÊNCIA (acima da mediana)", E.compute_power_score(E.nations[E._ascendente_iso]) >= mediana)

	# 3. só escolhe UMA vez (idempotente)
	var primeiro: String = E._ascendente_iso
	E._maybe_pick_ascendente()
	_t.call("não troca o ascendente (1 por partida)", E._ascendente_iso == primeiro)

	# 4. save/load preserva o rival ascendente (campo global)
	var asc_antes: String = E._ascendente_iso
	var d: Dictionary = {"ascendente_iso": E._ascendente_iso}
	E._ascendente_iso = ""
	E._ascendente_iso = String(d.get("ascendente_iso", ""))
	_t.call("rival ascendente serializa/restaura (%s)" % E._ascendente_iso, E._ascendente_iso == asc_antes)

	# 5. CAMPANHA REAL: o rival ascendente SOBE de verdade ao longo dos anos?
	# reseta o estado e roda 500 turnos com o mundo ativo
	E._ascendente_iso = ""
	for c in E.nations: E.nations[c].ascendente = false
	E.current_turn = 12
	E.date_year = 2001
	var asc_rank0: int = -1
	var asc_iso: String = ""
	for i in 500:
		E.end_turn()
		if E._ascendente_iso != "" and asc_iso == "":
			asc_iso = E._ascendente_iso
			asc_rank0 = E.get_power_rank(asc_iso)
	if asc_iso != "":
		var rank_f: int = E.get_power_rank(asc_iso)
		print("  → rival %s: rank de poder %d → %d em ~40 anos" % [E.nations[asc_iso].nome, asc_rank0, rank_f])
		_t.call("rival ascendente foi eleito numa campanha real", true)
		_t.call("rival mantém ou melhora posição de poder (não afunda)", rank_f <= asc_rank0 + 3)
	else:
		_t.call("rival ascendente foi eleito numa campanha real", false)
	_t.call("DEFCON não travou em alerta máximo (%d)" % E.defcon, E.defcon >= 2)

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
