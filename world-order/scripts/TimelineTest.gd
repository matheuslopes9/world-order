extends Node
## Teste FASE 6: simula 400 turnos (100 anos: 2000→2100) e conta tipos de eventos
## que dispararam — âncora histórica + secundários + megatrends.

func _ready() -> void:
	print("\n══════════════════════════════════════════════")
	print("  TESTE FASE 6 — Campanha completa 100 anos")
	print("══════════════════════════════════════════════")
	await get_tree().process_frame
	GameEngine.confirm_player_nation("BR")
	print("Jogador: %s | Modo: %s" % [GameEngine.player_nation.nome, GameEngine.settings.get("mode", "?")])
	print("Eventos âncora+secundários: %d | Megatrends: %d" % [GameEngine.timeline.pending_events.size(), GameEngine.timeline.megatrends.size()])

	# Conta por categoria
	var anchor_ids: Dictionary = {}
	var secondary_ids: Dictionary = {}
	var megatrend_ids: Dictionary = {}
	for ev in GameEngine.timeline.pending_events:
		var ev_dict: Dictionary = ev
		var is_secondary: bool = ev_dict.get("scope", "") == "national" and not ev_dict.get("modal_decision", false) and ev_dict.get("year", 0) <= 2024
		if is_secondary:
			secondary_ids[ev_dict.get("id", "")] = true
		else:
			anchor_ids[ev_dict.get("id", "")] = true
	for ev in GameEngine.timeline.megatrends:
		megatrend_ids[ev.get("id", "")] = true

	# Auto-resposta: sempre escolhe a 1ª choice em decisões
	GameEngine.timeline.historic_event_decision.connect(func(ev: Dictionary):
		var choices: Array = ev.get("choices", [])
		if choices.size() > 0:
			GameEngine.timeline.apply_choice_by_id(ev.get("id", ""), choices[0].get("id", "")))

	var fired_anchor: int = 0
	var fired_secondary: int = 0
	var fired_megatrend: int = 0
	var megatrend_log: Array = []

	print("\nAvançando 400 turnos (100 anos)...")
	for i in 400:
		var before: int = GameEngine.timeline.fired_event_ids.size()
		GameEngine.end_turn()
		var newly: Array = GameEngine.timeline.fired_event_ids.slice(before, GameEngine.timeline.fired_event_ids.size())
		for eid in newly:
			if anchor_ids.has(eid):
				fired_anchor += 1
			elif secondary_ids.has(eid):
				fired_secondary += 1
			elif megatrend_ids.has(eid):
				fired_megatrend += 1
				var ev: Dictionary = GameEngine.timeline._find_event(eid)
				megatrend_log.append("  Y%d: %s" % [GameEngine.date_year, ev.get("headline", eid)])

	print("\n── RESULTADO ──")
	print("Período simulado: 2000 → %d" % GameEngine.date_year)
	print("Âncora histórica disparados: %d / %d" % [fired_anchor, anchor_ids.size()])
	print("Secundários disparados: %d / %d" % [fired_secondary, secondary_ids.size()])
	print("Megatrends disparadas: %d / %d" % [fired_megatrend, megatrend_ids.size()])
	print("\n── MEGATRENDS DISPARADAS ──")
	for line in megatrend_log:
		print(line)

	print("\nEstado final BR:")
	print("  PIB: $%dB" % int(GameEngine.player_nation.pib_bilhoes_usd))
	print("  Estabilidade: %d%%" % int(GameEngine.player_nation.estabilidade_politica))
	print("  Apoio: %d%%" % int(GameEngine.player_nation.apoio_popular))
	print("  Tesouro: $%dB" % int(GameEngine.player_nation.tesouro))
	print("══════════════════════════════════════════════")
	get_tree().quit(0)
