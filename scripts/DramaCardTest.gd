extends Node
## Teste VISUAL do card de PLANTÃO GEOPOLÍTICO — confirma que dois plantões
## seguidos NÃO se sobrepõem (só 1 card por vez) e que body vazio não gera
## retângulo morto. Tira screenshot pra inspeção. Roda SEM --headless.
## Godot_v4.7.1-stable_win64.exe --path . res://scenes/DramaCardTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("user://dramacard")
	var wm = load("res://scenes/WorldMap.tscn").instantiate()
	get_tree().root.add_child(wm)
	var t0 := Time.get_ticks_msec()
	while not wm._is_modal_open() and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	# fecha o modal de seleção assumindo o BR direto
	GameEngine.player_nation = GameEngine.nations["BR"]
	GameEngine.game_state = "PLAYING"

	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)
	print("\n=== TESTE VISUAL DO CARD DE PLANTÃO ===")

	# 1. dispara o 1º plantão (golpe, com corpo)
	wm._show_world_drama_card({
		"headline": "💥 GOLPE EM QUÊNIA", "body": "General Odhiambo toma o poder em um golpe.",
		"iso": "KE", "role": "presidente", "severity": 3})
	await get_tree().process_frame
	var cards1 := _count_cards(wm)
	_t.call("1 card após o 1º plantão", cards1 == 1)

	# 2. dispara o 2º plantão ANTES do 1º sumir — não pode sobrepor
	wm._show_world_drama_card({
		"headline": "🌍 COALIZÃO CONTRA VOCÊ", "body": "5 potências se unem para conter sua ascensão.",
		"iso": "US", "role": "presidente", "severity": 3})
	await get_tree().process_frame
	await get_tree().process_frame
	var cards2 := _count_cards(wm)
	_t.call("AINDA 1 card após o 2º plantão (sem sobreposição)", cards2 == 1)

	# 3. plantão com body VAZIO não cria retângulo morto (menos filhos no col)
	wm._show_world_drama_card({
		"headline": "🎙 BRASIL MUDA DE RUMO", "body": "",
		"iso": "BR", "role": "presidente", "severity": 2})
	await get_tree().process_frame
	var card = _find_card(wm)
	var col_children := _deepest_vbox_count(card) if card else -1
	# col deve ter: cap + head (SEM body vazio) = 2, não 3
	_t.call("body vazio NÃO adiciona label morta (col tem %d filhos)" % col_children, col_children <= 2)

	# screenshot pra inspeção visual
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://dramacard/plantao_final.png")
	print("  → screenshot em user://dramacard/plantao_final.png")

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)

func _count_cards(wm) -> int:
	var n := 0
	for c in wm.get_children():
		if c is PanelContainer and String(c.name).begins_with("DramaCard_"):
			n += 1
	return n

func _find_card(wm):
	for c in wm.get_children():
		if c is PanelContainer and String(c.name).begins_with("DramaCard_"):
			return c
	return null

func _deepest_vbox_count(card) -> int:
	# o col é o VBox dentro do HBox dentro do card
	for c in card.get_children():
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is VBoxContainer:
					return cc.get_child_count()
	return -1
