extends Node
## Teste automatizado de amarração dos sistemas (headless).
##
## Roda com:
##   Godot_v4.6.2-stable_win64_console.exe --headless --path . res://scenes/SystemsCheck.tscn
##
## Exercita: dados, catálogo central de ações, limite de ações/turno,
## tech, turnos, cap de tesouro, BotPlayer, perks, save/load, espionagem, áudio.
## Sai com exit code 0 (PASS) ou 1 (FAIL).
##
## Protege os arquivos reais do usuário (save/achievements) com backup/restore.

var fails: int = 0
var checks: int = 0
var _backups: Dictionary = {}  # path → bytes (ou null se não existia)

const PROTECTED := ["user://world_order_save.json", "user://achievements.json"]

func _ready() -> void:
	await get_tree().process_frame
	_backup_user_files()
	_run()
	_restore_user_files()
	print("──────────────────────────────")
	if fails == 0:
		print("✅ SYSTEMS CHECK PASS — %d checks OK" % checks)
	else:
		printerr("❌ SYSTEMS CHECK FAIL — %d/%d checks falharam" % [fails, checks])
	get_tree().quit(1 if fails > 0 else 0)

func _check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  ✓ %s" % label)
	else:
		fails += 1
		printerr("  ✗ FALHOU: %s" % label)

func _run() -> void:
	print("\n══════════ SYSTEMS CHECK ══════════")
	var E = GameEngine

	# ── 0. Compilação de TODOS os scripts do projeto ──
	print("[0] Compilação de scripts")
	var sdir := DirAccess.open("res://scripts")
	var bad: Array = []
	var n_scripts: int = 0
	if sdir != null:
		for f in sdir.get_files():
			if f.ends_with(".gd"):
				n_scripts += 1
				var s = load("res://scripts/" + f)
				if s == null or not s.can_instantiate():
					bad.append(f)
	_check(bad.is_empty(), "%d scripts compilam sem erro%s" % [n_scripts, "" if bad.is_empty() else " — ERROS: %s" % str(bad)])

	# ── 1. Dados ──
	print("[1] Carga de dados")
	_check(E.nations.size() >= 190, "nações carregadas: %d" % E.nations.size())
	_check(E.tech != null and E.tech.tech_index.size() >= 50, "tech index: %d techs" % E.tech.tech_index.size())
	_check(E.events_data.size() > 0, "eventos: %d" % E.events_data.size())
	_check(E.timeline != null and E.timeline.pending_events.size() > 100, "timeline: %d eventos (âncora+secundários)" % E.timeline.pending_events.size())
	_check(E.scenarios_data.size() >= 5, "cenários: %d" % E.scenarios_data.size())

	# ── 2. Assumir comando ──
	print("[2] Seleção de nação")
	if E.meta_progression:
		E.meta_progression.active_perks = []  # isola o teste de perks reais do usuário
	E.confirm_player_nation("BR")
	_check(E.player_nation != null and E.player_nation.codigo_iso == "BR", "confirm_player_nation(BR)")
	_check(E.game_state == "PLAYING", "game_state = PLAYING")
	_check(E.player_actions_remaining == E.PLAYER_ACTIONS_PER_TURN, "ações iniciais: %d" % E.player_actions_remaining)

	# ── 3. Catálogo central de ações ──
	print("[3] Catálogo central de ações (PANEL_ACTIONS)")
	_check(E.get_panel_actions("governo").size() == 9, "9 ações de governo (inclui aperto monetário)")
	_check(E.get_panel_actions("militar").size() == 6, "6 ações militares")
	_check(E.get_panel_actions("economia").size() == 4, "4 ações econômicas")
	var apoio_antes: float = E.player_nation.apoio_popular
	var r1: Dictionary = E.player_panel_action("propaganda")
	_check(r1.get("ok", false), "propaganda executou: %s" % r1.get("msg", ""))
	_check(E.player_nation.apoio_popular > apoio_antes, "apoio subiu (%.1f → %.1f)" % [apoio_antes, E.player_nation.apoio_popular])
	E.player_panel_action("investir_saude")
	E.player_panel_action("investir_previdencia")
	var r4: Dictionary = E.player_panel_action("propaganda")
	_check(not r4.get("ok", true), "4ª ação negada (limite 3/turno): %s" % r4.get("reason", ""))
	var r5: Dictionary = E.player_panel_action("acao_inexistente")
	_check(not r5.get("ok", true), "ação desconhecida negada")

	# ── 4. Tech ──
	print("[4] Pesquisa tecnológica")
	var avail: Array = E.tech.get_available_techs(E.player_nation)
	_check(avail.size() > 0, "get_available_techs: %d disponíveis" % avail.size())
	E.end_turn()  # reseta ações
	_check(E.player_actions_remaining == E.PLAYER_ACTIONS_PER_TURN, "ações resetadas após end_turn")
	if avail.size() > 0:
		var rres: Dictionary = E.player_start_research(String(avail[0].get("id", "")))
		_check(rres.get("ok", false), "start_research('%s')" % avail[0].get("nome", "?"))
		_check(E.player_nation.pesquisa_atual != null, "pesquisa_atual registrada")

	# ── 5. Turnos em lote ──
	print("[5] Simulação de turnos")
	var t0 := Time.get_ticks_msec()
	for i in 12:
		E.end_turn()
	var dt := Time.get_ticks_msec() - t0
	_check(E.current_turn >= 13, "12 turnos processados (turno atual: %d)" % E.current_turn)
	_check(dt < 12000, "performance: 12 turnos em %d ms" % dt)
	_check(E.player_nation.tesouro >= 0.0, "tesouro não-negativo: $%.0fB" % E.player_nation.tesouro)
	_check(E.player_nation.pib_bilhoes_usd > 0.0, "PIB positivo")

	# ── 5b. Ranking de poder global (base das novas vitórias) ──
	print("[5b] Ranking de poder global")
	E._refresh_world_maxima()
	var us_rank: int = E.get_power_rank("US")
	_check(us_rank == 1, "EUA é a potência #1 no início do século (rank %d)" % us_rank)
	var player_rank: int = E.get_power_rank("BR")
	_check(player_rank > 1 and player_rank < 60, "Brasil em posição intermediária (rank %d)" % player_rank)

	# ── 6. Cap de tesouro com piso (nações pequenas) ──
	print("[6] Cap de tesouro")
	var small = null
	for c in E.nations:
		if E.nations[c].pib_bilhoes_usd < 20.0 and E.nations[c].pib_bilhoes_usd > 1.0:
			small = E.nations[c]
			break
	if small != null:
		small.tesouro = 500.0
		small.process_turn_finances()
		_check(small.tesouro >= 100.0, "piso do cap preserva tesouro de nação pequena (%s: $%.0fB, PIB $%.0fB)" % [small.nome, small.tesouro, small.pib_bilhoes_usd])
	else:
		_check(true, "nenhuma nação pequena p/ testar cap (skip)")

	# ── 7. BotPlayer (árvore de decisão + execução via API central) ──
	print("[7] BotPlayer")
	var bot = load("res://scripts/BotPlayer.gd").new(E, get_tree(), "balanced")
	var best: Dictionary = bot._choose_best_action()
	_check(not best.is_empty(), "bot escolheu: %s" % best.get("reason", "?"))
	if best.get("type", "") == "panel_action":
		_check(E.PANEL_ACTIONS.has(String(best.get("action", ""))), "ação do bot existe no catálogo central")
	var executed: bool = bot._execute_action(best)
	_check(executed, "bot executou a ação escolhida")
	# gera candidatos de todas as categorias sem crash
	var n_cand: int = 0
	n_cand += bot._generate_economy_actions(E.player_nation).size()
	n_cand += bot._generate_social_actions(E.player_nation).size()
	n_cand += bot._generate_tech_actions(E.player_nation).size()
	n_cand += bot._generate_diplomacy_actions(E.player_nation).size()
	n_cand += bot._generate_military_actions(E.player_nation).size()
	n_cand += bot._generate_trade_actions(E.player_nation).size()
	_check(n_cand > 0, "geradores do bot produzem candidatos: %d" % n_cand)

	# ── 8. Perks de meta-progressão (amarração completa) ──
	print("[8] Perks")
	var mp = E.meta_progression
	if mp != null:
		for p in mp.PERK_CATALOG:
			mp._apply_perk_effects(E.player_nation, p.get("effects", {}))
		_check(int(E.player_nation.get_meta("perk_extra_actions", 0)) >= 1, "meta perk_extra_actions gravado")
		_check(float(E.player_nation.get_meta("perk_inflation_decay", 0)) > 0.0, "meta perk_inflation_decay gravado")
		_check(int(E.player_nation.get_meta("perk_honeymoon_extra", 0)) > 0, "meta perk_honeymoon_extra gravado")
		E.end_turn()
		_check(E.player_actions_remaining == E.PLAYER_ACTIONS_PER_TURN + 1, "+1 ação PERSISTE após end_turn (%d)" % E.player_actions_remaining)

	# ── 9. Diplomacia + Espionagem ──
	print("[9] Diplomacia & Espionagem")
	var prop: Dictionary = E.player_propose_treaty("AR", "livre_comercio")
	_check(not prop.is_empty() and prop.get("ok", true) != false, "propor tratado a AR")
	E.player_nation.tesouro = max(E.player_nation.tesouro, 200.0)
	var spy: Dictionary = E.player_execute_spy("campanha_desinformacao", "AR")
	_check(spy.get("ok", false), "operação de espionagem executa: %s" % spy.get("msg", ""))

	# ── 10. Save / Load ──
	print("[10] Save/Load")
	var SaveSys = load("res://scripts/SaveSystem.gd")
	_check(SaveSys.save_game(E), "save_game")
	var turn_saved: int = E.current_turn
	_check(SaveSys.load_game(E), "load_game")
	_check(E.current_turn == turn_saved, "turno preservado no ciclo save→load")

	# ── 11. Áudio ──
	print("[11] AudioManager")
	_check(AudioManager._sfx.size() == AudioManager.SFX_NAMES.size(), "%d SFX prontos (síntese procedural)" % AudioManager._sfx.size())
	AudioManager.play("click")
	AudioManager.play("achievement")
	_check(true, "play() não crasha em headless")

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
			# Não existia antes — remove o que o teste criou
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(data)
				f.close()
	print("[TEST] Arquivos user:// restaurados (save real preservado)")
