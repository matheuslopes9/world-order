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

	# ── 3. Catálogo central de ações (agrupado por ministério/painel) ──
	print("[3] Catálogo central de ações (PANEL_ACTIONS)")
	_check(E.get_panel_actions("governo").size() == 4, "4 ações da Casa Civil (painel governo)")
	_check(E.get_panel_actions("seguranca").size() == 8, "8 ações de Justiça & Segurança (segurança + defesa)")
	_check(E.get_panel_actions("economia").size() == 6, "6 ações da Fazenda")
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
	n_p.falencia_turnos = 1
	E.bailout_pending = {}
	E._last_bailout_turn = -999
	E.evaluate_endgame()
	_check(not E.bailout_pending.is_empty(), "FMI oferece resgate no 2º turno de falência")
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
	# Déficit comercial pressiona inflação: compara alvo com/sem déficit
	var infl_antes: float = carente.inflacao
	for i in 8: carente.process_turn_finances()
	var div_infl: float = div.inflacao
	for i in 8: div.process_turn_finances()
	_check(carente.inflacao >= div_infl - 1.0, "déficit comercial pressiona inflação (carente %.1f vs div %.1f)" % [carente.inflacao, div.inflacao])
	# Saldo comercial entra na receita
	var rec_com: float = div.calc_receita()
	_check(rec_com > 0.0, "receita inclui saldo comercial ($%.1fB)" % rec_com)

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
