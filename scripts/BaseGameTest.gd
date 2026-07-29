extends Node
## Teste: com a atualização MUNDO VIVO DESLIGADA, o jogo roda o comportamento BASE
## — nada do mundo vivo vaza. Godot_console.exe --headless res://scenes/BaseGameTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var E = GameEngine
	E.settings["mundo_vivo"] = false   # jogo BASE (a atualização desligada)
	E.player_nation = E.nations["BR"]
	E.game_state = "PLAYING"
	print("\n=== TESTE DO JOGO BASE (Mundo Vivo DESLIGADO) ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	# 1. memória NÃO é gravada com a flag off (declarar guerra não cria rancor)
	var ar = E.nations["AR"]
	ar.memoria = []
	E._remember_if_live(ar, "guerra_declarada", "BR")
	_t.call("memória NÃO grava no jogo base", ar.memoria.is_empty())

	# 2. reputação do jogador fica em 0 (não sobe)
	E.player_reputation = 0.0
	E._add_player_reputation(50.0)
	_t.call("reputação do jogador fica 0 no jogo base", E.player_reputation == 0.0)

	# 3. rival ascendente NÃO é escolhido
	E._ascendente_iso = ""
	for c in E.nations: E.nations[c].ascendente = false
	E.current_turn = 80
	E._maybe_pick_ascendente()
	_t.call("rival ascendente NÃO é escolhido no jogo base", E._ascendente_iso == "")

	# 4. golpe do jogador NÃO dispara (imune no base, mesmo com estab baixa)
	var br = E.nations["BR"]
	br.estabilidade_politica = 5.0
	br.set_meta("coup_pressure", 0)
	for i in 10: E._maybe_player_coup(br)
	_t.call("golpe do jogador NÃO acumula pressão no base", int(br.get_meta("coup_pressure", 0)) == 0)

	# 5. ocupação NÃO gera unrest (conquista é ganho líquido no base)
	if E._provinces_ready:
		var ar_provs: Array = E.provinces_of.get("AR", [])
		var pid: String = ""
		for pp in ar_provs:
			if not bool(E.provinces.get(pp, {}).get("is_capital", false)):
				pid = pp; break
		if pid != "":
			E.provinces[pid]["unrest"] = 0.0
			E.transfer_province(pid, "BR", "conquista")
			_t.call("ocupação NÃO gera unrest no jogo base", float(E.provinces[pid].get("unrest", 0)) == 0.0)
			# _process_occupation é no-op
			E.provinces[pid]["unrest"] = 99.0
			var owner_before: String = E.province_owner(pid)
			E._process_occupation()
			_t.call("_process_occupation é no-op no jogo base (não revolta)", E.province_owner(pid) == owner_before)

	# 6. o mundo ainda roda (o jogo base funciona) — avança turnos sem erro
	var t_ok := true
	for i in 20:
		E.end_turn()
	_t.call("jogo base avança turnos normalmente", E.current_turn > 80)

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
