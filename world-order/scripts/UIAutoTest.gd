extends Node
## Autoplay test — simula cliques em todos os botões críticos do WorldMap.
## Rode com: Godot --headless res://scenes/UIAutoTest.tscn
## Reporta no stdout cada teste como PASS / FAIL.

const ACTION_BUTTONS := ["governo", "militar", "economia", "diplomacia", "tech", "intel", "situacao", "historico", "noticias"]

var world_map: Node = null
var passed: int = 0
var failed: int = 0
var notes: Array = []

func _ready() -> void:
	print("\n╔══════════════════════════════════════════════════════════════════")
	print("║  WORLD ORDER — UI AUTOPLAY TEST")
	print("╚══════════════════════════════════════════════════════════════════")
	# Aguarda 1 frame antes de manipular tree (Godot bloqueia add_child no _ready do root)
	await get_tree().process_frame
	# Carrega WorldMap como cena raiz
	var packed: PackedScene = load("res://scenes/WorldMap.tscn")
	world_map = packed.instantiate()
	get_tree().root.add_child(world_map)
	# Aguarda inicialização (load + spinner mínimo)
	await get_tree().create_timer(1.2).timeout

	# ─── 1. Modal de seleção de nação deve estar aberto ───
	_test("Modal de seleção aparece ao iniciar", world_map._is_modal_open())

	# ─── 2. Lista de nações populada ───
	var list = world_map.nations_list
	_test("Lista populada com >= 100 itens", list != null and list.item_count >= 100)

	# ─── 3. Selecionar e confirmar uma nação (Brasil) ───
	var brasil_idx: int = -1
	for i in list.item_count:
		if list.get_item_metadata(i) == "BR":
			brasil_idx = i; break
	_test("Brasil encontrado na lista", brasil_idx >= 0)
	if brasil_idx >= 0:
		list.select(brasil_idx)
		list.item_selected.emit(brasil_idx)
		await get_tree().process_frame
		# Verifica preview_code setado
		_test("preview_code virou 'BR' após seleção", world_map.preview_code == "BR")
		# Confirma comando
		world_map._on_confirm_pressed()
		await get_tree().process_frame
		_test("player_code virou 'BR' após confirmar", world_map.player_code == "BR")
		# Modal de seleção fechado
		_test("Modal fechou após confirmar (ou tutorial pode ter aberto)",
			not world_map._is_modal_open() or world_map._modal_stack.size() == 1)
		# Action bar visível
		_test("ActionBar visível", world_map.action_bar.visible)
		_test("NextTurnButton visível", world_map.next_turn_button.visible)

	# Fecha qualquer modal de tutorial
	while not world_map._modal_stack.is_empty():
		world_map._close_top_modal()
		await get_tree().process_frame

	# ─── 4. Cada botão de painel abre o modal correspondente ───
	for panel_id in ACTION_BUTTONS:
		world_map._open_overlay_modal(panel_id)
		await get_tree().process_frame
		_test("Painel '%s' abre modal" % panel_id, world_map._is_modal_open())
		# Mapa deve estar travado quando modal aberto
		var fake_pos := Vector2(get_viewport().get_visible_rect().size.x / 2.0, get_viewport().get_visible_rect().size.y / 2.0)
		_test("  → Mapa travado durante painel '%s'" % panel_id, not world_map._is_in_map_area(fake_pos))
		world_map._close_top_modal()
		await get_tree().process_frame
		_test("  → Painel '%s' fecha corretamente" % panel_id, not world_map._is_modal_open())

	# ─── 5. Botão OPÇÕES abre modal ───
	world_map._on_menu_pressed()
	await get_tree().process_frame
	_test("Botão OPÇÕES abre modal", world_map._is_modal_open())
	world_map._close_top_modal()
	await get_tree().process_frame

	# ─── 6. Próximo turno avança ───
	var t0: int = GameEngine.current_turn
	world_map._on_next_turn_pressed()
	await get_tree().create_timer(0.5).timeout  # spinner mínimo + processamento
	_test("Próximo turno avançou", GameEngine.current_turn > t0)

	# ─── 7. Click em país abre dossiê modal ───
	world_map._open_dossier_modal("US")
	await get_tree().process_frame
	_test("Dossiê de US abre como modal", world_map._is_modal_open())
	_test("PreviewName atualizado para Estados Unidos",
		world_map.preview_name.text == GameEngine.nations["US"].nome)
	world_map._close_top_modal()
	await get_tree().process_frame

	# ─── 8. Zoom buttons funcionam ───
	var zoom_before: float = world_map.camera.zoom.x
	world_map._on_zoom_in_pressed()
	await get_tree().process_frame
	_test("ZoomIn aumentou zoom", world_map.camera_target_zoom.x > zoom_before)

	world_map._on_zoom_reset_pressed()
	await get_tree().process_frame
	# Zoom reset deve ter setado um target diferente do atual
	_test("ZoomReset setou novo target", world_map.camera_animating)

	# ─── RESUMO ───
	print("\n╔══════════════════════════════════════════════════════════════════")
	print("║  RESULTADO: %d PASS  /  %d FAIL  (total %d)" % [passed, failed, passed + failed])
	print("╚══════════════════════════════════════════════════════════════════")
	if failed > 0:
		print("\nFALHAS:")
		for n in notes:
			print("  ✗ %s" % n)
	get_tree().quit(0 if failed == 0 else 1)

func _test(name: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  ✓ %s" % name)
	else:
		failed += 1
		notes.append(name)
		print("  ✗ %s" % name)
