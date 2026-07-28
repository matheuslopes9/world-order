extends Node
## Teste: a HEGEMONIA é alcançável? Força uma nação a dominar e vê se o streak
## progride até a vitória (ou se a coalizão/gate a sabotam).
## Godot_console.exe --headless --path . res://scenes/HegemonyTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var E = GameEngine
	E.player_nation = E.nations["BR"]
	E.game_state = "PLAYING"
	E.current_turn = 350  # pós-2025 (gate exige >=300)

	var br = E.nations["BR"]
	# torna o BR dominante: maior PIB, militar e indicadores altos
	# (simula um jogador que jogou bem e chegou ao topo)
	var maior_pib := 0.0
	for c in E.nations:
		maior_pib = maxf(maior_pib, E.nations[c].pib_bilhoes_usd)
	br.pib_bilhoes_usd = maior_pib * 1.6   # claramente o #1
	br.militar["poder_militar_global"] = 9999.0
	br.apoio_popular = 80.0
	br.estabilidade_politica = 80.0
	br.tecnologias_concluidas = range(50)  # tech alta

	print("\n=== TESTE DE HEGEMONIA (BR forçado ao topo) ===")
	var rank := E.get_power_rank("BR")
	print("Rank de poder do BR após virar dominante: #%d" % rank)
	print("PIB do BR: $%dB | maior do mundo antes: $%dB (35%% = $%dB)" % [int(br.pib_bilhoes_usd), int(maior_pib), int(maior_pib*0.35)])

	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)
	_t.call("BR vira #1 de poder quando domina", rank == 1)

	# roda turnos e vê o streak crescer até a vitória
	var venceu := false
	var max_streak := 0
	for i in 80:
		E.evaluate_endgame()
		var s: int = int(br.get_meta("hegemony_streak", 0))
		max_streak = max(max_streak, s)
		if E.victory_achieved:
			venceu = true
			print("  → HEGEMONIA alcançada no turno %d (streak %d)" % [E.current_turn, s])
			break
		# mantém os indicadores altos (simula bom jogo contínuo)
		br.apoio_popular = maxf(br.apoio_popular, 70.0)
		br.estabilidade_politica = maxf(br.estabilidade_politica, 70.0)
		br.pib_bilhoes_usd = maxf(br.pib_bilhoes_usd, maior_pib * 1.5)
		E.current_turn += 1
	print("  streak máximo atingido: %d (precisa de 48)" % max_streak)
	_t.call("o streak de hegemonia PROGRIDE (não é sabotado)", max_streak >= 48 or venceu)
	_t.call("HEGEMONIA é alcançável jogando bem", venceu)

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
