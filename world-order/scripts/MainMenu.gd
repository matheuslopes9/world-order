extends Control
## Tela inicial do WORLD ORDER — Hello World do porte Godot.
## Confirma que: cena carrega, script roda, tema visual aplica, input funciona.

@onready var status_label: Label = %StatusLabel
@onready var info_label: Label = %InfoLabel
@onready var test_button: Button = %TestButton
@onready var map_button: Button = %MapButton

const SaveSys = preload("res://scripts/SaveSystem.gd")
const MONO_FONT := preload("res://fonts/CascadiaMono.ttf")

# Paleta consolidada — referenciada pelos modais e UI dinâmica
const PALETTE := {
	"cyan": Color(0, 0.823, 1, 0.9),
	"cyan_dim": Color(0, 0.823, 1, 0.55),
	"gold": Color(1, 0.85, 0.3, 0.85),
	"red_warn": Color(1, 0.45, 0.4, 0.85),
	"green_ok": Color(0.4, 1, 0.6, 0.95),
	"bg_panel": Color(0.035, 0.06, 0.10, 0.99),
	"bg_panel_red": Color(0.10, 0.04, 0.04, 0.99),
	"bg_overlay": Color(0, 0.04, 0.08, 0.94),
	"text_primary": Color(0.95, 0.99, 1),
	"text_dim": Color(0.55, 0.7, 0.85),
}

# Aplica fade-in suave (200ms) a um node, partindo de modulate.a=0.
func _fade_in(node: CanvasItem, duration: float = 0.20) -> void:
	if node == null: return
	node.modulate = Color(node.modulate.r, node.modulate.g, node.modulate.b, 0.0)
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC)

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

	# Botão de deletar save — só aparece se existe save
	if SaveSys.has_save():
		_add_delete_save_button()

	# Seletor de modo de jogo (inspirado / livre) — inserido antes do ButtonRow
	_add_mode_selector()
	# Seletor de cenário (campanha, década crítica, sandbox, etc)
	_add_scenario_selector()
	# Botão de progresso (XP / perks desbloqueados entre saves)
	_add_progression_button()
	# Seletor de idioma
	_add_language_selector()
	# Botão de créditos depois dos demais
	_add_credits_button()

	# ─── ANIMAÇÃO DE ENTRADA + SCANLINES ───
	_play_entrance_animation()
	_start_brand_pulse()
	_start_status_pulse()
	_spawn_startup_scanline()
	_style_main_buttons()

	# Intro cinematográfica — só na primeira vez que o jogador abre o jogo
	_maybe_show_intro_lore()

	print("[WORLD ORDER] MainMenu pronto. Renderer: %s" % RenderingServer.get_video_adapter_name())

# Intro cinematográfica que aparece UMA vez (controlado por config).
# Pode ser visto novamente via botão "📜 Histórico" futuramente.
func _maybe_show_intro_lore(force: bool = false) -> void:
	if not force:
		var cfg = ConfigFile.new()
		if cfg.load("user://settings.cfg") == OK:
			if cfg.get_value("intro", "shown", false):
				return
	_show_intro_lore()

func _show_intro_lore() -> void:
	# Overlay full-screen sobre o MainMenu
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 200
	add_child(modal)
	# Fundo preto puro
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(bg)
	# Container central
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	box.custom_minimum_size = Vector2(820, 0)
	center.add_child(box)

	# Fragmentos da narrativa (aparecem em sequência)
	var fragments: Array = [
		{
			"prefix": "2099",
			"text": "A inteligência artificial OLIMPIA é questionada por historiadores:\n\n— \"Qual decisão mudou o século?\"",
			"color": Color(0, 0.823, 1, 1),
		},
		{
			"prefix": "OLIMPIA RESPONDE",
			"text": "Para responder, simulei o século XXI bilhões de vezes.\n\nMas a verdade é mais perturbadora: nenhuma resposta única existe.",
			"color": Color(0.85, 0.93, 1, 1),
		},
		{
			"prefix": "CONVITE",
			"text": "Você é um analista da OLIMPIA.\n\nSua missão: assumir uma das 195 nações em 2000 e provar que outra história era possível.\n\nDe Putin a Lula, de Mubarak a Bush — cada turno, uma escolha. Cada escolha, uma realidade alternativa.",
			"color": Color(1, 0.85, 0.3, 1),
		},
		{
			"prefix": "WORLD ORDER",
			"text": "100 anos. 195 nações. 838 eventos.\nUma simulação. Sua história.",
			"color": Color(0, 1, 0.55, 1),
		},
	]

	# Renderiza fragmento atual + animação
	var current_frag: int = 0
	var prefix_lbl := Label.new()
	prefix_lbl.add_theme_color_override("font_color", Color(0, 0.823, 1, 0.85))
	prefix_lbl.add_theme_font_size_override("font_size", 13)
	prefix_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prefix_lbl.modulate = Color(1, 1, 1, 0)
	box.add_child(prefix_lbl)

	var deco := ColorRect.new()
	deco.color = Color(0, 0.823, 1, 0.6)
	deco.custom_minimum_size = Vector2(80, 2)
	deco.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	deco.modulate = Color(1, 1, 1, 0)
	box.add_child(deco)

	var text_lbl := Label.new()
	text_lbl.add_theme_color_override("font_color", Color(0.95, 1, 1))
	text_lbl.add_theme_font_size_override("font_size", 22)
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.modulate = Color(1, 1, 1, 0)
	box.add_child(text_lbl)

	# Botões: Pular agora / Continuar (próximo fragmento)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.modulate = Color(1, 1, 1, 0)
	box.add_child(btn_row)

	var btn_skip := Button.new()
	btn_skip.text = "⏭ PULAR INTRO"
	btn_skip.custom_minimum_size = Vector2(160, 40)
	btn_skip.add_theme_font_size_override("font_size", 11)
	btn_row.add_child(btn_skip)

	var btn_next := Button.new()
	btn_next.text = "PRÓXIMO ▶"
	btn_next.custom_minimum_size = Vector2(160, 40)
	btn_next.add_theme_font_size_override("font_size", 11)
	btn_row.add_child(btn_next)

	# Função pra renderizar fragmento atual com animação
	var render_frag := func():
		if current_frag >= fragments.size():
			# Fim — fade-out tudo e remove modal
			var out := create_tween()
			out.tween_property(modal, "modulate:a", 0.0, 0.6)
			out.tween_callback(func():
				if is_instance_valid(modal): modal.queue_free()
				_mark_intro_shown())
			return
		var f: Dictionary = fragments[current_frag]
		prefix_lbl.text = String(f.get("prefix", ""))
		prefix_lbl.add_theme_color_override("font_color", f.get("color", Color(0, 0.823, 1, 0.85)))
		text_lbl.text = String(f.get("text", ""))
		# Reset alpha pra animar
		prefix_lbl.modulate = Color(1, 1, 1, 0)
		deco.modulate = Color(1, 1, 1, 0)
		text_lbl.modulate = Color(1, 1, 1, 0)
		btn_row.modulate = Color(1, 1, 1, 0)
		# Anima em sequência
		var tw := create_tween()
		tw.tween_property(prefix_lbl, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(deco, "modulate:a", 1.0, 0.3)
		tw.tween_property(text_lbl, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(btn_row, "modulate:a", 1.0, 0.3)
		current_frag += 1

	btn_skip.pressed.connect(func():
		var tw := create_tween()
		tw.tween_property(modal, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func():
			if is_instance_valid(modal): modal.queue_free()
			_mark_intro_shown()))
	btn_next.pressed.connect(render_frag)

	render_frag.call()

func _mark_intro_shown() -> void:
	var cfg = ConfigFile.new()
	cfg.load("user://settings.cfg")  # OK se não existir
	cfg.set_value("intro", "shown", true)
	cfg.save("user://settings.cfg")

func _add_scenario_selector() -> void:
	var main_box := get_node_or_null("Center/Card/MainBox")
	var button_row := get_node_or_null("Center/Card/MainBox/ButtonRow")
	if main_box == null or button_row == null: return
	var scen_box := VBoxContainer.new()
	scen_box.add_theme_constant_override("separation", 6)
	main_box.add_child(scen_box)
	main_box.move_child(scen_box, button_row.get_index())

	var lbl := Label.new()
	lbl.text = "◆ CENÁRIO"
	lbl.add_theme_color_override("font_color", Color(0, 0.823, 1, 0.85))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scen_box.add_child(lbl)

	# OptionButton (dropdown) com lista de cenários carregados
	var dropdown := OptionButton.new()
	dropdown.custom_minimum_size = Vector2(420, 36)
	dropdown.add_theme_font_size_override("font_size", 12)
	scen_box.add_child(dropdown)

	# Hint que muda conforme cenário selecionado
	var hint := Label.new()
	hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
	hint.add_theme_font_size_override("font_size", 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(420, 0)
	scen_box.add_child(hint)

	# Popula dropdown com cenários disponíveis
	var scenarios: Array = []
	if GameEngine and GameEngine.scenarios_data:
		scenarios = GameEngine.scenarios_data
	if scenarios.is_empty():
		dropdown.add_item("Campanha 100 Anos")
		hint.text = "Carregando cenários..."
		return
	var current_id: String = String(GameEngine.settings.get("scenario", "campanha"))
	var current_idx: int = 0
	for i in scenarios.size():
		var sc: Dictionary = scenarios[i]
		var locked: bool = not bool(sc.get("unlocked_by_default", true))
		var label_text: String = "%s  %s — %s" % [sc.get("icon", "🎮"), sc.get("name", "?"), sc.get("subtitle", "")]
		if locked:
			label_text = "🔒 " + label_text
		dropdown.add_item(label_text)
		if locked:
			dropdown.set_item_disabled(i, true)
		if sc.get("id", "") == current_id:
			current_idx = i
	dropdown.select(current_idx)
	# Atualiza hint
	var update_hint := func(idx: int):
		if idx < 0 or idx >= scenarios.size(): return
		var sc: Dictionary = scenarios[idx]
		var hours: String = String(sc.get("estimated_hours", "?"))
		hint.text = "%s\n⏱ %s" % [sc.get("description", ""), hours]
	update_hint.call(current_idx)
	dropdown.item_selected.connect(func(idx: int):
		var sc: Dictionary = scenarios[idx]
		if sc.get("id", "") != "":
			GameEngine.settings["scenario"] = String(sc.get("id"))
		update_hint.call(idx))

func _add_delete_save_button() -> void:
	var button_row := get_node_or_null("Center/Card/MainBox/ButtonRow")
	if button_row == null: return
	var btn := Button.new()
	btn.text = tr("ui.menu.delete_save")
	btn.custom_minimum_size = Vector2(420, 28)
	btn.add_theme_font_size_override("font_size", 10)
	btn.modulate = Color(1, 0.7, 0.7)
	btn.pressed.connect(func():
		_show_main_menu_confirm(
			"🗑 APAGAR SAVE?",
			"Tem certeza que quer apagar o save atual?\n\nEsta ação não pode ser desfeita. A partida atual será perdida e você precisará começar uma nova.",
			func():
				if SaveSys.delete_save():
					btn.queue_free()
					if map_button:
						map_button.text = "▶ INICIAR NOVA CAMPANHA"))
	button_row.add_child(btn)

# Modal genérico de confirmação no MainMenu (overlay simples)
func _show_main_menu_confirm(title: String, msg: String, on_confirm: Callable) -> void:
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 200
	add_child(modal)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(480, 240)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.04, 0.04, 0.99)
	sb.border_color = Color(1, 0.4, 0.4, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_lbl)
	var msg_lbl := Label.new()
	msg_lbl.text = msg
	msg_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
	msg_lbl.add_theme_font_size_override("font_size", 11)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg_lbl)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	v.add_child(btns)
	var btn_no := Button.new()
	btn_no.text = "✕ CANCELAR"
	btn_no.custom_minimum_size = Vector2(140, 36)
	btn_no.pressed.connect(func(): modal.queue_free())
	btns.add_child(btn_no)
	var btn_yes := Button.new()
	btn_yes.text = "✓ CONFIRMAR"
	btn_yes.custom_minimum_size = Vector2(140, 36)
	btn_yes.modulate = Color(1, 0.7, 0.7)
	btn_yes.pressed.connect(func():
		modal.queue_free()
		on_confirm.call())
	btns.add_child(btn_yes)
	_fade_in(modal)

func _add_language_selector() -> void:
	var button_row := get_node_or_null("Center/Card/MainBox/ButtonRow")
	if button_row == null: return
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(420, 0)
	button_row.add_child(box)
	var lbl := Label.new()
	lbl.text = "🌐"
	lbl.add_theme_font_size_override("font_size", 14)
	box.add_child(lbl)
	for loc in Accessibility.SUPPORTED_LOCALES:
		var label_text: String = "PT" if loc == "pt_BR" else loc.to_upper()
		var btn := Button.new()
		btn.text = label_text
		btn.toggle_mode = true
		btn.button_pressed = (Accessibility.locale == loc)
		btn.custom_minimum_size = Vector2(64, 28)
		btn.add_theme_font_size_override("font_size", 11)
		var ll: String = loc
		btn.pressed.connect(func():
			Accessibility.set_locale(ll)
			get_tree().reload_current_scene())
		box.add_child(btn)

func _add_progression_button() -> void:
	var button_row := get_node_or_null("Center/Card/MainBox/ButtonRow")
	if button_row == null: return
	var btn := Button.new()
	var xp: int = 0
	if GameEngine and GameEngine.meta_progression:
		xp = GameEngine.meta_progression.total_xp
	btn.text = "⭐ PROGRESSO  (%d XP)" % xp
	btn.custom_minimum_size = Vector2(420, 32)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_show_progression_modal)
	button_row.add_child(btn)

func _show_progression_modal() -> void:
	if GameEngine == null or GameEngine.meta_progression == null:
		return
	var meta = GameEngine.meta_progression
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 100
	add_child(modal)
	var bg := ColorRect.new()
	bg.color = Color(0, 0.04, 0.08, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(bg)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			modal.queue_free())
	# Card central
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(720, 640)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.06, 0.10, 0.99)
	sb.border_color = Color(1, 0.85, 0.2, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	# Título
	var title := Label.new()
	title.text = "⭐ PROGRESSO ENTRE PARTIDAS"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	# Stats globais
	var stats := Label.new()
	stats.text = "XP TOTAL: %d   |   PARTIDAS: %d   |   VITÓRIAS: %d" % [meta.total_xp, meta.lifetime_games, meta.lifetime_wins]
	stats.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
	stats.add_theme_font_size_override("font_size", 12)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats)
	var hint := Label.new()
	hint.text = "Compre perks com XP. Ative até 2 deles antes de iniciar uma partida."
	hint.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85))
	hint.add_theme_font_size_override("font_size", 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	v.add_child(HSeparator.new())
	# Lista de perks (scroll)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 460)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for p in meta.PERK_CATALOG:
		var perk_id: String = String(p.get("id", ""))
		var owned: bool = perk_id in meta.available_perks
		var active: bool = perk_id in meta.active_perks
		var cost: int = int(p.get("cost", 0))
		var row := PanelContainer.new()
		var rsb := StyleBoxFlat.new()
		if active:
			rsb.bg_color = Color(0.08, 0.15, 0.05, 0.95)
			rsb.border_color = Color(0.4, 1, 0.5, 0.85)
		elif owned:
			rsb.bg_color = Color(0.06, 0.10, 0.16, 0.95)
			rsb.border_color = Color(0, 0.7, 1, 0.6)
		else:
			rsb.bg_color = Color(0.05, 0.06, 0.10, 0.95)
			rsb.border_color = Color(0.4, 0.4, 0.5, 0.5)
		rsb.set_border_width_all(1)
		rsb.set_corner_radius_all(8)
		rsb.content_margin_left = 12
		rsb.content_margin_right = 12
		rsb.content_margin_top = 8
		rsb.content_margin_bottom = 8
		row.add_theme_stylebox_override("panel", rsb)
		list.add_child(row)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)
		# Texto
		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.add_theme_constant_override("separation", 2)
		hb.add_child(info_box)
		var nm := Label.new()
		var prefix: String = ("✅ ATIVO  " if active else ("◆ "+ ("DESBLOQUEADO  " if owned else "BLOQUEADO  ")))
		nm.text = prefix + String(p.get("name", "?"))
		nm.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if active else (Color(0.85, 0.95, 1) if owned else Color(0.55, 0.65, 0.78)))
		nm.add_theme_font_size_override("font_size", 13)
		info_box.add_child(nm)
		var desc := Label.new()
		desc.text = String(p.get("description", ""))
		desc.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		desc.add_theme_font_size_override("font_size", 11)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(desc)
		var meta_lbl := Label.new()
		meta_lbl.text = "Categoria: %s  |  Custo: %d XP" % [String(p.get("category", "?")), cost]
		meta_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75))
		meta_lbl.add_theme_font_size_override("font_size", 10)
		info_box.add_child(meta_lbl)
		# Botão ação
		var btn_action := Button.new()
		btn_action.custom_minimum_size = Vector2(140, 64)
		btn_action.add_theme_font_size_override("font_size", 11)
		if not owned:
			btn_action.text = "💰 COMPRAR\n(%d XP)" % cost
			btn_action.disabled = meta.total_xp < cost
			var pid := perk_id
			btn_action.pressed.connect(func():
				var res: Dictionary = meta.purchase_perk(pid)
				modal.queue_free()
				_show_progression_modal()
				if not bool(res.get("ok", false)):
					push_warning("[META] Falha: " + String(res.get("reason", ""))))
		else:
			if active:
				btn_action.text = "⛔ DESATIVAR"
			else:
				btn_action.text = "▶ ATIVAR\n(%d/2)" % meta.active_perks.size()
				btn_action.disabled = meta.active_perks.size() >= 2
			var pid2 := perk_id
			btn_action.pressed.connect(func():
				var res: Dictionary = meta.toggle_active_perk(pid2)
				modal.queue_free()
				_show_progression_modal()
				if not bool(res.get("ok", false)):
					push_warning("[META] Falha: " + String(res.get("reason", ""))))
		hb.add_child(btn_action)
	v.add_child(HSeparator.new())
	var close_btn := Button.new()
	close_btn.text = "✕ FECHAR"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(func(): modal.queue_free())
	v.add_child(close_btn)
	_fade_in(modal)

func _add_credits_button() -> void:
	var button_row := get_node_or_null("Center/Card/MainBox/ButtonRow")
	if button_row == null: return
	var btn := Button.new()
	btn.text = tr("ui.menu.credits")
	btn.custom_minimum_size = Vector2(420, 32)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_show_credits_modal)
	button_row.add_child(btn)

func _show_credits_modal() -> void:
	# Cria overlay simples cobrindo a tela
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 100
	add_child(modal)
	var bg := ColorRect.new()
	bg.color = Color(0, 0.04, 0.08, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(bg)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			modal.queue_free())
	# Card central
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(620, 580)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.06, 0.10, 0.99)
	sb.border_color = Color(0, 0.823, 1, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	# Título
	var title := Label.new()
	title.text = "📜 CRÉDITOS"
	title.add_theme_color_override("font_color", Color(0, 0.95, 1))
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "WORLD ORDER v0.5.0"
	sub.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85))
	sub.add_theme_font_size_override("font_size", 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())
	var sections := [
		{"title": "DESENVOLVIMENTO", "items": [
			"Matheus Lopes — design, código, direção criativa",
			"Claude (Anthropic) — pair programming, GDScript, integração de sistemas"
		]},
		{"title": "ENGINE & FERRAMENTAS", "items": [
			"Godot Engine 4.6 — open source",
			"GDScript — linguagem de scripting",
			"Vulkan / Forward+ — renderização"
		]},
		{"title": "DADOS & CONTEÚDO", "items": [
			"Banco Mundial — dados de PIB e demografia 2000",
			"Wikipedia — eventos históricos 2000-2024",
			"Natural Earth Data — geometria dos países"
		]},
		{"title": "FONTES", "items": [
			"Cascadia Mono (Microsoft) — texto monoespaçado",
			"Segoe UI (Microsoft) — texto principal",
			"Segoe UI Emoji — ícones e bandeiras"
		]},
		{"title": "AGRADECIMENTOS", "items": [
			"Comunidade Godot pela documentação e exemplos",
			"Você, jogador, por embarcar nessa simulação de 100 anos"
		]},
	]
	for sec in sections:
		var sec_title := Label.new()
		sec_title.text = "◆ " + String(sec["title"])
		sec_title.add_theme_color_override("font_color", Color(0, 0.823, 1, 0.85))
		sec_title.add_theme_font_size_override("font_size", 11)
		v.add_child(sec_title)
		for item in sec["items"]:
			var lbl := Label.new()
			lbl.text = "  " + String(item)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(lbl)
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 4)
		v.add_child(sp)
	v.add_child(HSeparator.new())
	# Botão de rever intro
	var intro_btn := Button.new()
	intro_btn.text = "🎬 REVER INTRO CINEMATOGRÁFICA"
	intro_btn.custom_minimum_size = Vector2(0, 36)
	intro_btn.pressed.connect(func():
		modal.queue_free()
		_maybe_show_intro_lore(true))
	v.add_child(intro_btn)
	# Botão fechar
	var close_btn := Button.new()
	close_btn.text = "✕ FECHAR"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(func(): modal.queue_free())
	v.add_child(close_btn)
	_fade_in(modal)

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
	_fade_in(ov, 0.18)

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
