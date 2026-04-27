extends Control
## Tela inicial do WORLD ORDER — Hello World do porte Godot.
## Confirma que: cena carrega, script roda, tema visual aplica, input funciona.

@onready var status_label: Label = %StatusLabel
@onready var info_label: Label = %InfoLabel
@onready var test_button: Button = %TestButton
@onready var map_button: Button = %MapButton

const SaveSys = preload("res://scripts/SaveSystem.gd")
const MONO_FONT := preload("res://fonts/CascadiaMono.ttf")

func _ready() -> void:
	# Roda diagnóstico inicial
	var info := []
	info.append("Godot %s" % Engine.get_version_info().string)
	info.append("Renderer: %s" % RenderingServer.get_video_adapter_name())
	info.append("Vendor: %s" % RenderingServer.get_video_adapter_vendor())
	info.append("Driver: %s" % OS.get_video_adapter_driver_info())
	info.append("FPS atual: %d" % Engine.get_frames_per_second())
	info.append("OS: %s (%s)" % [OS.get_name(), OS.get_distribution_name()])
	info_label.text = "\n".join(info)
	info_label.add_theme_font_override("font", MONO_FONT)

	status_label.text = "▸ SISTEMA ONLINE"
	# Atualiza texto botão se há save
	if map_button and SaveSys.has_save():
		var save_info: Dictionary = SaveSys.get_save_info()
		var quarters := ["JAN", "ABR", "JUL", "OUT"]
		var date_str: String = "%s %d" % [quarters[int(save_info.get("date_quarter", 1)) - 1], int(save_info.get("date_year", 2024))]
		map_button.text = "▶ CONTINUAR: %s (Turno %d, %s)" % [save_info.get("player_code", "?"), int(save_info.get("current_turn", 0)), date_str]
	test_button.pressed.connect(_on_test_pressed)
	if map_button:
		map_button.pressed.connect(_on_map_pressed)

	# Seletor de modo de jogo (inspirado / livre) — inserido antes do ButtonRow
	_add_mode_selector()

	# ─── ANIMAÇÃO DE ENTRADA + SCANLINES ───
	_play_entrance_animation()
	_start_brand_pulse()
	_start_status_pulse()
	_spawn_startup_scanline()
	_style_main_buttons()

	print("[WORLD ORDER] MainMenu pronto. Renderer: %s" % RenderingServer.get_video_adapter_name())

func _add_mode_selector() -> void:
	# Insere um VBox de "MODO DE CAMPANHA" antes do ButtonRow
	var main_box := get_node_or_null("Center/Card/MainBox")
	var button_row := get_node_or_null("Center/Card/MainBox/ButtonRow")
	if main_box == null or button_row == null: return

	var mode_box := VBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 6)
	mode_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main_box.add_child(mode_box)
	main_box.move_child(mode_box, button_row.get_index())  # coloca antes do ButtonRow

	var lbl := Label.new()
	lbl.text = "◆ MODO DE CAMPANHA"
	lbl.add_theme_color_override("font_color", Color(0, 0.823, 1, 0.85))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_box.add_child(lbl)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	mode_box.add_child(row)

	var current_mode: String = GameEngine.settings.get("mode", "inspirado")
	var btns: Array = []
	var modes := [
		{"id": "inspirado", "label": "🕰  Inspirado", "tip": "Eventos históricos disparam em janelas reais (11/9 em 2001, etc)"},
		{"id": "livre",     "label": "🎲  Livre",     "tip": "Eventos com janelas alargadas — IA reage sem constraint histórico"},
	]
	for m in modes:
		var b := Button.new()
		b.text = m["label"]
		b.tooltip_text = m["tip"]
		b.toggle_mode = true
		b.button_pressed = (m["id"] == current_mode)
		b.set_meta("mode_id", m["id"])
		b.custom_minimum_size = Vector2(180, 36)
		b.add_theme_font_size_override("font_size", 12)
		b.focus_mode = Control.FOCUS_NONE
		var mode_id: String = m["id"]
		b.pressed.connect(func():
			GameEngine.settings["mode"] = mode_id
			for other in btns:
				other.button_pressed = (other.get_meta("mode_id") == mode_id))
		row.add_child(b)
		btns.append(b)

	var hint := Label.new()
	hint.text = "Campanha 100 anos: 2000 → 2100"
	hint.add_theme_color_override("font_color", Color(0.5, 0.62, 0.78, 1))
	hint.add_theme_font_size_override("font_size", 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_box.add_child(hint)

func _play_entrance_animation() -> void:
	var box := get_node_or_null("CenterContainer/MainBox")
	if box == null: return
	box.modulate = Color(1, 1, 1, 0)
	box.position += Vector2(0, 30)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(box, "modulate", Color(1, 1, 1, 1), 0.6).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(box, "position", box.position - Vector2(0, 30), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _start_brand_pulse() -> void:
	var brand := get_node_or_null("CenterContainer/MainBox/TitleSection/Brand")
	if brand == null: return
	var tw := create_tween().set_loops()
	tw.tween_property(brand, "modulate:a", 0.55, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(brand, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE)

func _start_status_pulse() -> void:
	if status_label == null: return
	# Glow contínuo no status
	status_label.add_theme_constant_override("shadow_outline_size", 10)
	status_label.add_theme_color_override("font_shadow_color", Color(0, 1, 0.55, 0.5))
	var tw := create_tween().set_loops()
	tw.tween_property(status_label, "modulate", Color(1.2, 1.2, 1.2), 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(status_label, "modulate", Color(1, 1, 1), 1.0).set_trans(Tween.TRANS_SINE)

func _spawn_startup_scanline() -> void:
	# Linha ciano que atravessa horizontalmente — efeito CRT
	var line := ColorRect.new()
	line.color = Color(0, 0.823, 1, 0.0)
	line.custom_minimum_size = Vector2(0, 2)
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_left = 0
	line.offset_right = 0
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	# Loop: position vertical varre a tela
	var tw := create_tween().set_loops()
	tw.tween_callback(func():
		var vp_h: float = get_viewport_rect().size.y
		line.position = Vector2(0, -10)
		line.color = Color(0, 0.823, 1, 0.7)
		var t2 := create_tween()
		t2.tween_property(line, "position:y", vp_h + 10, 3.5).set_trans(Tween.TRANS_LINEAR)
		t2.parallel().tween_property(line, "color", Color(0, 0.823, 1, 0.0), 3.5).set_delay(2.0))
	tw.tween_interval(4.0)

func _style_main_buttons() -> void:
	# MapButton: botão grande, SEM shadow (shadow expande visual além da hitbox e
	# faz o usuário clicar abaixo do que aparece). Bordas simétricas pra hitbox bater.
	if map_button:
		var sb_n := StyleBoxFlat.new()
		sb_n.bg_color = Color(0, 0.55, 0.78, 0.9)
		sb_n.border_color = Color(0, 0.95, 1, 1)
		sb_n.set_border_width_all(2)
		sb_n.set_corner_radius_all(12)
		sb_n.content_margin_left = 22
		sb_n.content_margin_right = 22
		sb_n.content_margin_top = 14
		sb_n.content_margin_bottom = 14
		var sb_h := sb_n.duplicate() as StyleBoxFlat
		sb_h.bg_color = Color(0, 0.78, 0.98, 1)
		var sb_p := sb_n.duplicate() as StyleBoxFlat
		sb_p.bg_color = Color(0, 0.40, 0.65, 1)
		map_button.add_theme_stylebox_override("normal", sb_n)
		map_button.add_theme_stylebox_override("hover", sb_h)
		map_button.add_theme_stylebox_override("pressed", sb_p)
		map_button.add_theme_stylebox_override("focus", sb_h)
		map_button.add_theme_color_override("font_color", Color(1, 1, 1))
		map_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		_attach_hover_pop_simple(map_button)
	if test_button:
		_attach_hover_pop_simple(test_button)

func _attach_hover_pop_simple(btn: Control, _unused: float = 1.04) -> void:
	# Apenas brilho via modulate — não usa scale para não deslocar hitbox
	if btn == null: return
	btn.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_property(btn, "modulate", Color(1.18, 1.18, 1.18, 1.0), 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
	btn.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(btn, "modulate", Color(1, 1, 1, 1), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))

func _on_continue_pressed() -> void:
	# Carrega save e abre WorldMap
	if SaveSys.has_save():
		SaveSys.load_game(GameEngine)
	get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")

func _on_map_pressed() -> void:
	# Mostra overlay de carregamento ANTES de trocar de scene
	# (a troca em si é rápida, mas o _ready do WorldMap leva ~600ms carregando geometria)
	_show_loading_overlay()
	# Espera 1 frame pra UI atualizar antes de bloquear no load
	await get_tree().process_frame
	if SaveSys.has_save():
		SaveSys.load_game(GameEngine)
	get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")

func _show_loading_overlay() -> void:
	# Overlay full-screen com spinner rotacionando
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.z_index = 200
	add_child(ov)
	var bg := ColorRect.new()
	bg.color = Color(0, 0.04, 0.07, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var icon := Label.new()
	icon.text = "◐"
	icon.add_theme_font_size_override("font_size", 48)
	icon.add_theme_color_override("font_color", Color(0, 0.95, 1))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.custom_minimum_size = Vector2(64, 64)
	box.add_child(icon)
	var lbl := Label.new()
	lbl.text = "Carregando o mundo…"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	# Rotação contínua
	icon.pivot_offset = Vector2(32, 32)
	var tw := create_tween().set_loops()
	tw.tween_method(func(angle: float): icon.rotation = angle, 0.0, TAU, 1.0)

func _on_test_pressed() -> void:
	# Teste simples: muda cor e mostra que input funciona
	status_label.text = "✓ INPUT FUNCIONA — pronto para Fase 2"
	status_label.add_theme_color_override("font_color", Color(0, 1, 0.5))
	print("[WORLD ORDER] Botão clicado — sistema responsivo OK")

func _process(_delta: float) -> void:
	# Atualiza FPS em tempo real para confirmar fluidez
	if info_label and is_instance_valid(info_label):
		var lines := info_label.text.split("\n")
		if lines.size() >= 5:
			lines[4] = "FPS atual: %d" % Engine.get_frames_per_second()
			info_label.text = "\n".join(lines)
