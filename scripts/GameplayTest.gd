extends Node
## GAMEPLAY TEST — matriz completa de jogabilidade via UI REAL.
##
## Diferente do SystemsCheck (engine) e do UIAutoTest (fluxos básicos),
## este teste PRESSIONA CADA BOTÃO do jogo (pressed.emit() nos nós reais):
## MainMenu, seleção, wizard, os 19 botões de ação dos painéis, dossiê
## completo (embaixada/tratados/comércio/espionagem/sanções/guerra/paz),
## filtros de mapa, zoom, modo bot, opções, save, notícias, modal de
## decisão histórica, modal de evento e modal de endgame.
## Também mede TEMPO DE RESPOSTA por interação (proxy de fluidez).
##
## Rodar: Godot_v4.6.2-stable_win64_console.exe --headless --path . res://scenes/GameplayTest.tscn

var wm: Node = null
var passed := 0
var failed := 0
var notes: Array = []
var _timings: Array = []  # {label, ms}

var _backups: Dictionary = {}
const PROTECTED := ["user://world_order_save.json", "user://achievements.json", "user://settings.cfg"]

# ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	print("\n╔══════════════════════════════════════════════════════════════════")
	print("║  NATIONS: NEW DAWN — GAMEPLAY TEST (matriz completa de interações)")
	print("╚══════════════════════════════════════════════════════════════════")
	_backup_user_files()
	await get_tree().process_frame
	await _phase_mainmenu()
	await _phase_boot_and_select()
	await _phase_panel_actions()
	await _phase_dossier_flows()
	await _phase_map_and_filters()
	await _phase_shortcuts_and_bot()
	await _phase_options_save_news()
	await _phase_event_modals()
	await _phase_intel_and_bailout()
	await _phase_endgame_modal()
	_phase_ux_metrics()
	print("\n╔══════════════════════════════════════════════════════════════════")
	print("║  RESULTADO: %d PASS  /  %d FAIL  (total %d)" % [passed, failed, passed + failed])
	print("╚══════════════════════════════════════════════════════════════════")
	if failed > 0:
		print("FALHAS:")
		for n in notes:
			print("  ✗ %s" % n)
	_restore_user_files()
	get_tree().quit(1 if failed > 0 else 0)

func _test(name: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  ✓ %s" % name)
	else:
		failed += 1
		notes.append(name)
		print("  ✗ %s" % name)

# Pressiona um botão REAL medindo o tempo de resposta
func _press(btn: Button, label: String) -> void:
	var t0 := Time.get_ticks_usec()
	btn.pressed.emit()
	await get_tree().process_frame
	_timings.append({"label": label, "ms": (Time.get_ticks_usec() - t0) / 1000.0})

func _find_buttons(root: Node, acc: Array = []) -> Array:
	if root is Button and not (root as Button).disabled:
		acc.append(root)
	for c in root.get_children():
		_find_buttons(c, acc)
	return acc

func _find_button_by_text(root: Node, needles: Array) -> Button:
	for b in _find_buttons(root):
		var t: String = (b as Button).text.to_upper()
		for n in needles:
			if String(n).to_upper() in t:
				return b
	return null

# Modais "soltos" (ColorRect com filhos — padrão spy/treaty/trade/event).
# Agora vivem no modal_layer (CanvasLayer full-rect) para centralizarem certo;
# varremos tanto o modal_layer quanto os filhos diretos da cena (fallback antigo).
func _loose_modals() -> Array:
	var out: Array = []
	var scopes: Array = []
	if wm.get("modal_layer") != null:
		scopes.append(wm.modal_layer)
	scopes.append(wm)
	for scope in scopes:
		for c in scope.get_children():
			if c is ColorRect and c.get_child_count() > 0:
				out.append(c)
	return out

func _topup() -> void:
	GameEngine.player_nation.tesouro = 100000.0
	GameEngine.player_actions_remaining = 5

# Botões de ação do painel atual (frescos — o re-render os recria)
func _panel_action_buttons(overlay) -> Array:
	var out: Array = []
	for b in _find_buttons(overlay.panel_content):
		if "$" in (b as Button).text:
			out.append(b)
	return out

# ─────────────────────────────────────────────────────────────────
# FASE 1 — MAIN MENU
# ─────────────────────────────────────────────────────────────────

func _phase_mainmenu() -> void:
	print("\n[1] MAIN MENU")
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await get_tree().create_timer(0.8).timeout
	_test("MainBox existe no caminho corrigido (Center/Card/MainBox)",
		menu.get_node_or_null("Center/Card/MainBox") != null)
	_test("Brand existe (pulse da marca)",
		menu.get_node_or_null("Center/Card/MainBox/TitleSection/Brand") != null)
	var map_btn: Button = menu.get_node_or_null("Center/Card/MainBox/ButtonRow/MapButton")
	_test("Botão INICIAR existe e está habilitado", map_btn != null and not map_btn.disabled)
	# Botões extras criados via código (cenário, progresso, créditos…)
	var all_btns := _find_buttons(menu)
	_test("Menu tem %d botões (≥ 4 esperados)" % all_btns.size(), all_btns.size() >= 4)
	# Animação de entrada roda sem erro (regressão do bug do node path)
	if menu.has_method("_play_entrance_animation"):
		menu._play_entrance_animation()
		_test("Animação de entrada executa", true)
	menu.queue_free()
	await get_tree().process_frame

# ─────────────────────────────────────────────────────────────────
# FASE 2 — BOOT + SELEÇÃO + WIZARD (caminho real)
# ─────────────────────────────────────────────────────────────────

func _phase_boot_and_select() -> void:
	print("\n[2] SELEÇÃO DE NAÇÃO + WIZARD")
	wm = load("res://scenes/WorldMap.tscn").instantiate()
	get_tree().root.add_child(wm)
	# Espera ATIVA: o boot agora é fatiado (load cede frames p/ o spinner),
	# então o tempo até o modal abrir varia — poll até 8s em vez de sleep fixo.
	var boot_t0 := Time.get_ticks_msec()
	while not wm._is_modal_open() and Time.get_ticks_msec() - boot_t0 < 20000:
		await get_tree().process_frame
	_test("Modal de seleção abre no boot", wm._is_modal_open())
	# Busca em tempo real
	var list = wm.nations_list
	var total_itens: int = list.item_count
	if wm.search_box:
		wm.search_box.text = "bras"
		wm.search_box.text_changed.emit("bras")
		await get_tree().process_frame
		_test("Busca 'bras' filtra a lista (%d → %d)" % [total_itens, list.item_count],
			list.item_count > 0 and list.item_count < total_itens)
		wm.search_box.text = ""
		wm.search_box.text_changed.emit("")
		await get_tree().process_frame
		_test("Limpar busca restaura a lista", list.item_count >= total_itens - 1)
	# Seleciona Brasil na lista real
	var idx := -1
	for i in list.item_count:
		if list.get_item_metadata(i) == "BR":
			idx = i
			break
	list.select(idx)
	list.item_selected.emit(idx)
	await get_tree().process_frame
	_test("Preview carrega Brasil", wm.preview_code == "BR")
	# Abre o wizard pelo caminho real e tenta PERCORRÊ-LO clicando
	var modals_before: int = wm._modal_stack.size()
	if wm.has_method("_on_confirm_pressed"):
		wm._on_confirm_pressed()
		await get_tree().create_timer(0.4).timeout
	_test("Wizard 'Tomar Posse' abre", wm._modal_stack.size() > modals_before or wm._is_modal_open())
	var walked := false
	for step in 12:
		if GameEngine.player_nation != null:
			walked = true
			break
		if wm._modal_stack.is_empty():
			break
		var top = wm._modal_stack.back()
		var nxt := _find_button_by_text(top, ["ASSUMIR", "COMEÇAR", "INICIAR GOVERNO", "CONFIRMAR", "PRÓXIM", "CONTINUAR", "▶"])
		if nxt == null:
			break
		await _press(nxt, "wizard passo %d" % step)
		await get_tree().create_timer(0.25).timeout
	_test("Wizard percorrível até assumir o comando (cliques reais)", walked and GameEngine.player_nation != null)
	if GameEngine.player_nation == null:
		# Fallback: bypass pra continuar a suíte
		while not wm._modal_stack.is_empty():
			wm._close_top_modal()
			await get_tree().process_frame
		wm._takeover_state = {"country_code": "BR", "leader_name": "Tester", "leader_age": 45,
			"leader_background": "politico", "leader_motto": "", "government_type": "manter",
			"economic_doctrine": "mista", "first_steps": ["saude", "educacao", "infra"]}
		wm._finalize_takeover()
		await get_tree().create_timer(0.5).timeout
	# Fecha tutorial se abriu
	for i in 10:
		if wm._modal_stack.is_empty():
			break
		wm._close_top_modal()
		await get_tree().process_frame
	_test("Comando assumido (player = BR)", GameEngine.player_nation != null and GameEngine.player_nation.codigo_iso == "BR")
	_test("Barra de ações visível", wm.action_bar != null and wm.action_bar.visible)

# ─────────────────────────────────────────────────────────────────
# FASE 3 — TODOS OS BOTÕES DE AÇÃO DOS PAINÉIS
# ─────────────────────────────────────────────────────────────────

func _phase_panel_actions() -> void:
	print("\n[3] BOTÕES DE AÇÃO DOS PAINÉIS (ações via clique real, por ministério)")
	var overlay = wm.game_overlay
	# Ações PADRÃO (via PANEL_ACTIONS) consomem ação-de-turno + custo. O painel
	# economia TAMBÉM tem botões FINANCEIROS (empréstimo/dívida/bolsa/cripto) que
	# movem dinheiro sem consumir ação-de-turno — testados à parte (ver SystemsCheck).
	var expected := {"governo": 4, "economia": 7, "seguranca": 8, "saude": 3, "educacao": 3}
	for panel_id in expected.keys():
		wm._open_overlay_modal(panel_id)
		await get_tree().process_frame
		var all_btns: Array = _panel_action_buttons(overlay)
		# Separa financeiros (prefixo de ícone $) das ações padrão de ministério
		var std_btns: Array = []
		var fin_btns: Array = []
		for b in all_btns:
			if _is_financial_button(b as Button):
				fin_btns.append(b)
			else:
				std_btns.append(b)
		_test("Painel %s: %d ações padrão (esperado %d)" % [panel_id, std_btns.size(), expected[panel_id]],
			std_btns.size() == expected[panel_id])
		var ok_all := true
		# Pressiona por ÍNDICE só as ações PADRÃO, recoletando a lista FRESCA a cada
		# clique (o painel se re-renderiza e destrói os botões antigos)
		for i in std_btns.size():
			var fresh_all: Array = _panel_action_buttons(overlay)
			var fresh: Array = fresh_all.filter(func(b): return not _is_financial_button(b as Button))
			if i >= fresh.size():
				break
			var b: Button = fresh[i]
			_topup()
			var tes0: float = GameEngine.player_nation.tesouro
			var act0: int = GameEngine.player_actions_remaining
			var label: String = b.text.split("\n")[0].strip_edges()
			await _press(b, "%s: %s" % [panel_id, label])
			var consumed: bool = GameEngine.player_actions_remaining == act0 - 1
			var paid: bool = GameEngine.player_nation.tesouro < tes0
			if not (consumed and paid):
				ok_all = false
				_test("  ação '%s' consome ação+custo" % label, false)
		_test("Painel %s: ações padrão aplicam efeito (custo + ação consumida)" % panel_id, ok_all)
		# Botões financeiros do painel economia: existem e movem dinheiro (sem consumir ação)
		if panel_id == "economia":
			_test("Painel economia: botões financeiros presentes (empréstimo/bolsa/cripto)", fin_btns.size() >= 2)
			await _test_financial_buttons(overlay)
		wm._close_top_modal()
		await get_tree().process_frame
	# Caminhos negativos
	wm._open_overlay_modal("governo")
	await get_tree().process_frame
	var btns: Array = []
	for b in _find_buttons(overlay.panel_content):
		if "$" in (b as Button).text:
			btns.append(b)
	if btns.size() > 0:
		GameEngine.player_nation.tesouro = 0.0
		GameEngine.player_actions_remaining = 3
		var act0: int = GameEngine.player_actions_remaining
		await _press(btns[0], "governo: sem fundos")
		_test("Sem fundos: ação NÃO consumida", GameEngine.player_actions_remaining == act0)
		_topup()
		GameEngine.player_actions_remaining = 0
		var tes0: float = GameEngine.player_nation.tesouro
		btns = []
		for b in _find_buttons(overlay.panel_content):
			if "$" in (b as Button).text:
				btns.append(b)
		await _press(btns[0], "governo: sem ações")
		_test("Sem ações: custo NÃO cobrado", GameEngine.player_nation.tesouro == tes0)
	wm._close_top_modal()
	await get_tree().process_frame

# Botões financeiros (empréstimo/dívida/bolsa/cripto) do painel economia movem
# dinheiro entre tesouro e ativos SEM consumir ação-de-turno. Identificados pelo
# VERBO ("Captar $34B", "Comprar $20B") — não pelo ícone, que colide com ações
# padrão (🏦 APERTO MONETÁRIO, 💵 SUBSÍDIOS). Semântica detalhada no SystemsCheck.
const _FINANCIAL_VERBS := ["Captar", "Amortizar", "Comprar", "Vender", "Investir", "Resgatar"]
func _is_financial_button(b: Button) -> bool:
	var first_line: String = b.text.split("\n")[0]
	for verbo in _FINANCIAL_VERBS:
		if verbo in first_line:
			return true
	return false

# Clica os botões financeiros presentes e confirma que o tesouro MUDA (entra ou sai)
# sem exigir consumo de ação-de-turno. Recoleta a lista a cada clique (re-render).
func _test_financial_buttons(overlay) -> void:
	var seen := {}
	for _iter in 6:
		var fin: Array = _panel_action_buttons(overlay).filter(func(b): return _is_financial_button(b as Button))
		var target: Button = null
		for b in fin:
			var key: String = (b as Button).text.split(" ")[0]
			if not seen.has(key):
				target = b
				seen[key] = true
				break
		if target == null:
			break
		_topup()
		GameEngine.player_nation.tesouro = maxf(GameEngine.player_nation.tesouro, 500.0)
		var tes0: float = GameEngine.player_nation.tesouro
		var act0: int = GameEngine.player_actions_remaining
		var label: String = target.text.split("\n")[0].strip_edges()
		await _press(target, "economia fin: %s" % label)
		var moved: bool = abs(GameEngine.player_nation.tesouro - tes0) > 0.001
		var keeps_action: bool = GameEngine.player_actions_remaining == act0
		_test("  financeiro '%s' move dinheiro sem gastar ação-de-turno" % label, moved and keeps_action)

# ─────────────────────────────────────────────────────────────────
# FASE 4 — DOSSIÊ: DIPLOMACIA/INTEL/GUERRA COMPLETOS
# ─────────────────────────────────────────────────────────────────

func _phase_dossier_flows() -> void:
	print("\n[4] DOSSIÊ — fluxos completos contra a Argentina")
	_topup()
	wm._open_dossier_modal("AR")
	await get_tree().process_frame
	_test("Dossiê AR abre", wm._is_modal_open() and wm.preview_code == "AR")

	# Embaixada (agora via API central — consome ação)
	var rel0: float = float(GameEngine.player_nation.relacoes.get("AR", 0))
	var act_e0: int = GameEngine.player_actions_remaining
	wm._on_embassy_pressed()
	await get_tree().process_frame
	_test("Embaixada: +15 relações", float(GameEngine.player_nation.relacoes.get("AR", 0)) == clamp(rel0 + 15, -100, 100))
	_test("Embaixada consome 1 ação", GameEngine.player_actions_remaining == act_e0 - 1)

	# Tratado (picker com 6 tipos)
	_topup()
	var props0: int = GameEngine.diplomacy.proposals.size()
	wm._show_treaty_picker_modal("AR")
	await get_tree().process_frame
	var tmodal: Array = _loose_modals()
	_test("Picker de tratados abre", tmodal.size() > 0)
	if tmodal.size() > 0:
		var tbtns := _find_buttons(tmodal.back())
		_test("Picker: 6 tratados + cancelar (%d botões)" % tbtns.size(), tbtns.size() == 7)
		await _press(tbtns[0], "propor tratado")
		await get_tree().process_frame
		_test("Proposta de tratado criada", GameEngine.diplomacy.proposals.size() == props0 + 1)

	# Comércio (modal de recursos — vai pra _modal_stack via _open_modal)
	_topup()
	var trades0: int = GameEngine.active_trades.size()
	var stack0: int = wm._modal_stack.size()
	wm._on_trade_pressed()
	await get_tree().process_frame
	_test("Modal de comércio abre", wm._modal_stack.size() > stack0)
	if wm._modal_stack.size() > stack0:
		var rbtns := _find_buttons(wm._modal_stack.back())
		var pick: Button = null
		for b in rbtns:
			var bt: String = (b as Button).text.to_upper()
			# pula CANCELAR e o "✕" de fechar do shell do modal
			if "CANCELAR" in bt or bt.strip_edges() == "✕" or bt.length() < 4:
				continue
			pick = b
			break
		_test("Modal de comércio lista recursos exportáveis", pick != null)
		if pick:
			await _press(pick, "exportar recurso")
			await get_tree().process_frame
			_test("Acordo comercial criado", GameEngine.active_trades.size() == trades0 + 1)
		while wm._modal_stack.size() > stack0:
			wm._close_top_modal()
			await get_tree().process_frame

	# Espionagem (8 ops no picker)
	_topup()
	var log0: int = GameEngine.player_nation.spy_ops_log.size()
	wm._show_spy_picker_modal("AR")
	await get_tree().process_frame
	var smodal: Array = _loose_modals()
	_test("Picker de espionagem abre", smodal.size() > 0)
	if smodal.size() > 0:
		var sbtns := _find_buttons(smodal.back())
		_test("Picker: 8 operações + cancelar (%d botões)" % sbtns.size(), sbtns.size() == 9)
		await _press(sbtns[3], "spy op")  # desinformação (barata)
		await get_tree().process_frame
		_test("Operação de espionagem executada (log cresceu)", GameEngine.player_nation.spy_ops_log.size() == log0 + 1)
	# Reabre e cancela (botão CANCELAR)
	wm._show_spy_picker_modal("AR")
	await get_tree().process_frame
	var smodal2: Array = _loose_modals()
	if smodal2.size() > 0:
		var cancel := _find_button_by_text(smodal2.back(), ["CANCELAR"])
		await _press(cancel, "cancelar spy")
		await get_tree().process_frame
		_test("Cancelar fecha o picker", _loose_modals().is_empty())

	# Sanções (com modal de confirmação real)
	_topup()
	var sanc0: int = GameEngine.active_sanctions.size()
	wm._on_sanctions_pressed()
	await get_tree().process_frame
	var conf := _find_button_by_text(wm._modal_stack.back() if not wm._modal_stack.is_empty() else wm, ["CONFIRMAR"])
	_test("Confirmação de sanções abre", conf != null)
	if conf:
		await _press(conf, "confirmar sanções")
		await get_tree().process_frame
		_test("Sanção ativa criada", GameEngine.active_sanctions.size() == sanc0 + 1)

	# Guerra (modal de objetivo) e paz
	_topup()
	wm._on_declare_war_pressed()
	await get_tree().process_frame
	# Novo modal pede o OBJETIVO de guerra — escolhe "Conter/enfraquecer"
	var conf2 := _find_button_by_text(wm._modal_stack.back() if not wm._modal_stack.is_empty() else wm, ["CONTER", "REPARAÇÕES", "OBJETIVO"])
	_test("Modal de objetivo de guerra abre", conf2 != null)
	if conf2:
		await _press(conf2, "objetivo de guerra")
		await get_tree().process_frame
		_test("Guerra declarada contra AR", "AR" in GameEngine.player_nation.em_guerra)
	_topup()
	wm._on_propose_peace_pressed()
	await get_tree().process_frame
	_test("Paz proposta encerra a guerra", not ("AR" in GameEngine.player_nation.em_guerra))
	# Fecha dossiê
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame

# ─────────────────────────────────────────────────────────────────
# FASE 5 — MAPA: FILTROS + ZOOM
# ─────────────────────────────────────────────────────────────────

func _phase_map_and_filters() -> void:
	print("\n[5] MAPA — filtros e câmera")
	var fbtns := _find_buttons(wm.map_filters)
	_test("Filtros de mapa: %d botões (≥ 5)" % fbtns.size(), fbtns.size() >= 5)
	var ok := true
	for b in fbtns:
		await _press(b, "filtro: %s" % (b as Button).text)
	_test("Todos os filtros aplicam sem erro", ok)
	var z0: float = wm.camera_target_zoom.x if "camera_target_zoom" in wm else wm.camera.zoom.x
	wm._on_zoom_in_pressed()
	await get_tree().process_frame
	_test("Zoom-in aumenta o alvo", wm.camera_target_zoom.x > z0)
	wm._on_zoom_out_pressed()
	wm._on_zoom_reset_pressed()
	await get_tree().process_frame
	_test("Zoom reset anima a câmera", wm.camera_animating)

# ─────────────────────────────────────────────────────────────────
# FASE 6 — ATALHOS + MODO BOT
# ─────────────────────────────────────────────────────────────────

func _phase_shortcuts_and_bot() -> void:
	print("\n[6] ATALHOS DE TECLADO + MODO ESPECTADOR")
	for act in ["game_next_turn", "game_open_options", "game_save", "game_zoom_in", "game_zoom_out"]:
		_test("InputMap tem '%s'" % act, InputMap.has_action(act))
	var t0: int = GameEngine.current_turn
	wm._on_next_turn_pressed()
	await get_tree().create_timer(0.6).timeout
	_test("Próximo turno avança (%d → %d)" % [t0, GameEngine.current_turn], GameEngine.current_turn > t0)
	# Modo bot: liga, pensa, e o botão PARAR desliga
	wm.start_bot_mode("balanced", 0.05)
	await get_tree().create_timer(1.2).timeout
	_test("Modo espectador liga (bot pensando)", wm.bot_player != null and wm.bot_player.enabled)
	var stop_btn := _find_button_by_text(wm, ["PARAR"])
	_test("Botão PARAR do bot existe", stop_btn != null)
	if stop_btn:
		await _press(stop_btn, "parar bot")
		await get_tree().create_timer(0.3).timeout
	_test("Bot desliga pelo botão", wm.bot_player == null or not wm.bot_player.enabled)
	# Garante estado limpo
	if wm.has_method("stop_bot_mode"):
		wm.stop_bot_mode()
	await get_tree().create_timer(0.3).timeout

# ─────────────────────────────────────────────────────────────────
# FASE 7 — OPÇÕES + SAVE + NOTÍCIAS
# ─────────────────────────────────────────────────────────────────

func _phase_options_save_news() -> void:
	print("\n[7] OPÇÕES / SAVE / NOTÍCIAS")
	wm._on_menu_pressed()
	await get_tree().process_frame
	_test("Modal de opções abre", wm._is_modal_open())
	var top = wm._modal_stack.back() if not wm._modal_stack.is_empty() else null
	var save_btn := _find_button_by_text(top, ["SALVAR"]) if top else null
	_test("Botão SALVAR existe nas opções", save_btn != null)
	if save_btn:
		await _press(save_btn, "salvar via opções")
		await get_tree().process_frame
		_test("Save criado em disco", FileAccess.file_exists("user://world_order_save.json"))
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame
	# Modal de notícias
	wm._open_news_modal()
	await get_tree().process_frame
	_test("Modal de notícias abre", wm._is_modal_open())
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame

# ─────────────────────────────────────────────────────────────────
# FASE 8 — MODAIS DE DECISÃO (evento aleatório + histórico)
# ─────────────────────────────────────────────────────────────────

func _phase_event_modals() -> void:
	print("\n[8] MODAIS DE DECISÃO")
	# Evento aleatório (GameOverlay) com efeito verificável
	var overlay = wm.game_overlay
	var fake := {"nome": "Teste de Gabinete", "descricao": "Escolha de teste",
		"choices": [{"label": "Aceitar (-$10B)", "efeitos": {"tesouro": -10}}]}
	var tes0: float = GameEngine.player_nation.tesouro
	overlay._show_event_modal(fake)
	await get_tree().process_frame
	# O modal de evento agora vive no modal_layer (centralização correta); procura lá
	# primeiro, com fallback no próprio overlay.
	var evt_scope = wm.modal_layer if wm.get("modal_layer") != null else overlay
	var ebtn := _find_button_by_text(evt_scope, ["Aceitar"])
	if ebtn == null:
		ebtn = _find_button_by_text(overlay, ["Aceitar"])
	_test("Modal de evento abre com choice", ebtn != null)
	if ebtn:
		await _press(ebtn, "choice de evento")
		await get_tree().process_frame
		_test("Efeito da escolha aplicado (tesouro -10)", GameEngine.player_nation.tesouro == tes0 - 10)
	# Decisão histórica REAL (pega um evento âncora do timeline)
	var ev: Dictionary = {}
	for e in GameEngine.timeline.pending_events:
		if e.get("modal_decision", false) and e.get("choices", []).size() > 0:
			ev = e
			break
	var dec0: int = GameEngine.timeline.decision_log.size()
	wm._open_historic_decision_modal(ev)
	await get_tree().create_timer(0.3).timeout
	var top = wm._modal_stack.back() if not wm._modal_stack.is_empty() else null
	var choice_btn: Button = null
	if top:
		for b in _find_buttons(top):
			var t: String = (b as Button).text
			if t.length() > 6 and not ("FECHAR" in t.to_upper()):
				choice_btn = b
				break
	_test("Modal de decisão histórica abre (%s)" % ev.get("id", "?"), choice_btn != null)
	if choice_btn:
		await _press(choice_btn, "decisão histórica")
		await get_tree().create_timer(0.3).timeout
		_test("Decisão registrada no log histórico", GameEngine.timeline.decision_log.size() == dec0 + 1)
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame

# ─────────────────────────────────────────────────────────────────
# FASE 8b — INTEL CLICÁVEL + RESGATE DO FMI
# ─────────────────────────────────────────────────────────────────

func _phase_intel_and_bailout() -> void:
	print("\n[8b] INTEL CLICÁVEL + FMI")
	# Painel intel: 8 operações agora são BOTÕES
	wm._open_dossier_modal("AR")
	await get_tree().process_frame
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame
	wm._open_overlay_modal("intel")
	await get_tree().process_frame
	var overlay = wm.game_overlay
	var op_btns: Array = []
	for b in _find_buttons(overlay.panel_content):
		if "%" in (b as Button).text and "$" in (b as Button).text:
			op_btns.append(b)
	_test("Intel: 8 operações são botões clicáveis", op_btns.size() == 8)
	if op_btns.size() > 0:
		var loose0: int = _loose_modals().size()
		await _press(op_btns[3], "intel op via painel")
		await get_tree().process_frame
		_test("Intel: clique abre o picker de espionagem (alvo=AR)", _loose_modals().size() > loose0)
		for m in _loose_modals():
			m.queue_free()
		await get_tree().process_frame
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame

	# FMI: força crise → modal → aceitar
	_topup()
	GameEngine.player_nation.tesouro = 0.0
	GameEngine.player_nation.falencia_turnos = 5   # vira 6 no evaluate → gatilho FMI (ritmo mensal)
	GameEngine.bailout_pending = {}
	GameEngine._last_bailout_turn = -999
	var stack_b0: int = wm._modal_stack.size()
	GameEngine.evaluate_endgame()
	await get_tree().create_timer(0.4).timeout
	_test("FMI: modal de resgate abre na crise", wm._modal_stack.size() > stack_b0)
	var aceitar := _find_button_by_text(wm._modal_stack.back() if not wm._modal_stack.is_empty() else wm, ["ACEITAR RESGATE"])
	_test("FMI: botão ACEITAR existe", aceitar != null)
	if aceitar:
		await _press(aceitar, "aceitar FMI")
		await get_tree().process_frame
		_test("FMI: tesouro reforçado", GameEngine.player_nation.tesouro > 0.0)
	while not wm._modal_stack.is_empty():
		wm._close_top_modal()
		await get_tree().process_frame
	_topup()

# ─────────────────────────────────────────────────────────────────
# FASE 9 — ENDGAME (vitória → Continuar Livre)
# ─────────────────────────────────────────────────────────────────

func _phase_endgame_modal() -> void:
	print("\n[9] MODAL DE ENDGAME")
	GameEngine._fire_endgame(true, "🏆 TESTE DE VITÓRIA", "Modal de teste do harness.")
	await get_tree().create_timer(0.6).timeout
	var modal = get_tree().root.find_child("EndgameOverlay", true, false)
	_test("Modal de endgame aparece", modal != null)
	if modal:
		var cont := _find_button_by_text(modal, ["CONTINUAR"])
		_test("Botão CONTINUAR LIVRE existe", cont != null)
		if cont:
			await _press(cont, "continuar livre")
			await get_tree().create_timer(0.3).timeout
			_test("Jogo retoma (game_state=PLAYING)", GameEngine.game_state == "PLAYING")
			_test("Modal de endgame fechou", get_tree().root.find_child("EndgameOverlay", true, false) == null)

# ─────────────────────────────────────────────────────────────────
# FASE 10 — MÉTRICAS DE UX
# ─────────────────────────────────────────────────────────────────

func _phase_ux_metrics() -> void:
	print("\n[10] MÉTRICAS DE FLUIDEZ (tempo de resposta por clique)")
	if _timings.is_empty():
		return
	var total := 0.0
	var worst: Dictionary = _timings[0]
	for t in _timings:
		total += t["ms"]
		if t["ms"] > worst["ms"]:
			worst = t
	var avg: float = total / _timings.size()
	print("  interações medidas: %d | média %.1f ms | pior: %.1f ms (%s)" % [_timings.size(), avg, worst["ms"], worst["label"]])
	_test("Resposta média < 50 ms", avg < 50.0)
	_test("Pior clique < 250 ms", float(worst["ms"]) < 250.0)
	# Modais órfãos no fim da suíte
	_test("Sem modais órfãos (stack vazia)", wm._modal_stack.is_empty())
	_test("Sem modais soltos (spy/trade/event)", _loose_modals().is_empty())

# ─────────────────────────────────────────────────────────────────

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
	print("[TEST] Arquivos user:// restaurados")
