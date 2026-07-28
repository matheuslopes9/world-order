extends Node
## Teste de DENSIDADE DE EVENTOS: roda uma campanha 2025-2100 e conta quantas
## DECISÕES modais o jogador veria — mede se o "deserto do meio do século" acabou.
## Roda: Godot_console.exe --headless --path . res://scenes/EventDensityTest.tscn

const SAVE_PATH := "user://world_order_save.json"
var _save_backup := ""
var _had_save := false

func _ready() -> void:
	await get_tree().process_frame
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f: _save_backup = f.get_as_text(); f.close()

	var E = GameEngine
	# escolhe um jogador qualquer (Brasil) e avança até 2100 contando decisões
	E.player_nation = E.nations["BR"]
	var decisions_by_decade := {}
	if E.timeline and E.timeline.has_signal("historic_event_decision"):
		E.timeline.historic_event_decision.connect(func(ev):
			var yr: int = E.date_year
			var dec: int = (yr / 10) * 10
			decisions_by_decade[dec] = int(decisions_by_decade.get(dec, 0)) + 1)

	print("\n=== TESTE DE DENSIDADE DE EVENTOS (2025-2100) ===")
	# posiciona a campanha em 2025 e roda ~900 turnos (75 anos × 12 meses)
	E.date_year = 2025
	E.date_month = 1
	E.current_turn = 300
	var t0 := Time.get_ticks_msec()
	for i in 900:
		if E.timeline:
			E.timeline.process_turn()
		# avança o calendário manualmente (sem rodar end_turn completo — foco nos eventos)
		E.date_month += 1
		if E.date_month > 12:
			E.date_month = 1
			E.date_year += 1
		E.current_turn += 1
		if E.date_year > 2100:
			break
	var ms := Time.get_ticks_msec() - t0

	var total_decisions := 0
	for k in decisions_by_decade:
		total_decisions += int(decisions_by_decade[k])
	print("Decisões modais disparadas ao jogador: %d em 75 anos" % total_decisions)
	print("Por década:")
	var empty_decades := 0
	for decada in range(2020, 2100, 10):
		var c: int = int(decisions_by_decade.get(decada, 0))
		if decada >= 2030 and decada <= 2090 and c == 0:
			empty_decades += 1
		print("  %ds: %d decisões" % [decada, c])
	print("Décadas VAZIAS (2030-2090): %d" % empty_decades)
	print("(processado em %d ms)" % ms)

	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)
	# o objetivo: NENHUMA década de 2030-2090 completamente vazia + volume decente
	_t.call("nenhuma década 2030-2090 é deserto de decisões", empty_decades == 0)
	_t.call("volume saudável de decisões no século (>=8)", total_decisions >= 8)

	if _had_save:
		var fw := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if fw: fw.store_string(_save_backup); fw.close()

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
