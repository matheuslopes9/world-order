extends Node
## PLAYTHROUGH TOUR — joga o jogo REAL turno-a-turno pela UI e fotografa a evolução.
##
## Diferente do MegaSim (bot, sem UI) e do ScreenTour (telas isoladas): este ABRE a
## WorldMap real, assume o Brasil pelo caminho do jogador, e AVANÇA TURNO A TURNO
## clicando no botão real (_on_next_turn_pressed), tirando screenshot a cada 5 anos
## + registrando os indicadores. Valida a EXPERIÊNCIA turno-a-turno, não só o motor.
##
## Rodar: Godot_v4.7.1-stable_win64.exe --path . res://scenes/PlaythroughTour.tscn

var wm: Node = null
var _backups: Dictionary = {}
const PROTECTED := ["user://nations_new_dawn_save.json", "user://achievements.json", "user://settings.cfg"]
const SHOT_EVERY := 120  # turnos (=10 anos; ritmo mensal = 12 turnos/ano)
const MAX_TURNS := 1320  # 100 anos completos (1200) + margem
var shot_idx := 0
var log_rows: Array = []

func _ready() -> void:
	print("\n=== PLAYTHROUGH TOUR — jogando o jogo REAL turno-a-turno ===")
	_backup_user_files()
	DirAccess.make_dir_recursive_absolute("user://playthrough")
	await get_tree().process_frame

	# 1) Carrega a WorldMap real e assume o Brasil
	wm = load("res://scenes/WorldMap.tscn").instantiate()
	get_tree().root.add_child(wm)
	var t0 := Time.get_ticks_msec()
	while not wm._is_modal_open() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame

	var list = wm.nations_list
	var idx := -1
	for i in list.item_count:
		if list.get_item_metadata(i) == "BR":
			idx = i; break
	list.select(idx); list.item_selected.emit(idx)
	await get_tree().process_frame

	# assume o poder pelo caminho real (mesma lógica do GameplayTest)
	if wm.has_method("_on_confirm_pressed"):
		wm._on_confirm_pressed()
		await get_tree().create_timer(0.4).timeout
	for step in 14:
		if GameEngine.player_nation != null: break
		if wm._modal_stack.is_empty(): break
		var top = wm._modal_stack.back()
		_fill_required_fields(top)
		await get_tree().process_frame
		var nxt = _find_button(top, ["ASSUMIR","COMEÇAR","INICIAR GOVERNO","CONFIRMAR","PRÓXIM","CONTINUAR","▶"])
		if nxt == null or nxt.disabled: break
		nxt.pressed.emit()
		await get_tree().create_timer(0.25).timeout

	if GameEngine.player_nation == null:
		# fallback: força a posse mínima pra o tour seguir
		GameEngine.player_nation = GameEngine.nations["BR"]
		GameEngine.game_state = "PLAYING"
	print("  → assumiu %s. Jogando %d turnos..." % [GameEngine.player_nation.nome, MAX_TURNS])
	await get_tree().create_timer(0.5).timeout
	await _shot("inicio")

	# 2) Joga turno a turno clicando no botão REAL
	var turno := 0
	while turno < MAX_TURNS and GameEngine.game_state == "PLAYING" and GameEngine.date_year < 2100:
		# fecha qualquer modal aberto (evento/decisão) escolhendo a 1ª opção
		var guard := 0
		while wm._is_modal_open() and guard < 6:
			var top = wm._modal_stack.back() if not wm._modal_stack.is_empty() else null
			# inclui os botões de briefing/evento ("ASSUMIR O COMANDO", opções de decisão)
			var b = _find_button(top, ["ASSUMIR","COMANDO","OK","FECHAR","CONTINUAR","ENTENDI","✕","IGNORAR","DEPOIS","ACEITAR","MANTER","RECUSAR"]) if top else null
			if b == null and top != null:
				# fallback: clica o 1º botão não-desabilitado do modal (escolhe algo)
				for cand in _all_children(top):
					if cand is Button and not (cand as Button).disabled:
						b = cand; break
			if b: b.pressed.emit()
			else: break
			await get_tree().process_frame
			guard += 1
		# clica AVANÇAR TURNO (caminho real do jogador)
		if wm.has_method("_on_next_turn_pressed"):
			wm._on_next_turn_pressed()
		else:
			GameEngine.end_turn()
		await get_tree().process_frame
		turno += 1
		if turno % SHOT_EVERY == 0:
			_record()
			await _shot("t%03d_ano%d" % [turno, GameEngine.date_year])

	await _shot("fim")
	_report()
	_restore_user_files()
	get_tree().quit(0)

func _record() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	log_rows.append({
		"turno": GameEngine.current_turn, "ano": GameEngine.date_year,
		"pib": n.pib_bilhoes_usd, "tesouro": n.tesouro, "divida": n.divida_publica,
		"estab": n.estabilidade_politica, "apoio": n.apoio_popular,
		"infl": n.inflacao, "rank": GameEngine.get_power_rank(n.codigo_iso),
		"rating": n.rating_credito(), "guerras": n.em_guerra.size(),
	})

func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://playthrough/%02d_%s.png" % [shot_idx, name])
	shot_idx += 1

func _report() -> void:
	print("\n── EVOLUÇÃO DA CAMPANHA (Brasil, turno a turno) ──")
	print("  ano  | PIB($B)   | tesouro | dívida%%PIB | estab | apoio | infl | rank | rating")
	for r in log_rows:
		var dpib: float = 100.0 * r.divida / max(1.0, r.pib)
		print("  %4d | %9.0f | %7.0f | %9.0f | %5.1f | %5.1f | %4.1f | %4d | %5.1f" % [
			r.ano, r.pib, r.tesouro, dpib, r.estab, r.apoio, r.infl, r.rank, r.rating])
	print("\n  → %d screenshots em user://playthrough/  ·  desfecho: %s" % [shot_idx, GameEngine.game_state])

func _fill_required_fields(root: Node) -> void:
	for le in _all_children(root):
		if le is LineEdit and (le as LineEdit).text.strip_edges() == "":
			(le as LineEdit).text = "Tester"
			(le as LineEdit).text_changed.emit("Tester")
	var toggles: Array = []
	for b in _all_children(root):
		if b is Button and (b as Button).toggle_mode:
			toggles.append(b)
	var any_on := false
	for b in toggles:
		if (b as Button).button_pressed: any_on = true
	if not any_on and toggles.size() > 0:
		(toggles[0] as Button).pressed.emit()
	if toggles.size() >= 6:
		var on_count := 0
		for b in toggles:
			if (b as Button).button_pressed: on_count += 1
		var i := 0
		while on_count < 3 and i < toggles.size():
			if not (toggles[i] as Button).button_pressed:
				(toggles[i] as Button).pressed.emit(); on_count += 1
			i += 1

func _find_button(node, keywords: Array) -> Button:
	if node == null: return null
	for child in _all_children(node):
		if child is Button:
			var txt: String = String(child.text).to_upper()
			for k in keywords:
				if String(k).to_upper() in txt:
					return child
	return null

func _all_children(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append(c)
		out.append_array(_all_children(c))
	return out

func _backup_user_files() -> void:
	for p in PROTECTED:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f: _backups[p] = f.get_as_text(); f.close()

func _restore_user_files() -> void:
	for p in PROTECTED:
		if _backups.has(p):
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f: f.store_string(_backups[p]); f.close()
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
