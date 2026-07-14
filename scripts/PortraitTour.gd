extends Control
## Harness visual do PortraitGen: grade nações × papéis + linha de expressões.
## Roda COM janela (screenshot precisa de renderização):
##   Godot_v4.6.2-stable_win64_console.exe --path . res://scenes/PortraitTour.tscn
## Salva user://portrait_tour.png e sai.

const NATIONS := ["BR", "US", "NG", "JP", "IN", "SA", "SE", "FJ", "MX", "EG"]
const ROLES := ["presidente", "casa_civil", "economia", "seguranca", "saude", "educacao", "chanceler", "ancora"]
const EXPRS := ["neutro", "feliz", "preocupado", "bravo", "urgente"]
const CELL := 84.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0e1116")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# grade: linhas = nações, colunas = papéis
	for r in NATIONS.size():
		var lbl := Label.new()
		lbl.text = NATIONS[r]
		lbl.position = Vector2(8, 40 + r * (CELL * 1.2 + 4) + CELL * 0.5)
		add_child(lbl)
		for c in ROLES.size():
			var pv := PortraitView.make(NATIONS[r], ROLES[c], "neutro", CELL)
			pv.position = Vector2(48 + c * (CELL + 6), 36 + r * (CELL * 1.2 + 4))
			pv.size = Vector2(CELL, CELL * 1.2)
			add_child(pv)
	for c in ROLES.size():
		var h := Label.new()
		h.text = ROLES[c]
		h.position = Vector2(48 + c * (CELL + 6) + 14, 8)
		add_child(h)

	# coluna extra: expressões do min. segurança BR
	var ex_x := 48 + ROLES.size() * (CELL + 6) + 30
	var he := Label.new()
	he.text = "expressões (BR seguranca)"
	he.position = Vector2(ex_x, 8)
	add_child(he)
	for i in EXPRS.size():
		var pv2 := PortraitView.make("BR", "seguranca", EXPRS[i], CELL)
		pv2.position = Vector2(ex_x, 36 + i * (CELL * 1.2 + 4))
		pv2.size = Vector2(CELL, CELL * 1.2)
		add_child(pv2)
		var le := Label.new()
		le.text = EXPRS[i]
		le.position = Vector2(ex_x + CELL + 6, 36 + i * (CELL * 1.2 + 4) + CELL * 0.5)
		add_child(le)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://portrait_tour.png")
	print("PORTRAIT_TOUR_OK — salvo em %s/portrait_tour.png" % OS.get_user_data_dir())
	get_tree().quit(0)
