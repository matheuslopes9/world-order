extends Node
## SCREEN TOUR — captura screenshots de TODAS as telas principais do jogo
## para revisão visual de UX. Rode SEM --headless:
##   Godot_v4.6.2-stable_win64_console.exe --path . res://scenes/ScreenTour.tscn
## Salva em user://tour/NN_nome.png e fecha sozinho (~30s).

var wm: Node = null
var shot_idx: int = 0

var _backups: Dictionary = {}
const PROTECTED := ["user://world_order_save.json", "user://achievements.json", "user://settings.cfg"]

func _ready() -> void:
	_backup_user_files()
	get_tree().create_timer(90.0).timeout.connect(func():
		_restore_user_files()
		get_tree().quit(3))
	DirAccess.make_dir_recursive_absolute("user://tour")
	await get_tree().process_frame

	# 1 — Main Menu
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await get_tree().create_timer(1.2).timeout
	await _shot("menu")
	menu.queue_free()
	await get_tree().process_frame

	# 2 — WorldMap + seleção
	wm = load("res://scenes/WorldMap.tscn").instantiate()
	get_tree().root.add_child(wm)
	await get_tree().create_timer(1.5).timeout
	_mute_event_popups()
	await _shot("selecao_nacao")

	# 3 — Preview do Brasil + wizard
	var list = wm.nations_list
	for i in list.item_count:
		if list.get_item_metadata(i) == "BR":
			list.select(i)
			list.item_selected.emit(i)
			break
	await get_tree().create_timer(0.4).timeout
	await _shot("selecao_preview_brasil")
	if wm.has_method("_on_confirm_pressed"):
		wm._on_confirm_pressed()
		await get_tree().create_timer(0.5).timeout
		await _shot("wizard_tomar_posse")
	# Bypass pro jogo
	for i in 10:
		if wm._modal_stack.is_empty(): break
		wm._close_top_modal()
		await get_tree().process_frame
	wm._takeover_state = {"country_code": "BR", "leader_name": "Presidente Demo", "leader_age": 48,
		"leader_background": "politico", "leader_motto": "Ordem e Progresso", "government_type": "manter",
		"economic_doctrine": "mista", "first_steps": ["saude", "educacao", "infra"]}
	wm._finalize_takeover()
	await get_tree().create_timer(0.6).timeout
	for i in 10:
		if wm._modal_stack.is_empty(): break
		wm._close_top_modal()
		await get_tree().process_frame

	# 4 — Mapa em jogo (sem modal)
	GameEngine.player_power_rank_history = [14, 13, 12, 12, 11, 10, 9, 9, 8, 8]
	wm._refresh_top_bar()
	await _shot("mapa_em_jogo")

	# 4b — ONBOARDING (#14): briefing da nação + central de ajuda
	# Garante que o spinner/loading do takeover não esteja mais na frente.
	if wm.has_method("_hide_spinner"): wm._hide_spinner()
	if wm.has_method("_hide_loading_screen"): wm._hide_loading_screen()
	await get_tree().process_frame
	if wm.has_method("_show_nation_briefing"):
		wm._show_nation_briefing(GameEngine.player_nation, false)
		await get_tree().create_timer(0.5).timeout
		await _shot("onboarding_briefing")
		# O briefing é um Control no modal_layer (não no _modal_stack); remove direto.
		if wm.modal_layer:
			for c in wm.modal_layer.get_children():
				c.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	if wm.has_method("_show_help_center"):
		wm._show_help_center()
		await get_tree().create_timer(0.4).timeout
		await _shot("onboarding_ajuda")
		while not wm._modal_stack.is_empty():
			wm._close_top_modal()
			await get_tree().process_frame

	# Gabinete com níveis/verba/pesquisa p/ os painéis mostrarem conteúdo rico
	var pn = GameEngine.player_nation
	pn.tesouro = 3000.0
	pn.ministerios["casa_civil"]["nivel"] = 3; pn.ministerios["casa_civil"]["xp"] = 400.0
	pn.ministerios["saude"]["nivel"] = 2; pn.ministerios["saude"]["xp"] = 180.0; pn.ministerios["saude"]["verba"] = 40.0
	pn.ministerios["educacao"]["nivel"] = 4; pn.ministerios["educacao"]["xp"] = 900.0; pn.ministerios["educacao"]["verba"] = 60.0
	pn.ministerios["fazenda"]["nivel"] = 2; pn.ministerios["fazenda"]["verba"] = 30.0
	pn.ministerios["seguranca"]["nivel"] = 3
	for pasta_seed in ["saude", "educacao", "seguranca"]:
		var av: Array = GameEngine.tech.get_available_techs(pn, pasta_seed)
		if not av.is_empty():
			GameEngine.tech.start_research(pn, String(av[0]["id"]))
	for _i in 2:
		if GameEngine.tech: GameEngine.tech.process_turn()

	# Corrupção alta p/ o painel Fazenda demonstrar a espiral (IED, êxodo, desvio)
	pn.corrupcao = 68.0
	pn.confianca_investidor = 28.0
	pn.empresas_sairam = 4
	pn.tesouro_desviado_total = 23.5
	# (valores de demonstração — a espiral real é dirigida pela corrupção em jogo)

	# 5 — Painéis
	for panel_id in ["gabinete", "governo", "economia", "seguranca", "saude", "educacao", "diplomacia", "tech", "intel", "situacao", "historico"]:
		wm._open_overlay_modal(panel_id)
		await get_tree().create_timer(0.35).timeout
		await _shot("painel_" + panel_id)
		wm._close_top_modal()
		await get_tree().process_frame

	# 5b — Mapa no filtro RECURSOS (ícones vetoriais de petróleo/madeira/etc)
	if wm.has_method("_on_map_filter_pressed"):
		wm._on_map_filter_pressed("RECURSOS")
		await get_tree().create_timer(0.4).timeout
		await _shot("mapa_recursos_icones")
		wm._on_map_filter_pressed("POLITICO")
		await get_tree().process_frame

	# 5c — Modal do FMI (crise fiscal)
	GameEngine.player_nation.tesouro = 0.0
	GameEngine.player_nation.falencia_turnos = 1
	GameEngine.bailout_pending = {}
	GameEngine._last_bailout_turn = -999
	GameEngine.evaluate_endgame()
	await get_tree().create_timer(0.5).timeout
	await _shot("modal_fmi")
	# recusa pra limpar + restaura tesouro
	GameEngine.decline_bailout()
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame
	GameEngine.player_nation.tesouro = 500.0
	GameEngine.player_nation.falencia_turnos = 0

	# 6 — Dossiê + pickers
	wm._open_dossier_modal("US")
	await get_tree().create_timer(0.4).timeout
	await _shot("dossie_eua")
	wm._show_treaty_picker_modal("US")
	await get_tree().create_timer(0.3).timeout
	await _shot("picker_tratados")
	for m in _loose():
		m.queue_free()
	await get_tree().process_frame
	wm._show_spy_picker_modal("US")
	await get_tree().create_timer(0.3).timeout
	await _shot("picker_espionagem")
	for m in _loose():
		m.queue_free()
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame

	# 7 — Opções + Notícias
	wm._on_menu_pressed()
	await get_tree().create_timer(0.35).timeout
	await _shot("opcoes")
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame
	wm._open_news_modal()
	await get_tree().create_timer(0.35).timeout
	await _shot("noticias")
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame

	# 8 — Decisão histórica REAL (11/9 com conselheiros)
	var ev: Dictionary = {}
	for e in GameEngine.timeline.pending_events:
		if String(e.get("id", "")) == "ataques_911":
			ev = e
			break
	if not ev.is_empty():
		wm._open_historic_decision_modal(ev)
		await get_tree().create_timer(0.5).timeout
		await _shot("decisao_historica_911")
		while not wm._modal_stack.is_empty():
			wm._close_top_modal()
			await get_tree().process_frame

	# 9 — Endgame (vitória)
	GameEngine._fire_endgame(true, "🏆 HEGEMONIA GLOBAL", "Sua nação lidera o ranking mundial de poder há 4 anos consecutivos.")
	await get_tree().create_timer(0.8).timeout
	await _shot("endgame_vitoria")

	print("[TOUR] %d screenshots salvos em user://tour/" % shot_idx)
	_restore_user_files()
	await get_tree().process_frame
	get_tree().quit(0)

func _shot(name: String) -> void:
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	shot_idx += 1
	img.save_png("user://tour/%02d_%s.png" % [shot_idx, name])
	print("[TOUR] %02d_%s.png" % [shot_idx, name])

func _loose() -> Array:
	var out: Array = []
	for c in wm.get_children():
		if c is ColorRect and c.get_child_count() > 0:
			out.append(c)
	return out

func _mute_event_popups() -> void:
	for conn in GameEngine.player_event_triggered.get_connections():
		GameEngine.player_event_triggered.disconnect(conn["callable"])
	if GameEngine.timeline:
		for conn in GameEngine.timeline.historic_event_decision.get_connections():
			GameEngine.timeline.historic_event_decision.disconnect(conn["callable"])
	if GameEngine.storylines:
		for conn in GameEngine.storylines.storyline_triggered.get_connections():
			GameEngine.storylines.storyline_triggered.disconnect(conn["callable"])

func _backup_user_files() -> void:
	for path in PROTECTED:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			_backups[path] = f.get_buffer(f.get_length())
			f.close()
		else:
			_backups[path] = null

func _restore_user_files() -> void:
	for path in PROTECTED:
		var data = _backups.get(path)
		if data == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(data)
				f.close()
