extends Node
## Dev-tool: captura screenshot de um painel do jogo para verificação visual.
## Rode SEM --headless (precisa de renderização real):
##   Godot_v4.6.2-stable_win64_console.exe --path . res://scenes/PanelShot.tscn
## Salva em user://panel_situacao.png e fecha sozinho (~6s).
## NÃO avança turnos (evita autosave/eventos) — semeia trajetória de exemplo.

# Protege os arquivos reais do usuário (fluxos do WorldMap podem salvar)
var _backups: Dictionary = {}
const PROTECTED := ["user://nations_new_dawn_save.json", "user://achievements.json", "user://settings.cfg"]

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

func _ready() -> void:
	_backup_user_files()
	# Kill-switch: encerra de qualquer forma após 25s (restaurando saves)
	get_tree().create_timer(25.0).timeout.connect(func():
		_restore_user_files()
		get_tree().quit(3))

	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/WorldMap.tscn")
	var wm = packed.instantiate()
	get_tree().root.add_child(wm)
	await get_tree().create_timer(1.4).timeout

	# Assume comando do Brasil (bypass do wizard, como no UIAutoTest)
	wm._takeover_state = {
		"country_code": "BR", "leader_name": "Verificador", "leader_age": 50,
		"leader_background": "politico", "leader_motto": "", "government_type": "manter",
		"economic_doctrine": "mista", "first_steps": ["saude", "educacao", "infra"],
	}
	wm._finalize_takeover()
	await get_tree().create_timer(0.6).timeout
	for i in 10:  # fecha tutorial/modais (bounded)
		if wm._modal_stack.is_empty(): break
		wm._close_top_modal()
		await get_tree().process_frame

	# Semeia trajetória de exemplo (sem avançar turnos — sem autosave/eventos)
	GameEngine.player_power_rank_history = [14, 14, 13, 13, 12, 11, 11, 10, 9, 9, 8, 8, 7, 7]
	GameEngine.player_nation.set_meta("victory_streak", 11)

	# Shot 1: painel Situação
	wm._open_overlay_modal("situacao")
	await get_tree().create_timer(1.2).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://panel_situacao.png")
	print("[SHOT] user://panel_situacao.png salvo (%dx%d)" % [img.get_width(), img.get_height()])
	wm._close_top_modal()
	await get_tree().process_frame

	# Shot 2: dossiê de país (mostra a bandeira real)
	wm._open_dossier_modal("US")
	await get_tree().create_timer(1.0).timeout
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("user://panel_dossier.png")
	print("[SHOT] user://panel_dossier.png salvo")

	_restore_user_files()
	await get_tree().process_frame
	get_tree().quit()
