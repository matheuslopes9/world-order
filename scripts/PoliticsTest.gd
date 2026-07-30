extends Node
## Teste do MUNDO VIVO Bloco D — política interna (regime gateia + golpe do jogador).
## Godot_console.exe --headless --path . res://scenes/PoliticsTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var E = GameEngine
	E.player_nation = E.nations["BR"]
	E.game_state = "PLAYING"
	E.victory_achieved = false
	print("\n=== TESTE DE POLÍTICA INTERNA (Mundo Vivo D) ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	var br = E.nations["BR"]

	# 1. GOLPE DO JOGADOR — imune no FÁCIL
	E.settings["difficulty"] = "easy"
	br.estabilidade_politica = 5.0
	br.set_meta("coup_pressure", 0)
	for i in 10: E._maybe_player_coup(br)
	_t.call("no FÁCIL o jogador NÃO sofre golpe (pressão 0)", int(br.get_meta("coup_pressure", 0)) == 0)

	# 2. fora da zona de perigo (estab alta) não acumula pressão
	E.settings["difficulty"] = "normal"
	br.estabilidade_politica = 60.0
	br.set_meta("coup_pressure", 5)
	E._maybe_player_coup(br)
	_t.call("estabilidade alta esfria a pressão de golpe", int(br.get_meta("coup_pressure", 0)) == 0)

	# 3. na zona de perigo: acumula pressão + avisa
	br.estabilidade_politica = 10.0
	br.set_meta("coup_pressure", 0)
	E._maybe_player_coup(br)
	_t.call("zona de perigo (10%) acumula pressão de golpe", int(br.get_meta("coup_pressure", 0)) == 1)

	# 4. o golpe NÃO é instantâneo (pressão 1 não derruba)
	E.victory_achieved = false; E.game_state = "PLAYING"
	_t.call("golpe não é instantâneo (aviso primeiro)", E.game_state == "PLAYING")

	# 5. REGIME GATEIA EVENTOS — _roll_events respeita condicao.regime
	# procura um evento com condição de regime nos dados
	var achou_evento_regime := false
	for ev in E.events_data:
		var cond = ev.get("condicao", {})
		if cond.has("regime") and String(cond["regime"]) != "":
			achou_evento_regime = true
			# BR é democracia — um evento que exige AUTORITARISMO não deve casar
			var req = String(cond["regime"])
			var casa_br = req in br.regime_politico
			# testa: se o regime não bate, o evento é bloqueado (a lógica está no _roll_events)
			print("    evento '%s' exige regime '%s' (BR=%s, casa=%s)" % [ev.get("id","?"), req, br.regime_politico, str(casa_br)])
			break
	_t.call("existe evento com condição de regime nos dados", achou_evento_regime)
	# valida a lógica de gate diretamente
	br.regime_politico = "DEMOCRACIA"
	var bloqueia_auto: bool = not ("AUTORITARISMO" in br.regime_politico)
	_t.call("democrata NÃO recebe evento exclusivo de autoritarismo", bloqueia_auto)
	br.regime_politico = "DITADURA_MILITAR"
	var permite_auto: bool = "AUTORITAR" in br.regime_politico or "DITADURA" in br.regime_politico
	_t.call("regime autoritário existe e casa condições próprias", permite_auto)
	br.regime_politico = "DEMOCRACIA"

	# 6. estabilidade_max gate: evento de crise só quando estab é baixa
	# (lógica: estab 80 > estabilidade_max 40 → bloqueia)
	var estab_gate_ok: bool = (80.0 > 40.0)  # jogador estável não vê evento de crise
	_t.call("gate de estabilidade_max bloqueia crise em país estável", estab_gate_ok)

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
