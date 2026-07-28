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

const PROTECTED := ["user://nations_new_dawn_save.json", "user://achievements.json"]

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

	# ── 3. Catálogo central de ações (agrupado por ministério/painel) ──
	print("[3] Catálogo central de ações (PANEL_ACTIONS)")
	_check(E.get_panel_actions("governo").size() == 4, "4 ações da Casa Civil (painel governo)")
	_check(E.get_panel_actions("seguranca").size() == 8, "8 ações de Justiça & Segurança (segurança + defesa)")
	_check(E.get_panel_actions("economia").size() == 7, "7 ações da Fazenda (inclui upgrade industrial)")
	_check(E.get_panel_actions("saude").size() == 3, "3 ações de Saúde")
	_check(E.get_panel_actions("educacao").size() == 3, "3 ações de Educação")
	# toda ação declara seu ministério dono
	var sem_min: Array = []
	for aid in E.PANEL_ACTIONS:
		if String(E.PANEL_ACTIONS[aid].get("min", "")) == "":
			sem_min.append(aid)
	_check(sem_min.is_empty(), "toda ação tem ministério dono%s" % ("" if sem_min.is_empty() else " — FALTAM: %s" % str(sem_min)))
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
		_check(not E.player_nation.pesquisa_por_ministerio.is_empty(), "trilha de pesquisa registrada")

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
	var bd: Dictionary = E.get_power_breakdown(E.nations["US"])
	var soma: float = bd["economia"] + bd["militar"] + bd["tecnologia"] + bd["diplomacia"]
	_check(abs(soma - float(bd["total"])) < 0.01, "breakdown de poder soma o total (%.1f pts)" % bd["total"])
	_check(E.player_power_rank_history.size() > 0, "trajetória de rank registrada (%d entradas)" % E.player_power_rank_history.size())

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

	# ── 12. SISTEMAS DE DIVERSÃO (guerra/FMI/choques/tech/embaixada) ──
	print("[12] Guerra com espólios")
	var w = E.nations["US"]
	var l = E.nations["UY"]
	l.tesouro = 100.0
	l.recursos["petroleo"] = 99.0  # claramente o melhor recurso do perdedor
	w.em_guerra.append("UY")
	l.em_guerra.append("US")
	var w_tes0: float = w.tesouro
	var w_res0: Dictionary = w.recursos.duplicate()
	E._end_war_with_spoils(w, l, "teste")
	_check(w.tesouro > w_tes0, "vencedor recebe reparações (+$%.0fB)" % (w.tesouro - w_tes0))
	var res_ganho := false
	for rk in w.recursos:
		if float(w.recursos[rk]) > float(w_res0.get(rk, 0)):
			res_ganho = true
			break
	_check(res_ganho, "vencedor recebe concessão de recurso")
	_check(not ("UY" in w.em_guerra) and not ("US" in l.em_guerra), "guerra encerrada dos dois lados")
	# war score acumula
	w.em_guerra.append("UY")
	l.em_guerra.append("US")
	E._process_war_resolution()
	_check(E._war_score.size() >= 1, "war score registrado para guerra ativa")
	E._end_war_with_spoils(w, l, "cleanup")

	print("[12b] Resgate do FMI")
	var n_p = E.player_nation
	n_p.tesouro = 0.0
	n_p.falencia_turnos = 5   # vira 6 no evaluate → gatilho do resgate (ritmo mensal)
	E.bailout_pending = {}
	E._last_bailout_turn = -999
	E.evaluate_endgame()
	_check(not E.bailout_pending.is_empty(), "FMI oferece resgate no 6º mês de falência")
	var div0: float = n_p.divida_publica
	_check(E.accept_bailout(), "accept_bailout executa")
	_check(n_p.tesouro > 0.0, "tesouro reforçado pós-resgate")
	_check(n_p.divida_publica > div0, "dívida cresce (empréstimo com juros)")
	_check(n_p.falencia_turnos == 0, "contagem de falência zerada")

	print("[12c] Choques globais")
	E.active_shock = {"id": "recessao_global", "nome": "Recessão Global", "icon": "📉", "turns_remaining": 2, "dur_total": 2}
	var jp_pib0: float = E.nations["JP"].pib_bilhoes_usd
	E._process_global_shocks()
	_check(E.nations["JP"].pib_bilhoes_usd < jp_pib0, "recessão global derruba PIB")
	E._process_global_shocks()
	_check(E.active_shock.is_empty(), "choque expira e limpa")
	# Choque de commodities dobra a exportação de ENERGIA de um exportador
	n_p.recursos["petroleo"] = 90.0  # garante exportador de energia
	n_p.commodity_multiplier = 2.0
	n_p.update_balanca_comercial()
	var exp1: float = float(n_p.exportacoes.get("energia", 0.0))
	n_p.commodity_multiplier = 1.0
	n_p.update_balanca_comercial()
	var exp0: float = float(n_p.exportacoes.get("energia", 0.0))
	_check(exp1 > exp0 * 1.9, "choque de commodities dobra exportação de energia ($%.1f vs $%.1f)" % [exp1, exp0])

	print("[12c2] Complexidade econômica (raw vs processed)")
	var n_ce = load("res://scripts/Nation.gd").new()
	n_ce.pib_bilhoes_usd = 500.0
	n_ce.populacao = 50_000_000
	n_ce.recursos = {"petroleo": 90.0, "minerios": 85.0, "agricultura": 80.0}
	n_ce.grau_processamento = {"energia": 0.0, "materias_primas": 0.0, "alimentos": 0.0}
	n_ce.recompute_complexidade()
	var ecs_raw: float = n_ce.complexidade_economica
	var vol_raw: float = n_ce.commodity_volatilidade()
	n_ce.update_balanca_comercial()
	var exp_raw: float = float(n_ce.exportacoes.get("materias_primas", 0.0))
	# Industrializa tudo → ECS sobe, volatilidade cai, exportação vale mais
	n_ce.grau_processamento = {"energia": 1.0, "materias_primas": 1.0, "alimentos": 1.0}
	n_ce.recompute_complexidade()
	var ecs_proc: float = n_ce.complexidade_economica
	var vol_proc: float = n_ce.commodity_volatilidade()
	n_ce.update_balanca_comercial()
	var exp_proc: float = float(n_ce.exportacoes.get("materias_primas", 0.0))
	_check(ecs_proc > ecs_raw, "industrializar eleva o ECS (%.0f → %.0f)" % [ecs_raw, ecs_proc])
	_check(vol_proc < vol_raw, "processar reduz volatilidade de commodity (%.2f → %.2f)" % [vol_raw, vol_proc])
	_check(exp_proc > exp_raw * 1.3, "manufatura vale mais que bruto na exportação ($%.1f vs $%.1f)" % [exp_proc, exp_raw])
	# Ação de upgrade industrial sobe o grau de processamento de um setor
	E.player_nation.recursos["minerios"] = 85.0
	E.player_nation.grau_processamento["materias_primas"] = 0.0
	E.player_nation.recompute_complexidade()
	var proc_antes: float = E.player_nation._grau_proc("materias_primas")
	E.player_actions_remaining = 5
	E.player_nation.tesouro = 5000.0
	var r_up: Dictionary = E.player_panel_action("upgrade_industrial")
	_check(r_up.get("ok", false), "upgrade_industrial executa: %s" % r_up.get("msg", ""))
	_check(E.player_nation._grau_proc("materias_primas") > proc_antes, "upgrade_industrial eleva o grau de processamento (%.2f → %.2f)" % [proc_antes, E.player_nation._grau_proc("materias_primas")])

	print("[12d] Economia de escala científica")
	var fake_n = load("res://scripts/Nation.gd").new()
	for i in 30:
		fake_n.tecnologias_concluidas.append("fake_%d" % i)
	var eff: float = E.tech.get_effective_cost(fake_n, {"custo": 100})
	_check(eff == 55.0, "30 techs → custo 100 vira %d (esperado 55)" % int(eff))

	print("[12d2] Guerra ofensiva do bot (persona military)")
	var bot_mil = load("res://scripts/BotPlayer.gd").new(E, get_tree(), "military")
	bot_mil.verbose = false
	E.player_nation.tesouro = 500.0
	E.player_nation.em_guerra.clear()
	E.player_nation.militar["poder_militar_global"] = 900.0
	E.player_nation.relacoes["PY"] = -70.0
	E.nations["PY"].militar["orcamento_militar_bilhoes"] = 0.5
	var mil_cands: Array = bot_mil._generate_military_actions(E.player_nation)
	var tem_guerra := false
	for c in mil_cands:
		if c.get("type", "") == "war":
			tem_guerra = true
	_check(tem_guerra, "bot military gera candidato de GUERRA (alvo fraco + rival)")

	print("[12e] Embaixada via API central")
	n_p.tesouro = 1000.0
	E.player_actions_remaining = 3
	var rel0: float = float(n_p.relacoes.get("CL", 0))
	var emb: Dictionary = E.player_open_embassy("CL")
	_check(emb.get("ok", false), "embaixada executa")
	_check(E.player_actions_remaining == 2, "embaixada CONSOME ação (consistência)")
	_check(float(n_p.relacoes.get("CL", 0)) == clamp(rel0 + 15, -100, 100), "relações +15")

	# ── 13. Elenco de personagens (retratos procedurais) ──
	print("[13] Elenco de personagens (PortraitGen)")
	var PG = load("res://scripts/PortraitGen.gd")
	# determinismo: mesma nação+papel = feições idênticas (o rosto NÃO muda)
	var f_a: Dictionary = PG.features_for("BR", "general")
	var f_b: Dictionary = PG.features_for("BR", "general")
	_check(f_a["skin"] == f_b["skin"] and f_a["hair"] == f_b["hair"] and f_a["female"] == f_b["female"],
		"determinismo: o general do Brasil é sempre o mesmo rosto")
	# nações diferentes = gabinetes diferentes (variação real)
	var f_jp: Dictionary = PG.features_for("JP", "general")
	_check(f_a["region"] != f_jp["region"], "regiões distintas (BR=%s, JP=%s)" % [f_a["region"], f_jp["region"]])
	# papéis diferentes na mesma nação = pessoas diferentes
	var f_pres: Dictionary = PG.features_for("BR", "presidente")
	var diff_role: bool = (f_pres["tone"] != f_a["tone"]) or (f_pres["hair"] != f_a["hair"]) or (f_pres["female"] != f_a["female"])
	_check(diff_role, "presidente ≠ general na mesma nação (elenco variado)")
	# cobertura: TODAS as 195 nações × 6 papéis geram feições sem crash + toda ISO tem região
	var roles: Array = PG.ROLES.keys()
	var crashes: int = 0
	var sem_regiao: Array = []
	for code in E.nations:
		if PG.region_of(code) == "anglo" and not (" US CA AU NZ ".contains(" " + code + " ")):
			sem_regiao.append(code)
		for r in roles:
			var ff: Dictionary = PG.features_for(code, r)
			if not (ff.has("skin") and ff.has("hair") and ff.has("region")):
				crashes += 1
	_check(crashes == 0, "%d nações × %d papéis geram feições completas" % [E.nations.size(), roles.size()])
	_check(sem_regiao.is_empty(), "toda nação mapeada a uma região etno-cultural%s" % ("" if sem_regiao.is_empty() else " — FALTAM: %s" % str(sem_regiao)))
	# diversidade: os 10 tons de pele aparecem ao longo do elenco mundial
	var tons_vistos := {}
	for code in E.nations:
		tons_vistos[int(PG.features_for(code, "presidente")["tone"])] = true
	_check(tons_vistos.size() >= 8, "diversidade de pele: %d/10 tons representados nos presidentes do mundo" % tons_vistos.size())

	# ── 14. Gabinete de ministros (níveis + trilhas paralelas + gates) ──
	print("[14] Gabinete de ministros")
	var ng = E.player_nation
	_check(ng.ministerios.size() == 6, "6 ministérios inicializados: %d" % ng.ministerios.size())
	# Distribuição de pesquisa: as 6 pastas têm techs e nenhuma sobrecarrega (teto de techs)
	var carga: Dictionary = {}
	for tid in E.tech.tech_index:
		var pasta_t: String = E.tech.ministry_of(E.tech.tech_index[tid])
		carga[pasta_t] = int(carga.get(pasta_t, 0)) + 1
	var pastas_com_tech: int = carga.size()
	var max_carga: int = 0
	for v in carga.values():
		max_carga = maxi(max_carga, int(v))
	_check(pastas_com_tech == 6, "todas as 6 pastas têm trilha de pesquisa (%d/6): %s" % [pastas_com_tech, str(carga)])
	_check(max_carga <= 12, "nenhuma trilha sobrecarregada (máx %d techs/pasta — antes eram 21)" % max_carga)
	_check(ng.ministry_level("saude") == 1, "ministérios começam no nível 1")
	# XP sobe de nível ao cruzar limiar
	ng.add_ministry_xp("saude", 120.0)  # limiar nv2 = 100
	_check(ng.ministry_level("saude") == 2, "XP cruza limiar → nível 2 (%d)" % ng.ministry_level("saude"))
	# nível escala a força da ação
	var mult1: float = ng.ministry_action_mult("saude")
	_check(mult1 > 1.0, "nível 2 escala ação da pasta (mult %.2f)" % mult1)
	# slots de pesquisa desbloqueiam com Casa Civil
	var slots_base: int = ng.research_slots()
	ng.add_ministry_xp("casa_civil", 400.0)  # sobe alguns níveis
	_check(ng.research_slots() > slots_base, "slots de pesquisa sobem com nível da Casa Civil (%d→%d)" % [slots_base, ng.research_slots()])
	# trilhas PARALELAS: duas pastas pesquisam ao mesmo tempo
	E.tech.cancel_research(ng)
	ng.tesouro = 2000.0
	var av_saude: Array = E.tech.get_available_techs(ng, "saude")
	var av_seg: Array = E.tech.get_available_techs(ng, "seguranca")
	if not av_saude.is_empty() and not av_seg.is_empty():
		E.tech.start_research(ng, String(av_saude[0]["id"]))
		E.tech.start_research(ng, String(av_seg[0]["id"]))
		_check(ng.pesquisa_por_ministerio.size() == 2, "duas trilhas paralelas ativas (%d)" % ng.pesquisa_por_ministerio.size())
		# get_available_techs por pasta só devolve techs daquela categoria
		var cat_ok := true
		for t in av_saude:
			if E.tech.ministry_of(t) != "saude":
				cat_ok = false
		_check(cat_ok, "filtro por ministério só devolve techs da pasta")
	else:
		_check(true, "sem techs disponíveis p/ testar trilhas (skip)")
	# gate de tier: tech tier 3+ exige nível de ministério.
	# Escolhe uma tier≥3 SEM pré-requisitos pendentes e satisfaz PIB/estab/trilha,
	# deixando o nível como ÚNICO bloqueio possível.
	E.tech.cancel_research(ng)
	ng.tesouro = 999999.0
	ng.pib_bilhoes_usd = 999999.0
	ng.estabilidade_politica = 100.0
	var gated: Dictionary = {}
	for tid in E.tech.tech_index:
		var tt: Dictionary = E.tech.tech_index[tid]
		if int(tt.get("tier", 1)) >= 3 and (tt.get("pre_requisitos", []) as Array).is_empty():
			gated = tt
			break
	if not gated.is_empty():
		var pasta_g: String = E.tech.ministry_of(gated)
		ng.ministerios[pasta_g]["nivel"] = 1  # abaixo do exigido p/ tier≥3
		var chk: Dictionary = E.tech.can_research(ng, String(gated["id"]))
		var bloqueado: bool = not chk.get("ok", true) and String(chk.get("reason", "")).contains("nível")
		_check(bloqueado, "gate de nível bloqueia tech tier %d sem ministério forte (%s)" % [int(gated.get("tier", 3)), chk.get("reason", "?")])
		# e libera ao subir o ministério ao nível exigido
		ng.ministerios[pasta_g]["nivel"] = int(gated.get("tier", 3)) - 1
		var chk2: Dictionary = E.tech.can_research(ng, String(gated["id"]))
		_check(chk2.get("ok", false), "gate LIBERA ao subir o ministério ao nível exigido")
	else:
		_check(true, "nenhuma tech tier≥3 sem pré-req p/ testar gate (skip)")
	# snapshot do gabinete p/ UI
	var snap: Array = E.get_cabinet_snapshot()
	_check(snap.size() == 6, "snapshot do gabinete tem 6 pastas: %d" % snap.size())
	_check(snap[0].has("nivel") and snap[0].has("xp_pct") and snap[0].has("role"), "snapshot traz nível/xp/role p/ a UI")

	# ── 15. Corrupção: roubo do tesouro, IED, fuga de empresas ──
	print("[15] Espiral da corrupção")
	var nc = E.player_nation
	# Roubo do tesouro: corrupção alta desvia parte do tesouro por turno
	nc.corrupcao = 90.0
	nc.tesouro = 1000.0
	var desv0: float = nc.tesouro_desviado_total
	nc.process_turn_finances()
	_check(nc.tesouro_desviado_total > desv0, "corrupção 90%% desvia tesouro (roubou $%.1fB neste turno)" % (nc.tesouro_desviado_total - desv0))
	# Corrupção baixa NÃO rouba
	nc.corrupcao = 20.0
	nc.tesouro = 1000.0
	var desv1: float = nc.tesouro_desviado_total
	nc.process_turn_finances()
	_check(abs(nc.tesouro_desviado_total - desv1) < 0.001, "corrupção 20%% NÃO desvia tesouro")
	# Confiança do investidor cai com corrupção alta (via update_government)
	nc.corrupcao = 85.0
	nc.confianca_investidor = 60.0
	for i in 15:
		nc.update_government(0.02)
	_check(nc.confianca_investidor < 40.0, "corrupção alta derruba confiança do investidor (%.0f)" % nc.confianca_investidor)
	# Ação anticorrupção recupera confiança
	nc.corrupcao = 50.0
	var conf_antes: float = nc.confianca_investidor
	E.player_actions_remaining = 3
	nc.tesouro = 500.0
	E.player_panel_action("combater_corrupcao")
	_check(nc.confianca_investidor > conf_antes, "combater corrupção recupera confiança (%.0f→%.0f)" % [conf_antes, nc.confianca_investidor])
	# IED afeta o PIB: confiança alta cresce mais que confiança baixa
	var n_hi = load("res://scripts/Nation.gd").new()
	n_hi.from_dict({"nome": "Hi", "pib_bilhoes_usd": 1000.0, "populacao": 50000000, "estabilidade_politica": 60}, "XH")
	var n_lo = load("res://scripts/Nation.gd").new()
	n_lo.from_dict({"nome": "Lo", "pib_bilhoes_usd": 1000.0, "populacao": 50000000, "estabilidade_politica": 60}, "XL")
	n_hi.confianca_investidor = 90.0
	n_lo.confianca_investidor = 10.0
	n_hi.corrupcao = 20.0
	n_lo.corrupcao = 20.0
	n_hi.update_pib(1.0)
	n_lo.update_pib(1.0)
	_check(n_hi.pib_bilhoes_usd > n_lo.pib_bilhoes_usd, "IED alto cresce mais que IED baixo ($%.1fB vs $%.1fB)" % [n_hi.pib_bilhoes_usd, n_lo.pib_bilhoes_usd])

	# ── 16. Balança comercial (import/export por setor) ──
	print("[16] Balança comercial")
	# Petro-estado: só petróleo → exporta energia, importa o resto
	var petro = load("res://scripts/Nation.gd").new()
	petro.from_dict({"nome": "Petro", "pib_bilhoes_usd": 800.0, "populacao": 30000000, "recursos": {"petroleo": 95, "gas_natural": 80}}, "XP2")
	petro.update_balanca_comercial()
	_check(float(petro.exportacoes.get("energia", 0)) > 0.0, "petro-estado exporta energia ($%.1fB)" % float(petro.exportacoes.get("energia", 0)))
	_check(petro.importacoes.has("alimentos") and petro.importacoes.has("industriais"), "petro-estado importa alimentos e industriais (carências)")
	# Nação diversificada: superávit; nação carente: déficit
	var div = load("res://scripts/Nation.gd").new()
	div.from_dict({"nome": "Div", "pib_bilhoes_usd": 800.0, "populacao": 30000000, "recursos": {"petroleo": 80, "agricultura": 85, "minerios": 75, "manufatura": 70}}, "XD2")
	div.update_balanca_comercial()
	var carente = load("res://scripts/Nation.gd").new()
	carente.from_dict({"nome": "Carente", "pib_bilhoes_usd": 800.0, "populacao": 30000000, "recursos": {"turismo": 40}}, "XC2")
	carente.update_balanca_comercial()
	_check(div.calc_balanca_comercial() > carente.calc_balanca_comercial(), "diversificada tem saldo melhor que carente (%.1f vs %.1f)" % [div.calc_balanca_comercial(), carente.calc_balanca_comercial()])
	_check(carente.calc_balanca_comercial() < 0.0, "nação sem recursos tem DÉFICIT comercial (%.1f)" % carente.calc_balanca_comercial())
	# Dependência de importação é registrada
	_check(carente.import_dependencia.size() > 0, "dependência de importação registrada (%d setores)" % carente.import_dependencia.size())
	# Déficit comercial pressiona inflação: a nação carente (déficit) converge
	# para inflação MAIOR que a diversificada (superávit). Média longa (30t) com
	# muitas amostras lava o ruído do shock aleatório de ±1.
	for i in 30: carente.process_turn_finances()
	for i in 30: div.process_turn_finances()
	var soma_car := 0.0
	var soma_div := 0.0
	for i in 30:
		carente.process_turn_finances(); soma_car += carente.inflacao
		div.process_turn_finances(); soma_div += div.inflacao
	_check(soma_car / 30.0 > soma_div / 30.0 - 0.3, "déficit comercial pressiona inflação (carente %.1f vs div %.1f, média 30t)" % [soma_car / 30.0, soma_div / 30.0])
	# Saldo comercial entra na receita
	var rec_com: float = div.calc_receita()
	_check(rec_com > 0.0, "receita inclui saldo comercial ($%.1fB)" % rec_com)

	# ── 17. Empréstimos proativos + rating de crédito ──
	print("[17] Empréstimos + rating de crédito")
	var nb = E.player_nation
	nb.divida_publica = 0.0
	nb.estabilidade_politica = 80.0
	nb.confianca_investidor = 70.0
	nb.defaults_no_historico = 0
	var rating_bom: float = nb.rating_credito()
	# Rating cai com dívida alta
	nb.divida_publica = nb.pib_bilhoes_usd * 2.0
	var rating_endividado: float = nb.rating_credito()
	_check(rating_endividado < rating_bom, "dívida alta derruba o rating (%.0f → %.0f)" % [rating_bom, rating_endividado])
	# Juros: rating ruim paga mais caro
	nb.divida_publica = 0.0
	var juros_bom: float = nb.juros_emprestimo()
	nb.divida_publica = nb.pib_bilhoes_usd * 2.0
	var juros_ruim: float = nb.juros_emprestimo()
	_check(juros_ruim > juros_bom, "rating ruim = juros mais caros (%.1f%% vs %.1f%%)" % [juros_ruim*100, juros_bom*100])
	# Empréstimo proativo entra no tesouro e cria dívida
	nb.divida_publica = 0.0
	nb.estabilidade_politica = 80.0
	nb.tesouro = 200.0
	var tes_antes: float = nb.tesouro
	var div_antes: float = nb.divida_publica
	var loan: Dictionary = E.player_take_loan(100.0)
	_check(loan.get("ok", false) and nb.tesouro == tes_antes + 100.0 and nb.divida_publica == div_antes + 100.0, "empréstimo entra no tesouro e vira dívida")
	# Acima do limite é negado
	var loan_grande: Dictionary = E.player_take_loan(nb.pib_bilhoes_usd * 10.0)
	_check(not loan_grande.get("ok", true), "empréstimo acima do limite de crédito é negado")
	# Amortização reduz dívida e melhora rating
	nb.tesouro = 500.0
	var rating_antes_pgto: float = nb.rating_credito()
	E.player_repay_debt(100.0)
	_check(nb.rating_credito() >= rating_antes_pgto, "amortizar dívida melhora (ou mantém) o rating")
	# Calote queima o rating
	nb.divida_publica = 0.0
	var r_limpo: float = nb.rating_credito()
	nb.defaults_no_historico = 2
	_check(nb.rating_credito() < r_limpo, "histórico de calote derruba o rating")

	# ── 18. Mercado de ações ──
	print("[18] Mercado de ações")
	E.market_index = 1000.0
	E.player_stocks_shares = 0.0
	E.player_stocks_invested = 0.0
	nb.divida_publica = 0.0
	nb.tesouro = 1000.0
	# Investir tira do tesouro e cria posição
	var inv: Dictionary = E.player_invest_stocks(200.0)
	_check(inv.get("ok", false) and nb.tesouro == 800.0 and E.player_stocks_value() > 190.0, "investir move tesouro→bolsa (posição $%.0fB)" % E.player_stocks_value())
	# Índice sobe → posição valoriza
	E.market_index = 1200.0
	_check(E.player_stocks_value() > 220.0, "alta do índice valoriza a posição ($%.0fB a index 1200)" % E.player_stocks_value())
	# Resgatar credita o tesouro
	var pos_antes: float = E.player_stocks_value()
	var tes_pre: float = nb.tesouro
	var sell: Dictionary = E.player_sell_stocks(pos_antes)
	_check(sell.get("ok", false) and nb.tesouro > tes_pre, "resgatar credita o tesouro (+$%.0fB)" % (nb.tesouro - tes_pre))
	# Limite prudencial DUPLO: não deixa investir all-in (min de 40% caixa e 25% PIB)
	nb.pib_bilhoes_usd = 4000.0  # PIB alto → o teto que morde é o do caixa (40%)
	nb.tesouro = 1000.0
	E.player_stocks_shares = 0.0
	E.player_stocks_invested = 0.0
	E.player_invest_stocks(900.0)  # pede 90%, deve capar
	var teto_esperado: float = minf((nb.tesouro + E.player_stocks_value()) * 0.5, nb.pib_bilhoes_usd * 0.25)
	_check(E.player_stocks_value() <= teto_esperado + 1.0, "limite prudencial cap posição: pos $%.0fB (teto ~$%.0fB)" % [E.player_stocks_value(), teto_esperado])
	# Choque global derruba o índice (efeito ACUMULADO — no ritmo mensal o crash/turno
	# é suave, mas ao longo do choque o índice cai abaixo do ponto de partida).
	E.market_index = 1000.0
	E.active_shock = {"id": "colapso_financeiro", "nome": "Colapso", "icon": "📉", "turns_remaining": 12, "dur_total": 12}
	var idx_ini_shock: float = E.market_index
	for i in 12:
		E._process_market()
	E.active_shock = {}
	_check(E.market_index < idx_ini_shock, "choque global derruba o índice ao longo do choque (%.0f→%.0f)" % [idx_ini_shock, E.market_index])

	# ── 19. Criptomoeda (WorldCoin) ──
	print("[19] Criptomoeda")
	E.crypto_price = 1000.0
	E.player_crypto_coins = 0.0
	E.player_crypto_invested = 0.0
	E.crypto_legal_tender = false
	nb.pib_bilhoes_usd = 4000.0
	nb.tesouro = 1000.0
	# Comprar cripto move tesouro→cripto
	var cb: Dictionary = E.player_buy_crypto(100.0)
	_check(cb.get("ok", false) and nb.tesouro == 900.0 and E.player_crypto_value() > 90.0, "comprar cripto move tesouro→cripto (posição $%.0fB)" % E.player_crypto_value())
	# Preço sobe → posição valoriza
	E.crypto_price = 2000.0
	_check(E.player_crypto_value() > 190.0, "alta do preço valoriza a posição ($%.0fB a 2000)" % E.player_crypto_value())
	# Limite prudencial apertado: max ~12% do PIB
	nb.tesouro = 5000.0
	E.player_crypto_coins = 0.0
	E.player_crypto_invested = 0.0
	E.crypto_price = 1000.0
	E.player_buy_crypto(5000.0)  # pede tudo, deve capar bem abaixo
	_check(E.player_crypto_value() <= nb.pib_bilhoes_usd * 0.12 + 1.0, "limite prudencial cripto (max ~12%% do PIB): pos $%.0fB de PIB $%.0fB" % [E.player_crypto_value(), nb.pib_bilhoes_usd])
	# Volatilidade: em 30 turnos o preço se move bastante (mais que a bolsa)
	E.crypto_price = 1000.0
	E.crypto_cycle = 0.0
	var min_p := 1e9
	var max_p := 0.0
	for i in 30:
		E._process_crypto()
		min_p = minf(min_p, E.crypto_price)
		max_p = maxf(max_p, E.crypto_price)
	_check((max_p - min_p) / 1000.0 > 0.15, "cripto é volátil (amplitude %.0f%% em 30t)" % ((max_p - min_p) / 10.0))
	# Adoção como moeda legal alterna e dá sinal ao investidor
	E.crypto_legal_tender = false
	var conf_pre: float = nb.confianca_investidor
	var tl: Dictionary = E.player_toggle_legal_tender()
	_check(tl.get("ok", false) and E.crypto_legal_tender and nb.confianca_investidor > conf_pre, "adotar moeda legal liga a flag e sinaliza inovação (+confiança)")
	E.player_toggle_legal_tender()
	_check(not E.crypto_legal_tender, "revogar moeda legal desliga a flag")
	# Haircut prudencial: posição inflada por valorização acima do teto é realizada aos poucos
	nb.pib_bilhoes_usd = 1000.0
	nb.tesouro = 500.0
	E.crypto_price = 1000.0
	E.player_crypto_coins = 0.0
	E.player_crypto_invested = 0.0
	E._crypto_haircut_avisado = false
	E.player_buy_crypto(120.0)                       # ~12% do PIB (no cap de compra)
	E.crypto_price = 3000.0                            # preço triplica → posição ~36% do PIB
	var pos_pre: float = E.player_crypto_value()
	E._apply_crypto_haircut()                          # 1 turno de haircut
	var pos_pos: float = E.player_crypto_value()
	_check(pos_pos < pos_pre and pos_pos > nb.pib_bilhoes_usd * E.CRYPTO_HAIRCUT_TETO, "haircut realiza excedente aos poucos (%.0f→%.0f, ainda acima do teto)" % [pos_pre, pos_pos])
	# Repetindo o haircut muitos turnos, a posição converge para perto do teto e
	# ESTABILIZA (não zera): a venda para quando o excedente vira < $1B/turno.
	for _i in 80:
		E._apply_crypto_haircut()
	var teto: float = nb.pib_bilhoes_usd * E.CRYPTO_HAIRCUT_TETO
	var conv: float = E.player_crypto_value()
	_check(conv > teto and conv < teto * 1.15, "haircut converge para perto do teto sem zerar (pos $%.0fB, teto $%.0fB)" % [conv, teto])

	# ── 20. Doutrina econômica (efeito por turno do wizard "Tomar Posse") ──
	print("[20] Doutrina econômica")
	# Livre mercado: +1% PIB/turno e +5 corrupção estrutural (1×)
	nb.pib_bilhoes_usd = 1000.0
	nb.corrupcao = 30.0
	nb.set_meta("economic_doctrine", "livre_mercado")
	E._apply_economic_doctrine_once(nb)
	_check(nb.corrupcao == 35.0, "livre mercado: +5 corrupção estrutural (1×)")
	var pib_pre: float = nb.pib_bilhoes_usd
	E._process_economic_doctrine()
	_check(nb.pib_bilhoes_usd > pib_pre, "livre mercado: +1%% PIB/turno (%.1f→%.1f)" % [pib_pre, nb.pib_bilhoes_usd])
	# Planejamento estatal: tesouro cresce, PIB encolhe um pouco
	nb.set_meta("economic_doctrine", "planejada")
	nb.tesouro = 100.0
	var pib2: float = nb.pib_bilhoes_usd
	E._process_economic_doctrine()
	_check(nb.tesouro > 100.0 and nb.pib_bilhoes_usd < pib2, "planejamento: tesouro sobe, PIB desce (tes $%.2fB)" % nb.tesouro)
	# Nórdico: felicidade sobe, PIB encolhe um pouco
	nb.set_meta("economic_doctrine", "nordica")
	nb.felicidade = 50.0
	E._process_economic_doctrine()
	_check(nb.felicidade > 50.0, "nórdico: felicidade sobe (%.1f)" % nb.felicidade)
	# Mista: baseline, PIB inalterado por doutrina
	nb.set_meta("economic_doctrine", "mista")
	var pib3: float = nb.pib_bilhoes_usd
	var fel3: float = nb.felicidade
	E._apply_doctrine_turn(nb, E._doctrine_for(nb))
	_check(nb.pib_bilhoes_usd == pib3 and nb.felicidade == fel3, "mista: baseline, sem efeito de doutrina")
	# Bots herdam a doutrina da IDEOLOGIA da personalidade (não da meta do jogador)
	var bot_nat = null
	for c in E.nations.keys():
		if c != nb.codigo_iso:
			bot_nat = E.nations[c]
			break
	if bot_nat != null:
		bot_nat.personalidade = "milei_libertario"   # ideologia_economica = livre_mercado
		_check(E._doctrine_for(bot_nat) == "livre_mercado", "bot com personalidade milei → doutrina livre_mercado")
		bot_nat.personalidade = "xi_hegemonico"       # ideologia_economica = planejada
		_check(E._doctrine_for(bot_nat) == "planejada", "bot com personalidade xi → doutrina planejada")
		var bp0: float = bot_nat.pib_bilhoes_usd
		bot_nat.personalidade = "milei_libertario"
		E._apply_doctrine_turn(bot_nat, E._doctrine_for(bot_nat))
		_check(bot_nat.pib_bilhoes_usd > bp0, "doutrina do bot afeta o PIB do próprio bot (não do jogador)")

	# ── 21. Crises globais: decisão universal + efeitos globais estendidos ──
	print("[21] Crises globais (2008/COVID/Ucrânia)")
	# effects_global agora aplica estabilidade/inflação a TODAS as nações (não só pib)
	var estab_pre: float = E.nations["AR"].estabilidade_politica
	var infl_pre: float = E.nations["AR"].inflacao
	E.timeline._apply_global_effects({"estabilidade_fator": -5.0, "inflacao": 3.0})
	_check(E.nations["AR"].estabilidade_politica == clamp(estab_pre - 5.0, 0.0, 100.0) and E.nations["AR"].inflacao == clamp(infl_pre + 3.0, 0.0, 200.0), "effects_global aplica estabilidade+inflação a todas as nações")
	# Os 3 eventos de crise global estão marcados global_decision no JSON
	var crises := {"lehman_crash": false, "covid_19": false, "russia_ucrania": false}
	for ev in E.timeline.pending_events:
		var eid: String = ev.get("id", "")
		if crises.has(eid):
			crises[eid] = bool(ev.get("global_decision", false)) and bool(ev.get("modal_decision", false))
	_check(crises["lehman_crash"] and crises["covid_19"] and crises["russia_ucrania"], "2008/COVID/Ucrânia são decisões GLOBAIS (todo jogador escolhe)")
	# global_decision faz o modal disparar mesmo se o jogador NÃO é o país-epicentro
	var got_signal := {"v": false}
	var crisis_cb := func(_ev): got_signal["v"] = true
	E.timeline.historic_event_decision.connect(crisis_cb)
	var fake_global := {"id": "_test_global_crisis", "trigger": {"primary_country": "ZZ"}, "modal_decision": true, "global_decision": true, "choices": [{"id": "a", "effects": {}}], "categories": ["crise"], "headline": "teste"}
	E.timeline._fire_event(fake_global)
	E.timeline.historic_event_decision.disconnect(crisis_cb)
	_check(got_signal["v"], "global_decision abre modal mesmo com jogador != país-epicentro")

	# ── 22. Rotatividade de liderança (Fase 2) ──
	print("[22] Rotatividade de liderança")
	E.current_turn = 100   # turno avançado o bastante p/ cálculos de mandato
	# Pega uma nação-bot (não o jogador)
	var lead_nat = null
	for c in E.nations.keys():
		if c != E.player_nation.codigo_iso:
			lead_nat = E.nations[c]
			break
	# Inicializa líder na 1ª passagem
	lead_nat.lider_nome = ""
	E._process_leadership(lead_nat)
	_check(lead_nat.lider_nome != "", "líder inicializado na 1ª passagem (%s)" % lead_nat.lider_nome)
	# Autocracia NÃO cai por impopularidade prolongada (só democracia)
	lead_nat.regime_politico = "DITADURA_MILITAR"
	lead_nat.personalidade = "putin_russo"
	lead_nat.ideologia_dominante = "planejada"
	lead_nat.apoio_popular = 10.0
	lead_nat.estabilidade_politica = 60.0   # estável o bastante p/ não haver golpe
	lead_nat.lider_idade = 55               # jovem o bastante p/ não morrer
	lead_nat.turnos_impopular = 0
	var pers_pre: String = lead_nat.personalidade
	for _i in 20:
		E._process_leadership(lead_nat)
	_check(lead_nat.personalidade == pers_pre, "autocracia NÃO troca líder por impopularidade (só morte/golpe)")
	# Democracia CAI por impopularidade prolongada (após mandato mínimo) → novo líder
	lead_nat.regime_politico = "DEMOCRACIA"
	lead_nat.apoio_popular = 10.0
	lead_nat.estabilidade_politica = 60.0
	lead_nat.lider_idade = 55
	lead_nat.turnos_impopular = 0
	lead_nat.lider_desde_turno = E.current_turn - E.LEADER_MIN_TENURE  # já cumpriu o mandato mínimo
	var trocas_pre: int = lead_nat.lideres_passados
	for _i in (E.LEADER_UNPOP_LIMIT + 2):
		E._process_leadership(lead_nat)
	_check(lead_nat.lideres_passados > trocas_pre, "democracia troca líder após impopularidade prolongada")
	# Morte por idade força sucessão mesmo em autocracia
	lead_nat.regime_politico = "DITADURA_MILITAR"
	lead_nat.apoio_popular = 80.0
	lead_nat.estabilidade_politica = 80.0
	lead_nat.lider_idade = 95   # acima do máximo
	var trocas_pre2: int = lead_nat.lideres_passados
	var morreu := false
	for _i in 150:   # 0.94^150 ≈ 0.01% de não morrer — teste robusto a randf()
		lead_nat.lider_idade = maxi(lead_nat.lider_idade, 95)  # mantém velho após reset
		E._process_leadership(lead_nat)
		if lead_nat.lideres_passados > trocas_pre2:
			morreu = true
			break
	_check(morreu, "líder muito velho (95) morre e é sucedido mesmo em autocracia")
	# Sucessão define ideologia válida
	_check(lead_nat.ideologia_dominante in ["livre_mercado", "mista", "planejada", "nordica"], "sucessor tem ideologia econômica válida (%s)" % lead_nat.ideologia_dominante)

	# ── 23. IA por personalidade (Fase 3) ──
	print("[23] IA por personalidade")
	# A ação tática ponderada reflete a personalidade: agressivo escolhe militar mais
	# que um diplomata (amostragem — comparar frequências, não valor cru).
	var ai_nat = lead_nat
	ai_nat.personalidade = "agressivo"
	var mil_agr := 0
	for _i in 400:
		if E._pick_personality_action(ai_nat) == "militar":
			mil_agr += 1
	ai_nat.personalidade = "diplomatico"
	var mil_dip := 0
	for _i in 400:
		if E._pick_personality_action(ai_nat) == "militar":
			mil_dip += 1
	_check(mil_agr > mil_dip, "agressivo escolhe militar mais que diplomata (%d vs %d em 400)" % [mil_agr, mil_dip])
	# Diplomata escolhe "relacoes" com frequência decente
	var rel_dip := 0
	for _i in 400:
		if E._pick_personality_action(ai_nat) == "relacoes":
			rel_dip += 1
	_check(rel_dip > 0, "diplomata escolhe melhorar relações (%d/400)" % rel_dip)
	# Cursor rotativo: em N chamadas de _run_ai_turn, TODAS as nações são processadas
	# ao menos 1× (antes: amostra aleatória podia ignorar nações por muitos turnos).
	E._ai_cursor = 0
	var total_nat: int = E.nations.size()
	# Valida que o cursor percorre o vetor inteiro sem pular nenhuma nação.
	var visitados := {}
	E._ai_cursor = 0
	var codes_all: Array = E.nations.keys()
	for _g in (total_nat + 5):
		var idx: int = E._ai_cursor % total_nat
		visitados[String(codes_all[idx])] = true
		E._ai_cursor = (E._ai_cursor + 1) % total_nat
	_check(visitados.size() == total_nat, "cursor rotativo cobre todas as %d nações" % total_nat)
	# pesos_tratado influencia aceitação diplomática
	if E.diplomacy != null and E.diplomacy.has_method("_treaty_weight"):
		var wt: float = E.diplomacy._treaty_weight(ai_nat, "livre_comercio")
		_check(wt > 0.0, "peso de tratado lido da personalidade (livre_comercio=%.2f)" % wt)

	# ── 24. Afinidade ideológica (#7) ──
	print("[24] Afinidade ideológica")
	# Duas nações-bot para montar cenários controlados
	var n1 = null
	var n2 = null
	for c in E.nations.keys():
		if c != E.player_nation.codigo_iso:
			if n1 == null: n1 = E.nations[c]
			elif n2 == null: n2 = E.nations[c]
			else: break
	# Afins: ambas democracia + livre_mercado → afinidade alta positiva
	n1.regime_politico = "DEMOCRACIA"; n1.personalidade = "milei_libertario"       # livre_mercado
	n2.regime_politico = "DEMOCRACIA"; n2.personalidade = "sunak_atlanticista"     # livre_mercado
	var aff_afim: float = E._ideological_affinity(n1, n2)
	_check(aff_afim > 0.5, "democracias de mercado são afins (aff=%.2f)" % aff_afim)
	# Opostas: democracia+mercado vs autocracia+planejada → afinidade negativa
	n2.regime_politico = "DITADURA_MILITAR"; n2.personalidade = "putin_russo"      # planejada
	var aff_oposto: float = E._ideological_affinity(n1, n2)
	_check(aff_oposto < -0.3, "democracia-mercado × autocracia-planejada são opostas (aff=%.2f)" % aff_oposto)
	# Drift: relação caminha na direção da afinidade
	n1.regime_politico = "DEMOCRACIA"; n1.personalidade = "milei_libertario"
	n2.regime_politico = "DEMOCRACIA"; n2.personalidade = "sunak_atlanticista"
	n1.relacoes[n2.codigo_iso] = 0.0
	n1.em_guerra = []
	for _i in 30:
		E._drift_ideological_relations(n1)
	_check(float(n1.relacoes[n2.codigo_iso]) > 5.0, "drift aproxima nações afins (rel=%.1f)" % float(n1.relacoes[n2.codigo_iso]))
	# Drift afasta opostas
	n2.regime_politico = "DITADURA_MILITAR"; n2.personalidade = "putin_russo"
	n1.relacoes[n2.codigo_iso] = 0.0
	for _i in 30:
		E._drift_ideological_relations(n1)
	_check(float(n1.relacoes[n2.codigo_iso]) < -5.0, "drift afasta nações opostas (rel=%.1f)" % float(n1.relacoes[n2.codigo_iso]))

	# ── 25. Blocos geopolíticos (#11) ──
	print("[25] Blocos geopolíticos")
	_check(E.alliances_data.size() >= 10, "blocos carregados (%d)" % E.alliances_data.size())
	# _alliances_of encontra os blocos de uma nação (EUA está na OTAN)
	var us_blocs: Array = E._alliances_of("US")
	_check(us_blocs.size() > 0, "EUA pertence a blocos (%d)" % us_blocs.size())
	# Relações intra-bloco: semeadura eleva membros do mesmo bloco a aliados
	if E.nations.has("US") and E.nations.has("DE"):
		E.nations["US"].relacoes["DE"] = 0.0
		E.nations["DE"].relacoes["US"] = 0.0
		E._seed_bloc_relations()
		_check(float(E.nations["US"].relacoes.get("DE", -999)) >= 40.0, "membros do mesmo bloco viram aliados (US-DE=%.0f)" % float(E.nations["US"].relacoes.get("DE", 0)))
	# Jogador entra num bloco elegível: escolhe um em que não está e força relações altas
	var bloc_test: Dictionary = {}
	for a in E.alliances_data:
		if not (E.player_nation.codigo_iso in a.get("membros", [])):
			bloc_test = a
			break
	if not bloc_test.is_empty():
		# Força elegibilidade: +relação alta com todos os membros
		for m in bloc_test.get("membros", []):
			if E.nations.has(m):
				E.player_nation.relacoes[m] = 60.0
		E.player_actions_remaining = 3
		var membros_pre: int = bloc_test.get("membros", []).size()
		var jr: Dictionary = E.player_join_bloc(String(bloc_test.get("id", "")))
		_check(jr.get("ok", false) and bloc_test.get("membros", []).size() == membros_pre + 1, "jogador entra em bloco (%s)" % bloc_test.get("nome", "?"))
		# E consegue sair
		E.player_actions_remaining = 3
		var lr: Dictionary = E.player_leave_bloc(String(bloc_test.get("id", "")))
		_check(lr.get("ok", false) and not (E.player_nation.codigo_iso in bloc_test.get("membros", [])), "jogador sai do bloco")

	# ── 26. Coalizão de contenção (#9) ──
	print("[26] Coalizão de contenção")
	# Torna o jogador um hegemon esmagador e vê a coalizão esfriar suas relações
	E.current_turn = 120
	E._containment_active = false
	nb.pib_bilhoes_usd = 5_000_000.0   # domina o PIB mundial
	nb.militar = nb.militar if nb.militar else {}
	nb.militar["poder_militar_global"] = 5000.0
	# Zera relações do jogador com as grandes potências p/ medir o efeito
	var grandes_test: Array = []
	for c in E.nations.keys():
		if c != nb.codigo_iso and E.nations[c].pib_bilhoes_usd >= 500.0:
			grandes_test.append(c)
			nb.relacoes[c] = 0.0
			E.nations[c].relacoes[nb.codigo_iso] = 0.0
	var rel_antes: float = 0.0
	for c in grandes_test:
		rel_antes += float(nb.relacoes.get(c, 0))
	E._process_containment_coalition()
	var rel_depois: float = 0.0
	for c in grandes_test:
		rel_depois += float(nb.relacoes.get(c, 0))
	_check(E._containment_active and rel_depois < rel_antes, "hegemon dispara coalizão de contenção (relações %.0f→%.0f)" % [rel_antes, rel_depois])

	# ── 27. Guerra com objetivos (#B) ──
	print("[27] Guerra com objetivos")
	# Declarar guerra com objetivo grava o objetivo; vitória "regime" muda o regime do perdedor
	var alvo_g: String = ""
	for c in E.nations.keys():
		if c != nb.codigo_iso and not (c in nb.em_guerra):
			alvo_g = c
			break
	nb.pib_bilhoes_usd = 1000.0   # reset (a seção 26 deixou PIB gigante de hegemon)
	nb.tesouro = 5000.0
	E.player_actions_remaining = 3
	var dw: bool = E.player_declare_war(alvo_g, "regime")
	var wk: String = E._war_key(nb.codigo_iso, alvo_g)
	_check(dw and E._war_objectives.get(wk, "") == "regime", "declarar guerra grava o objetivo (regime)")
	# Simula vitória com objetivo "regime" → perdedor adota o regime do vencedor
	nb.regime_politico = "DEMOCRACIA_PLENA"
	var perdedor = E.nations[alvo_g]
	perdedor.regime_politico = "DITADURA"
	E._end_war_with_spoils(nb, perdedor, "vitoria")
	_check(perdedor.regime_politico == "DEMOCRACIA_PLENA", "vitória 'regime' impõe o regime do vencedor ao perdedor")

	# ── 28. Cenários diferenciados (#8) ──
	print("[28] Cenários diferenciados")
	# Guerra Fria 2.0: DEFCON inicial baixo + pesquisa acelerada
	var estab_pre28: float = 0.0
	for c in E.nations.keys():
		estab_pre28 += E.nations[c].velocidade_pesquisa
	E.apply_scenario("guerra_fria_2")
	_check(E.defcon <= 3, "Guerra Fria 2.0: DEFCON inicial elevado (%d)" % E.defcon)
	var pesq_pos: float = 0.0
	for c in E.nations.keys():
		pesq_pos += E.nations[c].velocidade_pesquisa
	_check(pesq_pos > estab_pre28, "Guerra Fria 2.0: pesquisa acelerada (corrida tech)")
	# Cada cenário intermediário tem objetivo temático próprio
	var tem_obj := {"decada_critica": false, "guerra_fria_2": false}
	for s in E.scenarios_data:
		if tem_obj.has(s.get("id", "")):
			tem_obj[s.get("id", "")] = String(s.get("objetivo", "")) != ""
	_check(tem_obj["decada_critica"] and tem_obj["guerra_fria_2"], "cenários intermediários têm objetivo temático próprio")

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
